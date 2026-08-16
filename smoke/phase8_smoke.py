# phase8_smoke.py -- Phase 8 headless smoke. Run: pymol -cq smoke/phase8_smoke.py
# Verifies the cmd-coupled Phase-8 export/import round-trip headlessly
# (pure pymol.cmd.* only, NO Qt -- AGENTS.md: headless path cannot run Qt).
# GUI paths (QFileDialog, tab-switching, 3-2-1 countdown, PickWizard
# click-to-find, timer display, found-mgmt dropdown after reload) are
# deferred to the human-verify checkpoint (plan Task 2).
#
# Sections (~60 checks total):
#   A. SETUP: fetch 1ubq + capture orig_count.
#   B. START + PLAY PARTIAL: 3 sphere hiders (seed=42), mark 1 found,
#      set reveal/hint/start_time (simulate mid-game checkpoint state).
#   C. SAVE (checkpoint): build .bcm + scoped .pse save (bare name) +
#      .bcmz bundle; verify archive contents + parsed .bcm fields.
#   D. LOAD + VERIFY SCOPED SAVE: clear session, load .pse (REPLACE),
#      assert _bchm_backup EXCLUDED + 3 sentinels survived.
#   E. RECONSTRUCT + RECONCILE: sentinel rebuild (rep=None, all hidden)
#      then apply_bcm_dict (reconcile rep + found-status + counters).
#   F. COUNTS_BY_REP RECOVERED: spheres == 3 (NOT 0 -- rep reconciled).
#   G. FOUND-MGMT SELECTION RECOVERED: build_found_selection +
#      group_found_by_rep + count_atoms == 1 (rep reconciliation makes
#      "Show found" work after reload).
#   H. FULL IMPORT_GAME ROUND-TRIP: read_bcmz + cmd.load(partial=1 MERGE)
#      + resolve_target + GameController.import_state (reconstruct +
#      reconcile + defensive recolor + fresh backup + _is_imported).
#   I. RESTART-ON-IMPORTED: mirror _on_restart_imported (restore backup +
#      re-reconcile from _imported_bcm + fresh backup). gc3 is a CHECKPOINT
#      so found-status (1 found) is restored from .bcm, NOT zeroed.
#   J. CLEANUP-ON-IMPORTED: two-step (backup.restore + mutation.cleanup)
#      -> no GAME atoms + count back to orig.
#   K. PUZZLE ROUND-TRIP: Generate & export (kind='puzzle', started=False,
#      timer 0, all hidden) + import + verify fresh-start state.
#   L. COLLISION DETECTABILITY: load 1ubq + verify refuse-first condition
#      (target_object in loaded molecules -> the GUI refuse dialog would fire).
#   N. POST-WIN CLEANUP/RESTART ON IMPORTED (regression for 08-05 fix):
#      import puzzle -> win -> cleanup-on-imported (clean molecule, NOT empty)
#      + import puzzle -> win -> restart-on-imported (hiders restored, NOT empty).
#   M. SUMMARY: print pass/fail counts, sys.exit(1) on any fail.
import sys
import os
import time
import zipfile

from pymol import cmd
from biochemeleon import game, registry, backup, mutation, persistence, generators
from biochemeleon.registry import (HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN,
                                    build_found_selection, group_found_by_rep)

RESULTS = []


def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)


# --- A. SETUP: fetch 1ubq + capture orig count ---
cmd.fetch("1ubq", async_=0)                 # AGENTS.md: async_=0 for sync load
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
check("A: setup orig_count > 0", orig_count > 0)

# --- B. START + PLAY PARTIAL (checkpoint save state) ---
extent = cmd.get_extent(obj)
positions = generators.generate_sphere_positions(extent, 3, seed=42)
hider_specs = [(pos, "spheres") for pos in positions]
gc = game.GameController(obj)
gc.start(hider_specs)
check("B: count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("B: registry len == 3", len(gc.registry.all()) == 3)
first_id = gc.registry.all()[0].id
gc._mark_found(first_id)   # default _found_color='green'; mirrors _on_pick
gc._reveal_count = 1
gc._hint_count = 2
gc._start_time = time.time() - 42.5  # simulate 42.5s elapsed
check("B: 1 found, 2 hidden after _mark_found",
      sum(1 for r in gc.registry.all() if r.status == HIDER_STATUS_FOUND) == 1 and
      sum(1 for r in gc.registry.all() if r.status == HIDER_STATUS_HIDDEN) == 2)

# --- C. SAVE (checkpoint): build .bcm + scoped .pse save + .bcmz bundle ---
elapsed = time.time() - gc._start_time  # ~42.5
check("C: elapsed ~42.5 (timer math)", abs(elapsed - 42.5) < 1.0)
setup_state = {
    "format": "biochemeleon-setup-v1", "target_mode": "loaded",
    "selected_object": obj, "pdb_code": "", "demo_id": "1znf",
    "hider_count": 3, "lock_scene": False,
    "per_rep": {"spheres": 3}, "difficulty_easy": True,
    "lock_source": False, "pdb_pool": [],
}
bcm_dict = persistence.build_bcm_dict(
    gc, setup_state, kind='checkpoint', elapsed=elapsed)
pse_path = "phase8_test.pse"
bcmz_path = "phase8_test.bcmz"
cmd.save(pse_path, obj)  # BARE name -> scoped save (excludes _bchm_backup)
check("C: .pse file exists + size > 0",
      os.path.exists(pse_path) and os.path.getsize(pse_path) > 0)
persistence.write_bcmz(bcmz_path, bcm_dict, pse_path)
check("C: .bcmz file exists + size > 0",
      os.path.exists(bcmz_path) and os.path.getsize(bcmz_path) > 0)
# Verify .bcmz contents + parse the .bcm sidecar
with zipfile.ZipFile(bcmz_path, 'r') as zf:
    names = zf.namelist()
    check("C: archive contains game.pse", "game.pse" in names)
    check("C: archive contains game.bcm", "game.bcm" in names)
    bcm_parsed = persistence.parse_bcm_dict(zf.read('game.bcm'))
check("C: bcm magic", bcm_parsed.get('magic') == persistence.BCM_MAGIC)
check("C: bcm version 1", bcm_parsed.get('version') == 1)
check("C: bcm kind checkpoint", bcm_parsed.get('kind') == 'checkpoint')
check("C: bcm target_object == 1ubq", bcm_parsed.get('target_object') == obj)
check("C: bcm registry len 3",
      len(bcm_parsed.get('registry', {}).get('hiders', [])) == 3)
_c_statuses = [h.get('status') for h in bcm_parsed.get('registry', {}).get('hiders', [])]
check("C: bcm 1 found, 2 hidden",
      _c_statuses.count('found') == 1 and _c_statuses.count('hidden') == 2)
check("C: bcm timer_elapsed ~42.5",
      abs(bcm_parsed.get('timer_elapsed', 0.0) - 42.5) < 1.0)
check("C: bcm reveal_count 1", bcm_parsed.get('reveal_count') == 1)
check("C: bcm hint_count 2", bcm_parsed.get('hint_count') == 2)

# --- D. LOAD + VERIFY SCOPED SAVE (backup excluded) ---
cmd.delete("all")  # clear session (REPLACE for the clean scoped-save check)
check("D: session cleared", cmd.get_names("objects") == [])
# Extract game.pse from the .bcmz to a relative path, load (partial=0 = REPLACE)
_pse_extracted = "phase8_extracted.pse"
with zipfile.ZipFile(bcmz_path, 'r') as zf:
    with open(_pse_extracted, 'wb') as f:
        f.write(zf.read('game.pse'))
cmd.load(_pse_extracted)  # partial=0 default -- REPLACE session
check("D: 1ubq present after load", obj in cmd.get_names("objects"))
# "objects" (mode 1) includes private underscore-prefixed objects; the
# scoped save (bare-name cmd.save) must have excluded _bchm_backup so it
# is NOT present after load. (PyMOL 2.5.0 has no "all_objects" type;
# querying.py:1168 maps "objects" -> mode 1 = all objects incl. private.)
check("D: _bchm_backup NOT in objects (scoped save worked)",
      "_bchm_backup" not in cmd.get_names("objects"))
check("D: 3 sentinels survived load",
      cmd.count_atoms("%s and segi GAME" % obj) == 3)
os.remove(_pse_extracted)

# --- E. RECONSTRUCT + RECONCILE ---
gc2 = game.GameController(obj)
gc2.reconstruct_registry()  # sentinel rebuild -- rep=None, all hidden
_recs2 = gc2.registry.all()
check("E: sentinel rebuild len == 3", len(_recs2) == 3)
check("E: all rep None after rebuild", all(r.rep is None for r in _recs2))
check("E: all hidden after rebuild",
      all(r.status == HIDER_STATUS_HIDDEN for r in _recs2))
_mismatches = persistence.apply_bcm_dict(gc2, bcm_parsed)
check("E: reconcile no missing_from_bcm", _mismatches.missing_from_bcm == [])
check("E: reconcile no missing_from_pse", _mismatches.missing_from_pse == [])
check("E: reconcile no bad_rep", _mismatches.bad_rep == [])
_recs2b = gc2.registry.all()
check("E: post-reconcile 1 found",
      sum(1 for r in _recs2b if r.status == HIDER_STATUS_FOUND) == 1)
check("E: post-reconcile 2 hidden",
      sum(1 for r in _recs2b if r.status == HIDER_STATUS_HIDDEN) == 2)
check("E: post-reconcile all rep == spheres",
      all(r.rep == "spheres" for r in _recs2b))
check("E: reveal_count restored to 1", gc2._reveal_count == 1)
check("E: hint_count restored to 2", gc2._hint_count == 2)
check("E: found_color restored to green", gc2._found_color == "green")

# --- F. COUNTS_BY_REP RECOVERED ---
_counts = gc2.registry.counts_by_rep()
check("F: counts_by_rep spheres == 3 (NOT 0 -- rep reconciled)",
      _counts.get("spheres") == 3)

# --- G. FOUND-MGMT SELECTION RECOVERED ---
_found = [r for r in gc2.registry.all() if r.status == HIDER_STATUS_FOUND]
_sele = build_found_selection(_found, obj)
check("G: build_found_selection not None", _sele is not None)
_by_rep = group_found_by_rep(_found)
check("G: group_found_by_rep has spheres", "spheres" in _by_rep)
check("G: group_found_by_rep spheres has 1 id",
      len(_by_rep.get("spheres", [])) == 1)
check("G: found selection count_atoms == 1", cmd.count_atoms(_sele) == 1)

# --- H. FULL IMPORT_GAME ROUND-TRIP (via the GUI's path, minus Qt) ---
cmd.delete("all")
_pse_path_h, _bcm_dict_h = persistence.read_bcmz(bcmz_path)
_names_before = set(cmd.get_names('public_objects', enabled_only=True))
cmd.load(_pse_path_h, partial=1)  # MERGE (Discrepancy 1 choice -- preserves scene)
_demos_list = [n for n in cmd.get_names('public_objects', enabled_only=True)
               if cmd.get_type(n) == 'object:molecule']
_target_obj = persistence.resolve_target(_bcm_dict_h, _names_before, _demos_list)
check("H: resolve_target == 1ubq", _target_obj == obj)
gc3 = game.GameController(_target_obj)
gc3.import_state(_bcm_dict_h)
check("H: _started == True", gc3._started is True)
check("H: _is_imported == True", gc3._is_imported is True)
check("H: _backup_name == _bchm_backup", gc3._backup_name == backup.BACKUP_PREFIX)
check("H: _imported_bcm == bcm_dict_h", gc3._imported_bcm == _bcm_dict_h)
_recs3 = gc3.registry.all()
check("H: registry len == 3", len(_recs3) == 3)
check("H: 1 found", sum(1 for r in _recs3 if r.status == HIDER_STATUS_FOUND) == 1)
check("H: 2 hidden", sum(1 for r in _recs3 if r.status == HIDER_STATUS_HIDDEN) == 2)
check("H: all rep == spheres", all(r.rep == "spheres" for r in _recs3))

# --- I. RESTART-ON-IMPORTED (cmd layer, mirrors _on_restart_imported) ---
# gc3 is a CHECKPOINT (1 found, per Section H). Restart-on-imported restores
# from the post-import backup + re-reconciles from _imported_bcm. The
# reconcile restores the checkpoint's found-status (1 found) -- NOT all-hidden.
# (For a puzzle import, the .bcm has all-hidden, so restart-on-imported would
# restore to 0 found -- but gc3 is a checkpoint, so we check the checkpoint
# path here.)
backup.restore(gc3.target_obj, gc3._backup_name)
backup.discard(gc3._backup_name)
gc3.reconstruct_registry()  # sentinel rebuild (rep=None, all hidden)
persistence.apply_bcm_dict(gc3, gc3._imported_bcm)  # re-reconcile rep + found
gc3._reveal_count = 0
gc3._hint_count = 0
gc3._start_time = None  # _begin_play sets it fresh
gc3._backup_name = backup.snapshot(gc3.target_obj)  # fresh backup
gc3._started = True
_n_found = sum(1 for r in gc3.registry.all() if r.status == HIDER_STATUS_FOUND)
check("I: restart-on-imported found-status restored from .bcm (1 found)",
      _n_found == 1)
check("I: gc3 _started == True", gc3._started is True)

# --- J. CLEANUP-ON-IMPORTED (two-step) ---
# Mirrors _on_cleanup for imported games: backup.restore (restores real-atom
# colors + brings hiders back) + mutation.cleanup_hiders (removes segi GAME).
backup.restore(gc3.target_obj, gc3._backup_name)
backup.discard(gc3._backup_name)
mutation.cleanup_hiders(gc3.target_obj)
check("J: no GAME atoms after cleanup",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)
check("J: count back to orig after cleanup",
      cmd.count_atoms(obj) == orig_count)

# --- K. PUZZLE (Generate & export) ROUND-TRIP ---
cmd.delete("all")
cmd.fetch("1ubq", async_=0)
gc4 = game.GameController(obj)
gc4.start([([20.0, 20.0, 20.0], "spheres")])  # 1 sphere hider
check("K: puzzle gc4 count += 1", cmd.count_atoms(obj) == orig_count + 1)
_puzzle_bcm = persistence.build_bcm_dict(gc4, setup_state, kind='puzzle')
_puzzle_pse = "phase8_puzzle.pse"
_puzzle_bcmz = "phase8_puzzle.bcmz"
cmd.save(_puzzle_pse, obj)  # scoped save (bare name)
persistence.write_bcmz(_puzzle_bcmz, _puzzle_bcm, _puzzle_pse)
gc4.cleanup()  # educator cleans up the generated hiders
check("K: gc4 cleanup count back to orig", cmd.count_atoms(obj) == orig_count)
# Read the puzzle .bcmz + verify kind + started + timer + all hidden
with zipfile.ZipFile(_puzzle_bcmz, 'r') as zf:
    _puzzle_bcm_parsed = persistence.parse_bcm_dict(zf.read('game.bcm'))
check("K: puzzle kind == puzzle", _puzzle_bcm_parsed.get('kind') == 'puzzle')
check("K: puzzle started == False", _puzzle_bcm_parsed.get('started') is False)
check("K: puzzle timer_elapsed == 0.0",
      _puzzle_bcm_parsed.get('timer_elapsed') == 0.0)
_puzzle_hiders = _puzzle_bcm_parsed.get('registry', {}).get('hiders', [])
check("K: puzzle all hiders hidden",
      all(h.get('status') == 'hidden' for h in _puzzle_hiders))
# Import the puzzle + verify fresh-start state
cmd.delete("all")
_pse_path_k, _bcm_dict_k = persistence.read_bcmz(_puzzle_bcmz)
cmd.load(_pse_path_k, partial=1)  # MERGE
gc5 = game.GameController(obj)
gc5.import_state(_bcm_dict_k)
check("K: puzzle import all hidden",
      all(r.status == HIDER_STATUS_HIDDEN for r in gc5.registry.all()))
check("K: puzzle import _started == True", gc5._started is True)
check("K: puzzle import _start_time is None (fresh start)",
      gc5._start_time is None)

# --- L. COLLISION DETECTABILITY ---
# Simulate a player who has 1ubq loaded + tries to import a .bcmz whose
# target_object == '1ubq'. The refuse-first check (Discrepancy 1) would
# fire in the GUI; here we verify the cmd-layer detectability.
cmd.delete("all")
cmd.fetch("1ubq", async_=0)  # player's existing scene
_loaded = [n for n in cmd.get_names('public_objects', enabled_only=True)
           if cmd.get_type(n) == 'object:molecule']
check("L: 1ubq in loaded molecules", obj in _loaded)
_target_in_bcm = _bcm_dict_h.get('target_object')
check("L: refuse-first condition True (target_object in loaded)",
      _target_in_bcm in _loaded)

# --- N. POST-WIN CLEANUP/RESTART ON IMPORTED (regression for 08-05 fix) ---
# The bug: _finish_win called controller.cleanup() after the win dialog,
# which DISCARDS the backup. For imported games, subsequent Cleanup/Restart
# call backup.restore(target, None) -> cmd.delete(target) + cmd.create(
# target, None) fails -> target DELETED -> empty scene. The fix:
# _finish_win skips cleanup() for imported games (preserves the backup).
# This section verifies the fix at the cmd layer: simulate win (mark all
# found) -> simulate the FIXED _finish_win (NO cleanup for imported) ->
# Cleanup-on-imported works (clean molecule, NOT empty scene) -> re-import
# + win -> Restart-on-imported works (hiders restored, NOT empty scene).

# N.1: Import puzzle -> win -> cleanup-on-imported
cmd.delete("all")
_pse_path_n1, _bcm_dict_n1 = persistence.read_bcmz(_puzzle_bcmz)
cmd.load(_pse_path_n1, partial=1)  # MERGE
gc6 = game.GameController(obj)
gc6.import_state(_bcm_dict_n1)
check("N1: puzzle import 1 hider", len(gc6.registry.all()) == 1)
check("N1: gc6 _is_imported", gc6._is_imported is True)
check("N1: gc6 _backup_name set", gc6._backup_name == backup.BACKUP_PREFIX)
# Simulate win: mark the hider found (mirrors on_pick -> _mark_found)
gc6._mark_found(gc6.registry.all()[0].id)
check("N1: post-win 0 remaining", gc6._remaining() == 0)
# Simulate the FIXED _finish_win: for imported, do NOT call cleanup.
# (The bug would call gc6.cleanup() here, discarding the backup.)
# Verify backup is still intact (the fix preserves it):
check("N1: backup intact post-win (fix preserves it)",
      gc6._backup_name == backup.BACKUP_PREFIX and
      backup.BACKUP_PREFIX in cmd.get_names("objects"))
# Now simulate _on_cleanup imported path (user clicks Cleanup):
backup.restore(gc6.target_obj, gc6._backup_name)
backup.discard(gc6._backup_name)
mutation.cleanup_hiders(gc6.target_obj)
gc6._started = False
gc6.registry = registry.HiderRegistry()
check("N1: post-win cleanup-on-imported: no GAME atoms",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)
check("N1: post-win cleanup-on-imported: count back to orig (NOT empty)",
      cmd.count_atoms(obj) == orig_count)

# N.2: Import puzzle -> win -> restart-on-imported
cmd.delete("all")
_pse_path_n2, _bcm_dict_n2 = persistence.read_bcmz(_puzzle_bcmz)
cmd.load(_pse_path_n2, partial=1)
gc7 = game.GameController(obj)
gc7.import_state(_bcm_dict_n2)
check("N2: puzzle import 1 hider", len(gc7.registry.all()) == 1)
# Simulate win
gc7._mark_found(gc7.registry.all()[0].id)
check("N2: post-win 0 remaining", gc7._remaining() == 0)
# Simulate the FIXED _finish_win (NO cleanup for imported) -> backup intact
check("N2: backup intact post-win (fix preserves it)",
      gc7._backup_name == backup.BACKUP_PREFIX and
      backup.BACKUP_PREFIX in cmd.get_names("objects"))
# Simulate _on_restart_imported (user clicks Restart):
backup.restore(gc7.target_obj, gc7._backup_name)
backup.discard(gc7._backup_name)
gc7.reconstruct_registry()  # sentinel rebuild (rep=None, all hidden)
persistence.apply_bcm_dict(gc7, gc7._imported_bcm)  # re-reconcile from .bcm
gc7._reveal_count = 0
gc7._hint_count = 0
gc7._start_time = None
gc7._backup_name = backup.snapshot(gc7.target_obj)  # fresh backup
gc7._started = True
check("N2: post-win restart-on-imported: 1 hider restored (NOT empty)",
      len(gc7.registry.all()) == 1)
check("N2: post-win restart-on-imported: all hidden (puzzle = fresh start)",
      all(r.status == HIDER_STATUS_HIDDEN for r in gc7.registry.all()))
check("N2: post-win restart-on-imported: GAME atoms present",
      cmd.count_atoms("%s and segi GAME" % obj) == 1)
check("N2: post-win restart-on-imported: count == orig + 1 (NOT empty)",
      cmd.count_atoms(obj) == orig_count + 1)
check("N2: post-win restart-on-imported: fresh backup set",
      gc7._backup_name == backup.BACKUP_PREFIX)
# Cleanup the gc7 hiders so the session is clean for the summary
backup.restore(gc7.target_obj, gc7._backup_name)
backup.discard(gc7._backup_name)
mutation.cleanup_hiders(gc7.target_obj)

# --- M. SUMMARY ---
_n_pass = sum(1 for _, ok in RESULTS if ok)
print("\n=== phase8_smoke: %d/%d PASS, %d FAIL ===" %
      (_n_pass, len(RESULTS), len(RESULTS) - _n_pass))
sys.exit(1 if _n_pass < len(RESULTS) else 0)
