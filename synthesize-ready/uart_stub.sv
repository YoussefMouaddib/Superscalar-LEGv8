`timescale 1ns/1ps

module uart_stub (
    input  logic        clk,
    input  logic        reset,
    
    // Memory-mapped interface
    input  logic [31:0] addr,       // Address from LSU
    input  logic        read_en,    // Read enable
    input  logic        write_en,   // Write enable
    input  logic [31:0] write_data, // Data to write
    output logic [31:0] read_data,  // Data read
    output logic        ready       // Always ready in stub
);
    // UART registers
    logic [7:0] tx_data_reg;
    logic       tx_busy;      // Always 0 in stub
    logic       rx_ready;     // Always 0 for now
    logic [7:0] rx_data_reg;  // Always 0 for now
    
    // Register offsets
    localparam ADDR_TX_DATA = 32'h00010000;
    localparam ADDR_STATUS  = 32'h00010004;
    localparam ADDR_RX_DATA = 32'h00010008;
    
    assign ready = 1'b1;  // Always ready
    assign tx_busy = 1'b0;  // Never busy in simulation
    assign rx_ready = 1'b0; // No RX data available
    
    // Write logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_data_reg <= 8'h00;
        end else begin
            // Debug: Print ALL write attempts
            if (write_en) begin
                $display("[UART_STUB] Write: addr=%h data=%h match=%b", 
                         addr, write_data, (addr == ADDR_TX_DATA));
            end
            
            // Check for TX_DATA write
            if (write_en && (addr == ADDR_TX_DATA)) begin
                tx_data_reg <= write_data[7:0];
                
                // Print character if it's printable ASCII
                if (write_data[7:0] >= 8'h20 && write_data[7:0] <= 8'h7E) begin
                    $display("[UART_TX] '%c' (0x%02h)", write_data[7:0], write_data[7:0]);
                end else if (write_data[7:0] == 8'h0D) begin
                    $display("[UART_TX] <CR> (0x0D)");
                end else if (write_data[7:0] == 8'h0A) begin
                    $display("[UART_TX] <LF> (0x0A)");
                end else if (write_data[7:0] == 8'h00) begin
                    $display("[UART_TX] <NUL> (0x00)");
                end else begin
                    $display("[UART_TX] <0x%02h>", write_data[7:0]);
                end
                
                $fflush();
            end
        end
    end
    
    // Read logic
    always_comb begin
        read_data = 32'h00000000;
        
        case (addr)
            ADDR_TX_DATA: read_data = {24'h0, tx_data_reg};
            ADDR_STATUS:  read_data = {30'h0, rx_ready, tx_busy};
            ADDR_RX_DATA: read_data = {24'h0, rx_data_reg};
            default:      read_data = 32'h00000000;
        endcase
    end
    
endmodule
