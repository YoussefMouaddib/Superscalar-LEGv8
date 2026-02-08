`timescale 1ns/1ps
import core_pkg::*;

module alu #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS
)(
    input  logic                clk,
    input  logic                reset,
    
    // Issue interface (from Reservation Station)
    input  logic                issue_valid,
    input  logic [7:0]          issue_op,           // Opcode + function code
    input  logic [PHYS_W-1:0]   issue_dst_tag,      // Destination physical register
    input  logic [XLEN-1:0]     issue_src1_val,     // Source 1 value (or forwarded)
    input  logic [XLEN-1:0]     issue_src2_val,     // Source 2 value (or forwarded)
    input  logic [5:0]          issue_rob_tag,      // ROB index
    
    // CDB Broadcast for forwarding
    input  logic                cdb_valid,
    input  logic [PHYS_W-1:0]   cdb_tag,
    input  logic [XLEN-1:0]     cdb_value,
    
    // Register File Read port (optional - RS might already have values)
    input  logic [XLEN-1:0]     rf_rdata,
    
    // Result output to CDB
    output logic                alu_result_valid,
    output logic [PHYS_W-1:0]   alu_result_tag,
    output logic [XLEN-1:0]     alu_result_value,
    output logic [5:0]          alu_result_rob_tag,
    
    // Bypass outputs
    output logic                alu_bypass_valid,
    output logic [PHYS_W-1:0]   alu_bypass_tag,
    output logic [XLEN-1:0]     alu_bypass_value
);

    // ============================================================
    //  Internal Signals
    // ============================================================
    logic [XLEN-1:0] src1_val, src2_val;
    logic [XLEN-1:0] alu_result;
    logic result_valid;
    
    // Opcode decoding (from your instruction format)
    logic [5:0] opcode;
    logic [5:0] func_code;
    
    assign opcode = issue_op[7:2];    // bits 7:2 = opcode
    assign func_code = issue_op[5:0]; // bits 5:0 = function code for R-type
    
    // ============================================================
    //  ALU Combinational Logic
    // ============================================================
    always_comb begin
        // Default values
        alu_result = '0;
        result_valid = 1'b0;
        
        if (issue_valid) begin
            result_valid = 1'b1;
            
            // Decode based on opcode
            case (opcode)
                // R-TYPE instructions (opcode 000000)
                6'b000000: begin
                    case (func_code)
                        // ADD
                        6'b100000: alu_result = src1_val + src2_val;
                        
                        // SUB
                        6'b100010: alu_result = src1_val - src2_val;
                        
                        // AND
                        6'b100100: alu_result = src1_val & src2_val;
                        
                        // ORR
                        6'b100101: alu_result = src1_val | src2_val;
                        
                        // EOR
                        6'b100110: alu_result = src1_val ^ src2_val;
                        
                        // NEG (0 - src1_val)
                        6'b101000: alu_result = '0 - src1_val;
                        
                        // CMP (like SUB but result not used)
                        6'b101010: alu_result = src1_val - src2_val; // Flags handled separately
                        
                        // LSL (register)
                        6'b000000: alu_result = src1_val << src2_val[4:0];
                        
                        // LSR (register)
                        6'b000010: alu_result = src1_val >> src2_val[4:0];
                        
                        // LSL (immediate) - SHAMT in src2_val[4:0]
                        6'b000001: alu_result = src1_val << src2_val[4:0];
                        
                        // LSR (immediate) - SHAMT in src2_val[4:0]
                        6'b000011: alu_result = src1_val >> src2_val[4:0];
                        
                        // RET (branch unit handles this)
                        6'b111000: alu_result = src1_val; // Pass through for return address
                        
                        default: alu_result = '0;
                    endcase
                end
                
                // I-TYPE instructions
                // ADDI
                6'b001000: alu_result = src1_val + src2_val; // src2_val contains immediate
                
                // SUBI
                6'b001001: alu_result = src1_val - src2_val;
                
                // ANDI
                6'b001010: alu_result = src1_val & src2_val;
                
                // ORI
                6'b001011: alu_result = src1_val | src2_val;
                
                // EORI
                6'b001100: alu_result = src1_val ^ src2_val;
                
                // Default: pass through (for non-ALU ops)
                default: begin
                    alu_result = src1_val;
                    result_valid = 1'b0;
                end
            endcase
        end
    end
    
    // ============================================================
    //  Source Operand Selection (with CDB forwarding)
    // ============================================================
    always_comb begin
        // Default: use values from RS
        src1_val = issue_src1_val;
        src2_val = issue_src2_val;
        
        // Check CDB forwarding for src1
        if (cdb_valid && (cdb_tag == issue_dst_tag)) begin
            // Actually check source tags vs CDB tags
            // This is simplified - RS should handle most forwarding
        end
    end
    
    // ============================================================
    //  Pipeline Register (1-cycle latency)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_result_valid <= 1'b0;
            alu_result_tag <= '0;
            alu_result_value <= '0;
            alu_result_rob_tag <= '0;
            alu_bypass_valid <= 1'b0;
            alu_bypass_tag <= '0;
            alu_bypass_value <= '0;
        end else begin
            // Pipeline the result
            alu_result_valid <= result_valid;
            alu_result_tag <= issue_dst_tag;
            alu_result_value <= alu_result;
            alu_result_rob_tag <= issue_rob_tag;
            
            // Bypass: valid in same cycle for dependent instructions
            alu_bypass_valid <= result_valid;
            alu_bypass_tag <= issue_dst_tag;
            alu_bypass_value <= alu_result;
        end
    end
    
    // ============================================================
    //  Flag Generation (for CMP and conditional branches)
    // ============================================================
    logic zero_flag, negative_flag, overflow_flag, carry_flag;
    
    always_comb begin
        zero_flag = (alu_result == '0);
        negative_flag = alu_result[XLEN-1];
        
        // Overflow detection for ADD/SUB
        if (opcode == 6'b000000 && func_code == 6'b100000) begin // ADD
            overflow_flag = (src1_val[XLEN-1] == src2_val[XLEN-1]) && 
                           (src1_val[XLEN-1] != alu_result[XLEN-1]);
        end else if (opcode == 6'b000000 && func_code == 6'b100010) begin // SUB
            overflow_flag = (src1_val[XLEN-1] != src2_val[XLEN-1]) && 
                           (src1_val[XLEN-1] != alu_result[XLEN-1]);
        end else begin
            overflow_flag = 1'b0;
        end
    end

endmodule
