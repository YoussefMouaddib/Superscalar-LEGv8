#!/usr/bin/env python3
"""
legv8_iss.py - tiny in-order reference simulator for the LEGv8 subset + the demo's devices.
Semantics follow the ASSEMBLER (encoder.cpp) and the intent of the RTL:
  X0 reads 0 and ignores writes; ADDI/SUBI/ANDI/ORI/EORI take a sign-extended imm16;
  LDR/STR = word, byte offset imm16 (sign-extended), must be 4-aligned; B/BL imm26 and CBZ/CBNZ imm21 are WORD offsets
  (target = pc + 4*imm), BL sets X30 = pc+4; RET Xn: pc = Xn; LSL/LSR (register form) shift by Xm[4:0].
  A zero word is treated as a NOP; any other unknown opcode raises.
Every store (RAM, VGA, IO) is appended to self.store_log as (pc, addr, value) in program order - this is the
reference trace to compare a hardware/RTL run against.
"""
import struct, sys, os

M32 = 0xFFFFFFFF
RAM_BASE, RAM_SIZE = 0x40000, 0x20000
IO_BASE, VGA_BASE = 0x20000, 0x30000
FRAME_ADDR = IO_BASE + 0x100

def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v

class Machine:
    def __init__(s, binfile, insns_per_frame=3000, ram_init=None):
        data = open(binfile, "rb").read()
        s.rom = list(struct.unpack("<%dI" % (len(data)//4), data))
        s.ram = bytearray(RAM_SIZE)          # RAM powers up zeroed (same as the RTL when no init file is used)
        ram_init = ram_init or os.environ.get("DEMO_RAM_INIT")   # plain hex file, one 32-bit word per line
        if ram_init:
            words = [int(l.strip(), 16) for l in open(ram_init) if l.strip()]
            if len(words)*4 > RAM_SIZE: raise RuntimeError("ram init file larger than RAM")
            for i, w in enumerate(words): struct.pack_into("<I", s.ram, 4*i, w)
        s.R = [0]*32; s.pc = 0; s.icount = 0
        s.keys = []                 # keys waiting in the FIFO
        s.key_schedule = []         # (frame, key) injected when frame counter reaches it
        s.insns_per_frame = insns_per_frame
        s.vga = [0x20]*2400
        s.store_log = []
        s.log_stores = False
        s.hook = None               # optional per-frame callback(machine)
        s.last_frame = 0

    @property
    def frame(s): return s.icount // s.insns_per_frame

    def _tick_devices(s):
        f = s.frame
        if f != s.last_frame:
            s.last_frame = f
            while s.key_schedule and s.key_schedule[0][0] <= f:
                s.keys.append(s.key_schedule.pop(0)[1])
            if s.hook: s.hook(s)

    def load(s, a):
        if a & 3: raise RuntimeError(f"misaligned load {a:#x} pc={s.pc:#x}")
        if RAM_BASE <= a < RAM_BASE + RAM_SIZE:
            o = a - RAM_BASE; return struct.unpack_from("<I", s.ram, o)[0]
        if a == IO_BASE:     return 1 if s.keys else 0
        if a == IO_BASE + 4: return s.keys[0] if s.keys else 0
        if a == FRAME_ADDR:  return s.frame & M32
        return 0

    def store(s, a, v):
        if a & 3: raise RuntimeError(f"misaligned store {a:#x} pc={s.pc:#x}")
        v &= M32
        if s.log_stores: s.store_log.append((s.pc, a, v))
        if RAM_BASE <= a < RAM_BASE + RAM_SIZE:
            struct.pack_into("<I", s.ram, a - RAM_BASE, v)
        elif a == IO_BASE + 8:
            if s.keys: s.keys.pop(0)
        elif VGA_BASE <= a < VGA_BASE + 2400*4:
            s.vga[(a - VGA_BASE) >> 2] = v
        else:
            raise RuntimeError(f"store to unmapped {a:#x} pc={s.pc:#x}")

    def ramword(s, off): return struct.unpack_from("<I", s.ram, off)[0]

    def step(s):
        pc = s.pc
        if pc >> 2 >= len(s.rom): raise RuntimeError(f"pc {pc:#x} outside ROM")
        w = s.rom[pc >> 2]; s.icount += 1; s._tick_devices()
        R = s.R; npc = pc + 4
        if w == 0: s.pc = npc; return
        op = w >> 26; rd = (w >> 21) & 31; rn = (w >> 16) & 31; rm = (w >> 11) & 31
        def wr(r, v):
            if r: R[r] = v & M32
        if op == 0:
            f = w & 63; a, b = R[rn] if rn else 0, R[rm] if rm else 0
            if   f == 0x20: wr(rd, a + b)
            elif f == 0x22: wr(rd, a - b)
            elif f == 0x24: wr(rd, a & b)
            elif f == 0x25: wr(rd, a | b)
            elif f == 0x26: wr(rd, a ^ b)
            elif f == 0x28: wr(rd, -a)
            elif f == 0x2A: pass
            elif f in (0, 1): wr(rd, a << (b & 31))
            elif f in (2, 3): wr(rd, a >> (b & 31))
            elif f == 0x38: npc = a
            else: raise RuntimeError(f"bad R func {f:#x} pc={pc:#x}")
            if f in (1, 3): raise RuntimeError(f"immediate shift used at pc={pc:#x} (not supported by current RTL)")
        elif 8 <= op <= 12:
            a = R[rn] if rn else 0; i = sext(w, 16) & M32
            wr(rd, [a+i, a-i, a&i, a|i, a^i][op-8])
        elif op in (0x10, 0x12):
            wr(rd, s.load((R[rn] if rn else 0) + sext(w, 16)))
        elif op in (0x11, 0x13):
            s.store((R[rn] if rn else 0) + sext(w, 16), R[rd] if rd else 0)
        elif op in (0x18, 0x19):
            z = (R[rd] if rd else 0) == 0
            if z == (op == 0x18): npc = pc + 4*sext(w, 21)
        elif op in (0x20, 0x21):
            if op == 0x21: R[30] = pc + 4
            npc = pc + 4*sext(w, 26)
        else:
            raise RuntimeError(f"illegal opcode {op:#x} pc={pc:#x}")
        s.pc = npc & M32

    def run(s, max_insns, until=None):
        end = s.icount + max_insns
        while s.icount < end:
            s.step()
            if until and until(s): return True
        return False

    # ---------- helpers for tests
    def type_line(s, text):
        for ch in text: s.keys.append(ord(ch))
        s.keys.append(13)

CP437 = {0xDB: '#', 0xB1: '+', 0x5F: '_'}
def screen_text(vga, with_attr=False):
    rows = []
    for r in range(30):
        row = ""
        for c in range(80):
            v = vga[r*80 + c]; ch = v & 0xFF
            row += CP437.get(ch, chr(ch) if 32 <= ch < 127 else "?")
        rows.append(row.rstrip())
    return rows
