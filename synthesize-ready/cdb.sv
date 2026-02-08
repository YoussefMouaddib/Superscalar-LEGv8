`timescale 1ns/1ps
import core_pkg::*;

module cdb_arbiter #(
    parameter int CDB_PORTS = 2,        // Number of CDB broadcast ports
    parameter int NUM_SOURCES = 4,      // Number of execution units
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS
)(
    input  logic                clk,
    input  logic                reset,

    // ============================================================
    // Inputs from Execution Units
    // ============================================================
    // Source 0: ALU0
    input  logic                     src0_valid,
    input  logic [PHYS_W-1:0]        src0_tag,
    input  logic [XLEN-1:0]          src0_value,
    input  logic [5:0]               src0_rob_tag,
    
    // Source 1: ALU1
    input  logic                     src1_valid,
    input  logic [PHYS_W-1:0]        src1_tag,
    input  logic [XLEN-1:0]          src1_value,
    input  logic [5:0]               src1_rob_tag,
    
    // Source 2: Branch Unit
    input  logic                     src2_valid,
    input  logic [PHYS_W-1:0]        src2_tag,
    input  logic [XLEN-1:0]          src2_value,
    input  logic [5:0]               src2_rob_tag,
    
    // Source 3: LSU
    input  logic                     src3_valid,
    input  logic [PHYS_W-1:0]        src3_tag,
    input  logic [XLEN-1:0]          src3_value,
    input  logic [5:0]               src3_rob_tag,

    // ============================================================
    // CDB Broadcast Outputs (to RS, ROB, PRF)
    // ============================================================
    output logic [CDB_PORTS-1:0]             cdb_valid,
    output logic [CDB_PORTS-1:0][PHYS_W-1:0] cdb_tag,
    output logic [CDB_PORTS-1:0][XLEN-1:0]   cdb_value,
    output logic [CDB_PORTS-1:0][5:0]        cdb_rob_tag
);

    // ============================================================
    // Internal Source Array (for easier indexing)
    // ============================================================
    logic [NUM_SOURCES-1:0]             src_valid;
    logic [NUM_SOURCES-1:0][PHYS_W-1:0] src_tag;
    logic [NUM_SOURCES-1:0][XLEN-1:0]   src_value;
    logic [NUM_SOURCES-1:0][5:0]        src_rob_tag;
    
    always_comb begin
        src_valid[0] = src0_valid;
        src_valid[1] = src1_valid;
        src_valid[2] = src2_valid;
        src_valid[3] = src3_valid;
        
        src_tag[0] = src0_tag;
        src_tag[1] = src1_tag;
        src_tag[2] = src2_tag;
        src_tag[3] = src3_tag;
        
        src_value[0] = src0_value;
        src_value[1] = src1_value;
        src_value[2] = src2_value;
        src_value[3] = src3_value;
        
        src_rob_tag[0] = src0_rob_tag;
        src_rob_tag[1] = src1_rob_tag;
        src_rob_tag[2] = src2_rob_tag;
        src_rob_tag[3] = src3_rob_tag;
    end
    
    // ============================================================
    // Round-Robin Arbitration State
    // ============================================================
    logic [1:0] priority_ptr;  // Points to highest priority source (rotates)
    
    // ============================================================
    // Arbitration Logic (Combinational)
    // ============================================================
    logic [NUM_SOURCES-1:0] granted;
    int grant_count;
    
    always_comb begin
        automatic logic [NUM_SOURCES-1:0] request;
        automatic int selected[CDB_PORTS];
        automatic logic [NUM_SOURCES-1:0] grant_mask;
        automatic int search_idx;
        automatic int port;
        
        // Initialize
        granted = '0;
        grant_mask = '0;
        grant_count = 0;
        for (int p = 0; p < CDB_PORTS; p++) begin
            selected[p] = -1;
        end
        
        // Collect requests
        request = src_valid;
        
        // ============================================================
        // Round-Robin Arbitration: Allocate CDB ports
        // Priority rotates based on priority_ptr
        // ============================================================
        for (port = 0; port < CDB_PORTS; port++) begin
            // Search starting from priority_ptr
            for (int offset = 0; offset < NUM_SOURCES; offset++) begin
                search_idx = (priority_ptr + offset) % NUM_SOURCES;
                
                // Grant if: requesting, not already granted, and slot available
                if (request[search_idx] && !grant_mask[search_idx]) begin
                    selected[port] = search_idx;
                    grant_mask[search_idx] = 1'b1;
                    granted[search_idx] = 1'b1;
                    grant_count++;
                    break;
                end
            end
        end
        
        // ============================================================
        // Drive CDB outputs based on grants
        // ============================================================
        for (port = 0; port < CDB_PORTS; port++) begin
            if (selected[port] != -1) begin
                cdb_valid[port] = 1'b1;
                cdb_tag[port] = src_tag[selected[port]];
                cdb_value[port] = src_value[selected[port]];
                cdb_rob_tag[port] = src_rob_tag[selected[port]];
            end else begin
                cdb_valid[port] = 1'b0;
                cdb_tag[port] = '0;
                cdb_value[port] = '0;
                cdb_rob_tag[port] = '0;
            end
        end
    end
    
    // ============================================================
    // Update Priority Pointer (Sequential)
    // Rotates to ensure fairness
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            priority_ptr <= 2'd0;
        end else begin
            // Advance priority pointer if any grants were made
            if (grant_count > 0) begin
                priority_ptr <= (priority_ptr + 1) % NUM_SOURCES;
            end
        end
    end
    
    // ============================================================
    // Optional: Performance Counter (grants per source)
    // ============================================================
    // synthesis translate_off
    logic [31:0] grant_count_per_source[NUM_SOURCES];
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                grant_count_per_source[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                if (granted[i]) begin
                    grant_count_per_source[i] <= grant_count_per_source[i] + 1;
                end
            end
        end
    end
    
    // Display stats every 1000 cycles
    logic [31:0] cycle_counter;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_counter <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (cycle_counter % 1000 == 0) begin
                $display("[CDB_ARB] Cycle %0d: Grants - ALU0:%0d ALU1:%0d BR:%0d LSU:%0d",
                    cycle_counter,
                    grant_count_per_source[0],
                    grant_count_per_source[1],
                    grant_count_per_source[2],
                    grant_count_per_source[3]);
            end
        end
    end
    // synthesis translate_on

endmodule
