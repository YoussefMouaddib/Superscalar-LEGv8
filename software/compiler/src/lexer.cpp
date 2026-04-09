#include "lexer.h"
#include <cctype>
#include <stdexcept>
#include <cstdlib>

static bool is_ident_start(char c) { return std::isalpha(c) || c == '_'; }
static bool is_ident_body(char c)  { return std::isalnum(c) || c == '_'; }

Lexer::Lexer(const std::string& filename, const std::string& src)
    : filename_(filename), src_(src) {}

char Lexer::peek(int off) const {
    size_t idx = pos_ + (size_t)off;
    return (idx < src_.size()) ? src_[idx] : '\0';
}

char Lexer::consume() {
    char c = src_[pos_++];
    if (c == '\n') { ++line_; col_ = 1; }
    else           { ++col_; }
    return c;
}

Token Lexer::make(TK t, const std::string& text, int64_t ival) const {
    return Token{t, text, ival, start_line_, start_col_, filename_};
}

void Lexer::skip_whitespace_and_comments() {
    while (pos_ < src_.size()) {
        // Whitespace
        if (std::isspace((unsigned char)peek())) { consume(); continue; }
        // Line comment
        if (peek() == '/' && peek(1) == '/') {
            while (pos_ < src_.size() && peek() != '\n') consume();
            continue;
        }
        // Block comment
        if (peek() == '/' && peek(1) == '*') {
            consume(); consume();
            while (pos_ < src_.size()) {
                if (peek() == '*' && peek(1) == '/') { consume(); consume(); break; }
                consume();
            }
            continue;
        }
        break;
    }
}

Token Lexer::lex_number() {
    std::string s;
    // Hex?
    if (peek() == '0' && (peek(1) == 'x' || peek(1) == 'X')) {
        s += consume(); s += consume();
        while (std::isxdigit((unsigned char)peek())) s += consume();
    } else {
        while (std::isdigit((unsigned char)peek())) s += consume();
    }
    char* end;
    int64_t val = std::strtoll(s.c_str(), &end, 0);
    return make(TK::INT_LIT, s, val);
}

Token Lexer::lex_ident_or_keyword() {
    std::string s;
    while (is_ident_body(peek())) s += consume();

    // Keyword table
    if (s == "int")    return make(TK::KW_INT,    s);
    if (s == "if")     return make(TK::KW_IF,     s);
    if (s == "else")   return make(TK::KW_ELSE,   s);
    if (s == "while")  return make(TK::KW_WHILE,  s);
    if (s == "for")    return make(TK::KW_FOR,     s);
    if (s == "return") return make(TK::KW_RETURN,  s);

    return make(TK::IDENT, s);
}

std::vector<Token> Lexer::tokenize() {
    std::vector<Token> toks;

    while (true) {
        skip_whitespace_and_comments();
        if (pos_ >= src_.size()) {
            toks.push_back(make(TK::END_OF_FILE, ""));
            break;
        }

        start_line_ = line_;
        start_col_  = col_;
        char c = peek();

        // Number
        if (std::isdigit((unsigned char)c)) {
            toks.push_back(lex_number());
            continue;
        }

        // Identifier / keyword
        if (is_ident_start(c)) {
            toks.push_back(lex_ident_or_keyword());
            continue;
        }

        consume(); // eat the character

        switch (c) {
            case '+': toks.push_back(make(TK::PLUS,  "+")); break;
            case '-':
                if (peek() == '>') { consume(); toks.push_back(make(TK::ARROW, "->")); }
                else toks.push_back(make(TK::MINUS, "-"));
                break;
            case '*': toks.push_back(make(TK::STAR,  "*")); break;
            case '/': toks.push_back(make(TK::SLASH, "/")); break;
            case '&':
                if (peek() == '&') { consume(); toks.push_back(make(TK::AND, "&&")); }
                else toks.push_back(make(TK::AMP, "&"));
                break;
            case '|':
                if (peek() == '|') { consume(); toks.push_back(make(TK::OR, "||")); }
                else toks.push_back(make(TK::PIPE, "|"));
                break;
            case '^': toks.push_back(make(TK::CARET, "^")); break;
            case '~': toks.push_back(make(TK::TILDE, "~")); break;
            case '<':
                if (peek() == '<') { consume(); toks.push_back(make(TK::LSHIFT, "<<")); }
                else if (peek() == '=') { consume(); toks.push_back(make(TK::LEQ, "<=")); }
                else toks.push_back(make(TK::LT, "<"));
                break;
            case '>':
                if (peek() == '>') { consume(); toks.push_back(make(TK::RSHIFT, ">>")); }
                else if (peek() == '=') { consume(); toks.push_back(make(TK::GEQ, ">=")); }
                else toks.push_back(make(TK::GT, ">"));
                break;
            case '=':
                if (peek() == '=') { consume(); toks.push_back(make(TK::EQ, "==")); }
                else toks.push_back(make(TK::ASSIGN, "="));
                break;
            case '!':
                if (peek() == '=') { consume(); toks.push_back(make(TK::NEQ, "!=")); }
                else toks.push_back(make(TK::BANG, "!"));
                break;
            case '(': toks.push_back(make(TK::LPAREN,    "(")); break;
            case ')': toks.push_back(make(TK::RPAREN,    ")")); break;
            case '{': toks.push_back(make(TK::LBRACE,    "{")); break;
            case '}': toks.push_back(make(TK::RBRACE,    "}")); break;
            case '[': toks.push_back(make(TK::LBRACKET,  "[")); break;
            case ']': toks.push_back(make(TK::RBRACKET,  "]")); break;
            case ';': toks.push_back(make(TK::SEMICOLON, ";")); break;
            case ',': toks.push_back(make(TK::COMMA,     ",")); break;
            default:
                throw std::runtime_error(
                    filename_ + ":" + std::to_string(start_line_) +
                    ": unexpected character '" + c + "'");
        }
    }
    return toks;
}
