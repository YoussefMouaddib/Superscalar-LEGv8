`timescale 1ns/1ps
import core_pkg::*;

module branch_ex #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int ISSUE_W = 2
)(
    input  logic                clk,
    input  logic                reset,
    input  logic                flush_pipeline,
    
    // Issue interface - accepts both lanes
    input  logic [ISSUE_W-1:0]              issue_valid,
    input  logic [ISSUE_W-1:0][11:0]        issue_op,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0]  issue_dst_tag,
    input  logic [ISSUE_W-1:0][XLEN-1:0]    issue_src1_val,
    input  logic [ISSUE_W-1:0][XLEN-1:0]    issue_src2_val,
    input  logic [ISSUE_W-1:0][XLEN-1:0]    issue_pc,
    input  logic [ISSUE_W-1:0][XLEN-1:0]    issue_imm,
    input  logic [ISSUE_W-1:0][5:0]         issue_rob_tag,
    
    // Branch result outputs (single result)
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
    // Lane Selection - Which lane has the branch?
    // ============================================================
    logic [ISSUE_W-1:0] is_branch_lane;
    logic branch_found;
    int active_lane;
    
    always_comb begin
        is_branch_lane = '0;
        branch_found = 1'b0;
        active_lane = 0;
        
        // Check each lane for branch instructions
        for (int i = 0; i < ISSUE_W; i++) begin
            if (issue_valid[i]) begin
                automatic logic [5:0] opcode = issue_op[i][11:6];
                automatic logic [5:0] func = issue_op[i][5:0];
                
                case (opcode)
                    6'b100000,  // B - Unconditional branch
                    6'b100001,  // BL - Branch and link
                    6'b011000,  // CBZ - Compare and branch if zero
                    6'b011001:  // CBNZ - Compare and branch if not zero
                        is_branch_lane[i] = 1'b1;
                    
                    6'b000000:  // R-type (check for RET)
                        if (func == 6'b111000)  // RET
                            is_branch_lane[i] = 1'b1;
                    
                    default: is_branch_lane[i] = 1'b0;
                endcase
            end
        end
        
        // Priority encode: lane 0 has priority if both have branches
        if (is_branch_lane[0]) begin
            branch_found = 1'b1;
            active_lane = 0;
        end else if (is_branch_lane[1]) begin
            branch_found = 1'b1;
            active_lane = 1;
        end
    end
    
    // ============================================================
    // Extract active lane signals
    // ============================================================
    logic [5:0] opcode;
    logic [5:0] func;
    logic [XLEN-1:0] active_src1_val;
    logic [XLEN-1:0] active_src2_val;
    logic [XLEN-1:0] active_pc;
    logic [XLEN-1:0] active_imm;
    logic [PHYS_W-1:0] active_dst_tag;
    logic [5:0] active_rob_tag;
    
    always_comb begin
        if (branch_found) begin
            opcode = issue_op[active_lane][11:6];
            func = issue_op[active_lane][5:0];
            active_src1_val = issue_src1_val[active_lane];
            active_src2_val = issue_src2_val[active_lane];
            active_pc = issue_pc[active_lane];
            active_imm = issue_imm[active_lane];
            active_dst_tag = issue_dst_tag[active_lane];
            active_rob_tag = issue_rob_tag[active_lane];
        end else begin
            opcode = '0;
            func = '0;
            active_src1_val = '0;
            active_src2_val = '0;
            active_pc = '0;
            active_imm = '0;
            active_dst_tag = '0;
            active_rob_tag = '0;
        end
    end
    
    // ============================================================
    // Branch Decision Logic (Combinational)
    // ============================================================
    logic taken;
    logic [XLEN-1:0] target_pc;
    logic [XLEN-1:0] return_addr;
    
    always_comb begin
        taken = 1'b0;
        target_pc = '0;
        return_addr = active_pc + 4;
        
        if (branch_found) begin
            case (opcode)
                // B - Unconditional branch (opcode 0x20)
                6'b100000: begin
                    taken = 1'b1;
                    target_pc = active_pc + active_imm;
                end
                
                // BL - Branch and Link (opcode 0x21)
                6'b100001: begin
                    taken = 1'b1;
                    target_pc = active_pc + active_imm;
                end
                
                // CBZ - Compare and Branch if Zero (opcode 0x18)
                6'b011000: begin
                    taken = (active_src1_val == '0);
                    target_pc = active_pc + active_imm;
                end
                
                // CBNZ - Compare and Branch if Non-Zero (opcode 0x19)
                6'b011001: begin
                    taken = (active_src1_val != '0);
                    target_pc = active_pc + active_imm;
                end
                
                // RET - Return (R-type opcode 0x00, func 0x38)
                6'b000000: begin
                    if (func == 6'b111000) begin
                        taken = 1'b1;
                        target_pc = active_src1_val; // Return address from X30
                    end
                end
                
                default: begin
                    taken = 1'b0;
                    target_pc = '0;
                end
            endcase
        end
    end
    
    // ============================================================
    // Pipeline Registers (1-cycle latency)
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
            if (branch_found && opcode == 6'b100001) begin
                branch_result_valid <= 1'b1;
                branch_result_tag <= active_dst_tag; // X30's physical reg
                branch_result_value <= return_addr;
                branch_result_rob_tag <= active_rob_tag;
            end else begin
                branch_result_valid <= 1'b0;
                branch_result_tag <= '0;
                branch_result_value <= '0;
                branch_result_rob_tag <= '0;
            end
            
            // Branch control outputs
            branch_taken <= taken && branch_found;
            branch_target_pc <= target_pc;
            
            // For now: no prediction, so mispredict = taken (always predict not-taken)
            // TODO: Integrate with branch predictor
            branch_mispredict <= (taken && branch_found);
        end
    end
    
    // ============================================================
    // Debug Display (synthesis off)
    // ============================================================
    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (branch_found && !reset && !flush_pipeline) begin
            $display("[BRANCH] lane=%0d opcode=%h pc=%h target=%h taken=%b imm=%h",
                active_lane, opcode, active_pc, target_pc, taken, active_imm);
        end
        
        if (branch_taken && !reset && !flush_pipeline) begin
            $display("[BRANCH_TAKEN] PC=%h → %h (mispredict=%b)",
                active_pc, branch_target_pc, branch_mispredict);
        end
    end
    // synthesis translate_on

endmodule
