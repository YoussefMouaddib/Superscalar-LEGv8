#include "encoder.h"
#include <cstdio>

// ---------------------------------------------------------------------------
// Bit-field helpers
// ---------------------------------------------------------------------------

// Check that val fits in a signed field of 'bits' bits
static void check_signed_range(int64_t val, int bits, const char* field_name,
                                SourceLoc loc) {
    int64_t lo = -((int64_t)1 << (bits - 1));
    int64_t hi =  ((int64_t)1 << (bits - 1)) - 1;
    if (val < lo || val > hi)
        err_fatal(loc, "immediate %lld out of range for %s "
                  "(must be %lld..%lld)",
                  (long long)val, field_name, (long long)lo, (long long)hi);
}

// Check register number 0-31
static void check_reg(uint8_t r, const char* name, SourceLoc loc) {
    if (r > 31)
        err_fatal(loc, "register number %u out of range for %s", r, name);
}

// ---------------------------------------------------------------------------
// R-type
// [31:26]=000000  [25:21]=Rd  [20:16]=Rn  [15:11]=Rm  [10:6]=shamt  [5:0]=func
// ---------------------------------------------------------------------------
uint32_t encode_r(const Instruction& inst) {
    check_reg(inst.rd,    "Rd",    inst.loc);
    check_reg(inst.rn,    "Rn",    inst.loc);
    check_reg(inst.rm,    "Rm",    inst.loc);

    // SHAMT: only meaningful for LSL/LSR-imm; must be 0-31
    uint8_t shamt = inst.shamt;
    if (shamt > 31)
        err_fatal(inst.loc, "shift amount %u out of range (0-31)", shamt);

    return  ((uint32_t)Opcode::R_TYPE << 26)
          | ((uint32_t)inst.rd        << 21)
          | ((uint32_t)inst.rn        << 16)
          | ((uint32_t)inst.rm        << 11)
          | ((uint32_t)shamt          <<  6)
          | ((uint32_t)inst.func      <<  0);
}

// ---------------------------------------------------------------------------
// I-type
// [31:26]=opcode  [25:21]=Rd  [20:16]=Rn  [15:0]=imm16 (signed)
// ---------------------------------------------------------------------------
uint32_t encode_i(const Instruction& inst) {
    check_reg(inst.rd, "Rd", inst.loc);
    check_reg(inst.rn, "Rn", inst.loc);
    check_signed_range(inst.imm, 16, "imm16", inst.loc);

    uint8_t opcode = 0;
    const auto& m = inst.mnemonic;
    if      (m == "ADDI") opcode = Opcode::ADDI;
    else if (m == "SUBI") opcode = Opcode::SUBI;
    else if (m == "ANDI") opcode = Opcode::ANDI;
    else if (m == "ORI")  opcode = Opcode::ORI;
    else if (m == "EORI") opcode = Opcode::EORI;
    else err_fatal(inst.loc, "unknown I-type mnemonic '%s'", m.c_str());

    uint16_t imm16 = (uint16_t)(inst.imm & 0xFFFF);

    return  ((uint32_t)opcode  << 26)
          | ((uint32_t)inst.rd << 21)
          | ((uint32_t)inst.rn << 16)
          | ((uint32_t)imm16   <<  0);
}

// ---------------------------------------------------------------------------
// D-type  (LDR / STR / LDUR / STUR)
// [31:26]=opcode  [25:21]=Rt  [20:16]=Rn  [15:0]=imm16 (signed offset)
//
// CAS (opcode=0x14) repurposes the layout:
//   [25:21]=Rd(result)  [20:16]=Rn(addr)  [15:11]=Rm(compare)  [10:0]=0
// ---------------------------------------------------------------------------
uint32_t encode_d(const Instruction& inst) {
    uint8_t opcode = 0;
    const auto& m = inst.mnemonic;

    if      (m == "LDR")  opcode = Opcode::LDR;
    else if (m == "STR")  opcode = Opcode::STR;
    else if (m == "LDUR") opcode = Opcode::LDUR;
    else if (m == "STUR") opcode = Opcode::STUR;
    else if (m == "CAS")  opcode = Opcode::CAS;
    else err_fatal(inst.loc, "unknown D-type mnemonic '%s'", m.c_str());

    if (m == "CAS") {
        // CAS layout: Rd=result [25:21], Rn=addr [20:16], Rm=cmp [15:11], rest=0
        check_reg(inst.rd, "Rd (CAS result)", inst.loc);
        check_reg(inst.rn, "Rn (CAS address)", inst.loc);
        check_reg(inst.rm, "Rm (CAS compare value)", inst.loc);
        return  ((uint32_t)opcode   << 26)
              | ((uint32_t)inst.rd  << 21)
              | ((uint32_t)inst.rn  << 16)
              | ((uint32_t)inst.rm  << 11);
        // [10:0] = 0 implicitly
    }

    // Standard load/store
    check_reg(inst.rd, "Rt", inst.loc);
    check_reg(inst.rn, "Rn (base)", inst.loc);
    check_signed_range(inst.imm, 16, "imm16 (byte offset)", inst.loc);

    uint16_t imm16 = (uint16_t)(inst.imm & 0xFFFF);

    return  ((uint32_t)opcode   << 26)
          | ((uint32_t)inst.rd  << 21)
          | ((uint32_t)inst.rn  << 16)
          | ((uint32_t)imm16    <<  0);
}

// ---------------------------------------------------------------------------
// B-type  (B / BL)
// [31:26]=opcode  [25:0]=imm26 (signed)
// inst.imm is the BYTE offset from the current PC.
// We divide by 4 (instructions are 4 bytes) and store as signed imm26.
// PC convention: offset is relative to the address of the branch instruction.
// ---------------------------------------------------------------------------
uint32_t encode_b(const Instruction& inst) {
    if (inst.imm % 4 != 0)
        err_fatal(inst.loc, "branch target not 4-byte aligned (offset=%lld)",
                  (long long)inst.imm);

    int64_t word_offset = inst.imm / 4;
    check_signed_range(word_offset, 26, "branch imm26 (word offset)", inst.loc);

    uint8_t opcode = (inst.mnemonic == "BL") ? Opcode::BL : Opcode::B;
    uint32_t imm26 = (uint32_t)(word_offset & 0x03FFFFFF);

    return  ((uint32_t)opcode << 26)
          | imm26;
}

// ---------------------------------------------------------------------------
// CB-type  (CBZ / CBNZ)
// [31:26]=opcode  [25:21]=Rt  [20:0]=imm21 (signed)
// Same PC-relative / divide-by-4 convention as B-type.
// ★ Opcode: 0x18/0x19 (authoritative — not 0x22/0x23)
// ---------------------------------------------------------------------------
uint32_t encode_cb(const Instruction& inst) {
    if (inst.imm % 4 != 0)
        err_fatal(inst.loc, "branch target not 4-byte aligned (offset=%lld)",
                  (long long)inst.imm);

    int64_t word_offset = inst.imm / 4;
    check_signed_range(word_offset, 21, "CBZ/CBNZ imm21 (word offset)", inst.loc);

    check_reg(inst.rd, "Rt (CBZ/CBNZ)", inst.loc);  // rd == Rt here

    uint8_t opcode = (inst.mnemonic == "CBNZ") ? Opcode::CBNZ : Opcode::CBZ;
    uint32_t imm21 = (uint32_t)(word_offset & 0x001FFFFF);

    return  ((uint32_t)opcode   << 26)
          | ((uint32_t)inst.rd  << 21)
          | imm21;
}

// ---------------------------------------------------------------------------
// SYS  (NOP / SVC)
// NOP: all zeros (0x00000000) -- matches opcode 0x3F only if that encoding
//      is desired; alternatively NOP = 32'b0 is fine for decode.
//      We use all-zeros for NOP so it is safe to emit as a padding word.
// SVC: [31:26]=0x38  [25:0]=imm26 (syscall number, unsigned)
// ---------------------------------------------------------------------------
uint32_t encode_sys(const Instruction& inst) {
    if (inst.mnemonic == "NOP")
        return 0x00000000;

    if (inst.mnemonic == "SVC") {
        if (inst.imm < 0 || inst.imm > 0x03FFFFFF)
            err_fatal(inst.loc, "SVC immediate %lld out of range (0..%d)",
                      (long long)inst.imm, 0x03FFFFFF);
        return  ((uint32_t)Opcode::SVC << 26)
              | ((uint32_t)(inst.imm & 0x03FFFFFF));
    }

    err_fatal(inst.loc, "unknown SYS mnemonic '%s'", inst.mnemonic.c_str());
    return 0; // unreachable
}

// ---------------------------------------------------------------------------
// Dispatch
// ---------------------------------------------------------------------------
uint32_t encode(const Instruction& inst) {
    switch (inst.fmt) {
        case InstFormat::R:   return encode_r(inst);
        case InstFormat::I:   return encode_i(inst);
        case InstFormat::D:   return encode_d(inst);
        case InstFormat::B:   return encode_b(inst);
        case InstFormat::CB:  return encode_cb(inst);
        case InstFormat::SYS: return encode_sys(inst);
    }
    err_fatal(inst.loc, "unknown instruction format");
    return 0; // unreachable
}
