---
phase: 10-polish-endgame-help
plan: 07
subsystem: ui
tags: [qt, tooltips, ux, pymol, gui-game]

# Dependency graph
requires:
  - phase: 10 (Plan 10-02 — Setup-tab tooltips pattern)
    provides: "The setToolTip() placement pattern (right after widget construction) + the precedent of verbatim text from 10-RESEARCH-help.md. This plan mirrors 10-02 for the Game tab."
  - phase: 10 (Plan 10-06 — most recent gui_game.py touch, post-Wave-1-merge base)
    provides: "The post-10-06 gui_game.py state (exec_ gate at 3: _finish_win + _finish_debrief + Help QDialog). This plan adds NO .exec_() — tooltips are not modal dialogs."
provides:
  - "setToolTip() calls on every previously-untooltipped Game-tab widget in gui_game.py (UX-01 Game-tab half — 8 new calls)"
  - "Together with Plan 10-02 (Setup-tab tooltips), this closes SC1's 'tooltips explain what each button does' half"
affects: [10-09 (human-verify checkpoint: hover each Game-tab widget in real PyMOL — Qt tooltips can't render headlessly from WSL)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Multi-line setToolTip() with implicit string concatenation for long tooltips (matches existing _import_btn/_save_btn pattern) — keeps lines readable while preserving exact verbatim text from research"

key-files:
  created: []
  modified:
    - biochemeleon/gui_game.py  # +22 lines: 8 new setToolTip() calls in GameTab.__init__

key-decisions:
  - "Used implicit Python string concatenation (adjacent string literals) for tooltips exceeding ~80 chars when indented — produces the identical string as the research draft (no paraphrasing) while keeping line lengths readable. Mirrors the existing _import_btn/_save_btn multi-line setToolTip pattern."
  - "Placed _found_mgmt_combo.setToolTip() AFTER the 4 addItem() calls (populating the combo is part of construction) and BEFORE btn_row.addWidget — matches the _color_btn pattern (setToolTip between construction and addWidget)."
  - "Placed _info_log.setToolTip() right after setReadOnly(True) per the plan's explicit instruction (the QTextEdit is a user-facing widget; the plan marked it 'optional but recommended' and we included it for full UX-01 coverage)."

patterns-established:
  - "Game-tab tooltip coverage complete: every user-facing widget in GameTab.__init__ now has a setToolTip() call (12 total = 8 new from this plan + 4 pre-existing). Together with Plan 10-02's 22 Setup-tab tooltips, all plugin widgets are now tooled for UX-01."

# Metrics
duration: ~5min
completed: 2026-08-18
---

# Phase 10 Plan 07: Game-tab Tooltips (UX-01) Summary

**setToolTip() added to all 8 previously-untooltipped Game-tab widgets — pure additive pass closing the UX-01 Game-tab half alongside Plan 10-02's Setup-tab tooltips**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-08-17T20:09:30Z (2026-08-18 04:09:30 +0800)
- **Completed:** 2026-08-17T20:13:56Z (2026-08-18 04:13:56 +0800)
- **Tasks:** 1/1 complete
- **Files modified:** 1 (biochemeleon/gui_game.py)

## Accomplishments
- Added 8 new `setToolTip()` calls to every previously-untooltipped widget in `GameTab.__init__`, using the exact draft text from the `10-RESEARCH-help.md` "Tooltips to ADD — gui_game.py" table (no paraphrasing).
- The 8 widgets that gained tooltips:
  1. `_info_log` (QTextEdit) — "Rolling log of game events: hits, misses, hints, reveals."
  2. `_timer_label` (QLabel) — "Elapsed time since the round began (counts up)."
  3. `_remaining_label` (QLabel) — "How many hiders are still hidden. Easy mode shows a per-representation breakdown."
  4. `_hint_btn` (QPushButton) — "Reveal a clue: temporarily highlights atoms near one hider to point you toward it (counts as a hint used)."
  5. `_reveal_one_btn` (QPushButton) — "Give up on one random hider — it gets revealed and marked found (counts as a reveal used)."
  6. `_reveal_all_btn` (QPushButton) — "Give up and reveal every remaining hider at once. This ends the game."
  7. `_reveal_label` (QLabel) — "How many hiders you've revealed (via Reveal one / Reveal all). Shown on the win screen too."
  8. `_found_mgmt_combo` (QComboBox) — "After finding hiders, choose how to display them: Hide, Show, or Recolor the found hiders."
- The 4 existing tooltips were left UNCHANGED: `_color_btn` (line 76), `_restart_btn` (line 79), `_import_btn` (lines 89-90), `_save_btn` (lines 92-93).
- Pure additive pass — no widget construction, signal, slot, or layout changed. No new import (tooltips are plain strings).
- All gates green: `py_compile` clean; exec_ gate stays 3 (unchanged from post-10-06 — tooltips are not modal dialogs); Pitfall-1 gate stays 0; 125 unit tests pass (no regression).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add setToolTip() to the 8 un-tooltipped Game-tab widgets** - `d7b6c78` (feat)

**Plan metadata:** (pending — final docs commit below)

## Files Created/Modified
- `biochemeleon/gui_game.py` — +22 lines (8 new `setToolTip()` calls in `GameTab.__init__`):
  - **Lines 26-27:** `_info_log.setToolTip(...)` after `setReadOnly(True)`.
  - **Lines 29-30:** `_timer_label.setToolTip(...)` after construction.
  - **Lines 32-34:** `_remaining_label.setToolTip(...)` after construction (implicit string concat for the long text).
  - **Lines 46-48:** `_hint_btn.setToolTip(...)` after construction.
  - **Lines 50-52:** `_reveal_one_btn.setToolTip(...)` after construction.
  - **Lines 54-56:** `_reveal_all_btn.setToolTip(...)` after construction.
  - **Lines 58-60:** `_reveal_label.setToolTip(...)` after construction.
  - **Lines 71-73:** `_found_mgmt_combo.setToolTip(...)` after the 4 `addItem()` calls, before `btn_row.addWidget`.

## Decisions Made

- **Implicit string concatenation for long tooltips:** Several research-draft tooltip strings exceed ~80 chars when indented to 12 spaces inside the `setToolTip(\n    "...")` multi-line pattern. Used Python's implicit string concatenation (adjacent string literals: `"foo " "bar"` → `"foo bar"`) to split long tooltips across two lines. This produces the IDENTICAL string as the research draft (verified: the concatenation joins with no separator, so "Easy mode shows a " + "per-representation breakdown." = "Easy mode shows a per-representation breakdown." — exact match). No paraphrasing. Mirrors the existing `_import_btn`/`_save_btn` multi-line `setToolTip` pattern.

- **`_found_mgmt_combo` tooltip placement:** Placed AFTER the 4 `addItem()` calls (which populate the combo — part of "construction") and BEFORE `btn_row.addWidget(self._found_mgmt_combo)`. This matches the existing `_color_btn` pattern: construct → `setToolTip` → `addWidget`.

- **`_info_log` tooltip included (optional but recommended):** The plan marked `_info_log` as "optional but recommended — the QTextEdit is a user-facing widget." Included it for full UX-01 coverage — a student hovering the log deserves to know what it records. Placed right after `setReadOnly(True)` per the plan's explicit instruction.

## Deviations from Plan

None — plan executed exactly as written. The tooltip text was taken verbatim from the research table; no paraphrasing, no factual corrections needed (unlike Plan 10-02 which corrected a "34"→"33" PDB pool count). All 8 widgets received tooltips; the 4 existing ones were left unchanged; no signal/slot/layout was modified.

## Issues Encountered
- None. The plan was a pure additive pass; all widget construction/signal/slot/layout left intact.

## Grep-Gate State (this plan, on exec/10-07 worktree branch)
- `grep -rnE "\.exec_\(\)" biochemeleon/` → exactly **3** hits (UNCHANGED from post-10-06 state):
  - `gui_game.py:345: msg.exec_()` — the `_finish_win` win dialog (child QMessageBox, from 10-05).
  - `gui_game.py:404: msg.exec_()` — the `_finish_debrief` debrief dialog (child QMessageBox, from 10-06).
  - `__init__.py:948: help_dlg.exec_()` — 10-03's Help dialog (child QDialog, from Wave 1).
  - NO hit on the main PluginDialog/SetupTab/GameTab. This plan adds NO new `.exec_()` — tooltips are not modal dialogs.
- `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/` → **0** hits (Pitfall-1 gate clean).
- `python3.6 -m py_compile biochemeleon/*.py` → clean.
- `python3.6 -m unittest tests.test_setup_state -v` → 125 tests, all pass (no regression).
- `grep -c "setToolTip" biochemeleon/gui_game.py` → **12** (8 new from this plan + 4 pre-existing unchanged).

## Next Phase Readiness
- **Game-tab tooltips are in place.** Together with Plan 10-02 (Setup-tab tooltips), all user-facing plugin widgets now have tooltips — UX-01's "tooltips explain what each button does" is code-complete.
- **Human-verify (hover rendering in real PyMOL) is DEFERRED to the Plan 10-09 checkpoint** — Qt tooltips can't be rendered headlessly from WSL (AGENTS.md: Qt needs a real display). Plan 10-09 is the Phase-10 human-verify gate for the full UX pass (Setup-tab tooltips + Game-tab tooltips + Help dialog + endgame debrief flow).
- **No blockers.** All WSL gates green (py_compile + 125 tests + Pitfall-1=0 + exec_=3 all child dialogs).
- Plan 10-08 (headless smoke of the cmd-layer debrief show path) runs in parallel with this plan on the disjoint `smoke/phase10_smoke.py` file — no file ownership conflict (this plan touches only `gui_game.py`).

---
*Phase: 10-polish-endgame-help*
*Plan: 07*
*Completed: 2026-08-18*
