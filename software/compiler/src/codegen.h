#pragma once
#include <string>
#include <vector>
#include <unordered_map>
#include <ostream>
#include "ast.h"

// ---------------------------------------------------------------------------
// ABI constants (locked)
// ---------------------------------------------------------------------------
// Argument registers:  X0-X5
// Return value:        X0
// Caller-saved:        X0-X15
// Callee-saved:        X16-X27
// Stack pointer:       X28  (SP, grows down, 8-byte aligned)
// Frame pointer:       X29  (FP)
// Link register:       X30  (LR)
// Scratch (compiler):  X27  (used for shift amounts — callee-saved so safe)
//
// Stack frame layout (grows downward from FP):
//   [FP + 0]   = saved FP (caller's frame pointer)
//   [FP - 4]   = saved LR (return address)
//   [FP - 8]   = local var 0
//   [FP - 12]  = local var 1
//   ...
// ---------------------------------------------------------------------------

struct LocalVar {
    std::string name;
    int         fp_offset;  // negative: FP + fp_offset = address
    bool        is_pointer;
};

struct FuncContext {
    std::string              name;
    std::vector<LocalVar>    locals;    // includes params
    int                      frame_size; // total bytes allocated (rounded up to 8)
    int                      next_offset; // next available offset from FP (starts at -8)
};

class CodeGen {
public:
    CodeGen(std::ostream& out);

    void emit_translation_unit(const TranslationUnit& tu);

private:
    std::ostream& out_;
    int           label_counter_ = 0;
    FuncContext*  cur_func_       = nullptr;

    // ── Label generation ──────────────────────────────────────────────────
    std::string new_label(const std::string& prefix = ".L");

    // ── Emission helpers ──────────────────────────────────────────────────
    void emit(const std::string& line);
    void emit_label(const std::string& label);
    void emit_comment(const std::string& msg);

    // ── Stack-machine expression helpers ─────────────────────────────────
    void push_expr();                      // push X0 onto expression stack
    void pop_expr(const std::string& reg); // pop from expression stack into reg

    // ── Load a 32-bit constant into a register ────────────────────────────
    // Since we have no MOV-immediate > 16-bit, we use ADDI + shift sequences
    void emit_load_const(const std::string& reg, int64_t val);

    // ── Shift by immediate (hardware only supports reg-shift) ─────────────
    // Uses X27 as scratch for the shift amount
    void emit_shift_left_imm(const std::string& dst, const std::string& src, int amount);
    void emit_shift_right_imm(const std::string& dst, const std::string& src, int amount);

    // ── Software multiply (shift-and-add) ─────────────────────────────────
    void emit_multiply(const std::string& dst,
                       const std::string& lhs, const std::string& rhs);

    // ── Stack frame management ────────────────────────────────────────────
    void emit_prologue(const FuncDecl& fn);
    void emit_epilogue();

    // ── Variable lookup ───────────────────────────────────────────────────
    // Returns the FP offset of a named variable (-8, -12, ...)
    const LocalVar* find_local(const std::string& name) const;
    LocalVar* alloc_local(const std::string& name, bool is_ptr);

    // ── Code generation — statements ──────────────────────────────────────
    void gen_func(const FuncDecl& fn);
    void gen_stmt(const Stmt& s);
    void gen_block(const Stmt& s);
    void gen_var_decl(const Stmt& s);
    void gen_if(const Stmt& s);
    void gen_while(const Stmt& s);
    void gen_for(const Stmt& s);
    void gen_return(const Stmt& s);

    // ── Code generation — expressions ─────────────────────────────────────
    // Each expression evaluates into X0 (result register)
    void gen_expr(const Expr& e);
    void gen_intlit(const Expr& e);
    void gen_var(const Expr& e);
    void gen_assign(const Expr& e);
    void gen_binary(const Expr& e);
    void gen_unary(const Expr& e);
    void gen_call(const Expr& e);
    void gen_index(const Expr& e);

    // ── Address-of a variable → result in X0 ──────────────────────────────
    void gen_addr_of(const Expr& e);
    void gen_index_addr(const Expr& e);

    // ── Emit a store to the address currently in X1 from value in X0 ──────
    void emit_store_to_addr(); // STR X0, [X1, #0]

    // ── Globals ───────────────────────────────────────────────────────────
    void emit_globals(const TranslationUnit& tu);
    std::unordered_map<std::string, std::string> global_labels_; // name → .L label
};
