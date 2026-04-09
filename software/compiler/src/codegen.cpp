#include "codegen.h"
#include <stdexcept>
#include <cassert>
#include <cstdlib>

// ---------------------------------------------------------------------------
// Register aliases
// ---------------------------------------------------------------------------
#define SP  "X28"
#define FP  "X29"
#define LR  "X30"
#define SH  "X27"   // shift-amount scratch (callee-saved)
#define RV  "X0"    // expression result / return value
#define T1  "X16"   // temp — only used within a single non-recursive emit
#define T2  "X17"
#define T3  "X18"

// ---------------------------------------------------------------------------
CodeGen::CodeGen(std::ostream& out) : out_(out) {}

// ---------------------------------------------------------------------------
// Emission helpers
// ---------------------------------------------------------------------------
std::string CodeGen::new_label(const std::string& prefix) {
    return prefix + std::to_string(label_counter_++);
}
void CodeGen::emit(const std::string& line) { out_ << "    " << line << "\n"; }
void CodeGen::emit_label(const std::string& lbl) { out_ << lbl << ":\n"; }
void CodeGen::emit_comment(const std::string& msg) { out_ << "    ; " << msg << "\n"; }

// ---------------------------------------------------------------------------
// Stack-machine helpers
// Push X0 onto the expression stack (uses SP = X28).
// These are the fix for nested binary expressions clobbering temps.
// ---------------------------------------------------------------------------
void CodeGen::push_expr() {
    emit("SUBI " SP ", " SP ", #4");
    emit("STR  " RV ", [" SP ", #0]");
}

void CodeGen::pop_expr(const std::string& reg) {
    emit("LDR  " + reg + ", [" SP ", #0]");
    emit("ADDI " SP ", " SP ", #4");
}

// ---------------------------------------------------------------------------
// Load a 32-bit constant into a register.
// Fits in 16-bit signed → single ADDI.
// Otherwise: load high 16, shift left 16, OR in low 16.
// ---------------------------------------------------------------------------
void CodeGen::emit_load_const(const std::string& reg, int64_t val) {
    int32_t v = (int32_t)(val & 0xFFFFFFFF);
    if (v >= -32768 && v <= 32767) {
        emit("ADDI " + reg + ", X0, #" + std::to_string(v));
        return;
    }
    int32_t hi = (v >> 16) & 0xFFFF;
    int32_t lo =  v        & 0xFFFF;
    emit("ADDI " + reg + ", X0, #" + std::to_string(hi));
    emit_shift_left_imm(reg, reg, 16);
    if (lo != 0) {
        emit("ADDI " T1 ", X0, #" + std::to_string(lo));
        emit("ORR  " + reg + ", " + reg + ", " T1);
    }
}

// ---------------------------------------------------------------------------
// Shift by immediate — hardware only supports register shifts.
// We load the amount into SH (X27), then use the reg-shift form.
// ---------------------------------------------------------------------------
void CodeGen::emit_shift_left_imm(const std::string& dst,
                                   const std::string& src, int amount) {
    if (amount == 0) {
        if (dst != src) emit("ORR " + dst + ", " + src + ", X0");
        return;
    }
    emit("ADDI " SH ", X0, #" + std::to_string(amount));
    emit("LSL  " + dst + ", " + src + ", " SH);
}

void CodeGen::emit_shift_right_imm(const std::string& dst,
                                    const std::string& src, int amount) {
    if (amount == 0) {
        if (dst != src) emit("ORR " + dst + ", " + src + ", X0");
        return;
    }
    emit("ADDI " SH ", X0, #" + std::to_string(amount));
    emit("LSR  " + dst + ", " + src + ", " SH);
}

// ---------------------------------------------------------------------------
// Software multiply: dst = lhs_reg * rhs_reg  (shift-and-add, 32 iterations)
// Uses T1 (accumulator), T2 (shifted lhs), T3 (remaining rhs bits).
// All caller-saved — safe inside non-recursive context.
// ---------------------------------------------------------------------------
void CodeGen::emit_multiply(const std::string& dst,
                             const std::string& lhs_reg,
                             const std::string& rhs_reg) {
    std::string loop = new_label(".Lmul_loop");
    std::string done = new_label(".Lmul_done");
    std::string skip = new_label(".Lmul_skip");

    emit_comment("software mul: " + dst + " = " + lhs_reg + " * " + rhs_reg);
    emit("ADDI " T1 ", X0, #0");           // accumulator = 0
    emit("ORR  " T2 ", " + lhs_reg + ", X0"); // T2 = lhs copy
    emit("ORR  " T3 ", " + rhs_reg + ", X0"); // T3 = rhs copy
    emit_label(loop);
    emit("CBZ  " T3 ", " + done);
    emit("ANDI " SH ", " T3 ", #1");       // SH = rhs bit 0
    emit("CBZ  " SH ", " + skip);
    emit("ADD  " T1 ", " T1 ", " T2);      // if bit set: acc += lhs
    emit_label(skip);
    emit("ADDI " SH ", X0, #1");
    emit("LSL  " T2 ", " T2 ", " SH);      // lhs <<= 1
    emit("ADDI " SH ", X0, #1");
    emit("LSR  " T3 ", " T3 ", " SH);      // rhs >>= 1
    emit("B    " + loop);
    emit_label(done);
    if (dst != T1) emit("ORR  " + dst + ", " T1 ", X0");
}

// ---------------------------------------------------------------------------
// Prologue / Epilogue
// Frame layout (FP = X29, SP = X28):
//   [SP + frame_size - 4]  saved old FP
//   [SP + frame_size - 8]  saved LR
//   [SP + frame_size - 12] param 0 / local 0   (FP - 8)
//   [SP + frame_size - 16] param 1 / local 1   (FP - 12)
//   ...
//   [SP + 0]               bottom of frame
// ---------------------------------------------------------------------------
void CodeGen::emit_prologue(const FuncDecl& fn) {
    // We reserve 64 bytes for locals (covers 16 ints).
    // Saved FP + LR = 8 bytes.  Total = 72, already 8-byte aligned.
    int frame_size = 72;
    cur_func_->frame_size = frame_size;

    emit_comment("prologue: " + fn.name);
    emit("SUBI " SP ", " SP ", #" + std::to_string(frame_size));
    // Save old FP
    emit("STR  " FP ", [" SP ", #" + std::to_string(frame_size - 4) + "]");
    // Save LR
    emit("STR  " LR ", [" SP ", #" + std::to_string(frame_size - 8) + "]");
    // Set our FP = SP + frame_size - 4
    // So FP points to the saved-FP slot.
    // Local var at FP-8 lives at SP + frame_size - 4 - 8 = SP + frame_size - 12.
    emit("ADDI " FP ", " SP ", #" + std::to_string(frame_size - 4));

    // Params: copy from arg registers X0-X5 into their stack slots
    for (size_t i = 0; i < fn.params.size() && i < 6; i++) {
        const LocalVar& lv = cur_func_->locals[i];
        emit("STR  X" + std::to_string(i) +
             ", [" FP ", #" + std::to_string(lv.fp_offset) + "]");
    }
}

void CodeGen::emit_epilogue() {
    int fs = cur_func_->frame_size;
    emit_comment("epilogue");
    emit("LDR  " LR ", [" SP ", #" + std::to_string(fs - 8) + "]");
    emit("LDR  " FP ", [" SP ", #" + std::to_string(fs - 4) + "]");
    emit("ADDI " SP ", " SP ", #" + std::to_string(fs));
    emit("RET  " LR);
}

// ---------------------------------------------------------------------------
// Variable management
// ---------------------------------------------------------------------------
const LocalVar* CodeGen::find_local(const std::string& name) const {
    if (!cur_func_) return nullptr;
    for (const auto& lv : cur_func_->locals)
        if (lv.name == name) return &lv;
    return nullptr;
}

LocalVar* CodeGen::alloc_local(const std::string& name, bool is_ptr) {
    LocalVar lv;
    lv.name       = name;
    lv.fp_offset  = cur_func_->next_offset;
    lv.is_pointer = is_ptr;
    cur_func_->next_offset -= 4;
    cur_func_->locals.push_back(lv);
    return &cur_func_->locals.back();
}

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
void CodeGen::emit_globals(const TranslationUnit& tu) {
    if (tu.globals.empty()) return;
    out_ << "\n.data\n";
    for (const auto& gv : tu.globals) {
        std::string lbl = "__g_" + gv.name;
        global_labels_[gv.name] = lbl;
        out_ << lbl << ":\n";
        out_ << "    .word " << (gv.has_init ? gv.init_val : 0) << "\n";
    }
    out_ << ".text\n\n";
}

// ---------------------------------------------------------------------------
// Translation unit
// ---------------------------------------------------------------------------
void CodeGen::emit_translation_unit(const TranslationUnit& tu) {
    out_ << "; Generated by legv8-cc\n";
    out_ << "; ABI: X0-X5 args, X0 return, X28=SP, X29=FP, X30=LR\n\n";
    out_ << ".text\n\n";
    emit_globals(tu);
    for (const auto& fn : tu.funcs)
        gen_func(*fn);
}

// ---------------------------------------------------------------------------
// Function generation
// ---------------------------------------------------------------------------
void CodeGen::gen_func(const FuncDecl& fn) {
    FuncContext ctx;
    ctx.name        = fn.name;
    ctx.next_offset = -8;  // first var at FP-8
    ctx.frame_size  = 0;
    cur_func_ = &ctx;

    // Pre-allocate slots for parameters before emitting prologue
    for (const auto& p : fn.params)
        alloc_local(p.name, p.is_pointer);

    out_ << "; ── function: " << fn.name << "\n";
    emit_label(fn.name);
    emit_prologue(fn);
    gen_stmt(*fn.body);

    // Implicit return 0
    emit_comment("implicit return 0");
    emit("ADDI " RV ", X0, #0");
    emit_epilogue();
    out_ << "\n";
    cur_func_ = nullptr;
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------
void CodeGen::gen_stmt(const Stmt& s) {
    switch (s.kind) {
        case StmtKind::Block:   gen_block(s);    break;
        case StmtKind::VarDecl: gen_var_decl(s); break;
        case StmtKind::ExprStmt: gen_expr(*s.expr); break;
        case StmtKind::If:      gen_if(s);       break;
        case StmtKind::While:   gen_while(s);    break;
        case StmtKind::For:     gen_for(s);      break;
        case StmtKind::Return:  gen_return(s);   break;
    }
}

void CodeGen::gen_block(const Stmt& s) {
    for (const auto& stmt : s.stmts) gen_stmt(*stmt);
}

void CodeGen::gen_var_decl(const Stmt& s) {
    alloc_local(s.var_name, s.is_pointer);
    const LocalVar* lv = find_local(s.var_name);
    if (s.init_expr) {
        gen_expr(*s.init_expr);
        emit("STR  " RV ", [" FP ", #" + std::to_string(lv->fp_offset) + "]");
    } else {
        // Zero-initialise
        emit("STR  X0, [" FP ", #" + std::to_string(lv->fp_offset) + "]");
    }
}

void CodeGen::gen_if(const Stmt& s) {
    std::string else_lbl = new_label(".Lelse");
    std::string end_lbl  = new_label(".Lendif");
    gen_expr(*s.cond);
    emit("CBZ  " RV ", " + (s.else_body ? else_lbl : end_lbl));
    gen_stmt(*s.then_body);
    if (s.else_body) {
        emit("B    " + end_lbl);
        emit_label(else_lbl);
        gen_stmt(*s.else_body);
    }
    emit_label(end_lbl);
}

void CodeGen::gen_while(const Stmt& s) {
    std::string loop_lbl = new_label(".Lwhile");
    std::string end_lbl  = new_label(".Lendwhile");
    emit_label(loop_lbl);
    gen_expr(*s.cond);
    emit("CBZ  " RV ", " + end_lbl);
    gen_stmt(*s.body);
    emit("B    " + loop_lbl);
    emit_label(end_lbl);
}

void CodeGen::gen_for(const Stmt& s) {
    std::string loop_lbl = new_label(".Lfor");
    std::string end_lbl  = new_label(".Lendfor");
    if (s.for_init)  gen_stmt(*s.for_init);
    emit_label(loop_lbl);
    if (s.for_cond) {
        gen_expr(*s.for_cond);
        emit("CBZ  " RV ", " + end_lbl);
    }
    gen_stmt(*s.body);
    if (s.for_post) gen_expr(*s.for_post);
    emit("B    " + loop_lbl);
    emit_label(end_lbl);
}

void CodeGen::gen_return(const Stmt& s) {
    if (s.ret_expr)
        gen_expr(*s.ret_expr);
    else
        emit("ADDI " RV ", X0, #0");
    emit_epilogue();
}

// ---------------------------------------------------------------------------
// Expression generation
// Invariant: every gen_expr call leaves its result in X0 (RV).
// For binary ops we use a push/pop stack discipline so that evaluating
// the rhs cannot clobber the lhs result regardless of nesting depth.
// ---------------------------------------------------------------------------
void CodeGen::gen_expr(const Expr& e) {
    switch (e.kind) {
        case ExprKind::IntLit: gen_intlit(e);  break;
        case ExprKind::Var:    gen_var(e);     break;
        case ExprKind::Assign: gen_assign(e);  break;
        case ExprKind::Binary: gen_binary(e);  break;
        case ExprKind::Unary:  gen_unary(e);   break;
        case ExprKind::Call:   gen_call(e);    break;
        case ExprKind::Index:  gen_index(e);   break;
        default:
            throw std::runtime_error("codegen: unhandled expr kind");
    }
}

void CodeGen::gen_intlit(const Expr& e) {
    emit_load_const(RV, e.ival);
}

void CodeGen::gen_var(const Expr& e) {
    const LocalVar* lv = find_local(e.name);
    if (lv) {
        emit("LDR  " RV ", [" FP ", #" + std::to_string(lv->fp_offset) + "]");
        return;
    }
    auto it = global_labels_.find(e.name);
    if (it != global_labels_.end()) {
        // Load global: emit address pool pattern
        std::string skip_lbl = new_label(".Lgskip");
        std::string pool_lbl = new_label(".Lgpool");
        // We need the address of pool_lbl in a register.
        // Use BL trick: BL next_instr captures PC+4 in LR.
        // Layout:
        //   BL   pool_lbl        ; LR = address of word below
        //   B    skip_lbl        ; skip over the pool word
        // pool_lbl:
        //   .word __g_name       ; address of global
        // skip_lbl:
        //   LDR  X0, [LR, #0]   ; X0 = address of global
        //   LDR  X0, [X0, #0]   ; X0 = value of global
        emit("BL   " + pool_lbl);
        emit("B    " + skip_lbl);
        emit_label(pool_lbl);
        out_ << "    .word " << it->second << "\n";
        emit_label(skip_lbl);
        emit("LDR  " RV ", [" LR ", #0]");  // X0 = address of global
        emit("LDR  " RV ", [" RV ", #0]");  // X0 = value
        return;
    }
    throw std::runtime_error("undefined variable: " + e.name);
}

void CodeGen::gen_assign(const Expr& e) {
    const Expr& lhs = *e.lhs;

    // Evaluate rhs → X0, then store
    gen_expr(*e.rhs);

    if (lhs.kind == ExprKind::Var) {
        const LocalVar* lv = find_local(lhs.name);
        if (!lv) throw std::runtime_error("assign to unknown variable: " + lhs.name);
        emit("STR  " RV ", [" FP ", #" + std::to_string(lv->fp_offset) + "]");
        return;
    }
    if (lhs.kind == ExprKind::Unary && lhs.op == "*") {
        // *ptr = rhs:  save rhs value, compute ptr address, store
        push_expr();                        // push rhs value
        gen_expr(*lhs.operand);             // X0 = ptr address
        pop_expr(T1);                       // T1 = rhs value
        emit("STR  " T1 ", [" RV ", #0]");
        emit("ORR  " RV ", " T1 ", X0");   // return the assigned value
        return;
    }
    if (lhs.kind == ExprKind::Index) {
        push_expr();                        // push rhs value
        gen_index_addr(lhs);                // X0 = address
        pop_expr(T1);                       // T1 = rhs value
        emit("STR  " T1 ", [" RV ", #0]");
        emit("ORR  " RV ", " T1 ", X0");
        return;
    }
    throw std::runtime_error("invalid assignment target");
}

// Compute address of arr[i] into X0
void CodeGen::gen_index_addr(const Expr& e) {
    // e.lhs = base pointer/array, e.rhs = index
    gen_expr(*e.lhs);          // X0 = base address
    push_expr();               // save base
    gen_expr(*e.rhs);          // X0 = index
    emit("ADDI " SH ", X0, #2");
    emit("LSL  " RV ", " RV ", " SH);  // X0 = index * 4
    pop_expr(T1);              // T1 = base
    emit("ADD  " RV ", " T1 ", " RV); // X0 = base + index*4
}

void CodeGen::gen_index(const Expr& e) {
    gen_index_addr(e);
    emit("LDR  " RV ", [" RV ", #0]");
}

// ---------------------------------------------------------------------------
// Binary expression — the stack-machine fix
//
// For all two-operand ops:
//   1. Evaluate lhs → X0
//   2. PUSH X0 onto expression stack
//   3. Evaluate rhs → X0
//   4. POP lhs into T1
//   5. Emit the operation: X0 = T1 op X0
//
// Step 3 may recurse arbitrarily without clobbering step 2's result
// because that result is safely on the hardware stack.
// ---------------------------------------------------------------------------
void CodeGen::gen_binary(const Expr& e) {
    const std::string& op = e.op;

    // Short-circuit operators — don't evaluate rhs unconditionally
    if (op == "&&") {
        std::string false_lbl = new_label(".Land_false");
        std::string end_lbl   = new_label(".Land_end");
        gen_expr(*e.lhs);
        emit("CBZ  " RV ", " + false_lbl);
        gen_expr(*e.rhs);
        emit("CBZ  " RV ", " + false_lbl);
        emit("ADDI " RV ", X0, #1");
        emit("B    " + end_lbl);
        emit_label(false_lbl);
        emit("ADDI " RV ", X0, #0");
        emit_label(end_lbl);
        return;
    }
    if (op == "||") {
        std::string true_lbl = new_label(".Lor_true");
        std::string end_lbl  = new_label(".Lor_end");
        gen_expr(*e.lhs);
        emit("CBNZ " RV ", " + true_lbl);
        gen_expr(*e.rhs);
        emit("CBNZ " RV ", " + true_lbl);
        emit("ADDI " RV ", X0, #0");
        emit("B    " + end_lbl);
        emit_label(true_lbl);
        emit("ADDI " RV ", X0, #1");
        emit_label(end_lbl);
        return;
    }

    // ── Stack-machine evaluation ─────────────────────────────────────────
    gen_expr(*e.lhs);       // X0 = lhs
    push_expr();            // push lhs onto stack (safe from rhs clobbering)
    gen_expr(*e.rhs);       // X0 = rhs  (may clobber T1/T2/T3 freely)
    pop_expr(T1);           // T1 = lhs  (restore from stack)
    // Now: T1 = lhs result, X0 = rhs result

    if (op == "+")  { emit("ADD  " RV ", " T1 ", " RV); return; }
    if (op == "-")  { emit("SUB  " RV ", " T1 ", " RV); return; }
    if (op == "&")  { emit("AND  " RV ", " T1 ", " RV); return; }
    if (op == "|")  { emit("ORR  " RV ", " T1 ", " RV); return; }
    if (op == "^")  { emit("EOR  " RV ", " T1 ", " RV); return; }
    if (op == "<<") { emit("LSL  " RV ", " T1 ", " RV); return; }
    if (op == ">>") { emit("LSR  " RV ", " T1 ", " RV); return; }
    if (op == "*")  { emit_multiply(RV, T1, RV); return; }

    // Comparisons → result 0 or 1
    if (op == "==" || op == "!=" || op == "<" || op == ">" ||
        op == "<=" || op == ">=") {
        std::string true_lbl = new_label(".Lcmp_true");
        std::string end_lbl  = new_label(".Lcmp_end");

        // T1 = lhs, X0 = rhs, T2 = lhs - rhs
        emit("SUB  " T2 ", " T1 ", " RV);

        if (op == "==") {
            emit("CBZ  " T2 ", " + true_lbl);
        } else if (op == "!=") {
            emit("CBNZ " T2 ", " + true_lbl);
        } else if (op == "<") {
            // lhs < rhs  iff  (lhs - rhs) is negative  iff  sign bit set
            emit("ADDI " SH ", X0, #31");
            emit("LSR  " T2 ", " T2 ", " SH);
            emit("CBNZ " T2 ", " + true_lbl);
        } else if (op == ">") {
            // lhs > rhs  iff  (rhs - lhs) is negative
            emit("SUB  " T2 ", " RV ", " T1);
            emit("ADDI " SH ", X0, #31");
            emit("LSR  " T2 ", " T2 ", " SH);
            emit("CBNZ " T2 ", " + true_lbl);
        } else if (op == "<=") {
            // lhs <= rhs  iff  NOT (lhs > rhs)  iff  (rhs - lhs) >= 0
            emit("SUB  " T2 ", " RV ", " T1);
            emit("ADDI " SH ", X0, #31");
            emit("LSR  " T2 ", " T2 ", " SH);
            emit("CBZ  " T2 ", " + true_lbl);
        } else { // >=
            // lhs >= rhs  iff  (lhs - rhs) >= 0  iff  sign bit clear
            emit("ADDI " SH ", X0, #31");
            emit("LSR  " T2 ", " T2 ", " SH);
            emit("CBZ  " T2 ", " + true_lbl);
        }

        emit("ADDI " RV ", X0, #0");
        emit("B    " + end_lbl);
        emit_label(true_lbl);
        emit("ADDI " RV ", X0, #1");
        emit_label(end_lbl);
        return;
    }

    throw std::runtime_error("codegen: unknown binary op '" + op + "'");
}

void CodeGen::gen_unary(const Expr& e) {
    if (e.op == "-") {
        gen_expr(*e.operand);
        emit("NEG  " RV ", " RV);
        return;
    }
    if (e.op == "~") {
        gen_expr(*e.operand);
        emit("ADDI " T1 ", X0, #-1");
        emit("EOR  " RV ", " RV ", " T1);
        return;
    }
    if (e.op == "!") {
        std::string true_lbl = new_label(".Lnot_true");
        std::string end_lbl  = new_label(".Lnot_end");
        gen_expr(*e.operand);
        emit("CBZ  " RV ", " + true_lbl);
        emit("ADDI " RV ", X0, #0");
        emit("B    " + end_lbl);
        emit_label(true_lbl);
        emit("ADDI " RV ", X0, #1");
        emit_label(end_lbl);
        return;
    }
    if (e.op == "*") {
        gen_expr(*e.operand);
        emit("LDR  " RV ", [" RV ", #0]");
        return;
    }
    if (e.op == "&") {
        gen_addr_of(*e.operand);
        return;
    }
    throw std::runtime_error("codegen: unknown unary op '" + e.op + "'");
}

void CodeGen::gen_addr_of(const Expr& e) {
    if (e.kind != ExprKind::Var)
        throw std::runtime_error("address-of requires a variable");
    const LocalVar* lv = find_local(e.name);
    if (!lv) throw std::runtime_error("& of unknown variable: " + e.name);
    emit_load_const(RV, lv->fp_offset);
    emit("ADD  " RV ", " FP ", " RV);
}

void CodeGen::gen_call(const Expr& e) {
    if (e.args.size() > 6)
        throw std::runtime_error("max 6 function arguments");

    int n = (int)e.args.size();
    // Evaluate args right-to-left, push to temp stack
    for (int i = n - 1; i >= 0; i--) {
        gen_expr(*e.args[i]);
        push_expr();
    }
    // Pop into X0-X5
    for (int i = 0; i < n; i++) {
        pop_expr("X" + std::to_string(i));
    }
    emit("BL   " + e.name);
    // Return value in X0
}
