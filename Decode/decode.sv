`timescale 1ns/1ps

module decode #(
    parameter int FETCH_W = 2
)(
    input  logic                    clk,
    input  logic                    reset,

    // Fetch inputs
    input  logic [FETCH_W-1:0]      instr_valid,
    input  logic [FETCH_W-1:0][31:0] instr,
    input  logic [FETCH_W-1:0][31:0] pc,

    // Backpressure from rename/dispatch
    input  logic                    decode_ready,

    // Decode outputs → Rename
    output logic [FETCH_W-1:0]      dec_valid,

    output logic [FETCH_W-1:0][5:0] dec_opcode,
    output logic [FETCH_W-1:0][4:0] dec_rs1,
    output logic [FETCH_W-1:0][4:0] dec_rs2,
    output logic [FETCH_W-1:0][4:0] dec_rd,

    output logic [FETCH_W-1:0][31:0] dec_imm,
    output logic [FETCH_W-1:0][31:0] dec_pc,

    // Operand usage
    output logic [FETCH_W-1:0]      dec_rs1_valid,
    output logic [FETCH_W-1:0]      dec_rs2_valid,
    output logic [FETCH_W-1:0]      dec_rd_valid,

    // Instruction class flags
    output logic [FETCH_W-1:0]      dec_is_alu,
    output logic [FETCH_W-1:0]      dec_is_load,
    output logic [FETCH_W-1:0]      dec_is_store,
    output logic [FETCH_W-1:0]      dec_is_branch,
    output logic [FETCH_W-1:0]      dec_is_cas
);

    integer i;

    always_comb begin
        for (i = 0; i < FETCH_W; i++) begin
            // Defaults
            dec_valid[i]      = instr_valid[i] & decode_ready;
            dec_opcode[i]     = instr[i][31:26];
            dec_pc[i]         = pc[i];

            dec_rs1[i]        = 5'd0;
            dec_rs2[i]        = 5'd0;
            dec_rd[i]         = 5'd0;
            dec_imm[i]        = 32'd0;

            dec_rs1_valid[i]  = 1'b0;
            dec_rs2_valid[i]  = 1'b0;
            dec_rd_valid[i]   = 1'b0;

            dec_is_alu[i]     = 1'b0;
            dec_is_load[i]    = 1'b0;
            dec_is_store[i]   = 1'b0;
            dec_is_branch[i]  = 1'b0;
            dec_is_cas[i]     = 1'b0;

            if (instr_valid[i] && decode_ready) begin
                case (instr[i][31:26])

                    // ======================
                    // R-type ALU
                    // ======================
                    6'b000000: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_rs2[i]       = instr[i][15:11];

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_alu[i]    = 1'b1;
                    end

                    // ======================
                    // I-type ALU
                    // ======================
                    6'b001000, // ADDI
                    6'b001001, // SUBI
                    6'b001010, // ANDI
                    6'b001011, // ORI
                    6'b001100: begin // EORI
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_imm[i]       = {{20{instr[i][15]}}, instr[i][15:4]};

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;

                        dec_is_alu[i]    = 1'b1;
                    end

                    // ======================
                    // Load / Store
                    // ======================
                    6'b010000: begin // LDR
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_imm[i]       = {{20{instr[i][15]}}, instr[i][15:4]};

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;

                        dec_is_load[i]   = 1'b1;
                    end

                    6'b010001: begin // STR
                        dec_rs1[i]       = instr[i][20:16]; // base
                        dec_rs2[i]       = instr[i][25:21]; // store data
                        dec_imm[i]       = {{20{instr[i][15]}}, instr[i][15:4]};

                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_store[i]  = 1'b1;
                    end

                    // ======================
                    // Branches
                    // ======================
                    6'b011000, // CBZ
                    6'b011001: begin // CBNZ
                        dec_rs1[i]       = instr[i][25:21];
                        dec_imm[i]       = {{11{instr[i][20]}}, instr[i][20:2], 2'b00};

                        dec_rs1_valid[i] = 1'b1;
                        dec_is_branch[i] = 1'b1;
                    end

                    6'b100000, // B
                    6'b100001: begin // BL
                        dec_imm[i]       = {{6{instr[i][25]}}, instr[i][25:0], 2'b00};
                        dec_is_branch[i] = 1'b1;
                    end

                    // ======================
                    // CAS (atomic)
                    // ======================
                    6'b101000: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_rs2[i]       = instr[i][15:11];

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_cas[i]    = 1'b1;
                    end

                    // ======================
                    // NOP / SVC
                    // ======================
                    6'b111000: begin
                        // no-op
                    end

                    default: begin
                        // treated as NOP
                    end
                endcase
            end
        end
    end

endmodule

