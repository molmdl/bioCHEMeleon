---
phase: 03-mutation-safety-hider-registry-foundation
plan: 07
subsystem: database
tags: [hider-registry, tdd, unit-tests, pure-layer, pymol-plugin, serialization, json, phase8-sidecar]

# Dependency graph
requires:
  - phase: 03-01
    provides: HiderRegistry core CRUD (register/get/all/remove) + HiderRecord with to_dict (the pure data container + record-level to_dict this plan composes into registry-level to_dict)
  - phase: 03-04
    provides: HiderRegistry query layer (by_rep/counts_by_rep/mark_found) + the "docstrings updated in GREEN not REFACTOR" precedent this plan follows
provides:
  - HiderRegistry.to_dict() - registry-level serialization -> {'version':1,'hiders':[record.to_dict() ...]} (insertion order)
  - HiderRegistry.from_dict(d) - @classmethod tolerant reconstruction (missing version/status/pos tolerated; required object/id/rep raise KeyError)
  - TestHiderRegistrySerialize - 6 unit tests covering empty / three-hiders / round-trip / missing-status / missing-version / empty-hiders
affects: [08-persistence-bcm-sidecar, later-phase3-registry-plans, 04-game-loop-session-save]

# Tech tracking
tech-stack:
  added: []   # stdlib only (OrderedDict + setup_state.GAME_REPS); no new libraries
  patterns:
    - "Design the persistence shape in the foundational phase + unit-test round-trip BEFORE the persistence phase needs it (avoids a Phase 8 schema migration)"
    - "Tolerant deserialization: from_dict accepts missing optional keys with sensible defaults (version->1, status->hidden, pos->None) while required keys (object/id/rep) raise KeyError - tolerant on read, strict on the data model"
    - "TDD red-green-refactor on the pure data layer (RED fails with AttributeError, GREEN implements, REFACTOR gates-only)"

key-files:
  created: []   # no new files; both targets already existed from 03-01
  modified:
    - biochemeleon/registry.py
    - tests/test_registry.py

key-decisions:
  - "to_dict shape = {'version':1,'hiders':[record.to_dict() ...]} designed in Phase 3 (not Phase 8) so Phase 8 just writes the dict to a .bcm JSON file and reads it back via from_dict - no schema migration at Phase 8"
  - "from_dict is a @classmethod (not a static method or instance method) - idiomatic for alternate constructors; returns a fresh HiderRegistry"
  - "from_dict is tolerant: missing 'version' accepted (treated as v1, no KeyError); missing 'status' on a hider defaults to HIDER_STATUS_HIDDEN; missing 'pos' stays None; required 'object'/'id'/'rep' raise KeyError (caller bug)"
  - "pos stored as-is from from_dict (a list from JSON) - list/tuple normalization is a Phase 8 boundary concern; Phase 3 only tests round-trip is value-preserving for id/object/rep/status (the four fields the click handler + Game tab rely on)"
  - "Round-trip test asserts id/object/rep/status match (NOT pos) - per the plan's implementation note, pos round-trip is not asserted because from_dict stores the list as-is; the RESEARCH serialization-shape note (lines 240-241) flags this as a known Phase 8 boundary concern"
  - "Docstrings updated in GREEN (not REFACTOR) - follows the 03-04 precedent: a feature is not complete while its docs still say 'deferred'; module/class 'Phase 3 methods' lists now enumerate to_dict/from_dict as implemented, with reconstruct_from_sentinels noted as the remaining later-plan work"
  - "Used HIDER_STATUS_HIDDEN constant (not the literal 'hidden') in from_dict's h.get('status', ...) default - matches the existing module pattern and the plan's GREEN task spec; equivalent but more explicit + refactor-safe"

patterns-established:
  - "Serialization shape is designed in the foundational phase and round-trip unit-tested BEFORE the persistence phase needs it - prevents a schema migration at Phase 8 (the .bcm sidecar writer/reader will be a thin file I/O wrapper over to_dict/from_dict)"
  - "Tolerant deserialization with required-field strictness: optional keys get sensible defaults (version/status/pos), required keys (object/id/rep) raise KeyError - tolerant on read so old/migrated sidecars still load, strict on the data model so bad data surfaces immediately"
  - "classmethod as alternate constructor: from_dict is the idiomatic Python 'named constructor' pattern (cf. dict.fromkeys) - callers read 'HiderRegistry.from_dict(d)' as 'construct a registry from a dict'"

# Metrics
duration: 2 min
completed: 2026-08-05
---

# Phase 3 Plan 7: HiderRegistry Serialization Summary

**TDD'd HiderRegistry `to_dict`/`from_dict` round-trip (6 new tests): the Phase 8 `.bcm` JSON sidecar shape `{'version':1,'hiders':[...]}` designed in Phase 3 with tolerant deserialization (missing version->v1, missing status->hidden, missing pos->None) - no Phase 8 schema migration.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-08-05T20:45:43Z
- **Completed:** 2026-08-05T20:48:01Z
- **Tasks:** 3 (RED, GREEN, REFACTOR+gates)
- **Files modified:** 2

## Accomplishments

- `HiderRegistry.to_dict()`: returns `{'version': 1, 'hiders': [record.to_dict() for each record in insertion order]}` - the Phase 8 `.bcm` JSON sidecar shape, designed NOW so Phase 8 just writes this dict to a file and reads it back via `from_dict`.
- `HiderRegistry.from_dict(d)`: `@classmethod` tolerant reconstruction - missing `'version'` accepted (treated as v1), missing `'status'` on a hider defaults to `HIDER_STATUS_HIDDEN`, missing `'pos'` stays `None`; required `'object'`/`'id'`/`'rep'` raise `KeyError` (caller bug). `id` is coerced to `int` via `register`.
- 6 new unit tests (`TestHiderRegistrySerialize`): empty registry, three hiders (mixed reps + one with pos), round-trip (id/object/rep/status match), missing-status defaults hidden, missing-version no KeyError, empty-hiders -> empty registry. 46 total registry tests (33 core + 7 queries + 6 serialize); 136 total across the pure layer (46 registry + 90 setup_state) - no regression.
- Registry stays **pure** (stdlib + `setup_state.GAME_REPS` only - NO `pymol`, NO `pymol.Qt`); fully WSL-unit-testable. All gates green (py_compile + 136 tests + purity `from pymol`=0 in registry.py + Pitfall-1=0 + Pitfall-11 `.exec_()`=0).
- Module + class docstrings updated in GREEN: the "Phase 3 methods" lists now enumerate `to_dict`/`from_dict` as implemented, with `reconstruct_from_sentinels` noted as the remaining later-plan work (was "A later plan adds `reconstruct_from_sentinels` + `to_dict`/`from_dict`").

## Task Commits

Each TDD phase was committed atomically (Conventional Commits, scope `03-07`):

1. **RED - add failing tests for registry serialization round-trip** - `b04b04b` (test) - 6 tests, all errored with `AttributeError: 'HiderRegistry' object has no attribute 'to_dict'` (methods not yet implemented)
2. **GREEN - implement registry serialization** - `a20f47a` (feat) - `to_dict`/`from_dict` added under a new `# ---- serialization (Phase 8 .bcm sidecar shape) ----` section; all 46 registry tests pass; docstrings updated
3. **REFACTOR + gates** - no commit (gates-only; no cleanup needed - the implementation followed the RESEARCH sketch verbatim and was clean on first pass)

**Plan metadata:** (committed separately) `docs(03-07): complete registry serialization plan`

## Files Created/Modified

- `biochemeleon/registry.py` - added `to_dict` (registry-level, 3 lines) + `from_dict` `@classmethod` (7 lines) under a new `# ---- serialization (Phase 8 .bcm sidecar shape) ----` section (after `mark_found`); updated the module docstring's "Phase 3 scope" list (added "+ serialization (to_dict/from_dict)") and the `HiderRegistry` class docstring's method list (now names `to_dict`/`from_dict` as implemented; `reconstruct_from_sentinels` noted as the remaining later-plan work). 188 -> 228 lines. Still pure (stdlib + `GAME_REPS`).
- `tests/test_registry.py` - added `TestHiderRegistrySerialize` (6 tests): `test_to_dict_empty`, `test_to_dict_three_hiders` (mixed reps + one with pos=[1.0,2.0,3.0]; asserts version, len, keys, pos-as-list), `test_from_dict_round_trip` (register 3, to_dict, from_dict, id/object/rep/status match - NOT pos), `test_from_dict_missing_status_defaults_hidden`, `test_from_dict_missing_version` (no KeyError), `test_from_dict_empty_hiders`. 361 -> 451 lines.

## Decisions Made

- **`to_dict` shape `{'version':1,'hiders':[...]}` designed in Phase 3** - the RESEARCH serialization-shape sketch (lines 228-236) is the contract; Phase 8 (Persistence) will be a thin file I/O wrapper over `to_dict`/`from_dict`. Designing the shape now (and round-trip unit-testing it) avoids a schema migration at Phase 8. The `version: 1` key is the forward-compat hook (Phase 8+ can bump it + branch on it in `from_dict`).
- **`from_dict` is a `@classmethod`** - idiomatic Python "named constructor" pattern (cf. `dict.fromkeys`); callers read `HiderRegistry.from_dict(d)` as "construct a registry from a dict". Returns a fresh `HiderRegistry` (no mutation of `cls` state).
- **`from_dict` is tolerant on optional keys, strict on required keys** - missing `'version'` accepted (treated as v1; no `KeyError`); missing `'status'` on a hider defaults to `HIDER_STATUS_HIDDEN`; missing `'pos'` stays `None`. Required `'object'`/`'id'`/`'rep'` raise `KeyError` (via `register` -> `HiderRecord.__init__`'s `rep in GAME_REPS` ValueError for bad rep, and `h['object']`/`h['id']`/`h['rep']` KeyError for missing required keys). Tolerant on read so old/migrated sidecars still load; strict on the data model so bad data surfaces immediately.
- **`pos` stored as-is from `from_dict` (list from JSON)** - `HiderRecord` accepts either a list or tuple for `pos`; `from_dict` passes `h.get('pos')` through unchanged, so a JSON `[1.0, 2.0, 3.0]` becomes `rec.pos == [1.0, 2.0, 3.0]` (a list), not a tuple. List/tuple normalization is a Phase 8 boundary concern (RESEARCH serialization-shape note, lines 240-241). Phase 3 only tests round-trip is value-preserving for `id`/`object`/`rep`/`status`.
- **Round-trip test asserts `id`/`object`/`rep`/`status` match (NOT `pos`)** - per the plan's `<implementation>` note: "Phase 3 only tests the round-trip is value-preserving." The four asserted fields are the ones the Phase 4 click handler + Game tab rely on. Asserting `pos` round-trip would require the list/tuple normalization that's explicitly deferred to Phase 8.
- **Used `HIDER_STATUS_HIDDEN` constant (not literal `'hidden'`)** in `from_dict`'s `h.get('status', HIDER_STATUS_HIDDEN)` default - matches the plan's GREEN task spec and the existing module pattern (the constant is defined for exactly this use); equivalent to the RESEARCH sketch's literal `'hidden'` but more explicit + refactor-safe (if the constant value ever changes, `from_dict`'s default tracks it).
- **Docstrings updated in GREEN, not REFACTOR** - follows the 03-04 precedent: a feature is not complete while its docs still say "deferred"; the module/class "Phase 3 methods" lists now enumerate `to_dict`/`from_dict` as implemented, with `reconstruct_from_sentinels` noted as the remaining later-plan work. REFACTOR was then gates-only (no commit, per the plan's "commit only if changed").
- **Followed the RESEARCH sketch verbatim** - `to_dict` is a 1-liner composition of `record.to_dict()`; `from_dict` is a `register` loop with `.get` defaults. No cleverness, no optimization - the simplest implementation that passes the tests. Kept as-is; harmless and matches the plan's `<implementation>` block exactly (modulo the `HIDER_STATUS_HIDDEN` constant substitution).

## Deviations from Plan

None - plan executed exactly as written.

Concurrency note (not a deviation - the plan flagged Wave 3 as 3 parallel agents on disjoint files): during this run, sibling agent 03-09 (mutation.py `cleanup_hiders`) was also active - I observed `biochemeleon/mutation.py` as modified (uncommitted) in `git status` at GREEN time. Files are disjoint (registry.py vs mutation.py vs backup.py), so no merge conflict. Per the AGENTS.md/plan concurrency guidance, I staged only my own files for every commit (`tests/test_registry.py` for RED, `biochemeleon/registry.py` for GREEN) - never `git add .` / `git add -A`, and never bare `git commit --amend` (which would absorb a sibling's staged files from the shared index, per the 03-03 lesson). The 03-09 agent's modified `mutation.py` was left untouched in the working tree (and unstaged for my commits).

## Issues Encountered

Tooling observation (not a code issue): the Grep tool cross-wired its results when called as a parallel batch (a single-file `path=registry.py` search for `from pymol` returned "No files found" correctly, but the sibling batch calls' results were mislabeled - the "Found 8 matches" output was actually the `from pymol` pattern re-run on the whole `biochemeleon/` package, not the Pitfall-1 pattern). I re-ran all three gates (purity `from pymol` in registry.py, Pitfall-1, Pitfall-11 `.exec_()`) sequentially via bash `grep -rnE` (rg is not available in this WSL) and confirmed all three return `exit=1` (zero matches = PASS). Same tooling observation as the 03-04 agent.

## User Setup Required

None - no external service configuration required. The registry is a pure in-memory data layer with no runtime/PyMOL dependencies (fully verified at WSL tier).

## Next Phase Readiness

- **Registry serialization layer complete** - `to_dict`/`from_dict` are ready for Phase 8 (Persistence): the `.bcm` sidecar writer will call `registry.to_dict()` + `json.dump`, and the reader will call `json.load` + `HiderRegistry.from_dict(d)`. No schema work needed at Phase 8 (the shape is pinned here).
- **Registry is pure + fully WSL-verified** - 46 unit tests + py_compile + purity + Pitfall gates all green. No runtime/PyMOL behavior to defer (unlike the cmd-coupled backup.py/mutation.py, which still need the Phase 3 smoke test).
- **Remaining Phase 3 registry work** (later plan): `reconstruct_from_sentinels(iterate_fn)` - the DI sentinel rebuild for `.pse` reload (game.py injects `lambda: mutation.fetch_all_hider_ids(obj)` so registry.py stays pure; `rep` is unknown post-reload and is recovered from the Phase 8 `.bcm` sidecar).
- **Phase 8 boundary concerns deferred** (known, tracked in RESEARCH): (1) `pos` list/tuple normalization at the JSON boundary; (2) `version` bump + branching in `from_dict` if the schema ever evolves; (3) `rep=None` tolerance in `reconstruct_from_sentinels` (relax the `GAME_REPS` check there, or add a sentinel-reconstruction path that bypasses validation - RESEARCH note lines 240).
- **No blockers** for this plan. Cross-phase blocker (unchanged): PyMOL Open Source has no undo - every destructive op still needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (established by 03-02; relied on by all later phases).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
