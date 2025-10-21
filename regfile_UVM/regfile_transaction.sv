// regfile_transaction.sv
`timescale 1ns/1ps
`ifndef REGFILE_TRANSACTION_SV
`define REGFILE_TRANSACTION_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import core_pkg::*;   // XLEN, preg_tag_t, PREGS

// NOTE: this is a standalone transaction class file.
// If you already have a regfile_pkg.sv that defines the class, do NOT duplicate.
// Otherwise add this file and include it in compilation.

class regfile_transaction extends uvm_sequence_item;
  `uvm_object_utils(regfile_transaction)

  // transaction fields -- instruction-level view
  rand bit [1:0]             lane;    // 0..1 (issue lane). Use 2 bits to allow read ports index 0..3 if needed
  rand bit                   is_write; // 1 = write operation, 0 = read operation
  // source operands (two sources per instruction)
  rand core_pkg::preg_tag_t  src1_tag;
  rand core_pkg::preg_tag_t  src2_tag;
  // destination (physical) tag and write data
  rand core_pkg::preg_tag_t  dst_tag;
  rand logic [XLEN-1:0]      wdata;

  // fields populated by monitor (observed values)
  logic [XLEN-1:0]           src1_rdata;
  logic [XLEN-1:0]           src2_rdata;
  logic [XLEN-1:0]           dst_wdata_observed;

  // constructors
  function new(string name = "regfile_transaction");
    super.new(name);
  endfunction

  // pretty print for debug logs
  function string convert2string();
    return $sformatf("lane=%0d is_write=%0b src1=%0d src2=%0d dst=%0d wdata=0x%0h r1=0x%0h r2=0x%0h",
                     lane, is_write, src1_tag, src2_tag, dst_tag, wdata, src1_rdata, src2_rdata);
  endfunction

endclass : regfile_transaction

`endif // REGFILE_TRANSACTION_SV
