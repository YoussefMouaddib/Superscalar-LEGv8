`timescale 1ns/1ps
import core_pkg::*;

module data_scratchpad #(
    parameter int MEM_SIZE = 4096,     
    parameter int XLEN = 32
)(
    input  logic             clk,
    input  logic             reset,
    
    // LSU interface
    input  logic             mem_req,
    input  logic             mem_we,
    input  logic [XLEN-1:0]  mem_addr,
    input  logic [XLEN-1:0]  mem_wdata,
    input  logic [1:0]       mem_size,   // Keep for compatibility but ignore
    input  logic             mem_atomic,
    input  logic [XLEN-1:0]  mem_cmp_val,
    
    output logic             mem_ready,
    output logic [XLEN-1:0]  mem_rdata,
    output logic             mem_error
);

    // Memory storage with BRAM inference
    (* ram_style = "block" *) 
    logic [XLEN-1:0] mem [0:(MEM_SIZE/4)-1];
    
    // Internal signals
    logic [XLEN-1:0] addr_word;
    logic [XLEN-1:0] read_data_reg;
    
    assign addr_word = mem_addr[XLEN-1:2];
    
    // ============================================================
    //  Memory Initialization (power-up only)
    // ============================================================
    initial begin
        for (int i = 0; i < (MEM_SIZE/4); i++) begin
            mem[i] = '0;
        end
         // String data starting at byte address 52 (word index 13)
    // "Superscalar LEGv8 Kernel is ON"
    mem[13] = 32'h00000053;  // 'S'  (addr 52)
    mem[14] = 32'h00000075;  // 'u'  (addr 56)
    mem[15] = 32'h00000070;  // 'p'  (addr 60)
    mem[16] = 32'h00000065;  // 'e'  (addr 64)
    mem[17] = 32'h00000072;  // 'r'  (addr 68)
    mem[18] = 32'h00000073;  // 's'  (addr 72)
    mem[19] = 32'h00000063;  // 'c'  (addr 76)
    mem[20] = 32'h00000061;  // 'a'  (addr 80)
    mem[21] = 32'h0000006C;  // 'l'  (addr 84)
    mem[22] = 32'h00000061;  // 'a'  (addr 88)
    mem[23] = 32'h00000072;  // 'r'  (addr 92)
    mem[24] = 32'h00000020;  // ' '  (addr 96)
    mem[25] = 32'h0000004C;  // 'L'  (addr 100)
    mem[26] = 32'h00000045;  // 'E'  (addr 104)
    mem[27] = 32'h00000047;  // 'G'  (addr 108)
    mem[28] = 32'h00000076;  // 'v'  (addr 112)
    mem[29] = 32'h00000038;  // '8'  (addr 116)
    mem[30] = 32'h00000020;  // ' '  (addr 120)
    mem[31] = 32'h0000004B;  // 'K'  (addr 124)
    mem[32] = 32'h00000065;  // 'e'  (addr 128)
    mem[33] = 32'h00000072;  // 'r'  (addr 132)
    mem[34] = 32'h0000006E;  // 'n'  (addr 136)
    mem[35] = 32'h00000065;  // 'e'  (addr 140)
    mem[36] = 32'h0000006C;  // 'l'  (addr 144)
    mem[37] = 32'h00000020;  // ' '  (addr 148)
    mem[38] = 32'h00000069;  // 'i'  (addr 152)
    mem[39] = 32'h00000073;  // 's'  (addr 156)
    mem[40] = 32'h00000020;  // ' '  (addr 160)
    mem[41] = 32'h0000004F;  // 'O'  (addr 164)
    mem[42] = 32'h0000004E;  // 'N'  (addr 168)
    mem[43] = 32'h00000000;  // '\0' (addr 172)
end
    end
    
    // ============================================================
    //  Synchronous Read (1-cycle latency)
    // ============================================================
    always_ff @(posedge clk) begin
        if (addr_word < (MEM_SIZE/4)) begin
            read_data_reg <= mem[addr_word];
        end else begin
            read_data_reg <= '0;
        end
    end
    
    // ============================================================
    //  Memory Access Logic
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mem_ready <= 1'b0;
            mem_rdata <= '0;
            mem_error <= 1'b0;
        end else begin
            // Defaults
            mem_ready <= 1'b0;
            mem_error <= 1'b0;
            
            if (mem_req) begin
                // Address range check
                if (addr_word >= (MEM_SIZE/4)) begin
                    mem_error <= 1'b1;
                    mem_ready <= 1'b1;
                    
                end else if (mem_we) begin
                    // Word write only
                    mem[addr_word] <= mem_wdata;
                    mem_ready <= 1'b1;
                    mem_rdata <= '0;
                    
                    // synthesis translate_off
                    $display("[SCRATCH] Write: addr=%h, data=%h", 
                            mem_addr, mem_wdata);
                    // synthesis translate_on
                    
                end else begin
                    // Read operation
                    mem_rdata <= read_data_reg;
                    mem_ready <= 1'b1;
                    
                    // synthesis translate_off
                    $display("[SCRATCH] Read: addr=%h, data=%h", 
                            mem_addr, read_data_reg);
                    // synthesis translate_on
                end
            end
        end
    end

endmodule
