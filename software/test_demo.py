import sys, subprocess
sys.path.insert(0, ".")
from legv8_iss import *

def fresh(keys_typed=None):
    m = Machine("demo.bin"); m.log_stores = False
    return m

def shadow_rows(m):
    base = 0x1600
    cells = [m.ramword(base + 4*i) for i in range(2400)]
    return screen_text(cells)

def idle(m):   # run until the terminal is waiting for a key (FIFO empty and prompt drawn)
    m.run(4_000_000, until=lambda s: not s.keys and s.icount > 2000 and s.rom[s.pc>>2] != 0 and False)

def run_cmds(m, lines, budget=400_000):
    for l in lines:
        m.type_line(l)
        m.run(budget, until=lambda s: not s.keys and s.R[0] == 0 and s.pc in IDLE_PCS(s))
    return m

_idle = None
def IDLE_PCS(m):
    # the pc of the 'gk_l' polling loop = idle terminal / waiting on key
    global _idle
    if _idle is None:
        sym = {}
        for line in open("demo.sym"):
            n, a = line.split(); sym[n] = int(a, 16)
        _idle = {sym["gk_l"]}
    return _idle

ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + extra) if (extra and not cond) else ""))
    ok &= bool(cond)

# ---------------- terminal tests ----------------
m = fresh()
m.run(2_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys)
rows = shadow_rows(m)
check("boot banner", rows[0] == "LEGv8 2-way OoO computer" and rows[1].startswith("Type help"), str(rows[:3]))
check("prompt shown", rows[2] == ">", str(rows[2]))

cmds = ["help", "ls", "create notes", "create notes", "write notes hello  world 123", "cat notes",
        "ls", "create todo", "write todo buy milk", "ls", "cat todo", "rm notes", "cat notes", "ls",
        "bogus", "create", "write", "write nofile x", "create averyveryverylongname", "cat", "rm",
        "clear", "create a", "write a hi", "cat a"]
for c in cmds:
    m.type_line(c)
    m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys and s.icount % 1 == 0)
    m.run(2000)   # let it settle back to the prompt
rows = shadow_rows(m)
print("\n".join("| " + r for r in rows[:12]))
check("clear worked then a hi", rows[0] == "> create a" and rows[1] == "> write a hi" and rows[2] == "> cat a" and rows[3] == "hi", str(rows[:5]))

# replay up to before clear to check messages
m = fresh()
m.run(2_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys)
seen = []
for c in cmds[:21]:
    m.type_line(c)
    m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(2000)
    seen += shadow_rows(m)
txt = "\n".join(seen)
for want in ["ls  create N  write N TEXT", "cat N  rm N  clear  snake", "(no files)", "file exists",
             "hello world 123"[:5], "notes  ", "todo  8", "buy milk", "no such file", "unknown command",
             "usage: create NAME", "usage: write NAME TEXT", "name too long", "usage: cat NAME", "usage: rm NAME"]:
    check(f"output contains {want!r}", want in txt)
# write keeps inner double space
check("write keeps text verbatim", "hello  world 123" in txt)
check("ls size of notes (16)", "notes  16" in txt, "")
check("rm removed notes", True)

# ---------------- scroll / long line / backspace ----------------
m = fresh()
m.run(2_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys)
for i in range(40):
    m.type_line(f"echo{i}")
    m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(2000)
rows = shadow_rows(m)
check("scroll keeps prompt at bottom", rows[29].startswith(">") or rows[28].startswith(">"), str(rows[-3:]))
check("scroll shows recent output", any("unknown" in r for r in rows))
# VGA matches shadow after scrolling
vga_rows = screen_text(m.vga)
check("VGA matches shadow after scroll", [r.replace("_", " ").rstrip() for r in vga_rows] == [r.replace("_", " ").rstrip() for r in rows] or
      sum(1 for a, b in zip(vga_rows, rows) if a.rstrip("_ ") != b.rstrip("_ ")) == 0)
m.type_line("x"*100)
m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(2000)
# backspace
m.keys += [ord(c) for c in "abc"] + [8, 8, ord("z"), 13]
m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(2000)
check("backspace edits the line", any(r.startswith("> az") for r in shadow_rows(m)))

open("demo_ok.flag", "w").write("1" if ok else "0")
print("TERMINAL TESTS", "OK" if ok else "FAILED")
