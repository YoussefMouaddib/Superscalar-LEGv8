`timescale 1ns/1ps
import core_pkg::*;

module inst_rom #(
    parameter int ROM_SIZE = 8192,     // 8KB
    parameter int XLEN = 32
)(
    input  logic             clk,
    input  logic             reset,
    
    // Fetch interface (same as your current memory model)
    input  logic             imem_ren,
    input  logic [XLEN-1:0]  imem_addr0,
    input  logic [XLEN-1:0]  imem_addr1,
    
    output logic             imem_valid,
    output logic [XLEN-1:0]  imem_rdata0,
    output logic [XLEN-1:0]  imem_rdata1,
    output logic [XLEN-1:0]  imem_pc [1:0],
    
    // Optional: ROM programming interface (for loading programs)
    input  logic             prog_en,
    input  logic [XLEN-1:0]  prog_addr,
    input  logic [XLEN-1:0]  prog_data
);

    // ROM storage (implemented as EBR/BRAM)
    logic [XLEN-1:0] rom [0:(ROM_SIZE/4)-1];  // 2048 entries
    
    // Registered addresses for 1-cycle latency
    logic [XLEN-1:0] addr0_reg, addr1_reg;
    
    // ============================================================
    //  ROM Programming (for loading test programs)
    // ============================================================
    always_ff @(posedge clk) begin
        if (reset) begin
            // Initialize with NOPs or your test program
            for (int i = 0; i < (ROM_SIZE/4); i++) begin
                rom[i] <= '0;  // Default to NOP (opcode 111111)
            end
            
            // Load test program at reset (optional)
            // rom[0] <= {6'b000000, 5'd1, 5'd2, 5'd3, 5'd0, 6'b100000};  // ADD X1, X2, X3
            // rom[1] <= {6'b001000, 5'd4, 5'd5, 16'd100};               // ADDI X4, X5, #100
            // rom[2] <= {6'b010000, 5'd6, 5'd7, 16'd64};                // LDR X6, [X7, #64]
            // rom[3] <= {6'b010001, 5'd8, 5'd9, 16'hFFF0};              // STR X8, [X9, #65520]
            
        end else if (prog_en) begin
            // Program ROM at runtime (for testbench loading)
            rom[prog_addr[XLEN-1:2]] <= prog_data;
        end
    end
    
    // ============================================================
    //  Read Logic (1-cycle latency)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            imem_valid <= 1'b0;
            imem_rdata0 <= '0;
            imem_rdata1 <= '0;
            imem_pc[0] <= '0;
            imem_pc[1] <= '0;
            addr0_reg <= '0;
            addr1_reg <= '0;
        end else begin
            // Default: no valid response
            imem_valid <= 1'b0;
            
            // Handle read request
            if (imem_ren) begin
                // Save addresses for next cycle
                addr0_reg <= imem_addr0;
                addr1_reg <= imem_addr1;
                
                // Schedule response for next cycle (1-cycle latency)
                imem_valid <= 1'b1;
                
                // Read from ROM (word-aligned addresses)
                imem_rdata0 <= rom[imem_addr0[XLEN-1:2]];
                imem_rdata1 <= rom[imem_addr1[XLEN-1:2]];
                
                // Return the PCs (same as addresses)
                imem_pc[0] <= imem_addr0;
                imem_pc[1] <= imem_addr1;
                
                // Debug output
                $display("[IROM] Fetch: PC=%h, instr0=%h, instr1=%h", 
                        imem_addr0, rom[imem_addr0[XLEN-1:2]], rom[imem_addr1[XLEN-1:2]]);
            end
        end
    end
    
    // ============================================================
    //  Address Range Checking (optional)
    // ============================================================
    logic addr0_in_range, addr1_in_range;
    
    assign addr0_in_range = (imem_addr0[XLEN-1:2] < (ROM_SIZE/4));
    assign addr1_in_range = (imem_addr1[XLEN-1:2] < (ROM_SIZE/4));
    
    // Note: Out-of-range accesses return 0 (could trap if needed)

endmodule
