#pragma once
#include <string>
#include <vector>
#include "token.h"

class Lexer {
public:
    Lexer(const std::string& filename, const std::string& src);
    std::vector<Token> tokenize();

private:
    std::string filename_;
    std::string src_;
    size_t      pos_  = 0;
    int         line_ = 1;
    int         col_  = 1;

    char peek(int off = 0) const;
    char consume();
    void skip_whitespace_and_comments();
    Token make(TK t, const std::string& text, int64_t ival = 0) const;
    Token lex_number();
    Token lex_ident_or_keyword();

    int  start_line_ = 1;
    int  start_col_  = 1;
};
