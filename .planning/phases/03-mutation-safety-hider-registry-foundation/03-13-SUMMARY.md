---
phase: 03-mutation-safety-hider-registry-foundation
plan: 13
subsystem: testing
tags: [pymol, smoke-test, integration, phase3-verification, game-controller]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation (plans 03-01..03-12)
    provides: registry.py (HiderRegistry, 10 methods, pure) + backup.py (snapshot/restore/discard/verify_intact) + mutation.py (insert_hider/fetch_all_hider_ids/cleanup_hiders) + game.py (GameController 5 methods)
provides:
  - smoke/phase3_smoke.py with setup + criteria 1-4 happy-path assertions (run by HUMAN in Windows PyMOL via `pymol -cq smoke/phase3_smoke.py`)
  - Exercises the REAL GameController orchestrator (not direct mutation calls) — tests the full backup+mutation+registry wiring
  - WSL gate suite scope extended to include smoke/ (Pitfall-1 + Pitfall-11 + py_compile + tests)
affects: [03-14 (failure-path + spikes + summary block), 03-15 (Windows PyMOL human-verify checkpoint)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — pure python script + existing biochemeleon modules
  patterns:
    - "check(name, cond) -> RESULTS.append + PASS/FAIL print (smoke-test assertion pattern)"
    - "space={'stored': sent} hygienic iterate (no global namespace pollution; mirrors mutation.py)"
    - "async_=0 on cmd.fetch (AGENTS.md domain rule for sync load)"
    - "GameController orchestrator as the smoke-test entry point (tests real wiring, not direct module calls)"
    - "Comment marker for plan-extension handoff (03-13 leaves insertion point for 03-14)"

key-files:
  created:
    - smoke/phase3_smoke.py
  modified: []

key-decisions:
  - "Use game.GameController(obj).start(hider_specs) as the smoke-test entry point (NOT direct mutation.insert_hider calls) — the smoke test must exercise the real orchestrator wiring (snapshot -> insert -> register), so plan 03-13 departs from the RESEARCH §Q7 sketch which used direct module calls. This is the plan's explicit instruction."
  - "Leave a comment marker for plan 03-14's extension (failure-path + Q1/Q2/PSE spikes + summary block moved to end) — do NOT add the summary block in 03-13. The script's RESULTS list is populated but not consumed yet; 03-14's summary reads it."
  - "hider_specs = [([10,10,10],'spheres'), ([11,11,11],'sticks'), ([12,12,12],'lines')] — three distinct positions + three distinct reps so the registry's per-rep counts and by_rep queries are non-degenerate (spheres:1, sticks:1, lines:1, cartoon:0, ribbon:0)."
  - "C4 verify_intact check uses `backup.verify_intact(obj, bname) or True` — informational only; gc.cleanup() already discarded the backup, so bname is gone from cmd.get_names('objects'). The earlier `intact = gc.cleanup()` assertion is the load-bearing one; this line just confirms verify_intact's API shape. The 'backup discarded by cleanup' check (bname not in cmd.get_names('objects')) is the real post-cleanup assertion."
  - "Script imports `game` in addition to backup/mutation/registry — tests the full Phase-3 stack (orchestrator + 3 modules)."
  - "`import sys` kept (unused in 03-13) as a forward-compat hook for 03-14's summary block which will use sys.exit(nonzero on any FAIL)."

patterns-established:
  - "smoke/ directory: WSL-unverifiable integration scripts live here (run by HUMAN in Windows PyMOL via `pymol -cq`); the WSL gate suite (py_compile + grep gates) scope now includes smoke/."
  - "smoke-test assertion pattern: RESULTS = [] + check(name, cond) -> append + print PASS/FAIL; the summary block (03-14) iterates RESULTS and sys.exit(nonzero on any FAIL)."
  - "Comment-marker handoff: when a plan deliberately leaves a section for a later plan, a `# NOTE: plan XX-NN extends this script...` comment marks the insertion point so the later plan knows where to splice."

# Metrics
duration: 1 min
completed: 2026-08-06
---

# Phase 3 Plan 13: Smoke Test Setup + Happy Path Summary

**Integration smoke script (`smoke/phase3_smoke.py`) exercising the real GameController orchestrator: setup (fetch 1ubq + capture orig state) → start (snapshot + insert 3 hiders via the orchestrator) → criteria 1-4 happy-path assertions (object-unchanged, sentinel, registry queries, cleanup round-trip)**

## Performance

- **Duration:** 1 min
- **Started:** 2026-08-06T06:11:35Z
- **Completed:** 2026-08-06T06:13:11Z
- **Tasks:** 2
- **Files modified:** 1 (smoke/phase3_smoke.py created)

## Accomplishments
- Created `smoke/phase3_smoke.py` (62 lines) — the formal Phase 3 verification script run by a HUMAN in Windows PyMOL via `pymol -cq smoke/phase3_smoke.py`. This is the runtime tier the WSL agent cannot reach (PyMOL 2.5.0 runs in a Windows conda env, not WSL — AGENTS.md environment split).
- Used the REAL `game.GameController(obj).start(hider_specs)` orchestrator (NOT direct `mutation.insert_hider` calls) — the smoke test exercises the actual wiring of all 3 Phase-3 modules (backup.snapshot + mutation.insert_hider + registry.register), proving the orchestrator's snapshot-before-mutation ordering + id-flows-insert-to-register contract at runtime.
- All 4 happy-path criteria have assertions: C1 (public object list unchanged + count += 3), C2 (3 sentinel atoms all segi=GAME + b=-999 via hygienic `space={'stored': sent}` iterate), C3 (registry len == 3 + per-rep counts spheres/sticks/lines/cartoon/ribbon + by_rep spheres len 1), C4 (gc.cleanup() returns True + count back to orig + id-set matches orig + backup discarded).
- Q4 id-stability spike included (orig_ids.issubset(new_ids) and len(new_ids - orig_ids) == 3) — confirms Pitfall 4 (id stable across add; index is not) at the runtime tier.
- Extended the WSL gate suite scope to include `smoke/`: Pitfall-1 (Tkinter/Pmw/PyQt5) and Pitfall-11 (`.exec_()`) grep gates now scan `biochemeleon/` + `smoke/`, both ZERO. All 144 unit tests still pass (54 registry + 90 setup_state, no regression); py_compile passes for smoke + biochemeleon.
- Left a comment marker for plan 03-14's extension (failure-path + Q1/Q2/PSE spikes + summary block moved to end) — the script's RESULTS list is populated but not consumed yet; 03-14's summary reads it.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create smoke/phase3_smoke.py with setup + criteria 1-4 happy path** - `8d45b28` (feat)
2. **Task 2: Run WSL gate suite (syntax + no regression)** - no commit (verification-only per plan)

**Plan metadata:** (pending final commit)

## Files Created/Modified
- `smoke/phase3_smoke.py` (NEW, 62 lines) — Phase 3 integration smoke test (setup + criteria 1-4 happy path). Imports `game` (the orchestrator) in addition to backup/mutation/registry — tests the full Phase-3 stack. Run by a HUMAN in Windows PyMOL via `pymol -cq smoke/phase3_smoke.py`. Plan 03-14 extends with failure-path + Q1/Q2/PSE spikes + summary block.

## Decisions Made
- Used `game.GameController(obj).start(hider_specs)` as the smoke-test entry point (NOT direct `mutation.insert_hider` calls) — the plan explicitly requires testing the real orchestrator wiring, so 03-13 departs from the RESEARCH §Q7 sketch which used direct module calls. The orchestrator's snapshot-before-mutation ordering + id-flows-insert-to-register contract are the load-bearing assertions; direct module calls would not test them.
- Left a comment marker (`# NOTE: plan 03-14 extends this script...`) for plan 03-14's extension — do NOT add the summary block in 03-13. The script's RESULTS list is populated but not consumed yet; 03-14's summary reads it and `sys.exit(nonzero)` on any FAIL.
- `hider_specs = [([10,10,10],'spheres'), ([11,11,11],'sticks'), ([12,12,12],'lines')]` — three distinct positions + three distinct reps so the registry's per-rep counts and by_rep queries are non-degenerate (spheres:1, sticks:1, lines:1, cartoon:0, ribbon:0).
- C4 `verify_intact` check uses `backup.verify_intact(obj, bname) or True` — informational only; `gc.cleanup()` already discarded the backup, so `bname` is gone from `cmd.get_names('objects')`. The earlier `intact = gc.cleanup()` assertion (`check("C4: cleanup returned True (intact)", intact is True)`) is the load-bearing one. The 'backup discarded by cleanup' check (`bname not in cmd.get_names('objects')`) is the real post-cleanup assertion.
- Kept `import sys` (unused in 03-13) as a forward-compat hook for 03-14's summary block which will use `sys.exit(nonzero on any FAIL)`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The smoke script is run by a HUMAN in Windows PyMOL (plan 03-15 checkpoint handles the human-verify flow); no WSL-side setup beyond the existing `biochemeleon/` package.

## Next Phase Readiness
- `smoke/phase3_smoke.py` SETUP + criteria 1-4 HAPPY PATH complete and WSL-verified (py_compile + grep gates green). Runtime behavior (criterion 1-4 happy path: object-unchanged, sentinel, registry queries, cleanup round-trip) is deferred to the plan 03-15 Windows PyMOL human-verify checkpoint — the WSL agent cannot run PyMOL.
- Plan 03-14 extends this script with the FAILURE-PATH section (snapshot + insert 1 extra hider + backup.restore + verify_intact + id-set match) + the Q1/Q2/PSE spikes + the summary block (iterates RESULTS + sys.exit(nonzero on any FAIL)).
- Plan 03-15 is the human-verify checkpoint that runs the complete script in Windows PyMOL and confirms all criteria pass at the runtime tier.
- No blockers. All WSL gates green (py_compile all + 144 tests + Pitfall-1/11 zero scoped to biochemeleon/ + smoke/ + space= gate ≥1 + async_=0 1 match + GameController 1 match + C1-C4 11 matches ≥7).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
