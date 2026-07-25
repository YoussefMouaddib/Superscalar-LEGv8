// uvm verif
`include "uvm_macros.svh"
import uvm_pkg::*;
//interface
interface freelist_if (input logic clk);
  logic         reset;
  logic [1:0]         alloc_en;
  logic [1:0][5:0]    alloc_phys;
  logic [1:0]         alloc_valid;
  logic [1:0]         free_en;
  logic [1:0][5:0]    free_phys;
endinterface

//sequence item
class freelist_seq_item extends uvm_sequence_item;
  rand bit [1:0]      alloc_en;
  rand bit [1:0]      free_en;
  rand bit [1:0][5:0] free_phys;

  // filled in by the monitor, not randomized — the DUT's response
  bit [1:0][5:0] alloc_phys;
  bit [1:0]      alloc_valid;

  `uvm_object_utils_begin(freelist_seq_item)
    `uvm_field_int(alloc_en,   UVM_ALL_ON)
    `uvm_field_int(free_en,    UVM_ALL_ON)
    `uvm_field_int(free_phys,  UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "freelist_seq_item");
    super.new(name);
  endfunction

  constraint c_free_range { foreach (free_phys[i]) free_phys[i] inside {[32:50]}; }
endclass

//sequence
class freelist_rand_seq extends uvm_sequence #(freelist_seq_item);
  `uvm_object_utils(freelist_rand_seq)

  function new(string name = "freelist_rand_seq");
    super.new(name);
  endfunction

  task body();
    repeat (300) begin
      freelist_seq_item req = freelist_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize())
        `uvm_error("SEQ", "randomize failed")
      finish_item(req);
    end
  endtask
endclass

//driver
class freelist_driver extends uvm_driver #(freelist_seq_item);
  `uvm_component_utils(freelist_driver)
  virtual freelist_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual freelist_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.alloc_en  = '0;
    vif.free_en   = '0;
    vif.free_phys = '0;
    @(negedge vif.reset);
    forever begin
      freelist_seq_item req;
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      vif.alloc_en  <= req.alloc_en;
      vif.free_en   <= req.free_en;
      vif.free_phys <= req.free_phys;
      seq_item_port.item_done();
    end
  endtask
endclass
    
//monitor
class freelist_monitor extends uvm_monitor;
  `uvm_component_utils(freelist_monitor)
  virtual freelist_if vif;
  uvm_analysis_port #(freelist_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual freelist_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      freelist_seq_item tr;
      @(posedge vif.clk);
      tr = freelist_seq_item::type_id::create("tr");
      tr.alloc_en    = vif.alloc_en;
      tr.free_en     = vif.free_en;
      tr.free_phys   = vif.free_phys;
      tr.alloc_valid = vif.alloc_valid;
      tr.alloc_phys  = vif.alloc_phys;
      ap.write(tr);
    end
  endtask
endclass
    
//scoreboard
class freelist_scoreboard extends uvm_subscriber #(freelist_seq_item);
  `uvm_component_utils(freelist_scoreboard)
  localparam int PHYS_REGS = 51;
  localparam int RENAME_START = 32;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  bit [PHYS_REGS-1:0] free_mask_model;     // mirrors DUT's free_mask
  bit [1:0]           free_en_r_model;     // mirrors DUT's free_en_r
  bit [1:0][5:0]      free_phys_r_model;   // mirrors DUT's free_phys_r
  bit                 have_prev;
  bit [1:0]           pred_valid;
  bit [1:0][5:0]      pred_phys;
  int unsigned        errors, checks;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    free_mask_model = '0;
    for (int i = RENAME_START; i < PHYS_REGS; i++) free_mask_model[i] = 1'b1;
    free_en_r_model = '0;
    have_prev = 0;
  endfunction

  function void write(freelist_seq_item t);
    bit [PHYS_REGS-1:0] temp_mask;
    bit [1:0][5:0]      a_phys;
    bit [1:0]           a_valid;

    if (have_prev) begin
      checks++;
      if (t.alloc_valid !== pred_valid || t.alloc_phys !== pred_phys) begin
        errors++;
        `uvm_error("SCBD", $sformatf(
          "MISMATCH: dut valid=%0b phys=%p  expected valid=%0b phys=%p",
          t.alloc_valid, t.alloc_phys, pred_valid, pred_phys))
      end
    end

    // build temp_mask exactly like the DUT: free_mask + PENDING frees held in free_en_r
    temp_mask = free_mask_model;
    for (int j = 0; j < 2; j++)
      if (free_en_r_model[j]) temp_mask[free_phys_r_model[j]] = 1'b1;

    // allocation decision, using THIS cycle's alloc_en against temp_mask
    a_valid = '0; a_phys = '0;
    if (t.alloc_en[0])
      for (int i = RENAME_START; i < PHYS_REGS; i++)
        if (temp_mask[i] && !a_valid[0]) begin a_phys[0] = i[5:0]; a_valid[0] = 1'b1; end
    if (t.alloc_en[1])
      for (int i = RENAME_START; i < PHYS_REGS; i++)
        if (temp_mask[i] && !a_valid[1] && !(a_valid[0] && i == a_phys[0])) begin
          a_phys[1] = i[5:0]; a_valid[1] = 1'b1;
        end

    // commit free_mask_model for next cycle: pending frees + this cycle's allocations
    for (int j = 0; j < 2; j++)
      if (free_en_r_model[j]) free_mask_model[free_phys_r_model[j]] = 1'b1;
    if (a_valid[0]) free_mask_model[a_phys[0]] = 1'b0;
    if (a_valid[1]) free_mask_model[a_phys[1]] = 1'b0;

    // advance the free_en_r pipeline register with THIS cycle's request, for use NEXT cycle
    free_en_r_model   = t.free_en;
    free_phys_r_model = t.free_phys;

    pred_valid = a_valid;
    pred_phys  = a_phys;
    have_prev  = 1;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCBD", $sformatf("checks=%0d errors=%0d", checks, errors), UVM_LOW)
  endfunction
endclass


    
//agent, env, test
class freelist_agent extends uvm_agent;
  `uvm_component_utils(freelist_agent)
  freelist_driver drv;
  freelist_monitor mon;
  uvm_sequencer #(freelist_seq_item) sqr;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = freelist_driver::type_id::create("drv", this);
    mon = freelist_monitor::type_id::create("mon", this);
    sqr = uvm_sequencer#(freelist_seq_item)::type_id::create("sqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

class freelist_env extends uvm_env;
  `uvm_component_utils(freelist_env)
  freelist_agent      agt;
  freelist_scoreboard scbd;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt  = freelist_agent::type_id::create("agt", this);
    scbd = freelist_scoreboard::type_id::create("scbd", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agt.mon.ap.connect(scbd.analysis_export);
  endfunction
endclass

class freelist_base_test extends uvm_test;
  `uvm_component_utils(freelist_base_test)
  freelist_env env;

  function new(string name = "freelist_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = freelist_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    freelist_rand_seq seq;
    phase.raise_objection(this);
    seq = freelist_rand_seq::type_id::create("seq");
    seq.start(env.agt.sqr);
    phase.drop_objection(this);
  endtask
endclass

//tb
module tb_top;
  logic clk = 0;
  always #5 clk = ~clk;

  freelist_if vif(clk);

  free_list #(
    .PHYS_REGS(51), .RENAME_START(32), .RENAME_REGS(19),
    .ALLOC_PORTS(2), .FREE_PORTS(2)
  ) dut (
    .clk(vif.clk), .reset(vif.reset),
    .alloc_en(vif.alloc_en), .alloc_phys(vif.alloc_phys), .alloc_valid(vif.alloc_valid),
    .free_en(vif.free_en), .free_phys(vif.free_phys)
  );

  initial begin
    vif.reset = 1;
    repeat (3) @(posedge clk);
    vif.reset = 0;
  end

  initial begin
    uvm_config_db#(virtual freelist_if)::set(null, "*", "vif", vif);
    run_test("freelist_base_test");
  end
endmodule
