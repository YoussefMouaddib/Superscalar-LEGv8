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

    // Memory storage (implemented as EBR/BRAM)
    logic [XLEN-1:0] mem [0:(MEM_SIZE/4)-1];  // 1024 words (4KB)
    
    // Internal signals
    logic [XLEN-1:0] addr_word;
    logic [1:0] addr_offset;
    logic [XLEN-1:0] read_data;
    logic atomic_pending;
    logic [XLEN-1:0] atomic_old_val;
    
    assign addr_word = mem_addr[XLEN-1:2];   // Word address
    assign addr_offset = mem_addr[1:0];      // Byte offset
    
    // ============================================================
    //  Memory Initialization
    // ============================================================
    initial begin
        // Initialize memory to zeros
        for (int i = 0; i < (MEM_SIZE/4); i++) begin
            mem[i] = '0;
        end
    end
    
    // ============================================================
    //  Memory Access Logic (Combinational Read)
    // ============================================================
    always_comb begin
        // Default read data (word-aligned)
        read_data = '0;
        
        // Check address range
        if (addr_word < (MEM_SIZE/4)) begin
            read_data = mem[addr_word];
        end
        
        // Handle misaligned accesses (optional)
        mem_error = 1'b0;
        if (mem_req) begin
            // Check word alignment for word accesses
            if (mem_size == 2'b10 && mem_addr[1:0] != 2'b00) begin
                mem_error = 1'b1;
            end
            // Check halfword alignment
            if (mem_size == 2'b01 && mem_addr[0] != 1'b0) begin
                mem_error = 1'b1;
            end
        end
    end
    
    // ============================================================
    //  Atomic Compare-and-Swap (CAS) Logic
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            atomic_pending <= 1'b0;
            atomic_old_val <= '0;
            mem_ready <= 1'b0;
            mem_rdata <= '0;
        end else begin
            // Default: not ready
            mem_ready <= 1'b0;
            
            if (mem_req && !mem_error) begin
                if (mem_atomic) begin
                    // CAS operation: compare and swap
                    atomic_old_val <= read_data;  // Save old value
                    
                    if (read_data == mem_cmp_val) begin
                        // Compare succeeds - write new value
                        if (addr_word < (MEM_SIZE/4)) begin
                            mem[addr_word] <= mem_wdata;
                        end
                    end
                    // CAS always returns old value
                    mem_rdata <= read_data;
                    mem_ready <= 1'b1;
                    
                    $display("[SCRATCH] CAS: addr=%h, cmp=%h, old=%h, new=%h, success=%b",
                            mem_addr, mem_cmp_val, read_data, mem_wdata, 
                            (read_data == mem_cmp_val));
                    
                end else if (mem_we) begin
                    // Write operation
                    if (addr_word < (MEM_SIZE/4)) begin
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
                                case (addr_offset)
                                    2'b00: mem[addr_word][15:0]  <= mem_wdata[15:0];
                                    2'b10: mem[addr_word][31:16] <= mem_wdata[15:0];
                                    default: mem_error <= 1'b1; // Misaligned
                                endcase
                            end
                            2'b10: begin // Word write
                                mem[addr_word] <= mem_wdata;
                            end
                            default: begin
                                // Invalid size
                            end
                        endcase
                    end
                    mem_ready <= 1'b1;
                    mem_rdata <= '0; // No read data for writes
                    
                    $display("[SCRATCH] Write: addr=%h, data=%h, size=%b",
                            mem_addr, mem_wdata, mem_size);
                    
                end else begin
                    // Read operation
                    mem_rdata <= read_data;
                    mem_ready <= 1'b1;
                    
                    $display("[SCRATCH] Read: addr=%h, data=%h, size=%b",
                            mem_addr, read_data, mem_size);
                end
            end
        end
    end
    
    // ============================================================
    //  Byte/Halfword Extraction for Reads
    // ============================================================
    logic [XLEN-1:0] final_rdata;
    
    always_comb begin
        final_rdata = mem_rdata;
        
        if (!mem_we && mem_ready) begin
            case (mem_size)
                2'b00: begin // Byte read
                    case (addr_offset)
                        2'b00: final_rdata = {{24{mem_rdata[7]}}, mem_rdata[7:0]};   // Sign-extend
                        2'b01: final_rdata = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                        2'b10: final_rdata = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                        2'b11: final_rdata = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                    endcase
                end
                2'b01: begin // Halfword read
                    case (addr_offset)
                        2'b00: final_rdata = {{16{mem_rdata[15]}}, mem_rdata[15:0]}; // Sign-extend
                        2'b10: final_rdata = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                        default: final_rdata = '0; // Misaligned
                    endcase
                end
                2'b10: begin // Word read
                    final_rdata = mem_rdata;
                end
                default: final_rdata = '0;
            endcase
        end
    end
    
    // Assign final output
    assign mem_rdata = final_rdata;

endmodule
