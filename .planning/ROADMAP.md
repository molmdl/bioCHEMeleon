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
- [ ] **Phase 04.1: Per-rep remaining hiders display (easy mode)** (INSERTED) - Close the GAME-03 per-rep display gap deferred from Phase 4
- [x] **Phase 5: Line/Stick & Cartoon Generators** - The harder blend-in generators (cartoon = L-complexity swing)
- [x] **Phase 6: Hint & Reveal** - Get-help / give-up mechanics with usage tracking
- [x] **Phase 7: Found-Hider Management, Restart & Cleanup** - Manage found hiders, reset, and clean the model
- [x] **Phase 8: Persistence & Shareable Puzzles** - Save/load game state + generate&export / import ✓ 2026-08-16
- [x] **Phase 9: Large Demo Fetch & Source Attribution** - Membrane/glycoprotein fetch + DATA_SOURCES.md
- [ ] **Phase 10: Polish, Endgame & Help** - Tooltips, controls help, win-screen stats, post-game debrief
- [x] **Phase 11: Alt-conf Cartoon/Ribbon Hider (v1 Follow-up)** - Re-research + implement the alt-conf segment replication approach (replaces terminal extension for connected cartoon blend)

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

### Phase 04.1: Per-rep remaining hiders display (easy mode) (INSERTED)
**Goal:** Close the GAME-03 gap — when the easy difficulty toggle is set, the Game tab shows remaining hiders per representation (not just total). Phase 4 shipped total-only; the per-rep display was explicitly deferred (04-RESEARCH.md:618) and never picked up by any later phase.
**Depends on**: Phase 4 (Game-tab display + GameController callbacks), Phase 3 (registry.counts_by_rep), Phase 2 (difficulty_easy in setup_state)
**Requirements**: GAME-03
**Success Criteria** (what must be TRUE):
  1. When the easy difficulty toggle is checked at game Start, the Game tab's remaining-hiders label shows a per-rep breakdown (e.g. "Remaining: 7  (spheres: 2, sticks: 3, cartoon: 2)") in addition to the total
  2. When the easy difficulty toggle is unchecked (hard mode), the label shows only the total — unchanged from Phase 4 behavior
  3. The per-rep counts update correctly as hiders are found (via counts_by_rep read after each on_pick / reveal)
**Plans**: 0 plans (not yet planned)

Plans:
- [ ] TBD (run /gsd-plan-phase 04.1 to break down)

**Details:**
Gap analysis identified 3 work items: (1) plumb `difficulty_easy` from setup state → `GameTab.start_countdown` (new param or controller attribute); (2) extend the `_update_remaining` callback to carry `counts_by_rep` (signature change or new callback, backward-compat with Phase 6's `on_counts_changed`); (3) render per-rep breakdown in the label when easy mode is active. Qt+cmd-coupled — follows the Phase 7 human-verify checkpoint pattern (unit-test pure helper for formatting, headless-smoke the counts_by_rep read path, human-verify the label renders).

### Phase 5: Line/Stick & Cartoon Generators
**Goal**: Hiders can blend into line/stick and cartoon/ribbon representations, not just spheres. Cartoon/ribbon is the "L"-complexity swing feature (novel C-alpha geometry) and the phase most likely to need deeper research.
**Depends on**: Phase 4
**Requirements**: HIDER-03, HIDER-05
**Success Criteria** (what must be TRUE):
  1. Line/stick hiders are generated as new atoms that mimic connected atoms or occupy alternate positions, blending with the line/stick representation
  2. Cartoon/ribbon hiders are generated by extending at a terminal or replicating a segment (loop) as an alternate position using C-alpha geometry, and render visibly under the cartoon representation (verified: `cmd.count('cartoon', 'obj and segi GAME') > 0`)
  3. A game started with mixed representations (sphere + line/stick + cartoon) produces hiders in each selected rep, all tracked in the registry
**Plans**: 5 plans (original) + 2 gap closures (05-07 line/stick IndexError, 05-09 ribbon rep support); alt-conf gap closure (05-06/05-08) attempted + reverted, deferred to Phase 11

Plans:
- [x] 05-01-PLAN.md — TDD pure generators (generate_line_stick_offsets + pick_terminal_residues) + unit tests
- [x] 05-02-PLAN.md — mutation.py cmd-coupled insert_line_stick_hider + insert_cartoon_hider + insert_hider_for_rep dispatcher (coloring option c)
- [x] 05-03-PLAN.md — Wire mixed-rep: game.py.start dispatch + __init__._on_start builds mixed-rep hider_specs from per_rep
- [x] 05-04-PLAN.md — Headless smoke (line/stick + cartoon + mixed-rep + 3 MEDIUM open-risk assertions + cleanup)
- [x] 05-05-PLAN.md — Human-verify checkpoint (visual blend for success criterion 3) — PARTIAL APPROVAL (cartoon disconnected on 1ubq, line/stick IndexError, ribbon unsupported)
- [x] 05-07-PLAN.md — Gap closure: line/stick IndexError fix (align _on_start neighbor selection with smoke + defensive ValueError) — cherry-picked
- [x] 05-09-PLAN.md — Gap closure: ribbon rep support (parameterize insert_cartoon_hider rep + forward rep from dispatcher; smoke section 5c) — 41/41 headless smoke ALL PASSED
- [-] 05-06-PLAN.md — Alt-conf research spike (gap closure) — DEFERRED to Phase 11 (spike proved mechanism viable in isolation but multi-rep integration failed; reverted)
- [-] 05-08-PLAN.md — Alt-conf cartoon/ribbon implementation (gap closure) — DEFERRED to Phase 11 (4 failed GUI fix cycles, each passed headless verification but failed in GUI)

**Phase 5 status: COMPLETE (v1 scope)** — Line/stick/sphere + terminal-extension cartoon + ribbon hiders all work (1znf mixed-rep confirmed; ribbon verified via 05-09 headless smoke 41/41 ALL PASSED, independently re-verified by gsd-verifier 5/5 must-haves). Remaining cosmetic gap deferred to Phase 11:
- Cartoon terminal-extension renders disconnected on 1ubq (cosmetic — hiders clickable, game playable) → Phase 11 alt-conf (connected blend via segment replication as alternate position)

### Phase 6: Hint & Reveal
**Goal**: The player can get spatial help finding a hider or give up on specific/all hiders, with reveal usage tracked across the game.
**Depends on**: Phase 4
**Requirements**: GAME-05, GAME-06, GAME-07, DIFF-01
**Success Criteria** (what must be TRUE):
  1. Pressing Hint colors the N atoms/residues around a hider (neighbors, not the hider itself), giving spatial context
  2. Pressing Reveal-one (after a confirm prompt) marks one random unfound hider as found
  3. Pressing Reveal-all (after a confirm prompt) marks all remaining hiders as found
  4. The number of reveals used is tracked and visible across the game
**Plans**: 3 plans (3/3 complete)

Plans:
- [x] 06-01-PLAN.md — TDD GameController hint/reveal_one/reveal_all/_mark_found + counters + on_counts_changed callback (RED/GREEN/REFACTOR)
- [x] 06-02-PLAN.md — GUI: Hint/Reveal-one/Reveal-all buttons + reveal counter label + confirm dialogs + 4th callback wiring
- [x] 06-03-PLAN.md — Headless smoke (hint+reveal+counter) + human-verify checkpoint (4 success criteria) — APPROVED; 3 Rule-1 bug fixes during verification (hint sparse-hider, reveal-counter reset, hint-orange-persist via backup-restore + object-scoped selection)

### Phase 7: Found-Hider Management, Restart & Cleanup
**Goal**: The player can manage how found hiders are displayed, restart for a fresh round, and clean the model back to its original state.
**Depends on**: Phase 4 (ideally Phase 5 so Restart regenerates all rep types)
**Requirements**: GAME-08, GAME-10, BTN-06, DIFF-04
**Success Criteria** (what must be TRUE):
  1. The found-hider management dropdown lets the player hide, show, or recolor all found hiders, with a player-chosen highlight color (accessibility / color-blind support)
  2. Pressing Restart restores the object from the stored initial state and regenerates hiders for a fresh round
  3. Pressing Cleanup removes all game-generated atoms/representations (by `segi='GAME'` sentinel only), leaving the original object exactly as it was (atom count matches pre-Start)
**Plans**: 3 plans

Plans:
- [x] 07-01-PLAN.md — TDD pure helpers (build_found_selection + group_found_by_rep in registry.py) + _found_color threading in game.py _mark_found (RED/GREEN/REFACTOR, WSL-tested)
- [x] 07-02-PLAN.md — GUI wiring: found-hider dropdown QComboBox + color picker QColorDialog + Restart button in gui_game.py; Cleanup button in gui_setup.py; _on_restart + _on_cleanup + wizard-lifecycle fix in __init__.py + button wiring
- [x] 07-03-PLAN.md — Headless smoke (Restart/Cleanup/found-mgmt/color via pure cmd) + human-verify checkpoint (all 4 success criteria + Qt paths + wizard lifecycle) — APPROVED

### Phase 8: Persistence & Shareable Puzzles
**Goal**: The player can checkpoint a game in progress and reload it later, and an educator can prepare a puzzle (Generate & export) and share it for a player to Import.
**Depends on**: Phase 4 (and Phase 5 so Generate & export supports all rep types)
**Requirements**: GAME-09, GAME-04, BTN-05
**Success Criteria** (what must be TRUE):
  1. Pressing Save writes a PyMOL session (`.pse`) plus a companion `.bcm` JSON sidecar (registry, timer, reveal counts, setup); reloading both restores the full game state with the registry rebuilt from sentinels
  2. Pressing Generate & export (from Setup) generates hiders and saves the initial game state to a file without starting play
  3. Pressing Import (from Game tab) loads a previously exported game and lets the player play it
**Plans**: 5 plans

Plans:
- [x] 08-01-PLAN.md — TDD HiderRegistry.reconcile_with_bcm pure method + ReconcileMismatches namedtuple (registry.py) + unit tests (Wave 1) ✓ 2026-08-12
- [x] 08-02-PLAN.md — TDD build_bcm_dict + parse_bcm_dict pure functions in NEW persistence.py + unit tests in NEW test_persistence.py (Wave 2) ✓ 2026-08-12
- [x] 08-03-PLAN.md — apply_bcm_dict + write_bcmz/read_bcmz/resolve_target file I/O in persistence.py + GameController.import_state + _is_imported/_imported_bcm in game.py (Wave 3, depends on 01+02) ✓ 2026-08-12
- [x] 08-04-PLAN.md — GUI wiring: export_btn (gui_setup) + begin_row + start_countdown(elapsed) + _begin_play resume fix (gui_game) + _prepare_and_start refactor + _on_export/_on_import/_on_save/_on_restart_imported + modified _on_restart/_on_cleanup (__init__) (Wave 4, depends on 03) ✓ 2026-08-12
- [x] 08-05-PLAN.md — Headless smoke (export/import round-trip, scoped save, reconcile, Restart/Cleanup-on-imported) + human-verify checkpoint (3 success criteria + imported-game lifecycle) (Wave 5, depends on 04) ✓ 2026-08-16

### Phase 9: Large Demo Fetch & Source Attribution
**Goal**: The demo set is rounded out with large fetched molecules (membrane proteins, glycoprotein) and every source is fully attributed with verified licenses.
**Depends on**: Phase 2
**Requirements**: DEMO-02, DEMO-03, DEMO-04, DIFF-05
**Success Criteria** (what must be TRUE):
  1. The large membrane-protein demos (1GZM helix, 3GP6 sheets) can be fetched on demand with full membrane (dppc-atomistic), stripped of water and salt, then compressed before caching — with a modeless cancelable progress dialog
  2. The glycoprotein-with-glycan demo can be fetched from SASBDB on demand, with source and IDs cited
  3. A `DATA_SOURCES.md` documents all PDB IDs, DOIs, SASBDB IDs, and MemProtMD attribution, with MemProtMD per-entry licenses verified before bundling
  4. The demo sub-menu surfaces difficulty-tiered metadata (Easy / Hard / Challenge / Very challenging)
**Plans**: 4 plans

Plans:
- [x] 09-01-PLAN.md — TDD pure-layer foundation: extend DEMO_MANIFEST to 9 entries (uniform source schema), TIER_LABELS, 4wb3 'mixed'→'hard', randomize fetched-exclusion, pure strip_resn_from_pdb helper (Wave 1)
- [x] 09-02-PLAN.md — demos.py split API (download_large_demo/finalize_large_demo/load_cached_demo/cache helpers) + load_demo source-branching + headless smoke (Wave 2, depends on 01)
- [x] 09-03-PLAN.md — Qt layer: modeless cancelable QProgressDialog + demo sub-menu tier display (DIFF-05) + human-verify (Wave 3, depends on 02) — 2 runtime fixes applied during checkpoint (MemProtMD .dry extension → format='pdb'; SASBDB SSL HARICA → fallback-no-verify); Phase 11 alt-conf bug on membrane proteins discovered + documented (out of scope)
- [x] 09-04-PLAN.md — DATA_SOURCES.md (DEMO-04) + oxy.ac.uk/DOI corrections + human-verify license/citation accuracy (Wave 1, parallel with 01)

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

### Phase 11: Alt-conf Cartoon/Ribbon Hider (v1 Follow-up)
**Goal**: Replace the terminal-extension cartoon hider with "replicate a segment (loop) as an alternate position using C-alpha geometry" for a connected, blended visual — closing the Phase 5 cosmetic gap (disconnected-look on 1ubq) and adding full ribbon support.
**Depends on**: Phase 5 (terminal-extension cartoon + line/stick/sphere working), Phase 7 (cleanup/restore path — alt-conf needs backup.restore between rounds)
**Requirements**: HIDER-03, HIDER-05
**Success Criteria** (what must be TRUE):
  1. Cartoon hiders render as CONNECTED parts of the cartoon trace via alt-conf segment replication (NOT disconnected like the terminal extension) — human-verified on 1ubq
  2. Ribbon hiders render without error (the requested rep is shown, not hardcoded cartoon)
  3. Multiple cartoon hiders per chain work (mid-chain segments, not capped at 1/chain)
  4. A game with mixed representations (sphere + line/stick + cartoon + ribbon) produces hiders in each selected rep, all tracked in the registry, all visible + clickable in the GUI
  5. Cleanup restores the original structure for alt-conf hiders (verify_intact True + count back to orig)
  6. New Game flow (cleanup → re-start) works without residual alt-conf state corruption
**Plans**: 8 plans

Plans:
- [x] 11-01-PLAN.md — TDD pure generators: pick_segments (disjoint mid-chain segments) + generate_middle_displacement (rigid unit vectors) — Wave 1 (parallel with 02)
- [x] 11-02-PLAN.md — TDD pure registry: 3 alt-conf fields (is_altconf/endpoint_resvs/alt_tag) + get_altconf_by_resv + serialization/.bcm round-trip — Wave 1 (parallel with 01)
- [x] 11-03-PLAN.md — TDD persistence .bcm round-trip tests for the 3 alt-conf fields (NO version bump; backward-compat with Phase 8 sidecars) — Wave 2 (parallel with 04)
- [x] 11-04-PLAN.md — mutation.py insert_altconf_cartoon_hider (4-call construction + 4 Bug fixes + displacement) + insert_hider_for_rep dispatcher (arity-based backward-compat routing) — Wave 2 (parallel with 03)
- [x] 11-05-PLAN.md — game.py + wizard.py: on_pick alt/resv gate + get_altconf_by_resv dual lookup + _mark_found is_altconf coloring + start backup_name/is_first_altconf/all_states + do_pick iterate pk1 + import_state alt fallback — Wave 3
- [x] 11-06-PLAN.md — __init__.py _prepare_and_start: build 4-tuple alt-conf payloads (pick_segments + generate_middle_displacement) + drop free_nterminal_valence — Wave 4
- [x] 11-07-PLAN.md — smoke/phase11_smoke.py headless smoke (construction + scoring + cleanup + multi-hider + mixed-rep + .bcm + .pse alt survival) — Wave 5
- [x] 11-08-PLAN.md — smoke/phase11_gui_diag.py + checkpoint:human-verify (all 6 success criteria + 4 GUI-only failure modes in real Windows PyMOL) — Wave 6, autonomous: false

**MAJOR mid-execution deviation (documented):** The 8 plans above describe the ORIGINAL alt-conf design (alt='B', shared atom ids, multi-state `all_states` scaffolding). During execution, two debug sessions discovered this approach caused GUI-only visibility regressions (only cartoon rendered; multi-state `cmd.create` wiped original coords). The executor refactored to a **single-state new-chain copy** approach: `insert_altconf_cartoon_hider` → `insert_cartoon_segment_hider` (copy a real 3-residue backbone to a NEW chain 'H' + `alt=''` + `CARTOON_RESI_OFFSET=10000` NEW resi, single-state union-create merge); `game.py` dropped `all_states`/`is_first_altconf`; `on_pick` uses a resv-range gate (not an alt gate); `_mark_found` uses `endpoint_resvs`-based fragment coloring. The plan `must_haves` are STALE (describe alt-conf); verification was against the 6 outcome-based SUCCESS CRITERIA (design-agnostic). See `.planning/debug/phase11-cartoon-hider-single-state-refactor.md` (status: resolved) + `11-08-SUMMARY.md` + `11-VERIFICATION.md`. Key refactor commits: `d65fb2c`, `8f3e274`, `548050c`, `4c5b14b`, `3b7d7b1`.

**RESEARCH REQUIRED (do NOT skip):** This phase has the HIGHEST research flag. A prior attempt (05-06 spike + 05-08 implementation, 2026-08-09) proved the alt-conf mechanism viable in isolation (10/10 headless) but multi-rep integration revealed 4 cascading GUI-only bug classes. Re-research MUST address:

1. **`cmd.create` append side effects on existing atoms** — the core integration hazard. `cmd.create(obj, tmp)` appending alt-conf atoms corrupts: (a) `cmd.iterate_state(1, "id X")` for non-segment atoms (returns missing), (b) rep flags on existing atoms (clobbers shown reps), (c) coordinates of 1st alt-conf when 2nd merges into state 1 (retroactive coord corruption → "no coordinates" warning). Re-research must find a non-destructive append mechanism or a post-append repair strategy.
2. **GUI-runnable verification** — the methodology failure. Headless PyMOL (`-cq`) defaults `auto_zoom=-1`; GUI defaults `auto_zoom=1`. Any `cmd.create`/`cmd.zoom` verification MUST run in both modes OR in the GUI directly (a Windows PyMOL diagnostic script the user runs, not headless-only smoke). Headless smoke passing does NOT prove GUI correctness for `cmd.create`-heavy code paths.
3. **Multi-state object handling** — 1znf (37-state NMR) + alt-conf interaction. `collapse_to_single_state` must run clean; alt-conf `cmd.create` must not re-introduce multi-state behavior or corrupt state-1 coordinates.
4. **A truly-unique clickable atom id** — alt-conf atoms SHARE ids with originals (PyMOL alt-conf semantics). The registry keys on `(object, id)` — shared ids cause collisions. `cmd.alter "id=..."` is a silent no-op; `cmd.create` preserves source ids; pseudoatoms (which mint unique ids) cannot render in cartoon/ribbon. Re-research must find a way to give each alt-conf hider a unique registry-trackable id without breaking cartoon renderability.

**Lessons from the prior attempt (05-06/05-08, reverted 2026-08-09):**
- Headless smoke is INSUFFICIENT for `cmd.create`-heavy code: `auto_zoom`, multi-state display, and retroactive coord corruption only manifest in the GUI
- `cmd.create(obj, tmp)` append has destructive side effects on existing atoms that only appear in multi-rep simultaneous insertion (not single-rep isolation)
- 4 fix cycles each passed headless verification (44/44, 49/49) but failed in the GUI — the methodology gap, not the implementation, was the blocker
- The spike (05-06) proved the mechanism in isolation; the failure was integration. Re-research should focus on INTEGRATION, not re-proving the mechanism.

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 04.1 → 5 → 6 → 7 → 8 → 9 → 10 → 11

Note: With `parallelization: true`, Phase 3 may run in parallel with Phase 2 (both depend only on Phase 1); Phases 6 and 7 may overlap (both depend on Phase 4). Decimal phases (insertions) appear between their surrounding integers.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1/1 | ✓ Complete | 2026-08-03 |
| 2. Setup Tab Configuration & Bundled Demos | 7/7 | ✓ Complete | 2026-08-05 |
| 3. Mutation Safety & Hider Registry Foundation | 20/20 | ✓ Complete | 2026-08-06 |
| 4. MVP Core Loop (Sphere) | 6/6 | ✓ Complete | 2026-08-08 |
| 04.1. Per-rep remaining hiders display (easy mode) | 0/0 | Not planned (INSERTED) | - |
| 5. Line/Stick & Cartoon Generators | 5/5 + 05-07 + 05-09 | ✓ Complete (v1 scope; alt-conf deferred to Phase 11) | 2026-08-10 |
| 6. Hint & Reveal | 3/3 | ✓ Complete | 2026-08-10 |
| 7. Found-Hider Management, Restart & Cleanup | 3/3 | ✓ Complete | 2026-08-12 |
| 8. Persistence & Shareable Puzzles | 5/5 | ✓ Complete | 2026-08-16 |
| 9. Large Demo Fetch & Source Attribution | 4/4 | ✓ Complete (Phase 11 alt-conf bug on membrane proteins documented for follow-up) | 2026-08-16 |
| 10. Polish, Endgame & Help | 0/TBD | Not started | - |
| 11. Alt-conf Cartoon/Ribbon Hider (v1 Follow-up) | 8/8 | ✓ Complete | 2026-08-16 |

## Research Flags

Phases likely needing deeper `/gsd-research-phase` during planning (from research SUMMARY.md):

- **Phase 1**: Qt-vs-Tk runtime validation — confirm `pymol.Qt` import works in the `setenv.bat`-launched PyMOL (closes the last LOW-confidence gap). Light research — mostly a smoke test.
- **Phase 3**: `cmd.create` merge-append vs replace semantics (MEDIUM); `.pse` round-trip `id`/`index` stability (MEDIUM). A small smoke test resolves both.
- **Phase 5 (HIGHEST research flag — v1 RESOLVED, alt-conf DEFERRED to Phase 11 — RESOLVED by Phase 11 single-state refactor 2026-08-16)**: Cartoon/ribbon hider geometry — "replicate a segment (loop) as alternate position" via C-alpha. The terminal-extension approach shipped (works; ribbon rep support added via 05-09 gap closure — `cmd.show(rep, ...)` parameterized, 41/41 headless smoke). The cosmetic disconnection on 1ubq remained (terminal-extension limitation). The alt-conf approach was spike-verified in isolation but multi-rep integration failed (4 GUI-only bug cycles, reverted). Deferred to Phase 11 — **RESOLVED by Phase 11 (single-state new-chain copy refactor, 2026-08-16)**: the alt-conf design was abandoned mid-execution in favor of `insert_cartoon_segment_hider` (copy a real backbone to a NEW chain 'H', single-state, NEW resi via `CARTOON_RESI_OFFSET`); the HIDER-03/HIDER-05 disconnected-look gap is closed (user-verified on 1ubq). See Phase 11 details + `11-VERIFICATION.md`.
- **Phase 11 (HIGHEST research flag)**: Alt-conf cartoon/ribbon integration — re-research `cmd.create` append side effects (state/rep/coord corruption) + GUI-runnable verification (headless auto_zoom gap was the methodology failure) + unique-id strategy for alt-conf atoms. Prior attempt's spike proved the mechanism; re-research must focus on INTEGRATION, not re-proving the mechanism.
- **Phase 8**: ~~`.pse` + companion `.bcm` co-location UX — two-file share is awkward; decide zip-together vs document "keep both files"~~ RESOLVED (2026-08-12): zip-together (`.bcmz` archive containing `game.pse` + `game.bcm`); Import uses `cmd.load(partial=1)` MERGE with refuse-first collision detection. Three parallel research files on disk at `.planning/phases/08-persistence-and-shareable-puzzles/`.
- **Phase 9**: MemProtMD per-entry license verification (site was unreachable at research time) — must verify before bundling membrane coordinates.

Phases with standard patterns (skip deep research): Phase 2, Phase 4, Phase 6, Phase 7, Phase 10.

---
*Roadmap created: 2026-08-03*
*Depth: comprehensive (11 phases)*
*Coverage: 46/46 v1 requirements mapped (Phase 11 closes the HIDER-03/HIDER-05 alt-conf gap)*
