---
phase: 07-found-hider-management-restart-cleanup
plan: 03
subsystem: testing
tags: [smoke-test, headless-pymol, human-verify, restart, cleanup, found-hider-management, color-picker, wizard-lifecycle, qcombobox, qcolordialog]

# Dependency graph
requires:
  - phase: 07-found-hider-management-restart-cleanup
    provides: Plan 01 pure helpers (build_found_selection + group_found_by_rep) + GameController._found_color threading; Plan 02 GUI wiring (found-hider dropdown GAME-08, color picker DIFF-04, Restart GAME-10, Cleanup BTN-06, wizard-lifecycle fix in _on_start)
  - phase: 06-hint-reveal
    provides: phase6_smoke.py pattern (pure pymol.cmd.* headless smoke) + AGENTS.md headless-run method (cmd.exe /c run-conda-pymol.bat -cq)
  - phase: 04-core-game-loop
    provides: GameController.start/cleanup/on_pick cmd-coupled paths exercised headlessly; two-tier verification (headless smoke + human-verify checkpoint) idiom
provides:
  - "smoke/phase7_smoke.py — 181-line headless smoke (38 checks, 7 sections) verifying the cmd-coupled Phase-7 mechanics (Restart round-trip, Cleanup restore, found-mgmt hide/show/recolor, color set_color + iterate, _found_color threading), 38/38 ALL PASSED headlessly (exit 0)"
  - "Human-verify checkpoint APPROVED — all 4 Phase-7 success criteria (C1 GAME-08, C2 DIFF-04, C3 GAME-10, C4 BTN-06) + the wizard-lifecycle fix confirmed in a real Windows PyMOL GUI session (1znf)"
  - "Phase 7 COMPLETE — all 3 plans done (07-01 pure helpers + 07-02 GUI wiring + 07-03 two-tier verification)"
affects: [07-found-hider-management-restart-cleanup (phase verification by gsd-verifier), 08-persistence-shareable-puzzles (cleanup/restart state transitions are runtime-verified — .bcm save/load can build on the verified cleanup path), 10-polish-endgame-help (win-screen + post-game debrief build on the verified Restart/Cleanup UI flow)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — smoke uses only pymol.cmd + biochemeleon imports; checkpoint uses the existing Qt GUI
  patterns:
    - "Two-tier verification for Qt+cmd plans — headless smoke (pure pymol.cmd.*, NO Qt) verifies the cmd layer; human-verify checkpoint verifies the Qt/GUI + wizard-lifecycle layer. The smoke header explicitly documents which paths are headless-unreachable (QColorDialog, QComboBox, PickWizard lifecycle, timer reset, log clearing, tab switching) so the smoke's scope is unambiguous. Mirrors Phase 4 04-06 + Phase 6 06-03."
    - "0 runtime bugs at BOTH tiers — the headless smoke passed 38/38 on the first run (no fix(07-03) commits needed) AND the human-verify checkpoint was clean (all 4 success criteria passed, no GUI bug-fix iterations). Plan 01 TDD + Plan 02 GUI wiring were correct on first runtime exercise."

key-files:
  created:
    - smoke/phase7_smoke.py
  modified:
    - .planning/STATE.md  # Task 1 + checkpoint pending (d26c150), then this commit finalizes to Phase 7 COMPLETE

key-decisions:
  - "Two-tier verification split is load-bearing — the headless smoke CAN reach the cmd paths (Restart start→cleanup→start→cleanup idempotent round-trip, Cleanup restore + no GAME atoms, found-mgmt hide/show/recolor via build_found_selection + group_found_by_rep on a real registry, cmd.set_color + cmd.iterate color-index change, _found_color threading at runtime [cyan index 5, NOT default green]) but CANNOT reach the Qt/GUI paths (QColorDialog modal, QComboBox dropdown UI, Restart/Cleanup button clicks, PickWizard activate/deactivate + mouse_selection_mode, timer reset, log clearing, tab switching). The smoke header documents this split explicitly; the human-verify checkpoint closes the Qt/wizard gap."
  - "0 runtime bugs at both tiers — the headless smoke (38/38 first run, exit 0) found no bugs in Plan 02's GUI wiring underlying cmd paths, and the human-verify checkpoint was clean (all 4 success criteria passed, no fixes needed). This is the cleanest Phase verification since Phase 3 (03-15 had 6 runtime auto-fixes; 04-06 had 3 GUI bug-fix iterations; 06-03 had 3 Rule-1 bug fixes). Plan 01's TDD (pure helpers + _found_color threading unit-tested with mocked cmd) + Plan 02's careful GUI wiring (filters by status NOT color, QColorDialog.getColor static method, activated signal, wizard-lifecycle fix folded into _on_start) paid off — first runtime exercise was clean."
  - "Wizard-lifecycle fix CONFIRMED in the real GUI — the CRITICAL risk from 07-RESEARCH.md section 2 (mouse_selection_mode corruption on Start-mid-game AND Restart) passed: left-drag rotates after BOTH Restart AND Cleanup (mouse NOT stuck in atomic-pick mode), and hider clicks succeed after Restart. This was the single biggest Phase-7 risk and it was verified green."
  - "Checkpoint-then-continuation execution pattern — Task 1 (smoke) + STATE update committed by the initial agent; Task 2 (checkpoint:human-verify) paused for user GUI verification; a fresh continuation agent (spawned after the user typed 'approved, all passed. good job!') finalized the plan by creating this SUMMARY + updating STATE + making the docs commit. No re-runs, no re-verification — everything was already verified."

patterns-established:
  - "Pattern: two-tier verification for Qt+cmd plans — headless smoke (pure cmd.*) for the cmd layer + human-verify checkpoint for the Qt/wizard layer. The smoke header documents headless-unreachable paths explicitly so the scope is unambiguous. (Mirrors 04-06 + 06-03.)"
  - "Pattern: checkpoint-then-continuation — when a plan ends on a checkpoint:human-verify, the initial agent commits Task 1 + a STATE update recording 'checkpoint pending', then a fresh continuation agent (spawned after the checkpoint resolves) writes the SUMMARY + finalizes STATE + makes the docs commit. The continuation agent does NOT re-run anything; it trusts the prior agent's committed work + the user's checkpoint approval."

# Metrics
duration: 7min  # active execution across 2 sessions (Task 1 smoke ~3min on 2026-08-11; Task 2 docs ~4min on 2026-08-12); human-verify checkpoint wait spanned ~18h between them
completed: 2026-08-12
---

# Phase 7 Plan 3: Headless Smoke + Human-Verify Checkpoint Summary

**Headless smoke (38/38 ALL PASSED) + human-verify checkpoint APPROVED — Phase 7 runtime-verified at both tiers (found-hider dropdown GAME-08, color picker DIFF-04, Restart GAME-10, Cleanup BTN-06, wizard-lifecycle fix) with 0 runtime bugs at either tier; Phase 7 COMPLETE**

## Performance

- **Duration:** ~7 min active (2 sessions — Task 1 headless smoke ~3 min on 2026-08-11, Task 2 docs ~4 min on 2026-08-12; human-verify checkpoint wait spanned ~18h between)
- **Started:** 2026-08-11T00:35:17Z (Task 1 smoke commit `e51bd0d`)
- **Completed:** 2026-08-11T18:48:00Z (Task 2 docs continuation — this SUMMARY + STATE + final commit)
- **Tasks:** 2 (Task 1 headless smoke; Task 2 checkpoint:human-verify APPROVED)
- **Files modified:** 1 created (smoke) + 2 planning docs (STATE + this SUMMARY)

## Accomplishments
- **smoke/phase7_smoke.py (181 lines, 38 checks, 7 sections)** created and run headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq smoke\phase7_smoke.py` from the staged `tmp/bioCHEMeleon/` path. **38/38 ALL PASSED, exit 0, first run clean.** Pure `pymol.cmd.*` (NO Qt — AGENTS.md headless path); modeled on `smoke/phase6_smoke.py`. Sections: (1) SETUP fetch 1ubq + orig_count; (2) START + SHOW 3 sphere hiders seed=42 + count += 3 + 3 visible; (3) FOUND-MGMT HIDE/SHOW via `build_found_selection` + `group_found_by_rep` on the real registry (cmd.hide → verify hidden; per-rep cmd.show → verify visible); (4) FOUND-MGMT RECOLOR + COLOR via `cmd.set_color('found_highlight', [...])` + `_found_color` assign + `cmd.color` + `cmd.iterate` color-index CHANGED assertion; (5) `_FOUND_COLOR` THREADING — fresh GameController, `_found_color='cyan'`, `_mark_found` → color index 5387→5 [cyan, NOT default green; runtime confirmation of the Plan 01 TDD change that was unit-tested with mocked cmd]; (6) RESTART ROUND-TRIP start→cleanup→start→cleanup (mirrors `_on_restart` at the cmd layer); (7) CLEANUP EXPLICIT PATH start→cleanup (mirrors `_on_cleanup` at the cmd layer; verify_intact True + count back to orig + no GAME atoms); (8) SUMMARY print + `sys.exit(1)` on any fail.
- **Human-verify checkpoint APPROVED** — user typed "approved, all passed. good job!" confirming all 4 Phase-7 success criteria + the wizard-lifecycle fix in a real Windows PyMOL GUI session (1znf):
  - **C1 (GAME-08) Found-hider dropdown:** Hide found → found hiders disappear (hidden hiders stay visible); Show found → found hiders reappear in their ORIGINAL reps; Recolor found → found hiders recolor to the current highlight color; dropdown resets to the "(select)" placeholder after each action (re-selectable).
  - **C2 (DIFF-04) Color picker:** Color… button opens QColorDialog; pick a non-default color → existing found hiders auto-recolor immediately; find a NEW hider → it uses the NEW color (NOT green — `_found_color` threading works for future finds); Cancel → no color change.
  - **C3 (GAME-10) Restart:** object restored (old hiders gone), NEW hiders generated, fresh 3-2-1 countdown, timer resets to 0:00, info log cleared. **CRITICAL wizard lifecycle:** after the Restart countdown, left-drag ROTATES the view (mouse NOT stuck in atomic-pick mode) and hider clicks SUCCEED — the wizard-lifecycle fix in `_on_start` (deactivate old PickWizard before cleanup) works.
  - **C4 (BTN-06) Cleanup:** object restored (atom count matches pre-Start, no GAME atoms), wizard deactivated (left-drag rotates — mouse mode restored), UI reset (Remaining: -, Reveals: 0, 0:00), Start works after Cleanup (controller released via `_controller = None`), Cleanup with no game running is a no-op (the `if self._controller is None: return` guard works).
- **0 runtime bugs at BOTH tiers** — the headless smoke found no bugs in Plan 02's GUI wiring underlying cmd paths (no `fix(07-03)` commits), and the human-verify checkpoint was clean (no GUI bug-fix iterations). This is the cleanest Phase verification since Phase 3.
- **Wizard-lifecycle fix CONFIRMED in the real GUI** — the single biggest Phase-7 risk (research 07-RESEARCH.md section 2: mouse_selection_mode corruption on Start-mid-game AND Restart) passed: left-drag rotates after BOTH Restart AND Cleanup, and hider clicks succeed after Restart.
- **All WSL gates green**: py_compile all modules (biochemeleon + smoke) + 200 tests pass (no regression) + package-wide Pitfall-1=0 + exec_ gate unchanged at 1 (existing `msg.exec_()` in `_finish_win` only — NO new `.exec_()` from QColorDialog, which uses the `getColor()` static method).
- **Phase 7 COMPLETE** — all 3 plans done (07-01 pure helpers + 07-02 GUI wiring + 07-03 two-tier verification). Ready for phase verification by the gsd-verifier.

## Task Commits

1. **Task 1: Headless smoke for Phase 7 (Restart/Cleanup/found-mgmt/color)** - `e51bd0d` (feat) — smoke/phase7_smoke.py, 181 lines, 38 checks, 38/38 ALL PASSED
2. **Task 1 docs: STATE.md updated to record Task 1 complete + Task 2 checkpoint pending** - `d26c150` (docs)
3. **Task 2: checkpoint:human-verify APPROVED** - no commit (checkpoint resolution — user typed "approved, all passed. good job!"; no code/docs change at resolution time)
4. **Plan metadata: 07-03-SUMMARY.md + STATE.md finalized** - `<this commit>` (docs)

_**Note:** Task 2 was a `checkpoint:human-verify` — no code commit at the checkpoint itself. The checkpoint was resolved by user approval in a real Windows PyMOL GUI session (1znf). This docs commit (by the continuation agent spawned after the checkpoint resolved) records the checkpoint resolution + creates this SUMMARY + finalizes STATE.md to Phase 7 COMPLETE. The continuation agent did NOT re-run the smoke or re-verify anything — everything was already verified by the initial agent (Task 1) + the user (Task 2)._

## Files Created/Modified
- `smoke/phase7_smoke.py` (CREATED, 181 lines) — Phase 7 headless smoke. Pure `pymol.cmd.*` (NO Qt). 38 checks across 7 sections: SETUP, START+SHOW, FOUND-MGMT HIDE/SHOW, FOUND-MGMT RECOLOR+COLOR, _FOUND_COLOR THREADING, RESTART ROUND-TRIP, CLEANUP EXPLICIT PATH (+ SUMMARY). Imports `from pymol import cmd` + `from biochemeleon import generators, game, registry, backup` + `from biochemeleon.registry import build_found_selection, group_found_by_rep, HIDER_STATUS_FOUND, HIDER_STATUS_HIDDEN`. Header comment explicitly documents the headless-unreachable paths (QColorDialog, QComboBox, PickWizard lifecycle, timer reset, log clearing, tab switching) deferred to the human-verify checkpoint. Run headlessly 38/38 ALL PASSED, exit 0, first run clean.
- `.planning/STATE.md` (MODIFIED) — Task 1 + checkpoint pending recorded by `d26c150` (initial agent); this commit finalizes it to Phase 7 COMPLETE (checkpoint APPROVED, all 3 plans done, ready for phase verification).
- `.planning/phases/07-found-hider-management-restart-cleanup/07-03-SUMMARY.md` (CREATED — this file)

## Decisions Made
- **Two-tier verification split is load-bearing**: the headless smoke CAN reach the cmd paths (Restart round-trip, Cleanup restore, found-mgmt hide/show/recolor on a real registry, color set_color + iterate, _found_color threading) but CANNOT reach the Qt/GUI paths (QColorDialog modal, QComboBox dropdown, Restart/Cleanup button clicks, PickWizard activate/deactivate + mouse_selection_mode, timer reset, log clearing, tab switching). The smoke header documents this split explicitly; the human-verify checkpoint closes the Qt/wizard gap. (Mirrors the 04-06 + 06-03 idiom.)
- **0 runtime bugs at both tiers** — the headless smoke passed 38/38 on the first run (no `fix(07-03)` commits) AND the human-verify checkpoint was clean (no GUI bug-fix iterations). Plan 01's TDD (pure helpers + _found_color threading unit-tested with mocked cmd) + Plan 02's careful GUI wiring (filters by status NOT color, QColorDialog.getColor static method, `activated` signal, wizard-lifecycle fix folded into `_on_start`) paid off — first runtime exercise was clean. This is the cleanest Phase verification since Phase 3.
- **Wizard-lifecycle fix CONFIRMED in the real GUI** — the CRITICAL risk from 07-RESEARCH.md section 2 (mouse_selection_mode corruption on Start-mid-game AND Restart) passed: left-drag rotates after BOTH Restart AND Cleanup, and hider clicks succeed after Restart. The Plan 02 decision to fold the fix into `_on_start` (fixing BOTH paths with one change) is runtime-validated.
- **Checkpoint-then-continuation execution pattern** — Task 1 (smoke) + STATE update committed by the initial agent; Task 2 (checkpoint:human-verify) paused for user GUI verification; a fresh continuation agent (spawned after the user approved) finalized the plan by creating this SUMMARY + updating STATE + making the docs commit. The continuation agent did NOT re-run anything — it trusted the prior agent's committed work + the user's checkpoint approval. This is the established idiom for plans ending on a `checkpoint:human-verify`.

## Deviations from Plan

None - plan executed exactly as written.

_The plan specified "6+ sections, 25+ checks"; the delivered smoke has 7 sections + 38 checks (exceeds the minimum, not a deviation — more coverage than required). Task 1 passed 38/38 on the first run with 0 runtime bugs (no `fix(07-03)` commits needed). The human-verify checkpoint was APPROVED with no GUI bug-fix iterations._

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Phase 7 COMPLETE** — all 3 plans done (07-01 pure helpers + 07-02 GUI wiring + 07-03 two-tier verification). All 4 Phase-7 success criteria + the wizard-lifecycle fix are runtime-verified at BOTH tiers (headless 38/38 + human-verify APPROVED). Ready for phase verification by the gsd-verifier.
- **No blockers**: all 200 tests pass, all WSL gates green (py_compile + Pitfall-1=0 + exec_=1 unchanged), module dependency direction intact. 0 runtime bugs at either tier.
- **What Phase 8 (Persistence) can build on**: the Cleanup/Restart state transitions are runtime-verified — `_on_cleanup` (restore + wizard deactivate + UI reset + `_controller = None`) and `_on_restart` (wizard deactivate + timer stop + `_on_start` fresh round) work end-to-end in the real GUI. The `.bcm` sidecar save/load can build on the verified cleanup path. `registry.to_dict()`/`from_dict()` (03-07) + `reconstruct_from_sentinels` (03-10, rep=None — Phase 8 sidecar reconciles rep) are the pure-layer foundation already in place.
- **Next step**: gsd-verifier phase verification for Phase 7, then Phase 8 planning (Persistence & Shareable Puzzles).

---
*Phase: 07-found-hider-management-restart-cleanup*
*Completed: 2026-08-12*
