
 ## LEGv8 2-Wide Superscalar Out-of-Order Processor
### Custom CPU Microarchitecture & End-to-End Software Stack — Toolchain, Firmware & Bare-Metal OS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![FPGA](https://img.shields.io/badge/Target-ColorLight%205A--75B-blue)](https://github.com/wuxx/ColorLight-FPGA)
[![Verilog](https://img.shields.io/badge/HDL-SystemVerilog-ff69b4)](https://en.wikipedia.org/wiki/SystemVerilog)
[![LUTs](https://img.shields.io/badge/LUTs-14k%2F24k-success)]()
# ![CpuI7GIF](https://github.com/user-attachments/assets/4eb98bca-c9c1-4a54-bd70-918482c4340f)

A complete RTL implementation of a 2-wide superscalar out-of-order processor supporting a subset of the LEGv8 ISA. This isn't a textbook example or a tutorial clone—this is a real CPU built from first principles, debugged at the waveform level, and verified running actual programs.

**Status:** ✅ Successfully executes "Hello, LEGv8!" via UART after 73 cycles of stores + loads

---

## 📖 Table of Contents
- [Why This Exists](#why-this-exists)
- [What Actually Works](#what-actually-works)
- [Architecture Overview](#architecture-overview)
- [Microarchitecture Deep Dive](#microarchitecture-deep-dive)
- [The Hard Parts (And How I Fixed Them)](#the-hard-parts)
- [Memory Map](#memory-map)
- [Building & Running](#building--running)
- [Verification](#verification)
- [What I Learned](#what-i-learned)
- [Future Work](#future-work)

---

## 🎯 Why This Exists

**The problem:** Every computer architecture course teaches you *about* superscalar processors. Few teach you how to *build* one.

**The goal:** Understand out-of-order execution by implementing every component from scratch:
- Register renaming (no false dependencies)
- Tomasulo's algorithm (dynamic scheduling)
- Reorder buffer (in-order commit from out-of-order execution)
- Load-store queue (memory ordering + forwarding)
- Branch prediction (speculative execution)
- Common Data Bus arbitration (multiple execution units competing)

**The result:** A working 2-wide superscalar processor that successfully:
- Fetches 2 instructions per cycle
- Renames registers to eliminate WAW/WAR hazards
- Issues instructions out-of-order when operands ready
- Executes on multiple functional units (2x ALU, 1x LSU, 1x Branch)
- Commits in-order to maintain precise exceptions
- Runs real programs (string output via UART)

This README documents the **actual implementation**, including the bugs I hit and how I fixed them.

---

## ✅ What Actually Works

**Verified Features:**
- ✅ 2-wide superscalar fetch/decode/rename/dispatch
- ✅ Out-of-order issue from 32-entry issue queue
- ✅ 64 physical registers (32 architectural + 32 rename)
- ✅ 32-entry reorder buffer with 2-wide commit
- ✅ Round-robin free list allocation (prevents premature register reuse)
- ✅ Load/store queue with memory ordering via sequence numbers
- ✅ Branch predictor with 2-bit saturating counters
- ✅ CDB arbitration (2 ports, 4 sources: ALU0, ALU1, Branch, LSU)
- ✅ Memory-mapped UART (writes "Hello, LEGv8!" to console)
- ✅ Scratchpad RAM (0x2000-0x2FFF, stores string data)
- ✅ ROM instruction storage (0x0000-0x1FFF, holds program)

**Test Program:**
```assembly
# Write "Hello, LEGv8!" to scratchpad, then send via UART
ADDI X1, X0, #1          # X1 = 1
ADDI X5, X0, #16         # X5 = 16
LSL  X1, X1, X5          # X1 = 0x10000 (UART base)
ADDI X9, X0, #2          # X9 = 2
ADDI X5, X0, #12         # X5 = 12
LSL  X9, X9, X5          # X9 = 0x2000 (scratchpad base)

# Store "Hello, LEGv8!\r\n\0" to scratchpad
ADDI X6, X0, #'H'
STR  X6, [X9, #0]
ADDI X6, X0, #'e'
STR  X6, [X9, #4]
# ... (full string stored at 0x2000-0x203C)

# Transmit loop: read from scratchpad, write to UART
send_string:
    ADDI X3, X9, #0      # X3 = string pointer
loop:
    LDR  X4, [X3, #0]    # Load character
    CBZ  X4, done        # Exit if null terminator
    LDR  X6, [X2, #0]    # Check UART status
    AND  X6, X6, X5      # Mask TX_BUSY bit
    CBNZ X6, wait_tx     # Wait if busy
    STR  X4, [X1, #0]    # Write to UART
    ADDI X3, X3, #4      # Next character
    B    loop
done:
    B    done            # Infinite loop
```

**Execution trace:** String successfully written to scratchpad (cycles 19-55), then read and transmitted via UART. CPU successfully executes stores, loads, branches, and I/O operations in an out-of-order fashion.

---

## 🏗️ Architecture Overview

### **Key Parameters**
```systemverilog
parameter XLEN = 32;              // 32-bit datapath
parameter ISSUE_WIDTH = 2;        // 2-wide superscalar
parameter PREGS = 64;             // Physical register file size
parameter ROB_ENTRIES = 32;       // Reorder buffer depth
parameter IQ_ENTRIES = 32;        // Issue queue depth
parameter LQ_ENTRIES = 16;        // Load queue depth
parameter SQ_ENTRIES = 16;        // Store queue depth
```

### **Pipeline Stages**
```
┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌───────┐  ┌─────────┐  ┌────────┐
│ Fetch   │→ │ Decode  │→ │ Rename  │→ │ Dispatch │→ │ Issue │→ │ Execute │→ │ Commit │
│ (F0,F1) │  │ (D0,D1) │  │ (R0,R1) │  │ (Di0,Di1)│  │  (IQ) │  │ (FUs)   │  │ (ROB)  │
└─────────┘  └─────────┘  └─────────┘  └──────────┘  └───────┘  └─────────┘  └────────┘
     ↑                                                                              ↓
     └──────────────────────── Branch Mispredict Flush ─────────────────────────────┘
```

**Stage Descriptions:**
1. **Fetch (F0, F1):** Reads 2 instructions from ROM per cycle, updates PC
2. **Decode (D0, D1):** Decodes opcodes, extracts register fields and immediates
3. **Rename (R0, R1):** Maps architectural registers to physical registers via RAT
4. **Dispatch (Di0, Di1):** Allocates ROB entries, sends to issue queue or LSU
5. **Issue (IQ):** Out-of-order wakeup when operands ready, sends to execution units
6. **Execute (ALU0, ALU1, Branch, LSU):** Compute results, broadcast on CDB
7. **Commit (C0, C1):** In-order commit from ROB, updates architectural state

---

## 🔬 Microarchitecture Deep Dive

### **1. Register Renaming**

**Purpose:** Eliminate false dependencies (WAW, WAR) while preserving true dependencies (RAW)

**Components:**
- **Register Alias Table (RAT):** Maps 32 architectural registers → 64 physical registers
- **Free List:** Tracks available physical registers using round-robin allocation
- **Commit Map:** Maintains committed architectural-to-physical mapping for exceptions

**Implementation Highlights:**
```systemverilog
// Rename stage (2-wide)
for (int i = 0; i < ISSUE_WIDTH; i++) begin
    if (decode_valid[i]) begin
        // Read source mappings from RAT
        phys_rs1[i] = rat[arch_rs1[i]];
        phys_rs2[i] = rat[arch_rs2[i]];
        
        // Allocate new physical destination
        phys_rd[i] = free_list_alloc[i];
        
        // Update RAT speculatively
        rat_next[arch_rd[i]] = phys_rd[i];
    end
end
```

**Critical Bug Fixed:** Initial free list always allocated lowest available register (e.g., p32, p33, p32, p33...), causing immediate reuse and value corruption. **Solution:** Round-robin allocation with rotating pointer starting at p32, ensuring minimum 32-cycle gap before reuse.

---

### **2. Reorder Buffer (ROB)**

**Purpose:** Maintain program order for in-order commit despite out-of-order execution

**Structure (32 entries):**
```systemverilog
typedef struct packed {
    logic valid;              // Entry allocated
    logic ready;              // Result available
    logic [4:0] arch_dest;    // Architectural register destination
    logic [5:0] phys_dest;    // Physical register destination
    logic [31:0] pc;          // Program counter
    logic is_store;           // Store instruction
    logic is_load;            // Load instruction
    logic is_branch;          // Branch instruction
    logic exception;          // Exception occurred
    logic [31:0] result;      // Computed value
} rob_entry_t;
```

**Allocation:** 2-wide allocation at dispatch, increments tail pointer

**Commit:** 2-wide commit from head, only when entries are ready and in-order

**Critical Bug Fixed:** 
1. **Multi-driver conflict:** `alloc_ok` driven by both `always_comb` and `always_ff` blocks
2. **Occupancy frozen:** Hardcoded `occupancy <= 1` prevented tracking
3. **Update logic wrong:** Occupancy updated inside commit conditional, never incremented during allocation

**Solution:** Moved occupancy update outside conditional:
```systemverilog
// WRONG (old):
if (commit_slots > 0) begin
    occupancy <= occupancy + alloc_count - commit_slots;
end

// CORRECT (new):
if (commit_slots > 0) begin
    head <= (head + commit_slots) % ROB_SIZE;
end
occupancy <= occupancy + alloc_count - commit_slots;  // Always update!
```

---

### **3. Load-Store Unit (LSU)**

**Purpose:** Execute memory operations out-of-order while maintaining memory ordering semantics

**Structure:**
- **Load Queue (LQ):** 16 entries, tracks in-flight loads
- **Store Queue (SQ):** 16 entries, tracks in-flight stores
- **Sequence Numbers:** 32-bit monotonic counter ensures ordering

**Memory Ordering Rules:**
1. **Loads** execute when all older stores have committed
2. **Stores** execute when all older stores have executed and are committed
3. **Sequence numbers** enforce these dependencies

**Implementation:**
```systemverilog
// Load execution check
automatic logic all_older_stores_committed = 1'b1;
for (int s = 0; s < SQ_ENTRIES; s++) begin
    if (sq[s].valid && sq[s].seq < lq[lq_search_idx].seq) begin
        if (!sq[s].committed) begin
            all_older_stores_committed = 1'b0;
            break;
        end
    end
end
if (all_older_stores_committed) begin
    // Execute load
    mem_req <= 1'b1;
    mem_we <= 1'b0;
    mem_addr <= lq[lq_search_idx].addr;
end
```

**Critical Bug Fixed:** Load results not broadcasting because `load_in_flight_idx` was truncated to 3 bits (range 0-7) instead of 4 bits (range 0-15). When load at lq[9] completed, it tried to broadcast from lq[1] instead.

**Solution:** Changed `load_in_flight_idx <= lq_search_idx[2:0]` to `load_in_flight_idx <= lq_search_idx` (full 4 bits).

---

### **4. Common Data Bus (CDB)**

**Purpose:** Broadcast computed results to wake up dependent instructions

**Arbitration:** Round-robin priority among 4 sources:
- ALU0 (port 0)
- ALU1 (port 1)
- Branch Unit (port 0/1)
- LSU (port 0/1)

**2 CDB ports** allow 2 simultaneous broadcasts per cycle

**Wakeup Logic:**
```systemverilog
// Issue queue wakeup (checks both CDB ports)
for (int i = 0; i < IQ_ENTRIES; i++) begin
    if (iq[i].valid) begin
        for (int j = 0; j < 2; j++) begin
            if (cdb_valid[j]) begin
                if (!iq[i].src1_ready && iq[i].src1_tag == cdb_tag[j]) begin
                    iq[i].src1_value <= cdb_value[j];
                    iq[i].src1_ready <= 1'b1;
                end
                if (!iq[i].src2_ready && iq[i].src2_tag == cdb_tag[j]) begin
                    iq[i].src2_value <= cdb_value[j];
                    iq[i].src2_ready <= 1'b1;
                end
            end
        end
    end
end
```

---

### **5. Branch Prediction**

**Components:**
- **Branch Target Buffer (BTB):** 64 entries, stores predicted PC
- **Branch History Table (BHT):** 512 entries, 2-bit saturating counters
- **Return Address Stack (RAS):** 8 entries (not yet implemented)

**Prediction Flow:**
1. Fetch stage: Look up PC in BTB
2. If hit: Use predicted target, update BHT on mispredict
3. If miss: Predict not-taken

**Mispredict Recovery:**
1. Branch unit computes actual target
2. If mispredict: Flush pipeline, restore RAT/free list, redirect fetch
3. Update BTB with correct target

**Known Issue:** Branch predictor updates not happening (commit signal not reaching predictor). Planned fix: Connect `rob_commit_is_branch` signal.

---

## 🗺️ Memory Map
```
0x00000000 - 0x00001FFF    ROM (8KB)          Instruction storage
0x00002000 - 0x00002FFF    Scratchpad (4KB)   Data storage (EBR)
0x00010000 - 0x0001000F    UART               Memory-mapped I/O
    0x10000: TX_DATA       Write to transmit
    0x10004: STATUS        Bit 0 = TX_BUSY (always 0 in stub)
    0x10008: RX_DATA       Read received data
```

---

## 🛠️ Building & Running

### **Prerequisites**
- Xilinx Vivado 2023.2+ (for Arty A7 FPGA)
- Icarus Verilog (for simulation)
- GTKWave (for waveform viewing)

### **Simulation**
```bash
# Compile and run testbench
iverilog -g2012 -o sim \
    superscalar_top.sv \
    core_pkg.sv \
    fetch.sv \
    decode.sv \
    rename.sv \
    dispatch.sv \
    rob.sv \
    issue_queue.sv \
    alu.sv \
    lsu.sv \
    branch_unit.sv \
    cdb_arbiter.sv \
    free_list.sv \
    inst_rom.sv \
    scratchpad.sv \
    uart_stub.sv \
    testbench.sv

# Run simulation
vvp sim

# View waveforms
gtkwave dump.vcd
```

### **FPGA Synthesis (Arty A7)**
```bash
# Open Vivado project
vivado superscalar_ooo.xpr

# Synthesize, implement, generate bitstream
# Flash to FPGA via USB
```

**Resource Usage (Arty A7-35T):**
- LUTs: ~18,000 / 20,800 (87%)
- FFs: ~12,000 / 41,600 (29%)
- Block RAM: 12 / 50 (24%)
- Fmax: ~50 MHz (clock constraint: 100 MHz, fails timing)

---

## ✅ Verification

### **Test Programs**
1. **Hello World (UART):** Stores string to scratchpad, transmits via UART
2. **Fibonacci:** Compute Fibonacci sequence, test ALU + branches
3. **Memory Test:** LDR/STR with various offsets, test LSU forwarding
4. **Branch Test:** Nested loops, test branch predictor accuracy

### **Debugging Tools**
- **Waveform Inspection:** GTKWave for cycle-by-cycle analysis
- **Print Statements:** `$display` for ROB/IQ/LSU state dumps
- **Assertions:** SystemVerilog assertions for structural checks

**Example Debugging Session (UART Bug):**
```
Problem: "Hello, LEGv8!" not appearing on UART
Investigation:
  1. Check scratchpad: String written correctly ✅
  2. Check loads: LDR executes, reads 'H' (0x48) ✅
  3. Check CDB: Broadcasts tag=p0 value=0x00 ❌ (should be p57=0x48)
Root Cause: load_in_flight_idx truncated to 3 bits, wraps at lq[7]
Fix: Use full 4-bit index for 16-entry load queue
Result: CDB now broadcasts correct tag/value, UART receives string ✅
```

---

## 💡 What I Learned

### **Technical Insights**
1. **Timing is everything:** Sequential logic must update in correct order (occupancy bug)
2. **Index width matters:** Truncated indices cause silent corruption (LSU bug)
3. **Context is king:** LLMs give generic solutions; humans understand system state
4. **Test early, test often:** Bugs compound—fix them immediately

### **Design Patterns**
1. **Round-robin allocation** prevents starvation (free list, CDB arbiter)
2. **Sequence numbers** enforce ordering without stalling (LSU)
3. **Separate allocation/commit** enables speculation (ROB)
4. **Tag broadcasting** implements Tomasulo efficiently (CDB)

### **Debugging Skills**
1. **Read waveforms, not code:** State machines fail in subtle ways
2. **Isolate components:** Test ROB alone, then integrate
3. **Print queue state:** Dump LQ/SQ/IQ contents at critical cycles
4. **Trust nothing:** Even "working" modules may have latent bugs

---

## 🚀 Future Work

### **Performance Improvements**
- [ ] Increase to 4-wide superscalar (fetch, issue, commit)
- [ ] Add hardware prefetcher for memory
- [ ] Implement store-to-load forwarding in LSU
- [ ] Add branch target cache (BTB) with higher associativity

### **Feature Additions**
- [ ] Floating-point unit (FPU) with separate register file
- [ ] L1 cache (I-cache + D-cache) with cache coherence
- [ ] AXI bus interface for external DRAM
- [ ] TinyTapeout submission (3x2 tiles, minimal OOO core)

### **Bug Fixes**
- [ ] Branch predictor update signal (connect `rob_commit_is_branch`)
- [ ] Load-to-use latency optimization (1-cycle loads for scratchpad)
- [ ] Exception handling (implement SVC syscall properly)

---

## 📚 References

**Books:**
- *Computer Organization and Design: ARM Edition* - Patterson & Hennessy
- *Computer Architecture: A Quantitative Approach* - Hennessy & Patterson
- *Modern Processor Design* - Shen & Lipasti

**Papers:**
- Tomasulo, R. M. (1967). "An Efficient Algorithm for Exploiting Multiple Arithmetic Units"
- Smith, J. E. & Sohi, G. S. (1995). "The Microarchitecture of Superscalar Processors"

**Online Resources:**
- [Onur Mutlu's YouTube Lectures](https://www.youtube.com/c/OnurMutluLectures)
- [Ben Eater's Breadboard Computer](https://eater.net/8bit)

---

## 📄 License

MIT License - Feel free to learn from, modify, and build upon this project.

---

## 🙏 Acknowledgments

Built solo as a learning project. Debugged with help from:
- Waveform traces (GTKWave)
- Print statement archaeology
- Late-night rubber duck debugging
- Claude.ai (for sanity checks and rubber ducking)

**No tutorial followed. No code copied. Every bug earned.**

---

**Last Updated:** March 2025  
**Status:** Functional, boots "Hello, LEGv8!" program successfully  
**Next Milestone:** TinyTapeout submission (Q2 2025)

