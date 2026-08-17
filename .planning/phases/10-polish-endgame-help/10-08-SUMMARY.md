---
phase: 10-polish-endgame-help
plan: 08
subsystem: testing
tags: [pymol, cmd, headless, smoke, debrief, diff-03, fragment-aware, cartoon, endpoint_resvs, pick_segments]

# Dependency graph
requires:
  - phase: 10 (Plan 10-06 — _show_all_hiders_for_debrief in gui_game.py)
    provides: "The fragment-aware cmd.show loop the smoke inlines: per rec, skip rep=None, fragment by segi GAME and resi rv1-rv2 (cartoon/ribbon 4-tuple, endpoint_resvs set), single-atom by id. The Qt method itself CANNOT run headlessly (Qt needs a real display) so the smoke reproduces the loop body verbatim."
  - phase: 11 (pick_segments + generate_middle_displacement + endpoint_resvs on HiderRecord)
    provides: "The Phase 11 single-state 4-tuple cartoon path the smoke exercises: generators.pick_segments for the mid-chain segment + generate_middle_displacement for the rigid bump; game.start registers endpoint_resvs via mutation.cartoon_hider_resi_range (the NEW resi range the fragment-aware show scopes)."
  - phase: 03 (registry.HiderRegistry.all() + counts_by_rep() + HiderRecord.endpoint_resvs + HIDER_STATUS_FOUND)
    provides: "registry.all() for the debrief show loop iteration; counts_by_rep() (zero-filled GAME_REPS) for the start assertion; HiderRecord.endpoint_resvs (2-tuple or None) for the fragment-aware branch; HIDER_STATUS_FOUND for the mark-all assertion."
provides:
  - "smoke/phase10_smoke.py (NEW, 127 lines) — pure pymol.cmd.* headless smoke verifying the cmd-layer debrief show path (the fragment-aware cmd.show loop Plan 10-06's _show_all_hiders_for_debrief runs). NO Qt (headless-runnable via cmd.exe /c run-conda-pymol.bat -cq)."
  - "Headless verification that the fragment-aware show loop makes every hider visible in its own rep: spheres (>=2 GAME atoms in spheres rep), sticks (>=1 in sticks rep), cartoon (>=1 in cartoon rep)."
  - "Headless verification that the cartoon fragment FULL rv1-rv2 range is shown (>=3 atoms in the range) AND the MIDDLE rv1+1-rv2-1 is shown (>=1 atom) — a naive by-id-only show would leave the support-residue + displaced-middle atoms hidden."
  - "Headless verification that cleanup restores the original (verify_intact True + count back to orig + no GAME atoms remain) — the debrief highlight is temporary."
affects: [10-09 (human-verify checkpoint: the Qt win + debrief QMessageBox flow + 100ms redraw delay + cleanup gate timing for non-imported vs imported — the cmd-layer show path this smoke verifies is the load-bearing dependency)]

# Tech tracking
tech-stack:
  added: []  # no new libs — pure pymol.cmd.* smoke
  patterns:
    - "Headless smoke of a Qt-coupled cmd-layer path: inline the cmd-layer loop body (NOT the Qt method call) so the smoke runs headlessly while still verifying the EXACT logic the Qt method runs. The smoke reproduces _show_all_hiders_for_debrief's loop verbatim (per rec, skip rep=None, fragment by endpoint_resvs -> segi GAME and resi rv1-rv2, single-atom by id). Mirrors phase4_1_smoke (per-rep remaining READ path) + phase6_smoke (hint/reveal mechanics) + phase7_smoke (found-mgmt cmd paths)."
    - "Cartoon 4-tuple path smoke pattern: generators.pick_segments(cas_by_chain, 1) for ONE disjoint mid-chain segment + generators.generate_middle_displacement(len(segments)) for the rigid bump vector; hider_spec = ((chain, start_resi, end_resi, disp), 'cartoon') routes to insert_cartoon_segment_hider via insert_hider_for_rep; endpoint_resvs is registered via mutation.cartoon_hider_resi_range(start_resi, end_resi). This is the production Phase 11 path (NOT the legacy 3-tuple terminal-extension), so the fragment-aware show branch IS exercised."

key-files:
  created:
    - smoke/phase10_smoke.py  # 127 lines, pure pymol.cmd.*, NO Qt
  modified: []

key-decisions:
  - "The smoke INLINES the fragment-aware cmd.show loop from Plan 10-06's _show_all_hiders_for_debrief (NOT a call to the Qt method). Rationale: the method lives on GameTab (gui_game.py) which requires Qt (pymol.Qt.QtWidgets) — a Qt import at smoke runtime would fail headlessly (AGENTS.md: headless path cannot run Qt). Inlining the loop body verbatim verifies the EXACT logic the Qt method runs without pulling Qt into the smoke. This is the established headless-smoke-of-Qt-coupled-path pattern (phase4_1_smoke inlines remaining_by_rep READ path; phase6_smoke inlines hint/reveal mechanics; phase7_smoke inlines found-mgmt cmd paths)."
  - "The cartoon 4-tuple path (pick_segments + generate_middle_displacement) is the production Phase 11 path (NOT the legacy 3-tuple terminal-extension from phase4_1_smoke). Rationale: the 4-tuple path sets endpoint_resvs (via mutation.cartoon_hider_resi_range), which is the trigger for the fragment-aware show branch — the legacy 3-tuple path leaves endpoint_resvs=None (by-id show), so it would NOT exercise the fragment-awareness the debrief depends on. The smoke MUST use the 4-tuple path to prove the debrief show works for the production cartoon hider shape."
  - "The MIDDLE (rv1+1-rv2-1) assertion is the KEY check. Rationale: a naive by-id-only show (the legacy single-atom path) would show ONLY the anchor CA id, leaving the support-residue + displaced-middle atoms hidden (if the player used 'Hide found' mid-game). The fragment-aware loop scopes the FULL rv1-rv2 range (endpoints included — they're part of the blend) so the whole blend re-renders. The middle-only check (rv1+1-rv2-1) specifically proves the fragment-aware path ran — a by-id-only show would leave middle_shown == 0."
  - "The smoke hides ALL GAME atoms (cmd.hide 'everything' segi GAME) BEFORE running the debrief show loop. Rationale: this simulates the 'Hide found' mid-game scenario where the player hid found hiders — the debrief show must RE-SHOW them. Without the pre-hide, the show loop would be a no-op (atoms already visible from the start-time cmd.show) and the assertions would pass trivially without proving the show loop actually works. The pre-hide + show + assert-visible pattern is the canonical 'show loop works' verification."
  - "1 Rule-3 deviation: reworded the header comment from 'win + debrief QMessageBox' to 'win + debrief' to avoid the Qt grep false-positive. The plan's verbatim comment contained the literal 'QMessageBox' token which tripped the 0-hits verification gate (grep -nE 'from pymol.Qt|QtWidgets|QMessageBox|QDialog'). This is exactly the AGENTS.md-warned pattern ('literal tokens in comments/docstrings trip this grep too — we hit a false positive on a docstring that said from PyQt5 import'). Mirrors the 03-03/03-06/03-10/08-01/08-02/10-06 docstring-rewording precedent."

patterns-established:
  - "Headless smoke of a Qt-coupled endgame cmd path: inline the cmd-layer loop body the Qt method runs, pre-hide to prove the show works, assert per-rep + fragment-range + cleanup. Reusable for any future 'show all hiders' endgame verification (e.g. a debug inspector, a replay feature)."
  - "4-tuple cartoon smoke setup: pick_segments(1) + generate_middle_displacement(len(segments)) + hider_spec 4-tuple -> endpoint_resvs registered -> fragment-aware branch exercised. The 3-tuple legacy path is backward-compat-only (phase4_1_smoke); new Phase 10+ smokes should use the 4-tuple path to test the production cartoon shape."

# Metrics
duration: 12min
completed: 2026-08-18
---

# Phase 10 Plan 08: Headless Smoke for Debrief Fragment-Aware Show Path Summary

**Headless smoke verifying the cmd-layer debrief show path (fragment-aware cmd.show loop inlined from _show_all_hiders_for_debrief) — 15/15 ALL PASSED, cartoon fragment FULL rv1-rv2 range + MIDDLE rv1+1-rv2-1 shown (the by-id-only regression the loop prevents)**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-08-17T19:47:16Z (2026-08-18 03:47:16 +0800)
- **Completed:** 2026-08-17T19:58:59Z (2026-08-18 03:58:59 +0800)
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments
- Created `smoke/phase10_smoke.py` (127 lines, pure `pymol.cmd.*`, NO Qt — headless-runnable). The smoke verifies the cmd-layer debrief show path (DIFF-03) that Plan 10-06's `_show_all_hiders_for_debrief` runs. The Qt dialogs (win + debrief QMessageBox), the 100ms redraw delay, and the cleanup gate are deferred to the human-verify checkpoint (Plan 10-09) — the smoke verifies ONLY the `cmd.show` logic the debrief depends on.
- 7 sections modeled on `smoke/phase4_1_smoke.py` (mixed-rep game setup) + `smoke/phase6_smoke.py` (RESULTS + check pattern): SETUP (fetch 1ubq + orig count) → START MIXED-REP (2 spheres + 1 stick + 1 cartoon 4-tuple segment via `pick_segments` + `generate_middle_displacement` — the Phase 11 production path, NOT the legacy 3-tuple) → MARK ALL FOUND (so the debrief show applies to found hiders) → DEBRIEF SHOW (inline the fragment-aware `cmd.show` loop: hide all GAME atoms first to simulate 'Hide found', then per rec skip rep=None, fragment by `segi GAME and resi rv1-rv2` for cartoon/ribbon, single-atom by `id N`) → ASSERT per-rep shown → ASSERT cartoon fragment FULL rv1-rv2 range + MIDDLE rv1+1-rv2-1 shown → CLEANUP.
- Headless run via `cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase10_smoke.py"`: **15/15 ALL PASSED, exit 0** (first run clean, no iterations needed).
- KEY assertion verified: the cartoon fragment FULL rv1-rv2 range is shown (>=3 atoms in the range) AND the MIDDLE (rv1+1-rv2-1) is shown (>=1 atom). A naive by-id-only show would leave the support-residue + displaced-middle atoms hidden (the bump the player is supposed to see in the debrief); the fragment-aware loop scopes the full range so the whole blend re-renders.
- Cleanup regression-tested: `gc.cleanup()` returns True (verify_intact), count back to orig, no GAME atoms remain — the debrief highlight is temporary and cleanup restores the original.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create smoke/phase10_smoke.py — headless verification of the debrief cmd.show path** - `934e28d` (test)

**Plan metadata:** (pending — final docs commit at end of execution)

## Files Created/Modified
- `smoke/phase10_smoke.py` (NEW, 127 lines) — pure `pymol.cmd.*` headless smoke. 7 sections + 15 checks. Inlines the fragment-aware `cmd.show` loop from Plan 10-06's `_show_all_hiders_for_debrief` (per rec: skip rep=None, `endpoint_resvs` set -> `cmd.show(rec.rep, "%s and segi GAME and resi %d-%d" % (obj, rv1, rv2))`, else -> `cmd.show(rec.rep, "%s and id %d" % (obj, rec.id))`). Builds a mixed-rep game via the Phase 11 4-tuple cartoon path (`pick_segments` + `generate_middle_displacement`). Headless run 15/15 ALL PASSED, exit 0.

## Decisions Made
- **Inline the cmd.show loop (NOT a call to _show_all_hiders_for_debrief):** the Qt method lives on GameTab (gui_game.py) which imports `pymol.Qt.QtWidgets` — a Qt import at smoke runtime would fail headlessly (AGENTS.md: headless path cannot run Qt). Inlining the loop body verbatim verifies the EXACT logic the Qt method runs without pulling Qt into the smoke. Established pattern (phase4_1_smoke / phase6_smoke / phase7_smoke).
- **Use the Phase 11 4-tuple cartoon path (NOT the legacy 3-tuple terminal-extension):** the 4-tuple path sets `endpoint_resvs` (via `mutation.cartoon_hider_resi_range`), which is the trigger for the fragment-aware show branch. The legacy 3-tuple path leaves `endpoint_resvs=None` (by-id show), so it would NOT exercise the fragment-awareness the debrief depends on. The smoke MUST use the 4-tuple path to prove the debrief show works for the production cartoon hider shape. The 4-tuple path is `((chain, start_resi, end_resi, disp), 'cartoon')` routed to `insert_cartoon_segment_hider` via `insert_hider_for_rep`.
- **Pre-hide ALL GAME atoms before the debrief show loop:** simulates the 'Hide found' mid-game scenario where the player hid found hiders — the debrief show must RE-SHOW them. Without the pre-hide, the show loop would be a no-op (atoms already visible from the start-time `cmd.show`) and the assertions would pass trivially without proving the show loop actually works. The pre-hide + show + assert-visible pattern is the canonical 'show loop works' verification.
- **The MIDDLE (rv1+1-rv2-1) assertion is the KEY check:** a naive by-id-only show (the legacy single-atom path) would show ONLY the anchor CA id, leaving the support-residue + displaced-middle atoms hidden. The fragment-aware loop scopes the FULL rv1-rv2 range (endpoints included — they're part of the blend) so the whole blend re-renders. The middle-only check (rv1+1-rv2-1) specifically proves the fragment-aware path ran — a by-id-only show would leave `middle_shown == 0`. The smoke asserts `middle_shown >= 1`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded header comment to avoid Qt grep false-positive**
- **Found during:** Task 1 (post-write gate verification)
- **Issue:** The plan's verbatim header comment contained the literal text `QMessageBox` ("The Qt dialogs (win + debrief QMessageBox), the 100ms redraw delay, ..."), which tripped the Qt-free verification gate (`grep -nE "from pymol.Qt|QtWidgets|QMessageBox|QDialog" smoke/phase10_smoke.py` — the plan's verify section requires 0 hits). This is exactly the AGENTS.md-warned false-positive pattern ("literal tokens in comments/docstrings trip this grep too — we hit a false positive on a docstring that said 'from PyQt5 import'"). The plan's verbatim code and the plan's verification gate are inconsistent (verbatim produces 1 hit; verify requires 0).
- **Fix:** Reworded the header comment from `"The Qt dialogs (win + debrief QMessageBox), the 100ms redraw delay, and the cleanup gate are deferred to the human-verify checkpoint (Plan 10-09)."` to `"The Qt dialogs (win + debrief), the 100ms redraw delay, and the cleanup gate are deferred to the human-verify checkpoint (Plan 10-09)."` — dropped the literal `QMessageBox` token (the parenthetical 'win + debrief' still makes sense — the two dialogs). Mirrors the 03-03/03-06/03-09/03-10/08-01/08-02/10-06 docstring-rewording precedent.
- **Files modified:** smoke/phase10_smoke.py (header comment only, line 4)
- **Verification:** `grep -nE "from pymol.Qt|QtWidgets|QMessageBox|QDialog" smoke/phase10_smoke.py` returns 0 hits (exit 1). py_compile still clean. Headless run still 15/15 ALL PASSED (the comment change has no runtime effect).
- **Committed in:** 934e28d (part of the Task 1 test commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The comment reword is a no-behavior-change fix required to keep the Qt-free verification gate clean (an AGENTS.md / plan verification contract). No scope creep; the plan's intent (a pure `pymol.cmd.*` smoke with no Qt imports or literal Qt-class tokens) is fully preserved.

## Issues Encountered
None. The headless smoke ran 15/15 ALL PASSED on the FIRST run — no runtime bugs, no fix(10-08) iterations needed. The Plan 10-06 `_show_all_hiders_for_debrief` cmd-layer logic was correct on first runtime exercise (mirrors the Phase 7 07-03 cleanest-verification-since-Phase-3 pattern: 0 runtime bugs at the headless tier).

## User Setup Required
None — no external service configuration required. This is a pure `pymol.cmd.*` smoke test run headlessly from WSL via `cmd.exe /c run-conda-pymol.bat -cq` after staging with `wsl2win_cp.sh`. The only runtime verification of the Qt dialogs (win + debrief QMessageBox), the 100ms redraw delay, and the cleanup gate timing is the human-verify checkpoint (Plan 10-09) — the cmd-layer show path this smoke verifies is the load-bearing dependency for that checkpoint.

## WSL Gate State (this plan, on exec/10-08 branch)
- `python3.6 -m py_compile smoke/phase10_smoke.py` → clean.
- `grep -nE "from pymol.Qt|QtWidgets|QMessageBox|QDialog" smoke/phase10_smoke.py` → 0 hits (pure `pymol.cmd.*`, NO Qt — verified).
- Headless run via `cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase10_smoke.py"` → 15/15 ALL PASSED, exit 0.
- The cartoon fragment FULL rv1-rv2 range is shown (>=3 atoms in the range, >=1 in the middle rv1+1-rv2-1) — verified.
- `python3.6 -m py_compile biochemeleon/*.py` → clean (no source code changed — smoke-only plan).
- `grep -rnE "\.exec_\(\)" biochemeleon/` → 3 hits (unchanged from 10-06 — all 3 on child dialogs: gui_game.py:323 _finish_win, gui_game.py:382 _finish_debrief, __init__.py:948 help_dlg; smoke is in smoke/, not biochemeleon/).
- `git status --short` after the test commit → clean (only smoke/phase10_smoke.py was staged + committed).

## Next Phase Readiness
- **Cmd-layer debrief show path is headless-verified.** The 15/15 ALL PASSED smoke proves the fragment-aware `cmd.show` loop (the load-bearing logic `_show_all_hiders_for_debrief` runs) makes every hider visible in its own rep, including the cartoon fragment's FULL rv1-rv2 range (NOT just the anchor id). The smoke is the regression-test floor for any future change to the debrief show path.
- **Handoff to Plan 10-09:** the Qt dialogs (win + debrief QMessageBox), the 100ms redraw delay, and the cleanup gate timing (non-imported vs imported) are the human-verify checkpoint (Plan 10-09). The cmd-layer show path this smoke verifies is the load-bearing dependency — the human-verify checkpoint exercises the FULL two-dialog flow in real Windows PyMOL (play to win, confirm win dialog -> hiders shown in viewer -> debrief dialog with per-rep explanations -> cleanup timing).
- **No blockers.** All WSL gates green (py_compile smoke + biochemeleon + Qt-free smoke + headless 15/15 PASS + exec_=3 unchanged). Plan 10-07 (game-tab tooltips) runs in parallel with this plan (Wave 3, disjoint files: 10-07 touches biochemeleon/gui_game.py; 10-08 touches smoke/phase10_smoke.py — no conflict).

---
*Phase: 10-polish-endgame-help*
*Plan: 08*
*Completed: 2026-08-18*
