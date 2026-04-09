#!/usr/bin/env python3
"""
uart_load.py — Send a compiled binary to the LEGv8 UART bootloader.

Usage:
    python3 uart_load.py <binary.bin> [--port /dev/ttyUSB0] [--baud 115200]

On Windows (WSL): port is typically /dev/ttyS3 or /dev/ttyUSB0
Find it with: ls /dev/ttyS* or check Device Manager for "USB Serial Port (COMx)"
then use /dev/ttySx where x = COM number

Protocol:
    1. Wait for "READY\\r\\n" from board
    2. Send 4-byte big-endian payload size
    3. Send raw binary payload
    4. Wait for "OK\\r\\n"
    5. Done — board is running your code
"""

import sys
import serial
import struct
import time
import argparse


def find_port():
    """Try to auto-detect the Arty A7 UART port."""
    import glob
    candidates = (
        glob.glob('/dev/ttyUSB*') +
        glob.glob('/dev/ttyACM*') +
        glob.glob('/dev/ttyS[0-9]*')
    )
    return candidates[0] if candidates else None


def load(port: str, baud: int, binary_path: str, timeout: float = 10.0):
    payload = open(binary_path, 'rb').read()
    if not payload:
        print(f"error: empty binary '{binary_path}'")
        sys.exit(1)

    size = len(payload)
    print(f"[uart_load] payload: {binary_path}  ({size} bytes)")
    print(f"[uart_load] port: {port}  baud: {baud}")

    with serial.Serial(port, baud, timeout=timeout) as ser:
        ser.reset_input_buffer()

        # ----------------------------------------------------------
        # Step 1: Wait for "READY\r\n"
        # ----------------------------------------------------------
        print("[uart_load] waiting for READY...", end='', flush=True)
        deadline = time.time() + timeout
        buf = b''
        while time.time() < deadline:
            chunk = ser.read(ser.in_waiting or 1)
            if chunk:
                buf += chunk
                sys.stdout.write(chunk.decode('ascii', errors='replace'))
                sys.stdout.flush()
            if b'READY\r\n' in buf:
                break
        else:
            print("\nerror: timed out waiting for READY — is the board running the bootloader?")
            sys.exit(1)
        print("  ✓")

        # ----------------------------------------------------------
        # Step 2: Send 4-byte big-endian size
        # ----------------------------------------------------------
        size_bytes = struct.pack('>I', size)
        ser.write(size_bytes)
        print(f"[uart_load] sent size: {size} (0x{size:08X})")

        # ----------------------------------------------------------
        # Step 3: Send payload
        # ----------------------------------------------------------
        CHUNK = 64
        sent = 0
        while sent < size:
            chunk = payload[sent:sent + CHUNK]
            ser.write(chunk)
            sent += len(chunk)
            pct = sent * 100 // size
            bar = '█' * (pct // 5) + '░' * (20 - pct // 5)
            print(f"\r[uart_load] sending [{bar}] {pct:3d}%  {sent}/{size}B",
                  end='', flush=True)
        print()

        # ----------------------------------------------------------
        # Step 4: Wait for "OK\r\n"
        # ----------------------------------------------------------
        print("[uart_load] waiting for OK...", end='', flush=True)
        deadline = time.time() + timeout
        buf = b''
        while time.time() < deadline:
            chunk = ser.read(ser.in_waiting or 1)
            if chunk:
                buf += chunk
            if b'OK\r\n' in buf:
                break
        else:
            print("\nerror: timed out waiting for OK — payload may be corrupt")
            sys.exit(1)
        print("  ✓")

        # ----------------------------------------------------------
        # Step 5: Stay open as a serial monitor
        # ----------------------------------------------------------
        print("[uart_load] board running. serial monitor active (Ctrl+C to exit)\n")
        ser.timeout = 0.1
        try:
            while True:
                data = ser.read(ser.in_waiting or 1)
                if data:
                    sys.stdout.write(data.decode('ascii', errors='replace'))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            print("\n[uart_load] disconnected.")


def main():
    parser = argparse.ArgumentParser(description='LEGv8 UART bootloader client')
    parser.add_argument('binary', help='path to assembled .bin file')
    parser.add_argument('--port', default=None,
                        help='serial port (default: auto-detect)')
    parser.add_argument('--baud', type=int, default=115200,
                        help='baud rate (default: 115200)')
    parser.add_argument('--timeout', type=float, default=10.0,
                        help='timeout in seconds (default: 10)')
    args = parser.parse_args()

    port = args.port or find_port()
    if not port:
        print("error: no serial port found. Use --port /dev/ttyUSBx")
        sys.exit(1)

    load(port, args.baud, args.binary, args.timeout)


if __name__ == '__main__':
    main()
