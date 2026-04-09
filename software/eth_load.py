#!/usr/bin/env python3
"""
eth_load.py - UDP program loader for OOO core
Replaces uart_load.py for Ethernet-based program loading.

Protocol (matching eth_prog_loader.sv):
    [4 bytes] Magic: 0xDEAD_BEEF (big-endian)
    [4 bytes] Byte count N (big-endian)
    [N bytes] Raw binary (little-endian 32-bit words, same as UART loader)

Requirements:
    - Board must be on local LAN, same subnet as your machine
    - Static ARP entry must be set (one-time setup, see below)
    - Binary must be <= 8192 bytes (instruction ROM size)

One-time WSL setup (run once, survives until network restart):
    sudo arp -s 192.168.1.50 aa:bb:cc:dd:ee:ff
    (replace IP and MAC with your board's actual values)

    Or on Windows host:
    netsh interface ipv4 add neighbors "Ethernet" 192.168.1.50 aa-bb-cc-dd-ee-ff

Usage:
    python3 eth_load.py program.bin
    python3 eth_load.py program.bin --ip 192.168.1.50 --port 5000
    python3 eth_load.py program.bin --verify  # check response (future)

The board holds the OOO core in reset while receiving, releases reset
when loading is complete. You should see your program's output on VGA
within ~100ms of sending.
"""

import socket
import struct
import sys
import os
import time
import argparse

# ---------------------------------------------------------------------------
# Configuration defaults - edit these or pass as CLI args
# ---------------------------------------------------------------------------
DEFAULT_BOARD_IP   = "192.168.1.50"
DEFAULT_BOARD_PORT = 5000
DEFAULT_BOARD_MAC  = "00:18:3e:01:ff:ff"  # LAN8720 default - set in RTL params
MAGIC              = 0xDEADBEEF
MAX_PROGRAM_BYTES  = 8192   # instruction ROM size

# ---------------------------------------------------------------------------
# Protocol
# ---------------------------------------------------------------------------
def build_packet(binary: bytes) -> bytes:
    """Build the UDP payload for the board's loader FSM."""
    header = struct.pack(">II", MAGIC, len(binary))
    return header + binary


def load_program(binary_path: str, board_ip: str, board_port: int,
                 verbose: bool = True) -> bool:
    """Send a binary to the board over UDP. Returns True on success."""

    # Load file
    if not os.path.exists(binary_path):
        print(f"ERROR: File not found: {binary_path}")
        return False

    with open(binary_path, "rb") as f:
        binary = f.read()

    if len(binary) == 0:
        print("ERROR: Empty binary file")
        return False

    if len(binary) > MAX_PROGRAM_BYTES:
        print(f"ERROR: Binary too large: {len(binary)} bytes > {MAX_PROGRAM_BYTES} max")
        print(f"       Instruction ROM is {MAX_PROGRAM_BYTES} bytes (8 KB)")
        return False

    # Pad to 4-byte alignment (instruction ROM is word-addressed)
    if len(binary) % 4 != 0:
        pad = 4 - (len(binary) % 4)
        binary += b'\x00' * pad
        if verbose:
            print(f"  Padded binary to {len(binary)} bytes (4-byte alignment)")

    packet = build_packet(binary)

    if verbose:
        print(f"Loading {binary_path}")
        print(f"  Binary size:  {len(binary)} bytes ({len(binary)//4} instructions)")
        print(f"  Packet size:  {len(packet)} bytes (header + payload)")
        print(f"  Target:       {board_ip}:{board_port}")
        print(f"  Magic:        0x{MAGIC:08X}")

    # Send
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2.0)

    try:
        t0 = time.monotonic()
        bytes_sent = sock.sendto(packet, (board_ip, board_port))
        t1 = time.monotonic()

        if bytes_sent != len(packet):
            print(f"ERROR: Only sent {bytes_sent}/{len(packet)} bytes")
            return False

        if verbose:
            elapsed_ms = (t1 - t0) * 1000
            print(f"  Sent {bytes_sent} bytes in {elapsed_ms:.1f} ms")
            print(f"  Board should be executing in ~100ms")
            print(f"  Check VGA display for output")

        return True

    except socket.timeout:
        print("ERROR: Send timed out (is the board on the network?)")
        return False
    except OSError as e:
        if "Network is unreachable" in str(e):
            print(f"ERROR: Network unreachable - check that {board_ip} is on your subnet")
            print(f"       WSL users: run 'ip route' and verify your network adapter")
        elif "No route to host" in str(e):
            print(f"ERROR: No route to {board_ip}")
            print(f"       Run: sudo arp -s {board_ip} {DEFAULT_BOARD_MAC}")
        else:
            print(f"ERROR: {e}")
        return False
    finally:
        sock.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="UDP program loader for OOO LEGv8 core",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Examples:
  python3 eth_load.py hello_uart.bin
  python3 eth_load.py program.bin --ip 192.168.1.100 --port 5000

One-time ARP setup (WSL/Linux):
  sudo arp -s {DEFAULT_BOARD_IP} {DEFAULT_BOARD_MAC}

One-time ARP setup (Windows PowerShell as admin):
  netsh interface ipv4 add neighbors "Ethernet" {DEFAULT_BOARD_IP} {DEFAULT_BOARD_MAC.replace(':', '-')}
        """
    )
    parser.add_argument("binary", help="Path to .bin file to load")
    parser.add_argument("--ip",   default=DEFAULT_BOARD_IP,
                        help=f"Board IP address (default: {DEFAULT_BOARD_IP})")
    parser.add_argument("--port", type=int, default=DEFAULT_BOARD_PORT,
                        help=f"Board UDP port (default: {DEFAULT_BOARD_PORT})")
    parser.add_argument("--quiet", action="store_true",
                        help="Suppress progress output")

    args = parser.parse_args()

    success = load_program(
        binary_path=args.binary,
        board_ip=args.ip,
        board_port=args.port,
        verbose=not args.quiet
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
