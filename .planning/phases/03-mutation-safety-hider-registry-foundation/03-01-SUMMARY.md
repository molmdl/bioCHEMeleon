---
phase: 03-mutation-safety-hider-registry-foundation
plan: 01
subsystem: data-model
tags: [pure-layer, registry, ordereddict, tdd, hider, slots, pymol-plugin, wsl-testable]

# Dependency graph
requires:
  - phase: 02-setup-tab-configuration-bundled-demos
    provides: setup_state.GAME_REPS (the 5 valid reps) imported by registry.py for rep validation
provides:
  - biochemeleon/registry.py — HiderRecord (data container) + HiderRegistry core CRUD (register/get/all/remove)
  - HIDER_STATUS_HIDDEN / HIDER_STATUS_FOUND constants
  - Pure-layer (stdlib + setup_state only) registry keyed by (object, atom_id) — WSL-unit-testable
  - 33 unit tests pinning the core CRUD behavior (TestHiderRecord + TestHiderRegistryCore)
affects: [03-02 (registry by_rep/counts_by_rep/mark_found), 03-03 (registry reconstruct_from_sentinels/to_dict/from_dict), 03-07/03-08 (mutation.py inserts ids the registry keys on), 03-09/03-10 (game.py orchestrates the registry), Phase 4+ (click handler reads registry), Phase 8 (.bcm sidecar serializes registry)]

# Tech tracking
tech-stack:
  added: []   # stdlib only (collections.OrderedDict); no new third-party deps
  patterns:
    - "Pure-layer registry module: stdlib + intra-package (setup_state) only — NO pymol/Qt import — WSL-unit-testable, mirroring setup_state.py"
    - "OrderedDict-backed registry keyed by (object, atom_id) tuple (Pitfall 4: id is stable across add/remove; index is not)"
    - "HiderRecord uses __slots__ for compactness + AttributeError on typos (no __dict__)"
    - "Int coercion on id at every entry point (register/get/remove) so str/int round-trip transparently"
    - "TDD RED-GREEN cycle for the pure layer; tests stub pymol/pymol.Qt via sys.modules MagicMock (same pattern as test_setup_state.py)"

key-files:
  created:
    - biochemeleon/registry.py   # HiderRecord + HiderRegistry core CRUD (148 lines, pure)
    - tests/test_registry.py      # 33 unit tests (288 lines)
  modified: []

key-decisions:
  - "Registry keyed by (object, id) tuple, not id alone — future-safe for multi-target-object games (matches research Q5 / Pitfall 4 lock)"
  - "HiderRecord uses __slots__=('id','object','rep','status','pos') — compact + surface typos as AttributeError"
  - "OrderedDict (not plain dict) for the registry store — explicit insertion-order contract even on Python 3.6 (where dict order is an impl detail)"
  - "Int coercion on id at register/get/remove — str '1' and int 1 round-trip transparently (defensive for callers passing cmd.identify results)"
  - "to_dict omits 'pos' when None, includes it as a list when set — keeps the Phase 8 .bcm sidecar compact when pos is unused"
  - "register() raises KeyError on duplicate (object,id) (caller bug); remove() is idempotent (returns False on absent, never raises)"
  - "Core CRUD only this plan — by_rep/counts_by_rep/mark_found (03-02), reconstruct_from_sentinels/to_dict/from_dict (03-03) deferred per plan"

patterns-established:
  - "Pattern: pure-layer registry module (no pymol import) — WSL-unit-testable; cmd-coupled insertion/cleanup goes in mutation.py, orchestrator in game.py (strict dependency direction per AGENTS.md)"
  - "Pattern: tests stub pymol/pymol.Qt via sys.modules MagicMock before importing biochemeleon.* (mirrors test_setup_state.py lines 13-15) so __init__.py's `from pymol.Qt import` works in WSL"
  - "Pattern: TDD RED-GREEN for the pure layer — write failing test (ImportError) → implement minimal pure module → all tests pass"

# Metrics
duration: 2 min
completed: 2026-08-05
---

# Phase 3 Plan 01: HiderRegistry Core CRUD Summary

**HiderRecord + HiderRegistry core CRUD (register/get/all/remove) as a pure stdlib+GAME_REPS module keyed by (object, atom_id), WSL-unit-tested with 33 tests**

## Performance

- **Duration:** 2 min (158s)
- **Started:** 2026-08-05T03:53:31Z
- **Completed:** 2026-08-05T03:56:09Z
- **Tasks:** 3 (RED → GREEN → REFACTOR+gates)
- **Files modified:** 2 created (biochemeleon/registry.py, tests/test_registry.py)

## Accomplishments
- Established the **HiderRegistry pure-layer data model** in `biochemeleon/registry.py` — the single source of truth for every inserted hider, keyed by the stable `(object, atom_id)` tuple (Pitfall 4: `id` is stable across add/remove; `index` is not). This is the foundation all later Phase 3 plans and Phases 4-10 build on.
- **33 passing unit tests** (`tests/test_registry.py`) pin the core CRUD behavior across two classes: `TestHiderRecord` (construction, rep validation, key, to_dict, __slots__) and `TestHiderRegistryCore` (register/get/all/remove, duplicate detection, int coercion, insertion order, independent instances).
- Verified the registry is **PURE** (no `from pymol` import — only `collections.OrderedDict` + `setup_state.GAME_REPS`) → WSL-unit-testable, mirroring `setup_state.py`'s convention. All grep gates green (Pitfall-1, Pitfall-11, purity) and existing 90 `test_setup_state` tests unaffected (123 total pass).

## Task Commits

Each task was committed atomically (TDD RED → GREEN; REFACTOR produced no commit — code was already clean):

1. **Task 1 (RED): failing tests for HiderRecord + HiderRegistry core** — `3811370` (test)
2. **Task 2 (GREEN): implement HiderRecord + HiderRegistry core CRUD** — `7236dfc` (feat)
3. **Task 3 (REFACTOR + gates): purity check + full regression** — no commit (no refactor changes; all gates pass)

**Plan metadata:** pending (docs commit after SUMMARY + STATE update)

## Files Created/Modified
- `biochemeleon/registry.py` — HiderRecord (data container with __slots__, rep validation, key(), to_dict()) + HiderRegistry (OrderedDict-backed register/get/all/remove). 148 lines, pure (stdlib + setup_state.GAME_REPS only).
- `tests/test_registry.py` — 33 unit tests (TestHiderRecord + TestHiderRegistryCore). 288 lines. Stubs pymol/pymol.Qt via sys.modules MagicMock (mirrors test_setup_state.py lines 13-15).

## Decisions Made
- **Keyed by `(object, id)` tuple, not `id` alone** — future-safe for multi-target-object games; matches the research Q5 lock and Pitfall 4 (ids are per-object; the tuple is the stable primary key).
- **`__slots__` on HiderRecord** — compact instances + surface attribute typos as `AttributeError` (no `__dict__`); exact 5 fields `('id','object','rep','status','pos')`.
- **`OrderedDict` (not plain dict) for the store** — explicit insertion-order contract even on Python 3.6 (where plain-dict order is an impl detail, not guaranteed by the language spec); `all()` returns records in the order hiders were registered, which the Phase 4 click handler relies on for stable iteration.
- **Int coercion on `id` at every entry point** (register/get/remove) — `str '1'` and `int 1` round-trip transparently; defensive for callers passing `cmd.identify` results or deserialized sidecar strings.
- **`to_dict` omits `pos` when None, includes it as a list when set** — keeps the Phase 8 `.bcm` sidecar compact when pos is unused (Phase 3/4); serializes tuple→list for JSON.
- **`register` raises `KeyError` on duplicate `(object,id)`** (caller bug — never insert the same atom twice); **`remove` is idempotent** (returns `False` on absent, never raises — safe to call twice).
- **Core CRUD only this plan** — `by_rep`/`counts_by_rep`/`mark_found` (03-02), `reconstruct_from_sentinels`/`to_dict`/`from_dict` (03-03) explicitly deferred per the plan's `<action>` ("DO NOT add ... yet — those are plans 03-04, 03-07, 03-10" / research wave table 03-02/03-03).
- **`object` kept as the parameter/field name** despite shadowing the builtin — matches the research sketch EXACTLY and the PyMOL domain term ("object"); changing it would deviate from the plan/research.

## Deviations from Plan

None — plan executed exactly as written. The TDD cycle produced exactly the 2 commits specified (RED test, GREEN feat); the REFACTOR task produced no commit (code was already minimal and clean per GREEN discipline, so the plan's "If no changes, skip commit" applied).

One minor note (not a deviation): the first test run hit a `SyntaxError` on a walrus operator (`:=`, Python 3.8+) I had used in one assertion — python3.6 is 3.6.9 which doesn't support `:=`. Fixed immediately (replaced with a plain `assertEqual(rec.rep, 'spheres')`) before the RED-phase confirmation run. The fix was part of the RED task (writing the tests) and is included in the `3811370` commit; no separate deviation commit needed.

## Issues Encountered

- **Walrus operator (`:=`) syntax error during RED phase** — Python 3.6.9 (the WSL test interpreter) does not support the assignment-expression operator introduced in 3.8. One test assertion used `self.assertEqual(rep := rec.rep, 'spheres')`. Resolved by replacing with `self.assertEqual(rec.rep, 'spheres')` (the walrus binding was unnecessary — the value was already accessible as `rec.rep`). Re-ran: tests failed with the expected `ModuleNotFoundError: No module named 'biochemeleon.registry'` (correct RED state). Lesson reaffirmed: target Python is 3.6.9 — avoid 3.7+ syntax (walrus, f-string `=`, `dict` ordering guarantees, etc.).

## User Setup Required

None — no external service configuration required. The registry is a pure stdlib module with no runtime dependencies beyond what already ships (PyQt5 via `pymol.Qt`, numpy) and the existing pure layer (`setup_state.GAME_REPS`).

## Next Phase Readiness
- **03-01 is complete and self-contained**: `biochemeleon/registry.py` exposes `HiderRecord` + `HiderRegistry` core CRUD (register/get/all/remove) + the `HIDER_STATUS_HIDDEN`/`HIDER_STATUS_FOUND` constants, all pure and WSL-tested. Sibling plans can import these directly.
- **Ready for 03-02** (registry `by_rep`/`counts_by_rep`/`mark_found`): extends the same `HiderRegistry` class in `registry.py`; the `OrderedDict` store and `HiderRecord` shape are in place. No blocker.
- **Ready for 03-03** (registry `reconstruct_from_sentinels`/`to_dict`/`from_dict`): the `to_dict` per-record shape is already implemented; `HiderRegistry.to_dict`/`from_dict` will aggregate it. The `reconstruct_from_sentinels` will need to relax the `GAME_REPS` validation (rep=None after `.pse` reload — research Open Risk 6); flagged for the 03-03 planner.
- **Ready for 03-07/03-08** (mutation.py `insert_hider`/`cleanup_hiders`): the registry's `register(object, id, rep)` signature is the contract `insert_hider` will call after fetching the id via `cmd.identify` (never the `cmd.pseudoatom` return value — Pitfall).
- **No blockers.** The registry is the foundation; everything downstream (game.py orchestration, Phase 4 click handler, Phase 8 .bcm sidecar) reads from it.

### Blockers/Concerns carried forward
- **Parallel Wave 1 execution**: 03-02 (backup.py snapshot+discard) and 03-03 (mutation.py insert_hider) were observed committing concurrently during this plan's execution (commits `07abca1`, `dc61273` in git log). Their files (`backup.py`, `mutation.py`) are disjoint from this plan's files (`registry.py`, `test_registry.py`) — no merge conflict. STATE.md is a shared file updated by each plan; the 03-02 agent already updated it to "03-02 complete (1 of 20)". This SUMMARY updates STATE.md to reflect 03-01 ALSO complete (2 of 20 Phase 3 plans summarized). If 03-03 also completes concurrently, its agent will update STATE.md again — last writer wins; the phase is not "complete" until all 20 plans summarize.
- **Python 3.6.9 syntax constraint** (reaffirmed, not new): avoid walrus `:=`, f-string `=`, positional-only params, etc. The WSL test interpreter is fixed at 3.6.9 per AGENTS.md.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
