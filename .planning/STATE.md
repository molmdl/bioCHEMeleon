# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-22)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v2.0 — VMD tcl port. Phase 14 (Setup Tab & Bundled Demos) in progress — 14-01 (pure-layer setup-state model) complete; 14-02 (mol bridge demos.tcl) next.

## Current Position

Phase: 14 of 23 (Setup Tab & Bundled Demos) — IN PROGRESS
Plan: 1 of 4 in current phase (14-01 complete)
Status: Phase 14 in progress; pure-layer setup-state model done, ready for 14-02 (mol bridge)
Last activity: 2026-08-29 — Completed 14-01-PLAN.md (setup-state model: validate_state full + randomize_state + randomize_per_rep quick-008 via TDD; 41 tcltest cases green under headless VMD; pure-layer + 8.6 gates clean).

Progress: ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ~9% v2.0 (1 of 11 phases complete; Phase 14 in progress 1/4 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 3 (v2.0); 77 in v1 (archived)
- Average duration: 20 min (v2.0, 3 plans)
- Total execution time: 61 min (v2.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 13. Bootstrap & Sourced Entry | 2/2 | 50 min | 25 min |
| 14. Setup Tab & Bundled Demos | 1/4 | 11 min | 11 min |

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
- **14-01 setup-state model + quick-008 (2026-08-29):** validate_state is a DETERMINISTIC clamp (NO randomness) — full v1 port with drop-overflow per_rep clamp (Pitfall 7: keep entries that fit, DROP overflow, never truncate; `{VDW 5 Cartoon 5 Lines 5}` hc=8 → `{VDW 5}`), DEFAULTS-key-order result (Pitfall 5: order-stable dict eq), enum/bool/pdb_pool validation. randomize_per_rep implements quick-008 SETUP-06 as a random NON-EMPTY SUBSET (1..len) of reps + non-empty guarantee (NOT all-reps — the verified v1 quick-008 behavior; research Open Q1 resolved per recommendation (a)). randomize_state seeds the GLOBAL PRNG once (`expr {srand($seed)}`) and calls randomize_per_rep with NO seed (continues the sequence); lock_source=1 preserves locked target else weighted-random mode (loaded/fetch/demo/demo; empty pdb_pool re-rolls fetch→demo). All randomness tests pass an explicit seed arg (Pitfall 4 mitigation — no reliance on residual global PRNG state). 41 tcltest cases green under headless VMD; pure-layer + 8.6 gates clean. Downstream: callers wanting reproducible randomization must pass a seed and NOT interleave `rand()` calls (global PRNG). v2 pdb_pool stays empty (no PDB_POOL constant; fetch is a later phase).

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 16 pick mechanism (MEDIUM confidence):** All 4 researchers referenced VMD's pick system with different specifics; `vmd_pick_*` globals are absent in text mode. Must lock the contract via ONE human-in-GUI test in Phase 16. Design PickBridge defensively (trace + callback-list + label-poll fallback).
- **Phase 15 PDB-rebuild (HIGHEST risk):** Viewpoint/reps must save+restore on a NEW molid; PDB column misalignment silently drops sentinels (mitigation: tag sentinels in-place via atomselect after load, never rely on PDB columns alone).
- **AGENTS.md VMD/tcl rewrite** deferred until after v2 research/execution progresses (currently v1-scoped per header note).

## Session Continuity

Last session: 2026-08-29 — Completed 14-01-PLAN.md (Phase 14 plan 1 of 4)
Stopped at: 14-01 complete. Commits: 863d5d5 (RED tests), 87db8e5 (GREEN impl). validate_state full + randomize_state + randomize_per_rep quick-008; 41 tcltest cases green; pure-layer + 8.6 gates clean. SETUP-02/04/06 + half SETUP-05 satisfied.
Resume file: None
Next: 14-02-PLAN.md (mol bridge demos.tcl: load_demo, get_active_reps, save/load_setup, fetch_pdb stub) + headless smoke. Then 14-03/14-04 (GUI structure + wire callbacks).

## v1 Milestone Reference (archived)

- **Shipped:** 2026-08-18 — bioCHEMeleon v1 (PyMOL 2.5.0 plugin), 12 phases, 77 plans, 393 commits, 46/46 requirements ✅ PASSED audit. Git tag: `v1`.
- **v1.1:** Shipped 2026-08-22 — 5 bugfix/gameplay quick tasks (207 unit tests green).
- **Archived:** `milestones/v1-{ROADMAP,REQUIREMENTS,MILESTONE-AUDIT}.md`; full execution history in `phases/*/*-SUMMARY.md`.
- **Known v1 tech debt considered for v2:** Phase 9 SSL fallback (check_hostname=False); Phase 11 SS-inheritance (cosmetic). v1.1 quick-008 (random total distribution) baked into v2 from the start (SETUP-06).

---
*Updated: 2026-08-29 after 14-01-PLAN.md completion (Phase 14 in progress, 1/4 plans)*
