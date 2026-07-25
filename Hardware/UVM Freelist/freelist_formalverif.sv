module freelist_fv #(
  parameter int PHYS_REGS    = 51,
  parameter int RENAME_START = 32,
  parameter int ALLOC_PORTS  = 2,
  parameter int FREE_PORTS   = 2
)(
  input logic clk,
  input logic reset,
  input logic [ALLOC_PORTS-1:0]       alloc_en,
  input logic [ALLOC_PORTS-1:0][5:0]  alloc_phys,
  input logic [ALLOC_PORTS-1:0]       alloc_valid,
  input logic [FREE_PORTS-1:0]        free_en,
  input logic [FREE_PORTS-1:0][5:0]   free_phys,
  // pull free_mask directly from the DUT through the bind port list
  input logic [PHYS_REGS-1:0]         free_mask
);

  // ============================================================
  // HELPER — count free registers from DUT's actual free_mask
  // ============================================================
  logic [$clog2(PHYS_REGS+1)-1:0] free_count;
  always_comb begin
    free_count = '0;
    for (int i = RENAME_START; i < PHYS_REGS; i++)
      free_count += free_mask[i];
  end

  // ============================================================
  // ASSUMPTIONS
  // ============================================================

  // freed register must be in the valid rename range
  always_comb begin
    for (int i = 0; i < FREE_PORTS; i++)
      if (free_en[i])
        assume (free_phys[i] >= RENAME_START[5:0] &&
                free_phys[i] <  PHYS_REGS[5:0]);
  end

  // two free ports can't free the same register simultaneously
  ap_no_double_free: assume property (
    @(posedge clk)
    (free_en[0] && free_en[1]) |-> (free_phys[0] != free_phys[1])
  );

  // ============================================================
  // ASSERTIONS
  // ============================================================

  // after reset deasserts, all rename registers are free within 1 cycle
  ap_reset_initializes: assert property (
    @(posedge clk)
    $fell(reset) |-> ##1 (free_count == (PHYS_REGS - RENAME_START))
  );

  // DUT never returns alloc_valid when the list is empty
  ap_no_valid_when_empty: assert property (
    @(posedge clk) disable iff (reset)
    (free_count == 0) |-> ##1 (alloc_valid == 2'b00)
  );

  // no valid output without a request
  ap_no_alloc_without_request_p0: assert property (
    @(posedge clk) disable iff (reset)
    !alloc_en[0] |-> ##1 !alloc_valid[0]
  );

  ap_no_alloc_without_request_p1: assert property (
    @(posedge clk) disable iff (reset)
    !alloc_en[1] |-> ##1 !alloc_valid[1]
  );

  // dual allocation must return two DIFFERENT registers
  // this is the one formal proves exhaustively that UVM cannot
  ap_no_duplicate_alloc: assert property (
    @(posedge clk) disable iff (reset)
    (alloc_valid == 2'b11) |-> (alloc_phys[0] != alloc_phys[1])
  );

  // allocated registers must be in the valid rename range
  ap_alloc_in_range_p0: assert property (
    @(posedge clk) disable iff (reset)
    alloc_valid[0] |->
      (alloc_phys[0] >= RENAME_START[5:0] && alloc_phys[0] < PHYS_REGS[5:0])
  );

  ap_alloc_in_range_p1: assert property (
    @(posedge clk) disable iff (reset)
    alloc_valid[1] |->
      (alloc_phys[1] >= RENAME_START[5:0] && alloc_phys[1] < PHYS_REGS[5:0])
  );

  // freed register reappears in free_mask within 2 cycles (1-cycle pipeline delay)
  ap_free_takes_effect: assert property (
    @(posedge clk) disable iff (reset)
    free_en[0] |-> ##2 free_mask[free_phys[0]]
  );

  // ============================================================
  // COVERS — prove these scenarios are reachable
  // ============================================================

  cp_dual_alloc: cover property (
    @(posedge clk) disable iff (reset)
    alloc_valid == 2'b11
  );

  cp_list_exhausted: cover property (
    @(posedge clk) disable iff (reset)
    free_count == 0
  );

  cp_free_then_alloc_same_cycle: cover property (
    @(posedge clk) disable iff (reset)
    (free_en != 2'b00 && alloc_en != 2'b00)
  );

endmodule
