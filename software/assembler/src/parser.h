#pragma once
#include <vector>
#include <string>
#include "lexer.h"
#include "encoder.h"
#include "symbol_table.h"

// ---------------------------------------------------------------------------
// DataItem — produced by .word / .byte / .space directives
// ---------------------------------------------------------------------------
struct DataItem {
    enum class Kind { WORD, BYTE, SPACE } kind;
    uint32_t    value;      // for WORD/BYTE
    uint32_t    count;      // for SPACE (count bytes of 0)
    SourceLoc   loc;
};

// ---------------------------------------------------------------------------
// Section entry — either an instruction or a data item
// ---------------------------------------------------------------------------
struct SectionEntry {
    enum class Kind { INST, DATA } kind;
    uint32_t    byte_addr;  // address of this entry

    // Valid when kind==INST
    Instruction inst;

    // Valid when kind==DATA
    DataItem    data;
};

// ---------------------------------------------------------------------------
// Parser
//
// Usage:
//   Parser p(tokens, filename);
//   p.parse();           // two-pass
//   auto& entries = p.entries();   // ordered list of instructions + data
//   auto& syms    = p.symbols();   // fully resolved symbol table
// ---------------------------------------------------------------------------
class Parser {
public:
    Parser(const std::vector<Token>& tokens, const std::string& filename,
           uint32_t load_addr = 0x00000000);

    void parse();   // run both passes; fatal on error

    const std::vector<SectionEntry>& entries() const { return entries_; }
    const SymbolTable& symbols() const { return syms_; }

private:
    // Pass 1: scan for LABEL_DEF and compute addresses
    void pass1();
    // Pass 2: parse instructions and resolve branches
    void pass2();

    // -----------------------------------------------------------------------
    // Token stream helpers
    // -----------------------------------------------------------------------
    const Token& peek(int offset = 0) const;
    const Token& consume();
    const Token& expect(TokType t, const char* ctx);
    bool at_end() const;

    // Skip END_OF_LINE tokens
    void skip_eol();

    // -----------------------------------------------------------------------
    // Instruction parsers (called from pass2)
    // -----------------------------------------------------------------------
    Instruction parse_instruction(const Token& mnemonic_tok);
    Instruction parse_r_type(const Token& tok);
    Instruction parse_i_type(const Token& tok);
    Instruction parse_d_type(const Token& tok);
    Instruction parse_b_type(const Token& tok);
    Instruction parse_cb_type(const Token& tok);
    Instruction parse_sys_type(const Token& tok);

    // Directive handler (called from pass2 to emit data items)
    void handle_directive(const Token& dir_tok);

    // Resolve a branch target: returns signed byte offset from current PC
    int64_t resolve_branch_offset(const Token& target_tok, uint32_t current_pc);

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    const std::vector<Token>& toks_;
    std::string     filename_;
    size_t          pos_;           // current position in toks_
    uint32_t        load_addr_;     // base address of .text section
    uint32_t        pc_;            // current byte address
    SymbolTable     syms_;
    std::vector<SectionEntry> entries_;

    SourceLoc loc() const {
        if (pos_ < toks_.size())
            return {filename_.c_str(), toks_[pos_].line, toks_[pos_].col};
        return {filename_.c_str(), 0, 0};
    }
};
