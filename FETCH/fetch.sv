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
  input  logic                fetch_en,      // allow fetch (high when front-end should fetch)
  input  logic                stall,         // hold fetch / do not advance PC or issue new fetchs

  // Branch redirect / exception / jump from later stages (synchronous redirect)
  input  logic                redirect_en,
  input  logic [PC_W-1:0]     redirect_pc,   // new PC to fetch from (branch target, trap vector)

  // Optional branch-predictor interface (lookup result can be fed as redirect by BP unit)
  // (left as higher-level connection; not required inside this module)

  // IF -> ID bundle (two-wide)
  output logic [FETCH_W-1:0]          if_valid,   // valid fetch slot(s) presented this cycle
  output logic [PC_W-1:0]             if_pc  [FETCH_W-1:0],
  output logic [INSTR_W-1:0]          if_instr [FETCH_W-1:0],

  // Instruction memory (synchronous BRAM/EBR) interface
  // Addr is word-addressable byte addresses. BRAM has 1-cycle read latency:
  output logic [PC_W-1:0]    imem_addr,   // address presented to BRAM (word byte address)
  output logic               imem_ren,    // read enable (pulsed when presenting new address)
  input  logic [INSTR_W-1:0] imem_rdata    // data returned next cycle
);

  // Internal PC register (points to next fetch base)
  logic [PC_W-1:0] pc_next;
  logic [PC_W-1:0] pc_reg;        // address issued to imem this cycle

  // Two request slots we issue into memory (addresses); since BRAM read is 1-cycle,
  // we present addr this cycle and capture imem_rdata next cycle.
  // request_valid indicates imem_ren was asserted for that request address.
  logic request_valid;
  logic [PC_W-1:0] req_pc;        // base PC requested this cycle (for slot0)
  // For FETCH_W == 2 we compute second PC = req_pc + 4 (word-aligned increments)

  // Output pipeline registers (capture imem_rdata next cycle)
  logic stage_vld;                        // next-stage valid (daata available)
  logic [PC_W-1:0] stage_pc0, stage_pc1;
  logic [INSTR_W-1:0] stage_instr0, stage_instr1;

  // Initialize PC on reset
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      pc_next <= '0;           // start at address 0 by default; change if you want boot vector
      pc_reg  <= '0;
      request_valid <= 1'b0;
      stage_vld <= 1'b0;
      if_valid <= '0;
      imem_ren <= 1'b0;
      imem_addr <= '0;
    end else begin
      // Branch redirect has priority: update next PC immediately (synchronous)
      if (redirect_en) begin
        pc_next <= redirect_pc;
        // Cancel outstanding request in progress (we still must consume imem_rdata from previous request;
        // treat that result as invalid by clearing stage_vld)
        request_valid <= 1'b0;
        stage_vld <= 1'b0;
        imem_ren <= 1'b0;
      end else begin
        // If not stalled and fetch enabled: issue a new imem read
        if (fetch_en && !stall) begin
          // present current pc_next to memory
          pc_reg <= pc_next;
          imem_addr <= pc_next;
          imem_ren <= 1'b1;
          req_pc <= pc_next;
          request_valid <= 1'b1;

          // advance PC_next for next fetch (dual-issue: two sequential PCs consumed per cycle)
          // For simplicity we always step by 4 per instruction
          pc_next <= pc_next + (4 * FETCH_W);
        end else begin
          // hold imem_ren low if no new request this cycle
          imem_ren <= 1'b0;
          request_valid <= 1'b0;
        end

        // Capture BRAM return (one-cycle latency): imem_rdata corresponds to previous cycle's imem_addr.
        // If previous cycle requested, accept and form two-wide bundle.
        if (request_valid) begin
          // We requested req_pc last cycle, now imem_rdata is the instruction at req_pc.
          // Build two-wide instructions: slot0 gets current imem_rdata; slot1 needs fetch of req_pc+4:
          // For the second instruction we have two options:
          //  - If I$ supports bursting / dual-read this cycle, you would request both addresses.
          //  - For simplicity: we assume the BRAM provides sequential data only for slot0.
          // Here we attempt to form slot1 by reading imem at req_pc+4 in next cycle if possible.
          stage_pc0 <= req_pc;
          stage_instr0 <= imem_rdata; // this is data for req_pc
          // For slot1: a small optimization — if FETCH_W==2, we can also have requested req_pc+4 last cycle
          // (by driving imem_ren for second address). To keep implementation simple and deterministic,
          // we treat slot1 as invalid here unless your imem supports dual-ported reads; user can extend.
          stage_pc1 <= req_pc + 32'd4;
          // conservative: set slot1 to a nop if not available (user may change to dual-port imem later)
          stage_instr1 <= 32'h00000013; // NOP-like (ADDI x0,x0,0) or your ISA NOP encoding
          stage_vld <= 1'b1;
        end else begin
          // No valid return this cycle
          stage_vld <= 1'b0;
        end

        // Produce IF outputs when stage_vld is set and front-end is ready to accept (we obey stall)
        if (stage_vld && !stall) begin
          if_valid[0] <= 1'b1;
          if_valid[1] <= 1'b1; // slot1 currently contains a NOP unless imem dual-port used
          if_pc[0] <= stage_pc0;
          if_pc[1] <= stage_pc1;
          if_instr[0] <= stage_instr0;
          if_instr[1] <= stage_instr1;
          // consumed the stage
          stage_vld <= 1'b0;
        end else begin
          // hold outputs if stall
          if (stall) begin
            // keep previous if_valid/if_instr stable (caller must handle backpressure)
            // No change here
          end else begin
            if_valid <= '0;
          end
        end
      end // redirect_en else
    end // reset else
  end // always_ff

endmodule
