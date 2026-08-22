# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-18)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v1 milestone COMPLETE (shipped 2026-08-18). Repo reorganized for multi-viewer support (commit 9ff57f1): v1 PyMOL code now lives under pymol/; vmd/ and chimeraX/ are placeholder dirs. Planning next milestone (v2 — VMD tcl script, deferred per spec.md; chimeraX is a later candidate).

## Current Position

Phase: v1 complete (all 12 phases: 1-11 + 04.1)
Plan: Not started (next milestone)
Status: Ready to plan next milestone
Last activity: 2026-08-22 — quick-005/006/007/008/009: gameplay tuning (cartoon segment spreading, stick sidechain neighbors, multi-viewer docs, random rep distribution) + alt-conf anchor fix. v1 milestone complete 2026-08-18 (archived + tagged).

Progress: ████████████████████████████████████████████████████████ 100% v1 (77 of 77 plans done — all phases COMPLETE + VERIFIED. v1 shipped.)

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

- **VMD tcl script** — deferred per spec.md; different tech stack (tcl vs python). Run `/gsd-new-milestone` to start (questioning → research → requirements → roadmap).
- **chimeraX port** — placeholder dir chimeraX/ exists; a later milestone candidate after VMD (v2). Different viewer/extension model than PyMOL and VMD; research needed when it becomes active.
- **Repo reorg (2026-08-19, commit 9ff57f1):** v1 code moved under pymol/ (biochemeleon/, smoke/, tests/); vmd/ and chimeraX/ placeholders added. Root AGENTS.md paths updated to pymol/-prefixed layout.
- **AGENTS.md needs VMD/tcl-specific rewrite** when v2 research begins (currently v1-scoped per AGENTS.md header note).
- **Known v1 tech debt to consider for v2:** Phase 9 SSL fallback (check_hostname=False for SASBDB HARICA cert); Phase 11 hider fragment secondary-structure inheritance (cosmetic). *(Phase 9 .pdb.gz cache path resolved 2026-08-22: quick-003 relocated to `<cwd>/tmp/phase9-demos/` for `cmd.fetch` parity; quick-004 flattened to a single `<cwd>/cache/` layer (cache + temp `.raw`/`.dry` co-located). makedirs-on-first-use ensures the dir exists regardless of install location. Network fetch + GUI on a fresh computer remain untested by the quick tasks — see `.planning/quick/004-*/004-SUMMARY.md`.)*

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
