# Project Milestones: bioCHEMeleon

## v1 bioCHEMeleon (Shipped: 2026-08-18)

**Delivered:** A PyMOL 2.5.0 plugin that turns a loaded molecular object into a hide-and-seek puzzle — load → generate blended "hider" atoms matching the local representation → click-to-find → win, with full game lifecycle (hint/reveal, found-management, persistence) and a teachable post-game debrief.

**Phases completed:** 1-11 + 04.1 (12 phases, 77 plans total)

**Key accomplishments:**

- Plugin foundation & modeless tabbed dialog (Setup + Game status) that keeps the 3D viewer interactive for click-to-find
- Pure-layer architecture (setup_state.py + registry.py stdlib-only, WSL-unit-testable) + mutation-safety foundation with backup → mutate → remove → restore proven safe; 6 runtime library-bug discoveries encoded as AGENTS.md domain rules
- MVP core loop shipped (load → generate sphere hiders → click-to-find → win) with timer, countdown, rolling log, win message, and per-rep remaining-hiders display (easy mode)
- Multi-representation hider generators: line/stick (bonded pseudoatom), sphere (bounding box), cartoon/ribbon (single-state new-chain copy refactor after 4 failed alt-conf GUI bug cycles)
- Full game lifecycle: hint (color neighbors), reveal-one/all (with confirm + counter), found-hider dropdown + color picker (accessibility), restart, cleanup, persistence via `.pse` + `.bcm` JSON sidecar zipped into `.bcmz` for shareable puzzles
- Large demo fetch (MemProtMD membrane proteins + SASBDB glycoprotein) with water/salt stripping + difficulty-tiered metadata + full source attribution in DATA_SOURCES.md; polish: tooltips, controls help, win-screen stats, post-game debrief highlighting all hiders with per-rep "why hard to spot" explanations

**Stats:**

- 290 files created/modified, ~14,000 lines of Python (5,621 biochemeleon + 4,420 smoke + 3,959 tests)
- 12 phases, 77 plans, 393 commits
- 16 days from project init to ship (2026-08-02 → 2026-08-18)
- 125 unit tests green + 6 headless smoke suites (Phase 3/4/4.1/5/6/7/8/10/11) + 9 human-verify checkpoints APPROVED
- Milestone audit: ✅ PASSED — 46/46 requirements, 12/12 phases, 9/9 integration, 6/6 E2E flows

**Git range:** `ad43f08` (docs: initialize project) → `3f52d7f` (docs(v1): milestone audit report)

**Archived:**
- `milestones/v1-ROADMAP.md` — full phase details
- `milestones/v1-REQUIREMENTS.md` — all 46 requirements marked complete
- `milestones/v1-MILESTONE-AUDIT.md` — audit report (PASSED)

**What's next:** v2 — VMD tcl script (deferred per spec.md). Run `/gsd-new-milestone` to start.

---

## v1.1 bioCHEMeleon (Shipped: 2026-08-22)

**Type:** Bugfix & gameplay improvements (post-v1 quick tasks, no new phases)

**Delivered:** Five focused fixes addressing gameplay tuning issues and a crash on alt-conf structures, plus repo restructuring for upcoming multi-viewer support.

**Changes:**

- **Bugfix — alt-conf crash:** Structures with alternate-location backbone atoms (e.g. 4wb3 nucleosome) no longer crash when generating cartoon/ribbon hiders (quick-009)
- **Bugfix — all-spheres fallback:** Setting only a total hider count now randomly distributes across all representations instead of defaulting to all spheres (quick-008)
- **Gameplay — spread cartoon hiders:** Multiple cartoon/ribbon hiders evenly distributed across the chain instead of clustering back-to-back near the N-terminus (quick-005)
- **Gameplay — stick sidechain placement:** Stick/line hiders bond to any heavy atom (side chains included), not just backbone; cartoon no longer obscures them (quick-006)
- **Infra — multi-viewer repo layout:** v1 code moved under `pymol/`; `vmd/` and `chimeraX/` placeholders added; tracking docs updated (quick-007)

**Stats:** 5 quick tasks, ~15 commits, 207 unit tests green, human-verified across protein / membrane protein / glycoprotein / DNA / RNA / mixed protein-nucleic structures

**Git range:** `e9a4c78` (v1 tag) → HEAD

**What's next:** v2 — VMD tcl script (deferred per spec.md); chimeraX is a later candidate.

---
