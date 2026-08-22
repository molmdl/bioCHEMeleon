# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-18)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v1.1 shipped 2026-08-22 (bugfix + gameplay improvements over v1). Repo reorganized for multi-viewer support (commit 9ff57f1): v1 PyMOL code now lives under pymol/; vmd/ and chimeraX/ are placeholder dirs. Planning next milestone (v2 — VMD tcl script, deferred per spec.md; chimeraX is a later candidate).

## Current Position

Phase: Not started (defining requirements for v2.0)
Plan: —
Status: Defining requirements
Last activity: 2026-08-22 — Milestone v2.0 (VMD tcl port) started. Reference material copied to `vmd-ref/` (gitignored). VMD 1.9.3 confirmed accessible headlessly via `vmd -dispdev text -e <script> -eofexit`.

Progress: ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 0% v2.0 (defining requirements)

## v1 Milestone Summary

**Shipped:** 2026-08-18 — bioCHEMeleon v1 (PyMOL 2.5.0 plugin)
- 12 phases, 77 plans, 393 commits, 16 days (2026-08-02 → 2026-08-18)
- ~14,000 lines Python (5,621 biochemeleon + 4,420 smoke + 3,959 tests)
- 125 unit tests green + 6 headless smoke suites + 9 human-verify checkpoints APPROVED
- Milestone audit: ✅ PASSED (46/46 requirements, 12/12 phases, 9/9 integration, 6/6 E2E flows)
- Git tag: `v1`

**Archived:**
- `.planning/milestones/v1-ROADMAP.md` — full phase details
- `.planning/milestones/v1-REQUIREMENTS.md` — all 46 requirements marked complete
- `.planning/milestones/v1-MILESTONE-AUDIT.md` — audit report (PASSED)
- `.planning/MILESTONES.md` — milestone summary entry

**Full v1 execution history:** `.planning/phases/*/*-SUMMARY.md` (77 plan summaries across 12 phases)

## Accumulated Context

### Open items for next milestone

- **VMD tcl script (v2.0 — ACTIVE)** — Milestone started 2026-08-22. Port v1's hide-and-seek game to VMD 1.9.3. MVP-first approach; research drives rep selection; explore VMD materials as differentiator. Reference material in `vmd-ref/` (gitignored). Headless testing via `vmd -dispdev text -e <script> -eofexit`.
- **chimeraX port** — placeholder dir chimeraX/ exists; a later milestone candidate after VMD (v2). Different viewer/extension model than PyMOL and VMD; research needed when it becomes active.
- **AGENTS.md needs VMD/tcl-specific rewrite** after /gsd-new-milestone workflow (currently v1-scoped per AGENTS.md header note). Will be updated with verified VMD API behavior as v2 research/execution progresses.
- **Repo reorg (2026-08-19, commit 9ff57f1):** v1 code moved under pymol/ (biochemeleon/, smoke/, tests/); vmd/ and chimeraX/ placeholders added. v2 code will live under vmd/.
- **Known v1 tech debt to consider for v2:** Phase 9 SSL fallback (check_hostname=False for SASBDB HARICA cert); Phase 11 hider fragment secondary-structure inheritance (cosmetic). v1.1 quick-008 fix (random total distribution) must be baked in from start in v2.

### Resolved (v1 — full log in MILESTONES.md + phase SUMMARYs)

All v1 blockers resolved. Key runtime discoveries encoded in AGENTS.md domain rules (Phase 3 library bugs: id vs ID, b<0 selector, space= hygiene, etc.). Phase 11 alt-conf integration failure resolved via single-state new-chain copy refactor.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 003 | Relocate Phase 9 fetched-demo cache to cwd (cmd.fetch parity) | 2026-08-22 | 5041541 | [003-relocate-phase9-demo-cache-to-cwd](./quick/003-relocate-phase9-demo-cache-to-cwd/) |
| 004 | Flatten Phase 9 demo cache to single `<cwd>/cache/` layer | 2026-08-22 | 3d8cf9b | [004-flatten-phase9-demo-cache-to-cache-dir](./quick/004-flatten-phase9-demo-cache-to-cache-dir/) |
| 005 | Spread cartoon/ribbon hiders across chain (even spacing, not adjacent) | 2026-08-22 | 00bda62 | [005-spread-cartoon-segments](./quick/005-spread-cartoon-segments/) |
| 006 | Expand stick hider neighbor pool to all heavy atoms (side chains) | 2026-08-22 | b8fb430 | [006-stick-sidechain-neighbors](./quick/006-stick-sidechain-neighbors/) |
| 007 | Update tracking docs for multi-viewer repo structure (pymol/ paths, chimeraX) | 2026-08-22 | 7626414 | [007-update-tracking-docs-multiviewer](./quick/007-update-tracking-docs-multiviewer/) |
| 008 | Randomize rep distribution when only total count specified (not all spheres) | 2026-08-22 | 889fd00 | [008-randomize-reps-when-total-only](./quick/008-randomize-reps-when-total-only/) |
| 009 | Fix alt-conf backbone atoms causing duplicate anchor in cartoon segment hider | 2026-08-22 | 4f7ed72 | [009-fix-altconf-anchor-duplicate](./quick/009-fix-altconf-anchor-duplicate/) |

*Updated: 2026-08-22 after quick tasks 005-009 completion*
