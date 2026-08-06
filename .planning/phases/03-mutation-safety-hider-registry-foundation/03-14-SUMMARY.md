---
phase: 03-mutation-safety-hider-registry-foundation
plan: 14
subsystem: testing
tags: [pymol, smoke-test, integration, pseudoatom, pse-roundtrip, backup-restore, sentinel]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation (03-13)
    provides: smoke/phase3_smoke.py setup + criteria 1-4 happy path (the script skeleton extended here)
provides:
  - Complete smoke/phase3_smoke.py (setup + C1-C4 happy path + failure path + Q1/Q2/PSE spikes + summary block)
  - Failure-path restore verification via GameController.abort_on_error (criterion 4 alternate)
  - Q1 spike (pseudoatom return value — informational), Q2 spike (single-call create merge-vs-replace), PSE spike (.pse round-trip sentinel/id/registry)
  - Summary block (RESULTS tally + sys.exit(1) on failure) — ready for plan 03-15 human-verify checkpoint
affects: [03-mutation-safety-hider-registry-foundation (03-15 human-verify checkpoint consumes the complete script)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Informational spikes: record UNVERIFIED C-dispatched behavior (Q1 pseudoatom return, Q2 create merge-vs-replace) without relying on it"
    - "Summary block pattern: RESULTS list accumulated by check() calls across the whole script; sys.exit(nonzero) on any failure"

key-files:
  created: []
  modified:
    - "smoke/phase3_smoke.py — extended with failure path + Q1/Q2/PSE spikes + summary (62 -> 107 lines)"

key-decisions:
  - "Failure path uses GameController.abort_on_error (the REAL orchestrator restore wiring), not direct backup.restore calls — exercises snapshot->restore->discard wiring end-to-end"
  - "Q1/Q2 spikes are INFORMATIONAL: Q1 prints the pseudoatom return value (RESEARCH says never rely on it); Q2 asserts single-call create is REPLACE, but a FAIL (append/double) CONFIRMS the delete+create recommendation — recorded in SUMMARY for the 03-15 checkpoint human to triage"
  - "PSE spike uses gc3.reconstruct_registry() (the DI method) — proves sentinel-survival + id-stability + registry reconstruction with rep=None (documented limitation; Phase 8 sidecar reconciles rep)"
  - "/tmp/phase3_test.pse path follows the plan verbatim; Windows PyMOL resolves /tmp differently — if the human's Windows PyMOL cannot write /tmp, that is a checkpoint triage item, NOT a plan failure"
  - "All iterate calls use space={'stored': ...} (hygienic explicit dict, never space=None which pollutes pymol.__dict__)"

patterns-established:
  - "Smoke-test spike pattern: informational checks assert a hypothesis; a FAIL records the C-dispatched ground truth rather than failing the suite (Q2 FAIL = confirms delete+create recommendation)"
  - "Smoke-test summary block: print N/M passed, sys.exit(1) on any failure, ALL PASSED on success — the single exit code signals pass/fail to the human-verify checkpoint"

# Metrics
duration: 1 min
completed: 2026-08-06
---

# Phase 3 Plan 14: Smoke Test Extension (Failure Path + Spikes + Summary) Summary

**Extended smoke/phase3_smoke.py with the failure-path restore (GameController.abort_on_error), Q1/Q2/PSE research spikes, and a sys.exit summary block — completing the Phase 3 integration smoke test for the 03-15 human-verify checkpoint**

## Performance

- **Duration:** 1 min
- **Started:** 2026-08-06T06:18:55Z
- **Completed:** 2026-08-06T06:20:09Z
- **Tasks:** 2 (1 commit + 1 verification-only)
- **Files modified:** 1 (smoke/phase3_smoke.py: 62 -> 107 lines, +48/-3)

## Accomplishments
- Failure path (criterion 4 alternate): gc2.start(1 hider) -> pre-restore count +1 -> gc2.abort_on_error() returns True -> count back to orig -> verify_intact (informational; backup discarded by abort). Tests the REAL orchestrator restore wiring (snapshot->restore->discard), not direct backup.restore.
- Q2 spike (RESEARCH sec Q2): single-call cmd.create(obj, "_spike_src") — the AMBIGUOUS merge-vs-replace form. Asserts n_after == n_before (REPLACE). A FAIL (append/double) CONFIRMS the delete+create recommendation recorded across 03-05/03-12.
- Q1 spike (RESEARCH sec Q1): prints cmd.pseudoatom return value + type (informational — RESEARCH says code never relies on it; this just records what it is for the SUMMARY). Cleans up via cmd.remove.
- PSE spike (RESEARCH sec Q4): gc3.start(1 hider) -> save /tmp/phase3_test.pse -> delete obj -> load .pse -> iterate sentinels (space={'stored': pse_sent}) -> checks sentinel survives (len==1), id stable (pse_sent == [saved_id]), reconstruct_registry rebuilds (len==1), rep is None (sentinel carries no rep). mutation.cleanup_hiders cleans up.
- Summary block: reads RESULTS (accumulated by all check() calls), prints N/M passed, sys.exit(1) on any failure, ALL PASSED on success.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend smoke script with failure path + Q1/Q2/PSE spikes + summary** - `476e74b` (feat)
2. **Task 2: Run WSL gate suite (final syntax + regression check)** - no commit (verification-only per plan)

**Plan metadata:** (pending — created after this summary)

## Files Created/Modified
- `smoke/phase3_smoke.py` — Extended from 62 to 107 lines: added failure-path restore (GameController.abort_on_error), Q2 spike (single-call create merge-vs-replace), Q1 spike (pseudoatom return value print), PSE spike (.pse round-trip sentinel survival + id stability + reconstruct_registry with rep=None), and the summary block (RESULTS tally + sys.exit). The 03-13 comment marker was replaced with these sections; the summary now sits at the very end of the script.

## Decisions Made
- Failure path uses `GameController.abort_on_error()` (the REAL orchestrator's restore path), not direct `backup.restore` calls — exercises the full wiring (snapshot->restore->discard) as the plan explicitly requires.
- Q1/Q2 spikes are INFORMATIONAL: Q1 prints the pseudoatom return value (RESEARCH sec Q1: never rely on it); Q2 asserts single-call create is REPLACE, but a FAIL (appended/doubled) CONFIRMS the delete+create recommendation — the result is recorded in the SUMMARY for the 03-15 checkpoint human to triage, treated as informational pass.
- PSE spike uses `gc3.reconstruct_registry()` (the DI method from 03-11) — proves sentinel-survival + id-stability + registry reconstruction with rep=None (the documented limitation; Phase 8 .bcm sidecar reconciles rep).
- `/tmp/phase3_test.pse` path follows the plan verbatim. Windows PyMOL resolves `/tmp` differently (the checkpoint human runs this); if the human's Windows PyMOL cannot write `/tmp`, that is a checkpoint triage item, NOT a plan failure.
- All iterate calls use `space={'stored': ...}` (hygienic explicit dict — never `space=None` which pollutes `pymol.__dict__`; mirrors the mutation.py pattern from 03-06).

## Deviations from Plan

None - plan executed exactly as written. The code blocks were inserted verbatim from the plan; the 03-13 comment marker was replaced with the failure-path + Q1/Q2/PSE + summary sections as specified.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required. The smoke script is run by a human in Windows PyMOL via `pymol -cq smoke/phase3_smoke.py` (the runtime tier the WSL agent cannot reach — AGENTS.md environment split).

## Next Phase Readiness
- The smoke script is COMPLETE: setup + C1-C4 happy path + failure path + Q1/Q2/PSE spikes + summary block. Ready for the plan 03-15 Windows PyMOL human-verify checkpoint.
- All WSL gates green: py_compile (smoke + biochemeleon all) + 144 tests (54 registry + 90 setup_state, no regression) + Pitfall-1/11 ZERO (scoped to biochemeleon/ + smoke/) + completeness gate 20 (>=10) + async_=0 1 + space={'stored'} 2 + abort_on_error 1 + reconstruct_registry 1 + ALL PASSED/sys.exit 2.
- The Q1/Q2 spikes are INFORMATIONAL — their runtime results (Q1 print value, Q2 REPLACE-vs-append) will be recorded by the 03-15 checkpoint human and folded into the RESEARCH findings. A Q2 FAIL (append) is expected to CONFIRM the delete+create recommendation already implemented in 03-05/03-12.
- The PSE spike validates the documented limitation (rep=None post-reload) and the DI reconstruction path — the load-bearing assertion for .pse round-trip robustness (RESEARCH sec Q4).
- Remaining Phase 3 work: plan 03-15 (Windows PyMOL human-verify checkpoint — runs the complete script) + plans 03-16..03-20.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
