# Requirements: bioCHEMeleon

**Defined:** 2026-08-22 (milestone v2.0 — VMD tcl port)
**Core Value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.

**Scope note:** v1 (PyMOL 2.5.0 plugin, 46 requirements, shipped 2026-08-18) is archived in `milestones/v1-REQUIREMENTS.md`. The requirements below are **v2.0-only** — they cover the VMD tcl port. v1's validated PyMOL requirements are NOT re-listed here; v2's requirement set is the port of v1's feature set to VMD's data model + VMD-specific additions (materials, extra reps, headless testing), formalized from the research SUMMARY.md must-have/should-have features and cross-checked against the 9 PROJECT.md "Active" checkboxes (PROJECT.md lines 64-72).

## v2.0 Requirements

Requirements for the VMD 1.9.3 tcl port. Each maps to exactly one roadmap phase (13-23).

### Bootstrap & Extension Entry

- [x] **ENTRY-01**: Sourced tcl script + `biochemeleon` command opens a modeless Tk `toplevel` with a `ttk::notebook` (Setup + Game tabs); the main dialog does NOT use `grab set` so the 3D viewer stays interactive for click-to-find
- [x] **ENTRY-02**: Extension registers an "bioCHEMeleon" item in the VMD Extensions menu via `vmd_install_extension`; a re-source guard (`info exists`) prevents state reset / duplicate dialogs on re-sourcing
- [x] **ENTRY-03**: All v2 code lives under `vmd/` (multi-viewer layout mirroring `pymol/`); zero external dependencies — only what VMD 1.9.3 ships (tcl/Tk 8.5 + ttk)

### Setup Tab — Configuration

- [ ] **SETUP-01**: Molecule dropdown — pick a loaded molecule (via `molinfo list`), fetch from PDB, or choose from the bundled demo set (with a sub-menu for demo categories)
- [ ] **SETUP-02**: Hider count input, capped to a reasonable maximum relative to the molecule's atom count
- [ ] **SETUP-03**: "Lock current scene" checkbox — when true, generate hiders from the current representations and detect the rep list from the scene; when false, randomize representations and list all available reps
- [ ] **SETUP-04**: Per-representation hider list with optional per-rep counts (random per-rep totaling the hider count if unspecified)
- [ ] **SETUP-05**: Difficulty toggle — show only total remaining hiders (hard) vs. also show remaining per representation (easy)
- [ ] **SETUP-06**: Random total hider count distributed across all available reps from the start (v1.1 quick-008 fix baked in, not a post-ship patch — never all-spheres when only a total is set)

### Setup Tab — 7 Buttons

- [ ] **BTN-01**: Reset — restore default settings
- [ ] **BTN-02**: Randomize — randomize the setup parameters
- [ ] **BTN-03**: Save Setup — save game setup parameters to a file
- [ ] **BTN-04**: Load Setup — load setup parameters from a file
- [ ] **BTN-05**: Generate & export — generate the game and save the initial state to a file for sharing / later loading (paired with GAME-04 Import)
- [ ] **BTN-06**: Cleanup model — remove all game-generated representations/atoms not in the original molecule (via `resname GAM and beta < 0` sentinel, never generic filters)
- [ ] **BTN-07**: Start — store the initial state, generate hiders per setup, switch to the Game status tab, and count down 3-2-1

### Hider Generation

- [ ] **HIDER-01**: Hider generation via PDB-rebuild (Option D) — write a combined PDB (real + hider atoms with strict column alignment), `mol new` reload as a single molecule; hiders live in the SAME molecule as real atoms (player can't isolate them by toggling molecule visibility)
- [ ] **HIDER-02**: Hider sentinel `resname=GAM` + `beta=-999` + `segid=GAME` set in-place via `atomselect` after load (robust against PDB column bugs); hider registry keyed by atom `index` (stable within a molid's lifetime), reconstructable from sentinels on reload
- [ ] **HIDER-03**: Sphere/VDW hiders — place anywhere in the bounding region (simplest generator; MVP)
- [ ] **HIDER-04**: Line/Licorice hiders — new atoms mimic connected atoms or alternate positions
- [ ] **HIDER-05**: Cartoon/NewCartoon hiders — splice a full residue (Cα + neighbors) with `mol ssrecalc`, OR use Tube/Trace as SS-independent alternatives to sidestep the STRIDE `ss='L'` caveat for fake `GAM` residues
- [ ] **HIDER-06**: Research-driven selection of which VMD representations are viable for the blend-in mechanic — 10-rep GAME_REPS list (Lines, VDW, Licorice, CPK, Cartoon, NewCartoon, Trace, Tube, Points, DynamicBonds); surface/volumetric reps are anti-features

### Core Loop

- [ ] **LOOP-01**: Click-to-find — clicking an atom in the OpenGL viewer (via a VMD pick mechanism) checks if the picked atom's `index` is a registered hider → marks it "found" (recolors or hides it)
- [ ] **LOOP-02**: Found-status tracking — a single source of truth per hider (found/hidden) that remaining-counter, found-management, reveal, and win all read
- [ ] **LOOP-03**: Win condition — when all hiders are "found", stop the timer and show a winning message with the time taken

### Game Status Tab

- [ ] **GAME-01**: Rolling info box (status messages / log of clicks, hints, reveals)
- [ ] **GAME-02**: Timer — counts up after the game starts, stops on win
- [ ] **GAME-03**: Remaining hiders count — total, and per-representation when the easy difficulty toggle is set
- [ ] **GAME-04**: Import button — import a game prepared by Generate & export
- [ ] **GAME-05**: Hint button — change color of the N atoms/residues around a hider (colors neighbors, not the hider itself)
- [ ] **GAME-06**: Reveal-one hider button — asks the user to confirm giving up, then marks one random hider "found" and counts the reveal use
- [ ] **GAME-07**: Reveal-all hiders button — asks the user to confirm giving up, then marks all hiders "found"
- [ ] **GAME-08**: Found-hider management dropdown — hide/show/change color of hiders with a "found" status
- [ ] **GAME-09**: Save button — save the game state as a combined-PDB + hand-rolled `.bcm` JSON sidecar (registry, timer, reveal counts, setup, found-status, original PDB path), zipped into `.bcmz` for checkpointing
- [ ] **GAME-10**: Restart button — restart the game from the stored initial state (`mol delete` + reload original PDB + re-apply saved reps)

### VMD Materials (v2 Differentiator)

- [ ] **MATERIAL-01**: Explore whether VMD's material system (Glass, Translucent, EdgyGlass, Metallic, etc.) adds a blending dimension beyond v1's rep-based approach — material-blend hiders via `material add GameBlend` + `material change opacity` + `mol modmaterial`
- [ ] **MATERIAL-02**: Setup tab "use material blending" toggle + curated material set (Glass1/Glass2/Glass3/Translucent + custom GameBlend); pedagogical value (noticing material/lighting artifacts) documented as a gameplay-validation hypothesis

### Demo Content

- [ ] **DEMO-01**: Reuse v1's 6 bundled small demo PDBs (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3) with their `SOURCES.md` citations (PDBs are viewer-agnostic; citations human-approved in v1)
- [ ] **DEMO-02**: Fetch the large membrane-protein demo PDBs from MemProtMD on demand (1GZM, 3GP6); strip water and salt, then compress before caching to `data/demos/cache/`
- [ ] **DEMO-03**: Fetch the glycoprotein-with-glycan demo from SASBDB on demand; cite the source and IDs in documentation
- [ ] **DEMO-04**: Reuse v1's `DATA_SOURCES.md` / `SOURCES.md` attribution (human-approved CC0/RCSB/MemProtMD citations); verify MemProtMD per-entry license before bundling

### Testing & Infrastructure

- [x] **TEST-01**: Headless testing via `vmd -dispdev text -e <script> -eofexit` from WSL (closes the WSL/Windows runtime gap for tcl scripts — the v2 equivalent of v1's `run-conda-pymol.bat -cq`)
- [x] **TEST-02**: Pure-layer architecture — `lib/setup_state.tcl` + `lib/registry.tcl` are stdlib-only tcl (NO `mol`/`atomselect`/`tk`), unit-testable in WSL via `tclsh` + `tcltest` (no VMD, no Python); strict dependency direction (pure ← interop ← controller)
- [ ] **TEST-03**: Seek user approval for any additional VMD tcl libs (e.g. tooltip.tcl — staged in `vmd-ref/` as reference); if approved, vendor under `vmd/3rd_party_lib/` (git-ignored) with the library's license noted — preferred: write a ~30-line pure-Tk helper (zero-dep)

### Accessibility & Clarity

- [ ] **UX-01**: In-game explanation — what each button does and what each representation/material means (help panel / tooltips)
- [ ] **UX-02**: Controls help — how to click, navigate, zoom, rotate in VMD, including the pick-vs-rotate mouse-mode toggle (pick/rotate are mutually exclusive in VMD)

### Differentiators

- [ ] **DIFF-01**: Reveal counter — track how many reveals were used across the game
- [ ] **DIFF-02**: Win-screen stats — show time taken, hints used, and reveals used on the winning message
- [ ] **DIFF-03**: Post-game debrief — after win, highlight all hiders and explain why each was hard to spot (the teachable moment)
- [ ] **DIFF-04**: Color picker for found-hider highlight — player chooses how found hiders are marked (accessibility / color-blind support)
- [ ] **DIFF-05**: Difficulty-tiered demo metadata surfaced in the demo sub-menu (Easy/Hard/Challenge/Very challenging)

### Documentation

- [ ] **DOC-01**: Root README.md updated to reflect multi-viewer architecture — covers both the PyMOL plugin (v1, shipped) and the VMD tcl script (v2), with links to per-viewer sub-dir READMEs
- [ ] **DOC-02**: `vmd/README.md` — install and use instructions for the VMD 1.9.3 tcl script (sourcing, Extensions menu entry, headless testing via `vmd -dispdev text`, bundled demo set)
- [ ] **DOC-03**: `pymol/README.md` — install and use instructions for the v1 PyMOL 2.5.0 plugin (Plugin Manager install, bundled demos, known limitations), updated if the v2 layout changed the v1 install path

## Traceability

Which phases cover which requirements. v2.0 phases are numbered 13-23 (continuing from v1's phase 11 + 04.1; clean numbering per milestone convention). Decimal phases 17.1/17.2 split the rep generator work by complexity tier.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENTRY-01 | Phase 13 | Complete |
| ENTRY-02 | Phase 13 | Complete |
| ENTRY-03 | Phase 13 | Complete |
| TEST-01 | Phase 13 | Complete |
| TEST-02 | Phase 13 | Complete |
| SETUP-01 | Phase 14 | Complete |
| SETUP-02 | Phase 14 | Complete |
| SETUP-03 | Phase 14 | Complete |
| SETUP-04 | Phase 14 | Complete |
| SETUP-05 | Phase 14 | Complete |
| SETUP-06 | Phase 14 | Complete |
| BTN-01 | Phase 14 | Complete |
| BTN-02 | Phase 14 | Complete |
| BTN-03 | Phase 14 | Complete |
| BTN-04 | Phase 14 | Complete |
| DEMO-01 | Phase 14 | Complete |
| HIDER-01 | Phase 15 | Pending |
| HIDER-02 | Phase 15 | Pending |
| HIDER-03 | Phase 16 | Pending |
| LOOP-01 | Phase 16 | Pending |
| LOOP-02 | Phase 16 | Pending |
| LOOP-03 | Phase 16 | Pending |
| BTN-07 | Phase 16 | Pending |
| GAME-01 | Phase 16 | Pending |
| GAME-02 | Phase 16 | Pending |
| GAME-03 | Phase 16 | Pending |
| HIDER-04 | Phase 17.1 | Pending |
| HIDER-05 | Phase 17.2 | Pending |
| HIDER-06 | Phase 17.1 | Pending |
| MATERIAL-01 | Phase 18 | Pending |
| MATERIAL-02 | Phase 18 | Pending |
| GAME-05 | Phase 19 | Pending |
| GAME-06 | Phase 19 | Pending |
| GAME-07 | Phase 19 | Pending |
| GAME-08 | Phase 19 | Pending |
| GAME-10 | Phase 19 | Pending |
| BTN-06 | Phase 19 | Pending |
| DIFF-01 | Phase 19 | Pending |
| DIFF-04 | Phase 19 | Pending |
| GAME-09 | Phase 20 | Pending |
| GAME-04 | Phase 20 | Pending |
| BTN-05 | Phase 20 | Pending |
| DEMO-02 | Phase 21 | Pending |
| DEMO-03 | Phase 21 | Pending |
| DEMO-04 | Phase 21 | Pending |
| DIFF-05 | Phase 21 | Pending |
| UX-01 | Phase 22 | Pending |
| UX-02 | Phase 22 | Pending |
| DIFF-02 | Phase 22 | Pending |
| DIFF-03 | Phase 22 | Pending |
| TEST-03 | Phase 22 | Pending |
| DOC-01 | Phase 23 | Pending |
| DOC-02 | Phase 23 | Pending |
| DOC-03 | Phase 23 | Pending |

## Coverage

- **Total v2.0 requirements:** 54
- **Mapped:** 54/54 ✓ (no orphans, no duplicates — each requirement maps to exactly one phase)
- **PROJECT.md active checkboxes covered:** 9/9 ✓
  1. Sourced tcl script + command → ENTRY-01, ENTRY-02, LOOP-01/02/03
  2. Hider gen adapted to VMD rep system → HIDER-01, HIDER-04, HIDER-05, HIDER-06
  3. Random total distribution (quick-008 baked in) → SETUP-06
  4. Research/limit viable VMD reps → HIDER-06
  5. Explore VMD material system → MATERIAL-01, MATERIAL-02
  6. Headless testing via `vmd -dispdev text` → TEST-01
  7. Reuse v1 demo PDB set → DEMO-01, DEMO-02, DEMO-03, DEMO-04
  8. Code under `vmd/` (multi-viewer layout) → ENTRY-03
  9. Seek approval for additional tcl libs (tooltip.tcl) → TEST-03
- **Additional (non-PROJECT.md):** 3 documentation requirements (DOC-01, DOC-02, DOC-03 → Phase 23) — multi-viewer README deliverables from roadmap revision

---
*Defined: 2026-08-22 for milestone v2.0 (VMD tcl port)*
