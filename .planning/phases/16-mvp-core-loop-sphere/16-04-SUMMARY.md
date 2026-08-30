---
phase: 16-mvp-core-loop-sphere
plan: 04
subsystem: game-ui
tags: [tcl, tcl-8.5, vmd, tdd, tcltest, pure-layer, formatter, game-tab]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: pure-layer setup_state.tcl namespace + tcltest-under-headless-VMD harness (BCHM_TEST_RESULT marker)
  - phase: 14-setup-tab-bundled-demos
    provides: GAME_REPS namespace variable, _to_bool coercion helper, validate_state defensive dict patterns
  - phase: 16 (16-02, same phase, merged first)
    provides: registry found-state procs whose counts will feed format_remaining from Plan 16-09
provides:
  - "::biochemeleon::setup_state::format_remaining {total counts_by_rep easy_mode} — pure, exported remaining-hiders label formatter (port of v1 setup_state.py:418-447)"
  - "6 tcltest cases proving exact-string behavior: hard mode, easy-no-counts, single-rep two-space string, GAME_REPS-order-vs-dict-insertion-order, zero/unknown-key omission, easy-all-zero"
affects: [16-09 game_tab (update_remaining consumer), 16-05+ pick/wiring plans, GAME-03 requirement]

# Tech tracking
tech-stack:
  added: [] # none — stdlib tcl 8.5 only
  patterns:
    - "Pure formatter in the pure layer (setup_state.tcl), thin GUI view consumes it (v1 architecture parity)"
    - "GAME_REPS-order iteration over the constant, never over the input dict (unknown keys skipped defensively)"
    - "Non-dict counts treated as empty via the validate_state catch pattern; _to_bool reused for Python-truthiness easy_mode coercion"

key-files:
  created: []
  modified:
    - vmd/lib/setup_state.tcl (export list + appended format_remaining proc; no existing proc touched)
    - vmd/tests/test_setup_state.test (6 appended cases before the marker block; no existing case touched)

key-decisions:
  - "Iterate GAME_REPS (not the dict) so unknown rep keys can never leak into the label — defensive port of v1's dict.get(rep, 0) loop"
  - "Reuse module _to_bool for easy_mode falsiness (0/\"\"/false/False) instead of raw truthiness — matches validate_state bool coercion and v1 Python bool() semantics"
  - "Non-dict counts_by_rep -> total-only via catch {dict size} guard (validate_state precedent) rather than erroring"

patterns-established:
  - "format_remaining is the single source of the GAME-03 display string; Plan 16-09's update_remaining must call it, never re-implement it"

# Metrics
duration: 8 min
completed: 2026-08-30
---

# Phase 16 Plan 04: Pure Remaining-Count Formatter Summary

**Pure `format_remaining` ported verbatim from v1 setup_state.py:418-447 into setup_state.tcl — exact two-space/GAME_REPS-order label string proven by 6 new tcltest cases (47/47 green under headless VMD), ready for Plan 16-09's update_remaining.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-30T09:41:42Z
- **Completed:** 2026-08-30T09:50:06Z
- **Tasks:** 3/3 (RED → GREEN → gates)
- **Files modified:** 2

## Accomplishments
- `::biochemeleon::setup_state::format_remaining {total counts_by_rep easy_mode}` implemented pure (no viewer API, no GUI toolkit, no event-loop calls) and added to the namespace export list
- Exact-string contract proven: `"Remaining: N"` (hard / empty counts / all-zero) and `"Remaining: N  (Rep: n, ...)"` with EXACTLY TWO spaces before the paren, GAME_REPS order beating dict insertion order, >0 counts only, unknown keys skipped
- Full regression gate held: all 41 pre-existing setup_state cases stayed green throughout (RED run: Total=47 Failed=6, existing 41 passing; GREEN run: 47/47)

## TDD Cycle (RED → GREEN)

**RED** — 6 failing tests appended before the marker block (`9e2914e`):
- `format_remaining_hard_mode` (3, {}, 0) → `Remaining: 3`
- `format_remaining_easy_no_counts` (3, {}, 1) → `Remaining: 3`
- `format_remaining_easy_single_rep` (5, {VDW 5}, 1) → `Remaining: 5  (VDW: 5)`
- `format_remaining_easy_multi_rep_game_reps_order` (7, {VDW 4 Lines 3}, 1) → `Remaining: 7  (Lines: 3, VDW: 4)`
- `format_remaining_ignores_zero_and_unknown` (4, {VDW 0 Lines 4 Bogus 9}, 1) → `Remaining: 4  (Lines: 4)`
- `format_remaining_easy_all_zero_total_only` (2, {VDW 0 Lines 0}, 1) → `Remaining: 2`

Headless run: `BCHM_TEST_RESULT Total=47 Passed=41 Failed=6` — all 6 failures were exactly `invalid command name "::biochemeleon::setup_state::format_remaining"` (clean RED; existing 41 unaffected).

**GREEN** — proc implemented + export extended (`d81aed4`):
- Total-only branch: `![_to_bool $easy_mode] || catch{dict size} fails || size==0` → `"Remaining: $total"`
- Paren branch: foreach over GAME_REPS, `dict exists` + integer>0 filter, `lappend` parts, `join $parts {, }`, wrapped as `"Remaining: $total  (...)"` (two literal spaces)

Headless run: `BCHM_TEST_RESULT Total=47 Passed=47 Failed=0 Skipped=0`; zero `ERROR)`, zero `bad switch`, zero `FAILED` lines. No REFACTOR needed (implementation landed minimal and comment-documented).

## Task Commits

Each task was committed atomically (TDD pattern):

1. **Task 1: RED — failing format_remaining tests** — `9e2914e` (test)
2. **Task 2: GREEN — implement format_remaining + export** — `d81aed4` (feat)
3. **Task 3: Gates + regression** — no new commit needed (gates passed pre-commit on the feat commit; verification-only task)

## Files Created/Modified
- `vmd/lib/setup_state.tcl` — +33/-1: export list gains `format_remaining`; pure proc appended after randomize_state (v1 source line + two-space rule documented in header comment)
- `vmd/tests/test_setup_state.test` — +32: 6 exact-string cases appended before the BCHM_TEST_RESULT marker block

## Decisions Made
- **Iterate GAME_REPS, not the input dict** — unknown rep keys (e.g. `Bogus`) are structurally unreachable, the defensive posture the plan prescribed ("dict-safe iteration over GAME_REPS, not over the dict")
- **Reuse `_to_bool` for easy_mode** — falsy set (0/""/false/False) matches both v1 Python truthiness and the module's existing validate_state coercion; avoids re-implementing falsiness inline
- **Non-dict counts_by_rep → total-only** via `catch {dict size}` — same defensive shape validate_state uses for its state input; v1 would raise, v2 degrades gracefully (GUI label never breaks mid-game)

## Deviations from Plan

**1. [Plan-internal reconciliation] Added a 6th test case (`format_remaining_easy_all_zero_total_only`)**

- **Found during:** Task 1 (RED test authoring)
- **Issue:** Task 1's action text specified 5 cases, but the must_haves artifact spec requires the suite to cover "(hard / easy-with-counts / easy-all-zero)" and 16-RESEARCH-gametab §3.4 explicitly lists "`easy all-zero → total-only`" as a required setup_state.test addition — the all-zero case was missing from the 5 listed cases
- **Fix:** Added the 6th case (2, {VDW 0 Lines 0}, 1) → `Remaining: 2`, exercising the parts-empty fallback branch the other cases don't reach
- **Files modified:** vmd/tests/test_setup_state.test
- **Verification:** GREEN run Total=47 (= 41 existing + 6 new) Failed=0 — note Total is existing+6, not existing+5, for this reason
- **Committed in:** 9e2914e (Task 1 commit)

---

**Total deviations:** 1 (test-count reconciliation in favor of the must_haves artifact + research; no behavior or scope change)
**Impact on plan:** None negative — strictly closes a gap between task text and the artifact/research contract.

## Issues Encountered
- **Flaky VMD stdin-exit interop (environment, not code):** one headless run completed the suite and printed the marker but vmd.exe then sat at its `vmd > ` prompt instead of consuming the piped `exit` (the documented `< /dev/null` hazard variant; also hit with `echo exit |`). Mitigation used throughout: output always redirected to a log file and parsed via grep (`BCHM_TEST_RESULT`, `ERROR)`, `bad switch`), inner `timeout 180` wrapper so a hang self-reaps before the tool timeout. A later run exited cleanly with the same command — flaky, not deterministic. No code impact.
- **Sibling-executor processes visible:** parallel worktree executors (16-05/16-06) run their own VMD probes concurrently; never killed by process name — only own-PID / timeout-wrapper cleanup.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness
- `setup_state::format_remaining` exported and green — Plan 16-09 (`game_tab::update_remaining`) can consume it directly as `setup_state::format_remaining [registry::remaining] [registry::remaining_by_rep] $easy_mode` → `remain_text` (key_links contract satisfied on the provider side)
- No blockers or concerns carried forward; existing setup_state behavior byte-identical (diff = export line + appended proc only)

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
