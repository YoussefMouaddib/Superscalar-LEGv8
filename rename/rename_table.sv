//===========================================================
//  Rename Table (Architectural → Physical Mapping)
//  Minimal OoO LEGv8 Core  —  Synthesizable
//===========================================================
module rename_table #(
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 48
)(
    input  logic              clk,
    input  logic              reset,

    // Lookup (read mapping)
    input  logic [4:0]        arch_rs1,
    input  logic [4:0]        arch_rs2,
    output logic [5:0]        phys_rs1,
    output logic [5:0]        phys_rs2,

    // Rename (new destination mapping)
    input  logic              rename_en,
    input  logic [4:0]        arch_rd,
    input  logic [5:0]        new_phys_rd,

    // Commit (restore architectural state)
    input  logic              commit_en,
    input  logic [4:0]        commit_arch_rd,
    input  logic [5:0]        commit_phys_rd
);

    logic [5:0] map_table [ARCH_REGS-1:0];  // current mapping
    logic [5:0] committed_table [ARCH_REGS-1:0]; // committed mapping

    // Read current mapping
    assign phys_rs1 = map_table[arch_rs1];
    assign phys_rs2 = map_table[arch_rs2];

    // Update mapping on rename or commit
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i]       <= i;
                committed_table[i] <= i;
            end
        end else begin
            if (rename_en)
                map_table[arch_rd] <= new_phys_rd;
            if (commit_en)
                committed_table[commit_arch_rd] <= commit_phys_rd;
        end
    end

endmodule
