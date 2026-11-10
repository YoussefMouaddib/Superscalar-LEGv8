
module branch_ex #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS,
    parameter int ISSUE_W = 2,
    parameter int NUM_CHECKPOINTS = 8
)(
    input  logic clk,
    input  logic reset,
    input  logic flush_pipeline,

    input  logic [ISSUE_W-1:0] issue_valid,
    input  logic [ISSUE_W-1:0][11:0] issue_op,
    input  logic [ISSUE_W-1:0][PHYS_W-1:0] issue_dst_tag,
    input  logic [ISSUE_W-1:0][XLEN-1:0] issue_src1_val,
    input  logic [ISSUE_W-1:0][XLEN-1:0] issue_src2_val,
    input  logic [ISSUE_W-1:0][XLEN-1:0] issue_pc,
    input  logic [ISSUE_W-1:0][XLEN-1:0] issue_imm,
    input  logic [ISSUE_W-1:0][5:0] issue_rob_tag,
    input  logic [ISSUE_W-1:0][$clog2(NUM_CHECKPOINTS)-1:0]
        issue_checkpoint_id,

    output logic branch_result_valid,
    output logic [PHYS_W-1:0] branch_result_tag,
    output logic [XLEN-1:0] branch_result_value,
    output logic [5:0] branch_result_rob_tag,
    output logic is_call,
    output logic is_return,

    output logic branch_taken,
    output logic [XLEN-1:0] branch_target_pc,
    output logic branch_mispredict,

    output logic [$clog2(NUM_CHECKPOINTS)-1:0]
        restore_checkpoint_id,

    // NEW: every branch resolution, including correctly predicted branches
    output logic branch_resolve_valid,
    output logic [$clog2(NUM_CHECKPOINTS)-1:0]
        branch_resolve_id
);

    localparam int CP_W = $clog2(NUM_CHECKPOINTS);

    logic [ISSUE_W-1:0] is_branch_lane;
    logic branch_found;
    integer active_lane;

    logic [5:0] opcode, func;
    logic [XLEN-1:0] active_src1_val, active_pc, active_imm;
    logic [PHYS_W-1:0] active_dst_tag;
    logic [5:0] active_rob_tag;
    logic [CP_W-1:0] active_checkpoint_id;

    logic taken;
    logic [XLEN-1:0] target_pc;
    logic [XLEN-1:0] return_addr;

    // Identify branch instructions. Lane 0 has priority.
    always_comb begin
        is_branch_lane = '0;
        branch_found = 1'b0;
        active_lane = 0;

        for (int i = 0; i < ISSUE_W; i++) begin
            if (issue_valid[i]) begin
                case (issue_op[i][11:6])
                    6'b100000, 6'b100001,
                    6'b011000, 6'b011001:
                        is_branch_lane[i] = 1'b1;

                    6'b000000:
                        if (issue_op[i][5:0] == 6'b111000)
                            is_branch_lane[i] = 1'b1;

                    default: ;
                endcase
            end
        end

        for (int i = ISSUE_W-1; i >= 0; i--) begin
            if (is_branch_lane[i]) begin
                branch_found = 1'b1;
                active_lane = i;
            end
        end
    end

    // Select the oldest branch.
    always_comb begin
        opcode = '0;
        func = '0;
        active_src1_val = '0;
        active_pc = '0;
        active_imm = '0;
        active_dst_tag = '0;
        active_rob_tag = '0;
        active_checkpoint_id = '0;

        if (branch_found) begin
            opcode = issue_op[active_lane][11:6];
            func = issue_op[active_lane][5:0];
            active_src1_val = issue_src1_val[active_lane];
            active_pc = issue_pc[active_lane];
            active_imm = issue_imm[active_lane];
            active_dst_tag = issue_dst_tag[active_lane];
            active_rob_tag = issue_rob_tag[active_lane];
            active_checkpoint_id =
                issue_checkpoint_id[active_lane];
        end
    end

    // Branch decision.
    always_comb begin
        taken = 1'b0;
        target_pc = '0;
        return_addr = active_pc + 4;

        is_call = 1'b0;
        is_return = 1'b0;

        if (branch_found) begin
            case (opcode)
                6'b100000: begin // B
                    taken = 1'b1;
                    target_pc = active_pc + active_imm;
                end

                6'b100001: begin // BL
                    taken = 1'b1;
                    target_pc = active_pc + active_imm;
                    is_call = 1'b1;
                end

                6'b011000: begin // CBZ
                    taken = (active_src1_val == '0);
                    target_pc = active_pc + active_imm;
                end

                6'b011001: begin // CBNZ
                    taken = (active_src1_val != '0);
                    target_pc = active_pc + active_imm;
                end

                6'b000000: begin // RET
                    if (func == 6'b111000) begin
                        taken = 1'b1;
                        target_pc = active_src1_val;
                        is_return = 1'b1;
                    end
                end

                default: ;
            endcase
        end
    end

    // Registered branch results and checkpoint resolution.
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_result_valid <= 1'b0;
            branch_result_tag <= '0;
            branch_result_value <= '0;
            branch_result_rob_tag <= '0;

            branch_taken <= 1'b0;
            branch_target_pc <= '0;
            branch_mispredict <= 1'b0;
            restore_checkpoint_id <= '0;

            branch_resolve_valid <= 1'b0;
            branch_resolve_id <= '0;

        end else if (flush_pipeline) begin
            branch_result_valid <= 1'b0;
            branch_taken <= 1'b0;
            branch_mispredict <= 1'b0;
            branch_resolve_valid <= 1'b0;

        end else begin
            branch_result_valid <=
                branch_found && (opcode == 6'b100001);

            if (branch_found && opcode == 6'b100001) begin
                branch_result_tag <= active_dst_tag;
                branch_result_value <= return_addr;
                branch_result_rob_tag <= active_rob_tag;
            end else begin
                branch_result_tag <= '0;
                branch_result_value <= '0;
                branch_result_rob_tag <= '0;
            end

            branch_taken <= branch_found && taken;
            branch_target_pc <= target_pc;

            // No predictor: taken = misprediction, not-taken = correct.
            branch_mispredict <= branch_found && taken;

            // Resolve every branch, not only mispredicted branches.
            branch_resolve_valid <= branch_found;

            if (branch_found) begin
                branch_resolve_id <= active_checkpoint_id;
                restore_checkpoint_id <= active_checkpoint_id;
            end
        end
    end

endmodule
