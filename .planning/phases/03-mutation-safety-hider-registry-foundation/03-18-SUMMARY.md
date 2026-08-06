---
phase: 03-mutation-safety-hider-registry-foundation
plan: 18
subsystem: testing
tags: [regression-gate, py_compile, unittest, pitfall-gates, headless-pymol, smoke-test, phase-complete-gate]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation (all code plans 03-01..03-15)
    provides: the complete Phase 3 stack (registry.py pure + backup.py/mutation.py/game.py cmd-coupled + tests/test_registry.py + smoke/phase3_smoke.py), runtime-verified by 03-15
provides:
  - "Final 12-gate WSL regression suite GREEN — Phase 3 ships clean (no cross-plan interaction broke any earlier grep-gate invariant)"
  - "Headless PyMOL smoke re-confirmed 24/24 ALL PASSED at runtime (no code changed since 03-15; shipped state stable)"
  - "Phase-3-complete gate declaration: code + tests + runtime all verified; ready for 03-19 (VERIFICATION.md) + 03-20 (phase handoff)"
affects: [03-19-VERIFICATION, 03-20-phase-summary, Phase 4-hider-generators]

# Tech tracking
tech-stack:
  added: []
  patterns: [final-regression-gate-suite-as-reporting-plan, headless-pymol-smoke-re-run-from-wsl]

key-files:
  created: [.planning/phases/03-mutation-safety-hider-registry-foundation/03-18-SUMMARY.md]
  modified: []

key-decisions:
  - "Phase 3 ships CLEAN: all 12 WSL gates green + headless smoke 24/24 ALL PASSED re-confirmed"
  - "registry.py completeness gate returns 11 (not the nominal 10) due to the documented HiderRecord.to_dict ∩ HiderRegistry.to_dict overlap from 03-01/03-07 — all 10 HiderRegistry methods present, NOT a failure"
  - "This is a REPORTING plan: modifies NO code files; if any gate had failed it would have been reported for gap closure (not auto-fixed)"

patterns-established:
  - "Final pre-declaration regression gate: run every WSL-runnable check across biochemeleon/ + smoke/ + tests/ together as a no-modify plan that catches cross-plan interactions (a later plan's edit breaking an earlier plan's grep-gate invariant)"

# Metrics
duration: 2 min
completed: 2026-08-06
---

# Phase 3 Plan 18: Final Regression Gate Summary

**All 12 WSL gates GREEN + headless PyMOL smoke 24/24 ALL PASSED re-confirmed — Phase 3 ships clean (no file modifications; verification-only plan)**

## Performance

- **Duration:** 2 min (111 s)
- **Started:** 2026-08-06T20:37:28Z
- **Completed:** 2026-08-06T20:39:19Z
- **Tasks:** 1 (gate-run; 12 plan gates + 7 completeness/fix-confirmation gates + 1 optional headless smoke)
- **Files modified:** 0 (this plan modifies NO code files — it is a gate-run/reporting plan; only SUMMARY.md + STATE.md are written)

## Accomplishments
- Ran the FINAL full-package regression gate: every WSL-runnable check across `biochemeleon/` + `smoke/` + `tests/` together — the phase-complete gate before declaring Phase 3 done. All 12 plan gates green; no cross-plan interaction broke any earlier grep-gate invariant.
- Re-confirmed the shipped state at runtime: re-staged `biochemeleon/` + `smoke/phase3_smoke.py` to the Windows-facing path (`wsl2win_cp.sh`; byte-identical to repo, cmp-verified) and re-ran the headless PyMOL smoke (`run-conda-pymol.bat -cq`) — **24/24 ALL PASSED**, exit 0. No code changed since 03-15; the shipped state is stable.
- Confirmed the 03-15 runtime fixes hold at the gate tier: the bad `b -999` selector is gone (0 matches), the fixed `b < 0` selector is present (1 match, `mutation.py:113`), and the uppercase `ID` iterate symbol is used everywhere (3 `stored.append...ID` matches; 0 lowercase `id`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Run the full Phase 3 regression gate suite** — NO COMMIT (this plan modifies no files; it is a verification/gate-run plan).

**Plan metadata:** `docs(03-18): complete final regression gate plan` (SUMMARY + STATE only)

## Gate Results (12 plan gates + 7 confirmation gates + 1 optional runtime gate)

### Plan gates (03-18-PLAN.md) — ALL GREEN

| # | Gate | Command | Expected | Actual | Result |
|---|------|---------|----------|--------|--------|
| 1 | py_compile ALL | `python3.6 -m py_compile biochemeleon/*.py smoke/phase3_smoke.py` | exit 0, no output | exit 0, no output | PASS |
| 2 | unittest test_registry -v | `python3.6 -m unittest tests.test_registry -v` | OK, count > 0 | Ran 54 tests, OK | PASS |
| 3 | unittest test_setup_state -v | `python3.6 -m unittest tests.test_setup_state -v` | Ran 90 tests, OK | Ran 90 tests, OK | PASS |
| 4 | combined unittest -v | `python3.6 -m unittest tests.test_registry tests.test_setup_state -v` | OK | Ran 144 tests, OK | PASS |
| 5 | Pitfall-1 (Tk/Pmw/PyQt5-raw) | `grep -rnE "import Tkinter\|...\|import PyQt5" biochemeleon/ smoke/` | 0 matches | 0 matches (exit 1) | PASS |
| 6 | Pitfall-11 (.exec_()) | `grep -rnE "\.exec_\(\)" biochemeleon/ smoke/` | 0 matches | 0 matches (exit 1) | PASS |
| 7 | Registry purity | `grep -n "from pymol" biochemeleon/registry.py` | 0 matches | 0 matches (exit 1) | PASS |
| 8 | cmd-coupled (`from pymol import cmd`) | `grep -c "from pymol import cmd" backup.py mutation.py game.py` | 1 each (3 total) | 1 / 1 / 1 | PASS |
| 9 | Sentinel `segi='GAME'` | `grep -nE "segi.?=.?['\"]GAME['\"]" mutation.py` | >=1 | 5 matches | PASS |
| 10 | `space=` hygiene | `grep -n "space=" mutation.py backup.py smoke/phase3_smoke.py` | >=4 | 9 matches | PASS |
| 11 | Architecture (setup_state pure) | `grep -nE "from pymol\|from pymol\.Qt" setup_state.py` | 0 matches | 0 matches (exit 1) | PASS |
| 12 | Orchestration (game.py wires 3 modules) | `grep -nE "backup\.\|mutation\.\|registry\." game.py` | >=6 | 18 matches | PASS |

### Confirmation gates (03-15 fix verification + module completeness) — ALL GREEN

| # | Gate | Expected | Actual | Result |
|---|------|----------|--------|--------|
| 13 | mutation.py completeness (`def insert_hider\|fetch_all_hider_ids\|cleanup_hiders`) | 3 | 3 | PASS |
| 14 | game.py completeness (`def __init__\|start\|cleanup\|abort_on_error\|reconstruct_registry`) | 5 | 5 | PASS |
| 15 | backup.py completeness (`def snapshot\|restore\|discard\|verify_intact`) | 4 | 4 | PASS |
| 16 | registry.py completeness (10 HiderRegistry methods) | 10 | 11 (see note) | PASS (documented overlap) |
| 17a | bad selector `b -999` in mutation.py | 0 | 0 (exit 1) | PASS |
| 17b | fixed selector `b < 0` in mutation.py | 1 | 1 (`mutation.py:113`) | PASS |
| 18a | lowercase `id` in `stored.append` (mutation.py + smoke) | 0 | 0 (exit 1) | PASS |
| 18b | uppercase `ID` in `stored.append` (mutation.py + smoke) | >=3 | 3 | PASS |

> **Note on gate 16:** returns 11 (not the nominal 10) because `def to_dict` matches BOTH `HiderRecord.to_dict` (added 03-01) AND `HiderRegistry.to_dict` (added 03-07) — a pre-existing, documented overlap (STATE.md 03-10 decision). All 10 HiderRegistry methods are present; the +1 is the `HiderRecord` helper. `grep -c` counts matching lines, not distinct method names. NOT a failure.

### Optional runtime gate (headless PyMOL smoke re-run) — GREEN

Re-staged via `wsl2win_cp.sh` (`biochemeleon/` byte-identical to repo, cmp-verified) + copied `smoke/phase3_smoke.py`. Ran from the staged Windows-facing path:

```
cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -45
```

Result: **24/24 passed — ALL PASSED** (exit 0). The 24 checks span C1 (object-list unchanged + count+=3), C2 (3 sentinels segi=GAME b=-999), Q4 (ids stable across insert), C3 (registry len=3 + per-rep counts + by_rep), C4 happy path (cleanup returns True + count back to orig + id-set matches + backup discarded), failure path (abort returns True + count back to orig), Q2 (single-call create IS REPLACE), Q1 (pseudoatom returns None), and the PSE reload spikes (sentinel survives, id stable, b=-999.0 preserved, reconstruct works, rep=None). No code changed since 03-15; the shipped state is runtime-stable.

## Files Created/Modified
- `.planning/phases/03-mutation-safety-hider-registry-foundation/03-18-SUMMARY.md` — this file (the gate-run report). No code files touched.

## Decisions Made
- **Phase 3 ships CLEAN.** The final 12-gate WSL regression suite is green and the headless smoke re-confirms 24/24 ALL PASSED at runtime. Phase 3 is ready for the documentation handoff (03-19 VERIFICATION.md + 03-20 phase SUMMARY).
- **registry.py completeness gate = 11 is the expected actual value**, not a regression. The `def to_dict` overlap (HiderRecord + HiderRegistry) is documented since 03-10; the gate's nominal "10" counts distinct HiderRegistry method names while `grep -c` counts matching lines. All 10 HiderRegistry methods are present.
- **This is a reporting plan — no auto-fix.** Per the plan's explicit instruction, if any gate had failed it would have been reported verbatim for gap closure (plans 03-16/03-17 or a dedicated gap-closure plan), NOT auto-fixed inline. None failed.

## Deviations from Plan

None — plan executed exactly as written. (The plan was a no-modify gate run; the only files written are SUMMARY.md + STATE.md, as the plan's `<output>` specifies.)

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. (The headless smoke re-run uses the already-configured `C:\src\run-conda-pymol.bat` + Windows conda env `chemtools-win10` documented in AGENTS.md; no new setup.)

## Next Phase Readiness
- **Phase 3 code is COMPLETE and VERIFIED** — pure layer (registry.py + setup_state.py) fully unit-tested in WSL (144 tests); cmd-coupled layer (backup.py/mutation.py/game.py) runtime-verified via headless PyMOL smoke (24/24); all architectural invariants (purity, dependency direction, sentinel hygiene, id-stability, snapshot-before-mutation) hold at both tiers.
- **No blockers.** The only "non-nominal" gate result (registry completeness = 11 vs 10) is a documented pre-existing overlap, not a defect.
- **Remaining Phase 3 work is documentation-only:** 03-19 (03-VERIFICATION.md) + 03-20 (03-SUMMARY.md phase handoff to Phase 4). Wave 10 siblings 03-16 (AGENTS.md domain rules + grep gates) + 03-17 (STATE.md Phase 3 complete + PITFALLS.md MEDIUM-flag resolution) ran concurrently.
- **Phase 4 (hider generators) can proceed** on the verified Phase 3 foundation: `insert_hider`/`fetch_all_hider_ids`/`cleanup_hiders` + backup `snapshot`/`restore`/`verify_intact` + GameController `start`/`cleanup`/`abort` + HiderRegistry CRUD/queries/serialize/reconstruct are all proven correct at the runtime tier.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
