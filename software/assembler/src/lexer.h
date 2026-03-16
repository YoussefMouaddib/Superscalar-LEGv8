#pragma once
#include <string>
#include <vector>
#include "error.h"

// ---------------------------------------------------------------------------
// Token types
// ---------------------------------------------------------------------------
enum class TokType {
    // Mnemonics
    MNEMONIC,       // ADD, LDR, CBZ, ...

    // Operands
    REG,            // X0..X31
    IMM,            // #123, #-4, #0xFF
    LABEL_REF,      // foo  (used as branch target)
    LABEL_DEF,      // foo: (definition)

    // Syntax
    LBRACKET,       // [
    RBRACKET,       // ]
    COMMA,          // ,
    HASH,           // # (already consumed into IMM usually)

    // Directives
    DIRECTIVE,      // .text, .data, .word, .byte, .align, .space

    // Data values inside directives
    STRING_LIT,     // "hello"
    INTEGER_LIT,    // raw integer (in .word / .byte without #)

    // Misc
    END_OF_LINE,
    END_OF_FILE,
};

struct Token {
    TokType     type;
    std::string text;       // original text for error messages
    int64_t     ival;       // valid when type==IMM, INTEGER_LIT, REG
    int         line;       // 1-based
    int         col;        // 1-based
};

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------
class Lexer {
public:
    Lexer(const std::string& filename, const std::string& source);

    // Returns every token in the file (including END_OF_LINE sentinels).
    // Callers iterate this list; parser consumes it.
    const std::vector<Token>& tokens() const { return tokens_; }

private:
    void tokenize();
    Token make_token(TokType t, const std::string& text,
                     int64_t ival, int line, int col) const;

    void lex_line(const std::string& line, int lineno);
    Token lex_word(const std::string& word, int lineno, int col);
    Token lex_immediate(const std::string& text, int lineno, int col);

    std::string filename_;
    std::string source_;
    std::vector<Token> tokens_;
};
