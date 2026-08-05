---
phase: 03-mutation-safety-hider-registry-foundation
plan: 04
subsystem: database
tags: [hider-registry, tdd, unit-tests, pure-layer, pymol-plugin, queries]

# Dependency graph
requires:
  - phase: 03-01
    provides: HiderRegistry core CRUD (register/get/all/remove) + HiderRecord (the pure data container this plan extends with query methods)
provides:
  - HiderRegistry.by_rep(rep) - order-preserving filter, [] for empty (not None)
  - HiderRegistry.counts_by_rep() - {rep: count} for ALL 5 GAME_REPS, zero-filled
  - HiderRegistry.mark_found(object, id) - sets status='found'; KeyError on unregistered
  - TestHiderRegistryQueries - 7 unit tests covering the above
affects: [04-game-loop-start-click-to-find, 06-hint-reveal, later-phase3-registry-plans]

# Tech tracking
tech-stack:
  added: []   # stdlib + setup_state.GAME_REPS only; no new libraries
  patterns:
    - "TDD red-green-refactor on the pure data layer (RED fails with AttributeError, GREEN implements, REFACTOR gates-only)"
    - "Zero-fill pattern: counts_by_rep pre-populates {rep: 0 for rep in GAME_REPS} before counting - stable UI keys regardless of which reps have registered hiders"

key-files:
  created: []   # no new files; both targets already existed from 03-01
  modified:
    - biochemeleon/registry.py
    - tests/test_registry.py

key-decisions:
  - "counts_by_rep zero-fills ALL 5 GAME_REPS so the Game tab can render 'cartoon: 0' even when no cartoon hiders exist (criterion 3: per-rep counts)"
  - "mark_found raises KeyError on unregistered (object, id) - clean error signaling for the Phase 4 click handler; a click on a non-registered atom is a caller bug and should surface immediately, not silently no-op"
  - "int(id) coercion on mark_found matches register/get/remove (str '1' <-> int 1 round-trip; defensive for cmd.identify results + deserialized sidecar strings)"
  - "Docstrings updated in GREEN (not REFACTOR): a feature is not complete while its docs still say 'deferred'; the class/module 'Phase 3 methods' lists now enumerate by_rep/counts_by_rep/mark_found as implemented"

patterns-established:
  - "Query methods are pure filters over the OrderedDict store (no caching, no indexing) - O(n) is fine for Phase 3 hider counts (<= 50 per game); simplicity over premature optimization"
  - "Zero-fill pattern for count dicts: pre-populate the full key set from the canonical source (GAME_REPS) before tallying, so consumers never KeyError on a rep with zero hiders"
  - "Status mutation via direct dict lookup + attribute set: mark_found relies on the (object, int(id)) primary key and lets KeyError propagate as the error signal (no try/except swallowing)"

# Metrics
duration: 4 min
completed: 2026-08-05
---

# Phase 3 Plan 4: HiderRegistry Queries Summary

**TDD'd HiderRegistry query methods `by_rep`/`counts_by_rep`/`mark_found` (7 new tests): per-rep zero-filled counts for the Phase 4 Game tab + `KeyError`-on-unregistered status update for the click-to-find handler.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-05T20:32:59Z
- **Completed:** 2026-08-05T20:37:11Z
- **Tasks:** 3 (RED, GREEN, REFACTOR+gates)
- **Files modified:** 2

## Accomplishments

- `by_rep(rep)`: returns a fresh list of records matching `rep` in insertion order; returns `[]` (not `None`) for reps with no hiders, so the Phase 4 Game tab can iterate without a None-check.
- `counts_by_rep()`: returns `{rep: count}` for **all 5** `GAME_REPS` (`lines`/`sticks`/`spheres`/`cartoon`/`ribbon`), zero-filled - satisfies criterion 3 (per-rep counts) and lets the UI render `"cartoon: 0"` even when no cartoon hiders exist.
- `mark_found(object, id)`: sets the record's `status` to `'found'`; raises `KeyError` on unregistered `(object, id)` - the clean error signal the Phase 4 click handler needs (a click on a non-hider atom is a caller bug). `id` is coerced to `int`, matching `register`/`get`/`remove`.
- 7 new unit tests (`TestHiderRegistryQueries`); 40 total registry tests (33 core + 7 queries); 130 total across the pure layer (40 registry + 90 setup_state) - no regression.
- Registry stays **pure** (stdlib + `setup_state.GAME_REPS` only - NO `pymol`, NO `pymol.Qt`); fully WSL-unit-testable. All gates green (py_compile + 130 tests + purity `from pymol`=0 + Pitfall-1=0 + Pitfall-11 `.exec_()`=0).

## Task Commits

Each TDD phase was committed atomically (Conventional Commits, scope `03-04`):

1. **RED - add failing tests for registry queries** - `998aa85` (test) - 7 tests, all failed with `AttributeError` (methods not yet implemented)
2. **GREEN - implement registry queries** - `97a3743` (feat) - `by_rep`/`counts_by_rep`/`mark_found` added; all 40 registry tests pass; docstrings updated
3. **REFACTOR + gates** - no commit (gates-only; no cleanup needed - the implementation followed the plan's sketch exactly and was clean on first pass)

**Plan metadata:** (committed separately) `docs(03-04): complete registry queries plan`

## Files Created/Modified

- `biochemeleon/registry.py` - added `by_rep`/`counts_by_rep`/`mark_found` (3 methods, ~30 lines) under a new `# ---- queries + status ----` section; updated the module docstring's "Phase 3 scope" list and the `HiderRegistry` class docstring's method list to enumerate the new methods as implemented (was "Later plans add ... (03-02)"). 148 -> 188 lines. Still pure (stdlib + `GAME_REPS`).
- `tests/test_registry.py` - added `TestHiderRegistryQueries` (7 tests) with a `setUp` fixture of 3 hiders across 2 reps (`('1ubq',1,'spheres')`, `('1ubq',2,'sticks')`, `('1ubq',3,'spheres')`); covers `by_rep` matching + empty, `counts_by_rep` all-reps-present + empty-registry, `mark_found` sets-status + only-affects-target + KeyError-on-unregistered. 288 -> 361 lines.

## Decisions Made

- **`counts_by_rep` zero-fills ALL 5 `GAME_REPS`** - pre-populates `{rep: 0 for rep in GAME_REPS}` before tallying, so the returned dict always has every rep as a key. Criterion 3 (per-rep counts) requires the Game tab to show "cartoon: 0" even with no cartoon hiders; a sparse dict would force the UI to `get(rep, 0)` everywhere. The zero-fill centralizes that contract in the registry.
- **`mark_found` raises `KeyError` on unregistered** - the Phase 4 click handler will call `mark_found(object, id)` when the player clicks an atom; if that atom isn't a registered hider, a clean `KeyError` surfaces the caller bug immediately. The alternative (silent no-op / return-False) would hide bugs. `int(id)` coercion matches `register`/`get`/`remove` so `mark_found('1ubq', '1')` finds a record registered with `register('1ubq', 1, ...)`.
- **Docstrings updated in GREEN, not REFACTOR** - a feature is not complete while its docs still say "deferred"; the module/class "Phase 3 methods" lists now name `by_rep`/`counts_by_rep`/`mark_found` as implemented, with `reconstruct_from_sentinels` + `to_dict`/`from_dict` noted as the remaining later-plan work. REFACTOR was then gates-only (no commit, per the plan's "commit only if changed").
- **Followed the plan's implementation sketch verbatim** - `out[r.rep] = out.get(r.rep, 0) + 1` (the `.get` is defensive; `r.rep` is always a key in the zero-filled `out` because `HiderRecord.__init__` validates `rep in GAME_REPS`). Kept as-is per plan; harmless and guards against future `GAME_REPS` extension bugs.

## Deviations from Plan

None - plan executed exactly as written.

Concurrency note (not a deviation - the plan flagged Wave 2 as 3 parallel agents on disjoint files): during this run, sibling agents 03-05 (backup.py) and 03-06 (mutation.py) were also active. I observed `biochemeleon/backup.py` and `biochemeleon/mutation.py` as modified in `git status` at various points, and 03-06 committed `d6ed085 feat(03-06): add mutation.py fetch_all_hider_ids` mid-run. Files are disjoint (registry.py vs backup.py vs mutation.py), so no merge conflict. Per the AGENTS.md/plan concurrency guidance, I staged only my own files for every commit (`tests/test_registry.py` for RED, `biochemeleon/registry.py` for GREEN) - never `git add .` / `git add -A`, and never bare `git commit --amend` (which would absorb a sibling's staged files from the shared index). The 03-05 agent's untracked `03-05-SUMMARY.md` and modified `STATE.md` were left untouched in the working tree.

## Issues Encountered

None.

Tooling observation (not a code issue): the Grep tool cross-wired its results when called as a parallel batch (a single-file `path=registry.py` search returned matches from sibling files). I re-ran the purity + Pitfall-1 + Pitfall-11 gates sequentially via bash `grep -rnE` (rg is not installed in this WSL) and confirmed all three return zero matches.

## User Setup Required

None - no external service configuration required. The registry is a pure in-memory data layer with no runtime/PyMOL dependencies (fully verified at WSL tier).

## Next Phase Readiness

- **Registry query layer complete** - `by_rep` + `counts_by_rep` are ready for the Phase 4 Game tab (remaining-hiders-per-rep display + per-rep counts); `mark_found` is ready for the Phase 4 click-to-find handler.
- **Registry is pure + fully WSL-verified** - 40 unit tests + py_compile + purity + Pitfall gates all green. No runtime/PyMOL behavior to defer (unlike the cmd-coupled backup.py/mutation.py, which still need the Phase 3 smoke test).
- **Remaining Phase 3 registry work** (later plan): `reconstruct_from_sentinels(iterate_fn)` (DI - keeps the registry pure by accepting an injected iterate function), `to_dict`/`from_dict` (Phase 8 `.bcm` sidecar serialization).
- **No blockers** for this plan. Cross-phase blocker (unchanged): PyMOL Open Source has no undo - every destructive op still needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (established by 03-02; relied on by all later phases).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
