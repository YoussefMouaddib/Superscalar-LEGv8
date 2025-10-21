// regfile_driver.sv
`timescale 1ns/1ps
import uvm_pkg::*;
import regfile_pkg::*;
import core_pkg::*;

class regfile_driver extends uvm_driver#(regfile_transaction);
  `uvm_component_utils(regfile_driver)

  virtual regfile_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual regfile_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", "virtual interface not found")
    end
  endfunction

  task run_phase(uvm_phase phase);
    regfile_transaction tr;
    forever begin
      seq_item_port.get_next_item(tr);

      // prepare to drive signals for this cycle
      // start with idle, then assert target lane fields
      vif.drive_idle();

      // drive this transaction onto the selected lane
      int l = tr.lane;
      // write port signals
      vif.wen[l]   <= tr.is_write;
      vif.wtag[l]  <= tr.tag;
      vif.wdata[l] <= tr.wdata;

      // sample one cycle so DUT can capture the write
      @(posedge vif.clk);
      // deassert to avoid unintended repeats
      vif.drive_idle();

      seq_item_port.item_done();
    end
  endtask

endclass : regfile_driver
