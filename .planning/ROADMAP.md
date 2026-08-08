# Roadmap: bioCHEMeleon

## Overview

bioCHEMeleon is a PyMOL 2.5.0 plugin that turns a loaded molecular object into a hide-and-seek puzzle. The journey builds from a clean plugin shell outward: first the plugin must install and register, then the Setup tab lets the user configure a game and load bundled demos, then the highest-risk area (safe object mutation + hider registry) is de-risked before any generator is built on it. With the foundation proven, the MVP core loop ships using the simplest generator (sphere) — the PROJECT.md core value — then the harder line/stick and cartoon/ribbon generators land, followed by the in-game actions (hint/reveal, found-management/restart/cleanup), persistence and shareable puzzles, the large fetched demos with full source attribution, and finally polish, endgame stats, and in-game help. The phase order is dictated by a dependency DAG and a single overriding principle: ship the load → generate → click-to-find → win loop as soon as the foundation allows, because if nothing else works, that loop must work.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Plugin Bootstrap & Dialog Scaffold** - Install + menu item + empty tabbed dialog
- [x] **Phase 2: Setup Tab Configuration & Bundled Demos** - Full Setup form + config buttons + bundled demo PDBs
- [x] **Phase 3: Mutation Safety & Hider Registry Foundation** - De-risk object mutation + registry (highest-risk area)
- [x] **Phase 4: MVP Core Loop (Sphere)** - THE core value: load → generate spheres → click-to-find → win
- [ ] **Phase 5: Line/Stick & Cartoon Generators** - The harder blend-in generators (cartoon = L-complexity swing)
- [ ] **Phase 6: Hint & Reveal** - Get-help / give-up mechanics with usage tracking
- [ ] **Phase 7: Found-Hider Management, Restart & Cleanup** - Manage found hiders, reset, and clean the model
- [ ] **Phase 8: Persistence & Shareable Puzzles** - Save/load game state + generate&export / import
- [ ] **Phase 9: Large Demo Fetch & Source Attribution** - Membrane/glycoprotein fetch + DATA_SOURCES.md
- [ ] **Phase 10: Polish, Endgame & Help** - Tooltips, controls help, win-screen stats, post-game debrief

## Phase Details

### Phase 1: Plugin Bootstrap & Dialog Scaffold
**Goal**: The plugin installs cleanly into PyMOL and opens a dialog from the Plugins menu — the stable shell every later phase builds on.
**Depends on**: Nothing (first phase)
**Requirements**: PLUGIN-01, PLUGIN-02, PLUGIN-03
**Success Criteria** (what must be TRUE):
  1. The user installs the plugin via PyMOL's Plugin Manager and PyMOL loads it on launch without errors (verified end-to-end via the `setenv.bat` → Windows-conda PyMOL path)
  2. A "bioCHEMeleon" item appears under the Plugins menu; clicking it opens the plugin dialog window
  3. The dialog shows a tabbed interface with "Setup" and "Game status" tabs (placeholder content is acceptable)
**Plans**: 1 plan

Plans:
- [ ] 01-01-PLAN.md — Create the biochemeleon/ package (6 files: entry point + singleton + PluginDialog with 2 placeholder tabs), WSL syntax+Pitfall-1/11 gate, then Windows-PyMOL install + smoke test

### Phase 2: Setup Tab Configuration & Bundled Demos
**Goal**: The user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience.
**Depends on**: Phase 1
**Requirements**: SETUP-01, SETUP-02, SETUP-03, SETUP-04, SETUP-05, SETUP-06, DEMO-01, BTN-01, BTN-02, BTN-03, BTN-04
**Success Criteria** (what must be TRUE):
  1. The user can choose a target via the object selector: a loaded object, a PDB fetch, or a bundled demo (with a category sub-menu)
  2. The user can set the hider count (capped to a sane max), toggle "lock current scene", assign per-rep hider counts (or leave them random), and toggle difficulty
  3. The user can Reset to defaults, Randomize the params, Save Setup to a file, and Load Setup from a file
  4. Bundled small demo PDBs (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3) load and render in the viewer with sources cited
**Plans**: 7 plans (4 original + 3 gap closures)

Plans:
- [x] 02-01-PLAN.md — TDD the pure setup state model (DEFAULTS, hider_count_cap, randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST)
- [x] 02-02-PLAN.md — Bundle 6 demo PDBs from RCSB + write SOURCES.md citations (DEMO-01)
- [x] 02-03-PLAN.md — Populate demos.py (cmd-coupled helpers + to_windows_path) and gui_setup.py (full SetupTab form)
- [x] 02-04-PLAN.md — Windows PyMOL smoke test of the 4 success criteria (human-verify checkpoint)
- [x] 02-05-PLAN.md — Gap closure: enforce hider-count cap, bound per-rep sum, add lock-source + PDB-pool editor
- [x] 02-06-PLAN.md — Gap closure: replace pool QPlainTextEdit with QListWidget + Add/Edit/Remove buttons + tighten _validate_pdb_code to 4-char
- [x] 02-07-PLAN.md — Gap closure: add "Choose random" button to pick a random pool entry into the fetch field

### Phase 3: Mutation Safety & Hider Registry Foundation
**Goal**: The plugin can safely insert hider atoms into an existing object and track them — de-risking the highest-uncertainty area BEFORE any generator is built on it, with a smoke test proving backup → mutate → remove → restore leaves the original structure intact.
**Depends on**: Phase 1 (independent of Phase 2; may parallelize)
**Requirements**: HIDER-01, HIDER-02, HIDER-06
**Success Criteria** (what must be TRUE):
  1. Hider atoms can be inserted INTO an existing object (not a new object) — the PyMOL object list is unchanged after insertion
  2. Every inserted hider carries the `segi='GAME'` + `b=-999` sentinel and is recorded in a HiderRegistry keyed by atom `id`
  3. The registry can be queried for all hiders (id, rep, status) and per-rep counts
  4. After removing all hiders by sentinel (or restoring from a pre-mutation backup), the object's atom count and structure match its pre-game state exactly
**Plans**: 20 plans

Plans:
- [x] 03-01-PLAN.md — TDD registry.py core (HiderRecord + HiderRegistry register/get/all/remove)
- [x] 03-02-PLAN.md — backup.py snapshot + discard (BACKUP_PREFIX)
- [x] 03-03-PLAN.md — mutation.py insert_hider (pseudoatom + sentinel + identify→id)
- [x] 03-04-PLAN.md — TDD registry.py queries (by_rep, counts_by_rep, mark_found)
- [x] 03-05-PLAN.md — backup.py restore (delete+create, never single-call)
- [x] 03-06-PLAN.md — mutation.py fetch_all_hider_ids (sentinel iterate with space=)
- [x] 03-07-PLAN.md — TDD registry.py serialize (to_dict/from_dict round-trip)
- [x] 03-08-PLAN.md — backup.py verify_intact (count + tuple-multiset)
- [x] 03-09-PLAN.md — mutation.py cleanup_hiders (sentinel remove)
- [x] 03-10-PLAN.md — TDD registry.py reconstruct_from_sentinels (DI) + edge cases
- [x] 03-11-PLAN.md — game.py GameController __init__ + start() (snapshot + insert loop + register)
- [x] 03-12-PLAN.md — game.py GameController cleanup() + abort_on_error()
- [x] 03-13-PLAN.md — smoke/phase3_smoke.py setup + criteria 1-4 happy path
- [x] 03-14-PLAN.md — smoke/phase3_smoke.py failure path + Q1/Q2/PSE spikes + summary
- [x] 03-15-PLAN.md — checkpoint:human-verify (run smoke in Windows PyMOL + triage) — CLOSED via headless PyMOL (run-conda-pymol.bat -cq from WSL, 24/24 ALL PASSED)
- [x] 03-16-PLAN.md — AGENTS.md Phase 3 domain rules + grep gates
- [x] 03-17-PLAN.md — STATE.md (Phase 3 complete) + PITFALLS.md (resolve MEDIUM flags)
- [x] 03-18-PLAN.md — final 12-gate regression suite (full-package WSL check)
- [x] 03-19-PLAN.md — 03-VERIFICATION.md (criterion-by-criterion evidence + spike findings)
- [x] 03-20-PLAN.md — 03-SUMMARY.md (phase handoff to Phase 4)

### Phase 4: MVP Core Loop (Sphere)
**Goal**: The player can play a complete hide-and-seek round with sphere hiders — the PROJECT.md core value. If nothing else works, this loop works.
**Depends on**: Phase 2, Phase 3
**Requirements**: LOOP-01, LOOP-02, LOOP-03, HIDER-04, BTN-07, GAME-01, GAME-02, GAME-03
**Success Criteria** (what must be TRUE):
  1. Pressing Start backs up the object, generates sphere hiders per setup, switches to the Game tab, and counts down 3-2-1 before play begins
  2. Clicking a hider atom in the viewer marks it "found" (recolors or hides it); clicking a non-hider does nothing harmful
  3. The Game tab shows a rolling info log, a timer counting up from start, and the remaining-hiders count (total)
  4. When all hiders are found, the timer stops and a winning message shows the time taken
**Plans**: 6 plans

Plans:
- [x] 04-01-PLAN.md — TDD pure sphere generator (generators.py + tests/test_generators.py)
- [x] 04-02-PLAN.md — Populate PickWizard in wizard.py (click-to-find handler)
- [x] 04-03-PLAN.md — TDD GameController.on_pick/win/set_callbacks/_remaining (game.py)
- [x] 04-04-PLAN.md — Populate GameTab UI (log/timer/remaining/countdown/begin_play/on_win)
- [x] 04-05-PLAN.md — Wire Start button → _on_start (BTN-07 core loop fan-in)
- [x] 04-06-PLAN.md — Headless smoke + human-verify checkpoint (4 success criteria)

### Phase 5: Line/Stick & Cartoon Generators
**Goal**: Hiders can blend into line/stick and cartoon/ribbon representations, not just spheres. Cartoon/ribbon is the "L"-complexity swing feature (novel C-alpha geometry) and the phase most likely to need deeper research.
**Depends on**: Phase 4
**Requirements**: HIDER-03, HIDER-05
**Success Criteria** (what must be TRUE):
  1. Line/stick hiders are generated as new atoms that mimic connected atoms or occupy alternate positions, blending with the line/stick representation
  2. Cartoon/ribbon hiders are generated by extending at a terminal or replicating a segment (loop) as an alternate position using C-alpha geometry, and render visibly under the cartoon representation (verified: `cmd.count('cartoon', 'obj and segi GAME') > 0`)
  3. A game started with mixed representations (sphere + line/stick + cartoon) produces hiders in each selected rep, all tracked in the registry
**Plans**: 5 plans

Plans:
- [ ] 05-01-PLAN.md — TDD pure generators (generate_line_stick_offsets + pick_terminal_residues) + unit tests
- [ ] 05-02-PLAN.md — mutation.py cmd-coupled insert_line_stick_hider + insert_cartoon_hider + insert_hider_for_rep dispatcher (coloring option c)
- [ ] 05-03-PLAN.md — Wire mixed-rep: game.py.start dispatch + __init__._on_start builds mixed-rep hider_specs from per_rep
- [ ] 05-04-PLAN.md — Headless smoke (line/stick + cartoon + mixed-rep + 3 MEDIUM open-risk assertions + cleanup)
- [ ] 05-05-PLAN.md — Human-verify checkpoint (visual blend for success criterion 3)

### Phase 6: Hint & Reveal
**Goal**: The player can get spatial help finding a hider or give up on specific/all hiders, with reveal usage tracked across the game.
**Depends on**: Phase 4
**Requirements**: GAME-05, GAME-06, GAME-07, DIFF-01
**Success Criteria** (what must be TRUE):
  1. Pressing Hint colors the N atoms/residues around a hider (neighbors, not the hider itself), giving spatial context
  2. Pressing Reveal-one (after a confirm prompt) marks one random unfound hider as found
  3. Pressing Reveal-all (after a confirm prompt) marks all remaining hiders as found
  4. The number of reveals used is tracked and visible across the game
**Plans**: TBD

Plans:
- [ ] 06-01: TBD during planning

### Phase 7: Found-Hider Management, Restart & Cleanup
**Goal**: The player can manage how found hiders are displayed, restart for a fresh round, and clean the model back to its original state.
**Depends on**: Phase 4 (ideally Phase 5 so Restart regenerates all rep types)
**Requirements**: GAME-08, GAME-10, BTN-06, DIFF-04
**Success Criteria** (what must be TRUE):
  1. The found-hider management dropdown lets the player hide, show, or recolor all found hiders, with a player-chosen highlight color (accessibility / color-blind support)
  2. Pressing Restart restores the object from the stored initial state and regenerates hiders for a fresh round
  3. Pressing Cleanup removes all game-generated atoms/representations (by `segi='GAME'` sentinel only), leaving the original object exactly as it was (atom count matches pre-Start)
**Plans**: TBD

Plans:
- [ ] 07-01: TBD during planning

### Phase 8: Persistence & Shareable Puzzles
**Goal**: The player can checkpoint a game in progress and reload it later, and an educator can prepare a puzzle (Generate & export) and share it for a player to Import.
**Depends on**: Phase 4 (and Phase 5 so Generate & export supports all rep types)
**Requirements**: GAME-09, GAME-04, BTN-05
**Success Criteria** (what must be TRUE):
  1. Pressing Save writes a PyMOL session (`.pse`) plus a companion `.bcm` JSON sidecar (registry, timer, reveal counts, setup); reloading both restores the full game state with the registry rebuilt from sentinels
  2. Pressing Generate & export (from Setup) generates hiders and saves the initial game state to a file without starting play
  3. Pressing Import (from Game tab) loads a previously exported game and lets the player play it
**Plans**: TBD

Plans:
- [ ] 08-01: TBD during planning

### Phase 9: Large Demo Fetch & Source Attribution
**Goal**: The demo set is rounded out with large fetched molecules (membrane proteins, glycoprotein) and every source is fully attributed with verified licenses.
**Depends on**: Phase 2
**Requirements**: DEMO-02, DEMO-03, DEMO-04, DIFF-05
**Success Criteria** (what must be TRUE):
  1. The large membrane-protein demos (1GZM helix, 3GP6 sheets) can be fetched on demand with full membrane (dppc-atomistic), stripped of water and salt, then compressed before caching — with a modeless cancelable progress dialog
  2. The glycoprotein-with-glycan demo can be fetched from SASBDB on demand, with source and IDs cited
  3. A `DATA_SOURCES.md` documents all PDB IDs, DOIs, SASBDB IDs, and MemProtMD attribution, with MemProtMD per-entry licenses verified before bundling
  4. The demo sub-menu surfaces difficulty-tiered metadata (Easy / Hard / Challenge / Very challenging)
**Plans**: TBD

Plans:
- [ ] 09-01: TBD during planning

### Phase 10: Polish, Endgame & Help
**Goal**: The game is polished with in-game explanations, PyMOL controls help, and a rich endgame experience (win-screen stats + post-game debrief) that delivers the teachable moment. The README is finalized to reflect the shipped product.
**Depends on**: Phase 4, Phase 6
**Requirements**: UX-01, UX-02, DIFF-02, DIFF-03
**Success Criteria** (what must be TRUE):
  1. Tooltips / a help panel explain what each button does and what each representation means
  2. A controls-help reference explains how to click, navigate, zoom, and rotate in PyMOL (for users new to PyMOL)
  3. The winning message shows time taken, hints used, and reveals used
  4. After winning, all hiders are highlighted with an explanation of why each was hard to spot (the teachable debrief)
  5. README.md is updated to reflect the final shipped feature set, install instructions, and usage
**Plans**: TBD

Plans:
- [ ] 10-01: TBD during planning

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

Note: With `parallelization: true`, Phase 3 may run in parallel with Phase 2 (both depend only on Phase 1); Phases 6 and 7 may overlap (both depend on Phase 4). Decimal phases (insertions) appear between their surrounding integers.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1/1 | ✓ Complete | 2026-08-03 |
| 2. Setup Tab Configuration & Bundled Demos | 7/7 | ✓ Complete | 2026-08-05 |
| 3. Mutation Safety & Hider Registry Foundation | 20/20 | ✓ Complete | 2026-08-06 |
| 4. MVP Core Loop (Sphere) | 6/6 | ✓ Complete | 2026-08-08 |
| 5. Line/Stick & Cartoon Generators | 0/5 | Not started | - |
| 6. Hint & Reveal | 0/TBD | Not started | - |
| 7. Found-Hider Management, Restart & Cleanup | 0/TBD | Not started | - |
| 8. Persistence & Shareable Puzzles | 0/TBD | Not started | - |
| 9. Large Demo Fetch & Source Attribution | 0/TBD | Not started | - |
| 10. Polish, Endgame & Help | 0/TBD | Not started | - |

## Research Flags

Phases likely needing deeper `/gsd-research-phase` during planning (from research SUMMARY.md):

- **Phase 1**: Qt-vs-Tk runtime validation — confirm `pymol.Qt` import works in the `setenv.bat`-launched PyMOL (closes the last LOW-confidence gap). Light research — mostly a smoke test.
- **Phase 3**: `cmd.create` merge-append vs replace semantics (MEDIUM); `.pse` round-trip `id`/`index` stability (MEDIUM). A small smoke test resolves both.
- **Phase 5 (HIGHEST research flag)**: Cartoon/ribbon hider geometry — "replicate a segment (loop) as alternate position" via C-alpha is genuinely novel; needs a dedicated spike on `cmd.attach_amino_acid` dihedrals, C-alpha chain endpoints, and secondary-structure handling. Most likely phase to slip.
- **Phase 8**: `.pse` + companion `.bcm` co-location UX — two-file share is awkward; decide zip-together vs document "keep both files".
- **Phase 9**: MemProtMD per-entry license verification (site was unreachable at research time) — must verify before bundling membrane coordinates.

Phases with standard patterns (skip deep research): Phase 2, Phase 4, Phase 6, Phase 7, Phase 10.

---
*Roadmap created: 2026-08-03*
*Depth: comprehensive (10 phases)*
*Coverage: 46/46 v1 requirements mapped*
