#!/usr/bin/env python3
"""
build_demo.py - generates demo.s (LEGv8 assembly) for the standalone terminal + RAM files + snake demo.

The assembler has no constants/macros, so this script is a thin host-side macro expander.
Its output (demo.s) is plain LEGv8 assembly for legv8-as.  Nothing here runs on the CPU.

HARDWARE CONTRACT (edit the constants below if your addresses differ)
  RAM        0x40000 ..            word-aligned LDR/STR, one char per 32-bit word. Needs ~0xC000 used + stack.
  IO base    0x20000  +0x00 KBD_STATUS (bit0 = key waiting)  +0x04 KBD_DATA (ASCII, no side effects on read)
                      +0x08 KBD_ACK (any store pops one key)  +0x100 FRAME (free-running, +1 per vsync)
  VGA        0x30000 + cell*4  (bits 7:0 char, 9:8 colour)
  Key codes  printable ASCII, 8=backspace, 13=enter, 27=esc, 0x81 up, 0x82 down, 0x83 left, 0x84 right
             (key press events only - no release events)

REGISTER CONVENTION
  X0  = zero (never written)         X31 = assembler scratch (compare macros)
  X23 = 31, X24 = 2 (shift amounts)  X25 = VGA base  X26 = IO base  X27 = RAM base + 0x8000
  X28 = SP, X30 = LR                 X29 unused
  X1-X8   clobbered by level-0 helpers (scr_putc, cell_write, scroll, pollkey, draw2 ...)
  X9-X14  clobbered by level-1 helpers (puts, dec_to_buf, strcmp, gfx_puts, getkey ...)
  X15-X22 owned by level-2 code (readline, fs_*, cmd_*, snake_game); survive calls to level 0/1
"""
import sys, argparse

ap = argparse.ArgumentParser(description="Generate the LEGv8 demo assembly (and optionally the RAM init file).")
ap.add_argument("out", nargs="?", default="demo.s", help="assembly output file")
ap.add_argument("--strings", choices=["ram", "code"], default="ram",
                help="ram: strings come from a preloaded RAM image (ram_init.mem), boot code is small. "
                     "code: boot code stores every character itself (RAM can start zeroed, no init file needed)")
ap.add_argument("--mem", default="ram_init.mem", help="RAM init file written when --strings=ram")
ARGS = ap.parse_args()

RAM_BASE   = 0x40000
RAM_BIAS   = 0x8000
SP_INIT    = 0x5FFF0
IO_BASE    = 0x20000
VGA_BASE   = 0x30000

# ---- RAM layout (byte offsets from RAM_BASE; all must be < 0x10000) ----
VARS    = 0x0000
STRS    = 0x0400
LINEBUF = 0x1400   # 96 words
NUMBUF  = 0x1580   # 16 words
SHADOW  = 0x1600   # 2400 words
FS      = 0x3C00   # 16 records * 1088 bytes
BODY    = 0x8000   # 1024 words (snake ring buffer of screen cell indices)
GRID    = 0x9000   # 2400 words (0 empty, 1 snake, 2 wall)

NFILES, RECBYTES = 16, 1088   # rec: [0]=used [4..55]=name(13 words) [56]=size [64..]=data(256 words)
VAR_NAMES = ["CUR_IDX","CUR_COL","CUR_ATTR","RNG","FOOD","LASTF","CMDP","ARG1P","ARG2P"]
VOFF = {n: VARS + 4*i for i, n in enumerate(VAR_NAMES)}

def r(off):               # imm16 for [X27, #imm] addressing RAM_BASE+off
    v = off - RAM_BIAS
    assert -32768 <= v <= 32767, hex(off)
    return v

STRINGS = [
 ("S_BANNER", "LEGv8 2-way OoO computer\n"),
 ("S_HINT",   "Type help for commands.\n"),
 ("S_PROMPT", "> "),
 ("S_HELP1",  "ls  create N  write N TEXT\n"),
 ("S_HELP2",  "cat N  rm N  clear  snake\n"),
 ("S_UNKNOWN","unknown command\n"),
 ("S_UCREATE","usage: create NAME\n"),
 ("S_UWRITE", "usage: write NAME TEXT\n"),
 ("S_UCAT",   "usage: cat NAME\n"),
 ("S_URM",    "usage: rm NAME\n"),
 ("S_NOFILE", "no such file\n"),
 ("S_EXISTS", "file exists\n"),
 ("S_FULL",   "disk full\n"),
 ("S_LONG",   "name too long\n"),
 ("S_NONE",   "(no files)\n"),
 ("C_HELP","help"),("C_LS","ls"),("C_CREATE","create"),("C_WRITE","write"),
 ("C_CAT","cat"),("C_RM","rm"),("C_CLEAR","clear"),("C_SNAKE","snake"),
 ("S_SCORE",  "SCORE: "),
 ("S_QUIT",   "Q=QUIT"),
 ("S_OVER",   "GAME OVER"),
 ("S_FINAL",  "FINAL SCORE: "),
 ("S_ANYKEY", "PRESS ANY KEY"),
]
SOFF, _o = {}, STRS
for n, t in STRINGS:
    SOFF[n] = _o; _o += 4 * (len(t) + 1)
assert _o <= LINEBUF, "string area overflow"

class Asm:
    def __init__(s): s.out = []; s.n = 0
    def raw(s, t): s.out.append(t)
    def i(s, t): s.out.append("    " + t)
    def c(s, t): s.out.append("    ; " + t)
    def label(s, n): s.out.append(n + ":")
    def new(s, p="L"): s.n += 1; return f"{p}{s.n}"
    def func(s, name, doc):
        s.out.append(""); s.out.append("; " + "-"*70); s.out.append("; " + doc); s.label(name)
    # --- basic macros
    def li(s, rd, v):
        v &= 0xFFFFFFFF
        if v >= 0x80000000: v -= 1 << 32
        if -32768 <= v <= 32767: s.i(f"ADDI X{rd}, X0, #{v}"); return
        hi = (v + 0x8000) >> 16; lo = v - (hi << 16)
        s.i(f"ADDI X{rd}, X0, #{hi}"); s.i("ADDI X31, X0, #16"); s.i(f"LSL X{rd}, X{rd}, X31")
        if lo: s.i(f"ADDI X{rd}, X{rd}, #{lo}")
    def mov(s, d, a): s.i(f"ADD X{d}, X{a}, X0")
    def ldv(s, d, v): s.i(f"LDR X{d}, [X27, #{r(VOFF[v])}]")
    def stv(s, a, v): s.i(f"STR X{a}, [X27, #{r(VOFF[v])}]")
    def push(s, reg=30): s.i("SUBI X28, X28, #4"); s.i(f"STR X{reg}, [X28, #0]")
    def pop(s, reg=30):  s.i(f"LDR X{reg}, [X28, #0]"); s.i("ADDI X28, X28, #4")
    def call(s, f): s.i(f"BL {f}")
    def ret(s): s.i("RET X30")
    def b(s, l): s.i(f"B {l}")
    # --- compare/branch macros (signed, small values only; no flags in this ISA)
    def beq(s, a, b, L):  s.i(f"SUB X31, X{a}, X{b}"); s.i(f"CBZ X31, {L}")
    def bne(s, a, b, L):  s.i(f"SUB X31, X{a}, X{b}"); s.i(f"CBNZ X31, {L}")
    def blt(s, a, b, L):  s.i(f"SUB X31, X{a}, X{b}"); s.i("LSR X31, X31, X23"); s.i(f"CBNZ X31, {L}")
    def bge(s, a, b, L):  s.i(f"SUB X31, X{a}, X{b}"); s.i("LSR X31, X31, X23"); s.i(f"CBZ X31, {L}")
    def beqi(s, a, v, L): s.i(f"SUBI X31, X{a}, #{v}"); s.i(f"CBZ X31, {L}")
    def bnei(s, a, v, L): s.i(f"SUBI X31, X{a}, #{v}"); s.i(f"CBNZ X31, {L}")
    def blti(s, a, v, L): s.i(f"SUBI X31, X{a}, #{v}"); s.i("LSR X31, X31, X23"); s.i(f"CBNZ X31, {L}")
    def bgei(s, a, v, L): s.i(f"SUBI X31, X{a}, #{v}"); s.i("LSR X31, X31, X23"); s.i(f"CBZ X31, {L}")
    def say(s, name): s.i(f"ADDI X1, X27, #{r(SOFF[name])}"); s.call("puts")

A = Asm()

# =====================================================================
# BOOT
# =====================================================================
def boot():
    A.raw("; LEGv8 demo: terminal + RAM file system + snake.  GENERATED by build_demo.py - do not hand edit.")
    A.raw("; Code lives in ROM at 0x0. All data (strings, files, screen copy) lives in RAM.")
    A.label("_start")
    A.li(28, SP_INIT); A.li(27, RAM_BASE + RAM_BIAS); A.li(25, VGA_BASE); A.li(26, IO_BASE)
    A.i("ADDI X24, X0, #2"); A.i("ADDI X23, X0, #31")
    A.c("variables")
    for v in ["CUR_IDX","CUR_COL","CUR_ATTR","FOOD","LASTF","CMDP","ARG1P","ARG2P"]: A.stv(0, v)
    A.li(1, 0x2545F491); A.stv(1, "RNG")
    if ARGS.strings == "code":
        A.c("build string table in RAM (one char per word)")
        for n, t in STRINGS:
            base = SOFF[n]
            for k, ch in enumerate(t):
                A.i(f"ADDI X1, X0, #{ord(ch)}"); A.i(f"STR X1, [X27, #{r(base + 4*k)}]")
            A.i(f"STR X0, [X27, #{r(base + 4*len(t))}]")
    else:
        A.c(f"string table is NOT built here: it is preloaded from {ARGS.mem} (see build_demo.py --strings=ram)")
    A.c("mark every file record unused")
    A.i(f"ADDI X5, X27, #{r(FS)}"); A.i("ADDI X6, X0, #0")
    A.label("boot_fs"); A.i("STR X0, [X5, #0]"); A.i(f"ADDI X5, X5, #{RECBYTES}"); A.i("ADDI X6, X6, #1")
    A.bnei(6, NFILES, "boot_fs")
    A.call("clear_screen")
    A.say("S_BANNER"); A.say("S_HINT")
    # ---- main loop
    A.label("main_loop")
    A.say("S_PROMPT"); A.call("readline"); A.call("parse_line")
    A.ldv(19, "CMDP"); A.i("LDR X1, [X19, #0]"); A.i("CBZ X1, main_loop")
    for cname, fn in [("C_HELP","cmd_help"),("C_LS","cmd_ls"),("C_CREATE","cmd_create"),("C_WRITE","cmd_write"),
                      ("C_CAT","cmd_cat"),("C_RM","cmd_rm"),("C_CLEAR","clear_screen"),("C_SNAKE","cmd_snake")]:
        nxt = A.new("nx")
        A.mov(1, 19); A.i(f"ADDI X2, X27, #{r(SOFF[cname])}"); A.call("strcmp")
        A.i(f"CBNZ X1, {nxt}"); A.call(fn); A.b("main_loop"); A.label(nxt)
    A.say("S_UNKNOWN"); A.b("main_loop")

# =====================================================================
# LEVEL 0: screen / keyboard primitives (X1-X8)
# =====================================================================
def level0():
    A.func("cell_write", "X2=cell idx, X4=value -> write VGA + shadow. clobbers X5,X6")
    A.i("LSL X5, X2, X24"); A.i("ADD X6, X5, X25"); A.i("STR X4, [X6, #0]")
    A.i("ADD X5, X5, X27"); A.i(f"STR X4, [X5, #{r(SHADOW)}]"); A.ret()

    A.func("scr_putc", "X1=char. prints at cursor; handles \\n, backspace(8), wrap, scroll. clobbers X1-X8")
    A.push()
    A.beqi(1, 10, "sp_nl"); A.beqi(1, 8, "sp_bs")
    A.ldv(2, "CUR_IDX"); A.ldv(3, "CUR_ATTR"); A.i("ORR X4, X1, X3"); A.call("cell_write")
    A.i("ADDI X2, X2, #1"); A.stv(2, "CUR_IDX")
    A.ldv(3, "CUR_COL"); A.i("ADDI X3, X3, #1"); A.beqi(3, 80, "sp_wrap")
    A.stv(3, "CUR_COL"); A.b("sp_chk")
    A.label("sp_wrap"); A.stv(0, "CUR_COL"); A.b("sp_chk")
    A.label("sp_nl")
    A.ldv(2, "CUR_IDX"); A.ldv(3, "CUR_COL"); A.i("ADDI X4, X0, #80"); A.i("SUB X4, X4, X3"); A.i("ADD X2, X2, X4")
    A.stv(2, "CUR_IDX"); A.stv(0, "CUR_COL"); A.b("sp_chk")
    A.label("sp_bs")
    A.ldv(3, "CUR_COL"); A.i("CBZ X3, sp_done")
    A.ldv(2, "CUR_IDX"); A.i("SUBI X2, X2, #1"); A.stv(2, "CUR_IDX")
    A.i("SUBI X3, X3, #1"); A.stv(3, "CUR_COL")
    A.ldv(4, "CUR_ATTR"); A.i("ADDI X4, X4, #32"); A.call("cell_write"); A.b("sp_done")
    A.label("sp_chk"); A.ldv(2, "CUR_IDX"); A.bgei(2, 2400, "sp_scroll"); A.b("sp_done")
    A.label("sp_scroll"); A.call("scroll")
    A.label("sp_done"); A.pop(); A.ret()

    A.func("scroll", "scroll text up one row (shadow + VGA), cursor to start of last row. clobbers X1-X8")
    A.i(f"ADDI X5, X27, #{r(SHADOW)}"); A.i("ADD X8, X25, X0"); A.i("ADDI X6, X0, #0")
    A.label("sc_cp")
    A.i("LDR X7, [X5, #320]"); A.i("STR X7, [X5, #0]"); A.i("STR X7, [X8, #0]")
    A.i("ADDI X5, X5, #4"); A.i("ADDI X8, X8, #4"); A.i("ADDI X6, X6, #1"); A.bnei(6, 2320, "sc_cp")
    A.ldv(3, "CUR_ATTR"); A.i("ADDI X4, X3, #32"); A.i("ADDI X6, X0, #0")
    A.label("sc_cl")
    A.i("STR X4, [X5, #0]"); A.i("STR X4, [X8, #0]")
    A.i("ADDI X5, X5, #4"); A.i("ADDI X8, X8, #4"); A.i("ADDI X6, X6, #1"); A.bnei(6, 80, "sc_cl")
    A.li(2, 2320); A.stv(2, "CUR_IDX"); A.stv(0, "CUR_COL"); A.ret()

    A.func("clear_screen", "blank shadow + VGA, cursor home. clobbers X1-X8")
    A.i("ADDI X4, X0, #32"); A.i(f"ADDI X5, X27, #{r(SHADOW)}"); A.i("ADD X6, X25, X0"); A.i("ADDI X7, X0, #0")
    A.label("cs_l")
    A.i("STR X4, [X5, #0]"); A.i("STR X4, [X6, #0]")
    A.i("ADDI X5, X5, #4"); A.i("ADDI X6, X6, #4"); A.i("ADDI X7, X7, #1"); A.bnei(7, 2400, "cs_l")
    A.stv(0, "CUR_IDX"); A.stv(0, "CUR_COL"); A.ret()

    A.func("redraw_all", "copy shadow -> VGA (restore terminal after snake). clobbers X4-X7")
    A.i(f"ADDI X5, X27, #{r(SHADOW)}"); A.i("ADD X6, X25, X0"); A.i("ADDI X7, X0, #0")
    A.label("ra_l")
    A.i("LDR X4, [X5, #0]"); A.i("STR X4, [X6, #0]")
    A.i("ADDI X5, X5, #4"); A.i("ADDI X6, X6, #4"); A.i("ADDI X7, X7, #1"); A.bnei(7, 2400, "ra_l")
    A.ret()

    A.func("vga_fill", "X4=value -> fill all 2400 VGA cells (not the shadow). clobbers X6,X7")
    A.i("ADD X6, X25, X0"); A.i("ADDI X7, X0, #0")
    A.label("vf_l"); A.i("STR X4, [X6, #0]"); A.i("ADDI X6, X6, #4"); A.i("ADDI X7, X7, #1"); A.bnei(7, 2400, "vf_l")
    A.ret()

    A.func("cursor_on", "draw yellow underscore at cursor (VGA only). clobbers X2,X4,X5")
    A.ldv(2, "CUR_IDX"); A.i("LSL X5, X2, X24"); A.i("ADD X5, X5, X25"); A.i("ADDI X4, X0, #607"); A.i("STR X4, [X5, #0]"); A.ret()
    A.func("cursor_off", "restore cell under cursor from shadow. clobbers X2,X4,X5,X6")
    A.ldv(2, "CUR_IDX"); A.i("LSL X5, X2, X24"); A.i("ADD X6, X5, X25"); A.i("ADD X5, X5, X27")
    A.i(f"LDR X4, [X5, #{r(SHADOW)}]"); A.i("STR X4, [X6, #0]"); A.ret()

    A.func("pollkey", "-> X1 = key code or 0 if none (pops it). clobbers X1,X2")
    A.i("LDR X2, [X26, #0]"); A.i("CBZ X2, pk_none")
    A.i("LDR X1, [X26, #4]"); A.i("STR X1, [X26, #8]"); A.ret()
    A.label("pk_none"); A.i("ADDI X1, X0, #0"); A.ret()

    A.func("rng_next", "xorshift32 -> X1. clobbers X1-X3")
    A.ldv(1, "RNG")
    for sh, op in ((13, "LSL"), (17, "LSR"), (5, "LSL")):
        A.i(f"ADDI X2, X0, #{sh}"); A.i(f"{op} X3, X1, X2"); A.i("EOR X1, X1, X3")
    A.stv(1, "RNG"); A.ret()

    A.func("draw2", "X1=cell idx, X2=value -> VGA cells idx and idx+1 (snake cells are 2 chars wide). clobbers X3")
    A.i("LSL X3, X1, X24"); A.i("ADD X3, X3, X25"); A.i("STR X2, [X3, #0]"); A.i("STR X2, [X3, #4]"); A.ret()
    A.func("mark_cell", "X1=cell idx -> GRID[idx]=GRID[idx+1]=1. clobbers X3,X4")
    A.i("LSL X3, X1, X24"); A.i("ADD X3, X3, X27"); A.i("ADDI X4, X0, #1")
    A.i(f"STR X4, [X3, #{r(GRID)}]"); A.i(f"STR X4, [X3, #{r(GRID)+4}]"); A.ret()
    A.func("put_wall", "X1=cell idx -> draw wall + GRID=2 on idx,idx+1. clobbers X3-X6")
    A.i("LSL X3, X1, X24"); A.i("ADD X4, X3, X25"); A.i("ADDI X5, X0, #177")
    A.i("STR X5, [X4, #0]"); A.i("STR X5, [X4, #4]")
    A.i("ADD X3, X3, X27"); A.i("ADDI X6, X0, #2")
    A.i(f"STR X6, [X3, #{r(GRID)}]"); A.i(f"STR X6, [X3, #{r(GRID)+4}]"); A.ret()

# =====================================================================
# LEVEL 1: strings / numbers (X9-X14)
# =====================================================================
def level1():
    A.func("puts", "X1=ptr to 0-terminated word string -> print. clobbers X1-X10")
    A.push(); A.mov(9, 1)
    A.label("pu_l"); A.i("LDR X1, [X9, #0]"); A.i("CBZ X1, pu_d"); A.call("scr_putc"); A.i("ADDI X9, X9, #4"); A.b("pu_l")
    A.label("pu_d"); A.pop(); A.ret()

    A.func("gfx_puts", "X1=cell idx, X2=ptr, X3=attr(<<8) -> draw string straight to VGA. clobbers X9-X11")
    A.mov(9, 2); A.i("LSL X10, X1, X24"); A.i("ADD X10, X10, X25")
    A.label("gp_l"); A.i("LDR X11, [X9, #0]"); A.i("CBZ X11, gp_d"); A.i("ORR X11, X11, X3"); A.i("STR X11, [X10, #0]")
    A.i("ADDI X9, X9, #4"); A.i("ADDI X10, X10, #4"); A.b("gp_l")
    A.label("gp_d"); A.ret()

    A.func("strcmp", "X1=a, X2=b -> X1=0 if equal else 1. clobbers X1,X2,X9-X11")
    A.label("sm_l"); A.i("LDR X9, [X1, #0]"); A.i("LDR X10, [X2, #0]"); A.i("SUB X11, X9, X10"); A.i("CBNZ X11, sm_ne")
    A.i("CBZ X9, sm_eq"); A.i("ADDI X1, X1, #4"); A.i("ADDI X2, X2, #4"); A.b("sm_l")
    A.label("sm_eq"); A.i("ADDI X1, X0, #0"); A.ret()
    A.label("sm_ne"); A.i("ADDI X1, X0, #1"); A.ret()

    A.func("strlen", "X1=ptr -> X1=length. clobbers X9-X11")
    A.mov(9, 1); A.i("ADDI X10, X0, #0")
    A.label("sl_l"); A.i("LDR X11, [X9, #0]"); A.i("CBZ X11, sl_d"); A.i("ADDI X9, X9, #4"); A.i("ADDI X10, X10, #1"); A.b("sl_l")
    A.label("sl_d"); A.mov(1, 10); A.ret()

    A.func("strcpy", "X1=dst, X2=src (copies the NUL too). clobbers X1,X2,X9")
    A.label("sy_l"); A.i("LDR X9, [X2, #0]"); A.i("STR X9, [X1, #0]"); A.i("CBZ X9, sy_d")
    A.i("ADDI X1, X1, #4"); A.i("ADDI X2, X2, #4"); A.b("sy_l")
    A.label("sy_d"); A.ret()

    A.func("strcpy_lim", "X1=dst, X2=src, X3=max chars -> X1=chars copied; always NUL terminates. clobbers X1-X3,X9,X10")
    A.i("ADDI X10, X0, #0")
    A.label("sq_l"); A.i("CBZ X3, sq_t"); A.i("LDR X9, [X2, #0]"); A.i("CBZ X9, sq_t")
    A.i("STR X9, [X1, #0]"); A.i("ADDI X1, X1, #4"); A.i("ADDI X2, X2, #4"); A.i("ADDI X10, X10, #1"); A.i("SUBI X3, X3, #1"); A.b("sq_l")
    A.label("sq_t"); A.i("STR X0, [X1, #0]"); A.mov(1, 10); A.ret()

    A.func("getkey", "-> X1 = next key (blocks). clobbers X1,X2")
    A.push(); A.label("gk_l"); A.call("pollkey"); A.i("CBZ X1, gk_l"); A.pop(); A.ret()

    A.func("dec_to_buf", "X1=unsigned value (<100000), X2=buf -> decimal digits as words, NUL terminated. clobbers X9-X14")
    A.mov(9, 1); A.mov(10, 2); A.i("ADDI X11, X0, #0")
    for div in (10000, 1000, 100, 10, 1):
        lp, en, sk = A.new("dd"), A.new("dd"), A.new("dd")
        A.i("ADDI X12, X0, #0")
        A.label(lp); A.i(f"SUBI X13, X9, #{div}"); A.i("LSR X14, X13, X23"); A.i(f"CBNZ X14, {en}")
        A.mov(9, 13); A.i("ADDI X12, X12, #1"); A.b(lp)
        A.label(en)
        if div != 1:
            A.i("ORR X13, X12, X11"); A.i(f"CBZ X13, {sk}"); A.i("ADDI X11, X0, #1")
        A.i("ADDI X12, X12, #48"); A.i("STR X12, [X10, #0]"); A.i("ADDI X10, X10, #4")
        if div != 1: A.label(sk)
    A.i("STR X0, [X10, #0]"); A.ret()

# =====================================================================
# LEVEL 2: terminal, file system, commands
# =====================================================================
def level2():
    A.func("readline", "reads a line into LINEBUF (0-terminated words), echoing. clobbers X1-X14, uses X15")
    A.push(); A.i("ADDI X15, X0, #0")
    A.label("rl_l"); A.call("cursor_on"); A.call("getkey"); A.push(1); A.call("cursor_off"); A.pop(1)
    A.beqi(1, 13, "rl_enter"); A.beqi(1, 8, "rl_bs")
    A.blti(1, 32, "rl_l"); A.bgei(1, 127, "rl_l"); A.bgei(15, 78, "rl_l")
    A.i("LSL X2, X15, X24"); A.i("ADD X2, X2, X27"); A.i(f"STR X1, [X2, #{r(LINEBUF)}]"); A.i("ADDI X15, X15, #1")
    A.call("scr_putc"); A.b("rl_l")
    A.label("rl_bs"); A.i("CBZ X15, rl_l"); A.i("SUBI X15, X15, #1"); A.i("ADDI X1, X0, #8"); A.call("scr_putc"); A.b("rl_l")
    A.label("rl_enter")
    A.i("LSL X2, X15, X24"); A.i("ADD X2, X2, X27"); A.i(f"STR X0, [X2, #{r(LINEBUF)}]")
    A.i("ADDI X1, X0, #10"); A.call("scr_putc"); A.pop(); A.ret()

    A.func("parse_line", "split LINEBUF in place: CMDP=command, ARG1P=first arg, ARG2P=rest of line. uses X15")
    A.i(f"ADDI X15, X27, #{r(LINEBUF)}")
    A.label("pl_s1"); A.i("LDR X1, [X15, #0]"); A.bnei(1, 32, "pl_c1"); A.i("ADDI X15, X15, #4"); A.b("pl_s1")
    A.label("pl_c1"); A.stv(15, "CMDP")
    A.label("pl_t1"); A.i("LDR X1, [X15, #0]"); A.i("CBZ X1, pl_e1"); A.beqi(1, 32, "pl_p1"); A.i("ADDI X15, X15, #4"); A.b("pl_t1")
    A.label("pl_p1"); A.i("STR X0, [X15, #0]"); A.i("ADDI X15, X15, #4")
    A.label("pl_s2"); A.i("LDR X1, [X15, #0]"); A.bnei(1, 32, "pl_a1"); A.i("ADDI X15, X15, #4"); A.b("pl_s2")
    A.label("pl_a1"); A.stv(15, "ARG1P")
    A.label("pl_t2"); A.i("LDR X1, [X15, #0]"); A.i("CBZ X1, pl_e2"); A.beqi(1, 32, "pl_p2"); A.i("ADDI X15, X15, #4"); A.b("pl_t2")
    A.label("pl_p2"); A.i("STR X0, [X15, #0]"); A.i("ADDI X15, X15, #4")
    A.label("pl_s3"); A.i("LDR X1, [X15, #0]"); A.bnei(1, 32, "pl_a2"); A.i("ADDI X15, X15, #4"); A.b("pl_s3")
    A.label("pl_a2"); A.stv(15, "ARG2P"); A.ret()
    A.label("pl_e1"); A.stv(15, "ARG1P"); A.stv(15, "ARG2P"); A.ret()
    A.label("pl_e2"); A.stv(15, "ARG2P"); A.ret()

    A.func("fs_find", "X1=name ptr -> X1=record ptr or 0. uses X15-X18, clobbers X1-X11")
    A.push(); A.mov(16, 1); A.i(f"ADDI X15, X27, #{r(FS)}"); A.i("ADDI X17, X0, #0")
    A.label("ff_l"); A.i("LDR X18, [X15, #0]"); A.i("CBZ X18, ff_n")
    A.i("ADDI X1, X15, #4"); A.mov(2, 16); A.call("strcmp"); A.i("CBZ X1, ff_hit")
    A.label("ff_n"); A.i(f"ADDI X15, X15, #{RECBYTES}"); A.i("ADDI X17, X17, #1"); A.bnei(17, NFILES, "ff_l")
    A.i("ADDI X1, X0, #0"); A.pop(); A.ret()
    A.label("ff_hit"); A.mov(1, 15); A.pop(); A.ret()

    A.func("fs_alloc", "-> X1=free record ptr or 0. uses X15,X17,X18")
    A.i(f"ADDI X15, X27, #{r(FS)}"); A.i("ADDI X17, X0, #0")
    A.label("fa_l"); A.i("LDR X18, [X15, #0]"); A.i("CBZ X18, fa_hit")
    A.i(f"ADDI X15, X15, #{RECBYTES}"); A.i("ADDI X17, X17, #1"); A.bnei(17, NFILES, "fa_l")
    A.i("ADDI X1, X0, #0"); A.ret()
    A.label("fa_hit"); A.mov(1, 15); A.ret()

    # ---- commands (use X19-X21 across calls)
    A.func("cmd_help", "")
    A.push(); A.say("S_HELP1"); A.say("S_HELP2"); A.pop(); A.ret()

    A.func("cmd_ls", "list files: NAME  SIZE")
    A.push(); A.i(f"ADDI X19, X27, #{r(FS)}"); A.i("ADDI X20, X0, #0"); A.i("ADDI X21, X0, #0")
    A.label("ls_l"); A.i("LDR X1, [X19, #0]"); A.i("CBZ X1, ls_n"); A.i("ADDI X21, X21, #1")
    A.i("ADDI X1, X19, #4"); A.call("puts")
    A.i("ADDI X1, X0, #32"); A.call("scr_putc"); A.i("ADDI X1, X0, #32"); A.call("scr_putc")
    A.i("LDR X1, [X19, #56]"); A.i(f"ADDI X2, X27, #{r(NUMBUF)}"); A.call("dec_to_buf")
    A.i(f"ADDI X1, X27, #{r(NUMBUF)}"); A.call("puts"); A.i("ADDI X1, X0, #10"); A.call("scr_putc")
    A.label("ls_n"); A.i(f"ADDI X19, X19, #{RECBYTES}"); A.i("ADDI X20, X20, #1"); A.bnei(20, NFILES, "ls_l")
    A.i("CBNZ X21, ls_d"); A.say("S_NONE"); A.label("ls_d"); A.pop(); A.ret()

    def need_arg(usage, done):
        A.ldv(19, "ARG1P"); A.i("LDR X1, [X19, #0]"); ok = A.new("ok"); A.i(f"CBNZ X1, {ok}")
        A.say(usage); A.b(done); A.label(ok)

    A.func("cmd_create", "create NAME")
    A.push(); need_arg("S_UCREATE", "cc_d")
    A.mov(1, 19); A.call("strlen"); A.bgei(1, 13, "cc_long")
    A.mov(1, 19); A.call("fs_find"); A.i("CBNZ X1, cc_ex")
    A.call("fs_alloc"); A.i("CBZ X1, cc_full")
    A.mov(20, 1); A.i("ADDI X2, X0, #1"); A.i("STR X2, [X20, #0]")
    A.i("ADDI X1, X20, #4"); A.mov(2, 19); A.call("strcpy")
    A.i("STR X0, [X20, #56]"); A.i("STR X0, [X20, #64]"); A.b("cc_d")
    A.label("cc_long"); A.say("S_LONG"); A.b("cc_d")
    A.label("cc_ex"); A.say("S_EXISTS"); A.b("cc_d")
    A.label("cc_full"); A.say("S_FULL"); A.label("cc_d"); A.pop(); A.ret()

    A.func("cmd_write", "write NAME TEXT  (overwrites, max 255 chars)")
    A.push(); need_arg("S_UWRITE", "cw_d")
    A.mov(1, 19); A.call("fs_find"); A.i("CBZ X1, cw_no"); A.mov(20, 1)
    A.i("ADDI X1, X20, #64"); A.ldv(2, "ARG2P"); A.i("ADDI X3, X0, #255"); A.call("strcpy_lim")
    A.i("STR X1, [X20, #56]"); A.b("cw_d")
    A.label("cw_no"); A.say("S_NOFILE"); A.label("cw_d"); A.pop(); A.ret()

    A.func("cmd_cat", "cat NAME")
    A.push(); need_arg("S_UCAT", "ct_d")
    A.mov(1, 19); A.call("fs_find"); A.i("CBZ X1, ct_no")
    A.i("ADDI X1, X1, #64"); A.call("puts"); A.i("ADDI X1, X0, #10"); A.call("scr_putc"); A.b("ct_d")
    A.label("ct_no"); A.say("S_NOFILE"); A.label("ct_d"); A.pop(); A.ret()

    A.func("cmd_rm", "rm NAME")
    A.push(); need_arg("S_URM", "rm_d")
    A.mov(1, 19); A.call("fs_find"); A.i("CBZ X1, rm_no"); A.i("STR X0, [X1, #0]"); A.b("rm_d")
    A.label("rm_no"); A.say("S_NOFILE"); A.label("rm_d"); A.pop(); A.ret()

    A.func("cmd_snake", "start the game, restore the terminal screen afterwards")
    A.push(); A.call("snake_game"); A.call("redraw_all"); A.pop(); A.ret()

# =====================================================================
# SNAKE  (text mode, cell = 2 chars wide, 40x30 cells; row 0 = status, border rows 1 and 28)
# =====================================================================
def snake():
    A.func("show_score", "draw current score (X20) on row 0")
    A.push(); A.mov(1, 20); A.i(f"ADDI X2, X27, #{r(NUMBUF)}"); A.call("dec_to_buf")
    A.i("ADDI X1, X0, #9"); A.i(f"ADDI X2, X27, #{r(NUMBUF)}"); A.i("ADDI X3, X0, #0"); A.call("gfx_puts"); A.pop(); A.ret()

    A.func("place_food", "pick a random empty cell inside the walls -> FOOD, draw it red. clobbers X1-X14")
    A.push(); A.i("ADDI X13, X0, #0")
    A.label("pf_try"); A.i("ADDI X13, X13, #1"); A.bgei(13, 3000, "pf_give")
    A.call("rng_next"); A.mov(9, 1)
    A.i("ANDI X10, X9, #63"); A.blti(10, 1, "pf_try"); A.bgei(10, 39, "pf_try")
    A.i("ADDI X2, X0, #8"); A.i("LSR X11, X9, X2"); A.i("ANDI X11, X11, #31"); A.blti(11, 2, "pf_try"); A.bgei(11, 28, "pf_try")
    A.i("ADDI X12, X0, #0"); A.mov(14, 11)
    A.label("pf_m"); A.i("CBZ X14, pf_md"); A.i("ADDI X12, X12, #80"); A.i("SUBI X14, X14, #1"); A.b("pf_m")
    A.label("pf_md"); A.i("ADD X12, X12, X10"); A.i("ADD X12, X12, X10")
    A.i("LSL X1, X12, X24"); A.i("ADD X1, X1, X27"); A.i(f"LDR X2, [X1, #{r(GRID)}]"); A.i("CBNZ X2, pf_try")
    A.stv(12, "FOOD"); A.mov(1, 12); A.li(2, 0x3DB); A.call("draw2"); A.b("pf_d")
    A.label("pf_give"); A.stv(0, "FOOD")
    A.label("pf_d"); A.pop(); A.ret()

    A.func("snake_game", "play one game; returns when the player quits or after GAME OVER + key")
    A.push()
    A.i("ADDI X4, X0, #32"); A.call("vga_fill")
    A.i(f"ADDI X5, X27, #{r(GRID)}"); A.i("ADDI X7, X0, #0")
    A.label("sn_gc"); A.i("STR X0, [X5, #0]"); A.i("ADDI X5, X5, #4"); A.i("ADDI X7, X7, #1"); A.bnei(7, 2400, "sn_gc")
    A.c("top and bottom walls")
    A.i("ADDI X8, X0, #80"); A.i("ADDI X7, X0, #0")
    A.label("sn_wt"); A.mov(1, 8); A.call("put_wall"); A.i("ADDI X1, X8, #2160"); A.call("put_wall")
    A.i("ADDI X8, X8, #2"); A.i("ADDI X7, X7, #1"); A.bnei(7, 40, "sn_wt")
    A.c("left and right walls")
    A.i("ADDI X8, X0, #80"); A.i("ADDI X7, X0, #0")
    A.label("sn_ws"); A.mov(1, 8); A.call("put_wall"); A.i("ADDI X1, X8, #78"); A.call("put_wall")
    A.i("ADDI X8, X8, #80"); A.i("ADDI X7, X7, #1"); A.bnei(7, 28, "sn_ws")
    A.i("ADDI X1, X0, #2"); A.i(f"ADDI X2, X27, #{r(SOFF['S_SCORE'])}"); A.i("ADDI X3, X0, #0"); A.call("gfx_puts")
    A.i("ADDI X1, X0, #70"); A.i(f"ADDI X2, X27, #{r(SOFF['S_QUIT'])}"); A.i("ADDI X3, X0, #0"); A.call("gfx_puts")
    A.c("initial snake: 3 cells on row 15 heading right")
    for k, idx in enumerate((1236, 1238, 1240)):
        A.li(1, idx); A.i(f"STR X1, [X27, #{r(BODY + 4*k)}]"); A.call("mark_cell")
        A.li(1, idx); A.li(2, 0x2DB if k == 2 else 0x1DB); A.call("draw2")
    A.li(15, 1240); A.i("ADDI X16, X0, #2"); A.i("ADDI X17, X0, #0")
    A.i("ADDI X18, X0, #1"); A.i("ADDI X19, X0, #1"); A.i("ADDI X20, X0, #0"); A.i("ADDI X21, X0, #8")
    A.i("LDR X1, [X26, #256]"); A.stv(1, "LASTF"); A.ldv(2, "RNG"); A.i("EOR X2, X2, X1"); A.i("ORI X2, X2, #1"); A.stv(2, "RNG")
    A.call("place_food"); A.call("show_score")

    A.label("sn_wait")
    A.call("pollkey"); A.i("CBZ X1, sn_frame")
    A.beqi(1, 113, "sn_quit"); A.beqi(1, 81, "sn_quit"); A.beqi(1, 27, "sn_quit")
    keymap = {0: (119, 87, 129), 1: (100, 68, 132), 2: (115, 83, 130), 3: (97, 65, 131)}
    for d, keys in keymap.items():
        for k in keys: A.beqi(1, k, f"sn_d{d}")
    A.b("sn_frame")
    for d in range(4):
        A.label(f"sn_d{d}"); A.i(f"ADDI X2, X0, #{d}"); A.i("EOR X3, X2, X18"); A.beqi(3, 2, "sn_frame"); A.mov(19, 2); A.b("sn_frame")
    A.label("sn_frame")
    A.i("LDR X1, [X26, #256]"); A.ldv(3, "LASTF"); A.i("SUB X4, X1, X3"); A.blt(4, 21, "sn_wait"); A.stv(1, "LASTF")
    A.c("one move")
    A.mov(18, 19)
    A.beqi(18, 0, "sn_mu"); A.beqi(18, 1, "sn_mr"); A.beqi(18, 2, "sn_md")
    A.i("ADDI X2, X0, #-2"); A.b("sn_go")
    A.label("sn_mu"); A.i("ADDI X2, X0, #-80"); A.b("sn_go")
    A.label("sn_mr"); A.i("ADDI X2, X0, #2"); A.b("sn_go")
    A.label("sn_md"); A.i("ADDI X2, X0, #80")
    A.label("sn_go")
    A.i("ADD X22, X15, X2"); A.ldv(3, "FOOD"); A.i("SUB X4, X22, X3"); A.i("CBZ X4, sn_coll")
    A.c("not eating: remove tail first")
    A.i("LSL X5, X17, X24"); A.i("ADD X5, X5, X27"); A.i(f"LDR X6, [X5, #{r(BODY)}]")
    A.i("LSL X7, X6, X24"); A.i("ADD X7, X7, X27"); A.i(f"STR X0, [X7, #{r(GRID)}]"); A.i(f"STR X0, [X7, #{r(GRID)+4}]")
    A.mov(1, 6); A.i("ADDI X2, X0, #32"); A.call("draw2")
    A.i("ADDI X17, X17, #1"); A.i("ANDI X17, X17, #1023")
    A.label("sn_coll")
    A.i("LSL X5, X22, X24"); A.i("ADD X5, X5, X27"); A.i(f"LDR X6, [X5, #{r(GRID)}]"); A.i("CBNZ X6, sn_over")
    A.mov(1, 15); A.li(2, 0x1DB); A.call("draw2")
    A.mov(15, 22); A.i("ADDI X16, X16, #1"); A.i("ANDI X16, X16, #1023")
    A.i("LSL X5, X16, X24"); A.i("ADD X5, X5, X27"); A.i(f"STR X15, [X5, #{r(BODY)}]")
    A.mov(1, 15); A.call("mark_cell"); A.mov(1, 15); A.li(2, 0x2DB); A.call("draw2")
    A.ldv(3, "FOOD"); A.i("SUB X4, X15, X3"); A.i("CBNZ X4, sn_wait")
    A.i("ADDI X20, X20, #1")
    A.i("ANDI X2, X20, #3"); A.i("CBNZ X2, sn_nosp"); A.blti(21, 4, "sn_nosp"); A.i("SUBI X21, X21, #1")
    A.label("sn_nosp"); A.call("place_food"); A.call("show_score"); A.b("sn_wait")

    A.label("sn_over")
    A.li(1, 1156); A.i(f"ADDI X2, X27, #{r(SOFF['S_OVER'])}"); A.li(3, 0x300); A.call("gfx_puts")
    A.li(1, 1232); A.i(f"ADDI X2, X27, #{r(SOFF['S_FINAL'])}"); A.i("ADDI X3, X0, #0"); A.call("gfx_puts")
    A.mov(1, 20); A.i(f"ADDI X2, X27, #{r(NUMBUF)}"); A.call("dec_to_buf")
    A.li(1, 1245); A.i(f"ADDI X2, X27, #{r(NUMBUF)}"); A.i("ADDI X3, X0, #0"); A.call("gfx_puts")
    A.li(1, 1312); A.i(f"ADDI X2, X27, #{r(SOFF['S_ANYKEY'])}"); A.li(3, 0x200); A.call("gfx_puts")
    A.i("LDR X21, [X26, #256]")
    A.label("sn_settle"); A.call("pollkey"); A.i("LDR X1, [X26, #256]"); A.i("SUB X1, X1, X21"); A.blti(1, 60, "sn_settle")
    A.call("getkey")
    A.label("sn_quit"); A.pop(); A.ret()

boot(); level0(); level1(); level2(); snake()
text = "\n".join(A.out) + "\n"
open(ARGS.out, "w").write(text)
ninstr = sum(1 for l in A.out if l.startswith("    ") and not l.strip().startswith(";"))
print(f"wrote {ARGS.out}: {ninstr} instructions = {ninstr*4} bytes of ROM  (strings in {ARGS.strings.upper()})")

if ARGS.strings == "ram":
    # RAM image, word 0 = RAM_BASE. Only the variable + string region is preloaded; everything after it is left to the RAM's own reset/zero state.
    words = [0] * (_o // 4)
    for n, t in STRINGS:
        for k, ch in enumerate(t + "\0"):
            words[(SOFF[n] // 4) + k] = ord(ch)
    with open(ARGS.mem, "w") as f:
        for w in words: f.write(f"{w:08x}\n")
    print(f"wrote {ARGS.mem}: {len(words)} words (RAM bytes 0x0 .. {_o:#x}); word i = RAM_BASE + 4*i")
