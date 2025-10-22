# 🧩 Module: `rename_stage.sv`


### **Description**
The `rename_stage` module handles **register renaming** — converting architectural register references from decoded instructions into physical register references.  
This eliminates **false dependencies (WAR/WAW)** and enables **out-of-order execution**.

It interacts with the **Rename Map Table (RMT)**, **Free List**, and **Reorder Buffer (ROB)** to allocate and track physical registers for instruction destinations.

---

### **Functionality**

- **Inputs:**
  - Decoded instruction fields (`rd`, `rs1`, `rs2`, opcode)
  - Control signals (`valid`, `flush`, `stall`)
- **Core Operations:**
  1. Reads the current architectural → physical mappings for source registers (`rs1`, `rs2`) from the RMT.
  2. Allocates a free physical register for the destination register (`rd`) from the Free List.
  3. Updates the RMT entry for `rd` with the newly allocated physical register.
  4. Outputs the renamed instruction (with physical register numbers) to the **Dispatch Stage**.
- **Outputs:**
  - Renamed instruction bundle (includes physical `rd`, `rs1`, `rs2`)
  - Valid and stall indicators

---

### **Verification**

**Testbench:** `tb_rename_stage.sv`

**Objective:** Verify correct renaming logic, free-list behavior, and rename table updates.

#### **Tests Performed**
1. **Basic Mapping Test:**  
   - Ensure `rs1` and `rs2` physical mappings are read correctly from RMT.
2. **Allocation Test:**  
   - Check that each destination register (`rd`) gets a new physical register allocation.
3. **Free List Exhaustion:**  
   - Simulate full PRF and confirm module signals stall/invalid rename.
4. **Rollback Simulation (for future):**  
   - Restore RMT snapshot to handle branch mispredictions or flush.

#### **Pass Criteria**
- Output physical registers match expected renamed values.  
- Rename Map Table updates correctly per instruction.  
- Free List count decrements after each rename.  
- Module handles stalls gracefully when no registers are available.

---

### **Next Stage**
After successful verification, the rename stage connects to:
- **Issue Queue (IQ):** For scheduling renamed instructions.
- **Reorder Buffer (ROB):** For tracking instruction completion and commit.

---
**Status:** ✅ Verified via SystemVerilog testbench `tb_rename_stage.sv`
