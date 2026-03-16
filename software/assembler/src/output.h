#pragma once
#include <vector>
#include <string>
#include <cstdint>
#include "parser.h"
#include "encoder.h"
#include "error.h"

enum class OutputFormat {
    BIN,        // Raw binary — used with UART bootloader
    HEX_INTEL,  // Intel HEX — useful for inspection / other tools
    COE,        // Xilinx .coe — for Vivado BRAM initialization (bootloader)
    LISTING,    // Human-readable listing (addr: encoding  mnemonic)
};

// ---------------------------------------------------------------------------
// Assemble all entries into a flat byte buffer starting at base_addr.
// Gaps (from .align, .space) are zero-filled.
// ---------------------------------------------------------------------------
struct FlatImage {
    uint32_t             base_addr;
    std::vector<uint8_t> bytes;

    uint32_t size() const { return (uint32_t)bytes.size(); }
    uint32_t end_addr() const { return base_addr + size(); }
};

FlatImage build_image(const std::vector<SectionEntry>& entries,
                      uint32_t base_addr);

// ---------------------------------------------------------------------------
// Write the image to a file in the requested format.
// ---------------------------------------------------------------------------
void write_output(const FlatImage& img, const std::string& path,
                  OutputFormat fmt);

// Also write a listing to stdout (or a file) for debugging.
void write_listing(const std::vector<SectionEntry>& entries,
                   const std::string& path);
