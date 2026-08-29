---
phase: 14-setup-tab-bundled-demos
plan: 01
subsystem: testing
tags: [tcl, tcltest, vmd, setup-state, quick-008, prng, pure-layer, tdd]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: pure-layer namespace ::biochemeleon::setup_state + tcltest harness under headless VMD (BCHM_TEST_RESULT marker) + GAME_REPS/DEFAULTS/DEMO_MANIFEST/hider_count_cap constants + validate_state STUB
provides:
  - "validate_state (full deterministic clamp: fills DEFAULTS, clamps hider_count [1,cap], drop-overflow per_rep clamp, enum validation, bool coercion, pdb_pool dedupe)"
  - "randomize_state (Randomize button: complete 11-key dict, seed-deterministic, lock_source branch, weighted-random mode, calls randomize_per_rep)"
  - "randomize_per_rep (quick-008 SETUP-06: random non-empty subset of reps + non-empty guarantee when hider_count>0)"
  - "6 internal helpers (_to_bool, _randint, _choice, _sample Fisher-Yates, _validate_pdb_code, _validate_pdb_pool)"
  - "~29 new tcltest cases (13 validate + 8 per_rep + 8 state) -> 41 total, all green under headless VMD"
affects:
  - "14-02 (mol bridge demos.tcl: load_demo/get_active_reps/save+load_setup call validate_state for canonicalization)"
  - "14-03/14-04 (GUI setup_tab: collect_state/apply_state/Reset/Randomize call validate_state + randomize_state)"
  - "Phase 16 (Start flow calls randomize_state/randomize_per_rep — quick-008 baked into both)"
  - "Phase 20 (.bcm Save/Load uses validate_state for defense-in-depth canonicalization)"

# Tech tracking
tech-stack:
  added: []  # stdlib-only tcl; no new libraries
  patterns:
    - "Global-PRNG determinism via seed arg: proc does expr {srand($seed)} at top; randomize_state seeds once and calls randomize_per_rep with NO seed (continues sequence) — Pitfall 4"
    - "DEFAULTS-key-order dict result: validate_state starts set result $DEFAULTS for order-stable dict eq (Pitfall 5)"
    - "Drop-overflow per_rep clamp: keep entries that fit remaining budget, DROP overflow (never truncate) — Pitfall 7"
    - "Fisher-Yates partial shuffle (_sample) as the tcl 8.5 port of Python random.sample"
    - "Pure-layer gate + 8.6-features gate run after every setup_state.tcl change"

key-files:
  created: []
  modified:
    - "vmd/lib/setup_state.tcl — replaced validate_state STUB with full impl; added 6 helpers + randomize_per_rep + randomize_state; updated namespace export"
    - "vmd/tests/test_setup_state.test — renamed stub test + added ~29 new cases (41 total)"

key-decisions:
  - "randomize_per_rep distributes across a RANDOM NON-EMPTY SUBSET (1..len) of reps, NOT all reps — the verified v1 quick-008 behavior (research Open Question 1 resolved per recommendation (a); matches generators.py:252 + 008-PLAN)"
  - "validate_state is a DETERMINISTIC clamp with NO randomness; all randomness isolated in randomize_state/randomize_per_rep (keeps the clamp testable)"
  - "per_rep-sum clamp DROPS overflow entries in insertion order, never truncates (Pitfall 7: {VDW 5 Cartoon 5 Lines 5} hc=8 -> {VDW 5})"
  - "v2 pdb_pool empty/invalid returns empty list (v2 has NO PDB_POOL constant; empty pool -> fetch re-rolls to demo in randomize_state)"
  - "Every randomness test passes an explicit seed as a proc arg (the proc reseeds internally via srand) — Pitfall 4 mitigation; no test relies on residual global PRNG state"

patterns-established:
  - "Global PRNG determinism: pass seed as proc arg; proc reseeds at top; orchestrator (randomize_state) seeds once and calls helper with NO seed so the helper continues the sequence"
  - "DEFAULTS-key-order result dict for order-stable dict eq round-trip in Save/Load (Pitfall 5)"
  - "Drop-overflow clamp (insertion-order keep + drop) — never truncate per_rep counts (Pitfall 7)"
  - "Pure-layer gate (no mol/atomselect/tk/toplevel/ttk) + 8.6-features gate (no lmap/try/throw/finally/tailcall/coroutine/yield) enforced on setup_state.tcl"

# Metrics
duration: 11min
completed: 2026-08-29
---

# Phase 14 Plan 01: Setup-state model (validate + randomize) Summary

**Pure-layer setup-state brain: full deterministic validate_state (drop-overflow clamp), randomize_state (seed-deterministic 11-key dict), and randomize_per_rep (quick-008 SETUP-06 non-empty-subset distribution) — 41 tcltest cases green under headless VMD.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-08-29T11:37:50Z
- **Completed:** 2026-08-29T11:48:57Z
- **Tasks:** 2 (RED + GREEN; no REFACTOR needed — clean transcription)
- **Files modified:** 2

## Accomplishments
- Replaced the validate_state STUB with the full deterministic v1 port: DEFAULTS-key-order result, hider_count clamp to [1, cap], insertion-order drop-overflow per_rep clamp (Pitfall 7), enum validation (target_mode/demo_id), bool coercion, pdb_pool dedupe (Pitfall 5 order-stable).
- Implemented randomize_per_rep — the quick-008 SETUP-06 helper: distributes hider_count across a random NON-EMPTY subset (1..len) of reps via Fisher-Yates _sample, with a non-empty guarantee (>=1 rep with count>0 when hider_count>0). seed -> deterministic.
- Implemented randomize_state — the Randomize button logic: seeds once at top, computes cap + hider_count, lock_source branch (preserves locked target) vs weighted-random mode (loaded/fetch/demo/demo; empty pdb_pool re-rolls fetch->demo), calls randomize_per_rep with NO seed (continues the global sequence). Returns a complete 11-key dict.
- Added 6 internal helpers (_to_bool, _randint, _choice, _sample, _validate_pdb_code, _validate_pdb_pool) — all stdlib-only.
- Added ~29 new tcltest cases (13 validate_state + 8 randomize_per_rep + 8 randomize_state) on top of the 12 from Phase 13 -> 41 total, all passing under headless VMD (Failed=0).
- setup_state.tcl remains pure (pure-layer gate: zero mol/atomselect/tk/toplevel/ttk) and 8.5-clean (8.6-features gate: zero lmap/try/throw/finally/tailcall/coroutine/yield).

## Task Commits

Each task was committed atomically (TDD RED-GREEN; REFACTOR skipped — code already clean):

1. **Task 1 (RED): Write ~28 failing tcltest cases** - `863d5d5` (test)
2. **Task 2 (GREEN): Implement validate_state full + randomize_state + randomize_per_rep** - `87db8e5` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified
- `vmd/lib/setup_state.tcl` — replaced validate_state STUB (lines 61-66) with 6 helpers + full validate_state + randomize_per_rep + randomize_state (~230 lines added); updated namespace export to add `randomize_state randomize_per_rep`.
- `vmd/tests/test_setup_state.test` — renamed `validate_state_stub_returns_defaults` -> `validate_state_empty_dict_returns_defaults_with_format`; added 29 new cases in 3 groups before the BCHM_TEST_RESULT marker.

## Decisions Made
- **quick-008 = random non-empty SUBSET (not all reps):** Implemented the verified v1 quick-008 behavior (`_randint 1 [llength $game_reps]` selects a subset size 1..len). This resolves research Open Question 1 per recommendation (a) — it is literally "v1's quick-008 patch" and what "baked in" means. (If the user later wants literal all-reps distribution, it's a one-line localized change to `set n [llength $game_reps]`.)
- **Determinism via seed-arg (not manual srand before call):** Every randomness test passes an explicit seed as a proc arg; the proc reseeds internally via `expr {srand($seed)}`. This is the API-faithful equivalent of the plan's "seed inside the loop body" guidance and satisfies Pitfall 4 (no reliance on residual global PRNG state; each call reseeds).
- **No REFACTOR commit:** The implementation is a clean, direct transcription of the probe-verified research skeletons; no duplication, dead code, or obvious improvements. Per the TDD reference, REFACTOR commits only happen if changes are made.
- **pdb_pool stays empty in v2 DEFAULTS:** v2 has no PDB_POOL constant (fetch is a later phase); empty/invalid pool returns `[list]` and randomize_state's fetch mode re-rolls to demo (research Open Question 3 resolved per recommendation).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `rm` denied by opencode.json — adapted test-staging approach**
- **Found during:** Task 1 verify (and Task 2 verify)
- **Issue:** The plan's verify command uses `rm -rf tmp/biochemeleon-vmd` to clean the staging dir, but `rm` is denied by opencode.json permission rules (confirmed in root AGENTS.md: "opencode.json denies pip*, apt*, conda*, rm*").
- **Fix:** Used a fixed staging dir `tmp/bchm14-stage` with `mkdir -p && cp -r vmd tmp/bchm14-stage/` (cp overwrites changed files). Achieves the same clean-staging result as `rm -rf` + fresh copy, without `rm`. The test runs `cd tmp/bchm14-stage && vmd -dispdev text -e vmd/tests/test_setup_state.test -eofexit` — identical to the plan's invocation (just a different staging dir name). `tmp/` is gitignored so leftover dirs are harmless.
- **Files modified:** none (workflow-only adaptation; no code changed)
- **Verification:** Baseline run (12 pass) + RED run (25 fail) + GREEN run (41 pass) all executed successfully via this staging approach.
- **Committed in:** N/A (workflow adaptation, not a code change)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking environment constraint)
**Impact on plan:** Minimal — the staging-dir name change is cosmetic and does not affect any deliverable, test result, or gate. All plan objectives met exactly as specified.

## Issues Encountered
None. The verified research skeletons (probe-verified against VMD 1.9.3's tcl 8.5.6) transcribed cleanly on the first run. The one brace-fix called out in the plan (randomize_state `if {$seed ne ""} { expr {srand($seed)} }`) was applied as specified. All 41 tests went green on the first GREEN run with no debugging needed.

## User Setup Required
None — no external service configuration required. This is a pure-layer tcl module + tcltest suite; the only runtime is VMD 1.9.3 (already installed) for the headless test harness.

## Next Phase Readiness
- **Ready for 14-02 (mol bridge demos.tcl):** `validate_state` is now the canonicalizer that `load_setup` will call for defense-in-depth; `GAME_REPS`/`DEMO_MANIFEST`/`SETUP_FORMAT` are exported and available to demos.tcl.
- **Ready for 14-03/14-04 (GUI):** `randomize_state` is the Randomize-button backend; `validate_state` is the Reset/Save/Load backend. Both are pure and tested.
- **Ready for Phase 16 (Start flow):** `randomize_state`/`randomize_per_rep` carry the quick-008 guarantee (SETUP-06) that the Start flow will rely on.
- **No blockers.** The pure-layer foundation for the Setup tab is verified.
- **Note for downstream:** `randomize_state`'s determinism depends on the GLOBAL tcl PRNG — callers that want reproducible randomization must pass a seed and must NOT interleave other `rand()` calls between the seed and the `randomize_per_rep` continuation (Pitfall 4). The Start flow (Phase 16) should pass an explicit seed if reproducibility is desired.

---
*Phase: 14-setup-tab-bundled-demos*
*Completed: 2026-08-29*
