// regfile_pkg.sv  (updated)
`ifndef REGFILE_PKG_SV
`define REGFILE_PKG_SV
`include "uvm_macros.svh"
import core_pkg::*;
import uvm_pkg::*;

package regfile_pkg;
  import uvm_pkg::*;

  // transaction item for a single issue-lane operation (read or write)
  class regfile_transaction extends uvm_sequence_item;
    // lane: for write ports use 0..1. For read sampling ports use 0..3 (we keep 2 bits).
    rand bit [1:0]             lane;      // 0..3
    rand bit                   is_write;  // 1 = write, 0 = read (when used as observed write, is_write=1)
    rand core_pkg::preg_tag_t  tag;       // physical tag (target reg)
    rand logic [XLEN-1:0]      wdata;     // write data (valid if is_write==1)
    logic [XLEN-1:0]           rdata;     // observed read data (valid if is_write==0)

    function new(string name = "regfile_transaction");
      super.new(name);
    endfunction

    `uvm_object_utils(regfile_transaction)

    function string convert2string();
      return $sformatf("lane=%0d is_write=%0b tag=%0d wdata=0x%0h rdata=0x%0h",
                        lane, is_write, tag, wdata, rdata);
    endfunction
  endclass : regfile_transaction

endpackage : regfile_pkg
`endif

