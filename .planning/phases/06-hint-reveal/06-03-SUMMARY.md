---
phase: 06-hint-reveal
plan: 03
subsystem: testing
tags: [pymol, headless-smoke, human-verify, checkpoint, hint, reveal, counter-reset, backup-restore, object-scoped-selection, regression-tests]

# Dependency graph
requires:
  - phase: 06-hint-reveal
    provides: GameController.hint()/reveal_one()/reveal_all()/_mark_found + _reveal_count/_hint_count counters + on_counts_changed 4th set_callbacks param (plan 06-01)
  - phase: 06-hint-reveal
    provides: GameTab Hint/Reveal-one/Reveal-all QPushButtons + reveal counter QLabel + _confirm helper + _on_counts_changed slot (plan 06-02)
  - phase: 03-mutation-safety-hider-registry
    provides: backup.snapshot/restore/discard/verify_intact two-step restore (delete+create) — the cleanup mechanism 06-03 retrofitted into cleanup()
  - phase: 04-mvp-core-loop-sphere
    provides: smoke/phase4_smoke.py pattern (RESULTS/check/=== SUMMARY ===/sys.exit(1)) + headless run via cmd.exe /c run-conda-pymol.bat -cq
provides:
  - smoke/phase6_smoke.py (131 lines, pure pymol.cmd.* — NO Qt) — headless verification of hint neighbor coloring + reveal-one + reveal-all + counter reset + cleanup restore-from-backup (29/29 ALL PASSED)
  - 4 new regression tests in tests/test_game_controller.py (test_hint_no_neighbors + 3 cleanup/abort counter-reset tests)
  - 3 runtime bug fixes in biochemeleon/game.py (hint sparse-hider filter, cleanup restore-from-backup, hint_sele object-scoped selection) + 1 GUI fix in biochemeleon/gui_game.py (reveal label reset in start_countdown)
  - Human-verify checkpoint APPROVED — all 4 Phase-6 success criteria (C1 Hint, C2 Reveal-one, C3 Reveal-all, C4 Reveal counter resets) + button-guard check confirmed in a real Windows PyMOL GUI session
affects: [Phase 6 phase-level 06-VERIFICATION.md / 06-SUMMARY.md handoff, Phase 7 (cleanup restore-from-backup pattern is the canonical cleanup path; counters reset in cleanup/abort), Phase 10 (win screen consumes hint_count via on_counts_changed; hint_count counter now reset correctly per round), Phase 11 (object-scoped selection pattern for around operators — backup corruption root cause generalizes to any around-based coloring)]

# Tech tracking
tech-stack:
  added: []
  patterns: [Object-scoped PyMOL `around` selections (append `and <target_obj>` — the around operator crosses object boundaries by default, coloring atoms in coordinate-identical backup copies), cleanup via backup.restore (delete+create two-step) instead of sentinel-remove+verify_intact (restores hint-colored real-atom colors in one step), counter reset in cleanup()/abort_on_error() (game over → _reveal_count/_hint_count back to 0), headless smoke cleanup assertions (hint orange cleared + no GAME atoms remain — verify restore-from-backup, not just count-back-to-orig)]

key-files:
  created:
    - smoke/phase6_smoke.py
  modified:
    - biochemeleon/game.py
    - biochemeleon/gui_game.py
    - tests/test_game_controller.py

key-decisions:
  - "cleanup() now calls backup.restore (delete+create two-step) instead of mutation.cleanup_hiders + backup.verify_intact + backup.discard — the backup (snapshotted in start() before any mutation/hint coloring) has the original atoms + colors, so restore removes hiders AND restores hint-colored real neighbor atoms to their original colors in one step"
  - "hint() selection is object-scoped: the `around` operator's selection now ends with `and <target_obj>` to prevent coloring atoms in the _bchm_backup object (coordinate-identical copy) — extracted to a hint_sele(hider_id) helper for DRY (used by both the candidate filter and cmd.color)"
  - "hint() filters hidden hiders to candidates with count_atoms(sele) > 0 before random.choice — if no candidate has neighbors within HINT_RADIUS, silent no-op (no count increment, no misleading log); fixes the sparse-hider bug where hint() reported 'highlighted neighbors of one hider' while coloring nothing"
  - "Reveal counter label resets in start_countdown (gui_game.py) BEFORE the countdown — matches the controller's _reveal_count reset in start(); the label was previously initialized once in __init__ and never reset on new game (C8 bug)"
  - "cleanup() + abort_on_error() reset _reveal_count=0 + _hint_count=0 — game over means counters reset (consistency; a fresh GameController already zeroes them in __init__, but an explicit reset on cleanup/abort makes the round boundary unambiguous)"
  - "Headless smoke cleanup assertions extended beyond count-back-to-orig: now also asserts hint orange cleared + no GAME atoms remain — these verify the restore-from-backup path, not just the sentinel-remove path"

patterns-established:
  - "Object-scoped `around` selections: PyMOL's `around` operator matches atoms across ALL loaded objects — append `and <target_obj>` to restrict. Generalizes to any around-based coloring when a backup object exists."
  - "Cleanup via backup.restore is the canonical post-game cleanup (not sentinel-remove + verify_intact) — it restores both atom count AND original colors in one step, which matters when hint() colored real neighbor atoms orange"
  - "Human-verify bug-fix iteration: headless smoke passing does NOT prove GUI correctness for color-persistence bugs (smoke checks count-back-to-orig but not color-clearing); the human-verify checkpoint catches what the smoke structurally cannot (visible color state across rounds)"
  - "Counter-reset regression tests: cleanup() and abort_on_error() now have explicit _reveal_count==0 + _hint_count==0 assertions — counters are part of the game-over contract, not just the start contract"

# Metrics
duration: ~75 min (2 sessions — Task 1 smoke + hint bug on 2026-08-10; human-verify checkpoint + 3-bug-fix iteration on 2026-08-11)
completed: 2026-08-10
---

# Phase 6 Plan 3: Headless Smoke + Human-Verify Checkpoint Summary

**Verified the Phase 6 hint/reveal mechanics at both tiers — 29/29 headless smoke ALL PASSED + human-verify checkpoint APPROVED — and fixed 3 runtime bugs discovered during verification (hint sparse-hider no-op, reveal-counter label not resetting, hint orange color persisting after cleanup via backup-corruption root cause)**

## Performance

- **Duration:** ~75 min (2 sessions)
- **Started:** 2026-08-10T18:52Z (first 06-03 commit: f5a2b00 hint() fix)
- **Completed:** 2026-08-10T18:57Z (last 06-03 commit: c9c2169; checkpoint approved same session)
- **Tasks:** 2/2 (Task 1 auto smoke + Task 2 checkpoint:human-verify APPROVED)
- **Files modified:** 4 (smoke/phase6_smoke.py created; biochemeleon/game.py, biochemeleon/gui_game.py, tests/test_game_controller.py modified)

## Accomplishments
- **Headless smoke (Task 1):** `smoke/phase6_smoke.py` (131 lines, pure `pymol.cmd.*` — NO Qt, modeled on phase4_smoke.py) — 10 sections verifying the full Phase 6 controller mechanics: start (count += 3, registry len 3) → show spheres → HINT (orange neighbors exist, NO GAME atoms orange, all hiders still hidden, _hint_count==1, on_counts_changed(1,0) fired, log fired) → REVEAL-ONE (exactly 1 more found, _reveal_count==1, on_counts_changed(1,1), remaining==2, win NOT fired, revealed hider green) → REVEAL-ALL (all found, _reveal_count==1+N, on_counts_changed, on_remaining_changed(0), win fired, all hider atoms green) → CLEANUP (returned True, count back to orig, hint orange cleared, no GAME atoms remain) → COUNTER RESET (fresh GameController zeroes _reveal_count + _hint_count before AND after start()). Headless run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase6_smoke.py` from the staged Windows path: **29/29 ALL PASSED, exit 0**.
- **Human-verify checkpoint (Task 2) APPROVED:** User confirmed all 4 Phase-6 success criteria in a real Windows PyMOL GUI session — C1 Hint (orange region appears, log fires, "Reveals" label unchanged), C2 Reveal-one (Yes/No confirm dialog above OpenGL window, one hider green on Yes, counter→1, remaining drops), C3 Reveal-all (confirm dialog, all remaining hiders green on Yes, win dialog with time, counter += N), C4 Reveal counter resets per round (new game → "Reveals: 0", Hint no change, Reveal-one → "Reveals: 1") — plus the button-guard check (buttons no-op when no game active or all found).
- **3 runtime bugs fixed during verification** (all Rule 1 bugs, auto-fixed): hint() sparse-hider no-op (f5a2b00), reveal-counter label not resetting on new game (c9c2169), hint orange color persisting after cleanup + root-cause backup-corruption via object-crossing `around` selection (c9c2169). All fixes include regression tests; all WSL gates green after each fix.
- **Test suite:** 187 unit tests pass (18 controller + 90 setup_state + 54 registry + 21 generators + 4 new 06-03 regression tests); 29/29 headless smoke ALL PASSED; all WSL gates green (py_compile, Pitfall-1=0, exec_=1 existing _finish_win only).

## Task Commits

Each task was committed atomically:

1. **Task 1: Write + run headless smoke test** - `e116c9b` (test) — smoke/phase6_smoke.py created (121 lines initially, 27/27 ALL PASSED first run)
2. **Task 1 (deviation): Fix hint() sparse-hider bug** - `f5a2b00` (fix) — biochemeleon/game.py + tests/test_game_controller.py (+1 regression test)
3. **Task 1+2 (bug-fix iteration): Reset reveal label + restore-from-backup cleanup + object-restrict hint selection** - `c9c2169` (fix) — biochemeleon/game.py, biochemeleon/gui_game.py, smoke/phase6_smoke.py (+2 checks), tests/test_game_controller.py (+3 regression tests)
4. **Task 2: checkpoint:human-verify** - (no commit — user approved)

**Plan metadata:** (pending final docs commit)

_Note: Task 1 produced 2 commits (smoke + a Rule-1 bug fix discovered while writing/running the smoke); the human-verify checkpoint iteration produced 1 commit fixing 3 bugs found via GUI testing. Task 2 is a checkpoint, so no code commit._

## Files Created/Modified
- `smoke/phase6_smoke.py` - **Created** (131 lines). Pure `pymol.cmd.*` smoke (NO Qt) modeled on phase4_smoke.py. 10 sections: fetch 1ubq → gen 3 spheres (seed=42) → start → show spheres → register 4 mock callbacks → HINT → REVEAL-ONE → REVEAL-ALL → CLEANUP (intact True + count back to orig + hint orange cleared + no GAME atoms remain) → COUNTER RESET (fresh GameController zeroes counters before + after start). Headless run: 29/29 ALL PASSED via `cmd.exe /c run-conda-pymol.bat -cq`.
- `biochemeleon/game.py` - **Modified**. (1) hint() now filters hidden hiders to candidates with `count_atoms(sele) > 0` before `random.choice`; silent no-op if no candidate has neighbors (no count, no log). (2) Extracted `hint_sele(hider_id)` helper returning `f"(byres ({obj} and id {hider_id} near {HINT_RADIUS})) and not segi GAME and {obj}"` — the trailing `and {obj}` restricts the `around`/`near` selection to the target object (root-cause fix for backup corruption). (3) cleanup() now calls `backup.restore` (delete+create two-step) instead of `mutation.cleanup_hiders` + `backup.verify_intact` + `backup.discard` — restores original atoms + colors in one step. (4) cleanup() + abort_on_error() reset `_reveal_count=0` + `_hint_count=0` (game-over counter consistency). mutation.cleanup_hiders + backup.verify_intact remain as available primitives in their modules.
- `biochemeleon/gui_game.py` - **Modified** (+1 line). `start_countdown` now sets `self._reveal_label.setText("Reveals: 0")` before the countdown — the label was previously initialized once in `__init__` and never reset on new game (C8 bug); now matches the controller's `_reveal_count` reset in `start()`.
- `tests/test_game_controller.py` - **Modified** (+4 regression tests). (1) `test_hint_no_neighbors` — `count_atoms.return_value=0` → hint() no-op: `_hint_count` stays 0, no color call, no counts callback, no log. (2) `test_cleanup_resets_counters` — cleanup() sets `_reveal_count==0` + `_hint_count==0`. (3) `test_abort_on_error_resets_counters` — abort_on_error() sets counters to 0. (4) `test_cleanup_idempotent_when_not_started` — cleanup() on a non-started controller returns True without error.

## Decisions Made
- **cleanup() switched from sentinel-remove to backup.restore** — the original cleanup (mutation.cleanup_hiders + backup.verify_intact + backup.discard) removed GAME atoms but left hint()-colored real neighbor atoms orange. backup.restore (delete+create two-step from the snapshot taken in start() before any mutation/coloring) restores both atom count AND original colors in one step. This makes cleanup correct for the post-hint game state, not just the pre-hint state. mutation.cleanup_hiders + backup.verify_intact remain as available primitives (not deleted — they're still useful for sentinel-only cleanup scenarios).
- **hint() selection is object-scoped via `and <target_obj>`** — PyMOL's `around`/`near` operator matches atoms across ALL loaded objects by default. The `_bchm_backup` object (a coordinate-identical copy created in start()) was being colored orange by hint(), corrupting the backup's colors and defeating the restore-from-backup cleanup. The fix appends `and <target_obj>` to the selection, restricting it to the target object only. Extracted to a `hint_sele(hider_id)` helper for DRY (used by both the candidate-count filter and the `cmd.color` call). This pattern generalizes to any `around`-based coloring when a backup object exists.
- **hint() filters to hiders with neighbors before random.choice** — the original `random.choice(hidden)` could pick a hider in a sparse region (no atoms within HINT_RADIUS=5.0Å), producing no visible hint while still incrementing `_hint_count`, firing callbacks, and logging "Hint: highlighted neighbors of one hider" (a lie). The fix filters `hidden` to candidates with `count_atoms(sele) > 0` first; if no candidate has neighbors, silent no-op (no count, no callback, no log). Discovered via headless smoke: 2 of 3 seed=42 sphere positions in 1ubq had 0 atoms within 5Å (sparse bounding-box regions).
- **Reveal counter label resets in start_countdown, not __init__** — the label was initialized to "Reveals: 0" once in `__init__` but never reset when a new game started, so the second game showed the previous game's final counter value until the first reveal. The fix sets `self._reveal_label.setText("Reveals: 0")` at the top of `start_countdown`, matching the controller's `_reveal_count` reset in `start()`. This is the C8 fix the user reported in the human-verify iteration.
- **cleanup() + abort_on_error() reset counters** — a fresh GameController zeroes `_reveal_count`/`_hint_count` in `__init__`, but an explicit reset on cleanup/abort makes the round boundary unambiguous (game over → counters back to 0, regardless of whether a new controller is constructed). Added regression tests for both paths.
- **Headless smoke cleanup assertions extended** — beyond the original "count back to orig", the smoke now also asserts "hint orange cleared" (no orange atoms remain) and "no GAME atoms remain" — these verify the restore-from-backup path (which restores colors), not just the sentinel-remove path (which only removes GAME atoms). The count-back-to-orig assertion alone would pass even if hint-colored real atoms stayed orange.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] hint() sparse-hider no-op reported a lie**
- **Found during:** Task 1 (Write + run headless smoke test)
- **Issue:** `hint()` picked a random hidden hider via `random.choice(hidden)` — if that hider had no atoms within `HINT_RADIUS=5.0`, the `around`/`near` selection matched nothing, so `cmd.color` colored zero atoms, but hint() STILL incremented `_hint_count`, fired `on_counts_changed`, and logged "Hint: highlighted neighbors of one hider" (a lie — nothing was highlighted). Discovered via headless smoke: 2 of 3 seed=42 sphere positions in 1ubq had 0 atoms within 5Å (sparse bounding-box regions).
- **Fix:** Filter `hidden` to candidates with `count_atoms(sele) > 0` before `random.choice`. If no candidate has neighbors, return without incrementing the count, firing callbacks, or logging (silent no-op — no misleading log).
- **Files modified:** biochemeleon/game.py, tests/test_game_controller.py
- **Verification:** New regression test `test_hint_no_neighbors` (count_atoms.return_value=0 → hint() no-op: _hint_count stays 0, no color call, no counts callback, no log). 184 tests pass (was 183, +1).
- **Committed in:** f5a2b00

**2. [Rule 1 - Bug] Reveal counter label not reset on new game (C8)**
- **Found during:** Task 2 (checkpoint:human-verify — user reported "no reset" across rounds)
- **Issue:** `_reveal_label` was initialized to "Reveals: 0" once in `__init__` but never reset when a new game started. The controller's `_reveal_count` resets in `start()`, but the GUI label did not sync — so the second game showed the previous game's final counter value until the first reveal of the new round.
- **Fix:** `start_countdown` now sets `self._reveal_label.setText("Reveals: 0")` before the countdown, matching the controller's reset.
- **Files modified:** biochemeleon/gui_game.py
- **Verification:** Human-verify C4 (reveal counter resets per round) now passes — user confirmed "Reveals: 0" at the start of a new game.
- **Committed in:** c9c2169

**3. [Rule 1 - Bug] Hint orange color persists after cleanup + root-cause backup corruption**
- **Found during:** Task 2 (checkpoint:human-verify — user reported "hint color keep after reset")
- **Issue:** `cleanup()` originally called `mutation.cleanup_hiders` (removes GAME atoms) + `backup.verify_intact` + `backup.discard` — but did NOT restore the original colors of REAL atoms that `hint()` colored orange. ROOT CAUSE: `hint()`'s `around`/`near` selection crossed object boundaries, coloring atoms in the `_bchm_backup` object too (corrupting the backup's colors — the backup is a coordinate-identical copy, so the `around` operator matched its atoms as well). This meant restore-from-backup would have restored the corrupted colors even if cleanup had used it.
- **Fix:** (a) `cleanup()` now calls `backup.restore` (delete+create two-step) instead of sentinel-remove + verify + discard — the backup (snapshotted in start() before any mutation/coloring) has the original atoms + colors, so restore removes hiders AND restores hint-colored real neighbor atoms to their original colors in one step. (b) The hint selection now ends with `and <target_obj>` to restrict to the target object only (extracted to a `hint_sele(hider_id)` helper for DRY). (c) `cleanup()` + `abort_on_error()` also reset `_reveal_count=0` + `_hint_count=0` (game-over counter consistency).
- **Files modified:** biochemeleon/game.py, smoke/phase6_smoke.py (+2 cleanup checks: hint orange cleared, no GAME atoms remain), tests/test_game_controller.py (+3 regression tests: cleanup resets counters, abort resets counters, cleanup idempotent when not started)
- **Verification:** Headless smoke 29/29 ALL PASSED (added 2 cleanup assertions). Human-verify C3d (hiders cleaned up, no green/orange atoms remain) now passes. 187 tests pass.
- **Committed in:** c9c2169

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs — all discovered during verification: 1 headless smoke, 2 human-verify)
**Impact on plan:** All 3 auto-fixes were necessary for correctness — the plan's smoke + checkpoint design surfaced real runtime bugs that WSL unit tests could not catch (the hint sparse-hider edge case, the GUI label reset, and the object-crossing `around` selection root cause). No scope creep; all fixes are targeted and regression-tested. The cleanup-restore and object-scoped-selection patterns are reusable for Phase 7/11.

## Issues Encountered
- **Headless smoke passing does NOT prove GUI correctness for color-persistence bugs** — the original smoke asserted "count back to orig" after cleanup, which passed even when hint-colored real atoms stayed orange (count only checks atom count, not colors). The human-verify checkpoint caught the color-persistence bug; the smoke was then extended with "hint orange cleared" + "no GAME atoms remain" assertions to verify the restore-from-backup path. This mirrors the Phase 5 05-06/05-08 lesson (headless auto_zoom gap) but for a different root cause (color state, not coord state). Documented in patterns-established for Phase 11.
- **Object-crossing `around` operator** — PyMOL's `around`/`near` operator matches atoms across ALL loaded objects by default. The `_bchm_backup` object (coordinate-identical copy) was silently colored by hint(), corrupting the backup. This is a subtle PyMOL selection semantics pitfall not previously documented in PITFALLS.md — worth adding to the Phase 6/7 domain rules (the `and <target_obj>` guard is the fix).

## Authentication Gates
None — no authentication required for this plan (headless PyMOL via staged Windows path + human-verify in an already-running PyMOL session).

## User Setup Required
None - no external service configuration required. The human-verify checkpoint required a real Windows PyMOL session (launched via `setenv.bat` → `pymol`), which the user already had available.

## Next Phase Readiness
- **Phase 6 is FULLY COMPLETE (all 3 plans done):** 06-01 (controller TDD), 06-02 (GUI buttons), 06-03 (smoke + checkpoint APPROVED). All 4 Phase-6 requirements (GAME-05 hint, GAME-06 reveal-one, GAME-07 reveal-all, DIFF-01 reveal counter) are satisfied at BOTH tiers (WSL unit tests + headless smoke + human GUI verification). Ready for the phase-level 06-VERIFICATION.md / 06-SUMMARY.md handoff (a later planning step, not this plan).
- **No blockers.** All 3 runtime bugs are fixed + regression-tested; the headless smoke is green (29/29); the human-verify is approved (all 4 success criteria + button-guard check). The ROADMAP should mark Phase 6 as complete (3/3 plans).
- **Phase 7 hooks ready:** (1) cleanup() now uses backup.restore (delete+create) — Phase 7's Cleanup button can call the same path; the pattern is established. (2) Counters reset in cleanup()/abort_on_error() — Phase 7 restart reuses the controller's start() reset. (3) The object-scoped `around` selection pattern (hint_sele) generalizes to any future around-based coloring.
- **Phase 10 hook ready:** The `_on_counts_changed(hint_count, reveal_count)` callback signature carries hint_count (stored but not displayed in Phase 6) — Phase 10's win screen can display it directly without changing the set_callbacks contract.
- **Phase 11 note:** The object-crossing `around` pitfall + the headless-smoke-cannot-catch-color-persistence lesson are relevant to Phase 11 (alt-conf cartoon/ribbon — which has its own headless-vs-GUI gap documented in the ROADMAP). The `and <target_obj>` guard should be applied to any around-based selection in Phase 11 code.

---
*Phase: 06-hint-reveal*
*Completed: 2026-08-10*
