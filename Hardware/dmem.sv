`timescale 1ns/1ps
import core_pkg::*;

module data_scratchpad #(
    parameter int MEM_SIZE = 512,     
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
        mem[4] = 32'd67;  // Test data at address 16 (0x10)
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
