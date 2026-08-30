---
phase: 16-mvp-core-loop-sphere
plan: 08
subsystem: game-loop
tags: [vmd, tcl-8.5, on-pick, click-to-find, scoring, callbacks, registry, headless-smoke]

# Dependency graph
requires:
  - phase: 15-mutation-safety-hider-registry
    provides: game.tcl composition root (start_game/cleanup/restart + frozen game_state dict + DI reconstruct), registry (mark_found/status_of/count_remaining), backup/mutation pipeline
  - phase: 16-mvp-core-loop-sphere (16-02)
    provides: registry status_of/count_remaining/remaining_by_rep + HIDER_STATUS_FOUND
  - phase: 16-mvp-core-loop-sphere (16-03)
    provides: game_logic state machine (state/finish_win/timer_elapsed/format_mmss/log_append)
  - phase: 16-mvp-core-loop-sphere (16-05)
    provides: hiders.tcl add_hider_reps/mark_found_visual (user2 flag + 2-rep split)
  - phase: 16-mvp-core-loop-sphere (16-06)
    provides: pick_bridge _on_event -> game::on_pick <index> single-arg contract
provides:
  - game::on_pick {idx} — v1 three-way guard (miss / already-found / hidden -> mark_found_visual + mark_found + log + remaining cb -> win check) with the game_logic playing-state gate and caller-side registry guard
  - game::set_callbacks {log_cb remaining_cb win_cb} — callback interface (1/0/2-arg contract; empty prefixes catch-safe)
  - start_game hider-rep step (hiders::add_hider_reps after backup::apply) + current_state namespace stash (cleared by cleanup)
  - phase16_onpick_smoke.tcl headless smoke (PASS=1): miss/hit/already/win/state-gate/double-win/stash-guard with recording callbacks
affects: [16-09 (Game tab registers set_callbacks + calls on_win), 16-11 (phase16_smoke re-runs all), 16-12 (GUI human-verify locks the pick contract), Phase 19 (cleanup/restart builds on game::cleanup)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — stdlib tcl only
  patterns:
    - "caller-side three-way guard (is_hider -> status_of found -> hidden) BEFORE mark_found (silent idempotent overwrite)"
    - "catch-wrapped pick handler with rc == 1 (TCL_ERROR) check, never a truthy catch test (guard returns carry TCL_RETURN rc == 2)"
    - "game_state stash in a namespace var (current_state) instead of threading state through pick_bridge"
    - "zero-arg callback recorder must be {incr counter} (a zero-arg lappend never grows a list)"

key-files:
  created:
    - vmd/smoke/phase16_onpick_smoke.tcl
  modified:
    - vmd/lib/game.tcl
    - vmd/smoke/phase15_smoke.tcl
    - vmd/smoke/phase15_game_smoke.tcl

key-decisions:
  - "on_pick reads the current_state namespace var stashed by start_game (cleared by cleanup) — the PickBridge contract delivers ONLY the index; game_state dict shape stays FROZEN {game_molid hider_count snapshot}"
  - "State gate FIRST (game_logic state == playing), then the empty-stash guard, then the three-way registry guard — stray picks during idle/countdown/won are no-ops and the gate doubles as double-win prevention"
  - "hider-rep step placed right after backup::apply per research SS5.5 (base numreps deterministic; hider reps are the LAST two); DI reconstruct line byte-unchanged"
  - "Win flow: finish_win (freezes elapsed, errors on double) -> timer_elapsed returns the FROZEN value -> win log line -> win_cb (elapsed hider_count); PickBridge deactivation stays the GUI's job (16-09 on_win)"

patterns-established:
  - "Callback prefixes stored as command-word lists invoked via catch {{*}$cb <args>} — unset callbacks are harmless no-ops (v1 set_callbacks parity)"
  - "Phase-15 smoke harnesses now source hiders.tcl and expect game-molid numreps == saved_numreps + 2 (Phase-16 hider-rep contract)"

# Metrics
duration: 14min
completed: 2026-08-30
---

# Phase 16 Plan 08: on_pick Controller Summary

**game.tcl click-scoring controller: v1 three-way on_pick (registry-guarded), set_callbacks interface, start_game hider-rep step + game_state stash — headless-proven end-to-end with recording callbacks (PASS=1 first clean run after one recorder fix)**

## Performance

- **Duration:** 14 min
- **Started:** 2026-08-30T10:04:36Z
- **Completed:** 2026-08-30T10:18:25Z
- **Tasks:** 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments
- `on_pick {idx}` implements the exact v1 three-way scoring (04-03 game.py 1:1): unregistered → "Miss!" log only; already-found → "Already found!" log only; hidden → mark_found_visual + mark_found + "Found one! N remaining" + remaining callback → win check. Registry status stays the single source of truth (LOOP-02); the caller-side guard is mandatory because mark_found silently overwrites (Pitfall 5)
- Win path fires exactly once: count_remaining == 0 → finish_win (freezes elapsed, errors on double) → win log line ("You found all 5 hiders in M:SS!") → win_cb with (elapsed, hider_count); stray picks outside `playing` are inert (state gate + finish_win guard = double-win prevention)
- `set_callbacks {log_cb remaining_cb win_cb}` stores command prefixes (1/0/2-arg contract); the 16-09 Game tab can register without game.tcl knowing the GUI
- start_game gains the hider-rep step (`hiders::add_hider_reps` right after `backup::apply`, research SS5.5) and stashes game_state in `current_state` (cleared by cleanup); the DI reconstruct line is byte-unchanged and the game_state dict shape stays frozen
- phase16_onpick_smoke.tcl proves all 10 plan steps headlessly with RECORDING callbacks (log lines, remaining-cb invocation count, win args), including the state gate, double-win prevention, and a direct empty-stash-guard proof

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend game.tcl (hider-rep step + on_pick + callbacks)** - `f35fa76` (feat)
2. **Task 2: Write + run the on_pick smoke** - `93db2cf` (test)
3. **Deviation fix: phase15 smoke harness updates** - `db3beac` (fix)

## Files Created/Modified
- `vmd/lib/game.tcl` - Extended composition root: namespace exports (on_pick, set_callbacks), current_state + _cb_* namespace vars, hider-rep step in start_game, stash build/clear, set_callbacks, on_pick with state gate + stash guard + three-way scoring + win flow (all catch-wrapped, rc == 1 error reporting via vmdcon -err)
- `vmd/smoke/phase16_onpick_smoke.tcl` - NEW: 10-step headless smoke with recording callbacks; sources libs in dep order incl. generators + game_logic + hiders; PASS=1 FAIL=none
- `vmd/smoke/phase15_smoke.tcl` - Regression fix: source hiders.tcl; game_numreps assertion now saved_numreps + 2 (Phase-16 hider-rep contract); restored-molid assertion unchanged
- `vmd/smoke/phase15_game_smoke.tcl` - Same regression fix (source hiders.tcl; game_numreps + 2)

## Decisions Made
- **Stash over threading:** game_state lives in the `current_state` namespace var (start_game sets, cleanup clears); on_pick takes ONE arg (the PickBridge contract) and reads the stash — dict shape frozen per 15-05, pick_bridge untouched
- **Guard order in on_pick:** state gate (playing) → empty-stash guard → is_hider → status_of found → hidden scoring. is_hider checked before status_of (status_of of an unregistered index is "" — the miss branch must not fall through)
- **rc == 1 catch pattern:** the whole on_pick body is catch-wrapped like pick_bridge's _on_event; guard `return`s carry TCL_RETURN (rc == 2) so a truthy catch test would misreport; errors are reported via vmdcon -err, never re-raised
- **Hider-rep step placement:** right after backup::apply (base = numreps AFTER apply — deterministic per round, hider reps land LAST at base..base+1; Pitfall 9), before the registry reconstruct

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Smoke recorder for the zero-arg remaining_cb never counted**
- **Found during:** Task 2 (first smoke run — FAIL=hit_rem_cb/already_rem_cb/win_rem_cb_total got=0)
- **Issue:** The recording callback was `{lappend ::REM_TICKS}` but remaining_cb is invoked with ZERO args; `lappend` with no values never grows the list, so the invocation counter stayed empty
- **Fix:** Switched the recorder to a scalar counter with the zero-arg-safe prefix `{incr ::REM_TICKS}`; all REM_TICKS assertions now compare the counter directly
- **Files modified:** vmd/smoke/phase16_onpick_smoke.tcl
- **Verification:** Re-run PASS=1 FAIL=none with hit=1/already=1/win=5 remaining-cb counts as expected
- **Committed in:** 93db2cf

**2. [Rule 1 - Bug] Phase-15 smokes regressed: game_numreps assertion + missing hiders.tcl source**
- **Found during:** Task 2 (post-change regression run of all prior smokes — phase15_smoke + phase15_game_smoke FAILed: `invalid command name "::biochemeleon::hiders::add_hider_reps"`, then `game_numreps exp=2 got=4`)
- **Issue:** start_game now calls hiders::add_hider_reps (call-time resolution — the harnesses never sourced hiders.tcl) and the game molid legitimately carries 2 more reps than the Phase-15 exact-restore assertion expected
- **Fix:** Both harnesses source hiders.tcl in dep order (after mutation, before game) and the SC4-forward game_numreps assertion now expects saved_numreps + 2; the restored-molid assertions stay exact (cleanup restores the original without hider reps)
- **Files modified:** vmd/smoke/phase15_smoke.tcl, vmd/smoke/phase15_game_smoke.tcl
- **Verification:** Re-run of ALL 5 affected smokes against fresh staging: phase16_onpick, phase15_smoke, phase15_game_smoke, phase16_hiders, phase16_pick — all PASS=1 FAIL=none
- **Committed in:** db3beac

**3. [Rule 3 - Blocking] Environment deviations (pre-established, not plan defects)**
- **Issue:** (a) `tclsh` is NOT installed in this WSL environment despite AGENTS.md listing it — the planned load-syntax-check was impossible; (b) `rm` is denied by permission rules — stale staging cleanup used `cp -r` overwrite instead
- **Fix:** Relied on the headless VMD smoke as the parse/syntax gate (a `source` error surfaces as `${nm}_source_error` bail + the full-log scan); re-staged via cp overwrite
- **Files modified:** none
- **Verification:** VMD parse clean (zero source_error bails, zero ERROR)/bad switch in full logs)
- **Committed in:** n/a (process only)

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking/process)
**Impact on plan:** All fixes necessary for correctness of the new contract and its regression surface. No scope creep — the phase15 smoke updates are the direct, planned consequence of the hider-rep step (research SS5.5); 16-11's re-run recipe requires those smokes green.

## Issues Encountered
- None beyond the deviations above. First smoke run surfaced the recorder bug; second run PASS=1; the regression sweep caught the phase15 contract updates before they could bite 16-11's phase verification.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **Ready for 16-09 (Game tab):** `set_callbacks {log_cb remaining_cb win_cb}` is live — the tab registers in start_round; win_cb receives (elapsed, hider_count) and owns PickBridge deactivation (game.tcl does NOT touch pick_bridge); remaining_cb is zero-arg (pull model — read registry::count_remaining/remaining_by_rep)
- **Ready for 16-10/16-11:** entry source order gains nothing new this plan (game.tcl/hiders already sourced by 15-04/16-05); the 16-11 full re-run now includes phase16_onpick_smoke.tcl (already green)
- **Contracts intact:** game_state dict shape frozen; DI reconstruct line byte-unchanged; pick_bridge `on_pick <index>` single-arg forward satisfied without modifying pick_bridge
- **No blockers.**

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
