---
phase: 02-setup-tab-configuration-bundled-demos
plan: 01
subsystem: testing
tags: [tdd, python, unittest, state-model, pymol-stub, pure-functions]

# Dependency graph
requires:
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: biochemeleon/ package with __init__.py whose module-level `from pymol.Qt import ...` necessitated the pymol stub in tests
provides:
  - "Pure setup state model: DEFAULTS (9-key schema), SETUP_FORMAT, hider_count_cap, randomize_state, validate_state"
  - "GAME_REPS - the 5 in-scope representations (lines, sticks, spheres, cartoon, ribbon); 'surface' excluded"
  - "DEMO_MANIFEST - 6 bundled demo PDB metadata (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3)"
  - "Test infrastructure: tests/ package + pymol.Qt stub-via-sys.modules pattern for WSL python3.6"
affects: [02-setup-tab-configuration-bundled-demos (02-03 demos.py/gui_setup.py import FROM setup_state), 04-mvp-core-loop (game state contract), 09-large-demo-fetch (DEMO_MANIFEST extension)]

# Tech tracking
tech-stack:
  added: []  # stdlib only (random, copy, unittest) - no new dependencies
  patterns:
    - "Pure state layer with NO Qt/pymol.cmd - imported BY GUI modules, never the reverse"
    - "pymol.Qt stub via sys.modules['pymol'] = MagicMock() so tests run in WSL python3.6 without PyMOL"
    - "random.Random(seed) instance for deterministic, testable randomness (NOT global random module)"

key-files:
  created:
    - biochemeleon/setup_state.py
    - tests/test_setup_state.py
    - tests/__init__.py
  modified: []

key-decisions:
  - "GAME_REPS and DEMO_MANIFEST live in setup_state.py (pure layer), NOT demos.py, so randomize_state can reference them without importing demos.py (which carries a cmd dependency)"
  - "Used random.Random(seed) instance (not global random module) for deterministic, testable randomness"
  - "validate_state returns a NEW dict (deepcopy of DEFAULTS + validated overlay) and never mutates its input"
  - "REFACTOR was a no-op - code was clean after GREEN; 169 lines (over the 120 soft target) is acceptable because the excess is documentation that directly aids Plan 02-03's imports"

patterns-established:
  - "Pattern 1: Pure state layer - biochemeleon/setup_state.py has NO Qt/pymol.cmd imports; GUI modules (demos.py, gui_setup.py) import FROM it. This keeps the data contract unit-testable in WSL."
  - "Pattern 2: pymol.Qt test stub - tests stub sys.modules['pymol'] and sys.modules['pymol.Qt'] with MagicMock before importing biochemeleon.*, because __init__.py does `from pymol.Qt import ...` at module level."
  - "Pattern 3: Deterministic randomness - use random.Random(seed) instances, never the global random module, so tests are reproducible."

# Metrics
duration: 2min
completed: 2026-08-04
---

# Phase 2 Plan 1: Setup State Model Summary

**Pure-Python setup state model (DEFAULTS, hider_count_cap, randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST) TDD'd with 48 unit tests runnable in WSL python3.6 without PyMOL**

## Performance

- **Duration:** 2 min
- **Started:** 2026-08-04T15:45:53Z
- **Completed:** 2026-08-04T15:48:40Z
- **Tasks:** 3 (RED, GREEN, REFACTOR-noop)
- **Files modified:** 3 (all created)

## Accomplishments
- TDD'd the pure setup state model: RED (244-line failing test file) -> GREEN (169-line implementation, all 48 tests pass) -> REFACTOR (no-op, code already clean)
- Established the project's first test infrastructure: `tests/` package + the pymol.Qt stub pattern (`sys.modules['pymol'] = MagicMock()`) that lets biochemeleon.* be unit-tested in WSL python3.6 without PyMOL installed
- Delivered the stable state contract that Plan 02-03's `demos.py` and `gui_setup.py` will import from: `DEFAULTS` (9-key schema), `SETUP_FORMAT`, `hider_count_cap` (max(1, min(50, atom_count // 50))), `randomize_state` (seeded-deterministic), `validate_state` (fills defaults, clamps, drops invalid keys, returns a new dict)
- Verified all 6 must-have truths: hider_count_cap boundary cases (0->1, 212->4, 100k->50), deterministic randomize_state, validate_state idempotence + clamping, DEFAULTS 9 keys, GAME_REPS 5 reps (no 'surface'), DEMO_MANIFEST 6 demos with full metadata

## Task Commits

Each TDD phase was committed atomically:

1. **RED: add failing tests for setup state model** - `68cb01b` (test)
2. **GREEN: implement setup state model (pure functions)** - `c892b83` (feat)
3. **REFACTOR: review and clean up** - no-op (no commit; code was clean after GREEN)

**Plan metadata:** pending (docs commit after this SUMMARY)

## Files Created/Modified
- `biochemeleon/setup_state.py` - Pure setup state model: GAME_REPS (5 reps), DEMO_MANIFEST (6 demos), DEFAULTS (9 keys), SETUP_FORMAT, hider_count_cap, randomize_state, validate_state. No pymol/Qt imports.
- `tests/test_setup_state.py` - 48 unit tests across 6 classes (TestHiderCountCap, TestDefaults, TestGameReps, TestDemoManifest, TestRandomizeState, TestValidateState). Stubs pymol.Qt for WSL.
- `tests/__init__.py` - Empty package marker for the tests directory.

## Decisions Made
- **GAME_REPS and DEMO_MANIFEST live in setup_state.py, not demos.py.** Rationale: randomize_state (a pure function) needs to reference them, but demos.py will carry a `pymol.cmd` dependency in Plan 02-03. Putting the manifest in the pure layer keeps randomize_state importable without pulling in cmd. This matches the plan's key_links spec (demos.py does `from .setup_state import GAME_REPS, DEMO_MANIFEST`).
- **random.Random(seed) instance, not global random module.** Rationale: the plan's implementation guidance explicitly calls this out - global state would make tests non-deterministic. A per-call Random instance seeded with the same seed guarantees identical output.
- **validate_state returns a NEW dict (deepcopy + overlay), never mutates input.** Rationale: matches the plan's behavior spec ("Returns a NEW dict (does not mutate input)") and is verified by test_does_not_mutate_input + test_returns_new_dict.
- **REFACTOR was a no-op.** Rationale: the GREEN implementation was already clean (no dead code, no unused imports, all public functions/constants documented, consistent naming). The 169-line count exceeds the 120-line soft guidance, but the excess is documentation (module docstring, `#:` constant comments, function docstrings) that directly aids Plan 02-03's imports - removing it would reduce quality for future phases. Per the plan, no commit when no changes are made.

## Deviations from Plan

None - plan executed exactly as written. The RED, GREEN, and REFACTOR tasks all followed the plan's specifications verbatim. The only judgment call was deeming the REFACTOR a no-op (the plan explicitly allows this: "If no changes needed, this task is no-op").

## Issues Encountered
None. The TDD cycle completed cleanly on the first GREEN pass - all 48 tests passed immediately after implementing setup_state.py per the plan's paste-ready code. No debugging iterations were needed.

`rg` (ripgrep) is not installed in the WSL shell, so the plan's `rg`-based verification commands were substituted with `grep`/the Grep tool (functionally equivalent). This did not affect verification outcomes.

## User Setup Required
None - no external service configuration required. This plan is pure Python with stdlib-only dependencies (random, copy, unittest).

## Next Phase Readiness
- **Ready for Plan 02-02** (Bundle 6 demo PDBs + SOURCES.md): DEMO_MANIFEST is in place with the 6 demo IDs and their `file` fields (`{id}.pdb`); Plan 02-02 downloads the actual PDB files to `biochemeleon/data/demos/` to match.
- **Ready for Plan 02-03** (Populate demos.py + gui_setup.py): the pure state contract is stable. demos.py will `from .setup_state import GAME_REPS, DEMO_MANIFEST`; gui_setup.py will `from .setup_state import DEFAULTS, SETUP_FORMAT, hider_count_cap, randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST` (exactly as specified in the plan's key_links).
- **Ready for Phase 4** (MVP core loop): the setup state schema (DEFAULTS + validate_state) is the contract the Start button will populate and pass to the hider generator.
- **No blockers or concerns.** The pure layer is decoupled from PyMOL, so Plan 02-02 (data download) and 02-03 (GUI/cmd coupling) can proceed independently (Wave-1 parallelism enabled, per the plan's objective).

---
*Phase: 02-setup-tab-configuration-bundled-demos*
*Completed: 2026-08-04*
