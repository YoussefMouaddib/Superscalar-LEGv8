`timescale 1ns/1ps
import core_pkg::*;

module tb_rob_golden;

  localparam int ROB_SIZE = core_pkg::ROB_ENTRIES;
  localparam int IDX_BITS = $clog2(ROB_SIZE);
  localparam int ISSUE_W = core_pkg::ISSUE_WIDTH;
  
  // Clock / reset
  logic clk;
  logic reset;

  // DUT I/O
  logic [ISSUE_W-1:0] alloc_en;
  logic [4:0]         alloc_arch_rd [ISSUE_W];
  preg_tag_t          alloc_phys_rd [ISSUE_W];
  logic               alloc_ok;
  logic [IDX_BITS-1:0] alloc_idx [ISSUE_W];

  logic               mark_ready_en;
  logic [IDX_BITS-1:0] mark_ready_idx;
  logic               mark_ready_val;
  logic               mark_exception;

  logic [ISSUE_W-1:0] commit_valid;
  logic [4:0]         commit_arch_rd [ISSUE_W];
  preg_tag_t          commit_phys_rd [ISSUE_W];
  logic [ISSUE_W-1:0] commit_exception;

  logic               rob_full;
  logic               rob_almost_full;
  logic               flush_en;
  logic [IDX_BITS-1:0] flush_ptr;

  // Golden model
  typedef struct packed {
    logic    valid;
    logic    ready;
    logic [4:0] arch_rd;
    preg_tag_t  phys_rd;
    logic    exception;
  } golden_entry_t;

  golden_entry_t golden_rob [0:ROB_SIZE-1];
  logic [IDX_BITS-1:0] golden_head, golden_tail;
  logic golden_rob_full, golden_rob_almost_full;
  logic [ISSUE_W-1:0] golden_commit_valid;
  logic [4:0] golden_commit_arch_rd [ISSUE_W];
  preg_tag_t  golden_commit_phys_rd [ISSUE_W];
  logic [ISSUE_W-1:0] golden_commit_exception;

  // Track allocated indices for wakeup
  logic [IDX_BITS-1:0] allocated_indices [$];
  int cycle_count = 0;

  // Instantiate DUT
  rob dut (.*);

  // Clock generator
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Initialize golden model
  task golden_reset();
    golden_head = '0;
    golden_tail = '0;
    for (int i = 0; i < ROB_SIZE; i++) begin
      golden_rob[i].valid = 1'b0;
      golden_rob[i].ready = 1'b0;
      golden_rob[i].exception = 1'b0;
    end
    allocated_indices.delete();
  endtask

  // Golden model allocation
  task golden_allocate();
    int reqs = 0;
    for (int i = 0; i < ISSUE_W; i++) 
      if (alloc_en[i]) reqs++;

    int free_slots = ROB_SIZE - ((golden_tail >= golden_head) ? 
                                (golden_tail - golden_head) : 
                                (ROB_SIZE - (golden_head - golden_tail)));

    if (reqs <= free_slots) begin
      for (int i = 0; i < ISSUE_W; i++) begin
        if (alloc_en[i]) begin
          golden_rob[golden_tail].valid = 1'b1;
          golden_rob[golden_tail].ready = 1'b0;
          golden_rob[golden_tail].arch_rd = alloc_arch_rd[i];
          golden_rob[golden_tail].phys_rd = alloc_phys_rd[i];
          golden_rob[golden_tail].exception = 1'b0;
          allocated_indices.push_back(golden_tail);
          golden_tail = (golden_tail + 1) % ROB_SIZE;
        end
      end
    end
  endtask

  // Golden model wakeup
  task golden_wakeup();
    if (mark_ready_en) begin
      if (golden_rob[mark_ready_idx].valid) begin
        if (mark_ready_val) golden_rob[mark_ready_idx].ready = 1'b1;
        if (mark_exception) golden_rob[mark_ready_idx].exception = 1'b1;
      end
    end
  endtask

  // Golden model commit
  task golden_commit();
    for (int i = 0; i < ISSUE_W; i++) begin
      golden_commit_valid[i] = 1'b0;
      golden_commit_arch_rd[i] = '0;
      golden_commit_phys_rd[i] = '0;
      golden_commit_exception[i] = 1'b0;
    end

    int commit_count = 0;
    logic [IDX_BITS-1:0] current_head = golden_head;

    for (int i = 0; i < ISSUE_W; i++) begin
      if (current_head != golden_tail && golden_rob[current_head].valid && golden_rob[current_head].ready) begin
        golden_commit_valid[i] = 1'b1;
        golden_commit_arch_rd[i] = golden_rob[current_head].arch_rd;
        golden_commit_phys_rd[i] = golden_rob[current_head].phys_rd;
        golden_commit_exception[i] = golden_rob[current_head].exception;
        
        golden_rob[current_head].valid = 1'b0;
        golden_rob[current_head].ready = 1'b0;
        golden_rob[current_head].exception = 1'b0;
        
        current_head = (current_head + 1) % ROB_SIZE;
        commit_count++;
      end else begin
        break;
      end
    end
    
    if (commit_count > 0) begin
      golden_head = current_head;
    end
  endtask

  // Check against golden model
  task check_golden(string context);
    // Check commits
    for (int i = 0; i < ISSUE_W; i++) begin
      if (commit_valid[i] !== golden_commit_valid[i]) begin
        $error("%s: commit_valid[%0d] mismatch: DUT=%0d, Golden=%0d", 
               context, i, commit_valid[i], golden_commit_valid[i]);
      end
      if (commit_valid[i] && golden_commit_valid[i]) begin
        if (commit_arch_rd[i] !== golden_commit_arch_rd[i]) begin
          $error("%s: commit_arch_rd[%0d] mismatch: DUT=%0d, Golden=%0d", 
                 context, i, commit_arch_rd[i], golden_commit_arch_rd[i]);
        end
        if (commit_phys_rd[i] !== golden_commit_phys_rd[i]) begin
          $error("%s: commit_phys_rd[%0d] mismatch: DUT=%0d, Golden=%0d", 
                 context, i, commit_phys_rd[i], golden_commit_phys_rd[i]);
        end
      end
    end

    // Check status flags
    golden_rob_full = (golden_head == golden_tail) && golden_rob[golden_head].valid;
    golden_rob_almost_full = ((golden_tail + ISSUE_W) % ROB_SIZE == golden_head);

    if (rob_full !== golden_rob_full) begin
      $error("%s: rob_full mismatch: DUT=%0d, Golden=%0d", context, rob_full, golden_rob_full);
    end
    if (rob_almost_full !== golden_rob_almost_full) begin
      $error("%s: rob_almost_full mismatch: DUT=%0d, Golden=%0d", context, rob_almost_full, golden_rob_almost_full);
    end
  endtask

  // Main test sequence - 50 cycles
  initial begin
    $display("=== Golden Model ROB Test (50 cycles) ===");
    
    // Initialize
    reset = 1;
    alloc_en = '0;
    mark_ready_en = 0;
    flush_en = 0;
    golden_reset();
    #20;
    reset = 0;
    #20;

    for (cycle_count = 0; cycle_count < 50; cycle_count++) begin
      // Random test patterns
      automatic int pattern = $urandom_range(0, 7);
      
      case (pattern)
        // Pattern 0-1: Normal allocation (40%)
        0,1: begin
          alloc_en = 2'b11;
          alloc_arch_rd[0] = $urandom_range(1, 31);
          alloc_phys_rd[0] = $urandom_range(1, 47);
          alloc_arch_rd[1] = $urandom_range(1, 31);
          alloc_phys_rd[1] = $urandom_range(1, 47);
        end
        
        // Pattern 2: Single allocation (20%)
        2: begin
          alloc_en = 2'b01;
          alloc_arch_rd[0] = $urandom_range(1, 31);
          alloc_phys_rd[0] = $urandom_range(1, 47);
          alloc_arch_rd[1] = '0;
          alloc_phys_rd[1] = '0;
        end
        
        // Pattern 3: Wakeup random entry (20%)
        3: begin
          alloc_en = '0;
          if (allocated_indices.size() > 0) begin
            mark_ready_en = 1;
            mark_ready_idx = allocated_indices[$urandom_range(0, allocated_indices.size()-1)];
            mark_ready_val = 1;
            mark_exception = 0;
          end else begin
            mark_ready_en = 0;
          end
        end
        
        // Pattern 4: Exception case (10%)
        4: begin
          alloc_en = '0;
          if (allocated_indices.size() > 0) begin
            mark_ready_en = 1;
            mark_ready_idx = allocated_indices[$urandom_range(0, allocated_indices.size()-1)];
            mark_ready_val = 1;
            mark_exception = 1;
          end else begin
            mark_ready_en = 0;
          end
        end
        
        // Pattern 5-7: No operation (30%)
        default: begin
          alloc_en = '0;
          mark_ready_en = 0;
        end
      endcase

      // Update golden model
      golden_allocate();
      golden_wakeup();
      golden_commit();

      #10; // Wait for DUT

      // Remove committed entries from tracking
      for (int i = 0; i < ISSUE_W; i++) begin
        if (commit_valid[i]) begin
          for (int j = 0; j < allocated_indices.size(); j++) begin
            if (allocated_indices[j] == dut.head - i) begin
              allocated_indices.delete(j);
              break;
            end
          end
        end
      end

      check_golden($sformatf("Cycle %0d", cycle_count));

      // Occasional flush (5% chance)
      if ($urandom_range(0, 19) == 0 && cycle_count > 10) begin
        $display("Cycle %0d: FLUSH triggered", cycle_count);
        flush_en = 1;
        flush_ptr = $urandom_range(0, ROB_SIZE-1);
        #10;
        flush_en = 0;
        golden_reset();
        #10;
      end
    end

    $display("=== Golden Model Test Complete ===");
    $finish;
  end

endmodule
