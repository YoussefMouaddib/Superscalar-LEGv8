# =============================================================
# Superscalar-LEGv8 Software Makefile
# Usage:
#   make all          — build assembler + assemble all targets
#   make hello        — assemble baremetal hello_uart
#   make bootloader   — assemble UART bootloader (.coe for Vivado)
#   make load FILE=x  — send a .bin to the board via UART
#   make monitor      — open serial monitor only
#   make clean        — remove all build artifacts
# =============================================================

AS      := assembler/legv8-as
PYTHON  := python3
PORT    ?= /dev/ttyUSB0
BAUD    := 115200

LOAD_BASE_IROM := 0x00000000
LOAD_BASE_DATA := 0x00002000

.PHONY: all assembler hello bootloader load monitor clean

# ------------------------------------------------------------------
all: assembler hello bootloader

# ------------------------------------------------------------------
assembler:
	$(MAKE) -C assembler

# ------------------------------------------------------------------
hello: assembler
	$(AS) baremetal/hello_uart.s \
	      --base $(LOAD_BASE_IROM) \
	      -o baremetal/hello_uart.coe -f coe \
	      -l baremetal/hello_uart.lst
	@echo "→  baremetal/hello_uart.coe  (load into Vivado BRAM init)"
	@echo "→  baremetal/hello_uart.lst  (listing for inspection)"

# ------------------------------------------------------------------
bootloader: assembler
	$(AS) bootloader/uart_bootloader.s \
	      --base $(LOAD_BASE_IROM) \
	      -o bootloader/uart_bootloader.coe -f coe \
	      -l bootloader/uart_bootloader.lst \
	      --dump-symbols
	@echo "→  bootloader/uart_bootloader.coe  (permanent BRAM image)"
	@echo ""
	@echo "  Load uart_bootloader.coe into your inst_rom BRAM in Vivado."
	@echo "  After that, use 'make load FILE=<bin>' for all future programs."

# ------------------------------------------------------------------
# Send a .bin to the running bootloader
# Example: make load FILE=baremetal/hello_uart.bin
load:
ifndef FILE
	@echo "Usage: make load FILE=path/to/program.bin"
	@exit 1
endif
	$(PYTHON) tools/uart_load.py $(FILE) --port $(PORT) --baud $(BAUD)

# ------------------------------------------------------------------
monitor:
	$(PYTHON) tools/uart_load.py /dev/null --port $(PORT) --baud $(BAUD) || \
	    python3 -c "import serial; \
	    import sys; \
	    s=serial.Serial('$(PORT)', $(BAUD), timeout=0.1); \
	    print('monitor open — Ctrl+C to exit'); \
	    [sys.stdout.write(s.read(s.in_waiting or 1).decode('ascii','replace')) \
	     or None for _ in iter(int, 1)]"

# ------------------------------------------------------------------
clean:
	$(MAKE) -C assembler clean
	rm -f baremetal/*.bin baremetal/*.coe baremetal/*.lst
	rm -f bootloader/*.bin bootloader/*.coe bootloader/*.lst
