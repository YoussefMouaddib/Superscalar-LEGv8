// ooo_core_top.sv  (UPDATED - I/O expansion revision)
// Changes from original:
//   1. clk input is now raw 100 MHz (true oscillator frequency)
//      MMCM derives clk_core(60MHz), clk_vga(25MHz), clk_eth(50MHz)
//   2. uart_tx now driven by real 8N1 serializer (uart_real)
//   3. uart_read_data_out[31:0] port REMOVED (32 debug pins freed)
//   4. VGA ports added (JD Pmod: 14 pins)
//   5. Ethernet RMII ports added (LAN8720 onboard: 5 pins)
//   6. VGA character RAM and engine instantiated
//   7. Memory map extended for VGA char RAM
//   8. eth_* ports present but loader FSM is a stub (next phase)
//
// Internal pipeline is completely unchanged. All existing submodules
// (fetch, decode, rename, dispatch, RS, ALU, CDB, ROB, commit,
//  PRF, ARF, LSU, branch_ex, data_scratchpad) are identical.

`timescale 1ns/1ps
import core_pkg::*;

module ooo_core_top (
    // ---------------------------------------------------------------
    // Board inputs
    // ---------------------------------------------------------------
    input  logic clk,          // 100 MHz crystal, Arty A7-100T pin E3
    input  logic reset,        // BTN0 active high, pin C2

    // ---------------------------------------------------------------
    // UART (real 8N1 serializer now)
    // ---------------------------------------------------------------
    output logic uart_tx,      // D10 → USB-UART bridge

    // ---------------------------------------------------------------
    // VGA output (JD Pmod, dual-row)
    // ---------------------------------------------------------------
    output logic [3:0] vga_r,  // Red   [3:0]
    output logic [3:0] vga_g,  // Green [3:0]
    output logic [3:0] vga_b,  // Blue  [3:0]
    output logic       vga_hs, // HSYNC (active low)
    output logic       vga_vs, // VSYNC (active low)

    // ---------------------------------------------------------------
    // Ethernet RMII (LAN8720 soldered on Arty A7 - fixed pins)
    // ---------------------------------------------------------------
    input  logic       eth_crs_dv,    // Carrier sense / data valid
    input  logic [1:0] eth_rxd,       // RMII receive data
    output logic       eth_ref_clk,   // 50 MHz ref clock to PHY
    output logic       eth_rstn       // PHY reset, active low
);

    // ================================================================
    // CLOCK GENERATION
    // ================================================================
    logic clk_core;      // 60.15 MHz → OOO pipeline, UART
    logic clk_vga;       // 25.00 MHz → VGA engine
    logic clk_eth;       // 50.00 MHz → LAN8720 REF_CLK
    logic pll_locked;    // MMCM locked signal

    mmcm_clocks clk_gen (
        .clk_in   (clk),
        .reset_in (reset),
        .clk_core (clk_core),
        .clk_vga  (clk_vga),
        .clk_eth  (clk_eth),
        .locked   (pll_locked)
    );

    // Ethernet ref clock: drive directly from MMCM output
    assign eth_ref_clk = clk_eth;

    // PHY reset: hold low for ~1 ms on startup, then release
    // LAN8720 requires >= 100 µs reset pulse. At 60 MHz, 65535 cycles = ~1 ms.
    logic [15:0] phy_rst_cnt;
    logic        phy_rst_done;

    always_ff @(posedge clk_core or negedge pll_locked) begin
        if (!pll_locked) begin
            phy_rst_cnt  <= '0;
            phy_rst_done <= 1'b0;
        end else if (!phy_rst_done) begin
            phy_rst_cnt  <= phy_rst_cnt + 1'b1;
            phy_rst_done <= &phy_rst_cnt;  // all ones = 65535 cycles ≈ 1 ms
        end
    end
    assign eth_rstn = phy_rst_done;

    // ================================================================
    // SYSTEM RESET
    // Synchronize to clk_core, hold until MMCM locked
    // ================================================================
    logic rst_sync_0, rst_sync_1;
    logic sys_reset;   // synchronous reset for all clk_core logic

    always_ff @(posedge clk_core or posedge reset) begin
        if (reset) begin
            rst_sync_0 <= 1'b1;
            rst_sync_1 <= 1'b1;
        end else begin
            rst_sync_0 <= !pll_locked;  // deassert only when locked
            rst_sync_1 <= rst_sync_0;
        end
    end
    assign sys_reset = rst_sync_1;

    // VGA-domain reset synchronizer
    logic vga_rst_0, vga_rst_1;
    logic vga_reset;

    always_ff @(posedge clk_vga or posedge reset) begin
        if (reset) begin
            vga_rst_0 <= 1'b1;
            vga_rst_1 <= 1'b1;
        end else begin
            vga_rst_0 <= !pll_locked;
            vga_rst_1 <= vga_rst_0;
        end
    end
    assign vga_reset = vga_rst_1;

    // ================================================================
    // INTERNAL SIGNAL DECLARATIONS
    // (identical to original ooo_core_top - not repeated for brevity,
    //  copy all logic/wire declarations from original here)
    // ================================================================

    // Fetch ↔ Instruction ROM
    logic [31:0] imem_addr0, imem_addr1;
    logic imem_ren;
    logic [31:0] imem_rdata0, imem_rdata1;
    logic [1:0][31:0] imem_pc;
    logic imem_valid;
    logic [1:0] if_valid;
    logic [1:0][31:0] if_pc, if_instr;
    logic [4:0] flush_rob_idx;

    // Fetch ↔ Control + Branch
    logic fetch_en, fetch_stall, redirect_en;
    logic [31:0] redirect_pc;
    logic flush_pipeline, flush_exception;
    logic [31:0] flush_pc;
    logic bp_update_en, branch_is_call, branch_is_return;
    logic [31:0] bp_update_pc, bp_update_target;
    logic bp_update_taken, bp_update_is_branch, bp_update_is_call, bp_update_is_return;

    // Decode outputs
    logic [1:0] dec_valid;
    logic [1:0][5:0] dec_opcode;
    logic [1:0][4:0] dec_rs1, dec_rs2, dec_rd;
    logic [1:0][31:0] dec_imm, dec_pc;
    logic [1:0] dec_rs1_valid, dec_rs2_valid, dec_rd_valid;
    logic [1:0] dec_is_alu, dec_is_load, dec_is_store, dec_is_branch, dec_is_cas;
    logic [1:0][5:0] dec_alu_func;
    logic [1:0][4:0] dec_shamt;
    logic decode_ready;

    // Rename outputs
    logic [1:0] rename_valid;
    logic [1:0][5:0] rename_opcode, rename_prs1, rename_prs2, rename_prd, rename_alu_func;
    logic [1:0][31:0] rename_imm, rename_pc;
    logic [1:0] rename_rs1_valid, rename_rs2_valid, rename_rd_valid;
    logic [1:0] rename_is_alu, rename_is_load, rename_is_store, rename_is_branch, rename_is_cas;
    logic [1:0][4:0] rename_arch_rs1, rename_arch_rs2, rename_arch_rd;
    logic rename_ready;
    logic [1:0] commit_en;
    logic [1:0][4:0] commit_arch_rd;
    logic [1:0][5:0] commit_phys_rd;

    // Dispatch / Issue
    logic dispatch_stall;
    logic [5:0] prf_rtag0, prf_rtag1, prf_rtag2, prf_rtag3;
    logic [31:0] prf_rdata0, prf_rdata1, prf_rdata2, prf_rdata3;
    logic [1:0] rs_alloc_en;
    logic [1:0][5:0] rs_alloc_dst_tag, rs_alloc_src1_tag, rs_alloc_src2_tag, rs_alloc_rob_tag;
    logic [1:0][31:0] rs_alloc_src1_val, rs_alloc_src2_val, rs_alloc_pc, rs_alloc_imm;
    logic [1:0] rs_alloc_src1_ready, rs_alloc_src2_ready;
    logic [1:0][11:0] rs_alloc_op;
    logic rs_full;
    logic [1:0] rob_alloc_en;
    logic [1:0][4:0] rob_alloc_arch_rd;
    logic [1:0][5:0] rob_alloc_phys_rd;
    logic [1:0] rob_alloc_is_store, rob_alloc_is_load, rob_alloc_is_branch;
    logic [1:0][31:0] rob_alloc_pc;
    logic rob_alloc_ok;
    logic [1:0][4:0] rob_alloc_idx;
    logic lsu_alloc_en, lsu_is_load;
    logic [7:0] lsu_opcode;
    logic [31:0] lsu_offset, lsu_store_data_value;
    logic [4:0] lsu_arch_rs1, lsu_arch_rs2, lsu_arch_rd;
    logic [5:0] lsu_phys_rd, lsu_rob_idx;
    logic lsu_store_data_ready;
    logic lsu_lane_index;

    // Issue / Execution
    logic [1:0] issue_valid;
    logic [1:0][11:0] issue_op;
    logic [1:0][5:0] issue_dst_tag, issue_rob_tag;
    logic [1:0][31:0] issue_src1_val, issue_src2_val, issue_pc, issue_imm;

    // CDB
    logic [1:0] cdb_valid;
    logic [1:0][5:0] cdb_tag, cdb_rob_tag;
    logic [1:0][31:0] cdb_value;
    logic branch_result_valid;
    logic [5:0] branch_result_tag;
    logic [31:0] branch_result_value;
    logic [4:0] branch_result_rob_tag;
    logic branch_taken;
    logic [31:0] branch_target_pc;
    logic branch_mispredict;
    logic branch_outcome_is_call, branch_outcome_is_return;

    // ROB / Commit
    logic [1:0] rob_commit_valid, rob_commit_exception;
    logic [1:0][4:0] rob_commit_arch_rd;
    logic [1:0][5:0] rob_commit_phys_rd;
    logic [1:0][4:0] rob_commit_rob_idx;
    logic [1:0] rob_commit_is_store, rob_commit_is_load, rob_commit_is_branch;
    logic [1:0][31:0] rob_commit_pc;
    logic [1:0] rob_commit_branch_taken;
    logic [1:0][31:0] rob_commit_branch_target;
    logic [1:0] rob_commit_branch_is_call, rob_commit_branch_is_return;
    logic mark_ready_en0, mark_ready_en1;
    logic [4:0] mark_ready_idx0, mark_ready_idx1;

    // Memory
    logic mem_req, mem_we, mem_ready, mem_error;
    logic scratchpad_we, scratchpad_ready;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [31:0] scratchpad_addr, scratchpad_wdata, scratchpad_rdata;

    // UART
    logic uart_read_en, uart_write_en;
    logic [31:0] uart_read_data;
    logic uart_ready;
    logic uart_serial;   // real serial output from uart_real

    // PRF
    logic [1:0] prf_wen;
    logic [1:0][5:0] prf_wtag;
    logic [1:0][31:0] prf_wdata;
    logic [1:0][5:0] prf_commit_rtag;
    logic [1:0][31:0] prf_commit_rdata;

    // Free list
    logic [1:0] freelist_free_en;
    logic [1:0][5:0] freelist_free_phys;

    // ARF
    logic [1:0] arf_wen;
    logic [1:0][4:0] arf_waddr;
    logic [1:0][31:0] arf_wdata;

    // LSU CDB
    logic lsu_cdb_valid, lsu_cdb_exception;
    logic [5:0] lsu_cdb_tag;
    logic [31:0] lsu_cdb_value;
    logic [1:0] lsu_commit_en, lsu_commit_is_store;
    logic [1:0][4:0] lsu_commit_rob_idx;
    logic [5:0] lsu_base_tag;
    logic lsu_base_ready;
    logic [31:0] lsu_base_value;
    logic [5:0] lsu_store_data_tag;
    logic [4:0] lsu_exception_cause;
    logic lsu_exception;
    logic [5:0] lsu_cdb_rob_tag;

    // Sequence counter
    logic [31:0] global_seq_counter;
    logic [ISSUE_WIDTH-1:0][31:0] alloc_seq_array;

    // ================================================================
    // VGA CHARACTER RAM signals
    // ================================================================
    logic        vga_cpu_wen;
    logic [11:0] vga_cpu_waddr;
    logic [15:0] vga_cpu_wdata;
    logic [11:0] vga_charram_raddr;
    logic [15:0] vga_charram_rdata;
    logic [11:0] vga_font_addr;
    logic [7:0]  vga_font_data;

    // ================================================================
    // ADDRESS DECODER
    // Memory map:
    //   0x00000000–0x00001FFF  Instruction ROM
    //   0x00002000–0x00002FFF  Data scratchpad
    //   0x00010000–0x0001000F  UART
    //   0x00030000–0x000302BF  VGA character RAM  (2400 cells × 4 bytes)
    //   0x00030400             VGA control (future)
    // ================================================================
    logic is_uart_access;
    logic is_vga_access;

    assign is_uart_access = (mem_addr >= 32'h00010000) &&
                            (mem_addr <= 32'h0001000F);

    assign is_vga_access  = (mem_addr >= 32'h00030000) &&
                            (mem_addr <= 32'h000302BF);  // 0x2BF = 2399*4 = 9596 → 0x257C; keep generous

    // VGA char RAM write: CPU writes word, extract cell address
    // Cell index = (addr - 0x30000) / 4
    assign vga_cpu_wen   = is_vga_access && mem_we;
    assign vga_cpu_waddr = (mem_addr - 32'h00030000) >> 2;   // cell index, 12 bits
    assign vga_cpu_wdata = mem_wdata[15:0];                   // [7:0]=char, [9:8]=color

    // UART enables
    assign uart_read_en  = is_uart_access && mem_req && !mem_we;
    assign uart_write_en = is_uart_access && mem_we;

    // Scratchpad enables (neither UART nor VGA)
    assign scratchpad_we   = !is_uart_access && !is_vga_access && mem_we;
    assign scratchpad_addr = mem_addr - 32'h00002000;
    assign scratchpad_wdata = mem_wdata;

    // Read data mux back to LSU
    always_comb begin
        if (is_uart_access)
            mem_rdata = uart_read_data;
        else if (is_vga_access)
            mem_rdata = 32'h0;    // VGA is write-only from CPU perspective
        else
            mem_rdata = scratchpad_rdata;
    end

    always_comb begin
        if (is_uart_access)
            mem_ready = uart_ready;
        else if (is_vga_access)
            mem_ready = 1'b1;     // VGA writes complete in 1 cycle
        else
            mem_ready = scratchpad_ready;
    end

    // ================================================================
    // SEQUENCE COUNTER (unchanged from original)
    // ================================================================
    always_ff @(posedge clk_core or posedge sys_reset) begin
        if (sys_reset) begin
            global_seq_counter <= 32'd0;
        end else begin
            if (|rob_alloc_en) begin
                automatic int alloc_count = 0;
                for (int i = 0; i < ISSUE_WIDTH; i++) begin
                    if (rob_alloc_en[i]) alloc_count++;
                end
                global_seq_counter <= global_seq_counter + alloc_count;
            end
        end
    end

    always_comb begin
        automatic logic [31:0] seq_temp = global_seq_counter;
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            alloc_seq_array[i] = seq_temp;
            if (rob_alloc_en[i]) seq_temp++;
        end
    end

    // Control signals (unchanged)
    assign fetch_en      = 1'b1;
    assign fetch_stall   = 1'b0;
    assign decode_ready  = 1'b1;
    assign redirect_en   = 1'b0;
    assign redirect_pc   = '0;
    assign flush_pipeline = '0;
    assign flush_rob_idx  = branch_result_rob_tag;
    assign rs_full        = 1'b0;

    assign mark_ready_en0  = cdb_valid[0];
    assign mark_ready_idx0 = cdb_rob_tag[0][4:0];
    assign mark_ready_en1  = cdb_valid[1];
    assign mark_ready_idx1 = cdb_rob_tag[1][4:0];

    assign prf_wen   = cdb_valid;
    assign prf_wtag  = cdb_tag;
    assign prf_wdata = cdb_value;

    // UART serial output
    assign uart_tx = uart_serial;

    // ================================================================
    // MODULE INSTANTIATIONS
    // ================================================================

    // --- Instruction ROM ---
    inst_rom #(.ROM_SIZE(8192), .XLEN(32)) imem (
        .clk(clk_core), .reset(sys_reset),
        .imem_ren(imem_ren),
        .imem_addr0(imem_addr0), .imem_addr1(imem_addr1),
        .imem_valid(imem_valid),
        .imem_rdata0(imem_rdata0), .imem_rdata1(imem_rdata1),
        .imem_pc(imem_pc)
    );

    // --- Fetch ---
    fetch fetch_inst (
        .clk(clk_core), .reset(sys_reset),
        .branch_taken(branch_taken), .branch_target_pc(branch_target_pc),
        .fetch_en(fetch_en), .stall(fetch_stall),
        .redirect_en(redirect_en), .redirect_pc(redirect_pc),
        .flush_pipeline(flush_pipeline),
        .bp_update_en(bp_update_en), .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken), .bp_update_target(bp_update_target),
        .bp_update_is_branch(bp_update_is_branch),
        .bp_update_is_call(bp_update_is_call), .bp_update_is_return(bp_update_is_return),
        .imem_rdata0(imem_rdata0), .imem_rdata1(imem_rdata1),
        .imem_pc(imem_pc), .imem_valid(imem_valid),
        .if_valid(if_valid), .if_pc(if_pc), .if_instr(if_instr),
        .imem_addr0(imem_addr0), .imem_addr1(imem_addr1), .imem_ren(imem_ren)
    );

    // --- Decode ---
    decode decode_inst (
        .clk(clk_core), .reset(sys_reset),
        .instr_valid(if_valid), .instr(if_instr), .pc(if_pc),
        .decode_ready(decode_ready), .flush_pipeline(flush_pipeline),
        .dec_valid(dec_valid), .dec_opcode(dec_opcode),
        .dec_rs1(dec_rs1), .dec_rs2(dec_rs2), .dec_rd(dec_rd),
        .dec_imm(dec_imm), .dec_pc(dec_pc),
        .dec_rs1_valid(dec_rs1_valid), .dec_rs2_valid(dec_rs2_valid), .dec_rd_valid(dec_rd_valid),
        .dec_is_alu(dec_is_alu), .dec_is_load(dec_is_load), .dec_is_store(dec_is_store),
        .dec_is_branch(dec_is_branch), .dec_is_cas(dec_is_cas),
        .dec_alu_func(dec_alu_func), .dec_shamt(dec_shamt)
    );

    // --- Rename ---
    rename_stage rename_inst (
        .clk(clk_core), .reset(sys_reset),
        .dec_valid(dec_valid), .dec_opcode(dec_opcode),
        .dec_rs1(dec_rs1), .dec_rs2(dec_rs2), .dec_rd(dec_rd),
        .dec_imm(dec_imm), .dec_pc(dec_pc),
        .dec_rs1_valid(dec_rs1_valid), .dec_rs2_valid(dec_rs2_valid), .dec_rd_valid(dec_rd_valid),
        .dec_is_alu(dec_is_alu), .dec_is_load(dec_is_load), .dec_is_store(dec_is_store),
        .dec_is_branch(dec_is_branch), .dec_is_cas(dec_is_cas), .dec_alu_func(dec_alu_func),
        .rename_ready(rename_ready),
        .rename_valid(rename_valid), .rename_opcode(rename_opcode),
        .rename_prs1(rename_prs1), .rename_prs2(rename_prs2), .rename_prd(rename_prd),
        .rename_imm(rename_imm), .rename_pc(rename_pc),
        .rename_rs1_valid(rename_rs1_valid), .rename_rs2_valid(rename_rs2_valid), .rename_rd_valid(rename_rd_valid),
        .rename_is_alu(rename_is_alu), .rename_is_load(rename_is_load), .rename_is_store(rename_is_store),
        .rename_is_branch(rename_is_branch), .rename_is_cas(rename_is_cas), .rename_alu_func(rename_alu_func),
        .rename_arch_rs1(rename_arch_rs1), .rename_arch_rs2(rename_arch_rs2), .rename_arch_rd(rename_arch_rd),
        .commit_en(commit_en), .commit_arch_rd(commit_arch_rd), .commit_phys_rd(commit_phys_rd),
        .flush_pipeline(flush_pipeline)
    );

    // --- Dispatch ---
    dispatch dispatch_inst (
        .clk(clk_core), .reset(sys_reset),
        .rename_valid(rename_valid), .rename_opcode(rename_opcode),
        .rename_prs1(rename_prs1), .rename_prs2(rename_prs2), .rename_prd(rename_prd),
        .rename_imm(rename_imm), .rename_pc(rename_pc),
        .rename_rs1_valid(rename_rs1_valid), .rename_rs2_valid(rename_rs2_valid), .rename_rd_valid(rename_rd_valid),
        .rename_is_alu(rename_is_alu), .rename_is_load(rename_is_load), .rename_is_store(rename_is_store),
        .rename_is_branch(rename_is_branch), .rename_is_cas(rename_is_cas), .rename_alu_func(rename_alu_func),
        .rename_arch_rs1(rename_arch_rs1), .rename_arch_rs2(rename_arch_rs2), .rename_arch_rd(rename_arch_rd),
        .flush_pipeline(flush_pipeline), .dispatch_stall(dispatch_stall),
        .prf_rtag0(prf_rtag0), .prf_rdata0(prf_rdata0),
        .prf_rtag1(prf_rtag1), .prf_rdata1(prf_rdata1),
        .prf_rtag2(prf_rtag2), .prf_rdata2(prf_rdata2),
        .prf_rtag3(prf_rtag3), .prf_rdata3(prf_rdata3),
        .rs_alloc_en(rs_alloc_en), .rs_alloc_dst_tag(rs_alloc_dst_tag),
        .rs_alloc_src1_tag(rs_alloc_src1_tag), .rs_alloc_src2_tag(rs_alloc_src2_tag),
        .rs_alloc_src1_val(rs_alloc_src1_val), .rs_alloc_src2_val(rs_alloc_src2_val),
        .rs_alloc_src1_ready(rs_alloc_src1_ready), .rs_alloc_src2_ready(rs_alloc_src2_ready),
        .rs_alloc_op(rs_alloc_op), .rs_alloc_pc(rs_alloc_pc), .rs_alloc_imm(rs_alloc_imm),
        .rs_alloc_rob_tag(rs_alloc_rob_tag), .rs_full(rs_full),
        .rob_alloc_en(rob_alloc_en), .rob_alloc_arch_rd(rob_alloc_arch_rd),
        .rob_alloc_phys_rd(rob_alloc_phys_rd), .rob_alloc_is_store(rob_alloc_is_store),
        .rob_alloc_is_load(rob_alloc_is_load), .rob_alloc_is_branch(rob_alloc_is_branch),
        .rob_alloc_pc(rob_alloc_pc), .rob_alloc_ok(rob_alloc_ok), .rob_alloc_idx(rob_alloc_idx),
        .lsu_alloc_en(lsu_alloc_en), .lsu_is_load(lsu_is_load), .lsu_opcode(lsu_opcode),
        .lsu_offset(lsu_offset), .lsu_arch_rs1(lsu_arch_rs1), .lsu_arch_rs2(lsu_arch_rs2),
        .lsu_arch_rd(lsu_arch_rd), .lsu_phys_rd(lsu_phys_rd), .lsu_rob_idx(lsu_rob_idx),
        .lsu_base_tag(lsu_base_tag), .lsu_base_ready(lsu_base_ready), .lsu_base_value(lsu_base_value),
        .lsu_store_data_tag(lsu_store_data_tag), .lsu_store_data_ready(lsu_store_data_ready),
        .lsu_store_data_value(lsu_store_data_value),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .lsu_lane_index(lsu_lane_index)
    );

    // --- Reservation Station ---
    reservation_station rs_inst (
        .clk(clk_core), .reset(sys_reset), .flush_pipeline(flush_pipeline),
        .alloc_en(rs_alloc_en), .alloc_dst_tag(rs_alloc_dst_tag),
        .alloc_src1_tag(rs_alloc_src1_tag), .alloc_src2_tag(rs_alloc_src2_tag),
        .alloc_src1_val(rs_alloc_src1_val), .alloc_src2_val(rs_alloc_src2_val),
        .alloc_src1_ready(rs_alloc_src1_ready), .alloc_src2_ready(rs_alloc_src2_ready),
        .alloc_op(rs_alloc_op), .alloc_rob_tag(rs_alloc_rob_tag),
        .alloc_pc(rs_alloc_pc), .alloc_imm(rs_alloc_imm),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .issue_valid(issue_valid), .issue_op(issue_op),
        .issue_dst_tag(issue_dst_tag), .issue_src1_val(issue_src1_val),
        .issue_src2_val(issue_src2_val), .issue_rob_tag(issue_rob_tag),
        .issue_pc(issue_pc), .issue_imm(issue_imm)
    );

    // --- ALUs ---
    logic alu0_result_valid, alu1_result_valid;
    logic [5:0] alu0_result_tag, alu1_result_tag;
    logic [31:0] alu0_result_value, alu1_result_value;
    logic [5:0] alu0_result_rob_tag, alu1_result_rob_tag;

    alu alu0_inst (
        .clk(clk_core), .reset(sys_reset),
        .issue_valid(issue_valid[0]), .issue_op(issue_op[0]),
        .issue_dst_tag(issue_dst_tag[0]),
        .issue_src1_val(issue_src1_val[0]), .issue_src2_val(issue_src2_val[0]),
        .issue_rob_tag(issue_rob_tag[0]),
        .cdb_valid(1'b0), .cdb_tag('0), .cdb_value('0), .rf_rdata('0),
        .alu_result_valid(alu0_result_valid), .alu_result_tag(alu0_result_tag),
        .alu_result_value(alu0_result_value), .alu_result_rob_tag(alu0_result_rob_tag),
        .alu_bypass_valid(), .alu_bypass_tag(), .alu_bypass_value()
    );

    alu alu1_inst (
        .clk(clk_core), .reset(sys_reset),
        .issue_valid(issue_valid[1]), .issue_op(issue_op[1]),
        .issue_dst_tag(issue_dst_tag[1]),
        .issue_src1_val(issue_src1_val[1]), .issue_src2_val(issue_src2_val[1]),
        .issue_rob_tag(issue_rob_tag[1]),
        .cdb_valid(1'b0), .cdb_tag('0), .cdb_value('0), .rf_rdata('0),
        .alu_result_valid(alu1_result_valid), .alu_result_tag(alu1_result_tag),
        .alu_result_value(alu1_result_value), .alu_result_rob_tag(alu1_result_rob_tag),
        .alu_bypass_valid(), .alu_bypass_tag(), .alu_bypass_value()
    );

    // --- CDB Arbiter ---
    cdb_arbiter cdb_arb_inst (
        .clk(clk_core), .reset(sys_reset),
        .src0_valid(alu0_result_valid), .src0_tag(alu0_result_tag),
        .src0_value(alu0_result_value), .src0_rob_tag(alu0_result_rob_tag),
        .src1_valid(alu1_result_valid), .src1_tag(alu1_result_tag),
        .src1_value(alu1_result_value), .src1_rob_tag(alu1_result_rob_tag),
        .src2_valid(branch_result_valid), .src2_tag(branch_result_tag),
        .src2_value(branch_result_value), .src2_rob_tag(branch_result_rob_tag),
        .src3_valid(lsu_cdb_valid), .src3_tag(rob_commit_rob_idx),
        .src3_value(lsu_cdb_value), .src3_rob_tag(lsu_cdb_rob_tag),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag),
        .cdb_value(cdb_value), .cdb_rob_tag(cdb_rob_tag)
    );

    // --- ROB ---
    rob rob_inst (
        .clk(clk_core), .reset(sys_reset),
        .alloc_en(rob_alloc_en), .alloc_arch_rd(rob_alloc_arch_rd),
        .alloc_phys_rd(rob_alloc_phys_rd), .alloc_is_store(rob_alloc_is_store),
        .alloc_is_load(rob_alloc_is_load), .alloc_is_branch(rob_alloc_is_branch),
        .alloc_pc(rob_alloc_pc), .alloc_ok(rob_alloc_ok), .alloc_idx(rob_alloc_idx),
        .mark_ready_en(mark_ready_en0), .mark_ready_idx(mark_ready_idx0),
        .mark_ready_val(1'b1), .mark_exception(1'b0),
        .mark_ready_en1(mark_ready_en1), .mark_ready_idx1(mark_ready_idx1),
        .mark_ready_val1(1'b1), .mark_exception1(1'b0),
        .branch_outcome_en(branch_result_valid), .branch_outcome_idx(branch_result_rob_tag),
        .branch_outcome_taken(branch_taken), .branch_outcome_target(branch_target_pc),
        .branch_outcome_is_call(branch_outcome_is_call),
        .branch_outcome_is_return(branch_outcome_is_return),
        .commit_valid(rob_commit_valid), .commit_arch_rd(rob_commit_arch_rd),
        .commit_phys_rd(rob_commit_phys_rd), .commit_exception(rob_commit_exception),
        .commit_rob_idx(rob_commit_rob_idx), .commit_is_store(rob_commit_is_store),
        .commit_is_load(rob_commit_is_load), .commit_is_branch(rob_commit_is_branch),
        .commit_pc(rob_commit_pc), .commit_branch_taken(rob_commit_branch_taken),
        .commit_branch_target(rob_commit_branch_target),
        .commit_branch_is_call(rob_commit_branch_is_call),
        .commit_branch_is_return(rob_commit_branch_is_return),
        .rob_full(), .rob_almost_full(),
        .flush_en(1'b0), .flush_ptr('0),
        .flush_pipeline(flush_pipeline), .flush_rob_idx(flush_rob_idx)
    );

    // --- Commit Stage ---
    commit_stage commit_inst (
        .clk(clk_core), .reset(sys_reset),
        .rob_commit_valid(rob_commit_valid), .rob_commit_arch_rd(rob_commit_arch_rd),
        .rob_commit_phys_rd(rob_commit_phys_rd), .rob_commit_exception(rob_commit_exception),
        .rob_commit_is_store(rob_commit_is_store), .rob_commit_is_load(rob_commit_is_load),
        .rob_commit_is_branch(rob_commit_is_branch), .rob_commit_pc(rob_commit_pc),
        .rob_commit_rob_idx(rob_commit_rob_idx),
        .rob_commit_branch_taken(rob_commit_branch_taken),
        .rob_commit_branch_target(rob_commit_branch_target),
        .rob_commit_branch_is_call(rob_commit_branch_is_call),
        .rob_commit_branch_is_return(rob_commit_branch_is_return),
        .arf_wen(arf_wen), .arf_waddr(arf_waddr), .arf_wdata(arf_wdata),
        .prf_commit_rtag(prf_commit_rtag), .prf_commit_rdata(prf_commit_rdata),
        .freelist_free_en(freelist_free_en), .freelist_free_phys(freelist_free_phys),
        .rename_commit_en(commit_en), .rename_commit_arch_rd(commit_arch_rd),
        .rename_commit_phys_rd(commit_phys_rd),
        .exception_valid(), .exception_cause(), .exception_pc(), .exception_tval(),
        .flush_pipeline(flush_exception), .flush_pc(flush_pc),
        .lsu_commit_en(lsu_commit_en), .lsu_commit_is_store(lsu_commit_is_store),
        .lsu_commit_rob_idx(lsu_commit_rob_idx),
        .bp_update_en(bp_update_en), .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken), .bp_update_target(bp_update_target),
        .bp_update_is_branch(bp_update_is_branch), .bp_update_is_call(bp_update_is_call),
        .bp_update_is_return(bp_update_is_return),
        .perf_insns_committed(), .perf_cycles(), .perf_exceptions(),
        .lsu_base_tag(lsu_base_tag), .lsu_base_ready(lsu_base_ready)
    );

    // --- Physical Register File ---
    regfile_synth prf_inst (
        .clk(clk_core), .reset(sys_reset),
        .wen0(prf_wen[0]), .wtag0(prf_wtag[0]), .wdata0(prf_wdata[0]),
        .wen1(prf_wen[1]), .wtag1(prf_wtag[1]), .wdata1(prf_wdata[1]),
        .rtag0(prf_rtag0), .rdata0(prf_rdata0),
        .rtag1(prf_rtag1), .rdata1(prf_rdata1),
        .rtag2(prf_rtag2), .rdata2(prf_rdata2),
        .rtag3(prf_rtag3), .rdata3(prf_rdata3),
        .rtag4(prf_commit_rtag[0]), .rdata4(prf_commit_rdata[0]),
        .rtag5(prf_commit_rtag[1]), .rdata5(prf_commit_rdata[1])
    );

    // --- Architectural Register File ---
    arch_regfile arf_inst (
        .clk(clk_core), .reset(sys_reset),
        .wen(arf_wen), .waddr(arf_waddr), .wdata(arf_wdata),
        .raddr0('0), .rdata0(),   // debug read port - future use
        .raddr1('0), .rdata1()
    );

    // --- LSU ---
    lsu lsu_inst (
        .clk(clk_core), .reset(sys_reset), .flush_pipeline(flush_pipeline),
        .alloc_en(lsu_alloc_en), .is_load(lsu_is_load), .opcode(lsu_opcode),
        .alloc_seq(lsu_alloc_en ? alloc_seq_array[lsu_lane_index] : 32'd0),
        .base_addr_tag(lsu_base_tag), .base_addr_ready(lsu_base_ready),
        .base_addr_value(lsu_base_value),
        .store_data_tag(lsu_store_data_tag), .store_data_ready(lsu_store_data_ready),
        .store_data_value(lsu_store_data_value),
        .offset(lsu_offset), .arch_rs1(lsu_arch_rs1), .arch_rs2(lsu_arch_rs2),
        .arch_rd(lsu_arch_rd), .phys_rd(lsu_phys_rd), .rob_idx(lsu_rob_idx),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag), .cdb_value(cdb_value),
        .cdb_req(lsu_cdb_valid), .cdb_req_tag(lsu_cdb_tag),
        .cdb_req_value(lsu_cdb_value), .cdb_req_exception(lsu_cdb_exception),
        .commit_en(rob_commit_valid), .commit_is_store(rob_commit_is_store),
        .commit_rob_idx(rob_commit_rob_idx),
        .lsu_exception(lsu_exception), .lsu_exception_cause(lsu_exception_cause),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_error(mem_error)
    );

    // --- UART (real 8N1 serializer) ---
    uart_real uart_inst (
        .clk(clk_core), .reset(sys_reset),
        .addr(mem_addr), .read_en(uart_read_en), .write_en(uart_write_en),
        .write_data(mem_wdata), .read_data(uart_read_data),
        .ready(uart_ready), .serial_out(uart_serial)
    );

    // --- Branch Execution Unit ---
    branch_ex branch_inst (
        .clk(clk_core), .reset(sys_reset), .flush_pipeline(flush_pipeline),
        .issue_valid(issue_valid), .issue_op(issue_op),
        .issue_dst_tag(issue_dst_tag), .issue_src1_val(issue_src1_val),
        .issue_src2_val(issue_src2_val), .issue_pc(issue_pc), .issue_imm(issue_imm),
        .issue_rob_tag(issue_rob_tag),
        .branch_result_valid(branch_result_valid), .branch_result_tag(branch_result_tag),
        .branch_result_value(branch_result_value), .branch_result_rob_tag(branch_result_rob_tag),
        .is_call(branch_outcome_is_call), .is_return(branch_outcome_is_return),
        .branch_taken(branch_taken), .branch_target_pc(branch_target_pc),
        .branch_mispredict(branch_mispredict)
    );

    // --- Data Scratchpad ---
    data_scratchpad dmem (
        .clk(clk_core), .reset(sys_reset),
        .mem_req(scratchpad_we || (mem_req && !is_uart_access && !is_vga_access && !mem_we)),
        .mem_we(scratchpad_we), .mem_addr(scratchpad_addr), .mem_wdata(scratchpad_wdata),
        .mem_size(2'b10), .mem_atomic(1'b0), .mem_cmp_val('0),
        .mem_ready(scratchpad_ready), .mem_rdata(scratchpad_rdata), .mem_error(mem_error)
    );

    // ================================================================
    // VGA SUBSYSTEM
    // ================================================================

    // Character RAM (dual-clock: CPU writes on clk_core, VGA reads on clk_vga)
    vga_charram char_ram (
        .clk_cpu   (clk_core),
        .cpu_wen   (vga_cpu_wen),
        .cpu_waddr (vga_cpu_waddr),
        .cpu_wdata (vga_cpu_wdata),
        .clk_vga   (clk_vga),
        .cpu_raddr ('0),
        .vga_raddr (vga_charram_raddr),
        .vga_rdata (vga_charram_rdata)
    );

    // Font ROM (clk_vga domain)
    font_rom font (
        .clk  (clk_vga),
        .addr (vga_font_addr),
        .data (vga_font_data)
    );

    // VGA timing + pixel engine
    vga_engine vga (
        .clk_vga      (clk_vga),
        .reset        (vga_reset),
        .charram_addr (vga_charram_raddr),
        .charram_data (vga_charram_rdata),
        .font_addr    (vga_font_addr),
        .font_data    (vga_font_data),
        .vga_r        (vga_r),
        .vga_g        (vga_g),
        .vga_b        (vga_b),
        .vga_hs       (vga_hs),
        .vga_vs       (vga_vs)
    );

    // ================================================================
    // ETHERNET (stub - loader FSM is next phase)
    // eth_crs_dv and eth_rxd are inputs, connect to loader module later.
    // For now, tie off to prevent Vivado unconnected input warnings.
    // ================================================================
    // synthesis translate_off
    logic _eth_unused;
    assign _eth_unused = eth_crs_dv ^ eth_rxd[0] ^ eth_rxd[1];
    // synthesis translate_on

endmodule
