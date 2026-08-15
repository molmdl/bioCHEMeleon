---
phase: 11-alt-conf-cartoon-hider
plan: 03
subsystem: testing (persistence)
tags: [alt-conf, persistence, bcm-sidecar, round-trip, backward-compat, pure-layer, wsl-tests]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry
    provides: HiderRegistry pure data model (HiderRecord + to_dict/from_dict/reconstruct_from_sentinels/reconcile_with_bcm)
  - phase: 08-persistence-shareable-puzzles
    provides: .bcm sidecar round-trip (build_bcm_dict/parse_bcm_dict/apply_bcm_dict + reconcile_with_bcm rep/status/pos restore)
  - phase: 11-02
    provides: HiderRecord 3 alt-conf fields (is_altconf/endpoint_resvs/alt_tag) + to_dict/from_dict/reconcile_with_bcm extension + _altconf_fields_from_hider_dict helper (list->tuple coercion)
provides:
  - 9 WSL round-trip tests proving the 3 alt-conf fields survive build_bcm_dict -> parse_bcm_dict -> apply_bcm_dict with list->tuple coercion (NO version bump)
  - 3 backward-compat tests proving a Phase 8 sidecar (no alt-conf fields) loads on Phase 11 code with defaults (degraded but playable)
  - Confirmation that persistence.py is a PASS-THROUGH layer (NO production code change needed — the 11-02 registry extension handles everything)
affects: [11-07 (cmd-coupled smoke verifying .pse alt survival + .bcmz round-trip at runtime), 11-05 (scoring on_pick — relies on .bcm-restored fields post-reload)]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure stdlib tests (unittest + json)
  patterns:
    - "Pass-through layer verification: persistence.py delegates to registry.to_dict()/reconcile_with_bcm; round-trip tests prove the delegation preserves the 3 alt-conf fields end-to-end with NO production code change"
    - "Backward-compat round-trip testing: hand-construct a Phase 8 sidecar (no new fields) + assert it loads on Phase 11 code with defaults (degraded but playable)"
    - "Round-trip test shape for optional fields: build (assert fields present + version unchanged) -> json.dumps -> parse (assert fields survive) -> apply on sentinel-rebuilt registry (assert fields restored with type coercion + defaults for absent fields)"

key-files:
  created: []
  modified:
    - tests/test_persistence.py  (483 -> 717 lines; +TestBcmAltconfRoundtrip 6 tests + TestBcmAltconfBackwardCompat 3 tests; reuses MockController + _sample_setup() helpers — no duplication)

key-decisions:
  - "persistence.py UNCHANGED — the pass-through hypothesis held exactly as the plan expected: build_bcm_dict calls controller.registry.to_dict() (extended in 11-02 to emit the 3 fields); apply_bcm_dict calls registry.reconcile_with_bcm (extended in 11-02 to restore them with list->tuple coercion). No defensive read was needed."
  - "Backward-compat verified at the pure WSL tier: a hand-constructed Phase 8 sidecar (hider dict with only object/id/rep/status) parses + applies on Phase 11 code, restoring the 3 alt-conf fields to defaults (is_altconf=False, endpoint_resvs=None, alt_tag=''). rep is still restored from the sidecar (non-altconf field). No version bump (research §8)."
  - "test_no_version_bump does NOT duplicate test_parse_unsupported_version_raises (the existing parse-rejects-version>1 test) — it only asserts build_bcm_dict emits version==1 for both alt-conf and non-alt-conf controllers; the parse rejection is confirmed green by the full suite run."

patterns-established:
  - "Optional-field round-trip test pattern: build (assert fields present + version unchanged) -> json.dumps -> parse (assert fields survive + types) -> apply on sentinel-rebuilt registry (assert fields restored with type coercion + defaults for absent fields)"

# Metrics
duration: 4min
completed: 2026-08-15
---

# Phase 11 Plan 03: Alt-conf .bcm Round-trip Tests Summary

**9 WSL round-trip tests proving the 3 alt-conf registry fields survive build_bcm_dict -> parse_bcm_dict -> apply_bcm_dict with list->tuple coercion and NO version bump, plus backward-compat with Phase 8 sidecars (persistence.py unchanged — pass-through confirmed)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-08-15T08:53:32Z
- **Completed:** 2026-08-15T08:56:57Z
- **Tasks:** 2
- **Files modified:** 1 (tests/test_persistence.py)

## Accomplishments

- **6 round-trip tests (`TestBcmAltconfRoundtrip`)** proving `build_bcm_dict -> parse_bcm_dict -> apply_bcm_dict` preserves `is_altconf`/`endpoint_resvs`/`alt_tag` with list->tuple coercion: build carries the 3 fields via the `registry.to_dict()` passthrough (version stays 1, NO schema bump); non-altconf records omit the fields (compact sidecar, backward-compatible with Phase 8); parse does NOT reject the new optional fields; apply restores the 3 fields on a sentinel-rebuilt registry with `endpoint_resvs` coerced list->tuple; a mixed registry (alt-conf + sphere) round-trips with correct defaults for the sphere.
- **3 backward-compat tests (`TestBcmAltconfBackwardCompat`)** proving a Phase 8 sidecar (no alt-conf fields) loads on Phase 11 code with defaults (`is_altconf=False`, `endpoint_resvs=None`, `alt_tag=''`); `reconcile_with_bcm` does NOT raise when the fields are present OR absent (no `KeyError` on `.get` — the helper uses `h.get(...)` with defaults); the no-version-bump contract holds (`build_bcm_dict` emits `version==1` for both alt-conf and non-alt-conf controllers).
- **`persistence.py` UNCHANGED** — the pass-through hypothesis held exactly as the plan expected: `build_bcm_dict` delegates to `controller.registry.to_dict()` (extended in 11-02 to emit the 3 fields); `apply_bcm_dict` delegates to `registry.reconcile_with_bcm` (extended in 11-02 to restore them with list->tuple coercion). No defensive read/tweak was needed. **Closes research Open Risk 3** (`.bcm` round-trip of alt-conf metadata) at the pure WSL tier, ahead of the cmd-coupled smoke (Plan 07) which verifies `.pse` `alt` survival at runtime.
- **Full WSL gate green:** 278 tests (was 269 baseline + 9 new), `py_compile` all modules, Pitfall-1=0, exec_ gate unchanged (only the pre-existing `gui_game.py:303` QMessageBox), `persistence.py` stays PURE (no `pymol` import).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add alt-conf .bcm round-trip tests (build -> parse -> apply)** — `57ef4b3` (test)
   - TestBcmAltconfRoundtrip: 6 tests (build carries/omits, parse accepts, apply restores on sentinel-rebuild/mixed registry, endpoint_resvs list->tuple round-trip)
2. **Task 2: Backward-compat tests (Phase 8 sidecar without alt-conf fields) + full WSL gate** — `b5ca733` (test)
   - TestBcmAltconfBackwardCompat: 3 tests (Phase 8 sidecar loads with defaults, reconcile_with_bcm no-raise present/absent, no version bump)

**Plan metadata:** (to be committed as `docs(11-03)` after this SUMMARY)

## Files Created/Modified

- `tests/test_persistence.py` (483 -> 717 lines) — +`TestBcmAltconfRoundtrip` (6 tests: `test_build_carries_altconf_fields`, `test_build_omits_defaults`, `test_parse_accepts_altconf_fields`, `test_apply_restores_altconf_on_sentinel_rebuild`, `test_apply_restores_altconf_mixed_registry`, `test_altconf_endpoint_resvs_json_list_roundtrip`) + `TestBcmAltconfBackwardCompat` (3 tests: `test_phase8_sidecar_loads_with_defaults`, `test_phase11_sidecar_loads_on_phase8_reconcile`, `test_no_version_bump`). Reuses the existing `MockController` helper (lines 43-60) and `_sample_setup()` (lines 63-71) — NO duplication. No new imports (HiderRegistry already imported). Total persistence tests: 37 (28 existing + 9 new).

## Decisions Made

- **persistence.py UNCHANGED** (pass-through confirmed) — the plan explicitly anticipated this ("If ALL tests pass with persistence.py UNCHANGED (expected — it is pass-through)"). The 11-02 registry extension (`to_dict` optional emit + `reconcile_with_bcm` restore with list->tuple coercion via `_altconf_fields_from_hider_dict`) handles the entire round-trip; persistence.py's `build_bcm_dict` and `apply_bcm_dict` are pure delegation. No defensive read was needed.
- **Backward-compat verified by hand-constructing a Phase 8 sidecar** — rather than relying on a saved fixture, the test builds a `.bcm`-shaped dict with a hider dict containing ONLY `object/id/rep/status` (no alt-conf keys), mimicking a save made BEFORE Phase 11. This precisely isolates the backward-compat contract (research §8: a Phase 8 sidecar loads on Phase 11 code as non-altconf; degraded but playable — only the anchor CA scores until re-saved on Phase 11).
- **`test_no_version_bump` does NOT duplicate `test_parse_unsupported_version_raises`** — per the plan's instruction ("existing test — do not duplicate, just confirm still green"). The new test only asserts `build_bcm_dict` emits `version==1` for both controller types; the parse-rejects-`version>1` contract is confirmed green by the full 278-test suite run.

## Deviations from Plan

None — plan executed exactly as written. `persistence.py` needed no change (the plan explicitly anticipated this: "If ALL tests pass with persistence.py UNCHANGED (expected — it is pass-through), commit only the test file"). Both task test suites went green on the first run; no debugging iterations. The pass-through hypothesis held exactly.

## Issues Encountered

None — both task test suites went green on the first run; no debugging iterations. The list->tuple coercion (the one subtle point — JSON has no tuples; lists fail `<` in py3) was already handled correctly by the 11-02 `_altconf_fields_from_hider_dict` helper, and `test_altconf_endpoint_resvs_json_list_roundtrip` confirms it end-to-end (parsed `endpoint_resvs` is a `list`; after `apply_bcm_dict` the record's `endpoint_resvs` is a `tuple`).

## User Setup Required

None — pure stdlib test additions (unittest + json); no runtime/PyMOL/Qt paths were touched. This plan extended the WSL-runnable pure test suite; `persistence.py` is unchanged and stays PURE.

## Next Phase Readiness

- **Ready for 11-07** (cmd-coupled smoke): the `.bcm` round-trip of alt-conf metadata is proven at the pure WSL tier (Open Risk 3 for `.bcm` closed). 11-07 verifies `.pse` `alt` survival + the full `.bcmz` round-trip at runtime (Open Risk 2 for `.pse` `alt` survival remains — the pure tier cannot verify `.pse` serialization).
- **Ready for 11-05** (scoring `on_pick`): the `.bcm`-restored fields (`is_altconf`/`endpoint_resvs`/`alt_tag`) are confirmed to survive reload via `reconcile_with_bcm` -> `on_pick`'s `get_altconf_by_resv` + `alt`/`resv` gate will work post-reload (the `endpoint_resvs` tuple is restored, so `rv1 < resv < rv2` works).
- **No blockers.** `persistence.py` is PURE and unchanged; all WSL gates green (278 tests across the 4 pure modules: 112 setup_state + 94 registry + 35 generators + 37 persistence — the latter being 28 existing + 9 new); `py_compile` all; Pitfall-1=0; exec_ gate unchanged (only the pre-existing `gui_game.py:303` QMessageBox); `persistence.py` purity=0.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
