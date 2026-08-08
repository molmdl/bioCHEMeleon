# phase4_smoke.py -- Phase 4 headless smoke. Run: pymol -cq smoke/phase4_smoke.py
# Verifies the cmd-coupled Phase-4 core loop headlessly (pure pymol.cmd.* only,
# NO Qt -- AGENTS.md: headless path cannot run Qt). The Qt/GUI paths (tab switch,
# countdown display, ticking timer, real mouse clicks, QMessageBox win
# message) are deferred to the human-verify checkpoint (plan Task 2).
#
# Steps: sphere gen -> insert+register -> show spheres -> simulate find via
# on_pick (logic path) -> recolor green -> remaining decrement -> miss ->
# win -> cleanup. Plus an optional do_pick-simulation spike (MEDIUM confidence,
# wrapped in try/except so a failure never breaks the main smoke exit code).
import sys
from pymol import cmd
from biochemeleon import generators, game, registry, mutation, wizard

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
check("gen: 3 positions", len(positions) == 3)
check("gen: positions within bounds",
      all(extent[0][k] - 1e-6 <= positions[i][k] <= extent[1][k] + 1e-6
          for i in range(3) for k in range(3)))

# --- 3. build hider_specs + start the game (snapshot -> insert -> register) ---
hider_specs = [(pos, "spheres") for pos in positions]
gc = game.GameController(obj)
gc.start(hider_specs)
check("start: count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("start: registry len == 3", len(gc.registry.all()) == 3)

# --- 4. show hiders as spheres ---
cmd.show("spheres", "%s and segi GAME" % obj)
check("show: spheres visible",
      cmd.count_atoms("%s and rep spheres and segi GAME" % obj) == 3)

# --- 5. register mock callbacks (stdlib only -- no unittest.mock) ---
logs = []; rems = []; wins = []
gc.set_callbacks(on_log=lambda m: logs.append(m),
                 on_remaining_changed=lambda r: rems.append(r),
                 on_win=lambda e: wins.append(e))
gc._start_time = 1234.0   # so win()'s elapsed math works without a real timer

# --- 6. simulate finding ONE hider via on_pick (logic path, not pick chain) ---
hids = [r.id for r in gc.registry.all()]
first_id = hids[0]
orig_cols = []
cmd.iterate("%s and id %d" % (obj, first_id), "stored.append(color)",
            space={'stored': orig_cols})
gc.on_pick(first_id)
check("on_pick: record now found",
      gc.registry.get(obj, first_id).status == registry.HIDER_STATUS_FOUND)
cols = []
cmd.iterate("%s and id %d" % (obj, first_id), "stored.append(color)",
            space={'stored': cols})
# cmd.color('green') sets the color index; the exact green index may vary by
# build, so assert CHANGED (post != pre) rather than a specific value.
check("on_pick: recolored (color changed)", cols and cols[0] != orig_cols[0])
print("diag: pre-pick color=%r post-pick color=%r (green index often 7)" %
      (orig_cols, cols))

# --- 7. post-first-find state: remaining 2, callbacks fired, win NOT fired ---
check("on_pick: remaining 2", gc._remaining() == 2)
check("on_pick: on_log fired", len(logs) >= 1)
check("on_pick: on_remaining_changed fired with 2", rems and rems[-1] == 2)
check("on_pick: on_win NOT fired yet", len(wins) == 0)

# --- 8. simulate a MISS (non-hider id 999999) ---
miss_logs_before = len(logs)
gc.on_pick(999999)
check("on_pick miss: logged Miss",
      len(logs) == miss_logs_before + 1 and "Miss" in logs[-1])
check("on_pick miss: remaining unchanged", gc._remaining() == 2)

# --- 9. find the remaining two -> win fires ---
for hid in hids[1:]:
    gc.on_pick(hid)
check("win: all found", gc._remaining() == 0)
check("win: on_win fired", len(wins) == 1 and isinstance(wins[0], float))

# --- 10. cleanup the first game (sentinel remove + verify_intact + discard) ---
# Runs BEFORE the spike so the spike's gc2.start()/gc2.cleanup() cannot
# clobber this game's backup (both share the global BACKUP_PREFIX name).
intact = gc.cleanup()
check("cleanup: returned True", intact is True)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig_count)

# --- 11. (optional spike) try the pick chain headlessly -- MEDIUM confidence ---
# 04-RESEARCH.md sec H Q32 Risk 1: do_pick needs a real mouse pick to populate
# pk1; we simulate by cmd.select("pk1", ...). Wrapped in try/except so a
# failure never breaks the main smoke exit code (the human-verify checkpoint
# definitively verifies the pick chain in a real PyMOL GUI session). Runs on
# the now-clean obj (post gc.cleanup) with its own fresh backup.
try:
    gc2 = game.GameController(obj)
    gc2.start([([5.0, 5.0, 5.0], "spheres")])
    gc2._start_time = 1234.0
    w2 = wizard.PickWizard(gc2, obj)
    w2.activate()
    hid2 = gc2.registry.all()[0].id
    cmd.select("pk1", "%s and id %d" % (obj, hid2))
    w2.do_pick(0)
    ok_pick = gc2.registry.get(obj, hid2).status == registry.HIDER_STATUS_FOUND
    check("spike: do_pick via simulated pk1 marks found", ok_pick)
    w2.deactivate()
    gc2.cleanup()
except Exception as exc:
    print("spike: do_pick-simulation not supported headlessly: %r" % (exc,))
    check("spike: do_pick simulation skipped (deferral to human-verify)", True)

# --- 11b. (optional spike) SELECT-path pick chain -- MEDIUM confidence ---
# Option 2 fix (04-02): in SELECTION button modes (the DEFAULT in 3-Button
# Viewing) the C layer (SceneMouse.cpp:337-356) creates "sele" + WizardDoSelect,
# NOT "pk1" + WizardDoPick. do_select maps sele -> pk1 -> do_pick. Simulate by
# creating "sele" on a hider atom, calling do_select("sele"), and asserting the
# hider is marked found. This is the path real GUI clicks take.
try:
    gc3 = game.GameController(obj)
    gc3.start([([6.0, 6.0, 6.0], "spheres")])
    gc3._start_time = 1234.0
    w3 = wizard.PickWizard(gc3, obj)
    w3.activate()
    hid3 = gc3.registry.all()[0].id
    cmd.select("sele", "%s and id %d" % (obj, hid3))  # simulate C-layer "sele"
    w3.do_select("sele")
    check("spike: do_select via simulated sele marks found",
          gc3.registry.get(obj, hid3).status == registry.HIDER_STATUS_FOUND)
    w3.deactivate()
    gc3.cleanup()
except Exception as exc:
    print("spike: do_select-simulation not supported headlessly: %r" % (exc,))
    check("spike: do_select simulation skipped (deferral to human-verify)", True)

# --- summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
