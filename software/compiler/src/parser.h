#pragma once
#include <vector>
#include <string>
#include <memory>
#include "token.h"
#include "ast.h"

class Parser {
public:
    Parser(const std::vector<Token>& tokens);
    TranslationUnit parse();

private:
    // ── Token stream ──────────────────────────────────────────────────────
    const std::vector<Token>& toks_;
    size_t pos_ = 0;

    const Token& peek(int off = 0) const;
    const Token& consume();
    const Token& expect(TK t, const char* ctx);
    bool  check(TK t, int off = 0) const;
    bool  match(TK t);
    void  error(const Token& tok, const std::string& msg) const;

    // ── Top-level ─────────────────────────────────────────────────────────
    void parse_global(TranslationUnit& tu);
    std::unique_ptr<FuncDecl> parse_function(const std::string& name, bool is_ptr);

    // ── Statements ────────────────────────────────────────────────────────
    StmtPtr parse_stmt();
    StmtPtr parse_block();
    StmtPtr parse_var_decl();
    StmtPtr parse_if();
    StmtPtr parse_while();
    StmtPtr parse_for();
    StmtPtr parse_return();
    StmtPtr parse_expr_stmt();

    // ── Expressions (precedence climbing) ─────────────────────────────────
    ExprPtr parse_expr();
    ExprPtr parse_assign();
    ExprPtr parse_logical_or();
    ExprPtr parse_logical_and();
    ExprPtr parse_bitwise_or();
    ExprPtr parse_bitwise_xor();
    ExprPtr parse_bitwise_and();
    ExprPtr parse_equality();
    ExprPtr parse_relational();
    ExprPtr parse_shift();
    ExprPtr parse_additive();
    ExprPtr parse_multiplicative();
    ExprPtr parse_unary();
    ExprPtr parse_postfix();
    ExprPtr parse_primary();

    // ── Helpers ───────────────────────────────────────────────────────────
    ExprPtr make_binary(const std::string& op, ExprPtr lhs, ExprPtr rhs, int line);
    ExprPtr make_unary(const std::string& op, ExprPtr operand, int line);
};
