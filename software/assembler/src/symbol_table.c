#pragma once
#include <string>
#include <unordered_map>
#include <cstdint>
#include "error.h"

// ---------------------------------------------------------------------------
// SymbolTable
//
// Pass 1: call define(label, address) for every LABEL_DEF encountered.
// Pass 2: call resolve(label, use_loc) to get the address.
//
// Addresses are byte addresses (the assembler tracks PC in bytes).
// ---------------------------------------------------------------------------
class SymbolTable {
public:
    // Define a label. Duplicate definition is a fatal error.
    void define(const std::string& name, uint32_t byte_addr, SourceLoc loc) {
        auto it = table_.find(name);
        if (it != table_.end()) {
            err_fatal(loc, "duplicate label definition '%s' "
                      "(previously defined at byte 0x%08X)",
                      name.c_str(), it->second);
        }
        table_[name] = byte_addr;
    }

    // Resolve a label. Missing definition is a fatal error.
    uint32_t resolve(const std::string& name, SourceLoc loc) const {
        auto it = table_.find(name);
        if (it == table_.end())
            err_fatal(loc, "undefined label '%s'", name.c_str());
        return it->second;
    }

    bool contains(const std::string& name) const {
        return table_.count(name) > 0;
    }

    // Debug: dump all symbols to stderr
    void dump() const {
        fprintf(stderr, "=== symbol table ===\n");
        for (auto& [name, addr] : table_)
            fprintf(stderr, "  %-30s 0x%08X\n", name.c_str(), addr);
    }

private:
    std::unordered_map<std::string, uint32_t> table_;
};
