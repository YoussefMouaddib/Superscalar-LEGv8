`timescale 1ns/1ps
import core_pkg::*;

module data_scratchpad #(
    parameter int MEM_SIZE = 4096,     // 4KB
    parameter int XLEN = 32
)(
    input  logic             clk,
    input  logic             reset,
    
    // LSU interface
    input  logic             mem_req,      // Memory request
    input  logic             mem_we,       // Write enable (1=write, 0=read)
    input  logic [XLEN-1:0]  mem_addr,     // Byte address
    input  logic [XLEN-1:0]  mem_wdata,    // Write data
    input  logic [1:0]       mem_size,     // 00=byte, 01=halfword, 10=word
    input  logic             mem_atomic,   // Atomic operation (CAS)
    input  logic [XLEN-1:0]  mem_cmp_val,  // Compare value for CAS
    
    output logic             mem_ready,    // Request accepted
    output logic [XLEN-1:0]  mem_rdata,    // Read data
    output logic             mem_error     // Access error
);

    // Memory storage with BRAM inference hint
    (* ram_style = "block" *) 
    logic [XLEN-1:0] mem [0:(MEM_SIZE/4)-1];  // 1024 words (4KB)
    
    // Internal signals
    logic [XLEN-1:0] addr_word;
    logic [1:0] addr_offset;
    logic [XLEN-1:0] read_data_reg;  // Registered read data for BRAM
    logic [XLEN-1:0] addr_word_reg;   // Registered address for read
    logic read_pending;
    
    assign addr_word = mem_addr[XLEN-1:2];   // Word address
    assign addr_offset = mem_addr[1:0];      // Byte offset
    
    // ============================================================
    //  Synchronous Read (BRAM inference)
    // ============================================================
    always_ff @(posedge clk) begin
        // Register address for next cycle read
        addr_word_reg <= addr_word;
        
        // Synchronous read from BRAM
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
            read_pending <= 1'b0;
            
            // Initialize memory to zeros
            for (int i = 0; i < (MEM_SIZE/4); i++) begin
                mem[i] <= '0;
            end
            mem[4] <= 32'd67;  // Test data at address 16 (0x10)
            
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
                    // Write operation
                    case (mem_size)
                        2'b00: begin // Byte write
                            case (addr_offset)
                                2'b00: mem[addr_word][7:0]   <= mem_wdata[7:0];
                                2'b01: mem[addr_word][15:8]  <= mem_wdata[7:0];
                                2'b10: mem[addr_word][23:16] <= mem_wdata[7:0];
                                2'b11: mem[addr_word][31:24] <= mem_wdata[7:0];
                            endcase
                        end
                        2'b01: begin // Halfword write
                            if (addr_offset[0] == 1'b0) begin  // 2-byte aligned
                                case (addr_offset)
                                    2'b00: mem[addr_word][15:0]  <= mem_wdata[15:0];
                                    2'b10: mem[addr_word][31:16] <= mem_wdata[15:0];
                                endcase
                            end else begin
                                mem_error <= 1'b1;  // Misaligned halfword
                            end
                        end
                        2'b10: begin // Word write
                            if (addr_offset == 2'b00) begin  // 4-byte aligned
                                mem[addr_word] <= mem_wdata;
                            end else begin
                                mem_error <= 1'b1;  // Misaligned word
                            end
                        end
                        default: begin
                            mem_error <= 1'b1;  // Invalid size
                        end
                    endcase
                    
                    mem_ready <= 1'b1;
                    mem_rdata <= '0;  // No read data for writes
                    
                    // synthesis translate_off
                    $display("[SCRATCH] Write: addr=%h, data=%h, size=%b",
                            mem_addr, mem_wdata, mem_size);
                    // synthesis translate_on
                    
                end else begin
                    // Read operation (use registered read data)
                    // Wait one cycle for BRAM read latency
                    if (read_pending) begin
                        // Data is ready from previous cycle
                        mem_rdata <= read_data_reg;
                        mem_ready <= 1'b1;
                        read_pending <= 1'b0;
                        
                        // synthesis translate_off
                        $display("[SCRATCH] Read: addr=%h, data=%h, size=%b",
                                mem_addr, read_data_reg, mem_size);
                        // synthesis translate_on
                    end else begin
                        // Initiate read
                        read_pending <= 1'b1;
                    end
                end
            end else begin
                read_pending <= 1'b0;
            end
        end
    end

endmodule
