#pragma once
#include <cstdint>
#include <string>
#include "error.h"

// ---------------------------------------------------------------------------
// Instruction formats (determines which encode_* function is called)
// ---------------------------------------------------------------------------
enum class InstFormat {
    R,      // ADD/SUB/AND/ORR/EOR/LSL/LSR/NEG/RET
    I,      // ADDI/SUBI/ANDI/ORI/EORI
    D,      // LDR/STR/LDUR/STUR/CAS
    B,      // B/BL
    CB,     // CBZ/CBNZ
    SYS,    // SVC/NOP
};

// ---------------------------------------------------------------------------
// Decoded instruction (produced by parser, consumed by encoder)
// ---------------------------------------------------------------------------
struct Instruction {
    InstFormat  fmt;
    std::string mnemonic;   // upper-case, e.g. "ADD"

    // Register fields (0-31; 31 = XZR)
    uint8_t     rd  = 0;    // destination
    uint8_t     rn  = 0;    // source 1 / base address
    uint8_t     rm  = 0;    // source 2 / compare value (CAS)

    // Immediate / offset (sign-extended at parse time; encoder re-checks range)
    int64_t     imm = 0;

    // Shift amount (R-type shift-immediate variants only)
    uint8_t     shamt = 0;

    // Branch target — resolved to byte address before encoding
    // For branch instructions imm already holds the BYTE OFFSET from PC.
    // encode_* will shift right by 2 and sign-extend as needed.

    // For R-type: FUNC field (6 bits)
    uint8_t     func = 0;

    SourceLoc   loc;        // for error messages
};

// ---------------------------------------------------------------------------
// FUNC table for R-type instructions
// ---------------------------------------------------------------------------
namespace RFunc {
    constexpr uint8_t ADD  = 0b100000;
    constexpr uint8_t SUB  = 0b100010;
    constexpr uint8_t AND  = 0b100100;
    constexpr uint8_t ORR  = 0b100101;
    constexpr uint8_t EOR  = 0b100110;
    constexpr uint8_t NEG  = 0b101000;
    constexpr uint8_t CMP  = 0b101010;
    constexpr uint8_t LSL_REG = 0b000000;
    constexpr uint8_t LSR_REG = 0b000010;
    constexpr uint8_t LSL_IMM = 0b000001;
    constexpr uint8_t LSR_IMM = 0b000011;
    constexpr uint8_t RET  = 0b111000;
}

// ---------------------------------------------------------------------------
// Opcode table
// ---------------------------------------------------------------------------
namespace Opcode {
    // R-type family all share opcode 0x00; FUNC selects the operation.
    constexpr uint8_t R_TYPE = 0x00;   // 000000

    constexpr uint8_t ADDI   = 0x08;   // 001000
    constexpr uint8_t SUBI   = 0x09;   // 001001
    constexpr uint8_t ANDI   = 0x0A;   // 001010
    constexpr uint8_t ORI    = 0x0B;   // 001011
    constexpr uint8_t EORI   = 0x0C;   // 001100

    constexpr uint8_t LDR    = 0x10;   // 010000
    constexpr uint8_t STR    = 0x11;   // 010001
    constexpr uint8_t LDUR   = 0x12;   // 010010
    constexpr uint8_t STUR   = 0x13;   // 010011
    constexpr uint8_t CAS    = 0x14;   // 010100

    // ★ CBZ/CBNZ: authoritative values (011000/011001, NOT 100010/100011)
    constexpr uint8_t CBZ    = 0x18;   // 011000
    constexpr uint8_t CBNZ   = 0x19;   // 011001

    constexpr uint8_t B      = 0x20;   // 100000
    constexpr uint8_t BL     = 0x21;   // 100001

    constexpr uint8_t SVC    = 0x38;   // 111000
    constexpr uint8_t NOP    = 0x3F;   // 111111
}

// ---------------------------------------------------------------------------
// Encoding functions — each returns a 32-bit machine word.
// All range checks are fatal errors using inst.loc.
// ---------------------------------------------------------------------------

// R-type: [31:26]=0x00 [25:21]=Rd [20:16]=Rn [15:11]=Rm [10:6]=shamt [5:0]=func
uint32_t encode_r(const Instruction& inst);

// I-type: [31:26]=opcode [25:21]=Rd [20:16]=Rn [15:0]=imm16 (signed)
uint32_t encode_i(const Instruction& inst);

// D-type: [31:26]=opcode [25:21]=Rt [20:16]=Rn [15:0]=imm16 (signed offset)
// CAS reuses D-type layout: Rt=Rd(result), Rn=addr, Rm encoded in [15:11],
//   lower [10:0] zeroed.
uint32_t encode_d(const Instruction& inst);

// B-type: [31:26]=opcode [25:0]=imm26 (signed, already in bytes; encoder >>2)
uint32_t encode_b(const Instruction& inst);

// CB-type: [31:26]=opcode [25:21]=Rt [20:0]=imm21 (signed bytes; encoder >>2)
uint32_t encode_cb(const Instruction& inst);

// SYS: NOP = all-zeros; SVC = opcode | imm26
uint32_t encode_sys(const Instruction& inst);

// Dispatch: calls the right encode_* based on inst.fmt
uint32_t encode(const Instruction& inst);
