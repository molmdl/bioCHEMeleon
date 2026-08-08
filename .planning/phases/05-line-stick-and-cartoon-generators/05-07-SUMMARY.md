---
phase: 05-line-stick-and-cartoon-generators
plan: 07
subsystem: testing
tags: [pymol, line-stick, neighbor-selection, gui-align, free-nterminal-valence, defensive-error, headless-smoke, gap-closure]

# Dependency graph
requires:
  - phase: 05-line-stick-and-cartoon-generators (plan 02)
    provides: mutation.py insert_line_stick_hider (the function that raised IndexError on nbr[0] when the neighbor atom was removed)
  - phase: 05-line-stick-and-cartoon-generators (plan 05)
    provides: the _on_start GUI path that captured ALL atom ids as neighbor candidates (the root-cause source); the 05-05 human-verify that surfaced the IndexError
  - phase: 05-line-stick-and-cartoon-generators (plan 04)
    provides: smoke/phase5_smoke.py — the headless smoke that used `name CA` (so it never caught the GUI bug); this plan extends it with section 5b
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: mutation.free_nterminal_valence (the H+cap removal that invalidated non-CA neighbor ids) + mutation.cleanup_hiders (used by section 5b cleanup)
provides:
  - GUI path aligned with smoke: _on_start neighbor_ids iterate now uses `name CA` (was all atoms) — CA atoms survive free_nterminal_valence, so sampled neighbor_ids stay valid when insert_line_stick_hider runs. Fixes the 05-05 GUI IndexError on nbr[0].
  - Defensive ValueError in mutation.insert_line_stick_hider — converts the cryptic `IndexError: list index out of range` on nbr[0] into a clear ValueError with a diagnostic message pointing to the `name CA` requirement (future-proofs against any new code path that removes CA atoms).
  - smoke/phase5_smoke.py section 5b — reproduces the exact _on_start flow (capture CA ids -> free_nterminal_valence -> insert_line_stick_hider -> cleanup) and verifies the root cause is fixed: ALL 76 CA neighbor_ids survive free_nterminal_valence (diag: surviving=76/76), and insert_line_stick_hider succeeds with a CA neighbor (no IndexError). 33/33 ALL PASSED, exit 0.
affects: [05-08 (alt-conf cartoon gap closure — shares the GUI path + free_nterminal_valence), Phase 6 (hint/reveal — the line/stick path is now GUI-safe), any future code path that removes atoms before insert_line_stick_hider]

# Tech tracking
tech-stack:
  added: []  # no new libs; 1-line selector change + 1 defensive check
  patterns:
    - "GUI/smoke alignment: the GUI path (_on_start) and the smoke path must use the SAME selector for neighbor capture. The 05-05 bug was caused by _on_start using `not segi GAME` (all atoms) while the smoke used `not segi GAME and name CA` — the smoke never caught the bug because CA atoms always survive free_nterminal_valence. Going forward, the GUI and smoke paths are aligned on `name CA`."
    - "Defensive ValueError over IndexError: when a list index access (nbr[0]) can fail due to upstream state changes (atom removal), guard it with `if not nbr: raise ValueError(<diagnostic>)` so the error message points to the root cause (neighbor_id removal) instead of a cryptic `list index out of range`. Future-proofs against regressions in the selector logic."
    - "CA atoms survive free_nterminal_valence: free_nterminal_valence only removes H atoms bonded to the terminal N and cap residue atoms (ACE/formyl). CA atoms are NEVER removed, so `name CA` is the safe selector for neighbor capture when cartoon/ribbon hiders (which trigger free_nterminal_valence) are in the same round."

key-files:
  created: []
  modified:
    - biochemeleon/__init__.py — _on_start neighbor_ids iterate selector changed from `%s and not segi GAME` to `%s and not segi GAME and name CA` (line 147); comment explains the CA-survival rationale (05-05 GUI bug, 05-07 fix). 227 -> 231 lines.
    - biochemeleon/mutation.py — insert_line_stick_hider: added `if not nbr: raise ValueError(...)` between the iterate_state call and the `nbr[0]` access (lines 220-225); converts IndexError into a diagnostic ValueError. 613 -> 619 lines.
    - smoke/phase5_smoke.py — new section 5b (GUI-PATH ALIGNMENT) inserted between section 5 (CLEANUP) and section 6 (optional spike): 49 lines, 4 new gui-align checks. 228 -> 277 lines.

key-decisions:
  - "Minimal fix: 1 selector change in __init__.py + 1 defensive check in mutation.py. No logic changes, no architectural changes. The selector change aligns the GUI path with the smoke path (both now use `name CA`); the defensive ValueError is a safety net for any future regression that removes CA atoms."
  - "The new smoke section 5b reproduces the EXACT _on_start flow (capture CA ids -> free_nterminal_valence -> insert_line_stick_hider -> cleanup) so the smoke now covers the GUI code path, not just the isolated mechanism. This closes the structural gap that let the 05-05 bug ship: the smoke used a different selector than the GUI."

patterns-established:
  - "GUI/smoke selector alignment: when the GUI and smoke exercise the same code path, they must use the same selectors — otherwise the smoke is structurally blind to GUI-only bugs."
  - "Defensive ValueError over IndexError: guard list-index accesses that depend on upstream state with a diagnostic ValueError."

# Metrics
duration: 5min
completed: 2026-08-08
---

# Phase 5 Plan 07: Line/Stick IndexError Fix Summary

**Aligned GUI neighbor selection with smoke (`name CA`) + defensive ValueError, closing the 05-05 GUI-only IndexError root cause; smoke 33/33 ALL PASSED with a new CA-survival section.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-08-08T16:56:01Z
- **Completed:** 2026-08-08T17:00:57Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Fixed the root cause of the 05-05 GUI IndexError: `_on_start` now captures neighbor ids via `name CA` (aligned with the smoke path), so sampled neighbor_ids survive `free_nterminal_valence` removal (which only removes H + cap residue atoms, never CA). The GUI line/stick path is now safe.
- Added a defensive `ValueError` in `mutation.insert_line_stick_hider` — converts the cryptic `IndexError: list index out of range` on `nbr[0]` into a clear diagnostic message pointing to the `name CA` requirement. Future-proofs against any new code path that removes CA atoms.
- Extended `smoke/phase5_smoke.py` with section 5b (GUI-PATH ALIGNMENT) that reproduces the exact `_on_start` flow and verifies the root cause is fixed: ALL 76 CA neighbor_ids survive `free_nterminal_valence` (diag: `surviving=76/76`), and `insert_line_stick_hider` succeeds with a CA neighbor (no IndexError). The smoke now covers the GUI code path, closing the structural gap that let the 05-05 bug ship.

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix _on_start neighbor selection + add defensive ValueError in insert_line_stick_hider** - `fccceb3` (fix)
2. **Task 2: Update smoke to verify CA-selection path + post-removal survival** - `e76e74b` (test)

## Files Created/Modified
- `biochemeleon/__init__.py` - `_on_start` neighbor_ids iterate selector: `%s and not segi GAME` -> `%s and not segi GAME and name CA`; comment explains the CA-survival rationale (05-05 GUI bug, 05-07 fix).
- `biochemeleon/mutation.py` - `insert_line_stick_hider`: added `if not nbr: raise ValueError(...)` between the `iterate_state` call and the `nbr[0]` access; converts IndexError into a diagnostic ValueError.
- `smoke/phase5_smoke.py` - New section 5b (GUI-PATH ALIGNMENT): re-fetch 1ubq -> capture CA neighbor_ids -> find N-terminus -> free_nterminal_valence -> verify ALL CA ids survive -> insert_line_stick_hider (no IndexError) -> cleanup restores count. 4 new gui-align checks.

## Decisions Made
None - followed plan as specified. The fix is minimal (1 selector change + 1 defensive check + 1 smoke section) and matches the plan verbatim.

## Deviations from Plan

None - plan executed exactly as written.

Minor note (not a deviation): The plan's prose said "~34 checks (29 existing + 5 new)" but the actual section 5b code (copied verbatim from the plan) has 4 `check()` calls, not 5. The smoke runs 33 checks total (28 existing + 4 new + 1 spike), all PASSED. This is a miscount in the plan's prose, not a code deviation — the code matches the plan's code block exactly.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The GUI line/stick path is now safe (no IndexError). The 05-05 human-verify partial-approval blocker (line/stick IndexError) is resolved.
- The remaining Phase 5 gap-closure items (alt-conf cartoon terminal-extension on 1ubq — plan 05-06; ribbon representation support — plan 05-08) are separate and unaffected by this fix.
- All WSL gates green: py_compile all + 90 tests (no regression) + Pitfall-1=0 + exec_=1 on allowed QMessageBox + purity generators.py/registry.py=0.
- Headless smoke 33/33 ALL PASSED, exit 0.
- No blockers or concerns for downstream phases.

---
*Phase: 05-line-stick-and-cartoon-generators*
*Completed: 2026-08-08*
