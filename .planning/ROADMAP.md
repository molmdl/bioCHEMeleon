# Roadmap: bioCHEMeleon

## Milestones

- ✅ **v1** — Phases 1-11 + 04.1 (shipped 2026-08-18) — 12 phases, 77 plans, 46/46 requirements. Full details: [milestones/v1-ROADMAP.md](milestones/v1-ROADMAP.md)
- 🚧 **v2.0 VMD tcl Port** — Phases 13-23 (in progress) — 12 phases, 54 requirements
- 📋 **chimeraX port** — future milestone candidate (placeholder dir `chimeraX/` exists; research needed)

---

## v1.0 PyMOL Plugin (SHIPPED)

<details>
<summary>✅ v1.0 (Phases 1-11 + 04.1) — SHIPPED 2026-08-18 — 12 phases, 77 plans, 46/46 requirements ✅ PASSED audit</summary>

**Milestone audit:** ✅ PASSED — 46/46 requirements, 12/12 phases, 9/9 integration, 6/6 E2E flows.

v1 built a PyMOL 2.5.0 plugin that turns a loaded molecular object into a hide-and-seek puzzle. The journey: clean plugin shell → Setup tab + bundled demos → mutation-safety foundation (de-risked before generators) → MVP core loop with sphere hiders (the core value) → line/stick + cartoon generators → hint/reveal → found-management/restart/cleanup → persistence + shareable puzzles → large fetched demos + attribution → polish/endgame/help → alt-conf cartoon fix.

Full phase details, plans, and summaries: [`milestones/v1-ROADMAP.md`](milestones/v1-ROADMAP.md). Requirements: [`milestones/v1-REQUIREMENTS.md`](milestones/v1-REQUIREMENTS.md). Audit: [`milestones/v1-MILESTONE-AUDIT.md`](milestones/v1-MILESTONE-AUDIT.md).

</details>

---

## 🚧 v2.0 VMD tcl Port (In Progress)

**Milestone Goal:** Port v1's hide-and-seek game to VMD 1.9.3 as a sourced tcl script — same core gameplay (load → generate hiders → click-to-find → win), adapted to VMD's data model (PDB-rebuild instead of in-place insertion; no undo, no global atom id), with an MVP-first approach, research-driven representation selection, random per-rep distribution baked in from the start, and VMD's material system explored as a v2 differentiator.

**Phases:** 13-23 (12 phases, comprehensive depth — mirrors v1's proven de-risking sequence, adapted to VMD-specific risks)
**Requirements:** 54 (see [REQUIREMENTS.md](REQUIREMENTS.md))
**Key principle (from v1):** Ship the load → generate → click-to-find → win loop as soon as the foundation allows, because if nothing else works, that loop must work.

**v1→v2 architectural changes (from research):**
- **PDB-rebuild** replaces in-place insertion (VMD has no `pseudoatom` analog) — highest-risk change, de-risked in Phase 15
- **Backup = reload original PDB** (VMD has no undo, no per-atom delete)
- **Registry keyed by atom `index`** (VMD has no global atom id; molid changes on every reload → sentinel reconstruction)
- **`.bcm` JSON sidecar hand-rolled** (VMD 1.9.3 has no `json` package; `save_state` drops beta/user/segid)
- **Pure-layer tcl** (`lib/setup_state.tcl` + `lib/registry.tcl`) unit-testable in WSL via `tclsh`/`tcltest` — direct port of v1's Python pure layer
- **Materials** as a NEW v2 blending dimension (VMD's 23-material system)

### Phase 13: Bootstrap & Sourced Entry

**Goal**: The script loads cleanly into VMD and opens a modeless dialog — the stable shell every later phase builds on, with the 3D viewer kept interactive for click-to-find.
**Depends on**: Nothing (first v2 phase)
**Requirements**: ENTRY-01, ENTRY-02, ENTRY-03, TEST-01, TEST-02
**Plans:** 2 plans (complete)

**Success Criteria** (what must be TRUE):
1. Sourcing `biochemeleon.tcl` in a VMD session registers an "bioCHEMeleon" item in the Extensions menu (via `vmd_install_extension`) with no errors, and re-sourcing the script does not reset state or duplicate the dialog (re-source guard works).
2. Running the `biochemeleon` command (console or Extensions menu) opens a modeless `ttk::notebook` dialog with Setup and Game placeholder tabs; the 3D viewer stays interactive (the user can rotate the molecule while the dialog is open).
3. The script runs headlessly from WSL via `vmd -dispdev text -e <script> -eofexit` without error (the `source` + `biochemeleon` smoke passes).
4. The pure layer (`lib/setup_state.tcl`) loads under `tclsh` with no `mol`/`tk` dependency and is ready for `tcltest` (strict layering + zero external deps established from day one).

Plans:
- [x] 13-01-PLAN.md — Pure-layer tcl (lib/setup_state.tcl + lib/registry.tcl) + tcltest harness under headless VMD [TEST-02, half ENTRY-03] — completed 2026-08-28
- [x] 13-02-PLAN.md — Entry script (biochemeleon.tcl) + headless smoke + GUI human-verify checkpoint [ENTRY-01, ENTRY-02, half ENTRY-03, TEST-01] — completed 2026-08-29

### Phase 14: Setup Tab & Bundled Demos

**Goal**: The user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience, before touching the risky PDB-rebuild.
**Depends on**: Phase 13
**Requirements**: SETUP-01, SETUP-02, SETUP-03, SETUP-04, SETUP-05, SETUP-06, BTN-01, BTN-02, BTN-03, BTN-04, DEMO-01
**Plans:** 4 plans

**Success Criteria** (what must be TRUE):
1. The Setup tab shows a molecule dropdown (loaded molecules via `molinfo list` + bundled demos + PDB-fetch option); selecting a bundled demo loads it into VMD via `mol new` (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3).
2. The user can set a hider count (capped to atom count), toggle "Lock current scene", select reps with optional per-rep counts, and set difficulty — all reflected in the setup state, and a total-only count randomly distributes across all reps (quick-008 baked in).
3. The Reset / Randomize / Save Setup / Load Setup buttons each work as labeled; Save/Load round-trips the full setup parameters to/from a file.
4. The pure setup-state model is unit-tested via `tcltest` in WSL (DEFAULTS, hider-count cap, randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST).

Plans:
- [x] 14-01-PLAN.md — Pure-layer setup-state logic (validate_state full + randomize_state + randomize_per_rep quick-008) via TDD [SETUP-02, SETUP-04, SETUP-06, half SETUP-05] — completed 2026-08-29
- [x] 14-02-PLAN.md — Mol bridge demos.tcl (load_demo, get_active_reps, save/load_setup, fetch_pdb stub) + headless smoke [DEMO-01, half SETUP-01, BTN-03/04 backend] — completed 2026-08-29
- [x] 14-03-PLAN.md — GUI structure: extract open_dialog to dialog.tcl + build setup_tab.tcl form (3-mode selector, dropdown, spinbox, per-rep rows, 4 buttons) + collect_state/apply_state [SETUP-01/03/05, BTN-01/02/03/04 UI] — completed 2026-08-29
- [x] 14-04-PLAN.md — Wire GUI callbacks (refresh_mol_menu trace, select_demo, do_reset/randomize/save/load, WM_DELETE handler) + GUI human-verify checkpoint [SETUP-01..06, BTN-01..04, DEMO-01] — completed 2026-08-29 (checkpoint approved)

### Phase 15: Mutation Safety & Hider Registry ⚠️ HIGHEST RISK

**Goal**: Hiders can be generated into a molecule and cleaned up, leaving the original intact — the highest-risk VMD-specific unknown (no in-place insertion) is de-risked BEFORE any generator is built on it.
**Depends on**: Phase 13 (pure layer), Phase 14 (mol new / molinfo proven)
**Requirements**: HIDER-01, HIDER-02
**Plans:** 5 plans

**Success Criteria** (what must be TRUE):
1. Given a loaded molecule, the backup → rebuild combined PDB → `mol new` → tag sentinels (atomselect) sequence produces a single molecule containing original + hider atoms, with hiders tagged `resname=GAM`/`beta=-999`/`segid=GAME` (verified via `atomselect` count and the canonical selector `resname GAM and beta < 0`).
2. Cleanup (`mol delete` game-molecule + `mol new` original PDB + re-apply saved reps) restores the original molecule exactly (same atom count, same reps) — no hider residue remains; restart uses the same mechanism.
3. The hider registry (pure `dict` in `lib/registry.tcl`) records each hider's `index` and reconstructs from sentinels on reload — unit-tested via `tcltest` in WSL without VMD (dependency-injected sentinel reconstruction, direct port of v1's pattern).
4. Viewpoint and rep list are saved before mutation and restored on the new molid after reload (viewmaster-style save/restore round-trip).

Plans:
- [ ] 15-01-PLAN.md — Pure-layer registry real logic (count_hiders + reset) via TDD + tcltest under headless VMD [SC3]
- [ ] 15-02-PLAN.md — mutation.tcl mol bridge: PDB-rebuild engine (5 procs) + headless smoke [SC1, SC3-DI]
- [ ] 15-03-PLAN.md — backup.tcl mol bridge: viewpoint + rep save/restore on a NEW molid (snapshot/apply/restore) + headless smoke [SC2, SC4]
- [ ] 15-04-PLAN.md — game.tcl composition root (start/cleanup/restart) + wire entry source order + headless smoke [SC2, SC3, SC4 integration]
- [ ] 15-05-PLAN.md — Phase-15 capstone smoke: full backup→mutate→reconstruct→cleanup→restore pipeline proving SC1-SC4 end-to-end

### Phase 16: MVP Core Loop (Sphere) ⚠️ PICK MECHANISM HUMAN-VERIFY

**Goal**: The player can play a complete hide-and-seek round with sphere hiders — the PROJECT.md core value. If nothing else works, this loop works. The VMD pick-callback contract is locked here via a GUI human-verify checkpoint.
**Depends on**: Phase 14 (Setup tab + demos), Phase 15 (mutation safety)
**Requirements**: HIDER-03, LOOP-01, LOOP-02, LOOP-03, BTN-07, GAME-01, GAME-02, GAME-03
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Clicking Start generates sphere hiders per setup (PDB-rebuild), switches to the Game tab, counts down 3-2-1, and starts the timer.
2. Clicking an atom in the viewer (via the VMD pick mechanism) correctly identifies whether it is a registered hider and marks found hiders (recolors/hides) — the pick contract is locked via a real VMD GUI session human-verify (PickBridge supports trace + callback-list + label-poll fallback).
3. The rolling info box logs clicks/found events; the remaining-hiders count (total + per-rep in easy mode) decrements on each find.
4. When all hiders are found, the timer stops and a winning message shows the time taken.
5. A pick-vs-rotate control is available so the player can rotate the view between picks (VMD pick/rotate are mutually exclusive mouse modes).

Plans:
- [ ] 16-01: TBD

### Phase 17.1: Rep Setup Infrastructure & Simple Rep Generators

**Goal**: Hiders can be generated for the simpler VMD representations (Lines/VDW/Licorice), with the lock-scene vs randomize infrastructure and research-driven GAME_REPS list established — the foundation all later generators build on.
**Depends on**: Phase 16 (core loop to test generators against)
**Requirements**: HIDER-06, HIDER-04
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. The research-driven 10-rep GAME_REPS list (Lines, VDW, Licorice, CPK, Cartoon, NewCartoon, Trace, Tube, Points, DynamicBond) is defined in the pure layer, with surface/volumetric reps explicitly excluded as anti-features.
2. "Lock current scene" detects the active reps from the loaded molecule (`molinfo $mol get numreps` + per-rep query) and generates hiders matching those reps; "randomize" distributes across the GAME_REPS list.
3. Line/Licorice/VDW hiders generate atoms that mimic connected atoms (bonded pseudoatom analogues) and visually blend with line/licorice/VDW representations.
4. Reps are tracked by stable name (`mol repname`/`mol repindex`), never by index (renumbers on `mol delrep`).

Plans:
- [ ] 17.1-01: TBD

### Phase 17.2: Cartoon/NewCartoon Generators ⚠️ STRIDE L-CAVEAT

**Goal**: Hiders can be generated for the complex cartoon representations — the hardest generator tier, de-risking the STRIDE `ss='L'` caveat for fake `GAM` residues (the v1 Phase 11 analogue).
**Depends on**: Phase 17.1 (rep infrastructure + simple generators proven)
**Requirements**: HIDER-05
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Cartoon/NewCartoon hiders generate and visually blend with cartoon representations.
2. The STRIDE `ss='L'` caveat for fake `GAM` residues is researched and a decision (accept vs Tube/Trace sidestep vs splice+`mol ssrecalc`) is recorded — the L-complexity item from v1 Phase 11.
3. A game round with cartoon-blend hiders is playable end-to-end (generate → click-to-find → win) using the Phase 16 core loop.

Plans:
- [ ] 17.2-01: TBD

### Phase 18: Materials Exploration (v2 Differentiator)

**Goal**: VMD's material system can be used as a blending dimension for hiders, beyond reps — the spec's explicit exploration target.
**Depends on**: Phase 17.2 (reps solid before materials layered on)
**Requirements**: MATERIAL-01, MATERIAL-02
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Hiders can be rendered with VMD materials (Glass/Translucent/custom GameBlend) via `mol modmaterial`, creating a material-based blend visually distinct from rep-based blending.
2. The Setup tab offers a "use material blending" toggle and a curated material set; the pedagogical value (noticing material/lighting artifacts) is documented as a gameplay-validation hypothesis.
3. A game round with material-blend hiders is playable end-to-end (generate → click-to-find → win).

Plans:
- [ ] 18-01: TBD

### Phase 19: In-game Actions

**Goal**: The player has the full set of in-game actions — hint, reveal, found-management, restart, cleanup — all acting on the proven core loop.
**Depends on**: Phase 16 (core loop), Phase 17.2 (generators)
**Requirements**: GAME-05, GAME-06, GAME-07, GAME-08, GAME-10, BTN-06, DIFF-01, DIFF-04
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Hint recolors the N atoms/residues around a hider (via `atomselect "within 5 of index N"` + an added rep) without revealing the hider itself.
2. Reveal-one (with `tk_messageBox` confirm) marks one random hider found and increments the reveal counter; Reveal-all (with confirm) marks all hiders found.
3. The found-hider dropdown lets the player hide/show/change color of found hiders, with a color picker for accessibility.
4. Restart reloads the original molecule + reps from backup and resets the game; Cleanup (`mol delete` + reload original) removes all game-generated atoms/representations (sentinel-only selector).
5. The reveal counter tracks total reveals used across the game.

Plans:
- [ ] 19-01: TBD

### Phase 20: Persistence (Combined-PDB + .bcm JSON)

**Goal**: Game state can be saved to a shareable file and reloaded, preserving hiders, registry, timer, and setup — `save_state` alone is insufficient (drops beta/user/segid).
**Depends on**: Phase 16-19 (a full game is playable before saving is meaningful)
**Requirements**: GAME-09, GAME-04, BTN-05
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Save writes a combined-PDB (real + hider atoms via `atomselect writepdb`) + a hand-rolled `.bcm` JSON sidecar (registry, timer, found-status, setup, reveal counts, original PDB path), zipped into a `.bcmz`.
2. Load/Import reads a `.bcmz`, reloads the combined-PDB via `mol new`, parses the `.bcm`, reconstructs the registry from sentinels, and reconciles by `index` — the game resumes with the saved state.
3. Generate & export produces a shareable `.bcmz` of the initial game state without starting the game.
4. The JSON is hand-rolled (no `json` package in VMD 1.9.3 — emit/parse with tcl 8.5 `dict`) and round-trips correctly (save → load preserves all fields).

Plans:
- [ ] 20-01: TBD

### Phase 21: Large Fetched Demos & Attribution

**Goal**: Large membrane-protein and glycoprotein demos can be fetched, processed, and loaded with full attribution — reusing v1's human-approved citations.
**Depends on**: Phase 17.2 (generators), Phase 20 (persistence to test against)
**Requirements**: DEMO-02, DEMO-03, DEMO-04, DIFF-05
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. The large demos (1GZM, 3GP6 from MemProtMD) fetch on demand, strip water/salt, compress, and cache to `data/demos/cache/`.
2. The glycoprotein demo (SASBDB) fetches on demand with its source and IDs cited in documentation.
3. Difficulty-tiered demo metadata (Easy/Hard/Challenge/Very challenging) is surfaced in the demo sub-menu.
4. Large-molecule performance is handled (strip water, narrow selects, `after 0` chunking for >200ms work, warn the user before Start on molecules >~20k atoms, cap hider count as a function of atom count).

Plans:
- [ ] 21-01: TBD

### Phase 22: Polish, Help & Endgame

**Goal**: The game is polished with in-game help, endgame stats, a post-game debrief, optional tooltips, and leak-free unload.
**Depends on**: Phase 13-21 (full game stack)
**Requirements**: UX-01, UX-02, DIFF-02, DIFF-03, TEST-03
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. In-game help explains what each button does and what each representation/material means.
2. Controls help explains how to click/navigate/zoom/rotate in VMD, including the pick-vs-rotate mouse-mode toggle.
3. The win screen shows time taken, hints used, and reveals used; the post-game debrief highlights all hiders with per-hider "why hard to spot" explanations.
4. The tooltip decision is resolved: either a ~30-line pure-Tk helper is written (zero-dep preferred), or `tooltip.tcl` is vendored under `vmd/3rd_party_lib/` (git-ignored) with user approval + Tcl/Tk license noted.
5. Unload cleanup releases all traces/selections/hotkeys (`trace vdelete`, `$sel delete`, restore mouse mode + hotkeys) — no leaks on script reload or VMD quit.

Plans:
- [ ] 22-01: TBD

### Phase 23: Documentation (Multi-viewer READMEs)

**Goal**: The repo documentation reflects the multi-viewer architecture — a root README covering both viewers, plus per-viewer READMEs with install/use instructions for the VMD tcl script and the PyMOL plugin.
**Depends on**: Phase 13-22 (full v2 game stack shipped; docs reflect what was built)
**Requirements**: DOC-01, DOC-02, DOC-03
**Plans**: TBD

**Success Criteria** (what must be TRUE):
1. Root README.md describes the multi-viewer architecture (PyMOL plugin + VMD tcl script), links to per-viewer sub-dir READMEs, and accurately reflects what each viewer port provides.
2. `vmd/README.md` provides install and use instructions for the VMD 1.9.3 tcl script — how to source it, the Extensions menu entry, headless testing via `vmd -dispdev text`, and the bundled demo set.
3. `pymol/README.md` provides install and use instructions for the v1 PyMOL 2.5.0 plugin — Plugin Manager install, bundled demos, and known limitations — updated if the v2 layout changed anything about the v1 install path.

Plans:
- [ ] 23-01: TBD

## Progress

**Execution Order:** Phases execute in numeric order: 13 → 14 → 15 → 16 → 17.1 → 17.2 → 18 → 19 → 20 → 21 → 22 → 23. Decimal phases (17.1, 17.2) execute between their surrounding integers (17 → 17.1 → 17.2 → 18). Additional decimal phases may be inserted via `/gsd-insert-phase`.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 13. Bootstrap & Sourced Entry | v2.0 | 2/2 | ✓ Complete | 2026-08-29 |
| 14. Setup Tab & Bundled Demos | v2.0 | 4/4 | ✓ Complete | 2026-08-29 |
| 15. Mutation Safety & Hider Registry | v2.0 | 0/5 | Not started | - |
| 16. MVP Core Loop (Sphere) | v2.0 | 0/TBD | Not started | - |
| 17.1. Rep Setup Infrastructure & Simple Rep Generators | v2.0 | 0/TBD | Not started | - |
| 17.2. Cartoon/NewCartoon Generators | v2.0 | 0/TBD | Not started | - |
| 18. Materials Exploration | v2.0 | 0/TBD | Not started | - |
| 19. In-game Actions | v2.0 | 0/TBD | Not started | - |
| 20. Persistence | v2.0 | 0/TBD | Not started | - |
| 21. Large Fetched Demos & Attribution | v2.0 | 0/TBD | Not started | - |
| 22. Polish, Help & Endgame | v2.0 | 0/TBD | Not started | - |
| 23. Documentation (Multi-viewer READMEs) | v2.0 | 0/TBD | Not started | - |

---
*Roadmap updated: 2026-08-29 (Phase 13 complete; revised 2026-08-22: Phase 17 split into 17.1/17.2 by generator complexity tier, Phase 23 docs added) for milestone v2.0 (VMD tcl port). v1 archived to `milestones/v1-ROADMAP.md`.*
