# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-22)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v2.0 — VMD tcl port. Roadmap created (phases 13-23, 54 requirements). Ready to plan Phase 13.

## Current Position

Phase: 13 of 23 (Bootstrap & Sourced Entry) — first v2 phase
Plan: — (not yet planned)
Status: Ready to plan Phase 13
Last activity: 2026-08-22 — v2.0 roadmap revised: Phase 17 split into 17.1 (rep setup + simple generators) / 17.2 (cartoon generators) by complexity tier; Phase 23 (documentation — multi-viewer READMEs) added; 3 DOC requirements added (54 total). 12 phases (13-23), 54 requirements mapped (100% coverage).

Progress: ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0% v2.0 (0 of ~12 phases)

## Performance Metrics

**Velocity:**
- Total plans completed: 0 (v2.0); 77 in v1 (archived)
- Average duration: — (v2.0 not started)
- Total execution time: —

**By Phase:** (v2.0 — none started yet)

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- **v2.0 milestone start (2026-08-22):** Port v1 to VMD 1.9.3 as a sourced tcl script. MVP-first; research drives rep selection; materials explored as differentiator. Phases numbered 13-23 (continuing from v1's 11+04.1).
- **v2 architecture:** PDB-rebuild (Option D) replaces in-place insertion — highest-risk change, de-risked in Phase 15. Backup = reload original PDB (no undo). Registry keyed by atom `index` (no global id). `.bcm` JSON hand-rolled (no `json` package). Pure-layer tcl unit-testable in WSL via `tclsh`/`tcltest`.
- **v2 de-risking order:** Phase 15 (mutation safety) before Phase 16 (MVP loop) — PDB-rebuild proven before generators build on it. Phase 16 locks the pick contract via GUI human-verify (MEDIUM-confidence research flag). Materials (Phase 18) after reps (Phase 17.2) solid.
- **Phase 17 split (2026-08-22 revision):** Phase 17 (rep generators) split into 17.1 (rep setup infrastructure + simple generators — Lines/VDW/Licorice, HIDER-06/HIDER-04) and 17.2 (cartoon generators — Cartoon/NewCartoon, HIDER-05) by generator complexity tier. Simple reps are bonded pseudoatom analogues; cartoon reps carry the STRIDE `ss='L'` L-complexity caveat (v1 Phase 11 analogue) and are de-risked separately.
- **Phase 23 docs (2026-08-22 revision):** Final phase 23 added for documentation — root README (multi-viewer), `vmd/README.md` (VMD tcl install/use), `pymol/README.md` (PyMOL plugin install/use). 3 DOC requirements added (54 total). AGENTS.md VMD/tcl rewrite is a post-workflow task, NOT a roadmap phase.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 16 pick mechanism (MEDIUM confidence):** All 4 researchers referenced VMD's pick system with different specifics; `vmd_pick_*` globals are absent in text mode. Must lock the contract via ONE human-in-GUI test in Phase 16. Design PickBridge defensively (trace + callback-list + label-poll fallback).
- **Phase 15 PDB-rebuild (HIGHEST risk):** Viewpoint/reps must save+restore on a NEW molid; PDB column misalignment silently drops sentinels (mitigation: tag sentinels in-place via atomselect after load, never rely on PDB columns alone).
- **AGENTS.md VMD/tcl rewrite** deferred until after v2 research/execution progresses (currently v1-scoped per header note).

## Session Continuity

Last session: 2026-08-22 — v2.0 roadmap revision
Stopped at: ROADMAP.md, REQUIREMENTS.md, STATE.md revised for v2.0. Phase 17 split into 17.1/17.2, Phase 23 (docs) added, 54 requirements mapped to 12 phases (13-23).
Resume file: None
Next: `/gsd-plan-phase 13` (Bootstrap & Sourced Entry)

## v1 Milestone Reference (archived)

- **Shipped:** 2026-08-18 — bioCHEMeleon v1 (PyMOL 2.5.0 plugin), 12 phases, 77 plans, 393 commits, 46/46 requirements ✅ PASSED audit. Git tag: `v1`.
- **v1.1:** Shipped 2026-08-22 — 5 bugfix/gameplay quick tasks (207 unit tests green).
- **Archived:** `milestones/v1-{ROADMAP,REQUIREMENTS,MILESTONE-AUDIT}.md`; full execution history in `phases/*/*-SUMMARY.md`.
- **Known v1 tech debt considered for v2:** Phase 9 SSL fallback (check_hostname=False); Phase 11 SS-inheritance (cosmetic). v1.1 quick-008 (random total distribution) baked into v2 from the start (SETUP-06).

---
*Updated: 2026-08-22 after v2.0 roadmap creation*
