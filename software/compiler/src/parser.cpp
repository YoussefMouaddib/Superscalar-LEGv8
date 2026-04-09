#include "parser.h"
#include <stdexcept>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const Token& Parser::peek(int off) const {
    size_t idx = pos_ + (size_t)off;
    if (idx >= toks_.size()) return toks_.back();
    return toks_[idx];
}
const Token& Parser::consume() {
    if (pos_ < toks_.size()) return toks_[pos_++];
    return toks_.back();
}
bool Parser::check(TK t, int off) const { return peek(off).type == t; }
bool Parser::match(TK t) {
    if (check(t)) { consume(); return true; }
    return false;
}
const Token& Parser::expect(TK t, const char* ctx) {
    if (!check(t))
        error(peek(), std::string("expected token while parsing ") + ctx);
    return consume();
}
void Parser::error(const Token& tok, const std::string& msg) const {
    throw std::runtime_error(
        tok.file + ":" + std::to_string(tok.line) + ":" +
        std::to_string(tok.col) + ": " + msg + " (got '" + tok.text + "')");
}

Parser::Parser(const std::vector<Token>& tokens) : toks_(tokens) {}

// ---------------------------------------------------------------------------
// Top-level parse
// ---------------------------------------------------------------------------
TranslationUnit Parser::parse() {
    TranslationUnit tu;
    while (!check(TK::END_OF_FILE)) {
        parse_global(tu);
    }
    return tu;
}

// Each top-level item starts with 'int' then a name.
// If followed by '(' it's a function; otherwise a global variable.
void Parser::parse_global(TranslationUnit& tu) {
    expect(TK::KW_INT, "global declaration");

    bool is_ptr = false;
    if (match(TK::STAR)) is_ptr = true;

    const Token& name_tok = expect(TK::IDENT, "global name");
    std::string name = name_tok.text;

    if (check(TK::LPAREN)) {
        // Function
        auto fn = parse_function(name, is_ptr);
        fn->line = name_tok.line;
        tu.funcs.push_back(std::move(fn));
    } else {
        // Global variable
        GlobalVar gv;
        gv.name       = name;
        gv.is_pointer = is_ptr;
        gv.has_init   = false;
        gv.init_val   = 0;
        gv.line       = name_tok.line;
        if (match(TK::ASSIGN)) {
            const Token& lit = expect(TK::INT_LIT, "global initializer");
            gv.init_val = lit.ival;
            gv.has_init = true;
        }
        expect(TK::SEMICOLON, "global variable");
        tu.globals.push_back(gv);
    }
}

std::unique_ptr<FuncDecl> Parser::parse_function(const std::string& name, bool /*is_ptr*/) {
    auto fn = std::make_unique<FuncDecl>();
    fn->name = name;

    expect(TK::LPAREN, "function params");
    while (!check(TK::RPAREN) && !check(TK::END_OF_FILE)) {
        expect(TK::KW_INT, "parameter type");
        Param p;
        p.is_pointer = false;
        if (match(TK::STAR)) p.is_pointer = true;
        const Token& pname = expect(TK::IDENT, "parameter name");
        p.name = pname.text;
        p.line = pname.line;
        fn->params.push_back(p);
        if (!match(TK::COMMA)) break;
    }
    expect(TK::RPAREN, "function params end");

    fn->body = parse_block();
    return fn;
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------
StmtPtr Parser::parse_stmt() {
    if (check(TK::LBRACE))     return parse_block();
    if (check(TK::KW_INT))     return parse_var_decl();
    if (check(TK::KW_IF))      return parse_if();
    if (check(TK::KW_WHILE))   return parse_while();
    if (check(TK::KW_FOR))     return parse_for();
    if (check(TK::KW_RETURN))  return parse_return();
    return parse_expr_stmt();
}

StmtPtr Parser::parse_block() {
    int line = peek().line;
    expect(TK::LBRACE, "block");
    auto blk = std::make_unique<Stmt>();
    blk->kind = StmtKind::Block;
    blk->line = line;
    while (!check(TK::RBRACE) && !check(TK::END_OF_FILE))
        blk->stmts.push_back(parse_stmt());
    expect(TK::RBRACE, "block end");
    return blk;
}

StmtPtr Parser::parse_var_decl() {
    int line = peek().line;
    expect(TK::KW_INT, "var decl");
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::VarDecl;
    s->line = line;
    s->is_pointer = false;
    if (match(TK::STAR)) s->is_pointer = true;
    s->var_name = expect(TK::IDENT, "var name").text;
    if (match(TK::ASSIGN))
        s->init_expr = parse_expr();
    expect(TK::SEMICOLON, "var decl");
    return s;
}

StmtPtr Parser::parse_if() {
    int line = peek().line;
    expect(TK::KW_IF, "if");
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::If;
    s->line = line;
    expect(TK::LPAREN, "if condition");
    s->cond = parse_expr();
    expect(TK::RPAREN, "if condition end");
    s->then_body = parse_stmt();
    if (match(TK::KW_ELSE))
        s->else_body = parse_stmt();
    return s;
}

StmtPtr Parser::parse_while() {
    int line = peek().line;
    expect(TK::KW_WHILE, "while");
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::While;
    s->line = line;
    expect(TK::LPAREN, "while condition");
    s->cond = parse_expr();
    expect(TK::RPAREN, "while condition end");
    s->body = parse_stmt();
    return s;
}

StmtPtr Parser::parse_for() {
    int line = peek().line;
    expect(TK::KW_FOR, "for");
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::For;
    s->line = line;
    expect(TK::LPAREN, "for (");

    // init: either 'int x = ...' or expr or empty
    if (check(TK::KW_INT))
        s->for_init = parse_var_decl();  // includes semicolon
    else if (!check(TK::SEMICOLON)) {
        auto es = std::make_unique<Stmt>();
        es->kind = StmtKind::ExprStmt;
        es->line = peek().line;
        es->expr = parse_expr();
        expect(TK::SEMICOLON, "for init");
        s->for_init = std::move(es);
    } else {
        consume(); // eat empty semicolon
    }

    // condition
    if (!check(TK::SEMICOLON))
        s->for_cond = parse_expr();
    expect(TK::SEMICOLON, "for cond");

    // post
    if (!check(TK::RPAREN))
        s->for_post = parse_expr();
    expect(TK::RPAREN, "for )");

    s->body = parse_stmt();
    return s;
}

StmtPtr Parser::parse_return() {
    int line = peek().line;
    expect(TK::KW_RETURN, "return");
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::Return;
    s->line = line;
    if (!check(TK::SEMICOLON))
        s->ret_expr = parse_expr();
    expect(TK::SEMICOLON, "return");
    return s;
}

StmtPtr Parser::parse_expr_stmt() {
    int line = peek().line;
    auto s = std::make_unique<Stmt>();
    s->kind = StmtKind::ExprStmt;
    s->line = line;
    s->expr = parse_expr();
    expect(TK::SEMICOLON, "expression statement");
    return s;
}

// ---------------------------------------------------------------------------
// Expressions — precedence climbing (lowest to highest)
// ---------------------------------------------------------------------------
ExprPtr Parser::parse_expr()           { return parse_assign(); }

ExprPtr Parser::parse_assign() {
    ExprPtr lhs = parse_logical_or();
    if (check(TK::ASSIGN)) {
        int line = peek().line;
        consume();
        ExprPtr rhs = parse_assign();  // right-associative
        auto e = std::make_unique<Expr>();
        e->kind = ExprKind::Assign;
        e->line = line;
        e->lhs  = std::move(lhs);
        e->rhs  = std::move(rhs);
        return e;
    }
    return lhs;
}

ExprPtr Parser::parse_logical_or() {
    ExprPtr lhs = parse_logical_and();
    while (check(TK::OR)) {
        int line = peek().line; consume();
        lhs = make_binary("||", std::move(lhs), parse_logical_and(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_logical_and() {
    ExprPtr lhs = parse_bitwise_or();
    while (check(TK::AND)) {
        int line = peek().line; consume();
        lhs = make_binary("&&", std::move(lhs), parse_bitwise_or(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_bitwise_or() {
    ExprPtr lhs = parse_bitwise_xor();
    while (check(TK::PIPE)) {
        int line = peek().line; consume();
        lhs = make_binary("|", std::move(lhs), parse_bitwise_xor(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_bitwise_xor() {
    ExprPtr lhs = parse_bitwise_and();
    while (check(TK::CARET)) {
        int line = peek().line; consume();
        lhs = make_binary("^", std::move(lhs), parse_bitwise_and(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_bitwise_and() {
    ExprPtr lhs = parse_equality();
    while (check(TK::AMP)) {
        int line = peek().line; consume();
        lhs = make_binary("&", std::move(lhs), parse_equality(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_equality() {
    ExprPtr lhs = parse_relational();
    while (check(TK::EQ) || check(TK::NEQ)) {
        int line = peek().line;
        std::string op = consume().text;
        lhs = make_binary(op, std::move(lhs), parse_relational(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_relational() {
    ExprPtr lhs = parse_shift();
    while (check(TK::LT) || check(TK::GT) || check(TK::LEQ) || check(TK::GEQ)) {
        int line = peek().line;
        std::string op = consume().text;
        lhs = make_binary(op, std::move(lhs), parse_shift(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_shift() {
    ExprPtr lhs = parse_additive();
    while (check(TK::LSHIFT) || check(TK::RSHIFT)) {
        int line = peek().line;
        std::string op = consume().text;
        lhs = make_binary(op, std::move(lhs), parse_additive(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_additive() {
    ExprPtr lhs = parse_multiplicative();
    while (check(TK::PLUS) || check(TK::MINUS)) {
        int line = peek().line;
        std::string op = consume().text;
        lhs = make_binary(op, std::move(lhs), parse_multiplicative(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_multiplicative() {
    ExprPtr lhs = parse_unary();
    while (check(TK::STAR)) {
        int line = peek().line;
        consume();
        lhs = make_binary("*", std::move(lhs), parse_unary(), line);
    }
    return lhs;
}

ExprPtr Parser::parse_unary() {
    int line = peek().line;
    if (check(TK::MINUS))  { consume(); return make_unary("-",  parse_unary(), line); }
    if (check(TK::TILDE))  { consume(); return make_unary("~",  parse_unary(), line); }
    if (check(TK::BANG))   { consume(); return make_unary("!",  parse_unary(), line); }
    if (check(TK::STAR))   { consume(); return make_unary("*",  parse_unary(), line); } // deref
    if (check(TK::AMP))    { consume(); return make_unary("&",  parse_unary(), line); } // addr-of
    return parse_postfix();
}

ExprPtr Parser::parse_postfix() {
    ExprPtr e = parse_primary();
    while (true) {
        if (check(TK::LBRACKET)) {
            // arr[i]  →  *(arr + i)
            int line = peek().line;
            consume();
            ExprPtr idx = parse_expr();
            expect(TK::RBRACKET, "array index");
            // Build arr[i] as Index node — codegen handles it
            auto ie = std::make_unique<Expr>();
            ie->kind = ExprKind::Index;
            ie->line = line;
            ie->lhs  = std::move(e);
            ie->rhs  = std::move(idx);
            e = std::move(ie);
        } else break;
    }
    return e;
}

ExprPtr Parser::parse_primary() {
    int line = peek().line;

    // Integer literal
    if (check(TK::INT_LIT)) {
        auto e = std::make_unique<Expr>();
        e->kind = ExprKind::IntLit;
        e->line = line;
        e->ival = consume().ival;
        return e;
    }

    // Identifier: variable or function call
    if (check(TK::IDENT)) {
        std::string name = consume().text;
        if (check(TK::LPAREN)) {
            // Function call
            consume();
            auto e = std::make_unique<Expr>();
            e->kind = ExprKind::Call;
            e->line = line;
            e->name = name;
            while (!check(TK::RPAREN) && !check(TK::END_OF_FILE)) {
                e->args.push_back(parse_expr());
                if (!match(TK::COMMA)) break;
            }
            expect(TK::RPAREN, "call args");
            return e;
        }
        // Variable reference
        auto e = std::make_unique<Expr>();
        e->kind = ExprKind::Var;
        e->line = line;
        e->name = name;
        return e;
    }

    // Parenthesised expression
    if (check(TK::LPAREN)) {
        consume();
        ExprPtr e = parse_expr();
        expect(TK::RPAREN, "parenthesised expr");
        return e;
    }

    error(peek(), "expected expression");
    return nullptr; // unreachable
}

// ---------------------------------------------------------------------------
// AST node constructors
// ---------------------------------------------------------------------------
ExprPtr Parser::make_binary(const std::string& op, ExprPtr lhs, ExprPtr rhs, int line) {
    auto e = std::make_unique<Expr>();
    e->kind = ExprKind::Binary;
    e->line = line;
    e->op   = op;
    e->lhs  = std::move(lhs);
    e->rhs  = std::move(rhs);
    return e;
}

ExprPtr Parser::make_unary(const std::string& op, ExprPtr operand, int line) {
    auto e = std::make_unique<Expr>();
    e->kind = ExprKind::Unary;
    e->line = line;
    e->op      = op;
    e->operand = std::move(operand);
    return e;
}
