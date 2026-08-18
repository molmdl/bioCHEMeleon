# Milestone v1: bioCHEMeleon (PyMOL 2.5.0 plugin)

**Status:** ✅ SHIPPED 2026-08-18
**Phases:** 1-11 + 04.1 (12 phases total)
**Total Plans:** 77

## Overview

bioCHEMeleon is a PyMOL 2.5.0 plugin that turns a loaded molecular object into a hide-and-seek puzzle. The journey builds from a clean plugin shell outward: first the plugin must install and register, then the Setup tab lets the user configure a game and load bundled demos, then the highest-risk area (safe object mutation + hider registry) is de-risked before any generator is built on it. With the foundation proven, the MVP core loop ships using the simplest generator (sphere) — the PROJECT.md core value — then the harder line/stick and cartoon/ribbon generators land, followed by the in-game actions (hint/reveal, found-management/restart/cleanup), persistence and shareable puzzles, the large fetched demos with full source attribution, and finally polish, endgame stats, and in-game help. The phase order is dictated by a dependency DAG and a single overriding principle: ship the load → generate → click-to-find → win loop as soon as the foundation allows, because if nothing else works, that loop must work.

**Milestone audit:** ✅ PASSED — 46/46 requirements, 12/12 phases verified, 9/9 cross-phase integration, 6/6 E2E flows. See `v1-MILESTONE-AUDIT.md`.

## Phases

### Phase 1: Plugin Bootstrap & Dialog Scaffold

**Goal**: The plugin installs cleanly into PyMOL and opens a dialog from the Plugins menu — the stable shell every later phase builds on.
**Depends on**: Nothing (first phase)
**Requirements**: PLUGIN-01, PLUGIN-02, PLUGIN-03
**Plans**: 1 plan (1/1 complete, 2026-08-03)

Plans:
- [x] 01-01-PLAN.md — Create the biochemeleon/ package (6 files: entry point + singleton + PluginDialog with 2 placeholder tabs), WSL syntax+Pitfall-1/11 gate, then Windows-PyMOL install + smoke test

### Phase 2: Setup Tab Configuration & Bundled Demos

**Goal**: The user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience.
**Depends on**: Phase 1
**Requirements**: SETUP-01, SETUP-02, SETUP-03, SETUP-04, SETUP-05, SETUP-06, DEMO-01, BTN-01, BTN-02, BTN-03, BTN-04
**Plans**: 7 plans (7/7 complete, 2026-08-05 — 4 original + 3 gap closures)

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
**Plans**: 20 plans (20/20 complete, 2026-08-06)

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
**Plans**: 6 plans (6/6 complete, 2026-08-08)

Plans:
- [x] 04-01-PLAN.md — TDD pure sphere generator (generators.py + tests/test_generators.py)
- [x] 04-02-PLAN.md — Populate PickWizard in wizard.py (click-to-find handler)
- [x] 04-03-PLAN.md — TDD GameController.on_pick/win/set_callbacks/_remaining (game.py)
- [x] 04-04-PLAN.md — Populate GameTab UI (log/timer/remaining/countdown/begin_play/on_win)
- [x] 04-05-PLAN.md — Wire Start button → _on_start (BTN-07 core loop fan-in)
- [x] 04-06-PLAN.md — Headless smoke + human-verify checkpoint (4 success criteria)

### Phase 04.1: Per-rep remaining hiders display (easy mode) (INSERTED)

**Goal**: Close the GAME-03 gap — when the easy difficulty toggle is set, the Game tab shows remaining hiders per representation (not just total). Phase 4 shipped total-only; the per-rep display was explicitly deferred (04-RESEARCH.md:618) and never picked up by any later phase.
**Depends on**: Phase 4 (Game-tab display + GameController callbacks), Phase 3 (registry.counts_by_rep), Phase 2 (difficulty_easy in setup_state)
**Requirements**: GAME-03
**Plans**: 3 plans (3/3 complete, 2026-08-17)

Plans:
- [x] 04.1-01-PLAN.md — TDD registry.remaining_by_rep (hidden-filtered per-rep data source, pure/WSL)
- [x] 04.1-02-PLAN.md — TDD setup_state.format_remaining (pure label formatter, pure/WSL)
- [x] 04.1-03-PLAN.md — Plumb _easy_mode + pull-model _update_remaining + headless smoke + human-verify (GAME-03 close)

### Phase 5: Line/Stick & Cartoon Generators

**Goal**: Hiders can blend into line/stick and cartoon/ribbon representations, not just spheres. Cartoon/ribbon is the "L"-complexity swing feature (novel C-alpha geometry) and the phase most likely to need deeper research.
**Depends on**: Phase 4
**Requirements**: HIDER-03, HIDER-05
**Plans**: 5 original + 2 gap closures + 2 deferred-to-Phase-11 (v1 scope complete, 2026-08-10)

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

**Phase 5 status: COMPLETE (v1 scope)** — Line/stick/sphere + terminal-extension cartoon + ribbon hiders all work. Remaining cosmetic gap (cartoon terminal-extension renders disconnected on 1ubq) deferred to Phase 11.

### Phase 6: Hint & Reveal

**Goal**: The player can get spatial help finding a hider or give up on specific/all hiders, with reveal usage tracked across the game.
**Depends on**: Phase 4
**Requirements**: GAME-05, GAME-06, GAME-07, DIFF-01
**Plans**: 3 plans (3/3 complete, 2026-08-10)

Plans:
- [x] 06-01-PLAN.md — TDD GameController hint/reveal_one/reveal_all/_mark_found + counters + on_counts_changed callback (RED/GREEN/REFACTOR)
- [x] 06-02-PLAN.md — GUI: Hint/Reveal-one/Reveal-all buttons + reveal counter label + confirm dialogs + 4th callback wiring
- [x] 06-03-PLAN.md — Headless smoke (hint+reveal+counter) + human-verify checkpoint (4 success criteria) — APPROVED; 3 Rule-1 bug fixes during verification

### Phase 7: Found-Hider Management, Restart & Cleanup

**Goal**: The player can manage how found hiders are displayed, restart for a fresh round, and clean the model back to its original state.
**Depends on**: Phase 4 (ideally Phase 5 so Restart regenerates all rep types)
**Requirements**: GAME-08, GAME-10, BTN-06, DIFF-04
**Plans**: 3 plans (3/3 complete, 2026-08-12)

Plans:
- [x] 07-01-PLAN.md — TDD pure helpers (build_found_selection + group_found_by_rep in registry.py) + _found_color threading in game.py _mark_found (RED/GREEN/REFACTOR, WSL-tested)
- [x] 07-02-PLAN.md — GUI wiring: found-hider dropdown QComboBox + color picker QColorDialog + Restart button in gui_game.py; Cleanup button in gui_setup.py; _on_restart + _on_cleanup + wizard-lifecycle fix in __init__.py + button wiring
- [x] 07-03-PLAN.md — Headless smoke (Restart/Cleanup/found-mgmt/color via pure cmd) + human-verify checkpoint (all 4 success criteria + Qt paths + wizard lifecycle) — APPROVED

### Phase 8: Persistence & Shareable Puzzles

**Goal**: The player can checkpoint a game in progress and reload it later, and an educator can prepare a puzzle (Generate & export) and share it for a player to Import.
**Depends on**: Phase 4 (and Phase 5 so Generate & export supports all rep types)
**Requirements**: GAME-09, GAME-04, BTN-05
**Plans**: 5 plans (5/5 complete, 2026-08-16)

Plans:
- [x] 08-01-PLAN.md — TDD HiderRegistry.reconcile_with_bcm pure method + ReconcileMismatches namedtuple (registry.py) + unit tests
- [x] 08-02-PLAN.md — TDD build_bcm_dict + parse_bcm_dict pure functions in NEW persistence.py + unit tests in NEW test_persistence.py
- [x] 08-03-PLAN.md — apply_bcm_dict + write_bcmz/read_bcmz/resolve_target file I/O in persistence.py + GameController.import_state + _is_imported/_imported_bcm in game.py
- [x] 08-04-PLAN.md — GUI wiring: export_btn (gui_setup) + begin_row + start_countdown(elapsed) + _begin_play resume fix (gui_game) + _prepare_and_start refactor + _on_export/_on_import/_on_save/_on_restart_imported + modified _on_restart/_on_cleanup (__init__)
- [x] 08-05-PLAN.md — Headless smoke (export/import round-trip, scoped save, reconcile, Restart/Cleanup-on-imported) + human-verify checkpoint (3 success criteria + imported-game lifecycle)

### Phase 9: Large Demo Fetch & Source Attribution

**Goal**: The demo set is rounded out with large fetched molecules (membrane proteins, glycoprotein) and every source is fully attributed with verified licenses.
**Depends on**: Phase 2
**Requirements**: DEMO-02, DEMO-03, DEMO-04, DIFF-05
**Plans**: 4 plans (4/4 complete, 2026-08-16)

Plans:
- [x] 09-01-PLAN.md — TDD pure-layer foundation: extend DEMO_MANIFEST to 9 entries (uniform source schema), TIER_LABELS, 4wb3 'mixed'→'hard', randomize fetched-exclusion, pure strip_resn_from_pdb helper
- [x] 09-02-PLAN.md — demos.py split API (download_large_demo/finalize_large_demo/load_cached_demo/cache helpers) + load_demo source-branching + headless smoke
- [x] 09-03-PLAN.md — Qt layer: modeless cancelable QProgressDialog + demo sub-menu tier display (DIFF-05) + human-verify — 2 runtime fixes applied during checkpoint (MemProtMD .dry extension; SASBDB SSL HARICA fallback)
- [x] 09-04-PLAN.md — DATA_SOURCES.md (DEMO-04) + oxy.ac.uk/DOI corrections + human-verify license/citation accuracy

### Phase 10: Polish, Endgame & Help

**Goal**: The game is polished with in-game explanations, PyMOL controls help, and a rich endgame experience (win-screen stats + post-game debrief) that delivers the teachable moment. The README is finalized to reflect the shipped product.
**Depends on**: Phase 4, Phase 6
**Requirements**: UX-01, UX-02, DIFF-02, DIFF-03
**Plans**: 11 plans (11/11 complete, 2026-08-18)

Plans:
- [x] 10-01-PLAN.md — TDD pure debrief formatter (DEBRIEF_EXPLANATIONS + format_debrief_text in setup_state.py + tests)
- [x] 10-02-PLAN.md — Setup-tab tooltips on ~25 widgets (UX-01)
- [x] 10-03-PLAN.md — Help button + modal Help dialog with 6 sections (UX-01 + UX-02, verified controls)
- [x] 10-04-PLAN.md — Pre-implementation audit: verify 10 research claims vs current code (read-only)
- [x] 10-05-PLAN.md — Endgame win-stats GUI (DIFF-02): _finish_win setInformativeText time/hints/reveals
- [x] 10-06-PLAN.md — Endgame debrief GUI (DIFF-03): _show_all_hiders_for_debrief + _finish_debrief + moved cleanup gate
- [x] 10-07-PLAN.md — Game-tab tooltips on ~8 widgets (UX-01)
- [x] 10-08-PLAN.md — Headless smoke for the debrief fragment-aware cmd.show path
- [x] 10-09-PLAN.md — Human-verify checkpoint: all 5 success criteria in real Windows PyMOL (autonomous: false)
- [x] 10-10-PLAN.md — README finalization (SC5): keep vibe-coding warning, remove UNDER DEVELOPMENT, v1 complete
- [x] 10-11-PLAN.md — Post-implementation audit: verify README + docs vs shipped code (read-only)

### Phase 11: Alt-conf Cartoon/Ribbon Hider (v1 Follow-up)

**Goal**: Replace the terminal-extension cartoon hider with "replicate a segment (loop) as an alternate position using C-alpha geometry" for a connected, blended visual — closing the Phase 5 cosmetic gap (disconnected-look on 1ubq) and adding full ribbon support.
**Depends on**: Phase 5 (terminal-extension cartoon + line/stick/sphere working), Phase 7 (cleanup/restore path)
**Requirements**: HIDER-03, HIDER-05
**Plans**: 8 plans (8/8 complete, 2026-08-16)

Plans:
- [x] 11-01-PLAN.md — TDD pure generators: pick_segments (disjoint mid-chain segments) + generate_middle_displacement (rigid unit vectors)
- [x] 11-02-PLAN.md — TDD pure registry: 3 alt-conf fields (is_altconf/endpoint_resvs/alt_tag) + get_altconf_by_resv + serialization/.bcm round-trip
- [x] 11-03-PLAN.md — TDD persistence .bcm round-trip tests for the 3 alt-conf fields (NO version bump; backward-compat with Phase 8 sidecars)
- [x] 11-04-PLAN.md — mutation.py insert_altconf_cartoon_hider (4-call construction + 4 Bug fixes + displacement) + insert_hider_for_rep dispatcher (arity-based backward-compat routing)
- [x] 11-05-PLAN.md — game.py + wizard.py: on_pick alt/resv gate + get_altconf_by_resv dual lookup + _mark_found is_altconf coloring + start backup_name/is_first_altconf/all_states + do_pick iterate pk1 + import_state alt fallback
- [x] 11-06-PLAN.md — __init__.py _prepare_and_start: build 4-tuple alt-conf payloads (pick_segments + generate_middle_displacement) + drop free_nterminal_valence
- [x] 11-07-PLAN.md — smoke/phase11_smoke.py headless smoke (construction + scoring + cleanup + multi-hider + mixed-rep + .bcm + .pse alt survival)
- [x] 11-08-PLAN.md — smoke/phase11_gui_diag.py + checkpoint:human-verify (all 6 success criteria + 4 GUI-only failure modes in real Windows PyMOL)

**MAJOR mid-execution deviation (documented):** The 8 plans above describe the ORIGINAL alt-conf design (alt='B', shared atom ids, multi-state `all_states` scaffolding). During execution, two debug sessions discovered this approach caused GUI-only visibility regressions. The executor refactored to a **single-state new-chain copy** approach: `insert_altconf_cartoon_hider` → `insert_cartoon_segment_hider` (copy a real 3-residue backbone to a NEW chain 'H' + `alt=''` + `CARTOON_RESI_OFFSET=10000` NEW resi, single-state union-create merge); `game.py` dropped `all_states`/`is_first_altconf`; `on_pick` uses a resv-range gate; `_mark_found` uses `endpoint_resvs`-based fragment coloring. See `.planning/debug/phase11-cartoon-hider-single-state-refactor.md` + `11-08-SUMMARY.md` + `11-VERIFICATION.md`.

## Milestone Summary

**Decimal Phases:**
- Phase 04.1: Per-rep remaining hiders display (INSERTED after Phase 4 — closes GAME-03 per-rep display gap deferred from Phase 4)

**Key Decisions:**
- PyMOL plugin is v1, VMD tcl is v2 — different tech stacks; phased delivery reduces risk. ✓ Good (v1 shipped on PyMOL 2.5.0)
- Hiders added INTO the same PyMOL object (not separate) — otherwise too easy to isolate. ✓ Good (core mechanic, validated)
- Hider placement depends on representation type. ✓ Good (sphere/line-stick/cartoon/ribbon all working)
- Surface representation not supported — doesn't fit blend-in mechanic. ✓ Good (held throughout v1)
- Click-to-find via standard PyMOL atom picking + registry lookup. ✓ Good (PickWizard.do_pick → do_select routing fix in Phase 4)
- Bundle small demo PDBs, fetch large membrane PDBs on demand. ✓ Good (6 bundled + 3 fetched with full attribution)
- No installs / no conda envs in WSL dev env. ✓ Good (held throughout; headless PyMOL via cmd.exe discovered in Phase 3)
- Pure-layer architecture (setup_state.py + registry.py stdlib-only, WSL-unit-testable). ✓ Good (14000 LOC, 125 tests green)
- Headless PyMOL from WSL via `cmd.exe /c run-conda-pymol.bat -cq`. ✓ Good (closed the WSL/Windows runtime gap for cmd-only scripts)
- Parallel-subagent worktree/branch protocol (one worktree per parallel plan). ✓ Good (eliminated shared-index races in Phase 4 Wave 1)
- Phase 11 single-state new-chain copy refactor (abandoned alt-conf design mid-execution). ✓ Good (connected cartoon hiders verified on 1ubq)

**Issues Resolved:**
- WSL/Windows runtime gap closed (Phase 3) — headless PyMOL runnable from WSL via cmd.exe wrapper
- 6 Phase-3 library-bug discoveries encoded as AGENTS.md domain rules (id vs ID, b<0 selector, space= hygiene, etc.)
- Phase 4 do_select routing bug (PickWizard never switched button mode) — fixed
- Phase 6 hint orange persistence + backup corruption — fixed via backup-restore + object-scoped selection
- Phase 8 post-win Cleanup/Restart on imported game empty scene — fixed (commit da8d7a8)
- Phase 11 membrane-protein cartoon duplicate-anchor-id bug — fixed (commit 0702563, quote chain value in selectors)
- Phase 11 alt-conf multi-rep integration failure (4 GUI bug cycles) — resolved by abandoning alt-conf for single-state new-chain copy

**Issues Deferred (v2 / future):**
- VMD tcl plugin (v2 milestone)
- Phase 9 SSL fallback uses check_hostname=False/CERT_NONE for SASBDB HARICA cert gap — revisit for v2
- Phase 9 .pdb.gz cache in repo-relative tmp/ won't exist for installed plugin — out of v1 scope
- Phase 11 hider fragment renders as loop (ss='L') — doesn't inherit parent secondary structure (cosmetic, future enhancement)
- Stale docstrings (game.py placeholder insert, __init__.py Phase 1 tabs) — cosmetic, no functional impact

**Technical Debt Incurred:**
- Some workflow grep gates tripped by literal tokens in docstrings (Rule-3 rewording precedent established)
- `backup.verify_intact` and `game.abort_on_error` are documented primitives NOT wired into main GUI flow (deliberate Phase 6 deviation — cleanup uses backup.restore instead)
- 7 REQUIREMENTS.md checkboxes remained `[ ]` despite Traceability table marking them Complete (doc sync gap — cosmetic)

---
*For current project status, see .planning/ROADMAP.md*
*Archived: 2026-08-18 as part of v1 milestone completion*
