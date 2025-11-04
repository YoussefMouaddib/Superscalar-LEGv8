`timescale 1ns/1ps
import core_pkg::*;

module fetch (
  input  logic        clk,
  input  logic        reset,
  input  logic        fetch_en,
  input  logic        stall,
  input  logic        redirect_en,
  input  logic [XLEN-1:0] redirect_pc,
  output logic [FETCH_WIDTH-1:0] if_valid,
  output logic [XLEN-1:0] if_pc  [FETCH_WIDTH-1:0],
  output logic [XLEN-1:0] if_instr [FETCH_WIDTH-1:0],
  output logic [XLEN-1:0] imem_addr0,
  output logic [XLEN-1:0] imem_addr1,
  output logic            imem_ren,
  input  logic [XLEN-1:0] imem_rdata0,
  input  logic [XLEN-1:0] imem_rdata1
);

  logic [XLEN-1:0] pc_reg;
  logic [XLEN-1:0] saved_pc0, saved_pc1;
  logic saved_valid;
  logic [XLEN-1:0] resp_pc0, resp_pc1;
  logic [XLEN-1:0] resp_instr0, resp_instr1;
  logic resp_valid;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_reg <= '0;
      imem_ren <= 1'b0;
      saved_valid <= 1'b0;
    end else begin
      if (redirect_en) begin
        pc_reg <= redirect_pc;
        imem_ren <= 1'b0;
        saved_valid <= 1'b0;
      end else if (fetch_en && !stall) begin
        imem_addr0 <= pc_reg;
        imem_addr1 <= pc_reg + 32'd4;
        imem_ren <= 1'b1;
        saved_pc0 <= pc_reg;
        saved_pc1 <= pc_reg + 32'd4;
        saved_valid <= 1'b1;
        pc_reg <= pc_reg + (4 * FETCH_WIDTH);
      end else begin
        imem_ren <= 1'b0;
        saved_valid <= 1'b0;
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
    end else begin
      resp_valid <= saved_valid && !redirect_en;
      if (saved_valid && !redirect_en) begin
        resp_pc0 <= saved_pc0;
        resp_pc1 <= saved_pc1;
        resp_instr0 <= imem_rdata0;
        resp_instr1 <= imem_rdata1;
      end
    end
  end

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      if_valid <= '0;
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
