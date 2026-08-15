---
phase: 11-alt-conf-cartoon-hider
plan: 02
subsystem: registry (data model)
tags: [alt-conf, registry, serialization, bcm-sidecar, tdd, pure-layer]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry
    provides: HiderRegistry pure data model (HiderRecord __slots__ + register/get/to_dict/from_dict/reconstruct_from_sentinels/reconcile_with_bcm)
  - phase: 08-persistence-shareable-puzzles
    provides: .bcm sidecar round-trip shape (to_dict/from_dict/reconcile_with_bcm) + reconcile_with_bcm rep/status/pos restore
provides:
  - HiderRecord carries 3 alt-conf fields (is_altconf, endpoint_resvs, alt_tag) with backward-compatible defaults
  - HiderRegistry.register accepts the 3 new optional kwargs (existing callers unaffected)
  - HiderRegistry.get_altconf_by_resv(object, resv) — pure O(N) strict-between resv lookup for non-anchor middle-atom scoring
  - .bcm round-trip (to_dict/from_dict/reconcile_with_bcm) carries the 3 fields with list→tuple coercion (NO version bump)
  - _altconf_fields_from_hider_dict @staticmethod helper (shared by from_dict + reconcile)
affects: [11-03 (persistence .bcm alt-conf round-trip tests), 11-05 (scoring on_pick alt/resv gate + get_altconf_by_resv), 11-06 (GUI _prepare_and_start alt-conf 4-tuple wiring)]

# Tech tracking
tech-stack:
  added: []  # pure stdlib only — no new libs
  patterns:
    - "Alt-conf resv-range lookup: get_altconf_by_resv iterates records in insertion order, first-match on rv1 < resv < rv2 (strict between; endpoints excluded)"
    - "List→tuple coercion on .bcm reconcile: endpoint_resvs serializes as a JSON list, coerced back to a tuple on read so rv1 < resv < rv2 works (lists fail < in py3)"
    - "Backward-compat optional fields (NO version bump): to_dict omits the 3 fields when default; from_dict/reconcile read with defaults — Phase 8 sidecars load unchanged"

key-files:
  created: []
  modified:
    - biochemeleon/registry.py  (387 → 515 lines; +3 __slots__ + register kwargs + get_altconf_by_resv + to_dict/from_dict/reconcile extension + _altconf_fields_from_hider_dict helper)
    - tests/test_registry.py   (880 → 1121 lines; +TestAltconfFields 9 tests + TestAltconfSerialization 8 tests + test_slots_defined update)

key-decisions:
  - "endpoint_resvs stored as-is on the record (2-tuple of ints or None; NOT coerced at construction — the caller passes ints from pick_segments); coercion happens only at the .bcm boundary (list→tuple on read)"
  - "alt_tag is any string, not validated (default '' for non-altconf, 'B' for alt-conf); keeps the registry permissive for future altLoc schemes"
  - "get_altconf_by_resv is pure O(N) first-match (no secondary index) — research §6c rejected the multi-id index (shared ids break it; the resv-range + alt approach degrades gracefully and is less state)"
  - "NO .bcm version bump: the 3 fields are ADDITIVE and optional (research §8); a Phase 8 sidecar without them loads as non-altconf; a Phase 11 sidecar loads on Phase 8 code (ignores unknown fields → degraded but playable)"
  - "REFACTOR: extracted _altconf_fields_from_hider_dict @staticmethod shared by from_dict + reconcile (DRYs the list→tuple coercion + default-reading); bool()-coerces is_altconf to normalize truthy ints from hand-edited sidecars"

patterns-established:
  - "Optional-field serialization: omit-on-default in to_dict, read-with-default in from_dict/reconcile — keeps the sidecar compact + backward-compatible across phases"
  - "Tuple-vs-list boundary discipline: registry records store tuples (for < comparisons); .bcm JSON stores lists (JSON has no tuples); reconcile coerces list→tuple on the read path"

# Metrics
duration: 21 min
completed: 2026-08-15
---

# Phase 11 Plan 02: Alt-conf Registry Fields Summary

**HiderRecord extended with is_altconf/endpoint_resvs/alt_tag + get_altconf_by_resv resv-range lookup, carried through the .bcm round-trip with list→tuple coercion and NO version bump (backward-compatible with Phase 8 sidecars)**

## Performance

- **Duration:** 21 min
- **Started:** 2026-08-15T08:28:31Z
- **Completed:** 2026-08-15T08:49:59Z
- **Tasks:** 2 (both TDD: RED + GREEN + optional REFACTOR)
- **Files modified:** 2 (biochemeleon/registry.py, tests/test_registry.py)

## Accomplishments

- **HiderRecord carries 3 alt-conf fields** (`is_altconf`, `endpoint_resvs`, `alt_tag`) added to `__slots__` AFTER the existing 5 (stable ordering), with backward-compatible defaults (`False`, `None`, `''`) so existing Phase 3/4/5 callers passing only `(object, id, rep, ...)` are unaffected.
- **`get_altconf_by_resv(object, resv)`** — pure O(N) first-match lookup returning the first alt-conf record with `endpoint_resvs[0] < resv < endpoint_resvs[1]` (strict between; endpoints excluded — they coincide with the real trace and blend into it). Skips non-altconf records. Enables non-anchor middle-atom scoring (USER REQUIREMENT 3: click ANY middle atom) since alt-conf atoms share ids with originals (research Pitfall 10) and the registry is keyed by `(object, id)` (the anchor only).
- **`.bcm` round-trip preserves the 3 fields with NO version bump** (research §8): `to_dict` emits them only when non-default (compact sidecar; backward-compatible with Phase 8 sidecars); `from_dict`/`reconcile_with_bcm` read them with defaults + list→tuple coercion for `endpoint_resvs` (JSON has no tuples; the record needs a tuple so `rv1 < resv < rv2` works — lists fail `<` in py3). `reconstruct_from_sentinels` defaults the 3 fields (sentinel carries no alt-conf info; the `.bcm` reconciles).
- **registry.py stays PURE** (stdlib + `GAME_REPS` only; NO `pymol` import) — fully WSL-unit-testable.

## Task Commits

Each task was committed atomically (TDD RED → GREEN → REFACTOR):

1. **Task 1 RED: failing tests for alt-conf registry fields** — `a7daf97` (test)
   - TestAltconfFields: 9 new tests + test_slots_defined updated to expect 8 slots
2. **Task 1 GREEN: alt-conf fields + get_altconf_by_resv** — `732bed6` (feat)
   - HiderRecord 3 new __slots__ + __init__ kwargs; register passthrough; get_altconf_by_resv
3. **Task 2 RED: failing tests for alt-conf serialization** — `2827c67` (test)
   - TestAltconfSerialization: 8 tests (to_dict omits/includes, from_dict round-trip/defaults, reconcile restore/list→tuple, reconstruct defaults)
4. **Task 2 GREEN: carry alt-conf through to_dict/from_dict/reconcile** — `3d55ad9` (feat)
   - to_dict optional emit; from_dict + reconcile restore with list→tuple coercion
5. **Task 2 REFACTOR: extract _altconf_fields_from_hider_dict helper** — `cbb6daa` (refactor)
   - DRYs the list→tuple coercion + default-reading shared by from_dict + reconcile; bool()-coerces is_altconf

## Files Created/Modified

- `biochemeleon/registry.py` (387 → 515 lines) — HiderRecord: 3 new `__slots__` + `__init__` kwargs (is_altconf, endpoint_resvs, alt_tag) with defaults; `HiderRegistry.register` passthrough; NEW `get_altconf_by_resv` (pure O(N) strict-between first-match); `to_dict` optional emit; `from_dict` + `reconcile_with_bcm` restore with list→tuple coercion; `_altconf_fields_from_hider_dict` @staticmethod helper. Stays PURE (no `pymol`).
- `tests/test_registry.py` (880 → 1121 lines) — TestAltconfFields (9 tests: record defaults/alt-conf fields, register fields/backward-compat, get_altconf_by_resv hit/endpoint-miss/non-altconf-skipped/first-match/wrong-object) + TestAltconfSerialization (8 tests: to_dict omits/includes, from_dict round-trip/defaults-when-absent, reconstruct defaults, reconcile restore/defaults/list→tuple) + test_slots_defined updated to 8 slots. Total 94 registry tests (77 existing + 17 new).

## Decisions Made

- **endpoint_resvs stored as-is at construction** (no coercion in `__init__`/`register` — the caller passes ints from `pick_segments`); list→tuple coercion happens ONLY at the `.bcm` boundary (read path). Keeps the registry permissive and avoids redundant tuple() calls on the hot insert path.
- **alt_tag not validated** (any string; default `''`). Keeps the registry permissive for future altLoc schemes beyond `'B'`; validation is a caller responsibility (Plan 04/05 set `alt='B'`).
- **get_altconf_by_resv is pure O(N) first-match** (no secondary index) — research §6c explicitly rejected the multi-id index (shared ids break it; the resv-range + alt approach degrades gracefully, is less state, and is robust to shared ids).
- **NO .bcm version bump** — the 3 fields are ADDITIVE and optional (research §8). A Phase 8 sidecar without them loads as non-altconf (degraded but playable); a Phase 11 sidecar loads on Phase 8 code (Phase 8 `from_dict` ignores unknown fields → `is_altconf=False` → anchor-only scoring). Lowest-risk migration.
- **REFACTOR extracted `_altconf_fields_from_hider_dict`** — DRYs the list→tuple coercion + default-reading shared by `from_dict` and `reconcile_with_bcm`. `bool()`-coerces `is_altconf` to normalize truthy ints (e.g. `1`) from hand-edited sidecars to clean bools. No behavior change (255 tests stay green).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded get_altconf_by_resv docstring to avoid a `from pymol` false-positive grep match**
- **Found during:** Task 1 GREEN (registry.py purity gate)
- **Issue:** The plan's docstring guidance used the literal phrase "NO `from pymol` (registry stays pure)" in the `get_altconf_by_resv` docstring; the `grep -nE "from pymol|import pymol" biochemeleon/registry.py` purity gate matched the docstring text (the AGENTS.md-warned false-positive pattern — "we hit a false positive on a docstring that said 'from PyQt5 import'").
- **Fix:** Reworded to "NO `pymol` import (registry stays pure)" — matching the existing module-level docstring convention (line 7-8: "NO `pymol` import, NO `pymol.Qt` import") which avoids both the `from pymol` and `import pymol` literal substrings (the word "import" follows "pymol", not precedes it).
- **Files modified:** biochemeleon/registry.py (get_altconf_by_resv docstring, 1 line)
- **Verification:** `grep -nE "from pymol|import pymol" biochemeleon/registry.py` returns 0 matches (exit 1 = PASS); 86 tests still green.
- **Committed in:** `732bed6` (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — docstring false-positive grep gate, mirroring the 03-02/03-06/03-09/03-10/04-04 precedent)
**Impact on plan:** The auto-fix was necessary to keep the registry purity gate at 0 matches (a hard WSL gate). No scope creep; no behavior change — pure docstring reword.

## Issues Encountered

None — both TDD cycles went RED → GREEN cleanly on the first implementation pass; no debugging iterations needed. The list→tuple coercion was the only subtle point (research §8 flagged it: lists fail `<` in py3), and it was handled correctly in the first GREEN attempt.

## User Setup Required

None — no external service configuration required. This plan extended a pure stdlib data model (registry.py) with WSL-unit-tested fields; no runtime/PyMOL/Qt paths were touched.

## Next Phase Readiness

- **Ready for 11-03** (persistence .bcm alt-conf round-trip tests): `to_dict`/`from_dict`/`reconcile_with_bcm` now carry the 3 fields; persistence.py is a pass-through layer (build_bcm_dict calls `registry.to_dict()`, apply_bcm_dict calls `reconcile_with_bcm`), so 11-03 only needs round-trip tests (no production code change expected).
- **Ready for 11-05** (scoring on_pick alt/resv gate): `get_altconf_by_resv` + `is_altconf`/`endpoint_resvs`/`alt_tag` are in place for `on_pick` to read `alt` + `resv` from `pk1` and gate on `alt == rec.alt_tag AND rv1 < resv < rv2`; `_mark_found` should pass `rec.id` (anchor), not `picked_id` (research §9d).
- **Ready for 11-06** (GUI wiring): `register` accepts the 3 new kwargs; `game.start` will pass `is_altconf=(rep in ('cartoon','ribbon')), endpoint_resvs=(rv1,rv2) if is_altconf else None, alt_tag='B' if is_altconf else ''` (research §9a).
- **No blockers.** The one Rule-3 deviation (docstring false-positive) is resolved. All WSL gates green: 255 tests (94 registry + 90 setup_state + 21 generators + 50 persistence), py_compile all, Pitfall-1=0, exec_ gate unchanged (1 pre-existing child QMessageBox in gui_game.py:303), registry purity=0.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
