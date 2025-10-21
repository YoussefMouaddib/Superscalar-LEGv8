// regfile_sequence.sv
`timescale 1ns/1ps
import uvm_pkg::*;
import regfile_pkg::*;

class regfile_sequencer extends uvm_sequencer#(regfile_transaction);
  `uvm_component_utils(regfile_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

class regfile_sequence extends uvm_sequence#(regfile_transaction);
  `uvm_object_utils(regfile_sequence)

  function new(string name = "regfile_sequence");
    super.new(name);
  endfunction

  task body();
    regfile_transaction tr;
    // example: create mixed read/write traffic
    repeat (500) begin
      tr = regfile_transaction::type_id::create("tr");
      // constrain addresses to a small range for easier checking in scoreboard
      if (!tr.randomize() with { tag inside {[0:15]}; lane inside {[0:1]}; })
        `uvm_warning("SEQ", "randomize failed")
      // bias writes a bit to populate regfile
      if ($urandom_range(0,3) == 0) tr.is_write = 1;
      else                            tr.is_write = 0;

      start_item(tr);
      // optionally tweak fields after start_item
      // e.g. ensure first few ops are writes
      finish_item(tr);
    end
  endtask
endclass : regfile_sequence
