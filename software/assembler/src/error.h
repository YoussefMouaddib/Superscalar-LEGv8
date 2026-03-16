#pragma once
#include <string>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>

// ---------------------------------------------------------------------------
// Error reporting
// All messages go to stderr. Fatal errors call exit(1).
// ---------------------------------------------------------------------------

struct SourceLoc {
    const char* file;
    int         line;   // 1-based
    int         col;    // 1-based, 0 = unknown
};

static inline void err_fatal(SourceLoc loc, const char* fmt, ...)
    __attribute__((format(printf, 2, 3)));

static inline void err_warning(SourceLoc loc, const char* fmt, ...)
    __attribute__((format(printf, 2, 3)));

static inline void err_fatal(SourceLoc loc, const char* fmt, ...) {
    fprintf(stderr, "%s:%d", loc.file, loc.line);
    if (loc.col > 0) fprintf(stderr, ":%d", loc.col);
    fprintf(stderr, ": error: ");
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    exit(1);
}

static inline void err_warning(SourceLoc loc, const char* fmt, ...) {
    fprintf(stderr, "%s:%d", loc.file, loc.line);
    if (loc.col > 0) fprintf(stderr, ":%d", loc.col);
    fprintf(stderr, ": warning: ");
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
}

// Unconditional internal assertion — not user-facing
#define ASSERT(cond, msg) \
    do { if (!(cond)) { \
        fprintf(stderr, "internal: %s:%d: %s\n", __FILE__, __LINE__, msg); \
        exit(2); \
    }} while(0)
