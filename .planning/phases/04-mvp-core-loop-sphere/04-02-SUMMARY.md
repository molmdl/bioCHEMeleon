---
phase: 04-mvp-core-loop-sphere
plan: 02
subsystem: ui
tags: [pymol-wizard, click-to-find, do_pick, cmd.identify, mouse_selection_mode, pick-handler, duck-typed-controller]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: mutation.insert_hider returns the stable atom id via cmd.identify(mode=0) — the SAME id do_pick reads via cmd.identify("pk1", mode=1); game.py GameController (duck-typed controller interface — on_pick(aid) added by plan 04-03)
provides:
  - PickWizard(Wizard) — click-to-find pick handler with do_pick/activate/deactivate/get_panel (~52 lines, cmd-coupled)
  - Stable-id routing: do_pick reads cmd.identify("pk1", mode=1) -> controller.on_pick(aid) — the id matches the registry key (object, id)
  - Mouse mode save/restore (mouse_selection_mode=0 atomic on activate; restored on deactivate) + prior-wizard save/restore
affects: [04-mvp-core-loop-sphere (plan 04-04 gui_game._begin_play activates PickWizard; plan 04-05 __init__ wiring; plan 04-06 headless smoke + human-verify checkpoint), 06-hint-reveal (wizard stays active during hints), 07-found-hider-management (wizard lifecycle/deactivate)]

# Tech tracking
tech-stack:
  added: []
  patterns: [Wizard subclass pattern (save/restore mouse_selection_mode + prior wizard), duck-typed controller (no GameController import — avoids circular import), cmd.identify("pk1", mode=1) for stable atom id from pk1 (NEVER cmd.index)]

key-files:
  created: []
  modified: [biochemeleon/wizard.py — populated PickWizard(Wizard) from 1-line stub to 52 lines]

key-decisions:
  - "do_pick uses cmd.identify('pk1', mode=1) for the stable atom id — NEVER cmd.index('pk1') (fragile index; querying.py:1313-1317 warns 'use integral atom identifiers instead of indices')"
  - "Controller is duck-typed (no GameController import) — wizard.py stays standalone, avoids circular import; controller exposes on_pick(aid) at runtime"
  - "Save/restore mouse_selection_mode (mode 0 = atomic) following canonical built-in wizard pattern (measurement.py:96-97) — ensures pk1 is exactly one atom"
  - "Save/restore prior wizard on activate/deactivate (cmd.get_wizard/cmd.set_wizard) — None-safe (set_wizard(None) == set_wizard() both clear)"
  - "Non-target clicks are no-op misses (LOOP-01: no harm) — model != target_object returns early before forwarding to controller"

patterns-established:
  - "Wizard subclass pattern: __init__ saves mouse_selection_mode + sets 0 + deselect; activate saves prior wizard via cmd.get_wizard + cmd.set_wizard(self); deactivate restores both via cmd.set_wizard(saved) + cmd.set(mouse_selection_mode, saved); do_pick reads pk1 via cmd.identify(mode=1) + cmd.unpick + forward to controller.on_pick(aid) + cmd.refresh_wizard"
  - "Duck-typed controller: wizard.py imports ONLY pymol.cmd + pymol.wizard.Wizard (no sibling biochemeleon imports) — standalone, avoids circular import (controller injected at construction time)"

# Metrics
duration: ~9 min
completed: 2026-08-08
---

# Phase 4 Plan 02: PickWizard (Click-to-Find Handler) Summary

**PickWizard(Wizard) routes atom picks to GameController.on_pick(aid) via cmd.identify("pk1", mode=1) — the stable-id click-to-find chain (never cmd.index), with mouse_selection_mode + prior-wizard save/restore**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-08-07T19:53:32Z
- **Completed:** 2026-08-07T20:02:29Z
- **Tasks:** 2
- **Files modified:** 1 (biochemeleon/wizard.py)

## Accomplishments

- PickWizard(Wizard) populated in wizard.py (52 lines) with __init__/do_pick/activate/deactivate/get_panel — the click-to-find handler for the Phase 4 hide-and-seek loop
- do_pick reads the picked atom's stable id from pk1 via cmd.identify("pk1", mode=1) and forwards it to controller.on_pick(aid) — the id matches the registry key (object, id) returned by mutation.insert_hider via cmd.identify(mode=0); NEVER cmd.index (fragile index, querying.py:1313-1317 warns against it)
- Non-target clicks are no-op misses (LOOP-01: no harm) — model != target_object returns early before forwarding to controller
- activate/deactivate save + restore mouse_selection_mode (mode 0 = atomic, ensures pk1 is exactly one atom) and the prior wizard (cmd.get_wizard/cmd.set_wizard — None-safe) — canonical built-in wizard pattern (measurement.py:96-97)
- get_panel provides a Done (quit game) button (right-side viewer menu)
- Controller is duck-typed — wizard.py imports ONLY pymol.cmd + pymol.wizard.Wizard (no sibling imports, avoids circular import; controller injected at construction time)

## Task Commits

Each task was committed atomically. The plan splits implementation (Task 1) from commit+purity-check (Task 2); the commit lands in Task 2:

1. **Task 1: Populate PickWizard in wizard.py** — implementation + WSL gates (no commit; plan defers commit to Task 2)
2. **Task 2: Commit + final purity of dependency direction** — `669cabd` (feat) — wizard.py standalone (no sibling imports; exactly 2 pymol imports)

**Plan metadata:** (pending — final docs commit after SUMMARY + STATE)

## Files Created/Modified

- `biochemeleon/wizard.py` — populated from 1-line stub to 52 lines: PickWizard(Wizard) with __init__ (saves mouse_selection_mode + sets 0 + deselect), do_pick (reads pk1 via cmd.identify mode=1, unpick, non-target miss, forwards to controller.on_pick, refresh_wizard), activate (saves prior wizard + set_wizard(self)), deactivate (restores wizard + mouse_selection_mode), get_panel (title + Done button)

## Decisions Made

- **do_pick uses cmd.identify("pk1", mode=1)** for the stable atom id (returns [(model, id)]) — NEVER cmd.index("pk1") which returns the fragile index (querying.py:1313-1317 docstring explicitly warns "use integral atom identifiers instead of indices"). The id from mode=1 matches the registry key (object, id) from mutation.insert_hider's cmd.identify(mode=0). This is the highest-risk chain in Phase 4 (04-RESEARCH.md §A Q2).
- **Controller is duck-typed** (no `from . import game` or `from biochemeleon import game`) — wizard.py stays standalone, avoids a circular import (game.py would import wizard.py in plan 04-04). The controller exposes on_pick(aid) (plan 04-03) at runtime.
- **Mouse mode 0 (atomic)** — ensures pk1 is exactly one atom (mode 1/residue would put all residue atoms in pk1). Canonical pattern from all built-in wizards (measurement.py:96-97, distance.py:69-70, etc.).
- **Non-target clicks are no-op misses** — model != target_object returns early (LOOP-01: clicking a non-hider does nothing harmful). Simpler than mtsslWizard's object-iteration approach (04-RESEARCH.md §A Q5).
- **No drag disambiguation** — PyMOL internally distinguishes click from drag before calling do_pick (all 8+ built-in wizards have zero drag logic; 04-RESEARCH.md §A Q8).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded docstring to avoid cmd.index("pk1") grep false-positive**

- **Found during:** Task 1 (implementation)
- **Issue:** The plan's literal docstring contained `NEVER cmd.index("pk1")` which would match the plan's OWN verification gate `grep -rnE "cmd\.index\(.pk1" biochemeleon/wizard.py` → 0 (the regex `.` matches the `"` in `cmd.index("pk1")`). The literal docstring would fail its own gate.
- **Fix:** Reworded to "NEVER read pk1 through the index primitive — index is fragile" (avoids the `cmd.index("pk1")` literal while preserving the AGENTS.md warning intent). Kept `cmd.identify("pk1", mode=1)` in the docstring (helps the >=1 identify gate). Mirrors the Phase 3 precedent of rewording docstrings to avoid grep false-positives (03-02/03-03 `from pymol` precedent).
- **Files modified:** biochemeleon/wizard.py (docstring only)
- **Verification:** id-not-index gate `cmd.index(.pk1` = 0 ✓, `cmd.identify(.pk1` = 3 (>=1) ✓
- **Committed in:** 669cabd

**2. [Rule 3 - Blocking] Recovered concurrent-execution git index collision (04-01 agent swept in staged wizard.py)**

- **Found during:** Task 2 (commit step)
- **Issue:** The parallel 04-01 agent's `git commit` (feat(04-01) GREEN, hash 3a4f8db) swept in my staged wizard.py from the shared git index, producing a single commit containing BOTH generators.py (04-01's file, 33 lines) AND wizard.py (my file, 53 lines) under the 04-01 commit message. Root cause: the git index (staging area) is shared across all concurrent agents — any agent's `git commit` commits EVERYTHING in the index, not just what that agent staged. This is the same class of collision documented in STATE.md for Phase 3 (03-03 `git commit --amend` collision).
- **Fix:** Recovered via safe-split pattern (mirrors Phase 3 precedent): `git reset --mixed HEAD~1` (uncommit 3a4f8db, leaves NOTHING staged — safe against further collision, unlike --soft which would leave both files staged) → `git add biochemeleon/generators.py && git commit -C 3a4f8db` (recommit generators.py with 04-01's original message + authorship via -C) → `git add biochemeleon/wizard.py && git commit -m "feat(04-02): ..."` (commit wizard.py as 04-02). All 5 steps chained in ONE bash invocation to minimize the collision window with the concurrent 04-03 agent (which was actively resetting + modifying game.py).
- **Files modified:** none (only git history reorganized — file contents unchanged)
- **Verification:** git log shows 04-01 (2ee7243, generators.py only) and 04-02 (669cabd, wizard.py only) as separate commits; `git show --stat` confirms each commit contains only its own file; all WSL gates re-run green after recovery (py_compile + 144 tests + Pitfall-1=0 + exec_=0 + id-not-index + mouse_selection_mode + sibling-imports=0 + from-pymol=2)
- **Committed in:** 669cabd (the 04-02 commit; the 04-01 recommit is 2ee7243)

---

**Total deviations:** 2 auto-fixed (2 blocking — 1 docstring grep false-positive, 1 concurrent-git collision)
**Impact on plan:** Both auto-fixes necessary for correct commit attribution and passing the plan's own verification gates. No scope creep. The concurrent-collision recovery is a git-hygiene operation (file contents unchanged); the docstring reword preserves the warning intent while satisfying the grep gate.

## Issues Encountered

- **Concurrent-execution git index collision** with the parallel 04-01 agent (resolved via safe-split — see Deviations #2). The shared git index is the root cause. Mitigation: use `git reset --mixed` (leaves nothing staged) instead of `--soft`, and chain all recovery commands in one bash invocation. This is a known hazard when multiple GSD agents execute Wave-1 plans in parallel (file-disjoint but sharing one git repo/index). The 04-03 agent was also concurrently resetting + modifying game.py during the recovery window but its files (game.py, test_game_controller.py) are disjoint and were left untouched.

## User Setup Required

None — no external service configuration required. wizard.py uses only pymol-open-source internals (pymol.cmd + pymol.wizard.Wizard, both shipped with PyMOL 2.5.0).

## Next Phase Readiness

- **Ready for plan 04-04** (gui_game._begin_play): creates `PickWizard(controller, target_obj)` and calls `activate()` after the 3-2-1 countdown; the controller is the GameController from plan 04-03 (duck-typed — on_pick(aid) + target_obj).
- **Ready for plan 04-05** (__init__ wiring): PluginDialog._on_start resolves target → generates sphere specs → GameController.start → switch tab → GameTab.start_countdown → _begin_play → PickWizard.activate.
- **Ready for plan 04-06** (smoke + human-verify): the headless smoke (task 1) simulates a pick via `cmd.select("pk1", f"{obj} and id {hider_id}")` + `wizard.do_pick(0)` to test the pick-chain; the human-verify checkpoint (task 2) does real mouse clicks in Windows PyMOL.
- **The pick-chain is the highest-risk item in Phase 4** (04-RESEARCH.md §A) — verified by py_compile + grep gates here, deferred to plan 04-06 for runtime verification (headless smoke for the pick simulation + human-verify for real mouse clicks). The id-match (do_pick's cmd.identify(mode=1) ↔ mutation's cmd.identify(mode=0)) is the load-bearing contract.
- **No blockers.** wizard.py is standalone (no sibling imports, no circular import risk). The controller is duck-typed — plan 04-03 (running in parallel) adds GameController.on_pick(aid); the wizard just calls `controller.on_pick(aid)` at runtime.

---
*Phase: 04-mvp-core-loop-sphere*
*Completed: 2026-08-08*
