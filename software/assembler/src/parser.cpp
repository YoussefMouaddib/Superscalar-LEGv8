#include "parser.h"
#include <cstring>
#include <algorithm>

// ---------------------------------------------------------------------------
Parser::Parser(const std::vector<Token>& tokens, const std::string& filename,
               uint32_t load_addr)
    : toks_(tokens), filename_(filename), pos_(0),
      load_addr_(load_addr), pc_(load_addr) {}

// ---------------------------------------------------------------------------
// Token stream helpers
// ---------------------------------------------------------------------------
const Token& Parser::peek(int offset) const {
    size_t idx = pos_ + (size_t)offset;
    if (idx >= toks_.size()) return toks_.back(); // EOF
    return toks_[idx];
}

const Token& Parser::consume() {
    if (pos_ < toks_.size()) return toks_[pos_++];
    return toks_.back(); // EOF sentinel
}

const Token& Parser::expect(TokType t, const char* ctx) {
    const Token& tok = consume();
    if (tok.type != t)
        err_fatal({filename_.c_str(), tok.line, tok.col},
                  "expected %s while parsing %s, got '%s'",
                  [&]() -> const char* {
                      switch(t) {
                          case TokType::REG: return "register (X0-X31)";
                          case TokType::IMM: return "immediate (#value)";
                          case TokType::COMMA: return "','";
                          case TokType::LBRACKET: return "'['";
                          case TokType::RBRACKET: return "']'";
                          case TokType::LABEL_REF: return "label";
                          default: return "token";
                      }
                  }(), ctx, tok.text.c_str());
    return toks_[pos_-1];
}

bool Parser::at_end() const {
    return pos_ >= toks_.size() ||
           toks_[pos_].type == TokType::END_OF_FILE;
}

void Parser::skip_eol() {
    while (!at_end() && peek().type == TokType::END_OF_LINE)
        consume();
}

// ---------------------------------------------------------------------------
// PASS 1 — compute label addresses
// Scans token stream, tracking PC, recording LABEL_DEF entries.
// Does NOT parse operands (avoids forward-reference issues).
// ---------------------------------------------------------------------------
void Parser::pass1() {
    pc_ = load_addr_;
    size_t saved_pos = pos_;
    pos_ = 0;

    while (!at_end()) {
        const Token& tok = consume();

        if (tok.type == TokType::END_OF_LINE || tok.type == TokType::END_OF_FILE)
            continue;

        if (tok.type == TokType::LABEL_DEF) {
            syms_.define(tok.text, pc_,
                         {filename_.c_str(), tok.line, tok.col});
            continue;
        }

        if (tok.type == TokType::MNEMONIC) {
            pc_ += 4;
            // Skip rest of line (operands)
            while (!at_end() && peek().type != TokType::END_OF_LINE &&
                   peek().type != TokType::END_OF_FILE)
                consume();
            continue;
        }

        if (tok.type == TokType::DIRECTIVE) {
            if (tok.text == ".word") {
                // Skip the value token(s)
                while (!at_end() && peek().type != TokType::END_OF_LINE &&
                       peek().type != TokType::END_OF_FILE)
                    consume();
                pc_ += 4;
            } else if (tok.text == ".byte") {
                while (!at_end() && peek().type != TokType::END_OF_LINE &&
                       peek().type != TokType::END_OF_FILE)
                    consume();
                pc_ += 1;
            } else if (tok.text == ".space") {
                // .space N  — advance PC by N
                const Token& num = consume();
                if (num.type != TokType::IMM && num.type != TokType::INTEGER_LIT)
                    err_fatal({filename_.c_str(), num.line, num.col},
                              ".space requires an integer argument");
                pc_ += (uint32_t)num.ival;
            } else if (tok.text == ".align") {
                const Token& num = consume();
                uint32_t align = (uint32_t)num.ival; // power of 2
                uint32_t mask  = (1u << align) - 1;
                pc_ = (pc_ + mask) & ~mask;
            } else if (tok.text == ".ascii" || tok.text == ".asciz") {
                // Skip the string token; advance by length (+1 for .asciz null)
                const Token& s = consume();
                pc_ += (uint32_t)s.text.size();
                if (tok.text == ".asciz") pc_ += 1;
            } else {
                // .text .data .bss .global .extern — no PC change
                while (!at_end() && peek().type != TokType::END_OF_LINE &&
                       peek().type != TokType::END_OF_FILE)
                    consume();
            }
            continue;
        }

        // Anything else on a line (label refs appearing as standalone?) — skip
        while (!at_end() && peek().type != TokType::END_OF_LINE &&
               peek().type != TokType::END_OF_FILE)
            consume();
    }

    pos_ = saved_pos;
}

// ---------------------------------------------------------------------------
// PASS 2 — full parse, instruction encoding, data item emission
// ---------------------------------------------------------------------------
void Parser::pass2() {
    pc_ = load_addr_;
    pos_ = 0;

    while (!at_end()) {
        skip_eol();
        if (at_end()) break;

        const Token& tok = consume();

        if (tok.type == TokType::LABEL_DEF) {
            // Already processed in pass1; skip
            continue;
        }

        if (tok.type == TokType::MNEMONIC) {
            uint32_t inst_addr = pc_;
            Instruction inst = parse_instruction(tok);
            inst.loc = {filename_.c_str(), tok.line, tok.col};

            SectionEntry e;
            e.kind      = SectionEntry::Kind::INST;
            e.byte_addr = inst_addr;
            e.inst      = inst;
            entries_.push_back(e);
            pc_ += 4;
            continue;
        }

        if (tok.type == TokType::DIRECTIVE) {
            handle_directive(tok);
            continue;
        }

        if (tok.type == TokType::END_OF_LINE || tok.type == TokType::END_OF_FILE)
            continue;

        err_fatal({filename_.c_str(), tok.line, tok.col},
                  "unexpected token '%s' at start of line", tok.text.c_str());
    }
}

// ---------------------------------------------------------------------------
// Top-level parse()
// ---------------------------------------------------------------------------
void Parser::parse() {
    pass1();
    pass2();
}

// ---------------------------------------------------------------------------
// Branch offset resolution
// ---------------------------------------------------------------------------
int64_t Parser::resolve_branch_offset(const Token& target_tok, uint32_t current_pc) {
    SourceLoc sloc = {filename_.c_str(), target_tok.line, target_tok.col};
    uint32_t target_addr = syms_.resolve(target_tok.text, sloc);
    // PC convention: offset from current instruction address (ARM-standard)
    return (int64_t)target_addr - (int64_t)current_pc;
}

// ---------------------------------------------------------------------------
// Directive handler
// ---------------------------------------------------------------------------
void Parser::handle_directive(const Token& dir_tok) {
    const std::string& d = dir_tok.text;
    SourceLoc sloc = {filename_.c_str(), dir_tok.line, dir_tok.col};

    if (d == ".text" || d == ".data" || d == ".bss" ||
        d == ".global" || d == ".extern") {
        // Consume rest of line (symbol name etc.)
        while (!at_end() && peek().type != TokType::END_OF_LINE &&
               peek().type != TokType::END_OF_FILE)
            consume();
        return;
    }

    if (d == ".word") {
        // .word value  (decimal or hex, with or without #)
        const Token& val_tok = consume();
        int64_t val = 0;
        if (val_tok.type == TokType::IMM || val_tok.type == TokType::INTEGER_LIT)
            val = val_tok.ival;
        else if (val_tok.type == TokType::LABEL_REF)
            val = (int64_t)syms_.resolve(val_tok.text, sloc);
        else
            err_fatal(sloc, ".word expects integer or label, got '%s'",
                      val_tok.text.c_str());

        DataItem di;
        di.kind  = DataItem::Kind::WORD;
        di.value = (uint32_t)val;
        di.count = 1;
        di.loc   = sloc;

        SectionEntry e;
        e.kind      = SectionEntry::Kind::DATA;
        e.byte_addr = pc_;
        e.data      = di;
        entries_.push_back(e);
        pc_ += 4;
        return;
    }

    if (d == ".byte") {
        const Token& val_tok = consume();
        if (val_tok.type != TokType::IMM && val_tok.type != TokType::INTEGER_LIT)
            err_fatal(sloc, ".byte expects integer");
        if (val_tok.ival < -128 || val_tok.ival > 255)
            err_fatal(sloc, ".byte value %lld out of range", (long long)val_tok.ival);

        DataItem di;
        di.kind  = DataItem::Kind::BYTE;
        di.value = (uint32_t)(val_tok.ival & 0xFF);
        di.count = 1;
        di.loc   = sloc;

        SectionEntry e;
        e.kind      = SectionEntry::Kind::DATA;
        e.byte_addr = pc_;
        e.data      = di;
        entries_.push_back(e);
        pc_ += 1;
        return;
    }

    if (d == ".space") {
        const Token& num = consume();
        uint32_t count = (uint32_t)num.ival;

        DataItem di;
        di.kind  = DataItem::Kind::SPACE;
        di.value = 0;
        di.count = count;
        di.loc   = sloc;

        SectionEntry e;
        e.kind      = SectionEntry::Kind::DATA;
        e.byte_addr = pc_;
        e.data      = di;
        entries_.push_back(e);
        pc_ += count;
        return;
    }

    if (d == ".align") {
        const Token& num = consume();
        uint32_t align = (uint32_t)num.ival;
        uint32_t mask  = (1u << align) - 1;
        pc_ = (pc_ + mask) & ~mask;
        return;
    }

    // Unhandled directives: warn and skip line
    err_warning(sloc, "ignoring directive '%s'", d.c_str());
    while (!at_end() && peek().type != TokType::END_OF_LINE &&
           peek().type != TokType::END_OF_FILE)
        consume();
}

// ---------------------------------------------------------------------------
// Instruction dispatch
// ---------------------------------------------------------------------------
Instruction Parser::parse_instruction(const Token& tok) {
    const std::string& m = tok.text;

    // R-type
    if (m=="ADD"||m=="SUB"||m=="AND"||m=="ORR"||m=="EOR"||
        m=="NEG"||m=="CMP"||m=="LSL"||m=="LSR"||m=="RET")
        return parse_r_type(tok);

    // I-type
    if (m=="ADDI"||m=="SUBI"||m=="ANDI"||m=="ORI"||m=="EORI")
        return parse_i_type(tok);

    // D-type
    if (m=="LDR"||m=="STR"||m=="LDUR"||m=="STUR"||m=="CAS")
        return parse_d_type(tok);

    // B-type
    if (m=="B"||m=="BL")
        return parse_b_type(tok);

    // CB-type
    if (m=="CBZ"||m=="CBNZ")
        return parse_cb_type(tok);

    // SYS
    if (m=="SVC"||m=="NOP")
        return parse_sys_type(tok);

    err_fatal({filename_.c_str(), tok.line, tok.col},
              "unknown mnemonic '%s'", m.c_str());
    return {}; // unreachable
}

// ---------------------------------------------------------------------------
// R-type parser
//
// ADD  Xd, Xn, Xm          (rd, rn, rm)
// SUB  Xd, Xn, Xm
// AND  Xd, Xn, Xm
// ORR  Xd, Xn, Xm
// EOR  Xd, Xn, Xm
// NEG  Xd, Xn               (rd, rn; rm=0)
// CMP  Xn, Xm               (rn, rm; rd=31/XZR)
// LSL  Xd, Xn, Xm           (reg shift — Rm holds shift amount)
// LSL  Xd, Xn, #imm         (immediate shift)
// LSR  Xd, Xn, Xm / #imm
// RET  Xn                   (branch to Xn)
// ---------------------------------------------------------------------------
Instruction Parser::parse_r_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::R;
    inst.mnemonic = tok.text;
    SourceLoc sloc = {filename_.c_str(), tok.line, tok.col};

    if (tok.text == "RET") {
        // RET Xn  or  RET  (default X30)
        if (!at_end() && peek().type == TokType::REG) {
            inst.rn = (uint8_t)consume().ival;
        } else {
            inst.rn = 30; // LR
        }
        inst.rd   = 0;
        inst.rm   = 0;
        inst.func = RFunc::RET;
        return inst;
    }

    if (tok.text == "CMP") {
        // CMP Xn, Xm  — result discarded (rd=XZR)
        inst.rd = 31;
        inst.rn = (uint8_t)expect(TokType::REG, "CMP Xn").ival;
        expect(TokType::COMMA, "CMP");
        inst.rm = (uint8_t)expect(TokType::REG, "CMP Xm").ival;
        inst.func = RFunc::CMP;
        return inst;
    }

    if (tok.text == "NEG") {
        // NEG Xd, Xn  — implemented as 0 - Xn
        inst.rd = (uint8_t)expect(TokType::REG, "NEG Xd").ival;
        expect(TokType::COMMA, "NEG");
        inst.rn = (uint8_t)expect(TokType::REG, "NEG Xn").ival;
        inst.rm   = 0;
        inst.func = RFunc::NEG;
        return inst;
    }

    if (tok.text == "LSL" || tok.text == "LSR") {
        inst.rd = (uint8_t)expect(TokType::REG, "LSL/LSR Xd").ival;
        expect(TokType::COMMA, "LSL/LSR");
        inst.rn = (uint8_t)expect(TokType::REG, "LSL/LSR Xn").ival;
        expect(TokType::COMMA, "LSL/LSR");

        if (peek().type == TokType::IMM) {
            // Immediate shift
            int64_t sh = consume().ival;
            if (sh < 0 || sh > 31)
                err_fatal(sloc, "shift amount %lld out of range (0-31)", (long long)sh);
            inst.shamt = (uint8_t)sh;
            inst.rm    = 0;
            inst.func  = (tok.text == "LSL") ? RFunc::LSL_IMM : RFunc::LSR_IMM;
        } else {
            // Register shift
            inst.rm    = (uint8_t)expect(TokType::REG, "LSL/LSR Xm").ival;
            inst.shamt = 0;
            inst.func  = (tok.text == "LSL") ? RFunc::LSL_REG : RFunc::LSR_REG;
        }
        return inst;
    }

    // ADD / SUB / AND / ORR / EOR : Xd, Xn, Xm
    inst.rd = (uint8_t)expect(TokType::REG, (tok.text + " Xd").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());
    inst.rn = (uint8_t)expect(TokType::REG, (tok.text + " Xn").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());
    inst.rm = (uint8_t)expect(TokType::REG, (tok.text + " Xm").c_str()).ival;

    if      (tok.text=="ADD") inst.func = RFunc::ADD;
    else if (tok.text=="SUB") inst.func = RFunc::SUB;
    else if (tok.text=="AND") inst.func = RFunc::AND;
    else if (tok.text=="ORR") inst.func = RFunc::ORR;
    else if (tok.text=="EOR") inst.func = RFunc::EOR;

    return inst;
}

// ---------------------------------------------------------------------------
// I-type parser:  ADDI Xd, Xn, #imm
// ---------------------------------------------------------------------------
Instruction Parser::parse_i_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::I;
    inst.mnemonic = tok.text;
    inst.rd = (uint8_t)expect(TokType::REG, (tok.text + " Xd").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());
    inst.rn = (uint8_t)expect(TokType::REG, (tok.text + " Xn").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());
    inst.imm = expect(TokType::IMM, (tok.text + " #imm").c_str()).ival;
    return inst;
}

// ---------------------------------------------------------------------------
// D-type parser
//
// LDR  Xt, [Xn, #imm]
// STR  Xt, [Xn, #imm]
// LDUR Xt, [Xn, #imm]
// STUR Xt, [Xn, #imm]
// CAS  Xd, Xn, Xm      (result, address, compare_value)
// ---------------------------------------------------------------------------
Instruction Parser::parse_d_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::D;
    inst.mnemonic = tok.text;
    SourceLoc sloc = {filename_.c_str(), tok.line, tok.col};

    if (tok.text == "CAS") {
        // CAS Xd, Xn, Xm
        inst.rd = (uint8_t)expect(TokType::REG, "CAS Xd").ival;
        expect(TokType::COMMA, "CAS");
        inst.rn = (uint8_t)expect(TokType::REG, "CAS Xn (address)").ival;
        expect(TokType::COMMA, "CAS");
        inst.rm = (uint8_t)expect(TokType::REG, "CAS Xm (compare)").ival;
        return inst;
    }

    // LDR / STR / LDUR / STUR :  Xt, [Xn, #imm]
    inst.rd = (uint8_t)expect(TokType::REG, (tok.text + " Xt").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());
    expect(TokType::LBRACKET, tok.text.c_str());
    inst.rn = (uint8_t)expect(TokType::REG, (tok.text + " [Xn]").c_str()).ival;

    // Offset is optional (defaults to 0)
    if (peek().type == TokType::COMMA) {
        consume(); // eat comma
        inst.imm = expect(TokType::IMM, (tok.text + " #imm").c_str()).ival;
    } else {
        inst.imm = 0;
    }
    expect(TokType::RBRACKET, tok.text.c_str());
    return inst;
}

// ---------------------------------------------------------------------------
// B-type parser:  B label / BL label
// ---------------------------------------------------------------------------
Instruction Parser::parse_b_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::B;
    inst.mnemonic = tok.text;

    const Token& target = consume();
    if (target.type != TokType::LABEL_REF && target.type != TokType::MNEMONIC)
        err_fatal({filename_.c_str(), target.line, target.col},
                  "%s: expected branch target label, got '%s'",
                  tok.text.c_str(), target.text.c_str());

    inst.imm = resolve_branch_offset(target, pc_);
    return inst;
}

// ---------------------------------------------------------------------------
// CB-type parser:  CBZ Xt, label / CBNZ Xt, label
// ---------------------------------------------------------------------------
Instruction Parser::parse_cb_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::CB;
    inst.mnemonic = tok.text;

    inst.rd = (uint8_t)expect(TokType::REG, (tok.text + " Xt").c_str()).ival;
    expect(TokType::COMMA, tok.text.c_str());

    const Token& target = consume();
    if (target.type != TokType::LABEL_REF && target.type != TokType::MNEMONIC)
        err_fatal({filename_.c_str(), target.line, target.col},
                  "%s: expected branch target label, got '%s'",
                  tok.text.c_str(), target.text.c_str());

    inst.imm = resolve_branch_offset(target, pc_);
    return inst;
}

// ---------------------------------------------------------------------------
// SYS parser:  NOP  /  SVC #imm
// ---------------------------------------------------------------------------
Instruction Parser::parse_sys_type(const Token& tok) {
    Instruction inst;
    inst.fmt      = InstFormat::SYS;
    inst.mnemonic = tok.text;

    if (tok.text == "SVC") {
        inst.imm = expect(TokType::IMM, "SVC #imm").ival;
    }
    // NOP: no operands
    return inst;
}
