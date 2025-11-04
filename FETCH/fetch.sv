`timescale 1ns/1ps
import core_pkg::*;

module fetch (
  input  logic        clk,
  input  logic        reset,
  
  input  logic        fetch_en,
  input  logic        stall,
  input  logic        redirect_en,
  input  logic [XLEN-1:0] redirect_pc,
  
  // imem input
  input  logic [XLEN-1:0] imem_rdata0,
  input  logic [XLEN-1:0] imem_rdata1,
  input  logic [XLEN-1:0] imem_pc [1:0],
  input logic imem_valid,
  
  //decode output
  output logic [FETCH_WIDTH-1:0] if_valid,
  output logic [XLEN-1:0] if_pc  [FETCH_WIDTH-1:0],
  output logic [XLEN-1:0] if_instr [FETCH_WIDTH-1:0],
  
  //imem output
  output logic [XLEN-1:0] imem_addr0,
  output logic [XLEN-1:0] imem_addr1,
  output logic            imem_ren
  
);

  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] resp_pc0, resp_pc1;
  logic [XLEN-1:0] resp_instr0, resp_instr1;
  logic resp_valid;
  
  // Request tracking - NEW
  logic pending_request;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
      imem_ren <= 1'b0;
      pending_request <= 1'b0;  // NEW
    end else begin
      if (redirect_en) begin
        pc_reg <= redirect_pc;
        imem_ren <= 1'b0;
        pending_request <= 1'b0;  // Cancel pending request on redirect
      end else if (fetch_en && !stall) begin
        imem_addr0 <= pc_reg;
        imem_addr1 <= pc_reg + 32'd4;
        imem_ren <= 1'b1;
        pending_request <= 1'b1;  // Mark that we have a request pending
        pc_reg <= pc_reg + (4 * FETCH_WIDTH);
      end else begin
        imem_ren <= 1'b0;
        // Don't clear pending_request here - wait for response or redirect
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      resp_valid <= 1'b0;
      resp_pc0 <= '0;
      resp_pc1 <= '0;
      resp_instr0 <= '0;
      resp_instr1 <= '0;
      pending_request <= 1'b0;  // Also clear here for safety
    end else begin
      // Only accept response if we have a pending request AND imem says it's valid
      resp_valid <= pending_request && imem_valid && !redirect_en;
      
      if (pending_request && imem_valid && !redirect_en) begin
        resp_pc0 <= imem_pc[0];
        resp_pc1 <= imem_pc[1];
        resp_instr0 <= imem_rdata0;
        resp_instr1 <= imem_rdata1;
        pending_request <= 1'b0;  // Request completed
      end
      
      // Clear pending request on redirect (redundant but safe)
      if (redirect_en) begin
        pending_request <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
      if_pc[0] <= '0;
      if_pc[1] <= '0;
      if_instr[0] <= '0;
      if_instr[1] <= '0;
    end else if (!stall) begin
      if_valid <= {FETCH_WIDTH{resp_valid}};
      if_pc[0] <= resp_pc0;
      if_pc[1] <= resp_pc1;
      if_instr[0] <= resp_instr0;
      if_instr[1] <= resp_instr1;
    end else begin
      if_valid <= '0;
    end
  end

endmodule
