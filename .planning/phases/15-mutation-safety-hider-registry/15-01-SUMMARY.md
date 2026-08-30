---
phase: 15-mutation-safety-hider-registry
plan: 01
subsystem: registry
tags: [tcl, tcltest, tdd, dict, vmd, pure-layer, dependency-injection, apply-lambda]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: pure ::biochemeleon::registry stub (reconstruct_from_sentinels/is_hider/mark_found via DI + {expand}; the 5 Phase-13 tcltest cases; the BCHM_TEST_RESULT harness + cleanupTests block; the verified [{*}$fetch_hider_ids] DI contract)
provides:
  - count_hiders {} -> int (dict size of _records; registry size, 0 when empty)
  - reset {} -> {} (zeroes _records; post-reset count_hider==0 and is_hider<any>==0)
  - 4 new tcltest cases (9 total green) incl. the molid-bound apply-lambda DI shape
  - export list extended with count_hiders + reset
affects: [15-02 game.tcl (cleanup calls reset; capstone smoke asserts count_hiders), 15 capstone smoke (SC3 exact-set proof), 16-mvp-loop (generators/click loop may read count)]

# Tech tracking
tech-stack:
  added: []  # stdlib tcl dict ops only — zero new deps (VMD 1.9.3 tcl 8.5.6)
  patterns:
    - "Pure-layer TDD RED->GREEN: commit failing tests first (the contract), then minimal impl. The pure tcltest suite + headless-VMD harness lets registry changes be TDD'd WITHOUT touching mol-coupled code."
    - "Bound-arg DI test case: the pure suite now mirrors game.tcl's [list apply {lambda} <arg>] command-prefix expansion shape, so the [{*}$fetch_hider_ids] one-arg contract is unit-tested at the pure layer (not just the capstone smoke)."

key-files:
  created: []
  modified:
    - vmd/lib/registry.tcl        # +count_hiders +reset (2 procs) + export update; stays PURE
    - vmd/tests/test_registry.test # +4 tcltest cases (9 total); existing 5 + harness unchanged

key-decisions:
  - "count_hiders = [dict size $_records] — trivial dict op. Required because the SC3 capstone smoke must prove the registry holds EXACTLY the sentinel set (no over-population): atomselect-count==N AND is_hider-per-sentinel AND count_hiders==N together pin the exact set. Without count_hiders the smoke could only prove each sentinel is_hider (cannot disprove extra phantom entries)."
  - "reset = set _records [dict create] — clearer than reconstruct_from_sentinels [list apply {{} {return [list]}}] (reuses the tested proc). Chosen because cleanup is a concrete Phase-15 caller (v1 parity: game::cleanup resets the registry so post-cleanup is_hider/count_hiders return 0)."
  - "Added a molid-bound apply-lambda DI case to the PURE suite (reconstruct_with_bound_arg_lambda). Phase 13's suite only exercised zero-arg lambdas; this is the first pure-layer verification of the ONE-arg [list apply {lambda} <arg>] command-prefix form that game.tcl actually injects (probed HIGH-confidence in 15-RESEARCH). The case uses a fake_molid arg returning {7 8} — no molecular-viewer API, pure unit test."
  - "DEFERRED to Phase 16/19 (YAGNI — no Phase-15 caller): count_found, count_remaining, list_hider_indices, hider_status. The rep field stays \"\" for placeholder hiders (real rep assignment is Phase 16/17 generator work)."

patterns-established:
  - "Pure-layer TDD cycle (RED->GREEN) on the registry: RED commits the failing-test contract (Total=9 Passed=5 Failed=4), GREEN adds the minimal dict-op impl (Total=9 Passed=9 Failed=0). Reusable for every future pure-registry addition."
  - "Verbatim-from-research test cases: the 4 new cases are copied character-for-character from 15-RESEARCH-registry-game.md lines 242-267 (the research already probed the DI shape against the real VMD install). Eliminates test-authoring drift between research and execution."
  - "DI bound-arg coverage in the pure suite: every command-prefix shape game.tcl injects (zero-arg AND one-arg apply lambdas) now has a pure-layer tcltest case, so the [{*}$fetch_hider_ids] expansion contract is unit-testable without VMD atomselect."

# Metrics
duration: 18min
completed: 2026-08-30
---

# Phase 15 Plan 01: Registry count_hiders + reset Summary

**Pure-layer TDD: count_hiders (dict size) + reset (clear) added to the existing ::biochemeleon::registry, with 4 new tcltest cases (9 total green under headless VMD) including the molid-bound apply-lambda DI shape game.tcl will inject.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-08-30T03:08+0800 (2026-08-29T19:08Z)
- **Completed:** 2026-08-30T03:29+0800 (2026-08-29T19:29Z; after GREEN verification)
- **Tasks:** 2 (RED test, GREEN impl)
- **Files modified:** 2 (vmd/lib/registry.tcl, vmd/tests/test_registry.test)

## Accomplishments
- `count_hiders {} -> int` and `reset {} -> {}` implemented as pure stdlib dict ops on the existing `::biochemeleon::registry` namespace, exported alongside the Phase-13 procs.
- tcltest suite extended from 5 -> 9 cases, all green under headless VMD (`BCHM_TEST_RESULT Total=9 Passed=9 Failed=0 Skipped=0`).
- The molid-bound apply-lambda DI case passes — the pure suite now mirrors game.tcl's actual `[list apply {lambda} $game_molid]` command-prefix injection shape, verifying the `[{*}$fetch_hider_ids]` one-arg expansion contract without needing VMD atomselect.
- registry.tcl stays PURE: zero `mol`/`atomselect`/`tk`/`toplevel`/`ttk` tokens and zero tcl 8.6 idioms (`lmap`/`try`/`throw`/`finally`/`tailcall`/`coroutine`/`yield`) — both grep gates return zero matches.
- No regression: the 5 Phase-13 cases + `reconstruct_from_sentinels`/`is_hider`/`mark_found`/`HIDER_STATUS_*`/`_records` initializer are all unchanged.

## Task Commits

Each task was committed atomically (TDD RED -> GREEN):

1. **Task 1 (RED): Add 4 failing tcltest cases for count_hiders + reset** - `ab25dcb` (test)
2. **Task 2 (GREEN): Implement count_hiders + reset in registry.tcl** - `b10f9a5` (feat)

**Plan metadata:** pending `docs(15-01)` commit (this SUMMARY + PLAN.md).

## Files Created/Modified
- `vmd/lib/registry.tcl` — added `count_hiders` (returns `[dict size $_records]`) and `reset` (sets `_records [dict create]`) after `mark_found`; extended the `namespace export` line. Stays the PURE layer (stdlib dict ops + namespace vars only; the atomselect lambda is injected by game.tcl, never referenced here).
- `vmd/tests/test_registry.test` — appended 4 tcltest cases after the existing 5 and before the `BCHM_TEST_RESULT`/`cleanupTests` block: `count_hiders_after_reconstruct` (3 after {5 10 15}), `count_hiders_empty` (0 after []), `reset_clears_records` (count 0 + is_hider 0 after reset), `reconstruct_with_bound_arg_lambda` (is_hider 7/8 + count 2 via a `[list apply {{fake_molid} {return {7 8}}} "dummy_molid"]` bound-arg prefix). Cases are verbatim from 15-RESEARCH-registry-game.md lines 242-267.

## Decisions Made
- **count_hiders + reset are the minimal Phase-15 real logic (YAGNI).** Both have concrete Phase-15 callers (the SC3 capstone smoke asserts `count_hiders == 5` after start / `== 0` after cleanup; `game::cleanup` calls `reset`). `count_found`/`count_remaining`/`list_hider_indices`/`hider_status` are deferred to the phases that call them (16/19).
- **reset uses `set _records [dict create]`** rather than reusing `reconstruct_from_sentinels` with an empty-returning lambda — clearer intent and a direct v1 parity (`game.py` cleanup re-instantiates the registry).
- **The bound-arg DI case was added to the PURE suite** (not just the capstone smoke) so the `[{*}$fetch_hider_ids]` one-arg expansion is unit-testable without VMD. Phase 13's suite only covered the zero-arg form; this closes that gap using a fake_molid lambda (no molecular-viewer API).
- **Test cases are verbatim from the research doc** (lines 242-267) — the research already probed the DI shape against the real VMD 1.9.3 install (HIGH confidence), so copying character-for-character eliminates authoring drift.

## Deviations from Plan

None - plan executed exactly as written. The RED state matched the expected `Total=9 Passed=5 Failed=4` (4 new cases erroring on undefined `count_hiders`/`reset`, 5 existing passing) and the GREEN state matched `Total=9 Passed=9 Failed=0`. No bugs, no missing critical functionality, no blocking issues, no architectural changes. Both purity gates (zero mol/atomselect/tk/toplevel/ttk; zero lmap/try/throw/finally/tailcall/coroutine/yield) were clean before AND after the edits.

## Issues Encountered
- **`tclsh` not installed in WSL** — the AGENTS.md mentions tclsh for pure-layer syntax checks, but it is not present in this WSL env (`tclsh: command not found`). Not a blocker: the canonical verification is the tcltest suite run under headless VMD (the established Phase 13/14 pattern), which ran cleanly. The pure layer is still unit-testable; a user-installed tclsh would also run the suite standalone.
- **`bash -ic` wrapper `tcsetattr` hang at VMD exit** — the known WSL/VMD interaction where the interactive-shell wrapper prints `bash: [...] tcsetattr: Inappropriate ioctl for device` after VMD exits. Not a failure: the `BCHM_TEST_RESULT` marker is printed BEFORE the hang, so `grep` finds it even when `timeout` kills the hung shell. Both RED and GREEN runs parsed the marker successfully.
- **WSL clock drift** — the `date -u` "now" timestamp drifted ~5h ahead of the git commit timestamps (a known WSL issue). Not a blocker; commit timestamps (the reliable artifacts) were used for the duration/started/completed metrics.

## User Setup Required

None - no external service configuration required. This is a pure-layer tcl change with zero new dependencies (stdlib dict ops on VMD 1.9.3's bundled tcl 8.5.6).

## Next Phase Readiness
- **Ready for 15-02 (game.tcl composition root):** `game::cleanup` can call `::biochemeleon::registry::reset` (now implemented + exported + tested); the capstone smoke can assert `count_hiders == 5` after `start_game` and `== 0` after `cleanup` (SC3 exact-set proof). The bound-arg `[list apply {{molid} {...}} $game_molid]` injection shape is now pure-layer-verified.
- **Ready for the Phase 15 capstone smoke (SC1-SC4):** count_hiders + is_hider-per-sentinel together prove the registry holds exactly the sentinel set (no over/under-population); reset proves the post-cleanup registry is empty.
- **No blockers.** registry.tcl remains the pure layer (passes both grep gates), unit-testable in WSL without VMD (SC3). The deferred procs (count_found etc.) arrive with their calling phases.

---
*Phase: 15-mutation-safety-hider-registry*
*Completed: 2026-08-30*
