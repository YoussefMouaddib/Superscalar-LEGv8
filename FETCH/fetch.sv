`timescale 1ns/1ps
import core_pkg::*;

module fetch #(
  parameter int FETCH_W       = 2,
  parameter int PC_W          = 32,
  parameter int INSTR_W       = 32
)(
  input  logic                clk,
  input  logic                reset,

  // Control from pipeline/backpressure
  input  logic                fetch_en,      // allow fetch
  input  logic                stall,         // hold fetch outputs

  // Branch redirect
  input  logic                redirect_en,
  input  logic [PC_W-1:0]     redirect_pc,   // new PC to fetch from

  // IF -> ID bundle (two-wide)
  output logic [FETCH_W-1:0]          if_valid,   // valid fetch slots
  output logic [PC_W-1:0]             if_pc  [FETCH_W-1:0],
  output logic [INSTR_W-1:0]          if_instr [FETCH_W-1:0],

  // Instruction memory interface
  output logic [PC_W-1:0]    imem_addr0,    // First instruction address
  output logic [PC_W-1:0]    imem_addr1,    // Second instruction address  
  output logic               imem_ren,      // read enable
  input  logic [INSTR_W-1:0] imem_rdata0,   // First instruction data
  input  logic [INSTR_W-1:0] imem_rdata1    // Second instruction data
);

  // PC register - points to next fetch address
  logic [PC_W-1:0] pc_reg;

  // Saved PCs from request cycle
  logic [PC_W-1:0] saved_pc0, saved_pc1;
  logic saved_valid;

  // Pipeline registers for memory response
  logic [PC_W-1:0] resp_pc0, resp_pc1;
  logic [INSTR_W-1:0] resp_instr0, resp_instr1;
  logic resp_valid;

  // ============================================================
  //  PC Management and Memory Request
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
      imem_ren <= 1'b0;
      saved_valid <= 1'b0;
    end else begin
      // Branch redirect has highest priority
      if (redirect_en) begin
        pc_reg <= redirect_pc;
        imem_ren <= 1'b0; // Cancel any pending request
        saved_valid <= 1'b0; // Cancel saved request
      end 
      // Normal fetch operation
      else if (fetch_en && !stall) begin
        // Present addresses to instruction memory
        imem_addr0 <= pc_reg;
        imem_addr1 <= pc_reg + 32'd4;
        imem_ren <= 1'b1;
        
        // Save the PCs that were used for this request
        saved_pc0 <= pc_reg;
        saved_pc1 <= pc_reg + 32'd4;
        saved_valid <= 1'b1;
        
        // Advance PC for next fetch
        pc_reg <= pc_reg + (4 * FETCH_W);
      end else begin
        // No fetch this cycle
        imem_ren <= 1'b0;
        saved_valid <= 1'b0;
      end
    end
  end

  // ============================================================
  //  Memory Response Handling (1-cycle latency)
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      resp_valid <= 1'b0;
      resp_pc0 <= '0;
      resp_pc1 <= '0;
      resp_instr0 <= '0;
      resp_instr1 <= '0;
    end else begin
      // Capture memory response using the saved PCs from the request cycle
      resp_valid <= saved_valid && !redirect_en;
      
      if (saved_valid && !redirect_en) begin
        resp_pc0 <= saved_pc0;  // Use the PC from the original request
        resp_pc1 <= saved_pc1;
        resp_instr0 <= imem_rdata0;
        resp_instr1 <= imem_rdata1;
      end
    end
  end

  // ============================================================
  //  Output Stage
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
    end else if (!stall) begin
      // Deliver instructions to decode stage
      if_valid <= {FETCH_W{resp_valid}};
      if_pc[0] <= resp_pc0;
      if_pc[1] <= resp_pc1;
      if_instr[0] <= resp_instr0;
      if_instr[1] <= resp_instr1;
    end else begin
      // Stall - hold outputs or clear them
      if_valid <= '0;
    end
  end

endmodule
