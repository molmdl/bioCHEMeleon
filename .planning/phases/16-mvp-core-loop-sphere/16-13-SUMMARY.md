---
phase: 16-mvp-core-loop-sphere
plan: 13
subsystem: game-controller
tags: [vmd, tcl85, game-loop, guard, molid-liveness, cleanup, auto-restart, gap-closure]

# Dependency graph
requires:
  - phase: 15-mutation-safety
    provides: game.tcl composition root (start_game/cleanup/restart + current_state stash), backup.tcl 2-arg restore contract (restore takes the LIVE game_molid), molids-monotonic/never-reused property
  - phase: 16-mvp-core-loop-sphere (16-01..16-12)
    provides: current_state stash shape {game_molid hider_count snapshot} (frozen per 15-05), dialog.tcl on_start path, 16-VERIFICATION.md gap 1 (Truth 7 FAILED — no active-game guard)
provides:
  - Self-guarding game::start_game: active/prior round is cleaned up first (auto-restart with the CALLER's new settings) at the single choke point both console and UI (on_start) paths share — stacked hider generations structurally impossible
  - Stale-stash resilience: catch branch re-does registry::reset + stash clear when cleanup's backup::restore errors on an externally-deleted game molecule
  - Liveness-based target remap: Start on the (now-dead) previous game molecule proceeds on the restored original; a live different target passes through unchanged
affects: [16-15 (regression smoke proves the behavior), 16-14/16-16/16-17 (sibling gap plans), phase-16 re-verification, Phase 19 (Restart/Cleanup buttons build on cleanup/restart semantics)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Self-guarding entry point: choke-point guard (dict size on the namespace stash) + cleanup-then-fresh-start + liveness-based molid remap (molinfo get numatoms in catch) — never molid equality (molids are monotonic)"
    - "Guard/catch-branch state repair: on mid-cleanup error, re-do registry::reset + stash clear so no ghost state leaks into the new round"

key-files:
  created: []
  modified:
    - vmd/lib/game.tcl (active-game guard at the top of start_game + doc-comment SELF-GUARDING section)

key-decisions:
  - "Auto-restart semantics, NOT restart's same-count semantics: the guard cleans the old round then starts fresh with THIS call's molid+hider_count (the user pressed Start with the CURRENT Setup form); restart {game_state} stays Phase 19's same-count Restart-button behavior"
  - "Target remap by LIVENESS (molinfo ... get numatoms in catch), not molid equality — molids are monotonic and never reused (research PROBE6), so the restored original never collides with the old game molid"
  - "hider_count passes through UNclamped in the remap branch: pass-through matches restart's own semantics; validate_state in on_start already clamped it against the user-selected target"
  - "cleanup stays the ONLY cleanup mechanism (owns the 2-arg restore contract + registry::reset + stash clear); the guard's catch branch re-does reset+clear ONLY because a mid-cleanup error skips them"

patterns-established:
  - "ACTIVE-GAME GUARD block: single-choke-point idempotent-start guard, reusable pattern for any future start-ish entry point"

# Metrics
duration: 8 min
completed: 2026-08-30
---

# Phase 16 Plan 13: Active-Game Guard (Gap Closure) Summary

**start_game is now self-guarding: a Start during/after a round auto-cleans the old round at the single console+UI choke point (liveness-based molid remap, stale-stash ghost-state clearing) — stacked hider generations (the observed 561-atom/Segments-3 defect) are structurally impossible**

## Performance

- **Duration:** 8 min
- **Started:** 2026-08-30T15:46:18Z
- **Completed:** 2026-08-30T15:54:05Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- VERIFICATION gap 1's code half closed at the controller level: the ACTIVE-GAME GUARD sits at the very top of `game::start_game` (before the step-1 `backup::snapshot`), the single choke point BOTH the console path and `dialog.tcl on_start` go through — re-running the observed defect sequence (start → win → start again on the same game molecule) can no longer stack generations
- Stale stash (game molecule deleted externally) cannot corrupt a new round: the guard's catch branch re-does `registry::reset` + stash clear; a live different target passes through; a fully-dead situation degrades to on_start's existing "Could not start the game" error — never corruption
- All frozen contracts byte-unchanged: 2-arg restore contract (cleanup still owns it), DI line `[list apply {{molid} {...}} $game_molid]`, game_state dict shape, namespace exports, steps 1-6 ordering

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the active-game guard to start_game** - `95a7de4` (feat)

**Plan metadata:** (this commit)

_Note: not a TDD plan (deliberate, per plan context: the pure part is a one-line `dict size` check already covered by the on_pick stash-guard pattern; the real risk is molid liveness, only provable with live VMD molecules)._

## Files Created/Modified

- `vmd/lib/game.tcl` - ACTIVE-GAME GUARD block (58 lines incl. doc-comment SELF-GUARDING section + ordering note): cleanup-then-fresh-start with liveness-based target remap and stale-stash catch repair

## Verification (this plan's gates + local de-risking)

All six structural gates green:

1. 8.5-idiom gate (`lmap|try|throw|tailcall|coroutine|yield|finally`): **0 matches**
2. `game.tcl` still sources NOTHING (`^\s*source\b`): **0**
3. Guard lines (93, 102) strictly BEFORE the snapshot line (138)
4. `list apply` count: **2** (see Deviations — pre-existing comment + code pair; DI line proven byte-identical, md5 match)
5. `namespace export start_game cleanup restart on_pick set_callbacks`: **unchanged**
6. `cleanup $old_gs` (105) + `registry::reset` (guard branch 110; cleanup's own pre-existing 186): **both present**

Local headless de-risking (staged copy `tmp/exec-16-13/`, gitignored; BCHM_SMOKE_RESULT marker + full-log `ERROR)`/`bad switch` scan, both clean):

- **Ad-hoc guard probe** (`tmp/exec-16-13/guard_probe.tcl`, NOT a repo smoke): **PASS=1 FAIL=none**, 0 ERROR) — path A round-1 no-op (426 atoms/2 sentinels); path B double-start ON the game molecule → **427 atoms (NOT 429 stacked), exactly 3 sentinels, registry 3, old molid deleted, stash = new round** (remap INFO line fired); path C different live target → 557 atoms/2 sentinels, old m2 deleted (pass-through, no remap — correct); path D stale stash (external `mol delete`) → fresh round succeeds on the live requested target, stash = new round
- **Existing smokes stay green with the guard** (no-op path): `phase15_game_smoke.tcl` PASS=1 FAIL=none; `phase16_onpick_smoke.tcl` PASS=1 FAIL=none
- Behavioral proof at phase level is **delegated to 16-15's regression smoke** (parallel wave: `phase16_restart_smoke.tcl` — double-start mid-round, double-start after-win, different-target restart), plus the GUI re-check in VERIFICATION.md §"Human Verification Required" item 5

## Decisions Made

- Auto-restart with the CALLER's new settings (not the old round's hider_count) — restart {game_state} remains Phase 19's same-count Restart semantics (pre-decided by the plan; transcribed)
- Liveness-based remap (`molinfo ... get numatoms` in catch), never molid equality — molids monotonic/never reused (pre-decided; probe confirmed the remap branch fires exactly when the target was the old game molecule)
- See STATE.md dated entry for the gate-4 interpretation decision (below)

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written (guard transcribed verbatim; no additional work discovered).

### Plan-expectation note (not a code deviation)

**1. Verify gate 4's literal expectation ("`grep -c "list apply"` → 1") was miscounted in the plan**

- **Found during:** Task 1 verification
- **Issue:** `vmd/lib/game.tcl` already contained 2 occurrences of "list apply" on HEAD — the CRITICAL doc-comment (`# CRITICAL: [list apply {lambda} $game_molid] is a COMMAND-PREFIX VALUE...`) plus the actual DI code line. The gate's substantive intent is "DI line byte-unchanged / no new occurrences", which cannot be read off a count of 1.
- **Resolution:** No code change (forcing a count of 1 would have meant deleting the CRITICAL warning comment — the wrong move). Instead proved the intent directly: count unchanged (2 → 2) AND the DI line itself md5-identical between HEAD and the working tree (`diff` + `md5sum` match).
- **Files modified:** none (verification-interpretation only)
- **Why it matters downstream:** 16-15's regression sweep / phase re-verification greps should expect 2 and assert the DI line byte-identity, not a count of 1.

---

**Total deviations:** 0 auto-fixed; 1 plan-expectation note (verification interpretation, no code impact)
**Impact on plan:** None — all gates' substantive intents hold; behavior proven locally and handed to 16-15 for the formal regression smoke.

## Issues Encountered

None. (The stale-stash probe path produced zero `ERROR)` lines — the guard's catch swallowed cleanup's restore error as designed.)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Gap 1's code half is closed; sibling gap plans 16-14..16-17 (parallel wave) close the remaining verification gaps; **16-15** delivers the formal regression smoke (`phase16_restart_smoke.tcl`) asserting atom count = original + N, exactly N sentinels, registry N, old game molid deleted for double-start mid-round / after-win / different-target
- Phase 19 (Game-tab Cleanup/Restart buttons) builds directly on `cleanup`/`restart` — the guard deliberately does NOT reuse `restart` (same-count semantics); Phase 19's Restart button should call `restart {game_state}` as planned
- Remaining GUI re-checks after the wave lands: VERIFICATION.md items 1-5 (pick-contract A/B, PICK capture, freeze repro, pv_cleanup restore, double-Start guard re-check)

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
