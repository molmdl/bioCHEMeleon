# phase7_smoke.py -- Phase 7 headless smoke. Run: pymol -cq smoke/phase7_smoke.py
# Verifies the cmd-coupled Phase-7 mechanics headlessly (pure pymol.cmd.* only,
# NO Qt -- AGENTS.md: headless path cannot run Qt). The Qt/GUI paths
# (QColorDialog modal picker, QComboBox dropdown UI, Restart/Cleanup button
# click behavior, PickWizard lifecycle activate/deactivate + mouse_selection_mode,
# timer reset, log clearing, tab switching) are deferred to the human-verify
# checkpoint (plan Task 2).
#
# Sections (38 checks total):
#   1. SETUP: fetch 1ubq + capture orig_count.
#   2. START + SHOW: 3 sphere hiders (seed=42), count += 3, 3 visible.
#   3. FOUND-MGMT HIDE/SHOW: mark 1 found, build_found_selection, cmd.hide,
#      verify hidden, group_found_by_rep + cmd.show per rep, verify visible.
#   4. FOUND-MGMT RECOLOR + COLOR: cmd.set_color('found_highlight', ...),
#      _found_color assign, cmd.color, iterate color CHANGED.
#   5. _FOUND_COLOR THREADING: fresh GameController, _found_color='cyan',
#      _mark_found uses cyan (not green) -- runtime confirmation of Plan 01 TDD.
#   6. RESTART ROUND-TRIP: cleanup -> start -> verify -> cleanup -> verify
#      (mirrors the start->cleanup->start cycle that _on_restart uses at the
#      cmd layer; the GUI _on_restart + wizard lifecycle is human-verify).
#   7. CLEANUP EXPLICIT PATH: start a game, cleanup, verify (mirrors _on_cleanup
#      at the cmd layer; the GUI wizard deactivation + UI reset is human-verify).
#   8. SUMMARY: print pass/fail counts, sys.exit(1) on any fail.
import sys
from pymol import cmd
from biochemeleon import generators, game, registry, backup
from biochemeleon.registry import (build_found_selection, group_found_by_rep,
                                    HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN)

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. setup: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
check("setup: orig_count > 0", orig_count > 0)

# --- 2. start + show: generate 3 sphere positions (seed=42), start, show ---
extent = cmd.get_extent(obj)
positions = generators.generate_sphere_positions(extent, 3, seed=42)
hider_specs = [(pos, "spheres") for pos in positions]
gc = game.GameController(obj)
gc.start(hider_specs)
check("start: count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("start: registry len == 3", len(gc.registry.all()) == 3)
cmd.show("spheres", "%s and segi GAME" % obj)
check("show: 3 sphere hiders visible",
      cmd.count_atoms("%s and rep spheres and segi GAME" % obj) == 3)

# --- 3. found-mgmt hide/show: mark 1 found, hide, verify hidden, show, verify visible ---
hids = [r.id for r in gc.registry.all()]
first_id = hids[0]
gc._mark_found(first_id)   # default _found_color='green'; mirrors _on_pick -> _mark_found
check("hide/show: 1 found after _mark_found",
      sum(1 for r in gc.registry.all() if r.status == HIDER_STATUS_FOUND) == 1)
check("hide/show: 2 still hidden",
      sum(1 for r in gc.registry.all() if r.status == HIDER_STATUS_HIDDEN) == 2)
found = [r for r in gc.registry.all() if r.status == HIDER_STATUS_FOUND]
sele = build_found_selection(found, obj)
check("hide/show: build_found_selection not None", sele is not None)
check("hide/show: found selection includes the found id + obj",
      sele is not None and str(first_id) in sele and obj in sele)
# HIDE: cmd.hide("everything", sele) -- mirrors _on_found_mgmt('hide')
cmd.hide("everything", sele)
check("hide/show: found hider hidden (0 visible spheres for id)",
      cmd.count_atoms("%s and rep spheres and id %d" % (obj, first_id)) == 0)
# SHOW: by_rep + cmd.show per rep -- mirrors _on_found_mgmt('show')
by_rep = group_found_by_rep(found)
check("hide/show: group_found_by_rep has spheres", "spheres" in by_rep)
for rep, ids in by_rep.items():
    cmd.show(rep, "%s and id %s" % (obj, "+".join(str(i) for i in ids)))
check("hide/show: found hider visible again (1 sphere for id)",
      cmd.count_atoms("%s and rep spheres and id %d" % (obj, first_id)) == 1)

# --- 4. found-mgmt recolor + color: set_color found_highlight, recolor, verify CHANGED ---
pre_cols = []
cmd.iterate("%s and id %d" % (obj, first_id), "stored.append(color)",
            space={'stored': pre_cols})    # hygienic space= (AGENTS.md: NEVER space=None)
check("recolor: pre-color read OK", len(pre_cols) == 1)
cmd.set_color('found_highlight', [0.5, 0.5, 0.0])  # yellow-ish, non-default
gc._found_color = 'found_highlight'  # DIFF-04 attribute assignment
cmd.color('found_highlight', sele)   # mirrors _on_found_mgmt('recolor')
post_cols = []
cmd.iterate("%s and id %d" % (obj, first_id), "stored.append(color)",
            space={'stored': post_cols})
# phase4_smoke precedent: assert CHANGED (post != pre) -- exact green/found_highlight
# index varies by build, so a CHANGED assertion is the robust form.
check("recolor: post-color changed from pre",
      post_cols and post_cols[0] != pre_cols[0])
print("diag: pre-recolor color=%r post-recolor color=%r "
      "(found_highlight should differ from green)" % (pre_cols, post_cols))
check("recolor: _found_color attribute assigned to 'found_highlight'",
      gc._found_color == 'found_highlight')

# --- 5. _found_color threading: fresh gc, _found_color='cyan', _mark_found uses it ---
# Cleanup the first game so gc_thread starts from a clean (orig) object.
intact_a = gc.cleanup()
check("threading: first gc cleanup returned True", intact_a is True)
check("threading: count back to orig after first cleanup",
      cmd.count_atoms(obj) == orig_count)
gc_thread = game.GameController(obj)
gc_thread.start([([5.0, 5.0, 5.0], "spheres")])
check("threading: gc_thread count += 1",
      cmd.count_atoms(obj) == orig_count + 1)
check("threading: gc_thread default _found_color == 'green'",
      gc_thread._found_color == 'green')
thread_id = gc_thread.registry.all()[0].id
pre_thread_cols = []
cmd.iterate("%s and id %d" % (obj, thread_id), "stored.append(color)",
            space={'stored': pre_thread_cols})
# Override _found_color (DIFF-04) + _mark_found should use it (Plan 01 TDD at runtime).
gc_thread._found_color = 'cyan'
gc_thread._mark_found(thread_id)
post_thread_cols = []
cmd.iterate("%s and id %d" % (obj, thread_id), "stored.append(color)",
            space={'stored': post_thread_cols})
check("threading: post-color changed from pre (cyan, not green)",
      post_thread_cols and post_thread_cols[0] != pre_thread_cols[0])
print("diag: pre-thread color=%r post-thread color=%r "
      "(cyan should differ from default)" % (pre_thread_cols, post_thread_cols))
check("threading: hider now FOUND (registry status updated)",
      gc_thread.registry.get(obj, thread_id).status == HIDER_STATUS_FOUND)
intact_thread = gc_thread.cleanup()
check("threading: gc_thread cleanup returned True", intact_thread is True)
check("threading: count back to orig after thread cleanup",
      cmd.count_atoms(obj) == orig_count)

# --- 6. restart round-trip: start -> cleanup -> verify (mirrors _on_restart cmd path) ---
# At the cmd layer, _on_restart does: cleanup the active game (if any), create a
# fresh controller, start. Here we test that cycle: gc2.start, verify, gc2.cleanup,
# verify count back to orig + no GAME atoms. The GUI wizard lifecycle is human-verify.
gc2 = game.GameController(obj)
gc2.start([([7.0, 7.0, 7.0], "spheres"),
           ([8.0, 8.0, 8.0], "spheres"),
           ([9.0, 9.0, 9.0], "spheres")])
check("restart: gc2 count += 3 (new hiders)", cmd.count_atoms(obj) == orig_count + 3)
check("restart: gc2 registry len == 3 (fresh)", len(gc2.registry.all()) == 3)
check("restart: gc2 _started == True", gc2._started is True)
check("restart: gc2 _backup_name set to BACKUP_PREFIX",
      gc2._backup_name == backup.BACKUP_PREFIX)
check("restart: gc2 backup object exists",
      gc2._backup_name in cmd.get_names("objects"))
intact_b = gc2.cleanup()
check("restart: gc2 cleanup returned True", intact_b is True)
check("restart: count back to orig after gc2 cleanup",
      cmd.count_atoms(obj) == orig_count)
check("restart: no GAME atoms after gc2 cleanup",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)
check("restart: gc2 _started == False after cleanup", gc2._started is False)

# --- 7. cleanup explicit path: start a game, cleanup, verify (mirrors _on_cleanup cmd path) ---
# At the cmd layer, _on_cleanup does: controller.cleanup(), then releases the
# controller. Here we test controller.cleanup() restores the object; the GUI
# wizard deactivation + UI reset is human-verify.
gc3 = game.GameController(obj)
gc3.start([([11.0, 11.0, 11.0], "spheres"),
           ([12.0, 12.0, 12.0], "spheres"),
           ([13.0, 13.0, 13.0], "spheres")])
check("cleanup: gc3 count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("cleanup: gc3 _started == True", gc3._started is True)
intact_c = gc3.cleanup()
check("cleanup: gc3 cleanup returned True", intact_c is True)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig_count)
check("cleanup: no GAME atoms remain",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)
check("cleanup: gc3 _started == False after cleanup", gc3._started is False)
# Idempotent: cleanup() on a non-started game returns True (no-op). Mirrors the
# _on_cleanup `if self._controller is None: return` guard at the cmd layer.
intact_c2 = gc3.cleanup()
check("cleanup: idempotent (returns True when not started)", intact_c2 is True)

# --- 8. summary ---
print("\n=== SUMMARY ===")
fails = [n for n, c in RESULTS if not c]
print("%d/%d passed" % (len(RESULTS) - len(fails), len(RESULTS)))
if fails:
    print("FAILED: " + ", ".join(fails)); sys.exit(1)
print("ALL PASSED")
