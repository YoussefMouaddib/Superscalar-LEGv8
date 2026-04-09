// uart_tx_core.sv
// 8N1 UART transmitter - memory-mapped, drop-in replacement for uart_stub.sv
//
// Clock: clk_core (~60.15 MHz)
// Baud:  115200
// Divisor: 60_150_000 / 115_200 = 521.9 → 522
//   (0.016% baud error at 115200 - negligible, well under 2% tolerance)
//
// Memory map (same as uart_stub so no LSU changes needed):
//   BASE + 0x0 (0x00010000): TX_DATA  - write bits[7:0] to transmit a byte
//   BASE + 0x4 (0x00010004): STATUS   - read bit[0]=tx_busy (1=transmitting)
//   BASE + 0x8 (0x00010008): RX_DATA  - stub (always 0, no RX implemented)
//
// Interface: identical to uart_stub.sv - just swap the module name in top-level
//
// Behavior:
//   - Write to TX_DATA while tx_busy=0 → latches byte, begins transmission
//   - Write to TX_DATA while tx_busy=1 → write ignored (software must poll STATUS)
//   - ready output is always 1 (the peripheral is always addressable)

`timescale 1ns/1ps

module uart_tx_core #(
    // Adjust if clk_core changes. Formula: CLK_HZ / BAUD_RATE
    parameter int CLK_HZ   = 60_150_000,
    parameter int BAUD_RATE = 115_200,
    parameter int DIVISOR   = CLK_HZ / BAUD_RATE  // = 522
)(
    input  logic        clk,
    input  logic        reset,

    // Memory-mapped interface (identical to uart_stub)
    input  logic [31:0] addr,
    input  logic        read_en,
    input  logic        write_en,
    input  logic [31:0] write_data,
    output logic [31:0] read_data,
    output logic        ready        // always 1 - peripheral never stalls CPU
);

    // ----------------------------------------------------------------
    // Address offsets (absolute, matched to uart_stub)
    // ----------------------------------------------------------------
    localparam logic [31:0] ADDR_TX_DATA = 32'h00010000;
    localparam logic [31:0] ADDR_STATUS  = 32'h00010004;
    localparam logic [31:0] ADDR_RX_DATA = 32'h00010008;

    // ----------------------------------------------------------------
    // Baud rate generator
    // ----------------------------------------------------------------
    logic [$clog2(DIVISOR)-1:0] baud_cnt;
    logic baud_tick;   // one clk_core cycle pulse at baud rate

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == DIVISOR - 1) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1'b1;
            baud_tick <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // TX shift register FSM
    // States: IDLE → START → DATA[0..7] → STOP → IDLE
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE  = 2'd0,
        START = 2'd1,
        DATA  = 2'd2,
        STOP  = 2'd3
    } tx_state_t;

    tx_state_t   tx_state;
    logic [7:0]  tx_shift;    // shift register
    logic [2:0]  bit_idx;     // which data bit we're sending (0-7)
    logic        tx_busy;
    logic        tx_pin;      // the actual serial output bit

    // Latch incoming byte on write
    logic        tx_load;
    logic [7:0]  tx_byte;

    assign tx_load = write_en && (addr == ADDR_TX_DATA) && !tx_busy;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            tx_byte <= 8'h00;
        else if (tx_load)
            tx_byte <= write_data[7:0];
    end

    // TX FSM
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_state <= IDLE;
            tx_shift <= 8'hFF;
            bit_idx  <= '0;
            tx_busy  <= 1'b0;
            tx_pin   <= 1'b1;   // UART idle = high
        end else begin
            case (tx_state)
                IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_load) begin
                        // Transition happens next cycle when baud_tick fires,
                        // but we pre-arm immediately
                        tx_shift <= tx_byte;  // will be valid next cycle
                        tx_busy  <= 1'b1;
                        tx_state <= START;
                        bit_idx  <= '0;
                        // Reset baud counter so we get a full bit period
                        // (handled by always_ff above - baud_cnt keeps running,
                        //  we wait for next baud_tick naturally)
                    end
                end

                START: begin
                    if (baud_tick) begin
                        tx_pin   <= 1'b0;   // start bit
                        tx_shift <= tx_byte; // latch fresh (in case just loaded)
                        tx_state <= DATA;
                        bit_idx  <= '0;
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        tx_pin  <= tx_shift[0];       // LSB first (8N1 standard)
                        tx_shift <= {1'b1, tx_shift[7:1]}; // shift right, fill 1s
                        if (bit_idx == 3'd7) begin
                            tx_state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        tx_pin   <= 1'b1;   // stop bit
                        tx_busy  <= 1'b0;
                        tx_state <= IDLE;
                    end
                end
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Outputs
    // ----------------------------------------------------------------
    assign ready = 1'b1;   // peripheral never back-pressures the CPU bus

    // Read mux
    always_comb begin
        read_data = 32'h0;
        case (addr)
            ADDR_TX_DATA: read_data = 32'h0;                  // write-only
            ADDR_STATUS:  read_data = {31'h0, tx_busy};       // bit0 = busy
            ADDR_RX_DATA: read_data = 32'h0;                  // no RX
            default:      read_data = 32'h0;
        endcase
    end

    // Serial output pin - connect to D10 in top-level
    // In the top-level: assign uart_tx = uart_serial_out;
    // We expose it here as a separate port so the top-level can name it clearly
    // (uart_stub used assign uart_tx = uart_write_en which was wrong)

endmodule


// ---------------------------------------------------------------------------
// Thin wrapper that exactly matches uart_stub.sv's port list AND adds the
// real serial output pin. Drop-in for the instantiation in ooo_core_top.sv.
// ---------------------------------------------------------------------------
module uart_real (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] addr,
    input  logic        read_en,
    input  logic        write_en,
    input  logic [31:0] write_data,
    output logic [31:0] read_data,
    output logic        ready,
    output logic        serial_out   // wire this to uart_tx port in top-level
);
    uart_tx_core uart_core (
        .clk        (clk),
        .reset      (reset),
        .addr       (addr),
        .read_en    (read_en),
        .write_en   (write_en),
        .write_data (write_data),
        .read_data  (read_data),
        .ready      (ready)
    );

    // Drive serial_out from the core's tx_pin
    // We reach into the submodule hierarchy here. Alternatively promote tx_pin
    // to a port of uart_tx_core - either is fine for synthesis.
    assign serial_out = uart_core.tx_pin;

endmodule
