# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-22)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v2.0 — VMD tcl port. Roadmap created (phases 13-23, 54 requirements). Ready to plan Phase 13.

## Current Position

Phase: 13 of 23 (Bootstrap & Sourced Entry) — COMPLETE
Plan: 2 of 2 in current phase (13-02 complete; checkpoint approved)
Status: Phase 13 complete, ready for verification/transition
Last activity: 2026-08-29 — Phase 13 complete (pure layer + tcltest + entry script + headless smoke + GUI checkpoint approved). One bug fixed during checkpoint (tk_version scoping, 57bcc53).

Progress: ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ~8% v2.0 (1 of ~12 phases complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 2 (v2.0); 77 in v1 (archived)
- Average duration: 25 min (v2.0, 2 plans)
- Total execution time: 50 min (v2.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 13. Bootstrap & Sourced Entry | 2/2 | 50 min | 25 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- **v2.0 milestone start (2026-08-22):** Port v1 to VMD 1.9.3 as a sourced tcl script. MVP-first; research drives rep selection; materials explored as differentiator. Phases numbered 13-23 (continuing from v1's 11+04.1).
- **v2 architecture:** PDB-rebuild (Option D) replaces in-place insertion — highest-risk change, de-risked in Phase 15. Backup = reload original PDB (no undo). Registry keyed by atom `index` (no global id). `.bcm` JSON hand-rolled (no `json` package). Pure-layer tcl unit-testable in WSL via `tclsh`/`tcltest`.
- **v2 de-risking order:** Phase 15 (mutation safety) before Phase 16 (MVP loop) — PDB-rebuild proven before generators build on it. Phase 16 locks the pick contract via GUI human-verify (MEDIUM-confidence research flag). Materials (Phase 18) after reps (Phase 17.2) solid.
- **Phase 17 split (2026-08-22 revision):** Phase 17 (rep generators) split into 17.1 (rep setup infrastructure + simple generators — Lines/VDW/Licorice, HIDER-06/HIDER-04) and 17.2 (cartoon generators — Cartoon/NewCartoon, HIDER-05) by generator complexity tier. Simple reps are bonded pseudoatom analogues; cartoon reps carry the STRIDE `ss='L'` L-complexity caveat (v1 Phase 11 analogue) and are de-risked separately.
- **Phase 23 docs (2026-08-22 revision):** Final phase 23 added for documentation — root README (multi-viewer), `vmd/README.md` (VMD tcl install/use), `pymol/README.md` (PyMOL plugin install/use). 3 DOC requirements added (54 total). AGENTS.md VMD/tcl rewrite is a post-workflow task, NOT a roadmap phase.
- **13-01 pure-layer namespaces (2026-08-28):** `::biochemeleon::setup_state` and `::biochemeleon::registry` (filename parity with v1; NOT `::biochemeleon::setup`). Entry script (13-02) MUST source by these exact names.
- **13-01 tcltest under headless VMD (2026-08-28):** `tclsh` NOT in WSL (AGENTS.md forbids apt). tcltest runs UNDER headless VMD via `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e <file>.test -eofexit < /dev/null'`. Result parsed from `BCHM_TEST_RESULT` marker, NOT `$?` (VMD doesn't propagate tcl exit codes). `.test` files are standalone-tclsh-compatible if user later installs tcl.
- **13-01 DI via tcl command-prefix + {expand} (2026-08-28):** `reconstruct_from_sentinels` uses `[{*}$fetch_hider_ids]` (argument expansion), NOT `[$fetch_hider_ids]` (single-word). Supports both proc names and `apply` lambda lists. Downstream Phase 15 game.tcl MUST use `{*}` when injecting `apply` lambdas.
- **13-02 GUI checkpoint + tk_version lesson (2026-08-29):** Phase 13 GUI checkpoint APPROVED — ttk::notebook renders correctly in VMD 1.9.3 Tk; modeless dialog keeps viewer interactive (no grab; brief OpenGL pause during window-move is normal VMD behavior, acceptable); re-source guard works (prints warning, prevents duplicate dialog + state reset); menu path Extensions → Visualization → bioCHEMeleon confirmed. One bug found+fixed: `info exists tk_version` inside a proc checks LOCAL scope only → use `::tk_version` (global qualifier). Downstream Phase 14+ GUI procs MUST use `::tk_version`. Headless smoke pattern (`bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/*.tcl -eofexit < /dev/null'` + `BCHM_SMOKE_RESULT` marker + `[pwd]`-based path resolution) is the established Phase 14+ pattern.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 16 pick mechanism (MEDIUM confidence):** All 4 researchers referenced VMD's pick system with different specifics; `vmd_pick_*` globals are absent in text mode. Must lock the contract via ONE human-in-GUI test in Phase 16. Design PickBridge defensively (trace + callback-list + label-poll fallback).
- **Phase 15 PDB-rebuild (HIGHEST risk):** Viewpoint/reps must save+restore on a NEW molid; PDB column misalignment silently drops sentinels (mitigation: tag sentinels in-place via atomselect after load, never rely on PDB columns alone).
- **AGENTS.md VMD/tcl rewrite** deferred until after v2 research/execution progresses (currently v1-scoped per header note).

## Session Continuity

Last session: 2026-08-29 — Phase 13 complete (2/2 plans; 13-02 checkpoint approved)
Stopped at: Phase 13 complete. 13-02 commits: 963e201 (entry script), 8bca26b (headless smoke), 57bcc53 (tk_version scoping fix during checkpoint). ENTRY-01/02/03 + TEST-01 satisfied.
Resume file: None
Next: `/gsd-execute-phase 13` verification (if any), or `/gsd-discuss-phase 14` (Setup Tab & Bundled Demos) — Phase 13 is the first v2 phase, now complete.

## v1 Milestone Reference (archived)

- **Shipped:** 2026-08-18 — bioCHEMeleon v1 (PyMOL 2.5.0 plugin), 12 phases, 77 plans, 393 commits, 46/46 requirements ✅ PASSED audit. Git tag: `v1`.
- **v1.1:** Shipped 2026-08-22 — 5 bugfix/gameplay quick tasks (207 unit tests green).
- **Archived:** `milestones/v1-{ROADMAP,REQUIREMENTS,MILESTONE-AUDIT}.md`; full execution history in `phases/*/*-SUMMARY.md`.
- **Known v1 tech debt considered for v2:** Phase 9 SSL fallback (check_hostname=False); Phase 11 SS-inheritance (cosmetic). v1.1 quick-008 (random total distribution) baked into v2 from the start (SETUP-06).

---
*Updated: 2026-08-29 after 13-02-PLAN.md completion (Phase 13 complete)*
