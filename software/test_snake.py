import sys; sys.path.insert(0, ".")
exec(open("test_demo.py").read().split("# ---------------- terminal tests")[0])

FOOD_OFF, GRID_OFF = 16, 0x9000
def grid(m): return [m.ramword(GRID_OFF + 4*i) for i in range(2400)]
def snake_len(m): return ((m.R[16] - m.R[17]) & 1023) + 1
def xy(idx): return ((idx % 80)//2, idx // 80)

def start_game(m):
    m.run(2_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys)
    m.type_line("snake")
    sym = {l.split()[0]: int(l.split()[1], 16) for l in open("demo.sym")}
    m.run(3_000_000, until=lambda s: s.pc == sym["sn_wait"])
    return sym

ok = True
def check(name, cond, extra=""):
    global ok
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if (extra and not cond) else ""))
    ok &= bool(cond)

# ---- 1. initial screen, moves right with no input, hits the wall, game over, key returns to terminal
m = Machine("demo.bin"); sym = start_game(m)
rows = screen_text(m.vga)
check("snake: score line + quit hint", rows[0].startswith("  SCORE: 0") and "Q=QUIT" in rows[0], rows[0])
check("snake: top/bottom border", set(rows[1].strip()) == {"+"} and set(rows[28].strip()) == {"+"} and len(rows[1].strip()) == 80, rows[1])
check("snake: left/right border", all(r[0] == "+" and r[1] == "+" and r[78] == "+" and r[79] == "+" for r in rows[1:29]))
check("snake: starts length 3 at row 15", snake_len(m) == 3 and rows[15][36:42] == "######", rows[15])
check("snake: food drawn inside field", m.ramword(FOOD_OFF) != 0 and 2*80 <= m.ramword(FOOD_OFF) < 28*80)

# reverse key is ignored: press 'a' (left) while heading right
m.keys += [ord("a")]
head0 = m.R[15]
m.run(400_000, until=lambda s: s.R[15] != head0)
check("snake: reverse key ignored (moved right)", m.R[15] == head0 + 2, (head0, m.R[15]))

# no input -> runs into right wall -> GAME OVER
over = lambda s: s.pc == sym["sn_settle"]
m.run(6_000_000, until=over)
rows = screen_text(m.vga)
check("snake: wall ends the game", m.pc == sym["sn_settle"] or any("GAME OVER" in r for r in rows), rows[14])
check("snake: GAME OVER + score + any key", any("GAME OVER" in r for r in rows) and any("FINAL SCORE:" in r for r in rows) and any("PRESS ANY KEY" in r for r in rows))
# a key pressed immediately is ignored (settle delay); then a later key returns to the terminal
m.keys += [ord("x")]
m.run(1000)
check("snake: early key ignored", any("GAME OVER" in r for r in screen_text(m.vga)))
m.run(400_000)
m.keys += [ord("x")]
m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys)
m.run(50_000)
vga_rows = screen_text(m.vga); sh = shadow_rows(m)
check("exit: terminal restored on VGA", [r.rstrip("_ ") for r in vga_rows] == [r.rstrip("_ ") for r in sh], vga_rows[:4])
check("exit: shows the snake command in history", sh[2].startswith("> snake"), sh[:4])

# ---- 2. bot chases food: score grows, grid stays consistent
m = Machine("demo.bin"); sym = start_game(m)
bad = []
stats = {"maxscore": 0, "frames": 0}
def bot(s):
    if s.pc not in range(sym["snake_game"], sym["sn_quit"]+8): return
    stats["frames"] += 1
    head, food = s.R[15], s.ramword(FOOD_OFF)
    stats["maxscore"] = max(stats["maxscore"], s.R[20])
    hx, hy = xy(head); fx, fy = xy(food)
    last = s.R[18]
    want = None
    if   fx > hx and last != 3: want = "d"
    elif fx < hx and last != 1: want = "a"
    elif fy > hy and last != 0: want = "s"
    elif fy < hy and last != 2: want = "w"
    if want: s.keys.append(ord(want))
    # consistency: GRID snake cells == 2*len, head cell marked, food cell empty
    g = grid(s); n = sum(1 for v in g if v == 1)
    if n != 2*snake_len(s) and s.pc in (sym["sn_wait"], sym["sn_frame"]) : bad.append(("grid", n, snake_len(s), s.icount))
    if g[head] != 1: bad.append(("head", head))
m.hook = bot
m.run(12_000_000, until=lambda s: s.pc == sym["sn_settle"])
check("bot: ate food at least 3 times", stats["maxscore"] >= 3, stats)
check("bot: grid/ring stay consistent", not bad, bad[:3])
rows = screen_text(m.vga)

# ---- 3. 'q' quits mid-game and restores terminal
m = Machine("demo.bin"); sym = start_game(m)
m.run(100_000)
m.keys += [ord("q")]
m.run(3_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(50_000)
vga_rows = screen_text(m.vga); sh = shadow_rows(m)
check("q: returns to terminal, screen restored", [r.rstrip("_ ") for r in vga_rows] == [r.rstrip("_ ") for r in sh] and sh[2].startswith("> snake"), vga_rows[:4])
# and the terminal keeps working + files survive a game
m.type_line("create f"); m.type_line("write f kept"); m.type_line("snake")
m.run(3_000_000, until=lambda s: s.pc == sym["sn_wait"])
m.keys += [ord("q")]
m.type_line("cat f")
m.run(6_000_000, until=lambda s: s.pc in IDLE_PCS(s) and not s.keys); m.run(60_000)
check("files survive snake", any(r.strip() == "kept" for r in shadow_rows(m)), shadow_rows(m)[:10])

# ---- 4. all stores stay in mapped regions and aligned (the ISS would raise otherwise); ROM size
print("ROM words:", len(m.rom))
open("snake_ok.flag", "w").write("1" if ok else "0")
print("SNAKE TESTS", "OK" if ok else "FAILED")
