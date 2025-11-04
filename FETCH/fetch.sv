module fetch #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 32
)(
    input  logic                   clk_i,
    input  logic                   rst_ni,
    
    // Control signals
    input  logic                   fetch_en_i,
    input  logic                   stall_i,
    input  logic                   redirect_i,
    input  logic [ADDR_WIDTH-1:0]  redirect_pc_i,
    
    // Instruction memory interface
    output logic                   imem_ren_o,
    output logic [ADDR_WIDTH-1:0]  imem_addr0_o,
    output logic [ADDR_WIDTH-1:0]  imem_addr1_o,
    input  logic [INSTR_WIDTH-1:0] imem_rdata0_i,
    input  logic [INSTR_WIDTH-1:0] imem_rdata1_i,
    input  logic                   imem_rvalid_i,
    
    // Output to decode
    output logic [1:0]             if_valid_o,
    output logic [ADDR_WIDTH-1:0]  if_pc0_o,
    output logic [ADDR_WIDTH-1:0]  if_pc1_o,
    output logic [INSTR_WIDTH-1:0] if_instr0_o,
    output logic [INSTR_WIDTH-1:0] if_instr1_o
);

    logic [ADDR_WIDTH-1:0] pc_q, pc_d;
    logic [ADDR_WIDTH-1:0] next_pc;
    logic [ADDR_WIDTH-1:0] saved_pc0, saved_pc1;
    logic [INSTR_WIDTH-1:0] saved_instr0, saved_instr1;
    logic saved_valid0, saved_valid1;
    logic fetching;

    // PC update logic
    always_comb begin
        if (redirect_i) begin
            next_pc = redirect_pc_i;
        end else if (fetch_en_i && !stall_i) begin
            next_pc = pc_q + 8; // 2 instructions per cycle
        end else begin
            next_pc = pc_q;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_q <= '0;
        end else begin
            pc_q <= next_pc;
        end
    end

    // Memory interface
    assign imem_ren_o = fetch_en_i && !redirect_i;
    assign imem_addr0_o = pc_q;
    assign imem_addr1_o = pc_q + 4;

    // Output register - FIXED: Track PCs along with instructions
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            saved_pc0 <= '0;
            saved_pc1 <= '0;
            saved_instr0 <= '0;
            saved_instr1 <= '0;
            saved_valid0 <= 1'b0;
            saved_valid1 <= 1'b0;
        end else if (!stall_i) begin
            if (redirect_i) begin
                // On redirect, invalidate current outputs
                saved_valid0 <= 1'b0;
                saved_valid1 <= 1'b0;
            end else if (imem_rvalid_i) begin
                // Save both PCs and instructions together
                saved_pc0 <= imem_addr0_o;
                saved_pc1 <= imem_addr1_o;
                saved_instr0 <= imem_rdata0_i;
                saved_instr1 <= imem_rdata1_i;
                saved_valid0 <= 1'b1;
                saved_valid1 <= 1'b1;
            end else begin
                // No valid data from memory
                saved_valid0 <= 1'b0;
                saved_valid1 <= 1'b0;
            end
        end
        // If stall_i is asserted, keep the same values
    end

    // Output assignments
    assign if_valid_o = {saved_valid1, saved_valid0};
    assign if_pc0_o = saved_pc0;
    assign if_pc1_o = saved_pc1;
    assign if_instr0_o = saved_instr0;
    assign if_instr1_o = saved_instr1;

endmodule
