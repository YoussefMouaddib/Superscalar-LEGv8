// regfile_agent_env_test.sv
`timescale 1ns/1ps
import uvm_pkg::*;
import regfile_pkg::*;
import core_pkg::*;

class regfile_agent extends uvm_component;
  `uvm_component_utils(regfile_agent)

  regfile_sequencer sequencer;
  regfile_driver    driver;
  regfile_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = regfile_sequencer::type_id::create("sequencer", this);
    driver    = regfile_driver::type_id::create("driver", this);
    monitor   = regfile_monitor::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // connect sequencer -> driver implicitly via uvm (driver uses seq_item_port)
  endfunction
endclass : regfile_agent

class regfile_env extends uvm_env;
  `uvm_component_utils(regfile_env)

  regfile_agent       agent;
  regfile_scoreboard  sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = regfile_agent::type_id::create("agent", this);
    sb    = regfile_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // hook monitor -> scoreboard
    uvm_config_db#(uvm_component)::set(this, "agent.monitor", "parent", this);
    super.connect_phase(phase);
    // connect monitor analysis port to scoreboard
    agent.monitor.ap.connect(sb.analysis_export);
  endfunction
endclass : regfile_env

// simple test that starts the regfile_sequence on the agent's sequencer
class regfile_test extends uvm_test;
  `uvm_component_utils(regfile_test)
  regfile_env env;

  function new(string name = "regfile_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = regfile_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    regfile_sequence seq = regfile_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #1000ns; // let traffic run (sequences have repeat), optional extra time
    phase.drop_objection(this);
  endtask
endclass : regfile_test
