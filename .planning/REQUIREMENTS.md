# Requirements: bioCHEMeleon

**Defined:** 2026-08-02
**Core Value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Plugin Installation

- [x] **PLUGIN-01**: Plugin installs as a standard PyMOL plugin via the GUI Plugin Manager (universal across platforms; works with Windows conda PyMOL accessed via setenv.bat from WSL)
- [x] **PLUGIN-02**: Plugin registers a menu item "bioCHEMeleon" via `__init_plugin__` + `addmenuitemqt`; when the user manually activates the plugin (clicks the menu item), the setup window pops up
- [x] **PLUGIN-03**: Plugin packaged as a `biochemeleon/` package directory with `__init__.py` (multi-file: gui_setup, gui_game, wizard, game, demos)

### Setup Tab — Configuration

- [x] **SETUP-01**: Setup window opens on launch with configurable game parameters (PyQt5 via `pymol.Qt`, `QTabWidget` with Setup + Game tabs)
- [x] **SETUP-02**: Object selector dropdown: pick a loaded object, fetch from PDB, or choose from the demo set (with a sub-menu for demo categories)
- [x] **SETUP-03**: Hider count input, capped to a reasonable maximum relative to the object's atom count
- [x] **SETUP-04**: "Lock current scene" checkbox — when true, generate hiders from the current representations and detect the rep list from the scene; when false, randomize representations and list all available reps
- [x] **SETUP-05**: Per-representation hider list with checkboxes; after ticking, a form/textbox/spinwheel sets the per-rep count (if unset, random per-rep totaling the hider count)
- [x] **SETUP-06**: Difficulty toggle: show only total remaining hiders (hard) vs. also show remaining per representation (easy)

### Setup Tab — 7 Buttons

- [x] **BTN-01**: Reset — restore default settings
- [x] **BTN-02**: Randomize — randomize the setup parameters
- [x] **BTN-03**: Save Setup — save game setup parameters to a file
- [x] **BTN-04**: Load Setup — load setup parameters from a file
- [ ] **BTN-05**: Generate & export — only generate the representation of the game and save the initial state to a file for sharing or later loading
- [ ] **BTN-06**: Cleanup model — remove all game-generated representations/atoms not in the original object (via `segi='GAME'` sentinel, never generic filters)
- [ ] **BTN-07**: Start — store the initial state, generate hiders per setup, switch to the Game status tab, and count down 3-2-1

### Hider Generation

- [x] **HIDER-01**: Hiders are new atoms/coordinates inserted INTO the same PyMOL object as the molecule (via `cmd.pseudoatom(object=existing)`/`cmd.fuse`), not a separate object
- [x] **HIDER-02**: Every hider is tagged with a `segi='GAME'` + `b=-999` sentinel and tracked by `id` in a HiderRegistry
- [ ] **HIDER-03**: Line/stick hiders — new atoms mimic connected atoms or alternate positions
- [ ] **HIDER-04**: Sphere hiders — place anywhere in the bounding region
- [ ] **HIDER-05**: Cartoon/ribbon hiders — extend at a terminal, or replicate a segment (e.g. a loop) as an alternate position; uses C-alpha
- [x] **HIDER-06**: Hider generation records every generated hider's `(object, atom-ID)` in the registry (foundation for cleanup, hint, reveal, found-status)

### Game Status Tab

- [ ] **GAME-01**: Rolling info box (status messages / log of clicks, hints, reveals)
- [ ] **GAME-02**: Timer — counts up after the game starts, stops on win
- [ ] **GAME-03**: Remaining hiders count — total, and per-representation when the easy difficulty toggle is set
- [ ] **GAME-04**: Import button — import a game prepared by Generate & export
- [ ] **GAME-05**: Hint button — change color of the N atoms/residues around a hider (colors neighbors, not the hider itself)
- [ ] **GAME-06**: Reveal-one hider button — asks the user to confirm giving up, then marks one random hider "found" and counts the reveal use
- [ ] **GAME-07**: Reveal-all hiders button — asks the user to confirm giving up, then marks all hiders "found"
- [ ] **GAME-08**: Found-hider management dropdown — hide/show/change color of hiders with a "found" status
- [ ] **GAME-09**: Save button — save the game state as a PyMOL session (`.pse`) + a companion `.bcm` JSON sidecar (registry, timer, reveal counts, setup) for checkpointing
- [ ] **GAME-10**: Restart button — restart the game from the stored initial state

### Core Loop

- [ ] **LOOP-01**: Click-to-find — clicking an atom in the OpenGL viewer (via a `pymol.wizard.Wizard` subclass overriding `do_pick`) checks if the picked atom's `(model, index)` is a registered hider → marks it "found" (recolors or hides it)
- [ ] **LOOP-02**: Found-status tracking — a single source of truth per hider (hidden/found) that remaining-counter, found-management, reveal, and win all read
- [ ] **LOOP-03**: Win condition — when all hiders are "found", stop the timer and show a winning message with the time taken

### Demo Content

- [x] **DEMO-01**: Bundle the small demo PDBs in the repo with sources cited in documentation:
  - Protein Easy: 1znf; Hard: 1xdn
  - Nucleic acid Easy: RNA 5E54, DNA 1K8P; Hard: 2QBZ
  - Mixed: 4WB3
- [ ] **DEMO-02**: Fetch the large membrane-protein demo PDBs from MemProtMD on demand (1GZM helix, 3GP6 sheets) with full membrane (dppc-atomistic); strip water and salt, then compress before caching
- [ ] **DEMO-03**: Fetch the glycoprotein-with-glycan demo from SASBDB on demand (an Alpha-1-glycoprotein model); cite the source and IDs in documentation
- [ ] **DEMO-04**: Produce a `DATA_SOURCES.md` documenting all PDB IDs + DOIs + SASBDB IDs + MemProtMD attribution; verify MemProtMD per-entry license before bundling

### Accessibility & Clarity

- [ ] **UX-01**: In-game explanation — what each button does and what each representation means (tooltips / help panel)
- [ ] **UX-02**: Controls help — how to click, navigate, zoom, rotate in PyMOL (for users new to PyMOL)

### Differentiators (v1)

- [ ] **DIFF-01**: Reveal counter — track how many reveals were used across the game
- [ ] **DIFF-02**: Win-screen stats — show time taken, hints used, and reveals used on the winning message
- [ ] **DIFF-03**: Post-game debrief — after win, highlight all hiders and explain why each was hard to spot (the teachable moment)
- [ ] **DIFF-04**: Color picker for found-hider highlight — player chooses how found hiders are marked (accessibility / color-blind support)
- [ ] **DIFF-05**: Difficulty-tiered demo metadata surfaced in the demo sub-menu (Easy/Hard/Challenge/Very challenging)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### VMD tcl Script

- **VMD-01**: Sourced tcl + command to launch a GUI; general gameplay similar to PyMOL
- **VMD-02**: Research and limit the set of VMD materials/representations the game plays on
- **VMD-03**: Seek approval for any additional VMD tcl libs (e.g. tooltip.tcl)

### Future Enhancements

- **FUT-01**: Shareable-puzzle educator workflow polish (one-click "puzzle pack" bundling)
- **FUT-02**: Sound effects / ambient audio (requires audio lib approval)
- **FUT-03**: Local achievements (no cloud)
- **FUT-04**: Optional "puzzle authoring" mode (curate which atoms become hiders, place by hand)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Surface representation hiders | Does not fit the blend-in mechanic (continuous mesh, not discrete atoms); explicitly excluded by spec |
| VMD plugin in v1 | Different tech stack (tcl vs python) and testing; deferred to v2 milestone |
| Web backend / cloud / online leaderboard | Out of scope per spec (no web/backend); offline educational tool |
| Auto-fetching/installing external Python libs silently | Explicit constraint — any non-PyMOL dependency must be listed, approved, then user-installed or vendored into `./3rd_party_lib` with license noted |
| Real-time / network multiplayer | Massive scope; PyMOL is single-user desktop |
| Touch / mobile support | PyMOL is desktop OpenGL |
| Procedural generation of novel molecules | Risks scientific inaccuracy; game inserts atoms into existing objects only |
| Adaptive AI difficulty scaling | Over-engineering for v1; setup params + curated tiers already give difficulty control |
| Sound effects / background music (v1) | Asset + dependency complexity; deferred to future |
| In-app plugin self-update mechanism | Standard PyMOL Plugin Manager install/update flow is enough |
| Custom 3D rendering / shaders for hiders | Rely on PyMOL's built-in OpenGL + `cmd.color`/`cmd.hide` |
| Modifying the original molecule's atoms | Breaks scientific integrity; only ADD atoms/coords, never alter real atoms |
| Installing conda envs / system packages from within the plugin | Explicit environment constraint — WSL may not install; PyMOL runs in Windows conda via setenv.bat |
| Cloud achievements / badges sync | Implies backend (excluded) |
| Hard time limit / fail state | Timer is for scoring, not failure; cozy-educational tone; player can always reveal-all to end |
| Tkinter / Pmw GUI | PyQt5 via `pymol.Qt` is the modern PyMOL 2.5 toolkit; Tkinter is the same legacy family as Pmw (no live Tk root under Qt build) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation (2026-08-03).

| Requirement | Phase | Status |
|-------------|-------|--------|
| PLUGIN-01 | Phase 1 | Complete |
| PLUGIN-02 | Phase 1 | Complete |
| PLUGIN-03 | Phase 1 | Complete |
| SETUP-01 | Phase 2 | Complete |
| SETUP-02 | Phase 2 | Complete |
| SETUP-03 | Phase 2 | Complete |
| SETUP-04 | Phase 2 | Complete |
| SETUP-05 | Phase 2 | Complete |
| SETUP-06 | Phase 2 | Complete |
| DEMO-01 | Phase 2 | Complete |
| BTN-01 | Phase 2 | Complete |
| BTN-02 | Phase 2 | Complete |
| BTN-03 | Phase 2 | Complete |
| BTN-04 | Phase 2 | Complete |
| HIDER-01 | Phase 3 | Complete |
| HIDER-02 | Phase 3 | Complete |
| HIDER-06 | Phase 3 | Complete |
| LOOP-01 | Phase 4 | Pending |
| LOOP-02 | Phase 4 | Pending |
| LOOP-03 | Phase 4 | Pending |
| HIDER-04 | Phase 4 | Pending |
| BTN-07 | Phase 4 | Pending |
| GAME-01 | Phase 4 | Pending |
| GAME-02 | Phase 4 | Pending |
| GAME-03 | Phase 4 | Pending |
| HIDER-03 | Phase 5 | Pending |
| HIDER-05 | Phase 5 | Pending |
| GAME-05 | Phase 6 | Pending |
| GAME-06 | Phase 6 | Pending |
| GAME-07 | Phase 6 | Pending |
| DIFF-01 | Phase 6 | Pending |
| GAME-08 | Phase 7 | Pending |
| GAME-10 | Phase 7 | Pending |
| BTN-06 | Phase 7 | Pending |
| DIFF-04 | Phase 7 | Pending |
| GAME-09 | Phase 8 | Pending |
| GAME-04 | Phase 8 | Pending |
| BTN-05 | Phase 8 | Pending |
| DEMO-02 | Phase 9 | Pending |
| DEMO-03 | Phase 9 | Pending |
| DEMO-04 | Phase 9 | Pending |
| DIFF-05 | Phase 9 | Pending |
| UX-01 | Phase 10 | Pending |
| UX-02 | Phase 10 | Pending |
| DIFF-02 | Phase 10 | Pending |
| DIFF-03 | Phase 10 | Pending |

**Coverage:**
- v1 requirements: 46 total (previously miscounted as 41 — the DIFF section's 5 requirements were not included in the prior count; 41 + 5 = 46)
- Mapped to phases: 46
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-02*
*Last updated: 2026-08-03 after roadmap creation (traceability populated)*
