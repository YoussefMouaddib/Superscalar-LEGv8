`timescale 1ns/1ps
import core_pkg::*;

module branch_ex #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS
)(
    input  logic                clk,
    input  logic                reset,
    
    // Issue interface
    input  logic                issue_valid,
    input  logic [7:0]          issue_op,
    input  logic [PHYS_W-1:0]   issue_dst_tag,
    input  logic [XLEN-1:0]     issue_src1_val,
    input  logic [XLEN-1:0]     issue_src2_val,
    input  logic [XLEN-1:0]     issue_pc,           // PC of branch instruction
    input  logic [XLEN-1:0]     issue_imm,          // Branch offset (already shifted <<2)
    input  logic [5:0]          issue_rob_tag,
    
    // CDB Broadcast
    input  logic                cdb_valid,
    input  logic [PHYS_W-1:0]   cdb_tag,
    input  logic [XLEN-1:0]     cdb_value,
    
    // Register File Read port
    input  logic [XLEN-1:0]     rf_rdata,
    
    // Branch result outputs
    output logic                branch_result_valid,
    output logic [PHYS_W-1:0]   branch_result_tag,
    output logic [XLEN-1:0]     branch_result_value,
    output logic [5:0]          branch_result_rob_tag,
    
    // Branch control outputs
    output logic                branch_taken,
    output logic [XLEN-1:0]     branch_target_pc,
    output logic                branch_mispredict,
    output logic                branch_is_call,
    output logic                branch_is_return
);

    // ============================================================
    //  Internal Signals
    // ============================================================
    logic [5:0] opcode;
    logic taken;
    logic [XLEN-1:0] target_pc;
    logic [XLEN-1:0] return_addr;
    logic mispredict;
    
    assign opcode = issue_op[7:2];
    
    // ============================================================
    //  Branch Decision Logic (Combinational)
    // ============================================================
    always_comb begin
        // Default values
        taken = 1'b0;
        target_pc = '0;
        return_addr = issue_pc + 4; // Default return address for BL
        mispredict = 1'b0;
        branch_is_call = 1'b0;
        branch_is_return = 1'b0;
        
        if (issue_valid) begin
            case (opcode)
                // B - Unconditional branch
                6'b100000: begin
                    taken = 1'b1;
                    target_pc = issue_pc + issue_imm;
                    // Assume always predicted taken, mispredict if predicted not-taken
                    mispredict = 1'b0; // Simplified - needs prediction logic
                end
                
                // BL - Branch and Link
                6'b100001: begin
                    taken = 1'b1;
                    target_pc = issue_pc + issue_imm;
                    branch_is_call = 1'b1;
                    // BL writes return address to X30
                    // return_addr already calculated above
                end
                
                // CBZ - Compare and Branch if Zero
                6'b100010: begin
                    taken = (issue_src1_val == '0);
                    target_pc = issue_pc + issue_imm;
                    // Assume predicted not-taken for CBZ/CBNZ
                    mispredict = (taken == 1'b1); // Mispredict if taken
                end
                
                // CBNZ - Compare and Branch if Non-Zero
                6'b100011: begin
                    taken = (issue_src1_val != '0);
                    target_pc = issue_pc + issue_imm;
                    // Assume predicted not-taken for CBZ/CBNZ
                    mispredict = (taken == 1'b1); // Mispredict if taken
                end
                
                // RET - Return (from function)
                6'b000000: begin // RET uses R-type with func=111000
                    if (issue_op[5:0] == 6'b111000) begin
                        taken = 1'b1;
                        target_pc = issue_src1_val; // Return address from register
                        branch_is_return = 1'b1;
                        // Assume predicted taken for RET
                        mispredict = 1'b0;
                    end
                end
                
                default: begin
                    // Not a branch instruction
                    taken = 1'b0;
                    target_pc = '0;
                end
            endcase
        end
    end
    
    // ============================================================
    //  Pipeline Registers (1-cycle latency)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_result_valid <= 1'b0;
            branch_result_tag <= '0;
            branch_result_value <= '0;
            branch_result_rob_tag <= '0;
            branch_taken <= 1'b0;
            branch_target_pc <= '0;
            branch_mispredict <= 1'b0;
            branch_is_call <= 1'b0;
            branch_is_return <= 1'b0;
        end else begin
            // Pipeline the results
            branch_result_valid <= issue_valid && 
                                 (opcode == 6'b100001 || // BL writes X30
                                  (opcode == 6'b000000 && issue_op[5:0] == 6'b111000)); // RET
            
            // For BL: write return address to X30
            if (opcode == 6'b100001) begin
                branch_result_tag <= issue_dst_tag; // Should be X30's physical reg
                branch_result_value <= return_addr;
            end else begin
                branch_result_tag <= '0;
                branch_result_value <= '0;
            end
            
            branch_result_rob_tag <= issue_rob_tag;
            branch_taken <= taken;
            branch_target_pc <= target_pc;
            branch_mispredict <= mispredict;
            branch_is_call <= branch_is_call;
            branch_is_return <= branch_is_return;
        end
    end

endmodule
