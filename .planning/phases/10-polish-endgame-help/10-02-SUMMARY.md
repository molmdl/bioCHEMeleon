---
phase: 10-polish-endgame-help
plan: 02
subsystem: ui
tags: [qt, tooltips, ux, pymol, gui-setup]

# Dependency graph
requires:
  - phase: 02-setup-tab
    provides: gui_setup.py SetupTab with all widgets constructed (the untooltipped widget inventory)
provides:
  - setToolTip() calls on every previously-untooltipped Setup-tab widget in gui_setup.py (UX-01 Setup-tab half)
  - REP_EXPLANATIONS module-level dict in gui_setup.py (5 verified per-rep descriptions for tooltip + Help panel reuse)
affects: [10-03 (Help panel may reuse REP_EXPLANATIONS), 10-07 (Game-tab tooltips), 10-09 (human-verify checkpoint for hover rendering)]

# Tech tracking
tech-stack:
  added: []
  patterns: [module-level tooltip-text dict (REP_EXPLANATIONS) keeps rep text in one place for tooltip + Help reuse]

key-files:
  created: []
  modified:
    - biochemeleon/gui_setup.py

key-decisions:
  - "REP_EXPLANATIONS dict placed in gui_setup.py (not setup_state.py) to keep files_modified strictly gui_setup.py for parallel-safe Wave 1 — mirrors the DEBRIEF_EXPLANATIONS pattern Plan 10-01 adds to setup_state.py, but lives in the Qt-coupled module since it's UX-01 tooltip text"
  - "Per-rep checkbox tooltip is a CONCATENATION of generic text + rep explanation (format: 'Check to put hiders in the <rep> representation. <explanation> Leave unchecked to let the game decide (random).') built inside the for-rep loop using the loop variable — delivers UX-01 'what each representation means' on hover"
  - "pool_default_btn tooltip uses '33 bundled' (verified PDB_POOL length at runtime + existing _use_bundled_pool docstring), NOT the research draft's '34' — Rule 1 factual-accuracy fix per AGENTS.md 'Do NOT make up anything'"

patterns-established:
  - "Tooltip-text dict pattern: a module-level dict of short UX strings keyed by a domain constant (GAME_REPS), placed in the Qt-coupled module for parallel-safe file ownership, reusable by both tooltips and the Help panel"

# Metrics
duration: ~10min
completed: 2026-08-17
---

# Phase 10 Plan 02: Setup-tab Tooltips (UX-01) Summary

**setToolTip() added to all 22 previously-untooltipped Setup-tab widgets + REP_EXPLANATIONS dict for per-rep hover explanations**

## Performance

- **Duration:** ~10 min
- **Tasks:** 1/1 complete
- **Files modified:** 1 (biochemeleon/gui_setup.py)

## Accomplishments
- Added 22 new `setToolTip()` source calls (30 runtime tooltip calls counting the 5×cb + 5×spin per-rep loop) to every previously-untooltipped widget in `SetupTab._build_ui`, using the exact draft text from the 10-RESEARCH-help.md "Tooltips to ADD — gui_setup.py" table.
- Added `REP_EXPLANATIONS` module-level dict (5 verified per-rep descriptions) and wired it into the per-rep checkbox tooltip inside the `for rep in GAME_REPS` loop, so each per-rep checkbox carries BOTH the generic "check to put hiders in this rep" text AND the short rep explanation (UX-01 "what each representation means" on hover).
- All gates green: `py_compile` clean; exec_ gate stays 1 (unchanged — tooltips are not modal dialogs); Pitfall-1 gate stays 0; 120 unit tests pass (no regression).

## Task Commits

1. **Task 1: Add setToolTip() to every un-tooltipped Setup-tab widget** - `83e5bee` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `biochemeleon/gui_setup.py` - Added REP_EXPLANATIONS module-level dict (lines 30-44) + 22 new setToolTip() calls throughout SetupTab._build_ui; 3 existing tooltips (obj_refresh_btn, export_btn, cleanup_btn) left unchanged. Pure additive — no signal/slot/layout change.

## Decisions Made

- **REP_EXPLANATIONS in gui_setup.py (not setup_state.py):** The plan offered a choice (module-level dict in gui_setup.py vs. import a shared constant from setup_state.py). Chose the in-file dict to keep `files_modified` strictly `biochemeleon/gui_setup.py` for parallel-safe Wave 1 (Plans 10-01 touches setup_state.py+tests, 10-03 touches __init__.py — disjoint ownership). The dict is UX-01 tooltip text (Qt-coupled context), not domain data, so gui_setup.py is the natural home.

- **Per-rep tooltip as concatenation (not separate explanation widget):** The plan's format `"Check to put hiders in the %s representation. %s Leave unchecked to let the game decide (random)."` % (rep, rep_explanation) puts both the generic instruction and the rep explanation in ONE tooltip on the checkbox. A student hovering "cartoon" sees the explanation right there — the highest-value UX-01 text (per the research recommendation #4). The Help panel (Plan 10-03) will repeat the full explanations for comprehensive reference (redundancy is good for discoverability).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect PDB pool count in research draft tooltip text**

- **Found during:** Task 1 (adding pool_default_btn tooltip)
- **Issue:** The 10-RESEARCH-help.md "Tooltips to ADD" table specified the `pool_default_btn` tooltip as "Reset the pool to the **34** bundled, pre-verified PDB codes." However, the actual `PDB_POOL` constant in `setup_state.py` has **33** entries (verified at runtime: `python3.6 -c "...; print(len(m.PDB_POOL))"` → `33`). The existing `_use_bundled_pool` docstring (gui_setup.py line 430) already documents "33-entry bundled PDB_POOL."
- **Fix:** Used "Reset the pool to the **33** bundled, pre-verified PDB codes." (the verified count) instead of the research's incorrect "34." Per AGENTS.md: "Do NOT make up anything. ALL claims and citations (DOIs, PDB IDs, sources) MUST be verified against a source." Stating "34" in a user-facing tooltip would be a false claim.
- **Files modified:** biochemeleon/gui_setup.py (pool_default_btn tooltip)
- **Verification:** `python3.6 -c` confirms `len(PDB_POOL) == 33`; tooltip text now matches the verified count.
- **Committed in:** 83e5bee (Task 1 commit)

**Total deviations:** 1 auto-fixed (1 factual-accuracy bug in research draft text)
**Impact on plan:** Minimal — a single digit corrected. No scope creep.

## Issues Encountered
- None. The plan was a pure additive pass; all widget construction/signal/slot/layout left intact.

## Next Phase Readiness
- Setup-tab tooltips are in place; human-verify (hover rendering in real PyMOL) is deferred to the Plan 10-09 checkpoint (Qt tooltips can't be rendered headlessly from WSL — AGENTS.md).
- Plan 10-03 (Help panel) may reuse `REP_EXPLANATIONS` from gui_setup.py for the "Representations explained" section, or define its own copy in __init__.py (the dict is importable: `from .gui_setup import REP_EXPLANATIONS`).
- Plan 10-07 (Game-tab tooltips) is the parallel UX-01 pass for gui_game.py (disjoint file ownership).

---
*Phase: 10-polish-endgame-help*
*Plan: 02*
*Completed: 2026-08-17*
