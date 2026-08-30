---
phase: 16-mvp-core-loop-sphere
plan: 12
subsystem: testing
tags: [vmd, tcl, picking, trace, human-verify, pick-bridge, vmd-1.9.3, gui-checkpoint]

# Dependency graph
requires:
  - phase: 15-mutation-safety
    provides: game.tcl composition root (start_game/cleanup), registry, backup/restore — the machinery the GUI round exercised
  - phase: 16-mvp-core-loop-sphere (16-01..16-11)
    provides: pick_bridge.tcl mechanism, game_tab/dialog GUI, hiders, game_logic — everything the checkpoint verified
provides:
  - GUI-locked (LOCKED-WITH-CAVEATS) VMD pick contract recorded in 16-VERIFICATION.md
  - Re-verify-ready pick_verify.tcl (paste-safe two-paste observer, callback A/B test, pv_cleanup console helper)
  - Updated vmd/AGENTS.md picking contract (MEDIUM flag removed) + STATE.md decision entry
  - Registered defect list for the phase verifier / gap-closure planning
affects: [16 phase verifier, gap-closure planning, Phase 19 cleanup/restart, pick_bridge mechanism decision]

# Tech tracking
tech-stack:
  added: [] # none — plan is docs + test-driver fixes only
  patterns:
    - "Two-paste console helpers for human GUI-verify sessions (every printed line < ~70 cols; no bracketed substitutions in paste instructions — terminal wraps split them silently)"
    - "Catch-guarded debug observers (print ? instead of erroring) so a missing global can never swallow the output a human is asked to record"
    - "Verify-script console fallbacks for not-yet-built UI (pv_cleanup stands in for the Phase-19 Cleanup button)"

key-files:
  created:
    - .planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md
    - .planning/phases/16-mvp-core-loop-sphere/16-12-SUMMARY.md
  modified:
    - vmd/tests/pick_verify.tcl
    - vmd/AGENTS.md
    - .planning/STATE.md

key-decisions:
  - "Pick contract LOCKED-WITH-CAVEATS: trace mechanism KEPT as primary — a complete round was WON through it in the real GUI session; step-2's capture failure was a paste artifact, not a mechanism failure"
  - "Labelpoll fallback KEPT dormant — its premise (every pick-atom click creates a detectable label) was GUI-confirmed"
  - "NO mechanism flip: evidence insufficient to demote the trace"
  - "`mouse callback on` NOT added to pick_bridge yet — leading hypothesis (finds correlated with `User Pick:` output) is unconfirmed; the re-verify A/B test (new STEP 4) decides first"
  - "Step 9c re-scoped to a console helper (pv_cleanup) — the Game-tab Cleanup button the script referenced does not exist until Phase 19"

patterns-established:
  - "Two-paste observer form for Tk-console capture (proc block + short registration line)"
  - "pv_* console helpers as the MVP-era path for game lifecycle ops awaiting their Phase-19 buttons"

# Metrics
duration: 25min
completed: 2026-08-30
---

# Phase 16 Plan 12: GUI Pick-Contract Verification Summary

**Pick contract locked-WITH-CAVEATS via a real VMD GUI session: trace-primary retained (a full round was won through it), step-2 capture fixed for re-verify (paste-safe observer, callback A/B test, console cleanup helper), and all session defects registered for the verifier/gap closure.**

## Checkpoint Outcome (front and center)

The GUI human-verify checkpoint returned a **MIXED verdict — LOCKED-WITH-CAVEATS, not a clean pass**:

- **What held up:** a complete game round was WON end-to-end through the game's own trace delivery (win box, timer frozen 5:14, remaining 0, labels auto-cleaned, mouse restored to saved rotate/-1). Steps 1, 6, 7, 8, 9a, 9b PASS.
- **What is unresolved:** C-side pick-event firing showed mode-desync flakiness (label-only clicks until keyboard re-arm; finds correlated with `User Pick:` output ⇒ `mouse callback` on; `Illegal mouse mode: 0 -1`; fresh restart cleared it). Step 2 (exact PICK values) was INCONCLUSIVE — the pasted observer one-liner was broken by a terminal wrap, NOT a disproof. One VMD freeze at session end (unresolved). Steps 3/5 PARTIAL.
- **What was blocked:** step 9c — the script told the human to press a Cleanup button that does not exist in the MVP (Phase 19 scope).
- **Disposition:** trace mechanism RETAINED as primary; labelpoll premise CONFIRMED (kept dormant); phantom callbacks-list falsified; `mouse callback on` NOT added to pick_bridge pending the re-verify A/B test. Full record: `16-VERIFICATION.md`.

## Performance

- **Duration:** 25 min (continuation session: Task 1 pre-completed in the prior segment; this segment = checkpoint verdict processing + Tasks A–D)
- **Started:** 2026-08-30T13:24:29Z
- **Completed:** 2026-08-30T13:49:56Z
- **Tasks:** 4/4 (A, B, C, D — after Task 1 + the Task-2 checkpoint in the prior segment)
- **Files modified:** 5 (1 created verification record, 1 created summary, 1 test driver, 2 docs)

## Accomplishments

- Honest human checkpoint record written (all 9 step verdicts with observed values, verbatim feedback, decisive log excerpts, open questions, defects, keep-vs-delete decisions)
- Verify driver made re-verify-ready: two-paste paste-safe observer (`pv_observe`), explicit `mouse callback` off/on A/B test (`pv_callback_state`), `pv_cleanup` console helper + `pv_state` game_state stash; headless guard still a clean no-op
- `vmd/AGENTS.md` picking section upgraded from MEDIUM-confidence to the LOCKED-WITH-CAVEATS contract (wrong facts from the pre-research section also corrected: pick 0 = query, callbacks list = phantom, hotkey 1 = pick atom)
- STATE.md decision entry captures the verdict, caveats, re-verify plan, and registered defects for the phase verifier

## Task Commits

Each task was committed atomically:

1. **Task 1: staged GUI pick-verify driver (prior segment)** - `1e57bf2` (test)
2. **Task 2: GUI checkpoint (prior segment)** — returned the mixed verdict processed by this segment
3. **Task A: record GUI checkpoint verdict** - `035ad54` (docs)
4. **Task B: re-verify-ready driver fixes** - `4470202` (test)
5. **Task C: AGENTS.md/STATE locked pick contract** - `6df180d` (docs)

**Plan metadata:** _this commit_ (docs: complete plan)

## Files Created/Modified

- `.planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md` — the human checkpoint record (verdict table, feedback, excerpts, open questions, defects, keep-vs-delete)
- `vmd/tests/pick_verify.tcl` — paste-safe two-paste observer, callback A/B test, pv_cleanup helper, pv_state stash; headless guard re-verified clean and re-staged to `tmp/biochemeleon-vmd/`
- `vmd/AGENTS.md` — picking section: LOCKED-WITH-CAVEATS contract + Phase-19 note (MEDIUM flag removed)
- `.planning/STATE.md` — one dated decision entry (Current Position intentionally untouched; the phase verifier owns the roll-up)
- `.planning/phases/16-mvp-core-loop-sphere/16-12-SUMMARY.md` — this file

## Decisions Made

- **Trace mechanism KEPT primary** — a full round was won through it; the step-2 capture failure was a paste artifact (newline inside a bracketed substitution from a terminal wrap), not a mechanism failure
- **Labelpoll KEPT dormant** — premise GUI-confirmed; cheap insurance
- **NO mechanism flip** — evidence insufficient
- **`mouse callback on` NOT added to pick_bridge** — hypothesis unconfirmed; re-verify A/B (STEP 4) decides, then the mechanism is touched
- **Step 9c re-scoped to `pv_cleanup`** — no Cleanup button exists until Phase 19; the console helper (pick_bridge::deactivate + game::cleanup with the stashed game_state) is the MVP-era path
- **Scope discipline:** no mechanism/code changes to pick_bridge.tcl, game.tcl, dialog.tcl, or setup_tab.tcl — the session's defects are registered for gap-closure planning, not fixed here

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, prior segment] Top-level `return` guard insufficient under `vmd -e`**

- **Found during:** Task 1 (staging the verify driver)
- **Issue:** under `vmd -e` each top-level command is evaluated independently, so a top-level `return` ends only that command and the rest of the file still ran (the step guide printed headless)
- **Fix:** wrapped the whole body in `if {[info exists ::tk_version]} {...}` — one single command in both evaluation modes
- **Committed in:** `1e57bf2`

**2. [Rule 3 - Blocking, prior segment] `[info script]` is empty under `vmd -e`**

- **Found during:** Task 1
- **Issue:** entry-resolution via `[info script]` returned "" under `vmd -e`, breaking the auto-source path
- **Fix:** trust `[info script]` only when non-empty; fall back to cwd-relative `vmd/biochemeleon.tcl`
- **Committed in:** `1e57bf2`

**3. [Rule 1 - Bug, this segment] Session-1 observer one-liner was wrap-fragile (the step-2 INCONCLUSIVE root cause)**

- **Found during:** Task B (from the checkpoint verdict)
- **Issue:** the printed one-liner's `[info exists ...]` was split by a terminal wrap during copy → the apply body errored on every fire → output silently swallowed → step 2 unrecordable
- **Fix:** two-paste form — multi-line `pv_observe` proc (every printed line < ~70 cols) + one short registration line; observer catch-guards each value (prints `?` instead of erroring); prose line with literal brackets reworded
- **Files modified:** vmd/tests/pick_verify.tcl
- **Verification:** headless guard run clean (EXIT=0, GUI-only warning, zero ERROR/bad-switch), re-staged
- **Committed in:** `4470202`

**4. [Rule 2 - Missing Critical, this segment] Step 9c referenced a nonexistent Cleanup button**

- **Found during:** Task B (from the checkpoint verdict — "c no such button exists")
- **Issue:** the script instructed the human to press a Game-tab Cleanup button that arrives in Phase 19; the restore path was untestable
- **Fix:** `pv_cleanup` console helper (pick_bridge::deactivate first per research §2.5, then game::cleanup with the game_state `pv_state` stashes at Start, game_tab fallback, idempotent messages) + step text notes Phase 19 owns the real button
- **Committed in:** `4470202`

**5. [Rule 2 - Missing Critical, this segment] Callback-state visibility for the A/B test**

- **Found during:** Task B
- **Issue:** UG 9.3.23 documents only `callback on/off` (no query form), so the session-1 flakiness had no recorded state to correlate against
- **Fix:** `pv_callback_state` helper (query attempt is belt-and-suspenders and explicitly NOT load-bearing — the A/B sets the state before each click, which is what makes it valid)
- **Committed in:** `4470202`

---

**Total deviations:** 5 auto-fixed (3 bug, 2 missing-critical; 2 from the prior segment, 3 from this one)
**Impact on plan:** all fixes serve the correctness/safety of the human-verification instrument itself. No scope creep — no mechanism or game-code files touched.

## Issues Encountered

These are **registered defects from the GUI session** — inputs for the phase verifier and gap-closure planning (NOT fixed in this plan, by design):

1. **Double-start stacking:** `start_game` has no active-game guard — after a won round with no Cleanup available, Start again ran on the still-loaded GAME molecule (558 atoms) → 561-atom combined PDB, stacked sentinels, `Segments: 3`, two hider generations (555-559)
2. **C-side firing flakiness / callback hypothesis:** finds correlated with `User Pick:` output (`mouse callback` on); label-only clicks until keyboard `p` re-arm; `Illegal mouse mode: 0 -1` before working picks; fresh restart cleared it — re-verify A/B test (STEP 4) decides whether pick_bridge gains `mouse callback on`
3. **End-of-session freeze (unresolved):** VMD froze after the won round + pv_state + labelatom clicks with the bridge inactive; a clean standard-gameplay session exited fine — flag for the re-verify session, do not speculate as fact
4. **Setup-Reset expectation mismatch:** Setup-tab Reset clears setup fields only, not hiders ("after a succeful gameplay, reset does not clear hider")
5. **Checkbox desync (minor UX):** hotkey `r` rotates but the Game-tab checkbox stays "Pick" — pick_bridge does not observe hotkey-driven mode changes
6. **Game tab has no Cleanup/Restart buttons** (Phase 19 scope) — until then cleanup is console-only

## User Setup Required

None — no external service configuration required. (Human follow-up: one targeted re-verify GUI session using the fixed `vmd/tests/pick_verify.tcl`, ~10 min, when scheduled.)

## Next Phase Readiness

- **Pick contract:** locked-with-caveats and durable (16-VERIFICATION.md + AGENTS.md + STATE.md) — the phase verifier can roll Phase 16 up with the caveats attached
- **Re-verify driver:** ready at `vmd/tests/pick_verify.tcl` (staged and headless-guard-clean); decides the callback hypothesis, captures exact PICK values, probes the freeze, and exercises restore via `pv_cleanup`
- **Gap-closure backlog:** the six registered defects above (active-game guard, Setup-Reset semantics, Cleanup/Restart buttons in Phase 19, checkbox sync, callback fix decision, freeze)
- **No blockers to Phase 17** (rep generators) — the pick contract caveats affect firing reliability, not rep generation; the mechanism decision point (labelpoll vs trace vs callback-on) is isolated inside pick_bridge

---
*Phase: 16-mvp-core-loop-sphere*
*Completed: 2026-08-30*
