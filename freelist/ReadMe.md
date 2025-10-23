# ⛓️‍💥Free List Operation Example

## Initial State
- **Free Mask**: All 48 bits = 1 (all registers free)
- **Available**: PHYS 0, 1, 2, 3, ... 47

---

## Cycle 1: Instruction `ADD R1, R2, R3` (writes to R1)
- **Operation**: `alloc_en = 1`, needs 1 physical register
- **Search**: Finds PHYS 0 is free (lowest available)
- **Result**: 
  - `alloc_phys = 0`, `alloc_valid = 1`
  - **Free mask**: bit 0 = 0, others = 1

---

## Cycle 2: Instruction `SUB R5, R1, R4` (writes to R5)
- **Operation**: `alloc_en = 1`, needs 1 physical register
- **Search**: Finds PHYS 1 is free (next lowest)
- **Result**:
  - `alloc_phys = 1`, `alloc_valid = 1`
  - **Free mask**: bits 0,1 = 0, others = 1

---

## Cycle 3: Instruction `MUL R1, R5, R6` (writes to R1 again!)
- **Operations**:
  - `free_en = 1`, `free_phys = 0` (free old PHYS 0 from first ADD)
  - `alloc_en = 1`, needs new register for R1
- **Order**:
  1. **Free PHYS 0** (bit 0 = 1)
  2. **Allocate** - finds PHYS 0 is now free!
- **Result**:
  - `alloc_phys = 0`, `alloc_valid = 1`
  - **Free mask**: bits 1 = 0, others = 1 (PHYS 0 recycled!)

---

## Cycle 4: Instruction `DIV R2, R1, R7` (writes to R2)
- **Operation**: `alloc_en = 1`, needs 1 physical register
- **Search**: Finds PHYS 2 is free (lowest available)
- **Result**:
  - `alloc_phys = 2`, `alloc_valid = 1`
  - **Free mask**: bits 0,1,2 = 0, others = 1

---

## Final Mapping State
| Architectural Register | Physical Register |
|-----------------------|-------------------|
| R1                    | PHYS 0            |
| R5                    | PHYS 1            |
| R2                    | PHYS 2            |

## Key Features Demonstrated
- ✅ **Lowest available priority** - Always allocates smallest free number
- ✅ **Immediate recycling** - Freed registers available same cycle  
- ✅ **Concurrent operations** - Free + allocate work together
- ✅ **Speculative execution support** - Handles rename patterns
