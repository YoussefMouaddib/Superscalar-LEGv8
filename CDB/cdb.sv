module cdb_arbiter #(
    parameter int CDB_W = 2,
    parameter int XLEN = core_pkg::XLEN,
    parameter int PHYS_W = core_pkg::LOG2_PREGS
)(
    input  logic                clk,
    input  logic                reset,
    
    // Inputs from execution units
    input  logic [CDB_W-1:0]    result_valid,      // From ALU0, ALU1, etc.
    input  logic [CDB_W-1:0][PHYS_W-1:0] result_tag,
    input  logic [CDB_W-1:0][XLEN-1:0] result_value,
    input  logic [CDB_W-1:0][5:0] result_rob_tag,
    
    // CDB broadcast outputs
    output logic [CDB_W-1:0]    cdb_valid,
    output logic [CDB_W-1:0][PHYS_W-1:0] cdb_tag,
    output logic [CDB_W-1:0][XLEN-1:0] cdb_value,
    output logic [CDB_W-1:0][5:0] cdb_rob_tag
);

    // Simple round-robin arbitration
    logic arbiter_bit;
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cdb_valid <= '0;
            cdb_tag <= '0;
            cdb_value <= '0;
            cdb_rob_tag <= '0;
            arbiter_bit <= 1'b0;
        end else begin
            // Simple priority: ALU0 > ALU1 > BranchEx
            if (result_valid[0]) begin
                cdb_valid[0] <= 1'b1;
                cdb_tag[0] <= result_tag[0];
                cdb_value[0] <= result_value[0];
                cdb_rob_tag[0] <= result_rob_tag[0];
            end else if (result_valid[1]) begin
                cdb_valid[0] <= 1'b1;
                cdb_tag[0] <= result_tag[1];
                cdb_value[0] <= result_value[1];
                cdb_rob_tag[0] <= result_rob_tag[1];
            end else begin
                cdb_valid[0] <= 1'b0;
            end
            
            // Second CDB port (if needed)
            // Similar logic for cdb_valid[1], etc.
        end
    end

endmodule
