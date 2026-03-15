`timescale 1ns/1ps
import core_pkg::*;

module branch_ex #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS
)(
    input  logic                clk,
    input  logic                reset,
    input  logic                flush_pipeline,
    
    // Issue interface
    input  logic                issue_valid,
    input  logic [11:0]         issue_op,
    input  logic [PHYS_W-1:0]   issue_dst_tag,
    input  logic [XLEN-1:0]     issue_src1_val,
    input  logic [XLEN-1:0]     issue_src2_val,
    input  logic [XLEN-1:0]     issue_pc,
    input  logic [XLEN-1:0]     issue_imm,
    input  logic [5:0]          issue_rob_tag,
    
    // Branch result outputs
    output logic                branch_result_valid,
    output logic [PHYS_W-1:0]   branch_result_tag,
    output logic [XLEN-1:0]     branch_result_value,
    output logic [5:0]          branch_result_rob_tag,
    
    // Branch control outputs
    output logic                branch_taken,
    output logic [XLEN-1:0]     branch_target_pc,
    output logic                branch_mispredict
);

    // ============================================================
    //  Internal Signals
    // ============================================================
    logic [5:0] opcode;
    logic [5:0] func;
    logic taken;
    logic [XLEN-1:0] target_pc;
    logic [XLEN-1:0] return_addr;
    logic is_branch;
    
    assign opcode = issue_op[11:6];
    assign func = issue_op[5:0];
    
    // ============================================================
    //  Branch Decision Logic (Combinational)
    // ============================================================
    always_comb begin
        taken = 1'b0;
        target_pc = '0;
        return_addr = issue_pc + 4;
        is_branch = 1'b0;
        
        if (issue_valid) begin
            case (opcode)
                // B - Unconditional branch (opcode 0x20)
                6'b100000: begin
                    is_branch = 1'b1;
                    taken = 1'b1;
                    target_pc = issue_pc + issue_imm;
                end
                
                // BL - Branch and Link (opcode 0x21)
                6'b100001: begin
                    is_branch = 1'b1;
                    taken = 1'b1;
                    target_pc = issue_pc + issue_imm;
                end
                
                // CBZ - Compare and Branch if Zero (opcode 0x22)
                6'b100010: begin
                    is_branch = 1'b1;
                    taken = (issue_src1_val == '0);
                    target_pc = issue_pc + issue_imm;
                end
                
                // CBNZ - Compare and Branch if Non-Zero (opcode 0x23)
                6'b100011: begin
                    is_branch = 1'b1;
                    taken = (issue_src1_val != '0);
                    target_pc = issue_pc + issue_imm;
                end
                
                // RET - Return (R-type opcode 0x00, func 0x38)
                6'b000000: begin
                    if (func == 6'b111000) begin
                        is_branch = 1'b1;
                        taken = 1'b1;
                        target_pc = issue_src1_val; // Return address from X30
                    end
                end
                
                default: begin
                    is_branch = 1'b0;
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
            
        end else if (flush_pipeline) begin
            branch_result_valid <= 1'b0;
            branch_taken <= 1'b0;
            branch_mispredict <= 1'b0;
            
        end else begin
            // BL writes return address to X30
            if (issue_valid && opcode == 6'b100001) begin
                branch_result_valid <= 1'b1;
                branch_result_tag <= issue_dst_tag; // X30's physical reg
                branch_result_value <= return_addr;
                branch_result_rob_tag <= issue_rob_tag;
            end else begin
                branch_result_valid <= 1'b0;
                branch_result_tag <= '0;
                branch_result_value <= '0;
                branch_result_rob_tag <= '0;
            end
            
            // Branch control outputs
            branch_taken <= taken && is_branch;
            branch_target_pc <= target_pc;
            
            // For now: no prediction, so mispredict = taken (always predict not-taken)
            // TODO: Integrate with branch predictor
            branch_mispredict <= (taken && is_branch);
        end
    end

endmodule
