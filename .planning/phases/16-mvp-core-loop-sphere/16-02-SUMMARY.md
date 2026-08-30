---
phase: 16-mvp-core-loop-sphere
plan: 02
subsystem: registry
tags: [tcl, tcltest, tdd, dict, vmd, pure-layer, found-state, game-logic, dependency-injection]

# Dependency graph
requires:
  - phase: 15-mutation-safety-hider-registry
    provides: pure ::biochemeleon::registry with reconstruct_from_sentinels/is_hider/mark_found/count_hiders/reset (record shape {rep status} keyed by atom index; HIDER_STATUS_HIDDEN/FOUND constants; silent-overwrite mark_found contract), 9-case tcltest suite + BCHM_TEST_RESULT headless-VMD harness
  - phase: 16-research (16-RESEARCH-sphere.md)
    provides: §6 probe-verified reference code for the three new procs + rep-arg signature; dict incr verified under tcl 8.5.6 (probe16_dictincr); mark_found idempotence (probe F19)
provides:
  - status_of {idx} -> "hidden" | "found" | "" (absent idx) — the LOOP-02 single source of truth for found-state
  - count_remaining {} -> int (hidden-only count; v1 game.py:113-116 _remaining parity) — GAME-03 total
  - remaining_by_rep {} -> dict {rep count} over hidden records; rep=="" records skipped; no zero-fill (GUI formats against GAME_REPS) — GAME-03 per-rep
  - reconstruct_from_sentinels {fetch_hider_ids {rep ""}} — optional rep arg, backward compatible; game.tcl will pass "VDW" (the sphere tier's GAME_REPS name)
  - tcltest suite extended 9 -> 18 cases, all green (BCHM_TEST_RESULT Total=18 Passed=18 Failed=0)
affects: [16-08 game.tcl on_pick (status_of guard BEFORE mark_found — the three-way miss/already-found/hidden caller guard), 16-09 game_tab.tcl update_remaining (count_remaining + remaining_by_rep pull model), 17+ multi-tier generators (per-tier rep stamps make per-rep remaining derivable forever), 20 .bcm sidecar (status persists via the same record shape)]

# Tech tracking
tech-stack:
  added: []  # stdlib tcl dict ops only — zero new deps (VMD 1.9.3 tcl 8.5.6)
  patterns:
    - "Pure-layer TDD RED->GREEN->REFACTOR on the registry (15-01 pattern reused): RED commits the failing-test contract (Total=18 Passed=9 Failed=9), GREEN implements (18/18), REFACTOR only if changes needed."
    - "dict for + dict incr over _records for aggregate views (8.5-safe; dict incr probe-verified in research); full-path $::biochemeleon::registry::HIDER_STATUS_* constant refs matching neighboring procs."
    - "Purity gate hygiene: avoid the English word 'after' in comments too — the plan's grep gate \bafter\b cannot distinguish comment prose from the tcl after command."

key-files:
  created: []
  modified:
    - vmd/lib/registry.tcl        # +status_of +count_remaining +remaining_by_rep (3 procs); reconstruct gains optional {rep ""}; export extended; header comment documents rep's Phase-16 meaning
    - vmd/tests/test_registry.test # +9 tcltest cases appended before the marker block (18 total); existing 9 + harness untouched (appends-only diff)

key-decisions:
  - "remaining_by_rep SKIPS rep==\"\" records instead of grouping them under the empty-string key. The research §6 reference code omitted the skip (it would emit {\"\" N}), but the plan's behavior spec + test 7 (remaining_by_rep_skips_empty_rep) + must_haves truth demand the skip — v1 registry.py:274-295 'skips rep None records exactly like we skip rep \"\"'. Implemented per the plan spec, not the research snippet."
  - "reconstruct_from_sentinels signature is {fetch_hider_ids {rep \"\"}} — optional 2nd arg with empty default, so every existing 1-arg call and test keeps working unchanged (backward-compatible signature widening only)."
  - "No guard logic added to mark_found — it stays a silent idempotent overwrite (probe F19); the three-way miss/already-found/hidden guard lives in the CALLER (Plan 16-08 on_pick reads status_of BEFORE mark_found)."
  - "Pre-existing Phase-15 comment lines reworded ('after start_game' -> 'post-start_game' etc.) so the plan's purity grep gate (which includes \\bafter\\b) returns zero matches — comment-only, no behavior change."

patterns-established:
  - "Registry found-state surface is pure and tcltest-able: status/count/aggregation are all dict ops over _records, unit-tested without VMD (18 cases green under headless VMD staging)."
  - "Appends-only test evolution: new cases inserted before the BCHM_TEST_RESULT marker block; existing cases never touched (git diff shows 69 insertions, 0 deletions)."

# Metrics
duration: 28min
completed: 2026-08-30
---

# Phase 16 Plan 02: Registry found-state surface Summary

**Pure-layer TDD: status_of / count_remaining / remaining_by_rep + an optional rep arg on reconstruct_from_sentinels added to ::biochemeleon::registry, with 9 new tcltest cases (18 total green under headless VMD) — LOOP-02 found-state single-source-of-truth and GAME-03 remaining-count data ready for 16-08 on_pick and 16-09 Game tab.**

## Performance

- **Duration:** 28 min
- **Started:** 2026-08-30T09:05:42Z
- **Completed:** 2026-08-30T09:34:38Z
- **Tasks:** 3 (RED, GREEN, REFACTOR+gates)
- **Files modified:** 2 (vmd/lib/registry.tcl, vmd/tests/test_registry.test)

## Accomplishments
- Three new pure procs: `status_of` (hidden/found/"" for unregistered — the status guard 16-08 needs), `count_remaining` (hidden-only, decrements on mark_found), `remaining_by_rep` ({rep count} over hidden, skips rep=="" — per-rep data 16-09 pulls).
- `reconstruct_from_sentinels` widened to `{fetch_hider_ids {rep ""}}` — 2-arg calls stamp every record's rep (game.tcl will pass "VDW"); all existing 1-arg calls/tests unchanged and green.
- tcltest suite 9 -> 18 cases, RED verified first (Total=18 Passed=9 Failed=9 on unknown procs + wrong-#-args), then GREEN Total=18 Passed=18 Failed=0 Skipped=0.
- registry.tcl stays 100% pure and 8.5-clean: purity gate (mol/atomselect/tk/after) and 8.6 gate (lmap/try/throw/tailcall/coroutine/yield/finally) both zero matches.
- No Phase-15 test touched: test-file diff vs baseline is appends-only (69 insertions, 0 deletions).

## Task Commits

Each task was committed atomically (TDD RED -> GREEN -> REFACTOR):

1. **Task 1 (RED): append 9 failing found-state tests** - `babb6cc` (test)
2. **Task 2 (GREEN): implement status_of/count_remaining/remaining_by_rep + rep arg** - `d0377a2` (feat)
3. **Task 3 (REFACTOR): reword pre-existing 'after' comments for the purity gate** - `eaa5e74` (refactor)

**Plan metadata:** committed as `docs(16-02): complete registry found-state plan` (this SUMMARY; STATE.md intentionally NOT updated — orchestrator owns it during parallel waves).

## Files Created/Modified
- `vmd/lib/registry.tcl` — added `status_of`, `count_remaining`, `remaining_by_rep` procs; `reconstruct_from_sentinels` now `{fetch_hider_ids {rep ""}}` stamping `rep $rep`; `namespace export` extended with the three new names; record-shape header comment documents rep's Phase-16 meaning (GAME_REPS tier name, "VDW" for Phase 16); 3 pre-existing comment lines reworded to drop the English word "after" (purity-gate hygiene).
- `vmd/tests/test_registry.test` — 9 new cases appended before the BCHM_TEST_RESULT marker block: `reconstruct_with_rep_arg`, `status_of_unregistered_is_empty`, `status_of_after_mark_found`, `count_remaining_counts_hidden_only`, `count_remaining_after_reset`, `remaining_by_rep_groups_and_sums`, `remaining_by_rep_skips_empty_rep`, `mark_found_idempotent`, `one_arg_reconstruct_still_works`. Existing 9 cases + harness byte-identical.

## Decisions Made
- **remaining_by_rep skips rep=="" records** (does NOT group them under the empty-string key). The research §6 reference snippet omitted the skip and would have returned `{"", N}`; the plan's behavior spec, must_haves truth, and test 7 all require the skip (v1 registry.py:274-295 parity). Implemented per plan spec; tracked as a deviation below.
- **Signature widening only** on reconstruct_from_sentinels — `{fetch_hider_ids {rep ""}}` keeps every existing caller working (proven by the untouched Phase-15 tests staying green).
- **mark_found untouched** — silent idempotent overwrite stays (probe F19); double-mark test asserts no error + count unchanged, and the three-way guard is documented as the 16-08 caller's job.
- **Comment rewording over gate exception** — the purity grep cannot tell the English word "after" from the tcl `after` command, so 3 pre-existing Phase-15 comments were reworded ("post-start_game"/"post-cleanup"/"post-restore") rather than weakening the gate.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] research §6 reference code for remaining_by_rep omitted the rep=="" skip**

- **Found during:** Task 2 (GREEN) — first staged run returned Total=18 Passed=16 Failed=2 (remaining_by_rep_skips_empty_rep got `0 2`, one_arg_reconstruct_still_works got `1 0 1`: remaining_by_rep returned a dict keyed by "" instead of empty)
- **Issue:** The research §6 snippet groups every hidden record under its rep without skipping rep=="" records, contradicting the plan's own behavior spec + must_haves + test 7 + the cited v1 registry.py:274-295 parity ("skips rep None records exactly like we skip rep \"\"")
- **Fix:** Added `if {$r eq ""} { continue }` inside the dict-for loop in remaining_by_rep
- **Files modified:** vmd/lib/registry.tcl
- **Verification:** Full suite 18/18 green (BCHM_TEST_RESULT Total=18 Passed=18 Failed=0)
- **Committed in:** d0377a2 (Task 2 commit)

**2. [Rule 3 - Blocking] Purity gate had 3 pre-existing matches (English "after" in Phase-15 comments)**

- **Found during:** Task 3 (gates) — `grep -nE "\bmol\b|\batomselect\b|\btk\b|\bafter\b" vmd/lib/registry.tcl` matched lines 67/68/74, all the English word "after" in comments predating this plan (Phase-15 text), not `after` command usage
- **Issue:** The plan's verification requires ZERO purity matches; the gate cannot distinguish comment prose from the tcl `after` command
- **Fix:** Reworded the 3 comment lines (after start_game -> post-start_game, after cleanup -> post-cleanup, after restore -> post-restore) — comment-only, no behavior change
- **Files modified:** vmd/lib/registry.tcl
- **Verification:** Purity gate zero matches; 8.6 gate zero matches; suite still 18/18
- **Committed in:** eaa5e74 (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking)
**Impact on plan:** Both fixes were required to meet the plan's own behavior spec and verification gates. No scope creep; the 8.6 gate was already clean.

## Issues Encountered
- **tclsh not in WSL** (known, same as 15-01) — the tcltest suite ran under headless VMD via staging (`tmp/biochemeleon-vmd/` inside this worktree, `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/tests/test_registry.test -eofexit < /dev/null'`), parsing the `BCHM_TEST_RESULT` marker.
- **`bash -ic` tcsetattr hang at VMD exit** (known benign WSL/VMD interaction) — the marker prints before the hang; `timeout 300` + grep handled all three runs.
- No false-PASS risk: all three run logs were scanned for `ERROR)` and `bad switch` — zero matches in every run.

## User Setup Required

None - no external service configuration required. Pure-layer tcl change with zero new dependencies (stdlib dict ops on VMD 1.9.3's bundled tcl 8.5.6).

## Next Phase Readiness
- **Ready for 16-08 (game.tcl on_pick):** `status_of` is exported and tested — the caller-side three-way guard (unregistered -> miss; "found" -> already-found; "hidden" -> mark_found) can be implemented exactly per v1 game.py on_pick parity. mark_found stays the silent overwrite; no registry change needed.
- **Ready for 16-09 (game_tab.tcl update_remaining):** `count_remaining` (total) + `remaining_by_rep` (per-rep, easy mode) are exported and tested; the GUI pulls both — format_remaining orders against GAME_REPS (no zero-fill by design, so absent reps just display 0).
- **Ready for 16-01/16-04..07 generators:** game.tcl should call `reconstruct_from_sentinels $fetch "VDW"` (the sphere tier's GAME_REPS name) so per-rep remaining is derivable forever; 1-arg calls remain valid for any non-tier usage.
- **No blockers.** Registry stays the pure layer (both grep gates zero), unit-testable without VMD; 18/18 green.

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
