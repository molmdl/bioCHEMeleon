---
phase: 10-polish-endgame-help
plan: 10
subsystem: docs
tags: [readme, sc5, v1-ship, user-facing-docs, demo-table]

# Dependency graph
requires:
  - phase: 10
    provides: "Plans 10-01 through 10-09 (the full Phase 10 implementation + human-verify: debrief formatter, Setup/Game tooltips, Help button+dialog, pre-impl audit, win-stats GUI, post-game debrief GUI, headless debrief smoke, human-verify APPROVED) — the verified-shipped feature set this README reflects"
  - phase: 10
    provides: "10-09-VERIFY.md (human-verify APPROVED record — 8/8 checks PASS; the README reflects verified-shipped behavior, not aspirational behavior, per the research's flagged dependency)"
  - phase: 9
    provides: "DEMO_MANIFEST 9-entry schema + TIER_LABELS 4-tier system + DATA_SOURCES.md (the verified demo inventory the README table reflects)"
provides:
  - "Finalized README.md reflecting the shipped v1 feature set (SC5): endgame + debrief + help + tooltips + controls, install instructions, usage, 4-tier demo table with network column"
  - "Vibe-coding warning kept VERBATIM; UNDER DEVELOPMENT removed (v1 complete)"
affects: [10-11]

# Tech tracking
tech-stack:
  added: []  # docs-only plan — no code, no libs
  patterns:
    - "README finalization gated on human-verify: sequenced AFTER 10-09 (the research flagged the dependency that the README's endgame/debrief copy depends on SC3/SC4 landing + being human-verified; the README reflects verified-shipped behavior, not aspirational behavior)"

key-files:
  created: []
  modified:
    - README.md  # the single file this plan touches — finalized for v1 ship

key-decisions:
  - "Demo table uses the 4-tier system (Easy/Hard/Challenge/Very challenging) from TIER_LABELS (setup_state.py:65-70) + a 'Needs network?' column — the 3 fetched demos (sasdpg4, 1gzm, 3gp6) are marked 'yes (fetched)'; the 6 bundled are 'no (bundled)'. All 9 IDs verified against DEMO_MANIFEST keys (1znf, 5e54, 1k8p, 1xdn, 2qbz, 4wb3, sasdpg4, 1gzm, 3gp6)."
  - "Project Structure tree comments cleaned (the ONLY exception to 'KEEP UNCHANGED'): line 'GSD workflow artifacts' -> 'project planning docs' (drops the GSD mention); line '(created during Phase 1)' parenthetical dropped. These two cleanings keep the user-facing grep gate `grep -cE 'Phase [0-9]|plan 10|gsd|GSD' README.md` at 0."
  - "Usage step 6 updated to the full win-then-debrief flow (time + hints + reveals + debrief) — reflects the SC3/SC4 target that 10-05/10-06/10-09 shipped + human-verified."
  - "Two new bullets added to 'What It Does' (Endgame & debrief + Help & tooltips), placed AFTER 'Core loop' and BEFORE 'Persistence' per the research outline order. The Game tab bullet also gained 'color picker for found hiders' (DIFF-04, shipped Phase 7)."

patterns-established:
  - "User-facing docs grep gate: `grep -cE 'Phase [0-9]|plan 10|gsd|GSD' README.md` must return 0 — the README is user-facing and must carry no internal phase/plan/GSD workflow references. Comment-only mentions in code blocks count (the Project Structure tree's 'GSD workflow artifacts' + '(created during Phase 1)' had to be cleaned)."

# Metrics
duration: ~38min (incl. context load)
completed: 2026-08-18
---

# Phase 10 Plan 10: README Finalization (SC5) Summary

**Single-task docs-only plan that finalized README.md for the v1 ship — vibe-coding warning kept verbatim, UNDER DEVELOPMENT removed, Endgame + Help + debrief + Tips sections added, Demo table upgraded to the 4-tier system with a network column. One atomic commit (4477540).**

## Performance

- **Duration:** ~38 min (incl. context load + verifying the feature inventory against ROADMAP/STATE/setup_state.py; active editing ~5 min)
- **Started:** 2026-08-18T01:39:10Z
- **Completed:** 2026-08-18T02:17:18Z
- **Tasks:** 1 (single auto task — rewrite README.md per the research outline)
- **Files modified:** 1 (`README.md` — 27 insertions, 19 deletions)
- **Files created:** 1 (`10-10-SUMMARY.md` — this summary)

## Accomplishments
- **Vibe-coding warning kept VERBATIM.** README lines 1-3 (the `> This is a vibe-coding project...` block + trailing `> ` blank line) are unchanged — not a single character altered, per the plan's hard constraint.
- **UNDER DEVELOPMENT removed.** The `> UNDER DEVELOPMENT` line (former line 4) is gone — the v1 PyMOL plugin is COMPLETE. Not replaced with another tag (the `# bioCHEMeleon` heading follows the vibe-coding warning directly, per the research outline).
- **Status line updated.** `> **Status:** v1 (PyMOL plugin) is complete. v2 (VMD tcl script) is deferred.` (was "Planning complete. v1 ... is being built"). The `> See `.planning/ROADMAP.md` for the phase breakdown.` line kept as-is.
- **Two new "What It Does" bullets added** (after Core loop, before Persistence, per the research outline order):
  - **Endgame & debrief** — win screen shows time + hints used + reveals used, then a debrief highlights each hider and why it was hard to spot (the teachable moment). Reflects SC3/SC4 shipped in 10-05/10-06 + human-verified in 10-09.
  - **Help & tooltips** — every control has a tooltip; a Help button opens a panel explaining each representation, the PyMOL controls (rotate/pan/zoom/click), and a tip on switching representations to spot hiders. Reflects UX-01/UX-02 shipped in 10-02/10-03/10-07 + human-verified in 10-09.
- **Game tab bullet updated** to mention the color picker for found hiders (DIFF-04, shipped Phase 7) alongside the existing found-hider management dropdown.
- **Usage step 6 updated** to the full win-then-debrief flow: "the timer stops and a win screen shows your time, hints used, and reveals used, followed by a debrief highlighting each hider and why it was hard to spot." (was "the timer stops and shows your time (plus hints/reveals used)").
- **Tip line added** at the end of Usage (after step 7): `> Tip: stuck? Open the Help button for how to rotate, zoom, and click — and for a strategy on switching representations to spot hiders.`
- **New "Tips — How to spot hiders" section** added (after Usage, before Demo Molecules) — frames the switch-reps strategy as a legitimate observation strategy, not a cheat (per the ROADMAP SC2 note + the research's UX-02 strategy section).
- **Demo Molecules table upgraded** to the 4-tier system (Easy/Hard/Challenge/Very challenging) from `TIER_LABELS` + a "Needs network?" column. 9 rows, all IDs verified against `DEMO_MANIFEST` keys. The 3 fetched demos (sasdpg4 SASBDB, 1gzm + 3gp6 MemProtMD) are marked "yes (fetched)"; the 6 bundled are "no (bundled)".
- **Project Structure tree comments cleaned** (the only exception to "KEEP UNCHANGED"): `GSD workflow artifacts` -> `project planning docs`; `(created during Phase 1)` parenthetical dropped. Keeps the user-facing grep gate at 0.
- **Last-updated date** updated to `2026-08-18` (the ship date); the "updated as the project evolves" phrasing dropped (v1 is complete).

## Task Commits

Each task was committed atomically:

1. **Rewrite README.md to reflect the shipped v1 feature set (SC5)** - `4477540` (docs) — single atomic commit. Staged ONLY README.md (per the plan's git rules). +27/-19 lines.

## Files Created/Modified
- `README.md` — finalized for v1 ship (the single file this plan touches):
  - Lines 1-3: vibe-coding warning (KEPT VERBATIM).
  - Line 4 (former UNDER DEVELOPMENT): REMOVED.
  - Status line: v1 complete + v2 deferred.
  - What It Does: +2 bullets (Endgame & debrief, Help & tooltips) + Game tab bullet gains color picker.
  - Usage step 6: win-then-debrief flow.
  - Usage: +Tip line.
  - NEW section: Tips — How to spot hiders.
  - Demo table: 4-tier + network column (9 rows).
  - Project Structure: 2 comment cleanings (GSD/Phase mentions dropped).
  - Last updated: 2026-08-18.
- `.planning/phases/10-polish-endgame-help/10-10-SUMMARY.md` — NEW (this summary).
- `.planning/STATE.md` — updated (Phase 10 Plan 10 complete; progress + handoff to 10-11).

## Decisions Made
- **Demo table 4-tier + network column.** The research outline specified the 4-tier system (Easy/Hard/Challenge/Very challenging) from `TIER_LABELS` + a "Needs network?" column. All 9 demo IDs verified against `DEMO_MANIFEST` keys in `setup_state.py` (1znf, 5e54, 1k8p, 1xdn, 2qbz, 4wb3, sasdpg4, 1gzm, 3gp6). The 3 fetched demos (sasdpg4 from SASBDB, 1gzm + 3gp6 from MemProtMD) are marked "yes (fetched)"; the 6 bundled RCSB PDBs are "no (bundled)".
- **Project Structure comment cleanings = the only exception to "KEEP UNCHANGED".** The plan explicitly flagged two inline code-block comments that mention GSD/Phase (the `GSD workflow artifacts` phrase + the `(created during Phase 1)` parenthetical) — they would trip the `grep -cE "Phase [0-9]|plan 10|gsd|GSD" README.md` check (returning 2 instead of 0). Cleaned per the plan's explicit instruction; the rest of the Project Structure tree is unchanged.
- **Usage step 6 reflects the verified-shipped win-then-debrief flow.** The research flagged the dependency: the README's endgame/debrief copy depends on SC3/SC4 landing + being human-verified. Sequencing this plan AFTER 10-09 (the human-verify checkpoint APPROVED) means the README reflects verified-shipped behavior, not aspirational behavior. The win screen shows time + hints + reveals (SC3/DIFF-02, shipped 10-05) and the debrief highlights each hider with a per-rep explanation (SC4/DIFF-03, shipped 10-06) — both human-verified in 10-09.
- **No phase numbers / plan IDs / GSD workflow mentions.** The README is user-facing. The grep gate `grep -cE "Phase [0-9]|plan 10|gsd|GSD" README.md` returns 0 (verified post-commit).

## Deviations from Plan

### Auto-fixed Issues

None — the plan executed exactly as written. The single task (rewrite README.md per the research outline) was executed verbatim; all 8 grep verifications pass; the Demo table's 9 rows + network column match the research outline + the shipped `DEMO_MANIFEST`.

## Issues Encountered
None.

## User Setup Required
None — docs-only plan (no code, no services, no environment changes).

## Grep-Gate State (post-commit)
README verifications (all pass):
- `grep -c "UNDER DEVELOPMENT" README.md` → **0** (removed).
- `grep -c "vibe-coding project" README.md` → **1** (kept verbatim).
- `grep -c "Endgame" README.md` → **1** (the new bullet).
- `grep -c "debrief" README.md` → **2** (the Endgame bullet + Usage step 6).
- `grep -c "Help & tooltips" README.md` → **1** (the new bullet).
- `grep -c "Tips — How to spot hiders" README.md` → **1** (the new section).
- `grep -c "legitimate observation strategy" README.md` → **1** (the Tips section).
- `grep -cE "Phase [0-9]|plan 10|gsd|GSD" README.md` → **0** (user-facing, no internal references).
- Demo table: **9** data rows + a "Needs network?" column + the 4-tier labels (Easy/Hard/Challenge/Very challenging).

WSL gates (unaffected — README-only plan, no Python code touched):
- `python3.6 -m py_compile biochemeleon/*.py` → clean (exit 0).
- Pitfall-1 grep → **0** matches (unchanged).
- exec_ grep (`.exec_\(\)`) → **3** hits, all on child dialogs (UNCHANGED — README-only plan).

## Next Phase Readiness
- **SC5 (README finalization) is COMPLETE.** The README reflects the final shipped v1 feature set: endgame (win stats + debrief), help (tooltips + Help dialog + controls), install instructions, usage, 4-tier demo table with network column. The vibe-coding warning is kept verbatim; UNDER DEVELOPMENT is removed; the Status line says v1 complete + v2 deferred.
- **Handoff to Plan 10-11:** "README finalized; Plan 10-11 audits the README claims against the shipped code." Plan 10-11 is the post-implementation audit (read-only verification that every README claim matches a shipped feature) + the phase closeout.
- **Phase 10 progress:** 10 of 11 plans complete (10-01 through 10-10). Remaining: 10-11 (post-impl audit + phase closeout).

---
*Phase: 10-polish-endgame-help*
*Plan: 10*
*Completed: 2026-08-18*
