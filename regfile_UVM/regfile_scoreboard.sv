// regfile_scoreboard.sv
`timescale 1ns/1ps
import uvm_pkg::*;
import regfile_pkg::*;
import core_pkg::*;

class regfile_scoreboard extends uvm_component;
  `uvm_component_utils(regfile_scoreboard)

  // implement analysis port to be connected to monitor
  uvm_analysis_imp#(regfile_transaction, regfile_scoreboard) analysis_export;

  // reference memory
  logic [XLEN-1:0] ref_mem [0:PREGS-1];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_export = new("analysis_export", this);
  endfunction

  // initialize ref mem on reset (optional)
  task reset_ref();
    for (int i = 0; i < PREGS; i++) ref_mem[i] = '0;
  endtask

  // Analysis write callback: receives both writes and reads from monitor
  function void write(regfile_transaction tr);
    // protect against out-of-range tags (shouldn't happen in well-formed tests)
    if (tr.tag >= PREGS) begin
      `uvm_error("SBOARD", $sformatf("Invalid tag %0d received", tr.tag))
      return;
    end

    if (tr.is_write) begin
      // observed write: update reference memory
      ref_mem[tr.tag] = tr.wdata;
    end else begin
      // observed read: compare against ref
      logic [XLEN-1:0] expect = ref_mem[tr.tag];
      if (expect !== tr.rdata) begin
        `uvm_error("SBOARD", $sformatf("Read miscompare at port %0d tag=%0d expect=0x%0h got=0x%0h",
                        tr.lane, tr.tag, expect, tr.rdata))
      end else begin
        `uvm_info("SBOARD", $sformatf("Read match port %0d tag=%0d value=0x%0h",
                         tr.lane, tr.tag, tr.rdata), UVM_LOW)
      end
    end
  endfunction

endclass : regfile_scoreboard
