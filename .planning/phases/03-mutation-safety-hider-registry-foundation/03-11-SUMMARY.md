---
phase: 03-mutation-safety-hider-registry-foundation
plan: 11
subsystem: orchestration
tags: [game-controller, orchestrator, pymol-plugin, cmd-coupled, snapshot-before-mutation, id-flow, dependency-injection, phase-3]

# Dependency graph
requires:
  - phase: 03-02
    provides: backup.snapshot(target_obj) — the snapshot primitive start() calls FIRST (before any mutation); no-undo safety
  - phase: 03-03
    provides: mutation.insert_hider(object, pos, rep, handle) — returns the stable id (via cmd.identify mode=0) that flows into registry.register
  - phase: 03-06
    provides: mutation.fetch_all_hider_ids(object) — the sentinel-based iterate fn reconstruct_registry injects via lambda (DI)
  - phase: 03-10
    provides: registry.HiderRegistry + reconstruct_from_sentinels(iterate_fn) — the DI rebuild reconstruct_registry delegates to (registry stays pure)
provides:
  - GameController.__init__(target_obj) — sets target_obj, a fresh HiderRegistry, _backup_name=None, _started=False
  - GameController.start(hider_specs) — snapshot BEFORE mutation + fresh registry + insert loop (insert_hider -> register by id) + _started double-start guard (RuntimeError); returns the backup name
  - GameController.reconstruct_registry() — DI rebuild via registry.HiderRegistry().reconstruct_from_sentinels(lambda: mutation.fetch_all_hider_ids(target_obj)); returns the registry
  - The key_link "game.py -> backup+mutation+registry orchestration" (orchestration gate 7 matches >= 3)
  - The id-flow link (insert -> identify -> register)
affects: [03-12 game.py cleanup/abort_on_error (the _started flag + _backup_name this plan sets are the hooks), 03-13/03-14 smoke test (exercises start() + reconstruct_registry), 04-game-loop (Start button calls GameController.start with generator-produced hider_specs), 08-persistence (reconstruct_registry + .bcm sidecar rep reconciliation)]

# Tech tracking
tech-stack:
  added: []   # no new libraries (pymol cmd + stdlib only)
  patterns:
    - "Snapshot-before-mutation ordering: start() calls backup.snapshot() FIRST, before any mutation.insert_hider — PyMOL has no undo, so the backup is mandatory and must precede every destructive op (the no-undo contract lives at the orchestration layer)"
    - "id flows insert -> identify -> register: insert_hider returns the stable id (fetched via cmd.identify mode=0 inside mutation.py, NOT the fragile index), which flows directly into registry.register(object=, id=, rep=) — the (object, id) key link"
    - "_started flag prevents double-start: RuntimeError('game already started; call cleanup() first') if start() is called twice without an intervening cleanup() (planned for 03-12) — guards against duplicate snapshots + duplicate hider inserts"
    - "Dependency injection for reconstruct: reconstruct_registry passes a lambda (mutation.fetch_all_hider_ids) into registry.reconstruct_from_sentinels — registry.py stays pure (no cmd import); game.py is the composition root"
    - "Composition root pattern: game.py imports backup + mutation + registry and wires them in start()/reconstruct_registry(); the dependency direction is strict (game -> backup/mutation/registry, never the reverse) — mirrors setup_state <- demos <- gui_setup"

key-files:
  created: []   # game.py already existed as a 1-line stub from Phase 1
  modified:
    - biochemeleon/game.py

key-decisions:
  - "start() snapshots BEFORE the insert loop (not after, not interleaved) — PyMOL has no undo (AGENTS.md domain rule); the backup must capture the pre-mutation state so a failure path (03-12 abort_on_error -> backup.restore) can recover atom-for-atom"
  - "start() builds a FRESH registry per round (self.registry = HiderRegistry() after snapshot) — a re-start after cleanup gets a clean registry, not stale records from a prior round"
  - "id flows insert -> identify -> register: the aid returned by mutation.insert_hider (fetched via cmd.identify mode=0 inside mutation.py, the stable id NOT the fragile index) is passed directly as id=aid to registry.register — the (object, id) key is the stable primary key (Pitfall 4 lock from 03-01)"
  - "_started flag prevents double-start with RuntimeError('game already started; call cleanup() first') — the cleanup() method is planned for 03-12; without the guard, a double-start would snapshot the already-mutated state (losing the pre-game backup) + insert duplicate hiders"
  - "reconstruct_registry uses dependency injection: passes lambda: mutation.fetch_all_hider_ids(self.target_obj) into registry.HiderRegistry().reconstruct_from_sentinels(...) — registry.py stays pure (no cmd import); game.py is the composition root that injects the cmd-coupled iterate fn (mirrors the 03-10 DI decision)"
  - "Handle format H%03d (H000, H001, ...) — unique per insertion index, used as the throwaway name handle for cmd.identify inside insert_hider; Phase 3 uses a placeholder hider_specs (Phase 4/5 generators produce the real specs)"
  - "game.py imports `from pymol import cmd` even though GameController itself delegates to backup/mutation/registry (no direct cmd call in this plan) — documents the cmd-coupled layer; future methods (03-12 cleanup/abort) + Phase 4 click-loop wiring will use cmd directly"

patterns-established:
  - "Snapshot-before-mutation is the orchestrator's first step: start() calls backup.snapshot() before any mutation.insert_hider — the no-undo safety contract lives at the orchestration layer, not the mutation layer"
  - "game.py is the composition root (thin orchestrator): imports backup + mutation + registry and wires them; never the reverse direction (registry/backup/mutation never import game) — mirrors the setup_state <- demos <- gui_setup architecture"
  - "DI composition for purity: game.py injects the cmd-coupled iterate fn (lambda: mutation.fetch_all_hider_ids) into the pure registry's reconstruct_from_sentinels — the pure layer stays pure, the cmd-coupled layer is the composition root (extends the 03-10 DI pattern to the orchestrator)"

# Metrics
duration: ~2 min
completed: 2026-08-06
---

# Phase 3 Plan 11: GameController Orchestrator Summary

**GameController thin orchestrator wiring backup.snapshot -> mutation.insert_hider -> registry.register in start(), plus DI-based reconstruct_registry via lambda: mutation.fetch_all_hider_ids**

## Performance

- **Duration:** ~2 min (104 sec)
- **Started:** 2026-08-06T05:52:23Z
- **Completed:** 2026-08-06T05:54:07Z
- **Tasks:** 2 (1 implementation + 1 verification-only per plan)
- **Files modified:** 1 (biochemeleon/game.py)

## Accomplishments
- GameController.__init__(target_obj) initializes target_obj, a fresh HiderRegistry, _backup_name=None, _started=False
- start(hider_specs) snapshots BEFORE any mutation (no-undo safety), builds a fresh registry, loops (pos, rep) tuples calling insert_hider -> register by id (id flows insert -> identify -> register), sets _started=True, returns the backup name
- reconstruct_registry() rebuilds the registry from sentinel atoms via dependency injection (lambda: mutation.fetch_all_hider_ids -> registry.reconstruct_from_sentinels), keeping registry.py pure (no cmd import)
- _started flag prevents double-start (RuntimeError "game already started; call cleanup() first") — guards against duplicate snapshots + duplicate hider inserts
- Replaces the 1-line stub; game.py now wires all 3 Phase-3 modules (orchestration gate 7 matches >= 3)
- All WSL gates green: py_compile all + 144 tests (no regression) + Pitfall-1/11 zero + orchestration gate 7 >= 3 + the 4 exact-count greps (backup.snapshot=1, mutation.insert_hider=1, registry.register=1, reconstruct_from_sentinels=1)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement GameController.__init__ + start() + reconstruct_registry()** - `f8606ab` (feat)
2. **Task 2: Run full gate suite (no regression)** - *(no commit — verification-only per plan; game.py was committed in Task 1)*

**Plan metadata:** *(pending — docs commit at end of plan)*

## Files Created/Modified
- `biochemeleon/game.py` — GameController orchestrator (replaces 1-line stub): module docstring + `from pymol import cmd` + `from . import backup, mutation, registry` + `class GameController` with `__init__(target_obj)` / `start(hider_specs)` / `reconstruct_registry()`. start() snapshots before the insert loop, builds a fresh registry, loops hider_specs (list of (pos, rep) tuples) calling insert_hider -> register by id, sets _started=True, returns the backup name. reconstruct_registry() delegates to registry.reconstruct_from_sentinels with an injected lambda. 1 -> 42 lines.

## Decisions Made
- start() snapshots BEFORE the insert loop (not after, not interleaved) — PyMOL has no undo (AGENTS.md domain rule); the backup must capture the pre-mutation state so the 03-12 failure path (abort_on_error -> backup.restore) can recover atom-for-atom.
- start() builds a FRESH registry per round (self.registry = HiderRegistry() after snapshot) — a re-start after cleanup gets a clean registry, not stale records from a prior round.
- id flows insert -> identify -> register: the aid returned by mutation.insert_hider (fetched via cmd.identify mode=0 inside mutation.py, the stable id NOT the fragile index per Pitfall 4) is passed directly as id=aid to registry.register — the (object, id) key is the stable primary key (03-01 lock).
- _started flag prevents double-start with RuntimeError("game already started; call cleanup() first") — the cleanup() method is planned for 03-12; without the guard, a double-start would snapshot the already-mutated state (losing the pre-game backup) + insert duplicate hiders.
- reconstruct_registry uses dependency injection: passes `lambda: mutation.fetch_all_hider_ids(self.target_obj)` into `registry.HiderRegistry().reconstruct_from_sentinels(...)` — registry.py stays pure (no cmd import); game.py is the composition root that injects the cmd-coupled iterate fn (mirrors the 03-10 DI decision).
- Handle format `H%03d` (H000, H001, ...) — unique per insertion index, used as the throwaway name handle for cmd.identify inside insert_hider; Phase 3 uses a placeholder hider_specs (Phase 4/5 generators produce the real specs).
- game.py imports `from pymol import cmd` even though GameController itself delegates to backup/mutation/registry (no direct cmd call in this plan) — documents the cmd-coupled layer; future methods (03-12 cleanup/abort) + Phase 4 click-loop wiring will use cmd directly.

## Deviations from Plan

None - plan executed exactly as written.

The plan's provided docstrings used prose forms ("insert_hider ->", "register.", "snapshot ->", "Rebuild the registry from sentinel atoms") that avoided the dotted-literal false-positives (`backup.snapshot` / `mutation.insert_hider` / `registry.register` / `reconstruct_from_sentinels`) that tripped earlier plans' exact-count greps (03-03/03-06/03-09/03-10 each needed a Rule-3 docstring rewording). No rewording was needed this time — the plan's code passed all 4 exact-count greps + the orchestration gate (7 matches) on the first write.

## Issues Encountered

None.

Note: The Grep tool cross-wired its parallel batch results (the known 03-07/03-10 caution — when called in parallel it returned matches across the whole package rather than the single file specified). Exact per-file counts were re-confirmed via sequential bash `grep -n` / `grep -rnE` per the logged precedent. One self-caught typo in the initial Pitfall-1 bash grep command (`Pwm` instead of `Pmw`) was corrected and re-run; the corrected gate returned ZERO matches (PASS). Neither item affected the code or the outcome — both are verification-methodology hygiene.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- game.py GameController now has __init__/start/reconstruct_registry; the remaining 03-12 plan adds cleanup() + abort_on_error() (the _started flag + _backup_name this plan sets are the hooks 03-12 consumes — cleanup resets _started so a new round can start; abort_on_error uses _backup_name to restore).
- start() uses a placeholder hider_specs (Phase 3 proves the orchestration mechanism with fixed positions + a rep list); Phase 4/5 generators produce the real (pos, rep) specs and pass them into start().
- game.py is cmd-coupled — the runtime behavior (snapshot-before-mutation ordering, insert -> identify -> register id flow, _started double-start guard, DI reconstruct after .pse reload) is WSL-unverifiable (no PyMOL in WSL; py_compile is syntax-only, the 144 unit tests exercise only the pure layer). Deferred to the Phase 3 smoke test (plans 03-13/03-14, run via 03-15 Windows PyMOL checkpoint).
- All WSL gates green (py_compile all + 144 tests + Pitfall-1/11 zero + orchestration gate 7 >= 3 + the 4 exact-count greps). No blocker for the WSL tier; the cmd-coupled runtime is the documented deferral.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
