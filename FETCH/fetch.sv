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

  // ============================================================
  //  STAGE 1: PC Management and Memory Request
  // ============================================================
  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] req_pc0, req_pc1;
  logic req_valid;
  
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
      imem_ren <= 1'b0;
      req_valid <= 1'b0;
      req_pc0 <= '0;
      req_pc1 <= '0;
    end else begin
      // Highest priority: branch redirect
      if (redirect_en) begin
        pc_reg <= redirect_pc;
        imem_ren <= 1'b0;
        req_valid <= 1'b0;
      end 
      // Normal fetch operation
      else if (fetch_en && !stall) begin
        // Drive memory request
        imem_addr0 <= pc_reg;
        imem_addr1 <= pc_reg + 32'd4;
        imem_ren <= 1'b1;
        
        // Save PCs for request tracking
        req_pc0 <= pc_reg;
        req_pc1 <= pc_reg + 32'd4;
        req_valid <= 1'b1;
        
        // Advance PC
        pc_reg <= pc_reg + 32'd8;
      end else begin
        // No fetch this cycle
        imem_ren <= 1'b0;
        req_valid <= 1'b0;
      end
    end
  end

  // ============================================================
  //  STAGE 2: Memory Response Handling 
  // ============================================================
  logic [XLEN-1:0] resp_pc0, resp_pc1;
  logic [XLEN-1:0] resp_instr0, resp_instr1;
  logic resp_valid;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      resp_valid <= 1'b0;
      resp_pc0 <= '0;
      resp_pc1 <= '0;
      resp_instr0 <= '0;
      resp_instr1 <= '0;
    end else begin
      // Only accept response if we had a valid request
      resp_valid <= req_valid && imem_valid && !redirect_en;
      
      if (req_valid && imem_valid && !redirect_en) begin
        resp_pc0 <= imem_pc[0];
        resp_pc1 <= imem_pc[1];
        resp_instr0 <= imem_rdata0;
        resp_instr1 <= imem_rdata1;
      end else begin
        resp_valid <= 1'b0;
      end
    end
  end

  // ============================================================
  //  STAGE 3: Output to Decode
  // ============================================================
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
      if_pc[0] <= '0;
      if_pc[1] <= '0;
      if_instr[0] <= '0;
      if_instr[1] <= '0;
    end else if (!stall) begin
      // Direct pipeline register - NO extra logic here
      if_valid <= {FETCH_WIDTH{resp_valid}};
      if_pc[0] <= resp_pc0;
      if_pc[1] <= resp_pc1;
      if_instr[0] <= resp_instr0;
      if_instr[1] <= resp_instr1;
    end else begin
      // Stall - clear valid but hold data (or clear both)
      if_valid <= '0;
    end
  end

endmodule
