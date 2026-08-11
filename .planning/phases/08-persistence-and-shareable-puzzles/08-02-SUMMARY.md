---
phase: 08-persistence-and-shareable-puzzles
plan: 02
subsystem: persistence
tags: [tdd, persistence, bcm-sidecar, json, pure-layer, magic-version, checkpoint-puzzle]

# Dependency graph
requires:
  - phase: 03-game-state-and-mutation-safety
    provides: HiderRegistry.to_dict/from_dict (the registry serialization shape build_bcm_dict embeds under 'registry')
  - phase: 02-setup-tab
    provides: SETUP_FORMAT constant (imported by persistence.py for the setup-embedded-under-'setup' contract)
  - phase: 08-01
    provides: reconcile_with_bcm (the consumer of parse_bcm_dict output — wired in Plan 03's apply_bcm_dict, not this plan)
provides:
  - biochemeleon/persistence.py NEW module (~140 lines, pure — no pymol at module level)
  - build_bcm_dict(controller, setup_state, kind, elapsed=None) -> .bcm dict (SAVE path)
  - parse_bcm_dict(raw) -> validated dict (LOAD path; magic + version guard)
  - BCM_MAGIC = 'BIOCHEMELEON-BCM' + BCM_VERSION = 1 constants
  - 15 unit tests in tests/test_persistence.py (TestBuildBcmDict 8, TestParseBcmDict 5, TestBcmRoundTrip 2)
affects: [08-03, 08-04, 08-05]

# Tech tracking
tech-stack:
  added: []  # stdlib json + time only (already available)
  patterns:
    - "Magic + version guard: parse_bcm_dict refuses magic != BCM_MAGIC or version > BCM_VERSION with a clear ValueError (forward-compat: newer sidecar surfaces 'please update' not silent mis-parse)"
    - "Checkpoint vs puzzle kind split: build_bcm_dict kind='puzzle' FORCES started=False (educator generated + exported, did not play) regardless of controller._started (which is True after gc.start() inserted hiders); kind='checkpoint' reflects the real _started state"
    - "Forward-compat getattr hook: found_color_rgb = getattr(controller, '_found_color_rgb', None) — None in Phase 8 (.pse preserves per-atom colors; exporting.py:424 + importing.py:143); a later phase may populate it via cmd.get_color"
    - "Elapsed fallback: elapsed=None + checkpoint + _start_time set -> time.time() - _start_time; elapsed=None + puzzle -> 0.0 (no fallback for puzzles)"
    - "Transient-field exclusion: build_bcm_dict does NOT serialize _backup_name / _wizard / _on_log / _start_time (session-local / non-JSON-serializable)"
    - "Discrepancy 2 resolution: build/parse live in persistence.py (NOT setup_state.py) to avoid a circular import (apply_bcm_dict needs from .registry, but registry already does from .setup_state)"

key-files:
  created:
    - biochemeleon/persistence.py
    - tests/test_persistence.py
  modified: []

key-decisions:
  - "build_bcm_dict + parse_bcm_dict live in persistence.py (NOT setup_state.py) — putting apply_bcm_dict in setup_state.py would create a circular import (apply_bcm_dict needs from .registry, but registry.py already does from .setup_state import GAME_REPS). persistence.py imports registry + setup_state one-directionally (no cycle)."
  - "persistence.py is PURE (no `pymol` import at module level) — the cmd-coupled file I/O (write_bcmz/read_bcmz/resolve_target) + apply_bcm_dict are Plan 03 and import cmd lazily inside the function body. Same sys.modules stub pattern as test_registry.py makes it WSL-testable."
  - "kind='puzzle' FORCES started=False even when controller._started is True — the educator did not play the puzzle (they generated + exported it); controller._started is True after gc.start() inserted the hiders, but the .bcm must record started=False for a puzzle. This is the load-bearing assertion that catches the discrepancy-soundness blocker."
  - "found_color_rgb is a FORWARD-COMPAT HOOK (None in Phase 8) — the .pse is HIGH confidence to preserve per-atom custom colors, so the RGB safety net is deferred to Phase 8+. build_bcm_dict reads controller._found_color_rgb via getattr if present, else None. Plan 04 does NOT set it."
  - "parse_bcm_dict catches json.JSONDecodeError (a ValueError subclass) and re-raises as ValueError with a 'could not parse .bcm JSON' prefix — callers get a single exception type for all parse failures (bad JSON, wrong magic, unsupported version)."
  - "Docstring reworded from 'NO `from pymol import cmd`' to 'NO `pymol` import' to avoid the from-pymol grep false-positive (mirrors 03-10/08-01 precedent; AGENTS.md-warned docstring-literal pattern)."

patterns-established:
  - "Phase 8 persistence module pattern: persistence.py is the single home for all .bcm concerns (build/parse/apply + .bcmz I/O); pure assembly (this plan) + cmd-coupled I/O (Plan 03) coexist with lazy cmd import keeping the module WSL-importable."
  - "Magic + version guard as the forward-compat contract: BCM_MAGIC refuses non-bioCHEMeleon JSON; BCM_VERSION refuses newer sidecars with a 'please update' message. A future schema bump increments BCM_VERSION and branches in apply_bcm_dict."
  - "MockController test helper pattern: a minimal stand-in class with the 7 attrs build_bcm_dict reads (target_obj, registry, _started, _reveal_count, _hint_count, _found_color, _start_time); no GameController import needed (keeps the test pure-layer)."

# Metrics
duration: 5min
completed: 2026-08-12
---

# Phase 8 Plan 02: build_bcm_dict + parse_bcm_dict Summary

**Pure .bcm sidecar assembly (build_bcm_dict) + validation (parse_bcm_dict) in new persistence.py; magic/version-guarded JSON with checkpoint/puzzle kind split (puzzle forces started=False)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-08-11T22:31:20Z
- **Completed:** 2026-08-11T22:36:30Z
- **Tasks:** 2 (RED + GREEN; no REFACTOR commit — clean on first pass)
- **Files modified:** 2 (1 created source + 1 created test)

## Accomplishments
- NEW `biochemeleon/persistence.py` (~140 lines): `build_bcm_dict` (controller + setup_state → .bcm dict) + `parse_bcm_dict` (raw JSON/bytes → validated dict) + `BCM_MAGIC`/`BCM_VERSION` constants. Pure (no `pymol` import at module level) — WSL-testable.
- `build_bcm_dict` captures the full game-state metadata the `.pse` doesn't carry: registry (per-hider rep + status via `to_dict()`), timer_elapsed, reveal_count, hint_count, found_color, target_object, and the setup dict (verbatim, for Restart-on-imported + puzzle-export configuration visibility).
- `parse_bcm_dict` validates magic == BCM_MAGIC + version <= BCM_VERSION, decodes bytes input, and re-raises JSON parse failures as ValueError — single exception type for all LOAD-path failures.
- Checkpoint vs puzzle kind split: `kind='puzzle'` forces `started=False` (educator did not play) regardless of `controller._started`; `kind='checkpoint'` reflects the real `_started` state (mid-game save). Elapsed falls back to `time.time() - _start_time` for checkpoint, `0.0` for puzzle.
- 15 unit tests across 3 classes (TestBuildBcmDict 8, TestParseBcmDict 5, TestBcmRoundTrip 2) — all green; 167 existing tests unchanged (no regression, 182 total).

## Task Commits

Each task was committed atomically (TDD RED/GREEN/REFACTOR):

1. **Task 1 (RED): add failing tests for build_bcm_dict + parse_bcm_dict** - `69a5edc` (test)
2. **Task 2 (GREEN): create persistence.py with build_bcm_dict + parse_bcm_dict** - `005bf65` (feat)
3. **Task 3 (REFACTOR): no commit** — implementation clean on first pass; full WSL gate suite green (per plan's "commit only if changed")

**Plan metadata:** `pending` (docs: complete plan — committed after SUMMARY + STATE)

## Files Created/Modified
- `biochemeleon/persistence.py` - NEW. Pure-layer .bcm sidecar assembly + parsing. `build_bcm_dict` (SAVE: controller → dict) + `parse_bcm_dict` (LOAD: raw JSON → validated dict) + `BCM_MAGIC`/`BCM_VERSION` constants. No `pymol` import at module level (Plan 03 adds cmd-coupled I/O with lazy import).
- `tests/test_persistence.py` - NEW. 15 tests across 3 classes. sys.modules stub pattern mirrors test_registry.py (pymol + pymol.Qt MagicMock). MockController helper stand-in for GameController (7 attrs build_bcm_dict reads).

## Decisions Made
- **Discrepancy 2 resolved: build/parse live in persistence.py (not setup_state.py).** Putting `apply_bcm_dict` (Plan 03) in `setup_state.py` would create a circular import (`apply_bcm_dict` needs `from .registry import ...`, but `registry.py` already does `from .setup_state import GAME_REPS`). `persistence.py` imports `registry` + `setup_state` one-directionally — no cycle. All `.bcm` concerns in one module.
- **persistence.py is PURE (no `pymol` at module level).** The cmd-coupled file I/O (`write_bcmz`/`read_bcmz`/`resolve_target`) + `apply_bcm_dict` are Plan 03; they import `cmd` lazily inside the function body. Same sys.modules stub pattern as `test_registry.py` makes the pure functions WSL-testable.
- **kind='puzzle' forces started=False.** The educator did not play the puzzle (they generated + exported it); `controller._started` is True after `gc.start()` inserted the hiders, but the .bcm must record `started=False` for a puzzle. Pinned by `test_puzzle_started_true_forces_false` (isolates the forcing so a regression to `bool(controller._started)` is caught).
- **found_color_rgb is a forward-compat hook (None in Phase 8).** The .pse is HIGH confidence to preserve per-atom custom colors (exporting.py:424 + importing.py:143), so the RGB safety net is deferred. `build_bcm_dict` reads `controller._found_color_rgb` via `getattr(..., None)` if present; Plan 04 does NOT set it.
- **parse_bcm_dict re-raises JSONDecodeError as ValueError.** Callers get a single exception type for all LOAD-path failures (bad JSON, wrong magic, unsupported version). `json.JSONDecodeError` is already a `ValueError` subclass; the `try/except ValueError` adds a "could not parse .bcm JSON" prefix for clarity.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed format-string typo in test_parse_then_build_round_trip**
- **Found during:** Task 2 (GREEN — running tests against new persistence.py)
- **Issue:** The RED test's assertion-failure message `"rebuilt %r != parsed %r" % (key,)` passed 1 argument to 2 `%r` placeholders — a `TypeError` would mask the real `AssertionError` if the assertion ever failed against a buggy implementation. The test logic itself was correct (the test passed when the assertion held), but the failure-reporting path was broken.
- **Fix:** Changed to `"rebuilt %r != parsed %r" % (rebuilt[key], parsed[key])` so a failure surfaces a clean `AssertionError` with both values.
- **Files modified:** tests/test_persistence.py
- **Verification:** All 15 tests pass; the format string now has matching argument count.
- **Committed in:** `005bf65` (Task 2 GREEN commit — folded in with the implementation since the test fix was needed for GREEN to pass cleanly).

**2. [Rule 3 - Blocking] Reworded persistence.py docstring to avoid from-pymol grep false-positive**
- **Found during:** Task 2 (GREEN — running the purity gate)
- **Issue:** The module docstring sentence "NO `from pymol import cmd` at module level" contained the literal `from pymol` token, tripping the purity gate `grep -rnE "from pymol" biochemeleon/persistence.py` (returned 1, must be 0). This is the AGENTS.md-warned docstring-literal false-positive pattern (the "from PyQt5 import" precedent).
- **Fix:** Reworded to "NO `pymol` import at module level" (mirrors the 03-10/08-01 precedent where "no `from pymol`" became "no `pymol` import"). No behavior change.
- **Files modified:** biochemeleon/persistence.py
- **Verification:** Purity gate now returns 0; py_compile clean; all tests pass.
- **Committed in:** `005bf65` (Task 2 GREEN commit).

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both auto-fixes necessary for the gate suite to pass green and for test failure-reporting to be correct. No scope creep — the implementation matches the plan's `<implementation>` sketch verbatim; only a test-typo fix + a docstring reword were needed.

## Issues Encountered
None — the implementation followed the plan's `<implementation>` block verbatim. The two deviations (test format-string typo, docstring false-positive) were caught and fixed within the GREEN task before committing.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Ready for 08-03-PLAN.md** (apply_bcm_dict + .bcmz file I/O): `build_bcm_dict` + `parse_bcm_dict` are the pure SAVE/LOAD primitives Plan 03 wires into `apply_bcm_dict` (calls `reconcile_with_bcm` from Plan 01) + `write_bcmz`/`read_bcmz` (cmd-coupled .pse+.bcm archive I/O, lazy `from pymol import cmd` inside function bodies to preserve purity).
- **Ready for 08-04-PLAN.md** (GUI Save/Export buttons): `build_bcm_dict` is the SAVE-path entry point; Plan 04 wires `_on_save` (checkpoint) + `_on_export` (puzzle) to capture elapsed BEFORE the file dialog (research §11 timer pitfall) and call `build_bcm_dict` + Plan 03's `write_bcmz`.
- **Ready for 08-05-PLAN.md** (GUI Load/Import): `parse_bcm_dict` is the LOAD-path entry point; Plan 05 wires `_on_load` to call Plan 03's `read_bcmz` + `parse_bcm_dict` + `apply_bcm_dict`.
- **No blockers.** The Phase 3 `rep=None` limitation is closable via Plan 01's `reconcile_with_bcm` (consumes `parse_bcm_dict` output); this plan provides the pure assembly + validation layer that feeds it. All WSL gates green (py_compile + 182 tests + Pitfall-1=0 + exec_=1 unchanged + persistence purity=0 + build_bcm_dict=1 + parse_bcm_dict=1).

---
*Phase: 08-persistence-and-shareable-puzzles*
*Completed: 2026-08-12*
