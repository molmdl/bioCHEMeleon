# Phase 10 Pre-Implementation Audit: Research Claims vs Current Code

**Audited:** 2026-08-18
**Auditor:** Plan 10-04 (read-only)
**Purpose:** Verify research claims before implementation plans 10-05..10-08, 10-10 build on them.
**Worktree:** `tmp/exec-10-04` (branch `exec/10-04`)

## Summary

| # | Claim | Verdict |
|---|-------|---------|
| 1 | game.py hint/reveal counters | PASS |
| 2 | gui_game.py _finish_win QMessageBox + exec_ gate = 1 | PASS |
| 3 | registry.counts_by_rep zero-fills GAME_REPS and skips rep=None | PASS |
| 4 | HiderRecord has endpoint_resvs field | PASS |
| 5 | game.py _mark_found is fragment-aware | PASS |
| 6 | wizard.py sets mouse_selection_mode=0, does NOT change button_mode | PASS |
| 7 | setup_state.py has format_remaining as the precedent | PASS |
| 8 | setup_state.py is PURE (no pymol, no Qt) | PASS |
| 9 | __init__.py PluginDialog is modeless (dialog.show(), never .exec_()); exec_ gate = 1 | PASS |
| 10 | PyMOL controls: plain wheel = slab (NOT zoom) | PASS |

**Total:** 10/10 PASS, 0 FAIL.

## Detail

### Claim 1: game.py hint/reveal counters
- **Source citation:** game.py:32-33 (init), game.py:62-63 (reset)
- **Claim:** `GameController.__init__` initializes `self._hint_count = 0` + `self._reveal_count = 0`; `start()` resets both.
- **Verified at:** biochemeleon/game.py:32-33 (init), biochemeleon/game.py:62-63 (reset in `start()`)
- **Verdict:** PASS
- **Notes:** Exact match. Line 32: `self._reveal_count = 0`; line 33: `self._hint_count = 0` (in `__init__`, under the comment "Phase 6 hint/reveal counters (DIFF-01; reset per round in start())"). Line 62: `self._reveal_count = 0  # reset per round (DIFF-01)`; line 63: `self._hint_count = 0  # reset per round (DIFF-01)` (in `start()`, after `self.registry = registry.HiderRegistry()  # fresh per round`). Both fields are public-by-convention attributes (no leading underscore privacy enforcement; the GUI already reads `_reveal_count` at gui_game.py:227). No downstream blocker.

### Claim 2: gui_game.py _finish_win QMessageBox + exec_ gate = 1
- **Source citation:** gui_game.py:307-312
- **Claim:** `_finish_win` constructs a `QMessageBox(self.window())`, calls `setText`, sets `WindowStaysOnTopHint`, and calls `msg.exec_()`. This is the SOLE `.exec_()` hit in the package today (the exec_ grep gate = 1).
- **Verified at:** biochemeleon/gui_game.py:307-312 (the `_finish_win` method); exec_ grep hit at biochemeleon/gui_game.py:312
- **Verdict:** PASS
- **Notes:** Exact match. Line 307: `msg = QtWidgets.QMessageBox(self.window())`; line 308: `msg.setIcon(QtWidgets.QMessageBox.Information)`; line 309: `msg.setWindowTitle("You win!")`; line 310: `msg.setText("You found all hiders in %d:%02d!" % (mins, secs))`; line 311: `msg.setWindowFlags(msg.windowFlags() | QtCore.Qt.WindowStaysOnTopHint)`; line 312: `msg.exec_()`. Ran `grep -rnE "\.exec_\(\)" biochemeleon/` → exactly 1 hit: `biochemeleon/gui_game.py:312:        msg.exec_()`. The exec_ grep gate baseline is confirmed at 1. Plan 10-03 (Help QDialog) will raise it to 2; Plan 10-06 (debrief QMessageBox) will raise it to 3 — all child dialogs, allowed per AGENTS.md. No downstream blocker.

### Claim 3: registry.counts_by_rep zero-fills GAME_REPS and skips rep=None
- **Source citation:** registry.py:250-270
- **Claim:** `counts_by_rep()` returns a dict with all 5 GAME_REPS keys (zero-filled), and SKIPS records with `rep is None` (never emits a None key).
- **Verified at:** biochemeleon/registry.py:265 (zero-fill), biochemeleon/registry.py:267-268 (rep=None skip)
- **Verdict:** PASS
- **Notes:** Exact match. Line 265: `out = {rep: 0 for rep in GAME_REPS}` (zero-fills all 5 reps: lines, sticks, spheres, cartoon, ribbon). Lines 266-269: the loop with `if r.rep is None: continue` (line 267-268) then `out[r.rep] = out.get(r.rep, 0) + 1` (line 269). The returned dict has only `GAME_REPS` keys, never a `None` key — confirmed by reading the method body (registry.py:250-270). This is the canonical per-rep count source the debrief (Plan 10-06) and win-stats (Plan 10-05) build on. No downstream blocker.

### Claim 4: HiderRecord has endpoint_resvs field
- **Source citation:** registry.py:86-93
- **Claim:** `HiderRecord` has an `endpoint_resvs` slot (None default or a 2-tuple of ints) used by the fragment-aware debrief show.
- **Verified at:** biochemeleon/registry.py:104-105 (`__slots__`), biochemeleon/registry.py:107-108 (`__init__` signature)
- **Verdict:** PASS
- **Notes:** Exact match. Lines 86-93 are the docstring describing `endpoint_resvs` ("``None`` (default) or a 2-tuple of ints ``(rv1, rv2)``..."). Line 104-105: `__slots__ = ('id', 'object', 'rep', 'status', 'pos', 'is_altconf', 'endpoint_resvs', 'alt_tag')` — `endpoint_resvs` IS in `__slots__`. Line 107-108: `def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None, is_altconf=False, endpoint_resvs=None, alt_tag=''):` — `endpoint_resvs` is accepted as a kwarg with `None` default. Line 123: `self.endpoint_resvs = endpoint_resvs` (stored as-is). The field is set by `game.py:82-83` (`extra = {'endpoint_resvs': mutation.cartoon_hider_resi_range(start_resi, end_resi)}`) for 4-tuple cartoon/ribbon hiders, and reconciled from `.bcm` by `reconcile_with_bcm` (registry.py:502-503). The debrief show (Plan 10-06) reads `rec.endpoint_resvs` to scope the fragment show range. No downstream blocker.

### Claim 5: game.py _mark_found is fragment-aware
- **Source citation:** game.py:204-213
- **Claim:** `_mark_found` colors cartoon/ribbon FRAGMENT hiders by `segi GAME and resi rv1+1-rv2-1` (the middle), and single-atom hiders by `id`. The debrief show (Plan 10-06) mirrors this fragment-aware pattern (full rv1-rv2 range for show, not just anchor id).
- **Verified at:** biochemeleon/game.py:206-210 (fragment branch), biochemeleon/game.py:211-213 (single-atom else branch)
- **Verdict:** PASS
- **Notes:** Exact match. Line 205: `self.registry.mark_found(self.target_obj, hider_id)`. Line 206: `if (rec is not None and rec.endpoint_resvs is not None):` — the fragment gate. Line 207: `rv1, rv2 = rec.endpoint_resvs`. Lines 208-210: `cmd.color(self._found_color, "%s and segi GAME and resi %d-%d" % (self.target_obj, rv1 + 1, rv2 - 1))` — colors the MIDDLE (rv1+1 to rv2-1, endpoints excluded). Line 211: `else:` — the single-atom branch. Lines 212-213: `cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))` — colors by anchor id. The debrief show (Plan 10-06 research at 10-RESEARCH-endgame.md:97-101) mirrors this with the FULL rv1-rv2 range (endpoints included) for `cmd.show`, which is the fragment-aware pattern the research recommends. No downstream blocker.

### Claim 6: wizard.py sets mouse_selection_mode=0, does NOT change button_mode
- **Source citation:** wizard.py:42-45
- **Claim:** `PickWizard.__init__` saves + sets `mouse_selection_mode=0` (single-atom pick) and does NOT change `button_mode` — so left-drag still rotates (basis for the controls text "left-click picks, left-drag rotates").
- **Verified at:** biochemeleon/wizard.py:43-44 (save + set mouse_selection_mode)
- **Verdict:** PASS
- **Notes:** Exact match. Line 42: `# Canonical pattern (measurement.py:96-97): save + set mouse mode`. Line 43: `self._saved_selection_mode = cmd.get_setting_int("mouse_selection_mode")` (saves prior mode). Line 44: `cmd.set("mouse_selection_mode", 0)   # 0 = atomic (single-atom pick)`. Line 45: `cmd.deselect()`. Ran `grep -nE "button_mode" biochemeleon/wizard.py` → 0 hits. The wizard does NOT change `button_mode` — the 3-Button Viewing preset stays active, so left-drag still rotates (the docstring at wizard.py:19-20 calls this out: "This preserves left-drag rotation (essential for spin-to-find)"). The controls help text (Plan 10-03) "left-click picks, left-drag rotates" is accurate for the play state. No downstream blocker.

### Claim 7: setup_state.py has format_remaining as the precedent
- **Source citation:** setup_state.py:418-447
- **Claim:** `format_remaining(total, counts_by_rep, easy_mode)` is a PURE formatter (stdlib only) that the new `format_debrief_text` mirrors in structure + test pattern.
- **Verified at:** biochemeleon/setup_state.py:418-447 (the `format_remaining` function)
- **Verdict:** PASS
- **Notes:** Exact match. Line 418: `def format_remaining(total, counts_by_rep, easy_mode):`. The function body (lines 441-447) operates only on its arguments: `if not easy_mode or not counts_by_rep: return "Remaining: %d" % total` (line 441-442); builds `parts` from `GAME_REPS` (line 443-444); returns `"Remaining: %d  (%s)" % (total, ", ".join(parts))` (line 447). NO `from pymol import cmd`, NO `from pymol.Qt import` — pure stdlib (references `GAME_REPS` from the same module). This is the precedent the new `format_debrief_text` (Plan 10-01) mirrors: a pure formatter taking a counts dict + returning an HTML/string, unit-tested in WSL. No downstream blocker.

### Claim 8: setup_state.py is PURE (no pymol, no Qt)
- **Source citation:** (implicit — the purity claim)
- **Claim:** `setup_state.py` has NO `from pymol import cmd` and NO `from pymol.Qt import` — the new debrief formatter (Plan 10-01) must preserve this purity.
- **Verified at:** biochemeleon/setup_state.py:14-15 (imports section); grep result (0 hits)
- **Verdict:** PASS
- **Notes:** Exact match. Lines 14-15: `import random as _random` / `import copy as _copy` — the ONLY top-level imports (both stdlib). Ran `grep -nE "from pymol|import pymol" biochemeleon/setup_state.py` → 0 hits (no output). The module is pure (stdlib + its own constants); unit-testable in WSL without PyMOL installed (the module docstring at lines 1-12 confirms: "It has NO Qt and NO pymol.cmd dependencies so it can be unit-tested in WSL without PyMOL installed."). Plan 10-01's `format_debrief_text` must preserve this purity (add to `setup_state.py`, not a cmd-coupled module). No downstream blocker.

### Claim 9: __init__.py PluginDialog is modeless (dialog.show(), never .exec_()); exec_ gate = 1
- **Source citation:** (implicit — the modeless-main rule)
- **Claim:** `run_plugin_gui` uses `dialog.show()` (NOT `.exec_()`). The main PluginDialog is MODELESS. The exec_ grep gate has exactly 1 hit today (the `_finish_win` QMessageBox from Claim 2). Plan 10-03 raises it to 2 (Help QDialog), Plan 10-06 raises it to 3 (debrief QMessageBox) — all child dialogs.
- **Verified at:** biochemeleon/__init__.py:30 (`dialog.show()`); exec_ grep result reused from Claim 2 (1 hit at gui_game.py:312)
- **Verdict:** PASS
- **Notes:** Exact match. Line 30: `dialog.show()` (in `run_plugin_gui`, after `if dialog is None: dialog = PluginDialog()` at line 28-29). Line 31: `dialog.raise_()`; line 32: `dialog.activateWindow()`. NO `.exec_()` on the main PluginDialog — confirmed by the exec_ grep (Claim 2) returning exactly 1 hit, which is on `gui_game.py:312` (the child QMessageBox in `_finish_win`), NOT on `__init__.py`. The main dialog stays modeless (AGENTS.md: "Main dialog is modeless: `dialog.show()`, NEVER `.exec_()`"). Plan 10-03 (Help QDialog) and Plan 10-06 (debrief QMessageBox) add child-dialog `.exec_()` calls — both allowed per AGENTS.md ("QFileDialog.exec_() / QMessageBox.exec_() on child dialogs ARE allowed"). The exec_ gate will rise to 2 then 3, all on child dialogs. No downstream blocker.

### Claim 10: PyMOL controls: plain wheel = slab (NOT zoom)
- **Source citation:** tmp/pymol-src/modules/pymol/controlling.py:320-348
- **Claim:** In the default `three_button_viewing` mode, the plain scroll wheel maps to `slab` (clipping slab, NOT zoom). Zoom = Right-drag (`movz`) or Ctrl+wheel. This is the critical counterintuitive claim the Help text (Plan 10-03) depends on.
- **Verified at:** /mnt/c/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/pymol-src/modules/pymol/controlling.py:336 (wheel=slab), controlling.py:323 (Right-drag=movz)
- **Verdict:** PASS
- **Notes:** Exact match. The `three_button_viewing` mode dict starts at line 320. Line 336: `('w','none','slab'),` — the plain wheel (`'w'` = wheel, `'none'` = no modifier) maps to `'slab'` (cButModeScaleSlab — clipping slab width, NOT zoom). This is the counterintuitive finding. Line 323: `('r','none','movz'),` — Right-drag maps to `'movz'` (cButModeTransZ — translate along Z = zoom). Line 338: `('w','ctrl','mvsz'),` — Ctrl+wheel maps to `'mvsz'` (cButModeMoveSlabAndZoom — move slab + zoom). Line 339: `('w','ctsh','movz'),` — Ctrl+Shift+wheel maps to `'movz'` (pure zoom). Line 321: `('l','none','rota'),` — Left-drag = rotate. Line 322: `('m','none','move'),` — Middle-drag = translate/pan. Line 343: `('single_left','none','+/-'),` — single left-click = selection toggle (routes through `do_select` → `do_pick` when PickWizard is active per wizard.py:69-84). Line 344: `('single_middle','none','cent'),` — single middle-click = center. Line 345: `('single_right','none', 'menu'),` — single right-click = menu. The Help text (Plan 10-03) controls reference is accurate: "plain wheel = slab (not zoom)", "Zoom: Right-drag (or Ctrl+wheel)", "Left-click picks, Left-drag rotates". The `tmp/pymol-src/` directory is gitignored (NOT in the worktree) but IS readable from the main-repo absolute path per AGENTS.md. No downstream blocker.

## Blockers (if any FAIL)

| Failed claim | Blocks plan(s) | Action needed |
|---|---|---|
| (none) | (none) | (none) |

## Conclusion

All 10 claims PASS — the research citations (`10-RESEARCH-endgame.md` + `10-RESEARCH-help.md`) are accurate against the current codebase. No stale claims, no drifted file:line references, no incorrect API assumptions.

- **Wave 1 parallel plans (10-01/02/03/05):** proceed unaffected. Note: 10-05 (win-stats) runs parallel with this audit; claims 1 + 2 (which 10-05 depends on) are PASS, so no concurrent-issue flag is needed.
- **Wave 2 (10-06 debrief):** proceeds unconditionally. Claims 3, 4, 5 (which 10-06 depends on) are all PASS — `counts_by_rep` zero-fills + skips None, `HiderRecord.endpoint_resvs` exists, and `_mark_found` is fragment-aware.
- **Plans 10-07 (tooltips), 10-08 (smoke), 10-10 (README):** proceed unaffected (claims 6, 7, 8, 9, 10 verify the foundations they build on — wizard mouse mode, format_remaining precedent, setup_state purity, modeless main dialog, PyMOL wheel=slab).

No source code was modified (read-only audit). `git status` shows a clean working tree; `python3.6 -m py_compile biochemeleon/*.py` passes; `grep -rnE "\.exec_\(\)" biochemeleon/` returns exactly 1 hit (gui_game.py:312); the Pitfall-1 grep gate returns 0 hits. The audit file is the only artifact added.
