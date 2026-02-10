`timescale 1ns/1ps
module tb_data_scratchpad();

    localparam XLEN = 32;
    localparam MEM_SIZE = 4096;
    
    logic clk;
    logic reset;
    
    // DUT interface
    logic             mem_req;
    logic             mem_we;
    logic [XLEN-1:0]  mem_addr;
    logic [XLEN-1:0]  mem_wdata;
    logic             mem_atomic;
    logic [XLEN-1:0]  mem_cmp_val;
    
    logic             mem_ready;
    logic [XLEN-1:0]  mem_rdata;
    logic             mem_error;
    
    // Clock generation
    always #5 clk = ~clk;
    
    // DUT instantiation
    data_scratchpad #(
        .MEM_SIZE(MEM_SIZE),
        .XLEN(XLEN)
    ) dut (
        .clk(clk),
        .reset(reset),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_size(2'b10),  // Word-only now
        .mem_atomic(mem_atomic),
        .mem_cmp_val(mem_cmp_val),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_error(mem_error)
    );
    
    // Test sequence
    initial begin
        clk = 0;
        reset = 1;
        
        // Initialize signals
        mem_req = 0;
        mem_we = 0;
        mem_atomic = 0;
        mem_addr = '0;
        mem_wdata = '0;
        mem_cmp_val = '0;
        
        // Reset cycle
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        
        $display("=== TEST 1: Single Write (0x1000 = 0xDEADBEEF) ===");
        // Write to address 0x1000 (word-aligned)
        @(posedge clk);
        mem_req = 1;
        mem_we = 1;
        mem_addr = 32'h1000;  // Must be word-aligned
        mem_wdata = 32'hDEADBEEF;
        
        // Wait for ready
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        mem_req = 0;
        @(posedge clk);
        
        $display("Write complete. mem_ready=%b, mem_error=%b", mem_ready, mem_error);
        $display("Expected: mem[0x1000] = 0xDEADBEEF");
        $display("");
        
        // ============================================
        $display("=== TEST 2: Read back (0x1000) ===");
        @(posedge clk);
        mem_req = 1;
        mem_we = 0;
        mem_addr = 32'h1000;
        
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        $display("Read complete. mem_ready=%b, mem_rdata=%h", mem_ready, mem_rdata);
        if (mem_rdata !== 32'hDEADBEEF) begin
            $error("READ FAILED: Expected 0xDEADBEEF, got %h", mem_rdata);
        end else begin
            $display("READ PASS: Correct data");
        end
        $display("");
        
        mem_req = 0;
        @(posedge clk);
        
        // ============================================
        $display("=== TEST 3: CAS FAIL (compare with wrong value) ===");
        // Attempt CAS: compare with 0x12345678 (should fail)
        @(posedge clk);
        mem_req = 1;
        mem_atomic = 1;
        mem_we = 0;  // CAS overrides we
        mem_addr = 32'h1000;
        mem_cmp_val = 32'h12345678;  // Wrong value
        mem_wdata = 32'hCAFEBABE;    // New value (should not write)
        
        // CAS takes 2 cycles - wait for first ready
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        $display("CAS Cycle 2 complete. mem_ready=%b, mem_rdata=%h", mem_ready, mem_rdata);
        if (mem_rdata !== 32'hDEADBEEF) begin
            $error("CAS FAIL READ: Expected old value 0xDEADBEEF, got %h", mem_rdata);
        end else begin
            $display("CAS returned correct old value");
        end
        
        mem_req = 0;
        mem_atomic = 0;
        @(posedge clk);
        
        // Verify memory unchanged (read again)
        $display("Verifying CAS failed (memory unchanged)...");
        @(posedge clk);
        mem_req = 1;
        mem_we = 0;
        mem_addr = 32'h1000;
        
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        $display("Read after failed CAS: mem_rdata=%h", mem_rdata);
        if (mem_rdata !== 32'hDEADBEEF) begin
            $error("CAS FAIL: Memory changed when it shouldn't have");
        end else begin
            $display("CAS FAIL test PASS: Memory unchanged");
        end
        $display("");
        
        mem_req = 0;
        @(posedge clk);
        
        // ============================================
        $display("=== TEST 4: CAS SUCCESS ===");
        // CAS with correct compare value
        @(posedge clk);
        mem_req = 1;
        mem_atomic = 1;
        mem_addr = 32'h1000;
        mem_cmp_val = 32'hDEADBEEF;  // Correct value
        mem_wdata = 32'hCAFEBABE;    // New value
        
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        $display("CAS Success complete. mem_ready=%b, mem_rdata=%h", mem_ready, mem_rdata);
        if (mem_rdata !== 32'hDEADBEEF) begin
            $error("CAS SUCCESS READ: Expected old value 0xDEADBEEF, got %h", mem_rdata);
        end
        
        mem_req = 0;
        mem_atomic = 0;
        @(posedge clk);
        
        // Verify memory changed
        $display("Verifying CAS success (memory updated)...");
        @(posedge clk);
        mem_req = 1;
        mem_we = 0;
        mem_addr = 32'h1000;
        
        @(posedge clk);
        while (!mem_ready) @(posedge clk);
        
        $display("Read after successful CAS: mem_rdata=%h", mem_rdata);
        if (mem_rdata !== 32'hCAFEBABE) begin
            $error("CAS SUCCESS: Memory not updated. Expected 0xCAFEBABE, got %h", mem_rdata);
        end else begin
            $display("CAS SUCCESS test PASS: Memory correctly updated");
        end
        $display("");
        
        // ============================================
        $display("=== TEST 5: Error Case (misaligned address) ===");
        @(posedge clk);
        mem_req = 1;
        mem_we = 0;
        mem_addr = 32'h1001;  // NOT word-aligned!
        
        @(posedge clk);
        // Should get error immediately (combinational)
        $display("Misaligned access: mem_error=%b (should be 1)", mem_error);
        if (!mem_error) begin
            $error("ERROR DETECTION FAILED: Misaligned address not flagged");
        end
        
        // Wait a cycle anyway
        @(posedge clk);
        mem_req = 0;
        
        $display("");
        $display("=== ALL TESTS COMPLETE ===");
        
        #20;
        $finish;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("tb_data_scratchpad.vcd");
        $dumpvars(0, tb_data_scratchpad);
    end
    
    // Safety timeout
    initial begin
        #1000;
        $error("Testbench timeout");
        $finish;
    end
    
    // Monitor for X propagation
    always @(posedge clk) begin
        if (!reset) begin
            if (mem_rdata === 'x) begin
                $error("X detected on mem_rdata!");
            end
            if (mem_ready === 'x) begin
                $error("X detected on mem_ready!");
            end
        end
    end
    
endmodule
