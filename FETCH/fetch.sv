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
  logic pending_request;

  // ============================================================
  //  STAGE 1: PC Management and Memory Request
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
      imem_ren <= 1'b0;
      pending_request <= 1'b0;
    end else begin
      if (redirect_en) begin
        pc_reg <= redirect_pc;
        imem_ren <= 1'b0;
        pending_request <= 1'b0;
      end else if (fetch_en && !stall) begin
        imem_addr0 <= pc_reg;
        imem_addr1 <= pc_reg + 32'd4;
        imem_ren <= 1'b1;
        pending_request <= 1'b1;
        pc_reg <= pc_reg + 32'd8;
      end else begin
        imem_ren <= 1'b0;
        // Keep pending_request until we get response or redirect
      end
    end
  end

  // ============================================================
  //  STAGE 2: Direct Output to Decode (NO USELESS REGISTERS)
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
      if_pc[0] <= '0;
      if_pc[1] <= '0;
      if_instr[0] <= '0;
      if_instr[1] <= '0;
    end else if (!stall) begin
      // DIRECT pipeline: imem response → outputs in SAME CYCLE
      if_valid <= {FETCH_WIDTH{(pending_request && imem_valid && !redirect_en)}};
      
      if (pending_request && imem_valid && !redirect_en) begin
        if_pc[0] <= imem_pc[0];
        if_pc[1] <= imem_pc[1];
        if_instr[0] <= imem_rdata0;
        if_instr[1] <= imem_rdata1;
        pending_request <= 1'b0;  // Request completed
      end else begin
        if_valid <= '0;
      end
    end else begin
      // Stall - clear outputs
      if_valid <= '0;
    end
  end

endmodule
