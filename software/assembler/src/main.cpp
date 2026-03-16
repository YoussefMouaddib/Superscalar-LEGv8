#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include "lexer.h"
#include "parser.h"
#include "output.h"
#include "error.h"

// ---------------------------------------------------------------------------
static void usage(const char* argv0) {
    fprintf(stderr,
        "usage: %s <input.s> [options]\n"
        "\n"
        "options:\n"
        "  -o <file>          output file (default: a.out)\n"
        "  -f bin             raw binary for UART bootloader (default)\n"
        "  -f coe             Xilinx .coe for Vivado BRAM init\n"
        "  -f hex             Intel HEX\n"
        "  -l <listing.txt>   write human-readable listing\n"
        "  --base <addr>      load address in hex (default: 0x00000000)\n"
        "  --dump-symbols     print symbol table to stderr after assembly\n"
        "  -h                 show this help\n"
        "\n"
        "examples:\n"
        "  %s boot.s -o boot.coe -f coe --base 0x00000000\n"
        "  %s app.s  -o app.bin  -f bin --base 0x40000000\n",
        argv0, argv0, argv0);
    exit(0);
}

// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
int main(int argc, char** argv) {
    if (argc < 2) { usage(argv[0]); }

    std::string input_path;
    std::string output_path = "a.out";
    std::string listing_path;
    OutputFormat fmt = OutputFormat::BIN;
    uint32_t base_addr = 0x00000000;
    bool dump_symbols = false;

    for (int i = 1; i < argc; ++i) {
        if (argv[i][0] != '-') {
            if (input_path.empty()) input_path = argv[i];
            else { fprintf(stderr, "error: multiple input files not supported\n"); exit(1); }
            continue;
        }
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            usage(argv[0]);
        }
        if (!strcmp(argv[i], "-o") && i+1 < argc) {
            output_path = argv[++i]; continue;
        }
        if (!strcmp(argv[i], "-f") && i+1 < argc) {
            ++i;
            if      (!strcmp(argv[i], "bin")) fmt = OutputFormat::BIN;
            else if (!strcmp(argv[i], "coe")) fmt = OutputFormat::COE;
            else if (!strcmp(argv[i], "hex")) fmt = OutputFormat::HEX_INTEL;
            else { fprintf(stderr, "error: unknown format '%s'\n", argv[i]); exit(1); }
            continue;
        }
        if (!strcmp(argv[i], "-l") && i+1 < argc) {
            listing_path = argv[++i]; continue;
        }
        if (!strcmp(argv[i], "--base") && i+1 < argc) {
            char* end;
            base_addr = (uint32_t)strtoul(argv[++i], &end, 0);
            if (*end != '\0') {
                fprintf(stderr, "error: invalid base address '%s'\n", argv[i]);
                exit(1);
            }
            continue;
        }
        if (!strcmp(argv[i], "--dump-symbols")) {
            dump_symbols = true; continue;
        }
        fprintf(stderr, "error: unknown option '%s'\n", argv[i]);
        exit(1);
    }

    if (input_path.empty()) {
        fprintf(stderr, "error: no input file\n");
        usage(argv[0]);
    }

    // -----------------------------------------------------------------------
    // Pipeline: read → lex → parse (2-pass) → build image → write
    // -----------------------------------------------------------------------
    std::string source = read_file(input_path);

    Lexer lexer(input_path, source);

    Parser parser(lexer.tokens(), input_path, base_addr);
    parser.parse();

    if (dump_symbols)
        parser.symbols().dump();

    FlatImage img = build_image(parser.entries(), base_addr);

    write_output(img, output_path, fmt);

    if (!listing_path.empty())
        write_listing(parser.entries(), listing_path);

    fprintf(stderr, "assembled %u bytes -> %s\n", img.size(), output_path.c_str());
    return 0;
}
