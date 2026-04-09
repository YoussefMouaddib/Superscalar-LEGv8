#include <iostream>
#include <fstream>
#include <sstream>
#include <cstring>
#include "lexer.h"
#include "parser.h"
#include "codegen.h"

static void usage(const char* argv0) {
    fprintf(stderr,
        "usage: %s <input.c> [options]\n"
        "\n"
        "options:\n"
        "  -o <file>    output file (default: stdout)\n"
        "  -h           show this help\n"
        "\n"
        "examples:\n"
        "  %s sort.c -o sort.s\n"
        "  %s sort.c | legv8-as - -o sort.bin -f bin\n",
        argv0, argv0, argv0);
    exit(0);
}

static std::string read_file(const std::string& path) {
    std::ifstream f(path);
    if (!f) {
        fprintf(stderr, "error: cannot open '%s'\n", path.c_str());
        exit(1);
    }
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

int main(int argc, char** argv) {
    if (argc < 2) usage(argv[0]);

    std::string input_path;
    std::string output_path;

    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) usage(argv[0]);
        if (!strcmp(argv[i], "-o") && i+1 < argc) { output_path = argv[++i]; continue; }
        if (argv[i][0] != '-') {
            if (input_path.empty()) input_path = argv[i];
            else { fprintf(stderr, "error: multiple input files not supported\n"); exit(1); }
            continue;
        }
        fprintf(stderr, "error: unknown option '%s'\n", argv[i]);
        exit(1);
    }

    if (input_path.empty()) {
        fprintf(stderr, "error: no input file\n");
        usage(argv[0]);
    }

    try {
        std::string src = read_file(input_path);

        Lexer lexer(input_path, src);
        auto tokens = lexer.tokenize();

        Parser parser(tokens);
        TranslationUnit tu = parser.parse();

        std::ofstream out_file;
        std::ostream* out = &std::cout;
        if (!output_path.empty()) {
            out_file.open(output_path);
            if (!out_file) {
                fprintf(stderr, "error: cannot open output '%s'\n", output_path.c_str());
                exit(1);
            }
            out = &out_file;
        }

        CodeGen cg(*out);
        cg.emit_translation_unit(tu);

        fprintf(stderr, "compiled %s -> %s\n",
                input_path.c_str(),
                output_path.empty() ? "stdout" : output_path.c_str());
        return 0;

    } catch (const std::exception& ex) {
        fprintf(stderr, "error: %s\n", ex.what());
        return 1;
    }
}
