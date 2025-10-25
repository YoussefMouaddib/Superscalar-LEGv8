### Example testbench for 4 instructions: 
 
## ROB Simulation Log

### Cycle 1
**Inputs**: alloc_en=11, mark_ready_en=0, mark_ready_idx=x  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=00, arch_rd[0]=0→phys_rd[0]=0, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=0, tail=0)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| All entries empty | | | | | |

### Cycle 2  
**Inputs**: alloc_en=11, mark_ready_en=0, mark_ready_idx=x  
**Outputs**: alloc_ok=1, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=1  
**Commits**: valid=00, arch_rd[0]=0→phys_rd[0]=0, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=0, tail=2)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 0 | 1 | 0 | 1 | 10 | 0 |
| 1 | 1 | 0 | 2 | 11 | 0 |

### Cycle 3
**Inputs**: alloc_en=00, mark_ready_en=0, mark_ready_idx=x  
**Outputs**: alloc_ok=1, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=2, [1]=3  
**Commits**: valid=00, arch_rd[0]=0→phys_rd[0]=0, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=0, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 0 | 1 | 0 | 1 | 10 | 0 |
| 1 | 1 | 0 | 2 | 11 | 0 |
| 2 | 1 | 0 | 3 | 12 | 0 |
| 3 | 1 | 0 | 4 | 13 | 0 |

### Cycle 4
**Inputs**: alloc_en=00, mark_ready_en=1, mark_ready_idx=0  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=00, arch_rd[0]=0→phys_rd[0]=0, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=0, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 0 | 1 | 0 | 1 | 10 | 0 |
| 1 | 1 | 0 | 2 | 11 | 0 |
| 2 | 1 | 0 | 3 | 12 | 0 |
| 3 | 1 | 0 | 4 | 13 | 0 |

### Cycle 5
**Inputs**: alloc_en=00, mark_ready_en=1, mark_ready_idx=1  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=00, arch_rd[0]=0→phys_rd[0]=0, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=0, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 0 | 1 | 1 | 1 | 10 | 0 |
| 1 | 1 | 0 | 2 | 11 | 0 |
| 2 | 1 | 0 | 3 | 12 | 0 |
| 3 | 1 | 0 | 4 | 13 | 0 |

### Cycle 6
**Inputs**: alloc_en=00, mark_ready_en=1, mark_ready_idx=2  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=01, arch_rd[0]=1→phys_rd[0]=10, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=1, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 1 | 1 | 1 | 2 | 11 | 0 |
| 2 | 1 | 0 | 3 | 12 | 0 |
| 3 | 1 | 0 | 4 | 13 | 0 |

### Cycle 7
**Inputs**: alloc_en=00, mark_ready_en=1, mark_ready_idx=3  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=01, arch_rd[0]=2→phys_rd[0]=11, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=2, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 2 | 1 | 1 | 3 | 12 | 0 |
| 3 | 1 | 0 | 4 | 13 | 0 |

### Cycle 8
**Inputs**: alloc_en=00, mark_ready_en=0, mark_ready_idx=3  
**Outputs**: alloc_ok=0, rob_full=0, rob_almost_full=0  
**Alloc Indices**: [0]=0, [1]=0  
**Commits**: valid=01, arch_rd[0]=3→phys_rd[0]=12, arch_rd[1]=0→phys_rd[1]=0  

**ROB Memory** (head=3, tail=4)
| Index | Valid | Ready | Arch RD | Phys RD | Exception |
|-------|-------|-------|---------|---------|-----------|
| 3 | 1 | 1 | 4 | 13 | 0 |
