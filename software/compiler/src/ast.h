#pragma once
#include <string>
#include <vector>
#include <memory>
#include <cstdint>

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
struct Expr;
struct Stmt;
struct FuncDecl;
using ExprPtr = std::unique_ptr<Expr>;
using StmtPtr = std::unique_ptr<Stmt>;

// ---------------------------------------------------------------------------
// Expression node kinds
// ---------------------------------------------------------------------------
enum class ExprKind {
    IntLit,         // 42
    Var,            // x
    Unary,          // -x, ~x, !x, &x (address-of), *x (deref)
    Binary,         // x + y, x & y, x << y, ...
    Assign,         // x = expr
    Call,           // foo(a, b, c)
    Index,          // arr[i]  →  *(arr + i)
    Deref,          // *ptr
    AddrOf,         // &var
};

struct Expr {
    ExprKind    kind;
    int         line;

    // IntLit
    int64_t     ival;

    // Var
    std::string name;

    // Unary
    std::string op;         // "-", "~", "!", "*", "&"
    ExprPtr     operand;

    // Binary
    // op field reused
    ExprPtr     lhs;
    ExprPtr     rhs;

    // Call
    // name = function name
    std::vector<ExprPtr> args;

    // Index: arr[i] — lhs=arr, rhs=i
    // Assign: lhs=target expr (Var or Deref or Index), rhs=value
};

// ---------------------------------------------------------------------------
// Statement node kinds
// ---------------------------------------------------------------------------
enum class StmtKind {
    Block,          // { stmt* }
    VarDecl,        // int x; or int x = expr;
    ExprStmt,       // expr;
    If,             // if (cond) then [else alt]
    While,          // while (cond) body
    For,            // for (init; cond; post) body
    Return,         // return expr;
};

struct Stmt {
    StmtKind    kind;
    int         line;

    // VarDecl
    std::string var_name;
    bool        is_pointer = false;     // int *p
    ExprPtr     init_expr;              // optional initializer

    // ExprStmt
    ExprPtr     expr;

    // If
    ExprPtr     cond;
    StmtPtr     then_body;
    StmtPtr     else_body;             // nullptr if no else

    // While / For body
    StmtPtr     body;

    // For: init is a VarDecl or ExprStmt; post is an ExprStmt
    StmtPtr     for_init;
    ExprPtr     for_cond;
    ExprPtr     for_post;

    // Block
    std::vector<StmtPtr> stmts;

    // Return
    ExprPtr     ret_expr;              // nullptr for bare return
};

// ---------------------------------------------------------------------------
// Function parameter
// ---------------------------------------------------------------------------
struct Param {
    std::string name;
    bool        is_pointer;
    int         line;
};

// ---------------------------------------------------------------------------
// Top-level function declaration
// ---------------------------------------------------------------------------
struct FuncDecl {
    std::string         name;
    std::vector<Param>  params;
    bool                returns_void;   // unused for now — all funcs return int
    StmtPtr             body;           // Block statement
    int                 line;
};

// ---------------------------------------------------------------------------
// Global variable declaration
// ---------------------------------------------------------------------------
struct GlobalVar {
    std::string name;
    bool        is_pointer;
    int64_t     init_val;   // only constant initializers for now
    bool        has_init;
    int         line;
};

// ---------------------------------------------------------------------------
// Translation unit — the whole file
// ---------------------------------------------------------------------------
struct TranslationUnit {
    std::vector<GlobalVar>              globals;
    std::vector<std::unique_ptr<FuncDecl>> funcs;
};
