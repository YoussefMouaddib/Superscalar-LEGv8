module rename_table #(
    parameter int ARCH_REGS = 32,
    parameter int PHYS_REGS = 48,
    parameter int LOOKUP_PORTS = 2,
    parameter int RENAME_PORTS = 2,
    parameter int COMMIT_PORTS = 2
)(
    input  logic              clk,
    input  logic              reset,

    // Lookup ports (multi-port read)
    input  logic [1:0][4:0]        arch_rs1,
    input  logic [1:0][4:0]        arch_rs2,
    output logic [1:0][5:0]        phys_rs1,
    output logic [1:0][5:0]        phys_rs2,

    // Rename ports (multi-port speculative update)
    input  logic [RENAME_PORTS-1:0]  rename_en,
    input  logic [1:0][4:0]        arch_rd,
    input  logic [1:0][5:0]        new_phys_rd,

    // Commit ports (multi-port committed state update)
    input  logic [COMMIT_PORTS-1:0]  commit_en,
    input  logic [1:0][4:0]        commit_arch_rd,
    input  logic [1:0][5:0]        commit_phys_rd,
    
    // Flush pipeline
    input  logic              flush_pipeline
);

    logic [5:0] map_table [ARCH_REGS-1:0];          // speculative mapping
    logic [5:0] committed_table [ARCH_REGS-1:0];    // committed mapping

    // ============================================================
    // Multi-port Combinational Reads
    // ============================================================
    always_comb begin
        for (int i = 0; i < LOOKUP_PORTS; i++) begin
            // X0 always maps to physical register 0
            phys_rs1[i] = (arch_rs1[i] == 5'd0) ? 6'd0 : map_table[arch_rs1[i]];
            phys_rs2[i] = (arch_rs2[i] == 5'd0) ? 6'd0 : map_table[arch_rs2[i]];
        end
    end

    // ============================================================
    // Sequential Updates (Rename + Commit)
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i]       <= 6'(i);  // Initial mapping: arch -> same phys
                committed_table[i] <= 6'(i);
            end
        end else if (flush_pipeline) begin
            // On flush: restore speculative map from committed state
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i] <= committed_table[i];
            end
        end else begin
            // ============================================================
            // Speculative Renames (multi-port, applied sequentially)
            // ============================================================
            for (int j = 0; j < RENAME_PORTS; j++) begin
                if (rename_en[j] && arch_rd[j] != 5'd0) begin
                    map_table[arch_rd[j]] <= new_phys_rd[j];
                end
            end
            
            // ============================================================
            // Committed State Updates (multi-port, applied sequentially)
            // ============================================================
            for (int j = 0; j < COMMIT_PORTS; j++) begin
                if (commit_en[j] && commit_arch_rd[j] != 5'd0) begin
                    committed_table[commit_arch_rd[j]] <= commit_phys_rd[j];
                end
            end
        end
    end

endmodule
