`timescale 1ns/1ps
import core_pkg::*;

module fetch (
  input  logic        clk,
  input  logic        reset,
  
  input  logic        fetch_en,
  input  logic        stall,
  input  logic        redirect_en,
  input  logic [XLEN-1:0] redirect_pc,
  
  // imem input (from memory model)
  input  logic [XLEN-1:0] imem_rdata0,
  input  logic [XLEN-1:0] imem_rdata1,
  input  logic [XLEN-1:0] imem_pc [1:0],
  input  logic            imem_valid,
  
  // decode output - FIXED ARRAY PACKING
  output logic [FETCH_WIDTH-1:0] if_valid,
  output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_pc,      // FIXED: Correct packing
  output logic [FETCH_WIDTH-1:0][XLEN-1:0] if_instr,   // FIXED: Correct packing
  
  // imem output (to memory model)
  output logic [XLEN-1:0] imem_addr0,
  output logic [XLEN-1:0] imem_addr1,
  output logic            imem_ren
);

  // ============================================================
  //  PC Register and Request Generation
  // ============================================================
  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] pc_next;
  
  // Next PC calculation
  always_comb begin
    if (redirect_en) begin
      pc_next = redirect_pc;
    end else if (fetch_en && !stall && imem_ren) begin
      // Only advance if we successfully issued a request this cycle
      pc_next = pc_reg + 32'd8;
    end else begin
      pc_next = pc_reg;
    end
  end
  
  // PC register update
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
    end else begin
      pc_reg <= pc_next;
    end
  end
  
  // Memory request generation (combinational for immediate response)
  always_comb begin
    imem_addr0 = pc_reg;
    imem_addr1 = pc_reg + 32'd4;
    
    // Generate request if fetch enabled, not stalled, and no redirect
    imem_ren = fetch_en && !stall && !redirect_en;
  end
  
  // ============================================================
  //  Pipeline Stage: Memory Response → Output
  // ============================================================
  // This is a simple 1-stage pipeline from memory response to decode
  // Memory has 1-cycle latency, so total latency is 2 cycles from PC to output
  
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
      // FIXED: Proper array initialization
      for (int i = 0; i < FETCH_WIDTH; i++) begin
        if_pc[i] <= '0;
        if_instr[i] <= '0;
      end
    end else begin
      // Handle stall: freeze outputs
      if (stall) begin
        // Keep current values (if_valid, if_pc, if_instr remain unchanged)
      end 
      // Handle redirect: flush pipeline
      else if (redirect_en) begin
        if_valid <= '0;
        // Note: pc/instr can be left as-is since valid=0
      end
      // Normal operation: accept memory response
      else if (imem_valid) begin
        if_valid <= {FETCH_WIDTH{1'b1}};
        
        // Assign PC and instructions correctly
        // imem_pc[0] corresponds to imem_rdata0 (first instruction)
        // imem_pc[1] corresponds to imem_rdata1 (second instruction)
        // FIXED: Correct array assignment
        if_pc[0] <= imem_pc[0];
        if_pc[1] <= imem_pc[1];
        if_instr[0] <= imem_rdata0;
        if_instr[1] <= imem_rdata1;
      end
      // No valid response: clear outputs
      
    end
  end

endmodule
