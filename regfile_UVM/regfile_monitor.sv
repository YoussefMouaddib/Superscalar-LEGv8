// regfile_monitor.sv
`timescale 1ns/1ps
import uvm_pkg::*;
import regfile_pkg::*;
import core_pkg::*;

class regfile_monitor extends uvm_component;
  `uvm_component_utils(regfile_monitor)

  virtual regfile_if vif;
  uvm_analysis_port#(regfile_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual regfile_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", "virtual interface not found for monitor")
    end
  endfunction

  // We capture both write events (driven by driver) and the combinational read outputs each clock.
  task run_phase(uvm_phase phase);
    regfile_transaction tr;
    forever begin
      @(posedge vif.clk);
      // capture writes (both lanes)
      for (int l = 0; l < 2; l++) begin
        if (vif.wen[l]) begin
          tr = regfile_transaction::type_id::create("tr_write");
          tr.lane    = l;
          tr.is_write= 1;
          tr.tag     = vif.wtag[l];
          tr.wdata   = vif.wdata[l];
          ap.write(tr);
        end
      end

      // capture reads (all 4 combinational read ports: rtag[0..3], rdata[0..3])
      for (int r = 0; r < 4; r++) begin
        tr = regfile_transaction::type_id::create($sformatf("tr_read_%0d", r));
        tr.lane     = r;           // use lane field to indicate read port index
        tr.is_write = 0;
        tr.tag      = vif.rtag[r];
        tr.rdata    = vif.rdata[r];
        ap.write(tr);
      end
    end
  endtask

endclass : regfile_monitor
