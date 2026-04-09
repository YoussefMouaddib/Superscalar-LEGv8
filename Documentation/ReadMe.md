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
  - Renamed instruction bundle (includes physical `rs1`, `rs2`)

 ## Example
## Example: Rename Table Operation

### Initial State
- **All mappings**: ARCH 1 → PHYS 1, ARCH 2 → PHYS 2, etc.

### Cycle 1: Instruction `ADD R2, R1, R3`
- **Read sources**: `arch_rs1 = 1`, `arch_rs2 = 3` → `phys_rs1 = 1`, `phys_rs2 = 3`
- **Rename destination**: `rename_en = 1`, `arch_rd = 2`, `new_phys_rd = 40`
- **Result**: Current map now has **ARCH 2 → PHYS 40**

### Cycle 2: Instruction `SUB R5, R2, R4`
- **Read sources**: `arch_rs1 = 2` → `phys_rs1 = 40` (gets the NEW physical register)
- **Rename destination**: `rename_en = 1`, `arch_rd = 5`, `new_phys_rd = 41`
- **Result**: Current map: **ARCH 5 → PHYS 41**

### Cycle 3: ADD Instruction Commits
- **Commit**: `commit_en = 1`, `commit_arch_rd = 2`, `commit_phys_rd = 40`
- **Result**: Committed map now has **ARCH 2 → PHYS 40**

  
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
