---
phase: 03-mutation-safety-hider-registry-foundation
plan: 10
subsystem: database
tags: [hider-registry, tdd, unit-tests, pure-layer, pymol-plugin, dependency-injection, pse-reload, sentinel-reconstruction]

# Dependency graph
requires:
  - phase: 03-01
    provides: HiderRegistry core CRUD (register/get/all/remove) + HiderRecord with __init__ rep validation + the (object, id) keying this plan extends with reconstruct_from_sentinels
  - phase: 03-04
    provides: HiderRegistry query layer (by_rep/counts_by_rep/mark_found) — the counts_by_rep zero-fill pattern this plan guards against rep=None + the "docstrings updated in GREEN" precedent
  - phase: 03-06
    provides: mutation.fetch_all_hider_ids returns (model, id) tuples — the exact data shape reconstruct_from_sentinels consumes via dependency injection
  - phase: 03-07
    provides: to_dict/from_dict serialization layer + the "docstrings updated in GREEN not REFACTOR" precedent this plan follows
provides:
  - HiderRegistry.reconstruct_from_sentinels(iterate_hider_keys) — DI-based post-.pse-reload registry rebuild (clears records, loops injected callable, registers rep=None records, returns self fluent)
  - HiderRecord.__init__ rep=None tolerance (validation relaxed: `if rep is not None and rep not in GAME_REPS`)
  - counts_by_rep rep=None guard (skips rep=None records; returned dict has only GAME_REPS keys, never a None key)
  - TestHiderRegistryReconstruct (5 tests) + TestHiderRegistryEdgeCases (3 tests)
  - registry.py functionally complete for Phase 3 (10 HiderRegistry methods)
affects: [08-persistence-bcm-sidecar (rep reconciliation for reloaded games), 03-11/03-12 game.py orchestration (injects the iterate fn), 03-13/03-14 smoke test (Q4 .pse reload section calls reconstruct), 04-game-loop (click handler post-reload)]

# Tech tracking
tech-stack:
  added: []   # stdlib only (OrderedDict + setup_state.GAME_REPS); no new libraries
  patterns:
    - "Dependency injection for purity: reconstruct_from_sentinels takes the iterate callable as a parameter so registry.py stays pure (NO pymol import) — game.py injects lambda: mutation.fetch_all_hider_ids(obj)"
    - "rep=None tolerance scoped to the reconstruction path ONLY: HiderRecord accepts rep=None (validation relaxed) but normal register() always passes a valid rep; the sentinel carries no rep post-.pse-reload"
    - "Guard aggregate queries against None keys: counts_by_rep skips rep=None records so the returned dict has only GAME_REPS keys (documented limitation Phase 8 sidecar reconciles)"
    - "TDD red-green-refactor on the pure data layer (RED fails AttributeError, GREEN implements, REFACTOR gates + 1 gate-fix commit)"

key-files:
  created: []   # no new files; both targets already existed from 03-01
  modified:
    - biochemeleon/registry.py
    - tests/test_registry.py

key-decisions:
  - "Chose option (b) — relax HiderRecord.__init__ to `if rep is not None and rep not in GAME_REPS` (allows rep=None) — over option (a) a validate_rep=True parameter; simpler, single validation point, and register() (the normal path) always passes a valid rep so the relaxation only affects reconstruction"
  - "reconstruct_from_sentinels clears records BEFORE rebuilding (overwrite, NOT append) — a reloaded game rebuilds the registry from scratch; test_reconstruct_clears_existing pins this (3 hiders registered, reconstruct with 1-key fn -> len==1, not 4)"
  - "reconstruct_from_sentinels returns self (fluent) — matches the plan's spec; allows `reg = HiderRegistry().reconstruct_from_sentinels(fn)` chaining"
  - "rep=None records get status=HIDER_STATUS_HIDDEN — a reloaded game treats all sentinel survivors as unfound (the .pse does not persist the in-memory found-status); Phase 8 sidecar recovers found-status too"
  - "counts_by_rep skips rep=None records (documented limitation) — the returned dict has only GAME_REPS keys, never a None key; Phase 8's .bcm sidecar reconciles rep for reloaded games, after which counts_by_rep reflects rebuilt records normally"
  - "id coerced to int in reconstruct (int(aid)) — matches register/get/remove's int coercion; defensive for cmd.identify results (int) and deserialized sidecar strings"
  - "Docstring reworded in REFACTOR (not GREEN) to avoid a from-pymol grep false positive — the reconstruct_from_sentinels docstring originally said 'no from pymol import cmd' which tripped the purity gate; reworded to 'NO pymol import' (mirrors 03-02 precedent + AGENTS.md-warned false-positive pattern); Rule 3 blocking fix"

patterns-established:
  - "Dependency injection keeps the pure layer pure: the cmd-coupled iterate (mutation.fetch_all_hider_ids) is injected as a parameter, not imported — registry.py has zero pymol imports (DI = dependency inversion)"
  - "rep=None is a first-class sentinel-reconstruction value: HiderRecord tolerates it, counts_by_rep skips it, by_rep filters it out naturally (rep=None != any GAME_REP) — the None-rep records are invisible to rep-keyed queries until Phase 8 reconciles"
  - "Documented limitations get a docstring note AND a pinning test: counts_by_rep's rep=None skip is documented in its docstring AND pinned by test_reconstruct_rep_none_then_counts_by_rep"

# Metrics
duration: 3 min
completed: 2026-08-06
---

# Phase 3 Plan 10: reconstruct_from_sentinels + edge cases Summary

**DI-based post-.pse-reload registry rebuild (`reconstruct_from_sentinels`) with rep=None tolerance + counts_by_rep None-guard — registry.py functionally complete for Phase 3 (10 methods)**

## Performance

- **Duration:** 3 min
- **Started:** 2026-08-06T05:32:33Z
- **Completed:** 2026-08-06T05:36:29Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `reconstruct_from_sentinels(iterate_hider_keys)` implemented via dependency injection — clears records, loops the injected callable, registers `HiderRecord(rep=None, status='hidden')` keyed by `(object, int(id))`, returns self (fluent); registry.py stays pure (NO pymol import — the iterate fn is INJECTED by game.py)
- `HiderRecord.__init__` rep validation relaxed to allow `rep=None` (post-.pse-reload reconstruction; the sentinel carries no rep) — `if rep is not None and rep not in GAME_REPS: raise ValueError`. Normal `register()` always passes a valid rep, so the relaxation only affects reconstruction
- `counts_by_rep` guards against `rep=None` records (skips them via `if r.rep is None: continue`) — the returned dict has only `GAME_REPS` keys, never a `None` key (documented limitation Phase 8 `.bcm` sidecar reconciles)
- registry.py is **functionally complete for Phase 3**: 10 HiderRegistry methods (register, get, all, remove, by_rep, counts_by_rep, mark_found, to_dict, from_dict, reconstruct_from_sentinels)
- 8 new tests (5 reconstruct + 3 edge cases) — 54 total registry tests pass; 90 setup_state unaffected (144 total, no regression)

## Task Commits

Each task was committed atomically (TDD red-green-refactor cycle):

1. **RED — write failing tests** — `1a71d61` (test)
   - TestHiderRegistryReconstruct (5) + TestHiderRegistryEdgeCases (3)
   - 6 reconstruct tests fail `AttributeError: 'HiderRegistry' object has no attribute 'reconstruct_from_sentinels'`; 2 reconfirm tests pass (existing 03-01 behavior)
2. **GREEN — implement** — `fbe173f` (feat)
   - reconstruct_from_sentinels (DI) + HiderRecord rep=None tolerance + counts_by_rep None-guard + docstrings
   - All 54 registry tests pass + 90 setup_state pass
3. **REFACTOR — gate fix** — `79dd6b1` (refactor)
   - Reworded reconstruct_from_sentinels docstring to avoid a `from pymol` grep false positive (Rule 3 blocking fix); no behavior change

## Files Created/Modified

- `biochemeleon/registry.py` — HiderRecord.__init__ rep validation relaxed (`if rep is not None and rep not in GAME_REPS`); `reconstruct_from_sentinels` method added (after `from_dict`, under a `# ---- sentinel reconstruction (dependency injection) ----` section); `counts_by_rep` rep=None guard; module + class + HiderRecord docstrings updated (rep=None documented; reconstruct_from_sentinels listed as implemented; registry.py marked functionally complete). 223 -> 267 lines.
- `tests/test_registry.py` — TestHiderRegistryReconstruct (5 tests: fake iterate, clears+rebuilds, empty iterate, returns self, rep=None bypasses validation) + TestHiderRegistryEdgeCases (3 tests: bad rep ValueError reconfirm, dup id KeyError reconfirm, rep=None then counts_by_rep invisible). 451 -> 579 lines.

## Decisions Made

- **Option (b) over (a) for rep=None tolerance** — relaxed `HiderRecord.__init__` to `if rep is not None and rep not in GAME_REPS` rather than adding a `validate_rep=True` parameter. Simpler (single validation point), and `register()` always passes a valid rep so the relaxation only affects the reconstruction path. The plan offered both; (b) is cleaner.
- **reconstruct clears before rebuilding (overwrite, NOT append)** — a reloaded game rebuilds the registry from scratch; pinned by `test_reconstruct_clears_existing` (3 hiders registered, reconstruct with 1-key fn → len==1, not 4).
- **reconstruct returns self (fluent)** — matches the plan's spec; enables `reg = HiderRegistry().reconstruct_from_sentinels(fn)` chaining.
- **rep=None records get status=HIDER_STATUS_HIDDEN** — a reloaded game treats all sentinel survivors as unfound (the `.pse` does not persist the in-memory found-status); Phase 8 sidecar recovers found-status too.
- **counts_by_rep skips rep=None records** — documented limitation; the returned dict has only `GAME_REPS` keys, never a `None` key. Documented in the method docstring AND pinned by `test_reconstruct_rep_none_then_counts_by_rep`.
- **id coerced to int in reconstruct** (`int(aid)`) — matches register/get/remove's int coercion; defensive for cmd.identify results (int) and deserialized sidecar strings.
- **Docstring reworded in REFACTOR (not GREEN)** to avoid a `from pymol` grep false positive — mirrors the 03-02 precedent (backup.py docstring) and the AGENTS.md-warned false-positive pattern (a docstring that said "from PyQt5 import" tripped the gate before).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded reconstruct_from_sentinels docstring to avoid from-pymol grep false positive**

- **Found during:** Task 3 (REFACTOR + gates + registry.py completeness)
- **Issue:** The `reconstruct_from_sentinels` docstring (added in GREEN) contained the literal text `no ``from pymol import cmd`` (dependency inversion)` which tripped the purity gate (`rg -n "from pymol" biochemeleon/registry.py` must return ZERO). The plan's verification requires ZERO; the docstring produced 1 match.
- **Fix:** Reworded to `NO ``pymol`` import (dependency inversion)` — matches the module docstring style (line 7-8: "NO ``pymol`` import") and avoids the `from pymol` substring. No behavior change.
- **Files modified:** biochemeleon/registry.py
- **Verification:** `grep -nE "from pymol" biochemeleon/registry.py` → exit 1 (ZERO matches). Purity gate green.
- **Committed in:** `79dd6b1` (REFACTOR commit)

**2. [Plan-internal note] Completeness grep returns 11 lines, not 10**

- **Found during:** Task 3 (REFACTOR + gates + registry.py completeness)
- **Issue:** The plan's verification expected "10 matches" for `def register|def get|def all|def remove|def by_rep|def counts_by_rep|def mark_found|def to_dict|def from_dict|def reconstruct_from_sentinels`, but the grep returns **11 lines** because `def to_dict` matches BOTH `HiderRecord.to_dict` (line 91, from 03-01) AND `HiderRegistry.to_dict` (line 215, from 03-07).
- **Resolution:** Not a deviation I introduced — `HiderRecord.to_dict` has matched `def to_dict` since 03-01 (pre-existing grep overlap). All **10 HiderRegistry methods** are present (register, get, all, remove, by_rep, counts_by_rep, mark_found, to_dict, from_dict, reconstruct_from_sentinels); the 11th line is the pre-existing `HiderRecord.to_dict`. The plan's "10 matches" referred to the 10 HiderRegistry methods (the completeness criterion), all confirmed present.
- **No code change needed** — this is a documentation/expectation mismatch in the plan's verification, not a code defect.

---

**Total deviations:** 1 auto-fixed (1 Rule 3 blocking — docstring false positive) + 1 plan-internal note (completeness grep count)
**Impact on plan:** The Rule 3 fix was necessary to satisfy the purity verification gate. No scope creep — the docstring rewording preserves the same semantic meaning.

## Issues Encountered

None — the TDD cycle ran cleanly: RED failed with the expected `AttributeError` (no reconstruct_from_sentinels), GREEN passed on first implementation (followed the plan's code snippet verbatim), REFACTOR was a single gate-fix commit.

## User Setup Required

None — no external service configuration required. registry.py is pure (stdlib only), fully WSL-testable.

## Next Phase Readiness

- **registry.py is functionally complete for Phase 3** (10 HiderRegistry methods): register, get, all, remove, by_rep, counts_by_rep, mark_found, to_dict, from_dict, reconstruct_from_sentinels. Pure (NO pymol import — DI confirmed), WSL-testable (54 unit tests + py_compile + purity/Pitfall-1/Pitfall-11 gates all green).
- **Ready for game.py orchestration** (plans 03-11/03-12) — `game.py` will inject `lambda: mutation.fetch_all_hider_ids(obj)` into `registry.reconstruct_from_sentinels(...)` on `.pse` reload, keeping registry.py pure.
- **Phase 8 (.bcm sidecar)** will reconcile `rep` for reloaded games (`rep=None` → valid `GAME_REP`) and recover found-status; the `to_dict`/`from_dict` shape (03-07) is already the sidecar contract.
- **The smoke test** (plans 03-13/03-14, run via 03-15 Windows PyMOL checkpoint) Q4 `.pse`-reload section will call `reconstruct_from_sentinels` to confirm the registry rebuilds from sentinel atoms after a session reload (runtime behavior is WSL-unverifiable — no PyMOL in WSL; py_compile is syntax-only, the 54 unit tests exercise only the pure layer with a fake iterate fn).
- **Documented limitation carried forward**: `counts_by_rep()` shows only `GAME_REPS` keys; `rep=None` records (post-reload) are invisible until Phase 8 sidecar reconciles `rep`.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
