---
phase: 13-bootstrap-sourced-entry
plan: 01
subsystem: testing
tags: [tcl, tcltest, vmd, headless, pure-layer, dependency-injection]

# Dependency graph
requires:
  - phase: none (first v2 phase)
    provides: nothing
provides:
  - "Pure-layer tcl foundation: vmd/lib/setup_state.tcl (GAME_REPS, DEMO_MANIFEST, DEFAULTS, hider_count_cap, validate_state stub)"
  - "Pure-layer tcl foundation: vmd/lib/registry.tcl (DI reconstruct_from_sentinels, is_hider, mark_found stubs)"
  - "tcltest suites under headless VMD (test_setup_state.test 12 cases, test_registry.test 5 cases)"
  - "Verified WSL headless-VMD test runner: bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e <script> -eofexit < /dev/null'"
  - "BCHM_TEST_RESULT marker convention (VMD does NOT propagate tcl exit codes)"
  - "[pwd]-based path resolution for -e'd scripts ([info script] is empty under vmd -e)"
  - "Pure-layer grep gate command (zero molecular-viewer/GUI tokens, zero tcl 8.6 idioms)"
affects: [13-02, 14, 15, 16, 17.1, 17.2, 18, 19, 20, 22]

# Tech tracking
tech-stack:
  added: []  # stdlib-only tcl 8.5; no new libs (VMD ships tcltest 2.3.0)
  patterns:
    - "Pure-layer / cmd-layer split (v1 architecture ported to tcl: lib/*.tcl stdlib-only, no mol/atomselect/tk)"
    - "Dependency injection via tcl command-prefix + {expand} (registry.tcl calls [{*}$fetch_hider_ids])"
    - "Headless VMD tcltest harness: marker-line result parsing (BCHM_TEST_RESULT), NOT $? (VMD exits 0 always)"
    - "[pwd]-based path resolution for -e'd test scripts ([info script] empty under vmd -e)"
    - "Staging pattern: cp -r vmd tmp/biochemeleon-vmd/ then cd staging && vmd -e (Windows-visible path)"

key-files:
  created:
    - vmd/lib/setup_state.tcl
    - vmd/lib/registry.tcl
    - vmd/tests/test_setup_state.test
    - vmd/tests/test_registry.test
  modified: []

key-decisions:
  - "Namespace name = ::biochemeleon::setup_state (filename parity with v1 setup_state.py; NOT ::biochemeleon::setup)"
  - "tcltest runs UNDER headless VMD (tclsh NOT installed in WSL; AGENTS.md forbids apt). .test files are standalone-tclsh-compatible if user later installs tcl."
  - "Result parsing = BCHM_TEST_RESULT marker line, NEVER $? (VMD does NOT propagate tcl exit codes — verified)"
  - "DI via tcl command-prefix + {expand}: reconstruct_from_sentinels uses [{*}$fetch_hider_ids] (supports proc names AND apply lambdas)"
  - "Comments use literal-worded prohibition ('no molecular-viewer API, no GUI toolkit') not forbidden tokens, to keep grep gate clean"

patterns-established:
  - "Pure-layer purity gate: grep -rnE for mol/atomselect/tk/toplevel/ttk:: + lmap/try/throw/tailcall/coroutine/yield returns zero on vmd/lib/*.tcl"
  - "Test marker convention: BCHM_TEST_RESULT Total=N Passed=N Failed=N Skipped=N (printed BEFORE cleanupTests; parsed by grep, not $?)"
  - "Headless test invocation: stage vmd/ to tmp/biochemeleon-vmd/, then bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/<file>.test -eofexit < /dev/null'"

# Metrics
duration: 20 min
completed: 2026-08-28
---

# Phase 13 Plan 01: Pure-layer tcl + tcltest harness Summary

**v2 pure-layer tcl foundation (setup_state.tcl + registry.tcl) with stdlib-only dependency-injected registry, unit-tested via tcltest under headless VMD from WSL (17 tests, Failed=0)**

## Performance

- **Duration:** 20 min
- **Started:** 2026-08-27T20:14:30Z
- **Completed:** 2026-08-28T04:39:39Z (spanned an interrupted session; actual working time ~20 min)
- **Tasks:** 2
- **Files modified:** 4 (all created)

## Accomplishments
- Established the v2 pure-layer tcl foundation: `vmd/lib/setup_state.tcl` (GAME_REPS 10-rep list, SETUP_FORMAT v2, DEFAULTS 11 keys, DEMO_MANIFEST 6 bundled entries, hider_count_cap, validate_state stub) and `vmd/lib/registry.tcl` (DI reconstruct_from_sentinels, is_hider, mark_found stubs) — both stdlib-only, zero mol/atomselect/tk references (grep gate clean).
- Proved the WSL headless-VMD tcltest harness works: 17 tcltest cases (12 setup_state + 5 registry) all pass with `BCHM_TEST_RESULT Failed=0` via `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/*.test -eofexit < /dev/null'`.
- Established the dependency-injection pattern in tcl: `reconstruct_from_sentinels` takes a command prefix and invokes it via `[{*}$fetch_hider_ids]` (argument expansion), supporting both proc names and `apply` lambdas — registry.tcl stays pure (no mol/atomselect); game.tcl in a later phase injects the real atomselect lambda.
- Locked the pure-layer contract from day one (TEST-02 + half ENTRY-03): strict dependency direction, the grep gate, the marker-line result convention, and the `[pwd]`-based path resolution (because `[info script]` is empty under `vmd -e`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Create the pure-layer tcl modules (setup_state.tcl + registry.tcl)** - `ecb0969` (feat)
2. **Task 2: Create tcltest suites + run them under headless VMD + run the grep gate** - `5a288a0` (test)

**Plan metadata:** (pending — created after this summary)

## Files Created/Modified
- `vmd/lib/setup_state.tcl` - Pure setup-state layer: GAME_REPS (10 reps), SETUP_FORMAT v2, DEFAULTS (11 keys), DEMO_MANIFEST (6 bundled entries), hider_count_cap proc, validate_state stub. Namespace `::biochemeleon::setup_state`.
- `vmd/lib/registry.tcl` - Pure hider registry: HIDER_STATUS_HIDDEN/FOUND, _records dict (keyed by atom index), reconstruct_from_sentinels (DI via command-prefix + {expand}), is_hider, mark_found stubs. Namespace `::biochemeleon::registry`.
- `vmd/tests/test_setup_state.test` - tcltest suite (12 cases): GAME_REPS count/first/no-surface, hider_count_cap (212→4, 0→1, 100000→50), SETUP_FORMAT v2, DEFAULTS, DEMO_MANIFEST (6 entries, 1znf source=bundled), validate_state stub. Sources via `[pwd]`.
- `vmd/tests/test_registry.test` - tcltest suite (5 cases): reconstruct_from_sentinels DI (clears+populates, clears previous, empty list), mark_found (sets status, errors on unregistered). DI via `[list apply ...]` command prefixes.

## Decisions Made
- **Namespace name = `::biochemeleon::setup_state`** (not `::biochemeleon::setup`): filename parity with v1's `setup_state.py`. This was a locked plan-time decision (the testing research's recommendation wins on filename-parity grounds over the entry research's `setup`).
- **tcltest under headless VMD, not standalone tclsh**: `tclsh` is NOT installed in WSL and AGENTS.md forbids `apt`. The `.test` files are written identically to standalone-tclsh form, so they run unchanged if the user later installs tcl (informational, not a checkpoint).
- **Result parsing via `BCHM_TEST_RESULT` marker, never `$?`**: VMD does NOT propagate tcl exit codes (`$?` is always 0 — verified). The marker is printed BEFORE `cleanupTests` (the numTests array is correct before, reset after).
- **DI via tcl command-prefix + `{expand}`**: `reconstruct_from_sentinels` uses `[{*}$fetch_hider_ids]` (argument expansion), the idiomatic tcl DI that supports both proc names and `apply` lambda lists. This was a bug fix discovered during Task 2 (see Deviations).
- **Literal-worded prohibition comments**: comments say "no molecular-viewer API, no GUI toolkit" rather than naming forbidden tokens (mol/atomselect/tk), to keep the grep gate clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed DI invocation in reconstruct_from_sentinels**
- **Found during:** Task 2 (running test_registry.test under headless VMD)
- **Issue:** The plan's skeleton (and the research doc's skeleton, lines 263-270) used `foreach idx [$fetch_hider_ids]` — single-word command invocation. The plan's test code passed `[apply {{} { return {5 10 15} }}]` which EVALUATES the apply immediately, returning the list `{5 10 15}`; then `[$fetch_hider_ids]` treats that list as a single command name → `invalid command name "5 10 15"`. 4 of 5 registry tests failed.
- **Fix:** Switched the library to `foreach idx [{*}$fetch_hider_ids]` (tcl argument-expansion `{*}`), which expands a command-prefix list into command words — works for both proc names (1-element list expands to itself) and `apply` lambda lists. Updated the tests to pass command prefixes via `[list apply ...]` (a value, not evaluated at the call site) instead of `[apply ...]` (evaluated immediately).
- **Files modified:** vmd/lib/registry.tcl, vmd/tests/test_registry.test
- **Verification:** Both suites re-run under headless VMD: setup_state 12/12 Passed, registry 5/5 Passed (`BCHM_TEST_RESULT Failed=0`). Grep gate stays clean.
- **Committed in:** `5a288a0` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The DI fix was necessary for the registry tests to pass — it corrects a bug present in the research doc's verified skeleton (the skeleton used `[$fetch_hider_ids]` which only works if `fetch_hider_ids` is a bare proc name, not an apply lambda; the plan's tests used apply lambdas, exposing the mismatch). The `{*}` expansion is the idiomatic tcl DI form and is documented in the SUMMARY for downstream plans. No scope creep.

## Issues Encountered
- The research doc's verified skeleton (lines 263-270, 286-296) showed `[$fetch_hider_ids]` for the DI call AND `apply` lambdas for the injection — these two are incompatible (`$cmd` invokes a single-word command; an `apply` lambda is a multi-word command prefix). The skeleton was "verified to source cleanly" but never exercised with an actual apply lambda at runtime. Resolved by switching to `[{*}$fetch_hider_ids]` (argument expansion) — the idiomatic tcl DI form. Downstream plans (Phase 15 game.tcl) MUST use the `{*}` form when injecting `apply` lambdas.

## User Setup Required
None - no external service configuration required. The headless VMD test harness uses the existing VMD 1.9.3 install (bashrc alias `vmd`); no new dependencies.

## Next Phase Readiness
- **Ready for Plan 13-02:** the entry script (`vmd/biochemeleon.tcl`) MUST source the pure layers by their exact namespace names: `::biochemeleon::setup_state` and `::biochemeleon::registry`. The smoke harness uses the same headless-VMD invocation pattern (`bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e <script> -eofexit < /dev/null'`) and the same `[pwd]`-based path resolution. The smoke uses `BCHM_SMOKE_RESULT` (different marker, same principle: VMD doesn't propagate exit codes).
- **Ready for Phase 14:** `validate_state` is a stub returning DEFAULTS (full validation is Phase 14); `randomize_state` is not yet ported (Phase 14). The tcltest harness is proven — every later pure-layer addition has a fast feedback loop.
- **Ready for Phase 15:** the DI shape is established — `reconstruct_from_sentinels` takes a command prefix; game.tcl injects an `apply` lambda that calls atomselect. The full sentinel logic (registry dict population) is Phase 15.
- **Grep gate stays scoped to `vmd/lib/`:** Plan 13-02's entry script is NOT pure (it uses mol/tk), so the gate stays scoped to `vmd/lib/*.tcl`. Re-run it after adding any new pure-layer file.
- **No blockers.** The `tclsh`-not-in-WSL constraint is mitigated (tcltest under headless VMD); the user MAY optionally `apt install tcl` for faster runs but it's not required.

---
*Phase: 13-bootstrap-sourced-entry*
*Completed: 2026-08-28*
