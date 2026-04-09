#pragma once
#include <string>
#include <cstdint>

// ---------------------------------------------------------------------------
// Token types for the C subset lexer
// ---------------------------------------------------------------------------
enum class TK {
    // Literals
    INT_LIT,        // 42, -7, 0xFF

    // Identifier / keywords
    IDENT,          // foo, bar, my_var
    KW_INT,         // int
    KW_IF,          // if
    KW_ELSE,        // else
    KW_WHILE,       // while
    KW_FOR,         // for
    KW_RETURN,      // return

    // Arithmetic operators
    PLUS,           // +
    MINUS,          // -
    STAR,           // *
    SLASH,          // /   (unsupported — error)

    // Bitwise operators
    AMP,            // &
    PIPE,           // |
    CARET,          // ^
    TILDE,          // ~
    LSHIFT,         // <<
    RSHIFT,         // >>

    // Comparison
    EQ,             // ==
    NEQ,            // !=
    LT,             // <
    GT,             // >
    LEQ,            // <=
    GEQ,            // >=

    // Assignment
    ASSIGN,         // =

    // Logical
    AND,            // &&
    OR,             // ||
    BANG,           // !

    // Delimiters
    LPAREN,         // (
    RPAREN,         // )
    LBRACE,         // {
    RBRACE,         // }
    LBRACKET,       // [
    RBRACKET,       // ]
    SEMICOLON,      // ;
    COMMA,          // ,

    // Pointer / address
    ARROW,          // ->  (future)

    // Misc
    END_OF_FILE,
};

struct Token {
    TK          type;
    std::string text;       // original text (for errors)
    int64_t     ival;       // valid for INT_LIT
    int         line;
    int         col;
    std::string file;
};
