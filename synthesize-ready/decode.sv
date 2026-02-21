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
    
    // NEW: Flush signal
    input  logic                    flush_pipeline,

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
    output logic [FETCH_W-1:0]      dec_is_cas,
    
    // Additional outputs for ALU operations
    output logic [FETCH_W-1:0][5:0] dec_alu_func,
    output logic [FETCH_W-1:0][4:0] dec_shamt
);

    always_comb begin
        for (int i = 0; i < FETCH_W; i++) begin
            // Extract function field for R-type
            automatic logic [5:0] func_field = instr[i][5:0];
            
            // Defaults
            // Block decoding during flush
            dec_valid[i]      = instr_valid[i] & decode_ready & !flush_pipeline;
            dec_opcode[i]     = instr[i][31:26];
            dec_pc[i]         = pc[i];

            dec_rs1[i]        = 5'd0;
            dec_rs2[i]        = 5'd0;
            dec_rd[i]         = 5'd0;
            dec_imm[i]        = 32'd0;
            dec_alu_func[i]   = 6'd0;
            dec_shamt[i]      = 5'd0;

            dec_rs1_valid[i]  = 1'b0;
            dec_rs2_valid[i]  = 1'b0;
            dec_rd_valid[i]   = 1'b0;

            dec_is_alu[i]     = 1'b0;
            dec_is_load[i]    = 1'b0;
            dec_is_store[i]   = 1'b0;
            dec_is_branch[i]  = 1'b0;
            dec_is_cas[i]     = 1'b0;

            if (instr_valid[i] && decode_ready && !flush_pipeline) begin
                case (instr[i][31:26])

                    // R-type ALU
                    6'b000000: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_rs2[i]       = instr[i][15:11];
                        dec_shamt[i]     = instr[i][10:6];
                        dec_alu_func[i]  = func_field;

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_alu[i]    = 1'b1;
                    end

                    // I-type ALU
                    6'b001000, 6'b001001, 6'b001010, 6'b001011, 6'b001100: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_imm[i]       = {{16{instr[i][15]}}, instr[i][15:0]};

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;

                        dec_is_alu[i]    = 1'b1;
                    end

                    // Load instructions
                    6'b010000, 6'b010010: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_imm[i]       = {{16{instr[i][15]}}, instr[i][15:0]};

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;

                        dec_is_load[i]   = 1'b1;
                    end

                    // Store instructions
                    6'b010001, 6'b010011: begin
                        dec_rs1[i]       = instr[i][20:16];
                        dec_rs2[i]       = instr[i][25:21];
                        dec_imm[i]       = {{16{instr[i][15]}}, instr[i][15:0]};

                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_store[i]  = 1'b1;
                    end

                    // CAS (atomic)
                    6'b010100: begin
                        dec_rd[i]        = instr[i][25:21];
                        dec_rs1[i]       = instr[i][20:16];
                        dec_rs2[i]       = instr[i][15:11];

                        dec_rd_valid[i]  = 1'b1;
                        dec_rs1_valid[i] = 1'b1;
                        dec_rs2_valid[i] = 1'b1;

                        dec_is_cas[i]    = 1'b1;
                    end

                    // Unconditional Branches
                    6'b100000, 6'b100001: begin
                        dec_imm[i]       = {{6{instr[i][25]}}, instr[i][25:0], 2'b00};
                        dec_is_branch[i] = 1'b1;
                    end

                    // Conditional Branches
                    6'b100010, 6'b100011: begin
                        dec_rs1[i]       = instr[i][25:21];
                        dec_imm[i]       = {{11{instr[i][20]}}, instr[i][20:0], 2'b00};

                        dec_rs1_valid[i] = 1'b1;
                        dec_is_branch[i] = 1'b1;
                    end

                    // System / Special
                    6'b111000: begin
                        dec_imm[i]       = {{6{instr[i][25]}}, instr[i][25:0]};
                    end
                    
                    

                    default: begin
                        // Undefined opcodes
                        
                            dec_valid[i] = 1'b0;
                        
                    end
                endcase
            end
        end
    end

endmodule
