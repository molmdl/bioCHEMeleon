---
phase: 10-polish-endgame-help
plan: 06
subsystem: ui
tags: [qt, qmessagebox, endgame, debrief, diff-03, fragment-aware, pymol, cmd-show, qtimer]

# Dependency graph
requires:
  - phase: 10 (Plan 10-01 — format_debrief_text pure helper in setup_state.py)
    provides: "format_debrief_text(counts_by_rep) pure HTML rich-text formatter + DEBRIEF_EXPLANATIONS dict (5 GAME_REPS keys, verbatim from research) — the text this plan's debrief QMessageBox writes onto setInformativeText."
  - phase: 10 (Plan 10-05 — _finish_win extended with DIFF-02 win-screen stats)
    provides: "The _finish_win method whose tail (inline cleanup gate at lines 336-337) this plan MOVES to _finish_debrief. The win-dialog QMessageBox (msg.exec_() at line 323) is the FIRST of the two sequential dialogs; this plan adds the SECOND."
  - phase: 03 (registry.HiderRegistry.all() + counts_by_rep() + HiderRecord.endpoint_resvs)
    provides: "registry.all() for the debrief show loop; counts_by_rep() (zero-filled GAME_REPS, skips rep=None) for the debrief text; HiderRecord.endpoint_resvs (2-tuple or None) for the fragment-aware cmd.show branch."
  - phase: 11 (endpoint_resvs on HiderRecord — forward-compat field)
    provides: "The endpoint_resvs field (rv1, rv2) that the fragment-aware show branch uses to scope segi GAME and resi rv1-rv2 for cartoon/ribbon backbone-segment hiders. None for sphere/line/stick -> by-id show."
provides:
  - "Post-game debrief flow (DIFF-03 / SC4): after the win dialog dismisses, all hiders are shown in the viewer in their own reps (fragment-aware), then a SECOND modal debrief QMessageBox appears with per-rep explanations from format_debrief_text."
  - "_show_all_hiders_for_debrief(self) — fragment-aware cmd.show loop over registry.all(): cartoon/ribbon 4-tuple hiders (endpoint_resvs set) shown by segi GAME and resi rv1-rv2, single-atom hiders shown by id; rep=None skipped (defensive)."
  - "_finish_debrief(self) — second modal QMessageBox (child dialog, .exec_() allowed) with format_debrief_text(registry.counts_by_rep()); the cleanup gate (_is_imported) MOVES here from _finish_win so hiders stay visible during the debrief."
  - "100ms redraw delay between win-dialog-dismiss and debrief-dialog-appear (QTimer.singleShot(100, _finish_debrief) + cmd.refresh()) — mirrors the existing _on_win pattern so cmd.show lands in the viewer before the modal blocks Qt."
  - "Moved cleanup gate: non-imported games cleanup after debrief dismiss (viewer returns to pre-game); imported games hiders stay (user clicks Cleanup explicitly — same _is_imported gate logic, just relocated from _finish_win to _finish_debrief)."
affects: [10-08 (headless smoke of the cmd-layer debrief show path), 10-09 (human-verify checkpoint: debrief appears after win, hiders shown, explanations match reps, cleanup timing for non-imported vs imported)]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure Qt QMessageBox + cmd.show extension
  patterns:
    - "Two sequential modal dialogs (win celebration -> debrief learning) wired via QTimer.singleShot(100, ...) — the 100ms redraw delay lets cmd.show land before the second modal blocks Qt (mirrors the _on_win -> _finish_win 100ms pattern)."
    - "Fragment-aware cmd.show for the debrief: cartoon/ribbon 4-tuple hiders (endpoint_resvs set) shown by 'segi GAME and resi rv1-rv2' (whole fragment re-renders), single-atom hiders shown by 'id N' — mirrors the _mark_found fragment-awareness pattern in game.py."
    - "Cleanup gate relocation: the _is_imported gate moves from _finish_win's tail to _finish_debrief's tail so hiders stay visible during the debrief; semantics unchanged (non-imported -> cleanup, imported -> hiders stay)."

key-files:
  created: []
  modified:
    - biochemeleon/gui_game.py  # +66/-11: import extended, _finish_win tail rewritten, +_show_all_hiders_for_debrief, +_finish_debrief

key-decisions:
  - "Two sequential dialogs (win -> debrief) rather than one combined — the research recommends the debrief as a follow-up beat (the spec's 'After winning, all hiders are highlighted with an explanation' frames DIFF-03 as a separate teachable moment). The 100ms QTimer.singleShot between them mirrors the existing _on_win -> _finish_win redraw-delay pattern."
  - "Fragment-aware cmd.show for the debrief: cartoon/ribbon 4-tuple hiders (endpoint_resvs set) are shown by 'segi GAME and resi rv1-rv2' (the FULL endpoint range, endpoints included — they're part of the blend), NOT just the anchor id (a single-atom show would leave support-residue + displaced-middle atoms hidden if the player used 'Hide found'). Single-atom hiders (sphere/line/stick, legacy 3-tuple cartoon) shown by 'id N'. Mirrors the _mark_found fragment-awareness pattern in game.py (which colors the middle rv1+1-rv2-1; here we SHOW the full rv1-rv2)."
  - "rep=None skip in the debrief show loop is defensive — counts_by_rep already skips rep=None (registry.py:267-268); the show loop skips it too so the hider stays in whatever rep the .pse preserved it in (a minor degraded experience for an imported game with a corrupt/missing .bcm sidecar, not a crash)."
  - "Cleanup gate MOVED (not duplicated) from _finish_win to _finish_debrief — the EXACT same _is_imported gate logic (`if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()`), just relocated. No behavior change to cleanup semantics; only the TIMING (after debrief dismiss instead of after win dismiss). Non-imported: cleanup restores from pre-game backup (removes hiders, discards backup) -> clean molecule. Imported: hiders stay (user clicks Cleanup explicitly — the imported two-step)."
  - "The debrief QMessageBox uses the SAME WindowStaysOnTopHint + self.window() parent as the win dialog (Bug B fix) so it appears above the PyMOL OpenGL window; the small messagebox leaves the highlighted hiders visible around it."
  - "Lazy `from pymol import cmd` inside _show_all_hiders_for_debrief (mirrors _on_found_mgmt at gui_game.py:155) — avoids a module-level cmd dependency in the Qt layer."
  - "1 Rule-3 deviation: reworded the _finish_debrief docstring from '.exec_() is ALLOWED' to 'exec_ is ALLOWED' to avoid a grep false-positive on the exec_ gate (the literal '.exec_()' token in a docstring trips the gate, exactly the AGENTS.md-warned pattern). Mirrors the 03-03/03-06/03-09/03-10/08-01/08-02 docstring-rewording precedent and the existing _on_pick_color docstring (gui_game.py:188 uses 'exec_' without dot+parens)."

patterns-established:
  - "Post-win debrief flow: _finish_win (win dialog) -> _show_all_hiders_for_debrief (cmd.show all hiders) -> cmd.refresh() + QTimer.singleShot(100, _finish_debrief) -> _finish_debrief (debrief dialog + cleanup gate). The two-dialog beat is the canonical endgame UX pattern for Phase 10."
  - "Fragment-aware cmd.show for endgame highlight: iterate registry.all(), branch on endpoint_resvs (fragment -> segi GAME and resi rv1-rv2, single-atom -> id N), skip rep=None. Reusable for any future 'show all hiders' need (e.g. a debug inspector)."

# Metrics
duration: 5min
completed: 2026-08-18
---

# Phase 10 Plan 06: Post-Game Debrief (DIFF-03 / SC4) Summary

**Two sequential post-win dialogs (win celebration -> debrief learning) with fragment-aware hider show + moved cleanup gate — the debrief QMessageBox consumes Plan 10-01's format_debrief_text; exec_ gate rises 2 -> 3 (all child dialogs)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-08-17T19:20:41Z (2026-08-18 03:20:41 +0800)
- **Completed:** 2026-08-17T19:25:50Z (2026-08-18 03:25:50 +0800)
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added the post-game debrief flow (DIFF-03 / SC4): after the win dialog dismisses, all hiders are shown in the viewer in their own reps (fragment-aware), then a SECOND modal debrief QMessageBox appears with per-rep explanations from `format_debrief_text` (Plan 10-01). Two sequential dialogs, not one combined — the research recommends the debrief as a follow-up teachable beat.
- `_show_all_hiders_for_debrief` is fragment-aware: cartoon/ribbon 4-tuple hiders (endpoint_resvs set) shown by `segi GAME and resi rv1-rv2` (the FULL endpoint range so the whole blend re-renders), single-atom hiders (sphere/line/stick, legacy 3-tuple cartoon) shown by `id N`. rep=None skipped (defensive — imported game with corrupt/missing .bcm rep). Mirrors the `_mark_found` fragment-awareness pattern in game.py.
- 100ms redraw delay between win-dialog-dismiss and debrief-dialog-appear (`cmd.refresh()` + `QTimer.singleShot(100, _finish_debrief)`) — mirrors the existing `_on_win` -> `_finish_win` 100ms pattern so the `cmd.show` calls land in the viewer before the modal debrief dialog blocks the Qt event loop.
- Cleanup gate MOVED from `_finish_win` tail to `_finish_debrief` tail — the EXACT same `_is_imported` gate logic, just relocated. Non-imported: cleanup runs after debrief dismiss (viewer returns to pre-game). Imported: hiders stay (user clicks Cleanup explicitly — the imported two-step). No behavior change to cleanup semantics; only the TIMING (deferred until after the debrief dismisses so hiders stay visible during the debrief).
- `_finish_debrief` shows a second modal QMessageBox (child dialog — `.exec_()` allowed by AGENTS.md; main PluginDialog stays modeless) with `format_debrief_text(registry.counts_by_rep())` on `setInformativeText`. Uses the SAME `WindowStaysOnTopHint` + `self.window()` parent as the win dialog (Bug B fix) so it appears above the OpenGL window.
- Import line extended: `from .setup_state import format_remaining, format_debrief_text` (Plan 10-01's pure helper is now consumed by the Qt layer).
- exec_ grep gate rises from 2 to 3 (the new `_finish_debrief` QMessageBox — a child dialog; the post-Wave-1-merge base already had 10-03's Help QDialog + 10-05's extended `_finish_win`). All 3 hits on child dialogs; NO hit on the main PluginDialog/SetupTab/GameTab.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add _show_all_hiders_for_debrief + _finish_debrief + move cleanup gate (DIFF-03)** - `41872b1` (feat)

**Plan metadata:** (pending — final docs commit at end of execution)

## Files Created/Modified
- `biochemeleon/gui_game.py` — 4 coordinated edits (+66/-11 lines):
  - **Edit 1 (line 15):** Import line extended to `from .setup_state import format_remaining, format_debrief_text`.
  - **Edit 2 (lines 322-335):** `_finish_win` tail rewritten — removed the inline cleanup gate (the 12-line comment block + `if not getattr... self._controller.cleanup()`); replaced with `_show_all_hiders_for_debrief()` + `from pymol import cmd` + `cmd.refresh()` + `QtCore.QTimer.singleShot(100, self._finish_debrief)`. The wizard-deactivation block + win-dialog block (with 10-05's DIFF-02 stats) UNCHANGED.
  - **Edit 3 (lines 337-360):** New method `_show_all_hiders_for_debrief(self)` — fragment-aware `cmd.show` loop over `registry.all()`: `endpoint_resvs` set -> `cmd.show(rec.rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))`; else -> `cmd.show(rec.rep, "%s and id %d" % (obj, rec.id))`; `rep=None` skipped. Lazy `from pymol import cmd` inside the method.
  - **Edit 4 (lines 362-392):** New method `_finish_debrief(self)` — builds `counts_by_rep()`, formats via `format_debrief_text(counts)`, shows a second modal QMessageBox (Information icon, "Debrief" title, "Debrief — where they were hiding" headline, `setInformativeText(text)`, `WindowStaysOnTopHint`, `self.window()` parent), `.exec_()`, then the moved cleanup gate (`if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()`).

## Decisions Made
- **Two sequential dialogs (win -> debrief) rather than one combined:** the research recommends the debrief as a follow-up beat. The spec's "After winning, all hiders are highlighted with an explanation" frames DIFF-03 as a separate teachable moment. The 100ms `QTimer.singleShot` between them mirrors the existing `_on_win` -> `_finish_win` redraw-delay pattern (the same Bug A fix — let PyMOL redraw before the modal blocks Qt).
- **Fragment-aware cmd.show for the debrief:** cartoon/ribbon 4-tuple hiders (endpoint_resvs set) are shown by `segi GAME and resi rv1-rv2` (the FULL endpoint range, endpoints included — they're part of the blend), NOT just the anchor id. A single-atom show would leave the support-residue + displaced-middle atoms hidden if the player used "Hide found". Single-atom hiders shown by `id N`. Mirrors the `_mark_found` fragment-awareness pattern in game.py (which colors the middle rv1+1-rv2-1; here we SHOW the full rv1-rv2 so the whole blend is visible).
- **rep=None skip is defensive:** `counts_by_rep` already skips rep=None (registry.py:267-268); the show loop skips it too so the hider stays in whatever rep the .pse preserved it in. A minor degraded experience for an imported game with a corrupt/missing .bcm sidecar, not a crash.
- **Cleanup gate MOVED (not duplicated):** the EXACT same `_is_imported` gate logic, just relocated from `_finish_win` tail to `_finish_debrief` tail. No behavior change to cleanup semantics; only the TIMING (after debrief dismiss instead of after win dismiss) so the hiders stay visible during the debrief. Non-imported: cleanup restores from pre-game backup (removes hiders, discards backup) -> clean molecule. Imported: hiders stay (user clicks Cleanup explicitly — the imported two-step; same 08-05 lesson: cleanup() on imported would discard the post-import backup, breaking subsequent Cleanup/Restart).
- **Same WindowStaysOnTopHint + self.window() parent as the win dialog (Bug B fix):** the debrief QMessageBox appears above the PyMOL OpenGL window; the small messagebox leaves the highlighted hiders visible around it.
- **Lazy `from pymol import cmd` inside _show_all_hiders_for_debrief:** mirrors `_on_found_mgmt` at gui_game.py:155 — avoids a module-level cmd dependency in the Qt layer.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded _finish_debrief docstring to avoid exec_ grep false-positive**
- **Found during:** Task 1 (post-edit gate verification)
- **Issue:** The plan's verbatim docstring for `_finish_debrief` contained the literal text `.exec_()` ("child dialog — .exec_() is ALLOWED by AGENTS.md"), which tripped the exec_ grep gate (`grep -rnE "\.exec_\(\)" biochemeleon/`). The gate expected EXACTLY 3 hits (10-03 Help QDialog + 10-05 _finish_win + this plan's _finish_debrief call); the docstring literal made it 4 textual hits. This is exactly the AGENTS.md-warned false-positive pattern ("literal tokens in comments/docstrings trip this grep too — we hit a false positive on a docstring that said 'from PyQt5 import'").
- **Fix:** Reworded the docstring from `.exec_() is ALLOWED` to `exec_ is ALLOWED` (dropped the leading dot + parens). The existing `_on_pick_color` docstring (gui_game.py:188) already uses `exec_` without dot+parens as the precedent. Mirrors the 03-03/03-06/03-09/03-10/08-01/08-02 docstring-rewording precedent.
- **Files modified:** biochemeleon/gui_game.py (docstring only, line 370)
- **Verification:** exec_ gate now returns EXACTLY 3 hits, all on child dialog `.exec_()` CALLS (gui_game.py:323 _finish_win, gui_game.py:382 _finish_debrief, __init__.py:948 help_dlg). No docstring/comment false-positives.
- **Committed in:** 41872b1 (part of the Task 1 feat commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The docstring reword is a no-behavior-change fix required to keep the exec_ grep gate clean (an AGENTS.md verification contract). No scope creep; the plan's intent (a child QMessageBox `.exec_()` call) is fully preserved.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. This is a Qt dialog + cmd.show edit; the only runtime verification is the human-verify checkpoint (playing to win in real PyMOL, confirming the two-dialog flow + fragment-aware hider show + per-rep explanations + cleanup timing for non-imported vs imported), which is DEFERRED to Plan 10-09's checkpoint (the Phase-10 endgame human-verify gate). The cmd-layer show path is smoke-tested in Plan 10-08.

## Grep-Gate State (this plan, on main post-Wave-1-merge)
- `grep -rnE "\.exec_\(\)" biochemeleon/` → exactly **3** hits:
  - `gui_game.py:323: msg.exec_()` — the `_finish_win` win dialog (child QMessageBox, from 10-05).
  - `gui_game.py:382: msg.exec_()` — the new `_finish_debrief` debrief dialog (child QMessageBox, this plan).
  - `__init__.py:948: help_dlg.exec_()` — 10-03's Help dialog (child QDialog, from Wave 1 merge).
  - NO hit on the main PluginDialog/SetupTab/GameTab. (The docstring false-positive was reworded — see Deviations.)
- `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/` → **0** hits (Pitfall-1 gate clean).
- `python3.6 -m py_compile biochemeleon/*.py` → clean.
- `python3.6 -m unittest tests.test_setup_state -v` → 125 tests, all pass (no regression).
- `_finish_win` tail (lines 322-335) no longer contains the inline cleanup gate — it ends with `QtCore.QTimer.singleShot(100, self._finish_debrief)`.
- `_show_all_hiders_for_debrief` (line 337) + `_finish_debrief` (line 362) exist on GameTab.
- The cleanup gate (`self._controller.cleanup()`) appears ONLY at line 392 (inside `_finish_debrief`); NOT in `_finish_win`.
- The import line (15) includes `format_debrief_text`.

## Next Phase Readiness
- **Debrief GUI is in place.** Plan 10-07 adds game-tab tooltips (parallel with 10-08's headless smoke of the cmd-layer show path). Plan 10-08 smoke-tests the `_show_all_hiders_for_debrief` cmd.show path headlessly (fragment-aware show for cartoon/ribbon + single-atom by-id + rep=None skip). Plan 10-09 is the human-verify checkpoint for the full debrief flow in real PyMOL (two sequential dialogs, hiders shown, explanations match reps, cleanup timing for non-imported vs imported).
- **No blockers.** All WSL gates green (py_compile + 125 tests + Pitfall-1=0 + exec_=3 all child dialogs).
- **Runtime/Qt verification deferred** to 10-09's checkpoint (the debrief QMessageBox + the 100ms redraw delay + the cleanup gate timing are Qt-coupled — not WSL-reachable). The cmd-layer show path is smoke-tested in 10-08.

---
*Phase: 10-polish-endgame-help*
*Plan: 06*
*Completed: 2026-08-18*
