---
phase: 10-polish-endgame-help
plan: 05
subsystem: ui
tags: [qt, qmessagebox, rich-text, endgame, win-screen, pymol]

# Dependency graph
requires:
  - phase: 04
    provides: _finish_win win dialog (QMessageBox) + on_win 100ms redraw-delay pattern + Bug B stay-on-top fix
  - phase: 06
    provides: GameController._hint_count + _reveal_count counters (reset per round in start()) + on_counts_changed callback signature
  - phase: 03
    provides: registry.HiderRegistry.all() (id-keyed, stable across add/remove) for the hider-count headline
provides:
  - Win-dialog headline carrying the hider count ("You found all N hiders in M:SS!")
  - Win-dialog setInformativeText rich-text stats block (Time / Hints used / Reveals used) always showing all three stats including 0/0
affects: [10-06, 10-09]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure Qt QMessageBox extension
  patterns: [QMessageBox.setInformativeText for rich-text secondary stats block below setText headline (Qt 5.x auto-detects HTML)]

key-files:
  created: []
  modified: [biochemeleon/gui_game.py]

key-decisions:
  - "Use setInformativeText (NOT setDetailedText) — setDetailedText is plain-text-only + hidden behind 'Show Details…' (wrong UX for a celebration); setInformativeText renders rich text inline below the headline."
  - "Use len(registry.all()) for the hider count (NOT sum(counts_by_rep().values())) — all() counts every registered hider including degraded rep=None records; counts_by_rep skips rep=None. The headline should count ALL hiders found (research Open Risk 5)."
  - "Always show all three stats including 0 hints / 0 reveals — a flex signal for the no-help win, and keeps dialog layout stable (no conditional-hide of a zero)."

patterns-established:
  - "Win-screen stats pattern: setText(headline + N + time) + setInformativeText(<b>Time:</b>…<br><b>Hints used:</b>…<br><b>Reveals used:</b>…) on the SAME QMessageBox, extended not duplicated."
  - "Reading controller public-by-convention attributes (_hint_count/_reveal_count) from the GUI layer — no new controller API needed for DIFF-02."

# Metrics
duration: ~3min
completed: 2026-08-18
---

# Phase 10 Plan 05: Win-Screen Stats (DIFF-02) Summary

**Surgical extension of `_finish_win` QMessageBox — headline now carries the hider count + a setInformativeText rich-text block shows Time / Hints used / Reveals used (always 0/0, never hidden)**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-08-17T18:58Z (worktree time)
- **Completed:** 2026-08-18T02:47Z+08:00 (commit timestamp)
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Win dialog headline now reads `"You found all %d hiders in %d:%02d!"` — the hider count comes from `len(self._controller.registry.all())` (counts ALL hiders including degraded `rep=None` records, per research Open Risk 5).
- A `setInformativeText` rich-text block renders below the headline: `<b>Time:</b> M:SS<br><b>Hints used:</b> N<br><b>Reveals used:</b> N` — Time/Hints/Reveals all visible immediately (NOT hidden behind "Show Details…").
- All three stats always shown including `0 hints / 0 reveals` (the flex case — a no-help win shows `Hints used: 0 / Reveals used: 0` as a skill signal; also keeps dialog layout stable — no surprise reflow).
- Existing `WindowStaysOnTopHint` + `self.window()` parent (Bug B fix) UNCHANGED.
- Existing `msg.exec_()` UNCHANGED — this plan adds NO new `.exec_()` (the existing one is extended, not duplicated).
- Existing cleanup gate at the tail of `_finish_win` (`if not getattr(self._controller, '_is_imported', False): self._controller.cleanup()`) UNCHANGED — Plan 10-06 moves it.
- Wizard deactivation block (lines 299-302) UNCHANGED.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend _finish_win win dialog with time/hints/reveals stats (DIFF-02)** - `bd73feb` (feat)

**Plan metadata:** (pending — final docs commit at end of execution)

## Files Created/Modified
- `biochemeleon/gui_game.py` — `_finish_win` win-dialog block extended (lines 305-323): 3 new locals (`n_hiders` / `hints` / `reveals`) + `setText` headline now includes `%d hiders` + new `setInformativeText` rich-text stats block. 12 insertions, 1 deletion (the old `setText` line replaced with the new headline + stats composition). No new imports (reads `self._controller._hint_count` / `_reveal_count` / `registry.all()` directly — already accessible via the duck-typed controller, same precedent as gui_game.py:158 + 227).

## Decisions Made
- **`setInformativeText` over `setDetailedText`:** `setDetailedText` is plain-text-only AND collapses behind a "Show Details…" button — wrong UX for a celebration screen where stats should be visible immediately. `setInformativeText` renders rich text (HTML auto-detected by Qt 5.x) in a secondary block below the headline — exactly the celebration UX. (Research endgame DIFF-02 recommendation; HIGH confidence.)
- **`len(registry.all())` over `sum(counts_by_rep().values())` for the hider count:** `all()` counts every registered hider including degraded `rep=None` records (e.g. an imported game with a corrupt/missing `.bcm` sidecar); `counts_by_rep` skips `rep=None`. The headline should count ALL hiders found — so `len(all())` is the simplest + correct source. (Research Open Risk 5.)
- **Always show 0/0 (never conditional-hide a zero):** A player who won without help should SEE `Hints used: 0 / Reveals used: 0` as a skill signal. This also keeps the dialog layout stable (no surprise reflow when a stat happens to be zero). The plan's must_have truth #3 + the research's explicit guidance.
- **No new controller API:** `_hint_count` + `_reveal_count` are already public-by-convention attributes on `GameController` (game.py:32-33, reset per round in `start()` at game.py:62-63). The GUI already reads `_reveal_count` at gui_game.py:227 (`start_countdown` sets the label). DIFF-02 just reads them again in `_finish_win` — no `game.py` change. (Research DIFF-02 rationale.)

## Deviations from Plan

None — plan executed exactly as written. The surgical edit was applied verbatim (the plan provided the exact replacement block); all verification gates passed on the first run (py_compile clean, exec_ = 1 unchanged, Pitfall-1 = 0, 120 tests pass no regression).

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. This is a Qt dialog edit; the only runtime verification is the human-verify checkpoint (playing to win in real PyMOL, confirming the 3 stats + the 0/0 flex case), which is DEFERRED to Plan 10-09's checkpoint (the Phase-10 endgame human-verify gate).

## Grep-Gate State (this plan's Wave-1 worktree)
- `grep -rnE "\.exec_\(\)" biochemeleon/` → exactly **1** hit (`gui_game.py:323 msg.exec_()` — the existing `_finish_win` QMessageBox, UNCHANGED; this plan adds NO new `.exec_()`). Plan 10-03's Help QDialog runs in a SEPARATE Wave-1 worktree (its own branch), so after the orchestrator merges both branches the gate will be 2 — this plan contributes no new hit.
- `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/` → **0** hits (Pitfall-1 gate clean).
- `python3.6 -m py_compile biochemeleon/*.py` → clean.
- `python3.6 -m unittest tests.test_setup_state -v` → 120 tests, all pass (no regression).
- `_finish_win` now contains `setInformativeText` and references `_hint_count` + `_reveal_count` + `registry.all()`.

## Next Phase Readiness
- Win stats are in place. The win dialog is a single-step modal: show stats → dismiss → (existing) cleanup gate.
- **Handoff to Plan 10-06:** Plan 10-06 adds the debrief dialog (DIFF-03) and MOVES the cleanup gate from `_finish_win` to `_finish_debrief` (so the hiders stay visible for the debrief highlight, then cleanup runs after the debrief is dismissed). This plan's `_finish_win` ends with the cleanup gate at its tail (lines 336-337) — exactly the block 10-06 will move. This plan adds NO new `.exec_()`, so 10-06's second `QMessageBox` (the debrief) brings the exec_ gate from 1 → 2 (both child QMessageBox — allowed by AGENTS.md).
- **Handoff to Plan 10-09:** Human-verify (play to win, confirm 3 stats + 0/0 flex case) is deferred to 10-09's checkpoint. The win-dialog text composition here is the canonical reference for that checkpoint.

---
*Phase: 10-polish-endgame-help*
*Plan: 05*
*Completed: 2026-08-18*
