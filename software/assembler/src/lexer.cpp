#include "lexer.h"
#include <sstream>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <stdarg.h>
#include <unordered_set>

// ---------------------------------------------------------------------------
// Mnemonic table — everything the lexer needs to classify a word as MNEMONIC
// ---------------------------------------------------------------------------
static const std::unordered_set<std::string> MNEMONICS = {
    "ADD","SUB","AND","ORR","EOR","NEG","CMP",
    "ADDI","SUBI","ANDI","ORI","EORI",
    "LSL","LSR",
    "LDR","STR","LDUR","STUR","CAS",
    "B","BL","RET","CBZ","CBNZ",
    "SVC","NOP",
};

static const std::unordered_set<std::string> DIRECTIVES = {
    ".text",".data",".bss",
    ".word",".byte",".align",".space",".ascii",".asciz",
    ".global",".extern",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static std::string to_upper(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), ::toupper);
    return s;
}

static bool is_ident_start(char c) {
    return std::isalpha(c) || c == '_' || c == '.';
}
static bool is_ident_body(char c) {
    return std::isalnum(c) || c == '_' || c == '.' || c == '@';
}

// ---------------------------------------------------------------------------
Lexer::Lexer(const std::string& filename, const std::string& source)
    : filename_(filename), source_(source) {
    tokenize();
}

Token Lexer::make_token(TokType t, const std::string& text,
                        int64_t ival, int line, int col) const {
    return Token{t, text, ival, line, col};
}

// ---------------------------------------------------------------------------
// Main tokenization: split into lines, lex each
// ---------------------------------------------------------------------------
void Lexer::tokenize() {
    std::istringstream ss(source_);
    std::string line;
    int lineno = 0;
    while (std::getline(ss, line)) {
        ++lineno;
        lex_line(line, lineno);
        tokens_.push_back(make_token(TokType::END_OF_LINE, "\n", 0, lineno, 0));
    }
    tokens_.push_back(make_token(TokType::END_OF_FILE, "", 0, lineno, 0));
}

// ---------------------------------------------------------------------------
// Lex one source line
// ---------------------------------------------------------------------------
void Lexer::lex_line(const std::string& raw, int lineno) {
    // Strip comment (;  or  // style)
    std::string line = raw;
    {
        bool in_str = false;
        for (size_t i = 0; i < line.size(); ++i) {
            if (line[i] == '"') { in_str = !in_str; continue; }
            if (!in_str) {
                if (line[i] == ';') { line = line.substr(0, i); break; }
                if (i+1 < line.size() && line[i]=='/' && line[i+1]=='/') {
                    line = line.substr(0, i); break;
                }
            }
        }
    }

    size_t i = 0;
    auto skip_ws = [&]() {
        while (i < line.size() && std::isspace((unsigned char)line[i])) ++i;
    };

    auto loc = [&]() -> SourceLoc { return {filename_.c_str(), lineno, (int)i+1}; };

    skip_ws();
    while (i < line.size()) {
        int col = (int)i + 1;

        // --- String literal ---
        if (line[i] == '"') {
            size_t start = ++i;
            while (i < line.size() && line[i] != '"') {
                if (line[i] == '\\') ++i;  // skip escape
                ++i;
            }
            if (i >= line.size())
                err_fatal({filename_.c_str(), lineno, col}, "unterminated string literal");
            std::string s = line.substr(start, i - start);
            tokens_.push_back(make_token(TokType::STRING_LIT, s, 0, lineno, col));
            ++i; // closing "
            skip_ws();
            continue;
        }

        // --- Comma ---
        if (line[i] == ',') {
            tokens_.push_back(make_token(TokType::COMMA, ",", 0, lineno, col));
            ++i; skip_ws(); continue;
        }

        // --- Brackets ---
        if (line[i] == '[') {
            tokens_.push_back(make_token(TokType::LBRACKET, "[", 0, lineno, col));
            ++i; skip_ws(); continue;
        }
        if (line[i] == ']') {
            tokens_.push_back(make_token(TokType::RBRACKET, "]", 0, lineno, col));
            ++i; skip_ws(); continue;
        }

        // --- Immediate: #value ---
        if (line[i] == '#') {
            ++i;
            size_t start = i;
            if (i < line.size() && (line[i] == '-' || line[i] == '+')) ++i;
            // Hex?
            if (i+1 < line.size() && line[i]=='0' &&
                (line[i+1]=='x'||line[i+1]=='X')) i += 2;
            while (i < line.size() && std::isxdigit((unsigned char)line[i])) ++i;
            std::string txt = line.substr(start, i - start);
            tokens_.push_back(lex_immediate(txt, lineno, col));
            skip_ws(); continue;
        }

        // --- Identifiers: mnemonics, registers, labels, directives ---
        if (is_ident_start(line[i])) {
            size_t start = i;
            while (i < line.size() && is_ident_body(line[i])) ++i;
            std::string word = line.substr(start, i - start);

            // Label definition: word followed by ':'
            skip_ws();
            if (i < line.size() && line[i] == ':') {
                tokens_.push_back(make_token(TokType::LABEL_DEF, word, 0, lineno, col));
                ++i; skip_ws(); continue;
            }

            tokens_.push_back(lex_word(word, lineno, col));
            skip_ws(); continue;
        }

        // --- Bare integer (e.g. inside .word 42) ---
        if (std::isdigit((unsigned char)line[i]) ||
            (line[i]=='-' && i+1<line.size() && std::isdigit((unsigned char)line[i+1]))) {
            size_t start = i;
            if (line[i]=='-') ++i;
            if (i+1<line.size() && line[i]=='0' && (line[i+1]=='x'||line[i+1]=='X'))
                i += 2;
            while (i < line.size() && std::isxdigit((unsigned char)line[i])) ++i;
            std::string txt = line.substr(start, i - start);
            char* end;
            int64_t val = std::strtoll(txt.c_str(), &end, 0);
            tokens_.push_back(make_token(TokType::INTEGER_LIT, txt, val, lineno, col));
            skip_ws(); continue;
        }

        err_fatal(loc(), "unexpected character '%c'", line[i]);
    }
}

// ---------------------------------------------------------------------------
// Classify an identifier word
// ---------------------------------------------------------------------------
Token Lexer::lex_word(const std::string& word, int lineno, int col) {
    // Directives (.text, .word, ...)
    if (!word.empty() && word[0] == '.') {
        std::string lower = word;
        std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
        if (DIRECTIVES.count(lower))
            return make_token(TokType::DIRECTIVE, lower, 0, lineno, col);
        // Unknown directive — warn but continue
        fprintf(stderr, "%s:%d:%d: warning: unknown directive '%s'\n",
                "?", lineno, col, word.c_str());
        return make_token(TokType::DIRECTIVE, lower, 0, lineno, col);
    }

    std::string up = to_upper(word);

    // Registers: X0..X31, XZR (== X31), SP (== X28 by convention here), LR (X30)
    if (!up.empty() && up[0] == 'X') {
        std::string num_part = up.substr(1);
        if (!num_part.empty() && std::all_of(num_part.begin(), num_part.end(), ::isdigit)) {
            int64_t rnum = std::stoll(num_part);
            if (rnum >= 0 && rnum <= 31)
                return make_token(TokType::REG, up, rnum, lineno, col);
        }
    }
    if (up == "XZR") return make_token(TokType::REG, up, 31, lineno, col);
    if (up == "SP")  return make_token(TokType::REG, up, 28, lineno, col);
    if (up == "LR")  return make_token(TokType::REG, up, 30, lineno, col);
    if (up == "FP")  return make_token(TokType::REG, up, 29, lineno, col);

    // Mnemonics
    if (MNEMONICS.count(up))
        return make_token(TokType::MNEMONIC, up, 0, lineno, col);

    // Fall-through: treat as label reference (branch target, etc.)
    return make_token(TokType::LABEL_REF, word, 0, lineno, col);
}

// ---------------------------------------------------------------------------
// Parse a bare numeric string (after # has been stripped) into an IMM token
// ---------------------------------------------------------------------------
Token Lexer::lex_immediate(const std::string& text, int lineno, int col) {
    if (text.empty())
        err_fatal({nullptr, lineno, col}, "empty immediate after '#'");
    char* end;
    int64_t val = std::strtoll(text.c_str(), &end, 0);
    if (*end != '\0')
        err_fatal({nullptr, lineno, col},
                  "malformed immediate '#%s'", text.c_str());
    return make_token(TokType::IMM, "#" + text, val, lineno, col);
}
