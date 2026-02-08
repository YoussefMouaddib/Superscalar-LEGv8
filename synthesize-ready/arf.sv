`timescale 1ns/1ps
import core_pkg::*;

module arch_regfile #(
    parameter int XLEN = core_pkg::XLEN,
    parameter int ARCH_REGS = core_pkg::ARCH_REGS,
    parameter int WRITE_PORTS = 2
)(
    input  logic                clk,
    input  logic                reset,
    
    // Write ports (from commit stage)
    input  logic [WRITE_PORTS-1:0]      wen,
    input  logic [4:0]                  waddr[WRITE_PORTS-1:0],
    input  logic [XLEN-1:0]             wdata[WRITE_PORTS-1:0],
    
    // Read ports (for exception recovery, debugging)
    input  logic [4:0]                  raddr0,
    output logic [XLEN-1:0]             rdata0,
    input  logic [4:0]                  raddr1,
    output logic [XLEN-1:0]             rdata1
);

    // Register storage
    logic [XLEN-1:0] regs [0:ARCH_REGS-1];
    
    // Synchronous writes
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                regs[i] <= '0;
            end
        end else begin
            // Write port 0
            if (wen[0] && waddr[0] != 5'd0) begin
                regs[waddr[0]] <= wdata[0];
            end
            
            // Write port 1 (check for conflicts)
            if (wen[1] && waddr[1] != 5'd0) begin
                if (!(wen[0] && waddr[0] == waddr[1])) begin
                    regs[waddr[1]] <= wdata[1];
                end
            end
        end
    end
    
    // Combinational reads with x0 hardwired to zero
    assign rdata0 = (raddr0 == 5'd0) ? '0 : regs[raddr0];
    assign rdata1 = (raddr1 == 5'd0) ? '0 : regs[raddr1];

endmodule
