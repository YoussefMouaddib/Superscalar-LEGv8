# ![CpuI7GIF](https://github.com/user-attachments/assets/4eb98bca-c9c1-4a54-bd70-918482c4340f)
 **LEGv8 2-Wide Superscalar Out-of-Order Processor**
### *From Scratch: Silicon-Correct RTL to FPGA Verification*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![FPGA](https://img.shields.io/badge/Target-ColorLight%205A--75B-blue)](https://github.com/wuxx/ColorLight-FPGA)
[![Verilog](https://img.shields.io/badge/HDL-SystemVerilog-ff69b4)](https://en.wikipedia.org/wiki/SystemVerilog)
[![LUTs](https://img.shields.io/badge/LUTs-14k%2F24k-success)]()

---

## 📖 **Table of Contents**
- [The Vision](#-the-vision)
- [Architectural Highlights](#-architectural-highlights)
- [Microarchitecture Deep Dive](#-microarchitecture-deep-dive)
- [Pipeline Visualization](#-pipeline-visualization)
- [FPGA Implementation](#-fpga-implementation)
- [Verification Strategy](#-verification-strategy)
- [Instruction Set Support](#-instruction-set-support)
- [Waveform Gallery](#-waveform-gallery)
- [Lessons From the Trenches](#-lessons-from-the-trenches)
- [Getting Started](#-getting-started)

---

## 🎯 **The Vision**

> *"The best way to understand a microprocessor is to build one."*

This project represents a **complete from-scratch implementation** of a 2-wide superscalar out-of-order processor supporting the LEGv8 ISA (ARMv8 subset as presented in Patterson & Hennessy's Computer Organization and Design: ARM Edition). What makes this project unique is not just the final product, but the **depth of understanding** required to build every component from the ground up.

**Why build a superscalar CPU from scratch?**
- Master the **true complexity** of out-of-order execution
- Implement **register renaming**, **Tomasulo's algorithm**, and **speculative execution** at the RTL level
- Debug **pipeline hazards** at the waveform level
- Experience the **full design flow** from architectural specification to FPGA verification

---

## ✨ **Architectural Highlights**

| Feature | Implementation | Why It Matters |
|---------|---------------|----------------|
| **Superscalar Width** | 2-wide fetch, 2-wide issue, 2-wide commit | Balanced pipeline with minimal structural hazards |
| **Reorder Buffer** | 16 entries | Compact commit window fitting FPGA constraints |
| **Physical Registers** | 48 (32 arch + 16 rename) | Eliminates register renaming stalls for typical code |
| **Issue Queue** | 16-entry unified | Out-of-order wakeup with tag broadcast |
| **Load-Store Queue** | 8 loads + 8 stores | Full forwarding support, CAS atomic operations |
| **Branch Prediction** | 64-entry BTB + 512-entry BHT | 2-bit saturating counters with optional GShare |
| **Memory System** | 8KB I-ROM + 4KB D-scratchpad | Direct-mapped, single-cycle access in EBR |
| **Pipeline Stages** | 7 stages (F→D→R→Di→I→Ex→C) | Full bypassing, 1-cycle ALU, 2-cycle load |
| **Exceptions** | Full trap support, SVC syscall | Real exception handling for system software |

---

## 🔬 **Microarchitecture Deep Dive**

### **Pipeline Overview**
Fetch [F0,F1] → Decode [D0,D1] → Rename [R0,R1] → Dispatch [Di0,Di1] → Issue [I0,I1] → Execute → Commit [C0,C1]
↑ ↑ ↑ ↑ ↑ ↑ ↓
└───── Branch Predict ────────┴────── ROB Update ──────────────┴─── CDB ────┴─ LSU ────┘

### **The Rename Stage: Breaking False Dependencies**
```systemverilog
// Real rename logic from implementation
always_comb begin
    for (int i = 0; i < 2; i++) begin
        if (alloc_en[i]) begin
            // Map architectural to physical registers
            phys_src1[i] = rat[arch_rs1[i]];
            phys_src2[i] = rat[arch_rs2[i]];
            
            // Allocate new physical destination
            phys_dest[i] = free_list[free_head + i];
            
            // Update RAT for future instructions
            rat_next[arch_rd[i]] = phys_dest[i];
        end
    end
end
This is where out-of-order execution begins - breaking WAW/WAR hazards through register renaming. The Register Alias Table (RAT) maps architectural registers to physical registers, while the free list provides new physical destinations for each write.

## 📊 **Pipeline Visualization**
###**Instruction Flow Timeline**
Cycle:  0   1   2   3   4   5   6   7   8   9   10
       ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
ADD x1:│ F │ D │ R │ Di│ I │ Ex│ C │   │   │   │
       └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
       ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
ADD x3:│   │ F │ D │ R │ Di│ I │ Ex│ C │   │   │
       └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
       ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
STR x0:│   │   │ F │ D │ R │ Di│ I │ Ex│ Ex│ C │ ← 2-cycle store
       └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
       ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
LDR x8:│   │   │   │ F │ D │ R │ Di│ I │ L0│ L1│ C ← 2-cycle load
       └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘


