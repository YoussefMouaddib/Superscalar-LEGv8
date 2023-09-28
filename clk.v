`timescale 1ns / 1ps
`define CYCLE 10000

module clock_module(
    output reg clk
    );
    always
       #(`CYCLE/2) clk <= ~clk;
       
    initial
        clk<=0;
endmodule