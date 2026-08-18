# Requirements Archive: v1 bioCHEMeleon (PyMOL 2.5.0 plugin)

**Archived:** 2026-08-18
**Status:** ✅ SHIPPED

This is the archived requirements specification for v1.
For current requirements, see `.planning/REQUIREMENTS.md` (created for next milestone).

---

# Requirements: bioCHEMeleon

**Defined:** 2026-08-02
**Core Value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Plugin Installation

- [x] **PLUGIN-01**: Plugin installs as a standard PyMOL plugin via the GUI Plugin Manager (universal across platforms; works with Windows conda PyMOL accessed via setenv.bat from WSL) — ✅ validated v1
- [x] **PLUGIN-02**: Plugin registers a menu item "bioCHEMeleon" via `__init_plugin__` + `addmenuitemqt`; when the user manually activates the plugin (clicks the menu item), the setup window pops up — ✅ validated v1
- [x] **PLUGIN-03**: Plugin packaged as a `biochemeleon/` package directory with `__init__.py` (multi-file: gui_setup, gui_game, wizard, game, demos) — ✅ validated v1

### Setup Tab — Configuration

- [x] **SETUP-01**: Setup window opens on launch with configurable game parameters (PyQt5 via `pymol.Qt`, `QTabWidget` with Setup + Game tabs) — ✅ validated v1
- [x] **SETUP-02**: Object selector dropdown: pick a loaded object, fetch from PDB, or choose from the demo set (with a sub-menu for demo categories) — ✅ validated v1
- [x] **SETUP-03**: Hider count input, capped to a reasonable maximum relative to the object's atom count — ✅ validated v1
- [x] **SETUP-04**: "Lock current scene" checkbox — when true, generate hiders from the current representations and detect the rep list from the scene; when false, randomize representations and list all available reps — ✅ validated v1
- [x] **SETUP-05**: Per-representation hider list with checkboxes; after ticking, a form/textbox/spinwheel sets the per-rep count (if unset, random per-rep totaling the hider count) — ✅ validated v1
- [x] **SETUP-06**: Difficulty toggle: show only total remaining hiders (hard) vs. also show remaining per representation (easy) — ✅ validated v1

### Setup Tab — 7 Buttons

- [x] **BTN-01**: Reset — restore default settings — ✅ validated v1
- [x] **BTN-02**: Randomize — randomize the setup parameters — ✅ validated v1
- [x] **BTN-03**: Save Setup — save game setup parameters to a file — ✅ validated v1
- [x] **BTN-04**: Load Setup — load setup parameters from a file — ✅ validated v1
- [x] **BTN-05**: Generate & export — only generate the representation of the game and save the initial state to a file for sharing or later loading — ✅ validated v1
- [x] **BTN-06**: Cleanup model — remove all game-generated representations/atoms not in the original object (via `segi='GAME'` sentinel, never generic filters) — ✅ validated v1
- [x] **BTN-07**: Start — store the initial state, generate hiders per setup, switch to the Game status tab, and count down 3-2-1 — ✅ validated v1

### Hider Generation

- [x] **HIDER-01**: Hiders are new atoms/coordinates inserted INTO the same PyMOL object as the molecule (via `cmd.pseudoatom(object=existing)`/`cmd.fuse`), not a separate object — ✅ validated v1
- [x] **HIDER-02**: Every hider is tagged with a `segi='GAME'` + `b=-999` sentinel and tracked by `id` in a HiderRegistry — ✅ validated v1
- [x] **HIDER-03**: Line/stick hiders — new atoms mimic connected atoms or alternate positions — ✅ validated v1
- [x] **HIDER-04**: Sphere hiders — place anywhere in the bounding region — ✅ validated v1
- [x] **HIDER-05**: Cartoon/ribbon hiders — extend at a terminal, or replicate a segment (e.g. a loop) as an alternate position; uses C-alpha — ✅ validated v1 (Phase 11 single-state new-chain copy)
- [x] **HIDER-06**: Hider generation records every generated hider's `(object, atom-ID)` in the registry (foundation for cleanup, hint, reveal, found-status) — ✅ validated v1

### Game Status Tab

- [x] **GAME-01**: Rolling info box (status messages / log of clicks, hints, reveals) — ✅ validated v1
- [x] **GAME-02**: Timer — counts up after the game starts, stops on win — ✅ validated v1
- [x] **GAME-03**: Remaining hiders count — total, and per-representation when the easy difficulty toggle is set — ✅ validated v1 (Phase 4.1 closed per-rep gap)
- [x] **GAME-04**: Import button — import a game prepared by Generate & export — ✅ validated v1
- [x] **GAME-05**: Hint button — change color of the N atoms/residues around a hider (colors neighbors, not the hider itself) — ✅ validated v1
- [x] **GAME-06**: Reveal-one hider button — asks the user to confirm giving up, then marks one random hider "found" and counts the reveal use — ✅ validated v1
- [x] **GAME-07**: Reveal-all hiders button — asks the user to confirm giving up, then marks all hiders "found" — ✅ validated v1
- [x] **GAME-08**: Found-hider management dropdown — hide/show/change color of hiders with a "found" status — ✅ validated v1
- [x] **GAME-09**: Save button — save the game state as a PyMOL session (`.pse`) + a companion `.bcm` JSON sidecar (registry, timer, reveal counts, setup) for checkpointing — ✅ validated v1
- [x] **GAME-10**: Restart button — restart the game from the stored initial state — ✅ validated v1

### Core Loop

- [x] **LOOP-01**: Click-to-find — clicking an atom in the OpenGL viewer (via a `pymol.wizard.Wizard` subclass overriding `do_pick`) checks if the picked atom's `(model, index)` is a registered hider → marks it "found" (recolors or hides it) — ✅ validated v1
- [x] **LOOP-02**: Found-status tracking — a single source of truth per hider (hidden/found) that remaining-counter, found-management, reveal, and win all read — ✅ validated v1
- [x] **LOOP-03**: Win condition — when all hiders are "found", stop the timer and show a winning message with the time taken — ✅ validated v1

### Demo Content

- [x] **DEMO-01**: Bundle the small demo PDBs in the repo with sources cited in documentation (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3) — ✅ validated v1
- [x] **DEMO-02**: Fetch the large membrane-protein demo PDBs from MemProtMD on demand (1GZM helix, 3GP6 sheets) with full membrane (dppc-atomistic); strip water and salt, then compress before caching — ✅ validated v1
- [x] **DEMO-03**: Fetch the glycoprotein-with-glycan demo from SASBDB on demand (an Alpha-1-glycoprotein model); cite the source and IDs in documentation — ✅ validated v1
- [x] **DEMO-04**: Produce a `DATA_SOURCES.md` documenting all PDB IDs + DOIs + SASBDB IDs + MemProtMD attribution; verify MemProtMD per-entry license before bundling — ✅ validated v1

### Accessibility & Clarity

- [x] **UX-01**: In-game explanation — what each button does and what each representation means (tooltips / help panel) — ✅ validated v1
- [x] **UX-02**: Controls help — how to click, navigate, zoom, rotate in PyMOL (for users new to PyMOL) — ✅ validated v1

### Differentiators (v1)

- [x] **DIFF-01**: Reveal counter — track how many reveals were used across the game — ✅ validated v1
- [x] **DIFF-02**: Win-screen stats — show time taken, hints used, and reveals used on the winning message — ✅ validated v1
- [x] **DIFF-03**: Post-game debrief — after win, highlight all hiders and explain why each was hard to spot (the teachable moment) — ✅ validated v1
- [x] **DIFF-04**: Color picker for found-hider highlight — player chooses how found hiders are marked (accessibility / color-blind support) — ✅ validated v1
- [x] **DIFF-05**: Difficulty-tiered demo metadata surfaced in the demo sub-menu (Easy/Hard/Challenge/Very challenging) — ✅ validated v1

## Traceability

Which phases cover which requirements. All Complete as of v1 ship (2026-08-18).

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUGIN-01 | Phase 1 | ✅ Complete |
| PLUGIN-02 | Phase 1 | ✅ Complete |
| PLUGIN-03 | Phase 1 | ✅ Complete |
| SETUP-01 | Phase 2 | ✅ Complete |
| SETUP-02 | Phase 2 | ✅ Complete |
| SETUP-03 | Phase 2 | ✅ Complete |
| SETUP-04 | Phase 2 | ✅ Complete |
| SETUP-05 | Phase 2 | ✅ Complete |
| SETUP-06 | Phase 2 | ✅ Complete |
| DEMO-01 | Phase 2 | ✅ Complete |
| BTN-01 | Phase 2 | ✅ Complete |
| BTN-02 | Phase 2 | ✅ Complete |
| BTN-03 | Phase 2 | ✅ Complete |
| BTN-04 | Phase 2 | ✅ Complete |
| HIDER-01 | Phase 3 | ✅ Complete |
| HIDER-02 | Phase 3 | ✅ Complete |
| HIDER-06 | Phase 3 | ✅ Complete |
| LOOP-01 | Phase 4 | ✅ Complete |
| LOOP-02 | Phase 4 | ✅ Complete |
| LOOP-03 | Phase 4 | ✅ Complete |
| HIDER-04 | Phase 4 | ✅ Complete |
| BTN-07 | Phase 4 | ✅ Complete |
| GAME-01 | Phase 4 | ✅ Complete |
| GAME-02 | Phase 4 | ✅ Complete |
| GAME-03 | Phase 4 + 4.1 | ✅ Complete |
| HIDER-03 | Phase 5 | ✅ Complete |
| HIDER-05 | Phase 5 + 11 | ✅ Complete |
| GAME-05 | Phase 6 | ✅ Complete |
| GAME-06 | Phase 6 | ✅ Complete |
| GAME-07 | Phase 6 | ✅ Complete |
| DIFF-01 | Phase 6 | ✅ Complete |
| GAME-08 | Phase 7 | ✅ Complete |
| GAME-10 | Phase 7 | ✅ Complete |
| BTN-06 | Phase 7 | ✅ Complete |
| DIFF-04 | Phase 7 | ✅ Complete |
| GAME-09 | Phase 8 | ✅ Complete |
| GAME-04 | Phase 8 | ✅ Complete |
| BTN-05 | Phase 8 | ✅ Complete |
| DEMO-02 | Phase 9 | ✅ Complete |
| DEMO-03 | Phase 9 | ✅ Complete |
| DEMO-04 | Phase 9 | ✅ Complete |
| DIFF-05 | Phase 9 | ✅ Complete |
| UX-01 | Phase 10 | ✅ Complete |
| UX-02 | Phase 10 | ✅ Complete |
| DIFF-02 | Phase 10 | ✅ Complete |
| DIFF-03 | Phase 10 | ✅ Complete |

---

## Milestone Summary

**Shipped:** 46 of 46 v1 requirements
**Adjusted:** None — all requirements delivered as specified
**Dropped:** None

**Notes:**
- HIDER-05 (cartoon/ribbon hider) was the highest-risk requirement. The original alt-conf approach (Phase 5 05-06/05-08) failed across 4 GUI bug cycles; Phase 11 resolved it via a single-state new-chain copy refactor (abandoning alt-conf mid-execution). Final outcome meets the requirement (connected, blended cartoon hiders verified on 1ubq).
- GAME-03 (per-rep remaining display) was explicitly deferred from Phase 4 (04-RESEARCH.md:618) and closed by inserted Phase 04.1 (2026-08-17).
- 7 requirement checkboxes in the live REQUIREMENTS.md remained `[ ]` (BTN-07, HIDER-04, GAME-01, GAME-02, LOOP-01, LOOP-02, LOOP-03) despite the Traceability table marking them Complete and every phase verification confirming them satisfied — a cosmetic doc-sync gap, not a coverage gap. All marked `[x]` in this archive.

---
*Archived: 2026-08-18 as part of v1 milestone completion*
