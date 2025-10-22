//===========================================================
//  Testbench — Rename Table
//===========================================================
module tb_rename_table;

    logic clk, reset;
    logic [4:0] arch_rs1, arch_rs2, arch_rd, commit_arch_rd;
    logic [5:0] new_phys_rd, commit_phys_rd;
    logic rename_en, commit_en;
    logic [5:0] phys_rs1, phys_rs2;

    rename_table dut (
        .clk(clk), .reset(reset),
        .arch_rs1(arch_rs1), .arch_rs2(arch_rs2),
        .phys_rs1(phys_rs1), .phys_rs2(phys_rs2),
        .rename_en(rename_en), .arch_rd(arch_rd),
        .new_phys_rd(new_phys_rd),
        .commit_en(commit_en), .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        $display("=== Rename Table TB Start ===");
        clk = 0; reset = 1;
        rename_en = 0; commit_en = 0;
        #10 reset = 0;

        // Lookup default mapping
        arch_rs1 = 5'd2; arch_rs2 = 5'd3;
        #10;
        assert(phys_rs1 == 6'd2 && phys_rs2 == 6'd3)
            else $fatal("Initial mapping incorrect");

        // Rename test
        rename_en = 1; arch_rd = 5'd2; new_phys_rd = 6'd40;
        #10 rename_en = 0;

        arch_rs1 = 5'd2; #10;
        assert(phys_rs1 == 6'd40) else $fatal("Rename failed");

        // Commit test
        commit_en = 1; commit_arch_rd = 5'd2; commit_phys_rd = 6'd40;
        #10 commit_en = 0;

        $display("All tests passed.");
        $finish;
    end
endmodule
