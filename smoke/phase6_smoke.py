# phase6_smoke.py -- Phase 6 headless smoke. Run: pymol -cq smoke/phase6_smoke.py
# Verifies the cmd-coupled Phase-6 hint/reveal mechanics headlessly (pure
# pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt). The
# Qt/GUI paths (confirm dialogs, button enable/disable, hint orange visibility
# in the viewer, reveal counter label updates) are deferred to the human-verify
# checkpoint (plan Task 2).
#
# Steps: fetch 1ubq -> gen 3 sphere positions -> start game (count += 3) ->
# show spheres -> register mock callbacks (4th = on_counts_changed) ->
# HINT (neighbor coloring orange, NO GAME atoms, no mark_found, count fired) ->
# REVEAL-ONE (1 more found, green, count==1, remaining==2, win NOT fired) ->
# REVEAL-ALL (all found, count += hidden, remaining==0, win fired, all green) ->
# CLEANUP (intact True, count back to orig) -> COUNTER RESET (fresh GameController
# zeroes counters before + after start()).
import sys
from pymol import cmd
from biochemeleon import generators, game, registry

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. setup: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)

# --- 2. generate 3 sphere positions from the real bounding box ---
extent = cmd.get_extent(obj)
positions = generators.generate_sphere_positions(extent, 3, seed=42)
hider_specs = [(pos, "spheres") for pos in positions]

# --- 3. start the game (snapshot -> insert -> register) ---
gc = game.GameController(obj)
gc.start(hider_specs)
check("start: count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("start: registry len == 3", len(gc.registry.all()) == 3)

# --- 4. show hiders as spheres ---
cmd.show("spheres", "%s and segi GAME" % obj)
check("show: spheres visible",
      cmd.count_atoms("%s and rep spheres and segi GAME" % obj) == 3)

# --- 5. register mock callbacks (stdlib only -- no unittest.mock) ---
logs = []; rems = []; wins = []; counts = []
gc.set_callbacks(on_log=lambda m: logs.append(m),
                 on_remaining_changed=lambda r: rems.append(r),
                 on_win=lambda e: wins.append(e),
                 on_counts_changed=lambda h, r: counts.append((h, r)))
gc._start_time = 1234.0   # so win()'s elapsed math works without a real timer

# --- 6. HINT test: neighbor coloring orange, no GAME atoms, no mark_found ---
orange_pre_hint = cmd.count_atoms("%s and color orange" % obj)  # baseline (likely 0 for 1ubq)
gc.hint()
check("hint: _hint_count == 1", gc._hint_count == 1)
check("hint: on_counts_changed fired", len(counts) >= 1 and counts[-1] == (1, 0))
# Hint colors neighbor atoms orange (not the hider, not GAME atoms)
orange_count = cmd.count_atoms("%s and color orange" % obj)
check("hint: orange atoms exist (neighbors colored)", orange_count > 0)
# CRITICAL: NO GAME atoms colored by hint (around excludes the hider atom;
# not segi GAME excludes support atoms + other hiders)
orange_game = cmd.count_atoms("%s and color orange and segi GAME" % obj)
check("hint: NO GAME atoms colored orange", orange_game == 0)
# All hiders still hidden (hint does NOT mark_found)
all_hidden = all(r.status == registry.HIDER_STATUS_HIDDEN
                 for r in gc.registry.all())
check("hint: all hiders still hidden (no mark_found)", all_hidden)
check("hint: log message fired", len(logs) >= 1)

# --- 7. REVEAL-ONE test: 1 more found, green, count==1, remaining==2 ---
before_found = sum(1 for r in gc.registry.all()
                   if r.status == registry.HIDER_STATUS_FOUND)
gc.reveal_one()
after_found = sum(1 for r in gc.registry.all()
                  if r.status == registry.HIDER_STATUS_FOUND)
check("reveal_one: exactly 1 more found", after_found == before_found + 1)
check("reveal_one: _reveal_count == 1", gc._reveal_count == 1)
check("reveal_one: on_counts_changed fired",
      len(counts) >= 2 and counts[-1] == (1, 1))
check("reveal_one: remaining == 2", gc._remaining() == 2)
check("reveal_one: win NOT fired yet", len(wins) == 0)
# The revealed hider is green (by id -- NOT segi GAME mass-color)
green_game = cmd.count_atoms("%s and color green and segi GAME" % obj)
check("reveal_one: revealed hider is green", green_game >= 1)

# --- 8. REVEAL-ALL test: all found, count += hidden, win fired, all green ---
hidden_before = gc._remaining()
gc.reveal_all()
check("reveal_all: all hiders found", gc._remaining() == 0)
check("reveal_all: _reveal_count == 1 + hidden_before",
      gc._reveal_count == 1 + hidden_before)
check("reveal_all: on_counts_changed fired",
      len(counts) >= 3 and counts[-1] == (1, gc._reveal_count))
check("reveal_all: on_remaining_changed(0) fired", rems and rems[-1] == 0)
check("reveal_all: win fired", len(wins) == 1 and isinstance(wins[0], float))
# All hiders green (by id -- verify no b=0 support atoms turned green)
green_game_all = cmd.count_atoms("%s and color green and segi GAME" % obj)
check("reveal_all: all hider atoms green",
      green_game_all >= len(gc.registry.all()))

# --- 9. CLEANUP the first game (restore from backup -> hiders gone + hint orange cleared) ---
intact = gc.cleanup()
check("cleanup: returned True", intact is True)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig_count)
# After cleanup, hint-colored real atoms should be restored to original
# (restore from backup brings back the pre-hint colors; the hint selection is
# object-restricted so it never colored the backup -- the backup is pristine)
orange_after = cmd.count_atoms("%s and color orange" % obj)
check("cleanup: hint orange cleared (restore from backup)",
      orange_after == orange_pre_hint)
# No GAME atoms remain (restore from backup removes all hiders + support atoms)
game_after = cmd.count_atoms("%s and segi GAME" % obj)
check("cleanup: no GAME atoms remain", game_after == 0)

# --- 10. COUNTER RESET test: fresh GameController zeroes counters ---
gc2 = game.GameController(obj)
check("reset: fresh _reveal_count == 0", gc2._reveal_count == 0)
check("reset: fresh _hint_count == 0", gc2._hint_count == 0)
gc2.start([([5.0, 5.0, 5.0], "spheres")])
check("reset: after start _reveal_count == 0", gc2._reveal_count == 0)
check("reset: after start _hint_count == 0", gc2._hint_count == 0)
gc2.cleanup()

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
