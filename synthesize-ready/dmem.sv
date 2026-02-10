`timescale 1ns/1ps
import core_pkg::*;

module data_scratchpad #(
    parameter int MEM_SIZE = 4096,
    parameter int XLEN = 32
)(
    input  logic             clk,
    input  logic             reset,
    
    // LSU interface - WORD-ALIGNED ONLY
    input  logic             mem_req,
    input  logic             mem_we,
    input  logic [XLEN-1:0]  mem_addr,     // BYTE address but must be word-aligned
    input  logic [XLEN-1:0]  mem_wdata,
    output logic             mem_ready,
    output logic [XLEN-1:0]  mem_rdata,
    output logic             mem_error
);

    // Memory storage - WORD ACCESS ONLY
    logic [XLEN-1:0] mem [0:(MEM_SIZE/4)-1];
    
    // Simplified: only word address
    logic [XLEN-3:0] addr_word;  // mem_addr[XLEN-1:2]
    
    // CAS state machine
    typedef enum logic [1:0] {
        CAS_IDLE,
        CAS_READ,
        CAS_WRITE
    } cas_state_t;
    
    cas_state_t cas_state;
    logic [XLEN-1:0] cas_old_val;
    logic [XLEN-3:0] cas_addr;
    logic [XLEN-1:0] cas_cmp;
    logic [XLEN-1:0] cas_wdata;
    
    assign addr_word = mem_addr[XLEN-1:2];
    assign mem_error = (mem_req && mem_addr[1:0] != 2'b00) ? 1'b1 : 1'b0;  // Word alignment check
    
    // ============================================
    //  COMBINATIONAL READ PATH (for forwarding)
    // ============================================
    logic [XLEN-1:0] read_data_comb;
    assign read_data_comb = (addr_word < (MEM_SIZE/4)) ? mem[addr_word] : '0;
    
    // ============================================
    //  SEQUENTIAL LOGIC - 2 CYCLE CAS
    // ============================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cas_state <= CAS_IDLE;
            mem_ready <= 1'b0;
            mem_rdata <= '0;
            for (int i = 0; i < (MEM_SIZE/4); i++) mem[i] <= '0;
        end else begin
            // Defaults
            mem_ready <= 1'b0;
            
            // CAS State Machine
            case (cas_state)
                CAS_IDLE: begin
                    if (mem_req && !mem_error) begin
                        if (mem_atomic) begin
                            // Cycle 1: Save CAS operands
                            cas_addr <= addr_word;
                            cas_cmp <= mem_cmp_val;
                            cas_wdata <= mem_wdata;
                            cas_old_val <= read_data_comb;  // Read OLD value
                            cas_state <= CAS_WRITE;
                        end else if (mem_we) begin
                            // Single-cycle write
                            if (addr_word < (MEM_SIZE/4)) begin
                                mem[addr_word] <= mem_wdata;
                            end
                            mem_ready <= 1'b1;
                            mem_rdata <= '0;  // Writes return 0
                        end else begin
                            // Single-cycle read
                            mem_rdata <= read_data_comb;
                            mem_ready <= 1'b1;
                        end
                    end
                end
                
                CAS_WRITE: begin
                    // Cycle 2: Compare and conditionally write
                    if (cas_old_val == cas_cmp) begin
                        if (cas_addr < (MEM_SIZE/4)) begin
                            mem[cas_addr] <= cas_wdata;
                        end
                    end
                    // Always return old value
                    mem_rdata <= cas_old_val;
                    mem_ready <= 1'b1;
                    cas_state <= CAS_IDLE;
                end
            endcase
        end
    end
    
    // ============================================
    //  DEBUG/TRACE
    // ============================================
    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (mem_req && !mem_error && !reset) begin
            if (mem_atomic) begin
                if (cas_state == CAS_IDLE) begin
                    $display("[SCRATCH] CAS Start: addr=%h, cmp=%h, wdata=%h", 
                            mem_addr, mem_cmp_val, mem_wdata);
                end else if (cas_state == CAS_WRITE) begin
                    $display("[SCRATCH] CAS End: old=%h, success=%b", 
                            cas_old_val, (cas_old_val == cas_cmp));
                end
            end else if (mem_we) begin
                $display("[SCRATCH] Write: addr=%h, data=%h", mem_addr, mem_wdata);
            end else if (mem_ready) begin
                $display("[SCRATCH] Read: addr=%h, data=%h", mem_addr, mem_rdata);
            end
        end
    end
    // synthesis translate_on
    
endmodule
