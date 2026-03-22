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
    
    // Scratchpad range for demo (0x2000 - 0x2FFF)
    localparam SCRATCHPAD_BASE = 32'h00002000;
    localparam SCRATCHPAD_END  = 32'h00002FFF;
    
    assign ready = 1'b1;  // Always ready
    assign tx_busy = 1'b0;  // Never busy in simulation
    assign rx_ready = 1'b0; // No RX data available
    
    // Character accumulator for demo
    logic [8*100-1:0] demo_string;  // 100-character buffer
    int demo_char_count;
    
    // Write logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_data_reg <= 8'h00;
            demo_char_count <= 0;
            demo_string <= '0;
        end else begin
            
            // ===================================================
            // DEMO MODE: Capture scratchpad writes for display
            // ===================================================
            if (write_en && (addr >= SCRATCHPAD_BASE) && (addr <= SCRATCHPAD_END)) begin
                automatic logic [7:0] char_val = write_data[7:0];
                
                // Display each character as it's written to scratchpad
                if (char_val >= 8'h20 && char_val <= 8'h7E) begin
                    $display("[DEMO_UART] Scratchpad[%h] = '%c' (0x%02h)", 
                             addr, char_val, char_val);
                    
                    // Accumulate printable characters
                    if (demo_char_count < 100) begin
                        demo_string[demo_char_count*8 +: 8] <= char_val;
                        demo_char_count <= demo_char_count + 1;
                    end
                    
                end else if (char_val == 8'h0D) begin
                    $display("[DEMO_UART] Scratchpad[%h] = <CR>", addr);
                end else if (char_val == 8'h0A) begin
                    $display("[DEMO_UART] Scratchpad[%h] = <LF>", addr);
                end else if (char_val == 8'h00) begin
                    $display("[DEMO_UART] Scratchpad[%h] = <NUL> (String terminator)", addr);
                    
                    // Print the complete string for demo
                    $display("\n╔════════════════════════════════════════════════════════╗");
                    $display("║          🎉 OUT-OF-ORDER CPU DEMO OUTPUT 🎉          ║");
                    $display("╠════════════════════════════════════════════════════════╣");
                    $display("║  Transmitted String: \"%s\"", demo_string[0 +: demo_char_count*8]);
                    $display("║  Character Count:     %0d bytes", demo_char_count);
                    $display("║  Memory Range:        0x%h - 0x%h", SCRATCHPAD_BASE, addr);
                    $display("╚════════════════════════════════════════════════════════╝\n");
                    
                end else begin
                    $display("[DEMO_UART] Scratchpad[%h] = <0x%02h>", addr, char_val);
                end
            end
            
            // ===================================================
            // REAL MODE: Actual UART register writes (for later)
            // ===================================================
            if (write_en && (addr == ADDR_TX_DATA)) begin
                tx_data_reg <= write_data[7:0];
                $display("[REAL_UART] TX_DATA = '%c' (0x%02h)", write_data[7:0], write_data[7:0]);
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
