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
    output logic [1:0][XLEN-1:0]  imem_pc ,

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
                rom[i] <= '0;  // Default to 0
            end
        // ADDI X1, X0, #10 (0+10=10)
        rom[0] <= {6'b001000, 5'd1, 5'd0, 16'd10};
        
        // SUBI X15, X15, #4 (4-4=0, sets loop counter to 0)
        rom[1] <= {6'b001001, 5'd15, 5'd15, 16'd4};
        
        // ADD X3, X9, X5 (4+4=8)
        rom[2] <= {6'b000000, 5'd3, 5'd9, 5'd5, 5'd0, 6'b100000};
        
        // SUBI X4, X3, #2 (8-2=6) with x3 dependency
        rom[3] <= {6'b001001, 5'd4, 5'd3, 16'd2};
        
        // STR X2, [X4, #58] (fixed alignment: 6+58=64=0x40)
        rom[4] <= {6'b010001, 5'd2, 5'd4, 16'd58};
        
        // NOP
        rom[5] <= 32'hFFFFFFFF;
        
        // LDR X8, [X12, #12]
        rom[6] <= {6'b010000, 5'd8, 5'd12, 16'd12};
        
        // CBZ X15, #-7 (if X15==0, branch back to rom[0])
        // Offset = -7 words → PC = PC + (-7*4) = PC - 28
        // Current PC = 0x1C, target = 0x00 → offset = -7
            rom[7] <= {6'b011000, 5'd15, -19'sd7, 2'b00}; // -7 in 19-bit signed
        
        // ADDI X15, X15, #1 (increment loop counter, X15 becomes 1)
        rom[8] <= {6'b001000, 5'd15, 5'd15, 16'd1};
        
        // NOP
        rom[9] <= 32'hFFFFFFFF;
        
        // B #40 (unconditional jump to rom[50])
        // Current PC = 0x28, target = 0xC8 (rom[50]) → offset = (0xC8-0x28)/4 = 40
            rom[10] <= {6'b100000, 26'sd40};
        // Call a function
        rom[15] <= {6'b100001, 26'sd10};  // BL #10 (call function at +40 bytes)
        
        // Function body
        rom[25] <= {6'b001000, 5'd1, 5'd1, 16'd1};  // ADDI X1, X1, #1
        
        // Return
        rom[26] <= {6'b000000, 5'd0, 5'd30, 5'd0, 5'd0, 6'h38};  // RET (uses X30)
                     
        // B #-50 (unconditional jump back to rom[0])
        // Current PC = 0xC8, target = 0x00 → offset = (0x00-0xC8)/4 = -50
            rom[50] <= {6'b100000, -26'sd50}; // -50 in 26-bit signed (two's complement)
        
        // Fill remaining with NOPs
        for (int i = 51; i < 256; i++) begin
            rom[i] <= 32'd0;
        end
            
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

                // synthesis translate_off
                $display("[IROM] Fetch: PC=%h, instr0=%h, instr1=%h", 
                        imem_addr0, rom[imem_addr0[XLEN-1:2]], rom[imem_addr1[XLEN-1:2]]);
                // synthesis translate_on
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
/*
            // ADDI X1, X0, #10 (0+10=10)
            rom[0] <= {6'b001000, 5'd1, 5'd0, 16'd10};
            rom[1] <= 32'b11111111111111111111111111111111;
            // ADDI X2, X0, #5
            // rom[1] <= {6'b001000, 5'd2, 5'd0, 16'd5};
            // ADD X3, X9, X5 (4+4=8)
            rom[2] <= {6'b000000, 5'd3, 5'd9, 5'd5, 5'd0, 6'b100000};
            
            // SUBI X4, X3, #2 (8-2=6) with x3 depency
            rom[3] <= {6'b001001, 5'd4, 5'd3, 16'd2};
            // STR X2, [X4, #60] ram[62+6=68] = 4
            rom[4] <= {6'b010001, 5'd2, 5'd4, 16'd62};
            rom[5] <= 32'b11111111111111111111111111111111;
            // LDR X8, [X12, #12] x8 = ram[12+4= 16] = 67
            rom[6] <= {6'b010000, 5'd8, 5'd12, 16'd12};
            // NOP (repeat)
            for (int i=7; i<16; i++) rom[i] <= 32'b11111111111111111111111111111111;            

*/
