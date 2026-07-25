bind free_list freelist_fv #(
  .PHYS_REGS   (PHYS_REGS),
  .RENAME_START(RENAME_START),
  .ALLOC_PORTS (ALLOC_PORTS),
  .FREE_PORTS  (FREE_PORTS)
) fv_inst (
  .clk        (clk),
  .reset      (reset),
  .alloc_en   (alloc_en),
  .alloc_phys (alloc_phys),
  .alloc_valid(alloc_valid),
  .free_en    (free_en),
  .free_phys  (free_phys),
  .free_mask  (free_mask)   
);
