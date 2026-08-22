# Project Research Summary

**Project:** bioCHEMeleon v2.0 — VMD tcl port of the v1 PyMOL hide-and-seek molecular game
**Domain:** Desktop molecular-visualization extension (sourced tcl script for VMD 1.9.3)
**Researched:** 2026-08-22
**Confidence:** HIGH (overall) — 4 parallel researchers cross-verified against headless VMD 1.9.3 probes + bundled-plugin source; one MEDIUM-confidence reconciliation point (picking mechanism) flagged for GUI human-verify.

## Executive Summary

bioCHEMeleon v2.0 is a port of the shipped, audited v1 PyMOL 2.5.0 plugin (Python/PyQt5, 46 requirements, 12 phases, PASSED 2026-08-18) to VMD 1.9.3 as a **sourced tcl script**. The game inserts "hider" atoms into a loaded molecule, styles them to match a representation, and the player hunts them by clicking. VMD's data model differs fundamentally from PyMOL's, and all 4 researchers converged on the same conclusion: **VMD cannot insert atoms in-place** (no `pseudoatom` analog; `mol addfile` rejects count mismatches; `atomselect` only mutates existing atoms). The v2 architectural answer is **PDB-rebuild**: write a combined PDB (real + hider atoms) with strict column alignment, then `mol new` reload as a single molecule. This is the single biggest v1→v2 change and reshapes the generator architecture. Combined with VMD having **no undo, no per-atom delete, and no global atom id** (identity = `(molid, index)`; molids are monotonic and never reused), the backup/restore model becomes "remember the original PDB path, `mol delete` the game-molecule, `mol new` the original." This is simpler than v1's in-memory backup object but coarser-grained.

The recommended approach is a **zero-external-dependency tcl 8.5.6 stack** (VMD ships Tcl/Tk 8.5 + ttk; no `tooltip.tcl`, no `tklib`, no Python). The pure layer (`lib/setup_state.tcl`, `lib/registry.tcl`) is stdlib-only tcl, unit-testable in WSL via `tclsh` + `tcltest` — the direct tcl analog of v1's WSL-python `setup_state.py`/`registry.py` tests. Cmd-coupled code is verified by headless VMD smoke (`vmd -dispdev text -e <script> -eofexit` from a `/mnt/c` cwd), the v2 equivalent of v1's `run-conda-pymol.bat -cq`. GUI/picking paths require human verification (Tk does not load in `-dispdev text`), preserving v1's human-verify-checkpoint discipline. The differentiator for v2 is **VMD's 23-material system** (Glass, Translucent, EdgyGlass, etc.) as a blending dimension beyond v1's rep-only approach — explored after the core loop is proven. The viable rep set is curated to **10 reps** (Lines, VDW, Licorice, CPK, Cartoon, NewCartoon, Trace, Tube, Points, DynamicBonds); surface and volumetric reps are anti-features (don't fit the discrete-atom blend-in mechanic).

Key risks: (1) **PDB-rebuild correctness** — the highest-risk phase (Phase 3); molid changes on every rebuild, viewpoint/reps must be saved+restored, and PDB column misalignment silently drops sentinels (mitigation: set sentinels in-place via `atomselect` after load, never rely on PDB columns alone). (2) **Picking mechanism** — researchers disagreed on the exact callback contract (`mouse mode 4 2` + `trace vmd_pick_event` vs `trace vmd_pick_atom w` vs `vmd_pick_atom_callbacks` list + `mouse mode pick 0` vs `mouse callback on` + poll `label list Atoms`); flagged MEDIUM-confidence and needs one GUI human-verify to lock the contract. (3) **`save_state` is worse than PyMOL's `.pse`** — explicitly does not restore `beta`/`user`/`segid` or "any data produced or modified by scripts" (save_state.tcl:39-46); forces combined-PDB + hand-rolled `.bcm` JSON sidecar (no `json` package in VMD 1.9.3 — hand-roll with tcl 8.5 `dict`). (4) **Cartoon hiders** — the v1 Phase 11 STRIDE/SS-inheritance caveat likely persists (a fake `GAM`/`HID` residue gets `ss='L'`/coil); Tube/Trace are SS-independent alternatives to sidestep it. (5) **WSL/Windows path split** carries over from v1 with a different conversion rule (`/mnt/c/` → `C:/` forward slashes, not `C:\` backslashes).

## Key Findings

### Recommended Stack

See [STACK.md](STACK.md) for full detail. v2 is a **single sourced tcl script** with zero external dependencies — the cleanest possible stack outcome. VMD 1.9.3 ships Tcl/Tk 8.5 + ttk; no `pip`/`npm`/`package install` step. Delivery is `source biochemeleon.tcl` (or `.vmdrc` auto-load, or `vmd -e`, or optional `pkgIndex.tcl` + `vmd_install_extension` for the Extensions menu).

**Core technologies:**
- **VMD 1.9.3** (Nov 30 2016) — host molecular viewer + tcl runtime. Last 32-bit-Windows-friendly release; widely deployed but old. Install verified at `C:\Program Files (x86)\University of Illinois\VMD\`.
- **Tcl 8.5.6** — implementation language. Verified three ways (DLLs, script dirs, `info patchlevel`). Feature set: `dict`, `lassign`, `lreverse`, `apply`, `trace add/remove variable`. **NO Tcl 8.6** (`try`/`throw`/`tailcall`/`coroutine`/`yield`/`lmap` — use `foreach`+`lappend` and `catch`).
- **Tk 8.5 + ttk (Tile)** — GUI framework. `ttk::notebook` for the Setup/Game tabbed UI (analog to v1's PyQt5 `QTabWidget`). Loads in GUI mode only (`-dispdev text` has no Tk — guard all GUI code with `if {[info exists tk_version]}`).
- **VMD mol/atomselect/molinfo commands** — molecule loading, atom manipulation, rep management. All verified headlessly against `1k8p.pdb` (19-check smoke test, all PASS).
- **VMD Tcl variable traces** (`trace add/remove variable`) — picking + lifecycle callbacks. Replaces v1's PyMOL Wizard `do_pick`.
- **(no external libs)** — `tooltip.tcl` is NOT needed (write a ~30-line pure-Tk helper or defer). Vendoring it would drag in the non-BSD Tcl/Tk license. Any future lib needs explicit user approval per AGENTS.md.

**Critical version requirements:**
- Tcl **8.5.6** (no 8.6 features — `lmap`/`try` are parse errors).
- VMD molfile plugins: 75 loaded at startup, all common formats (pdb, psf, dcd, xtc).
- WSL→VMD paths: Windows VMD cannot resolve `/mnt/c/`, `/tmp/`, `~/` — needs `C:/...` forward-slash paths.

### Expected Features

See [FEATURES.md](FEATURES.md) for full detail. This is a port of a shipped game — the feature set is derivative (v1's 46 reqs map to v2), but the implementation surface differs because VMD's data model differs. Spec line 61 asks: "do research and suggest to limit the representation this game could play on" — answered by the **Rep Viability Matrix** (27 reps analyzed; 10 viable, 12 anti-features).

**Must have (table stakes — game breaks without them):**
- Sourced tcl script + `biochemeleon` command → modeless `toplevel` with `ttk::notebook` (Setup/Game tabs). Main dialog must NOT use `grab set` (blocks the 3D viewer for click-to-find).
- Setup tab: molecule dropdown (loaded + demo + PDB fetch), hider count, lock-scene checkbox, per-rep list with optional counts, difficulty toggle, 7 buttons (Reset/Randomize/Save Setup/Load Setup/Generate & export/Cleanup/Start).
- **Hider generation via PDB-rebuild (Option D):** Sphere/VDW + Line/Licorice + Cartoon hiders, with random per-rep distribution baked in (v1.1 quick-008 fix). Hiders live in the SAME molecule as real atoms (invariant: player can't isolate hiders by toggling a molecule).
- Game tab: rolling info box, timer (counts up, stops on win), remaining hiders (total + per-rep), import, hint (recolor neighbors), reveal-one/reveal-all (with confirm), found-hider dropdown, save, restart.
- **Click-to-find** via a VMD pick mechanism (see Reconciliation below) + hider registry keyed by atom `index` (stable within a molid's lifetime).
- Win condition + winning message with time.
- Save/load = combined-PDB + `.bcm` JSON sidecar → `.bcmz` zip (hand-rolled JSON — no `json` package in VMD 1.9.3).
- Bundled demo PDBs (reuse v1's 6 small + 3 large) with `SOURCES.md` citations (human-approved in v1; PDBs are viewer-agnostic).
- In-game explanation + controls help.
- Hider sentinel: `resname=GAM` + `beta=-999` + `segid=GAME` (set in-place via atomselect after load, robust against PDB column bugs); canonical selector `resname GAM and beta < 0`.

**Should have (differentiators — VMD-specific opportunities):**
- **Material-blend hiders** (the spec's explicit exploration target, spec line 61 + PROJECT.md) — `GameBlend` (opacity 0.85) or built-in `Glass1`/`Glass2`/`Glass3`/`Translucent` materials applied via `mol modmaterial`. A 3rd blending axis beyond v1's rep-only approach. Pedagogical value: teaches students to notice material/lighting artifacts.
- **Additional viable reps** beyond v1's 5: NewCartoon (modern default), Trace + Tube (SS-independent — sidestep v1's Phase 11 caveat), CPK (ball-and-stick), Points (easy tier), DynamicBonds (dynamic challenge).
- Post-game debrief (show all hiders + "why hard to spot") — educational angle.
- Reveal counter + win-screen stats.

**Defer (v2.1+ — not essential for v2.0 launch):**
- Trajectory mode (hiders across NMR frames via `vmd_frame` trace) — VMD-specific, v1 had no trajectory concept. Flag for v2.x.
- Per-hider material variation (each hider a slightly different opacity).
- chimeraX port — future milestone (different extension model).
- Puzzle authoring mode (hand-place hiders).

**Anti-features (deliberately NOT build):**
- Surface/volumetric rep hiders (QuickSurf/Surf/MSMS/VolumeSlice/Isosurface/FieldLines/Orbital) — continuous meshes/volumes, not discrete atoms; don't fit blend-in.
- Separate GAME molecule for hiders (Option B) — breaks the core mechanic (player toggles it off to win trivially).
- Graphics primitives as hiders (Option C) — not pickable as atoms (`molinfo get numatoms` = 0).
- psfgen-based atom insertion (Option A) — overkill for fake-atom hiders; needs topology files.
- Web backend / cloud / online leaderboard — out of scope (single-user desktop).
- Hard time limit / fail state — changes cozy-educational tone (timer counts up, not down).
- Custom shaders — out of scope; rely on VMD's built-in OpenGL + `mol modcolor`/`mol showrep`.

### Architecture Approach

See [ARCHITECTURE.md](ARCHITECTURE.md) for full detail. v2 is a **single sourced tcl script** running inside the VMD host — no backend, no threads, no networking. Code lives under `vmd/` (mirrors `pymol/` layout). The architecture is **strictly layered** so game logic never calls `mol`/`atomselect` directly and GUI never mutates molecules except through controller procs — mirroring v1's strict layering so the click→found→refresh loop stays traceable and the pure layer stays unit-testable in WSL via `tclsh` + `tcltest`.

**Major components (v2 project structure):**
1. **`vmd/biochemeleon.tcl` (entry)** — `package provide` + `namespace eval ::BCM::`; register via `vmd_install_extension`; define `biochemeleon_tk_cb` (returns window handle for Extensions menu) and a plain `biochemeleon` console command (headless-testable). Source all `lib/` + `gui/` sub-modules.
2. **`gui/dialog.tcl` + `gui/setup_tab.tcl` + `gui/game_tab.tcl` (GUI layer)** — Tk/ttk widgets only, holds NO game logic, NO `mol` calls. `toplevel .biochemeleon` + `ttk::notebook` (Setup/Game), modeless (no `grab`, no `tkwait`).
3. **`lib/game.tcl` (controller — orchestrator)** — `start`, `on_pick`, `hint`, `reveal_one/all`, `save`, `restart`, `cleanup`. Holds registry + state + adapter refs. The "brain" — wires backup+mutation+registry+pick (composition root, direct port of v1's `game.py`).
4. **`lib/setup_state.tcl` + `lib/registry.tcl` (PURE logic layer)** — stdlib-only tcl, NO `mol`/`atomselect`/`tk`. `dict`-keyed hider registry with dependency-injected sentinel reconstruction (direct port of v1's `setup_state.py` + `registry.py` DI pattern). Unit-testable in WSL via `tcltest`.
5. **`lib/backup.tcl` + `lib/mutation.tcl` + `lib/pick.tcl` (VMD interop layer)** — the ONLY place that calls `mol`/`atomselect`/`mouse`/`material`/`label`. `backup` snapshots viewpoint+reps+atom-fields; `mutation` does the PDB-rebuild + reload + sentinel tagging + cleanup; `pick` registers in `::vmd_pick_atom_callbacks` + saves/restores mouse mode.
6. **`lib/persistence.tcl` (state store)** — hand-rolled JSON `.bcm` sidecar + combined-PDB save/load (no `json` package — emit/parse with tcl 8.5 `dict`).
7. **`lib/demos.tcl` + `lib/generators.tcl`** — demo manifest + `mol new` loader (reuses v1's `data/demos/` PDBs verbatim); per-rep hider placement (sphere/lines/cartoon/...).
8. **`vmd/tests/test_setup_state.test` + `test_registry.test`** — tcltest pure-layer tests, WSL-runnable via `tclsh` (NO VMD, NO Python needed).

**Key patterns to follow:**
- Sourced-script extension structure (namespace + `package provide` + `_tk_cb` + `vmd_install_extension` + optional self-launch on source if `tk_version` exists).
- Modeless Tk `toplevel` + `ttk::notebook` (REQUIRED for click-to-find; `grab set` only on transient sub-dialogs).
- Object-mutation safety: backup scene → rebuild combined PDB → `mol new` → tag sentinels in-place → restore viewpoint+reps on new molid (VMD has NO undo; backup is the only recovery).
- `trace variable` for update loops (`vmd_molecule`/`vmd_initialize_structure`/`vmd_frame` — VMD's signal mechanism, analog of Qt signals).
- Rep tracking by **stable name** (`mol repname`/`mol repindex`), NEVER by index (renumbers on `delrep`) — a VMD advantage over v1 (PyMOL reps were unnamed).
- Pure-layer registry with dependency-injected sentinel reconstruction (testable-core pattern; direct port of v1).

### Critical Pitfalls

See [PITFALLS.md](PITFALLS.md) for full detail. 14 pitfalls identified: 7 critical, 6 moderate, 3 minor. **5 carry over from v1 (3 with a VMD twist), 4 do not apply, 3 are brand-new VMD pitfalls.**

**Top 5 pitfalls with prevention strategies:**

1. **VMD cannot add atoms to a loaded molecule (Pitfall 1, CRITICAL — biggest porting risk)** — There is no `cmd.pseudoatom` analog. `mol new atoms N` creates a *separate* molecule; `atomselect set` only mutates existing atoms. **Prevention:** PDB-rebuild (Option D) — write a combined PDB with hider atoms appended (strict column format), `mol new` reload as one molecule. Verified working (427 atoms in one molecule in FEATURES test6). Hiders in a separate molecule = anti-pattern (player toggles it off to win).

2. **No undo, no per-atom delete — backup = reload original PDB (Pitfall 2, CRITICAL)** — `info commands undo` → empty; `atomselect $sel delete` deletes the *selection object*, not atoms; `mol delete` is whole-molecule only. **Prevention:** At Start, record `[molinfo $molid get filename]` + rep snapshot. Cleanup/Restart = `mol delete $molid; mol new $original_path` + re-apply saved reps. Wrap mutations in `catch` (no `try` in Tcl 8.5). Never assume partial mutation is recoverable in-place.

3. **`save_state` reloads original files — atom mods and game state are LOST (Pitfall 7, CRITICAL — WORSE than v1's `.pse`)** — `save_state.tcl:39-46` explicitly states it does NOT restore `beta`/`user`/`segid` or "any data produced or modified by scripts, even atom positions." Verified: after setting `segid GAME`/`beta -999` and saving, the session mentioned `GAME` once (as a color def) and `-999` zero times. **Prevention:** Combined-PDB (exact game scene with hiders spliced in) + hand-rolled `.bcm` JSON sidecar (registry, timer, found-status, setup, reveal counts, original PDB path). Sentinels must be IN the loaded file (set via PDB text or in-place `atomselect` after `mol new`), not via `atomselect set` on a loaded original.

4. **No global atom id; molid changes on reload — registry must rebuild from sentinels (Pitfall 3, CRITICAL)** — VMD has no `id`/`atomid`/`uid` attribute; identity = `(molid, index)`. Molids are monotonic, never reused. `index` is stable within a molid's lifetime (because atoms can't be added/deleted), but the molid changes on every reload. Dangling `atomselect` on a deleted molecule returns stale data silently. **Prevention:** Primary hider identity = `(molid, index)`, captured at generation. Sentinel reconstruction on load via `atomselect <molid> "segid GAME and beta < 0"` reading each atom's `index` (direct port of v1's `reconstruct_from_sentinels`). Delete every `atomselect` before `mol delete`; never cache across reload. `serial` is NOT a stable id (can collide/duplicate).

5. **Tk modal `grab` on main panel blocks the 3D viewer (Pitfall 4, CRITICAL — MEDIUM-confidence flag)** — `grab set` redirects ALL pointer events to one window; the OpenGL viewer gets nothing. v1's "use Qt, never `.exec_()`" rule becomes VMD's "use a modeless `toplevel`, never `grab set` on the main panel." Every bundled plugin confirms: main windows use `toplevel` + `wm deiconify` with NO grab (`ramaplot.tcl:130`, `viewmaster.tcl:70`, `clonerep.tcl:168`); `grab set` appears only ONCE on a *transient sub-dialog* (`mergestructs.tcl:138`). **Prevention:** Modeless `toplevel .biochemeleon` + singleton re-show pattern (`wm deiconify`). `grab set` ONLY on brief transient children (e.g. "pick a molecule" popup). Modal `tk_messageBox` is fine (brief). **MEDIUM flag:** whether `grab set` fully blocks the OpenGL viewer in VMD 1.9.3 needs one human-in-GUI verification; prevention is the same either way.

**Other notable pitfalls:** Tcl 8.5.6 language limits (no `lmap`/`try`; `foreach`+`lappend`, `catch`), extension re-source resets state (guard with `info exists`), WSL→VMD path conversion (`/mnt/c/` → `C:/` forward slashes), `atomselect` leaks (`$sel delete` everywhere), `mol delrep` renumbers reps (track by `mol repname`), `mol ssrecalc` needed for cartoon hiders (splice full residue, not lone Cα), large-mol perf (narrow selects, `molinfo` for counts, `after 0` chunking for >200ms work).

### Cross-Researcher Reconciliation: Picking Mechanism (MEDIUM confidence)

The 4 researchers converged on the same VMD pick system but cited **different specific mechanisms** — flag this as MEDIUM-confidence, needs GUI human-verify to lock the contract:

| Researcher | Mechanism Cited |
|------------|----------------|
| STACK.md | `mouse mode 4 2` + `trace variable vmd_pick_event write <cb>` (UG node143/159) |
| FEATURES.md | `trace variable vmd_pick_atom w` + `mouse mode 0 0` (test4 verified trace fires on `set vmd_pick_atom`) |
| ARCHITECTURE.md | `lappend ::vmd_pick_atom_callbacks <cb>` + `mouse mode pick 0` (UG node33; probe2 verified list recognized) |
| PITFALLS.md | `mouse callback on` + trace/poll `label list Atoms` (final_out.txt verified; fallback if trace unreliable) |

**Reconciliation:** All 4 reference VMD's pick system but with different specifics. The `vmd_pick_*` globals are **absent in text mode** (verified by all 4 — only populated on real GUI click). The **most defensible contract** (synthesizing all 4): register a proc in `::vmd_pick_atom_callbacks` (ARCHITECTURE), set `mouse mode pick 0` (atom-pick mode, UG node33), and inside the callback read globals `vmd_pick_atom`/`vmd_pick_molecule` as fallback if args are empty (defensive code reads BOTH). **Testable fallback** (PITFALLS, FEATURES): `label add Atoms <molid>/<idx>` + `label list Atoms` returns `{{<molid> <atomindex>} <value> <show>}` — programmatically testable headlessly even when the pick globals don't fire. **Pick vs rotate are mutually exclusive mouse modes in VMD** (unlike v1 where middle-drag rotate coexisted with left-click pick) — provide an in-panel "Rotate/Pick" toggle and document it. **One human-in-GUI test** in Phase 4 will lock the contract; until then, design the PickBridge to support both patterns (trace + callback-list + label-poll fallback).

### Sentinel Resname Discrepancy (Minor — Resolve at Phase 3)

A small reconciliation gap: FEATURES.md verified `resname=GAM` (3 chars — PDB resname is 3 cols; a 4-char `GAME` is silently truncated/dropped, verified by test5) while ARCHITECTURE.md Pattern 5 uses `resname=HID`. Both share `beta=-999` + `segid=GAME`. **Recommendation:** unify on `resname=GAM` (FEATURES ran specific column-alignment tests proving the 3-char limit; `HID` would also work but `GAM` aligns with the 3-char PDB reality and the v1 `GAME` naming intent). Canonical selector: `resname GAM and beta < 0` (most robust; doesn't depend on `segid` column alignment). Set in-place via `atomselect` after load (robust against PDB column bugs). Resolve this at Phase 3 (Mutation Safety) when the sentinel tagging code is written.

## Implications for Roadmap

Based on combined research, the suggested **10-phase structure** (mirrors v1's successful de-risking sequence, adapted to VMD-specific risks). The overriding principle (from v1): **ship the load → generate → click-to-find → win loop as soon as the foundation allows**, because if nothing else works, that loop must work.

### Phase 1: Bootstrap & Sourced Entry
**Rationale:** First thing the script must get right — extension loading, menu registration, modeless ttk GUI, pkgIndex, re-source guard. Without a clean entry, nothing else can be built or tested. Mirrors v1 Phase 1.
**Delivers:** `biochemeleon.tcl` sources cleanly; `vmd_install_extension` registers an Extensions menu item; `biochemeleon` console command opens a modeless `ttk::notebook` dialog with 2 placeholder tabs. Headless smoke: `source` + `biochemeleon` run without error.
**Addresses:** Plugin entry & GUI table-stakes.
**Avoids:** Pitfall 13 (re-source resets state), Pitfall 4 (modal grab — establish modeless from day one), Pitfall 12 (Tcl 8.5 style guide — `foreach`/`catch`/`variable`).

### Phase 2: Setup Tab + Bundled Demos
**Rationale:** Validate VMD `mol new`/`molinfo`, ttk form widgets, and demo loading before touching the risky PDB-rebuild. Reuses v1's bundled PDBs (viewer-agnostic) — lowest-risk content.
**Delivers:** ttk setup form (7 buttons — placeholders), demo manifest, `mol new` loads bundled PDBs (reused from v1), molecule dropdown via `molinfo list` + `trace variable vmd_molecule`.
**Addresses:** Setup tab configuration (spec req 2), demo content.
**Avoids:** Pitfall 10 (WSL→VMD path conversion — `to_vmd_path` helper + first load test), Pitfall 13 (extension loading in text mode — `tk_version` guard).

### Phase 3: Mutation Safety & Hider Registry ⚠️ HIGHEST RISK
**Rationale:** The PDB-rebuild approach is the highest-risk VMD-specific unknown (no in-place insertion). Proving backup → rebuild combined PDB → `mol new` → tag sentinels (atomselect) → cleanup restores original FIRST means the MVP loop (Phase 4) builds on a verified foundation. v1 did the same (Phase 3 de-risked mutation before Phase 4 MVP).
**Delivers:** `lib/backup.tcl` + `lib/mutation.tcl` + `lib/registry.tcl` (pure dict + sentinel reconstruct with DI). Smoke: backup → rebuild → cleanup → restore leaves original intact. Hider sentinel tagging in-place.
**Addresses:** Hider generation (the core mechanic — most research-sensitive), hider registry (atom-index keyed), cleanup model.
**Avoids:** Pitfall 1 (PDB-rebuild — the answer to no in-place insertion), Pitfall 2 (no undo — reload original), Pitfall 3 (molid changes on reload — sentinel reconstruct), Pitfall 7 (sentinels in PDB text, not post-load `atomselect set` on original), Pitfall 8 (cleanup = `mol delete`+reload, not `atomselect delete`). **Resolves sentinel resname discrepancy (GAM vs HID).**

### Phase 4: MVP Core Loop (sphere) ⚠️ PICK MECHANISM HUMAN-VERIFY
**Rationale:** The pick-callback signature is the second unknown (headless can't fire a click — all 4 researchers' `vmd_pick_*` globals stay unset in text mode). Phase 4 validates it via the simplest generator (sphere = "place anywhere in bbox"). Rep-specific generators (Phase 5) and materials (Phase 6) come after the loop is proven.
**Delivers:** Player completes a round with sphere hiders: pick callback registration, registry lookup, recolor, `after`-timer, win. **PROJECT core value.**
**Addresses:** Click-to-find (spec req 7), win condition (spec req 8), game status tab (spec req 6 — minimal), timer.
**Avoids:** Pitfall 5 (pick mechanism — lock the contract here via GUI human-verify; design PickBridge to support trace + callback-list + label-poll fallback), Pitfall 6 (timer = `after`, no threads), Pitfall 5 (pick/rotate UX — in-panel toggle).

### Phase 5: Rep Setup + Generator Strategy
**Rationale:** VMD reps are command-based (`mol addrep`/`modstyle`/`modselect`/`modcolor`/`modmaterial`), unlike v1's GUI-layered `cmd.show`. Per-rep generators need the loop from Phase 4 to test against. Lock-scene vs randomize. Research which reps blend (the spec's core question).
**Delivers:** Per-rep generators (Lines/VDW/Licorice/Cartoon/NewCartoon + sphere from Phase 4). Lock-scene detect via `molinfo $mol get numreps` + per-rep query. Randomize per-rep (quick-008 baked in). The 10-rep GAME_REPS list.
**Addresses:** Setup "Lock current scene" checkbox, per-rep hider list with optional counts, rep viability matrix (the spec's core question).
**Avoids:** Pitfall 9 (cartoon hiders need polymer trace — splice full residue + `mol ssrecalc`; or use Tube/Trace as SS-independent alternatives), `mol delrep` renumbers (track by `mol repname`).

### Phase 6: Materials Exploration (v2 differentiator)
**Rationale:** Materials are a NEW v2 dimension (no v1 equivalent) — explored once reps are solid (Phase 5). VMD's 23-material system (Glass, Translucent, EdgyGlass, etc.) as a blending dimension beyond reps. The spec's explicit exploration target (spec line 61 + PROJECT.md).
**Delivers:** Material-blend hiders via `material add GameBlend` + `material change opacity` + `mol modmaterial`. Setup UI: "use material blending" toggle. Curated material set (Glass1/Glass2/Glass3/Translucent + custom GameBlend).
**Addresses:** Material-based blending differentiator.
**Avoids:** (none specific — this is exploratory; document pedagogical value as MEDIUM-confidence hypothesis requiring gameplay validation).

### Phase 7: In-game Actions
**Rationale:** Hint (recolor neighbors), reveal-one/reveal-all, found-hider visibility/color dropdown, restart, save/load. All require the core loop (Phase 4) + generators (Phase 5) to act on.
**Delivers:** Hint (`atomselect "within 5 of index N"` + add rep with `color ColorID`), reveal-one/reveal-all (with `tk_messageBox` confirm), found-hider dropdown (`mol showrep`/`mol modcolor`), restart (from backup), save/load (minimal — full persistence in Phase 8).
**Addresses:** Game tab full button set (spec req 6), restart (spec req 6 item 9).
**Avoids:** Pitfall 8 (restart = `mol delete`+reload original, not surgical un-find), Pitfall 11 (hint uses narrow selects, not `$all_sel get`).

### Phase 8: Persistence (combined-PDB + .bcm JSON)
**Rationale:** Saving is meaningful only once a full game is playable (Phase 4-7). Hand-rolled JSON (no `json` package in VMD 1.9.3) + combined-PDB round-trip fidelity. Import (Generate & export paired).
**Delivers:** `lib/persistence.tcl` — combined-PDB save (`atomselect writepdb`) + `.bcm` JSON sidecar (registry, timer, found-status, setup, reveal counts, original PDB path). Load: `mol new` combined-PDB + parse `.bcm` + sentinel reconstruct + reconcile. `.bcmz` zip wrapper.
**Addresses:** Save button (spec req 6 item 8), Generate & export + Import (spec 3.5 + req 6 item 4).
**Avoids:** Pitfall 7 (combined-PDB + sidecar, never `save_state` alone), Pitfall 3 (reconstruct registry from sentinels after reload; reconcile `.bcm` by `index` with `(resname resid name)` fallback), `save_state` stores absolute paths (bundle relative).

### Phase 9: Large Fetched Demos + Attribution
**Rationale:** 1GZM/3GP6 (MemProtMD) + SASBDB glycoprotein; strip water/salt, compress; reuse v1's `SOURCES.md`. Large-file fetch/cache and VMD load of stripped PDBs. Needs Phase 5 generators + Phase 8 persistence to test against.
**Delivers:** Fetched large demos with strip pipeline (water/salt removal, compression). Cache to `data/demos/cache/`. Attribution reuse from v1 (human-approved CC0/RCSB/MemProtMD citations).
**Addresses:** Demo PDB set (3 fetched large), demo licensing/attribution.
**Avoids:** Pitfall 11 (large-mol perf — strip water, narrow selects, `after 0` chunking for >200ms work; warn user before Start on mols >~20k atoms), Pitfall 10 (path conversion for cached files).

### Phase 10: Polish + Help + Demos Reps
**Rationale:** UX polish, endgame stats, demo-specific rep presets, optional `tooltip.tcl` (vendor under `vmd/3rd_party_lib/` IF user approves — seek approval per spec). In-game help + controls help.
**Delivers:** In-game help dialog, endgame stats (reveal counter, win-screen), demo-specific rep presets, optional tooltips (write ~30-line pure-Tk helper OR vendor `tooltip.tcl` under `vmd/3rd_party_lib/` pending user approval).
**Addresses:** In-game explanation + controls help (PROJECT.md constraint), post-game debrief (differentiator).
**Avoids:** Unload cleanup (leaked traces/selections/hotkeys — `trace vdelete`, `$sel delete`, restore `$vmd_mouse_mode` + hotkeys).

### Phase Ordering Rationale

- **Phase 3 before 4** — the PDB-rebuild approach is the highest-risk VMD-specific unknown (no in-place insertion). Proving backup→rebuild→cleanup→restore first means the MVP loop builds on a verified foundation. (v1 did the same: Phase 3 de-risked mutation before Phase 4 MVP.)
- **Phase 4 before 5/6** — the pick-callback signature is the second unknown (headless can't fire a click). Phase 4 validates it via the simplest generator (sphere). Rep-specific generators (Phase 5) and materials (Phase 6) come after the loop is proven.
- **Materials (Phase 6) after reps (Phase 5)** — reps are the primary blend mechanism (proven in v1); materials are a NEW v2 dimension explored once reps are solid.
- **Persistence (Phase 8) after the loop + actions** — saving is meaningful only once a full game is playable.
- **Large demos (Phase 9) after persistence** — large-file fetch + strip pipeline benefits from having the full game stack to test against.
- **Groupings by architecture layer:** Phase 1-2 = entry + setup GUI; Phase 3 = interop layer (backup/mutation) + pure registry; Phase 4 = pick interop + controller + game tab minimal; Phase 5-6 = generators + materials (interop + logic); Phase 7 = controller actions + game tab full; Phase 8 = persistence interop; Phase 9 = demo interop; Phase 10 = polish.

### Research Flags

Phases likely needing deeper research during planning (`/gsd-research-phase`):
- **Phase 3 (Mutation Safety — HIGHEST RISK):** The exact "restore viewpoint + reps on a NEW molid" sequence (viewmaster does it; validate the rep-list round-trip on a `mol new`'d molecule). Combined-PDB write fidelity (does `atomselect writepdb` preserve all needed fields? does column alignment hold for hider ATOM records?). Sentinel resname reconciliation (GAM vs HID — resolve here).
- **Phase 4 (MVP Core Loop — PICK MECHANISM HUMAN-VERIFY):** The `vmd_pick_atom_callbacks` arg signature — headless CANNOT verify (globals stay unset without a real click). **MUST validate in a real VMD GUI session** (human-verify checkpoint, like v1's Qt-GUI checkpoints). Design PickBridge defensively (trace + callback-list + label-poll fallback) and lock the contract here.
- **Phase 5 (Rep Setup):** Which VMD reps actually blend for the cartoon-equivalent (Lines/VDW/Cartoon are obvious; Tube/Trace as SS-independent alternatives to sidestep v1's Phase 11 caveat — research which renders a hider residue). The cartoon-hider STRIDE caveat (likely `ss='L'` for fake `GAM` residue) — confirm and decide whether to use Tube/Trace as the v2.0 cartoon-equivalent.
- **Phase 8 (Persistence):** Combined-PDB round-trip fidelity for large molecules (does reload preserve `index` order? does `.bcm` reconciliation handle index drift?). `save_state` absolute-path fragility (bundle demos relative).
- **Phase 10 (Polish — tooltip.tcl):** If tooltips are wanted, vendor `tooltip.tcl` under `vmd/3rd_party_lib/` per the spec's dependency-approval rule (seek user approval first; note Tcl/Tk license; git-ignore the dir). OR write a ~30-line pure-Tk helper (zero-dep preferred).

Phases with standard patterns (skip research-phase):
- **Phase 1 (Bootstrap):** Well-documented VMD extension pattern (`package provide` + `vmd_install_extension` + `_tk_cb` — verified across 5 bundled plugins).
- **Phase 2 (Setup Tab + Demos):** Standard ttk form widgets + `mol new`/`molinfo` (all verified headlessly).
- **Phase 7 (In-game Actions):** Standard atomselect recolor + `mol showrep`/`modcolor` (verified headlessly).
- **Phase 9 (Large Demos):** Reuses v1's strip pipeline + `SOURCES.md` (already human-approved).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | 19-check headless smoke test (all PASS) + UG cross-verification + bundled-plugin source. Tcl 8.5.6 verified three ways. ttk MEDIUM-HIGH (can't verify headless — Tk doesn't load in `-dispdev text`; present in `scripts/tk8.5/ttk/`; flag for first GUI smoke). |
| Features | HIGH (rep/material/pick APIs — headless-verified) / MEDIUM (rep blend-in viability — reasoned from v1 analogues + VMD rep semantics, not gameplay-validated) / LOW (material-blending pedagogical value — verified API works but value is a hypothesis) | 27-rep analysis complete; 10 viable, 12 anti-features. Option D (PDB-rebuild) verified working (427 atoms in one molecule). |
| Architecture | HIGH (extension structure, GUI pattern, atom manipulation, persistence, build order) / MEDIUM (exact pick-callback arg signature — headless can't fire a click; Phase-4 validation point) | Layering direct-port of v1; pure-layer WSL-testable via tcltest. PDB-rebuild pattern verified by probe3. |
| Pitfalls | HIGH (atom-identity / no-undo / no-merge / no-atom-deletion / save_state / WSL-path / Tcl-8.5 / rep-naming / pick-via-labels — all verified) / MEDIUM (Tk modal/grab blocking the 3D viewer + exact `mouse callback` pick-handler contract — text mode can't drive the GUI; needs one human-in-GUI verification) | 14 pitfalls: 5 carry over from v1 (3 with VMD twist), 4 do not apply, 3 brand-new VMD. |

**Overall confidence:** HIGH — the four researchers cross-verified the core stack and APIs against the real VMD install + bundled-plugin source + UG. The single MEDIUM-confidence reconciliation point (picking mechanism) has a testable fallback (`label add Atoms` + `label list Atoms`) and a clear human-verify plan (Phase 4 GUI checkpoint). All other critical paths (PDB-rebuild, sentinel, registry, persistence, extension loading, modeless GUI) are HIGH-confidence.

### Gaps to Address

- **Picking mechanism contract (MEDIUM):** All 4 researchers reference VMD's pick system but with different specifics (`mouse mode 4 2` + `trace vmd_pick_event` vs `trace vmd_pick_atom w` vs `vmd_pick_atom_callbacks` list + `mouse mode pick 0` vs `mouse callback on` + poll `label list Atoms`). **Handle:** Design PickBridge defensively in Phase 4 to support all patterns (trace + callback-list + label-poll fallback); lock the contract via ONE human-in-GUI test. The `label add Atoms <molid>/<idx>` + `label list Atoms` path is the testable fallback (verified headlessly).
- **Sentinel resname (GAM vs HID — minor):** FEATURES verified `resname=GAM` (3-char PDB resname limit); ARCHITECTURE uses `resname=HID`. **Handle:** Unify on `resname=GAM` at Phase 3 (Mutation Safety) when sentinel tagging code is written; canonical selector `resname GAM and beta < 0`.
- **ttk theme availability (MEDIUM-HIGH):** ttk widgets present in `scripts/tk8.5/ttk/` but unverifiable headless (Tk doesn't load in `-dispdev text`). **Handle:** First GUI smoke test in Phase 1/2 confirms `ttk::notebook`/`ttk::frame`/`ttk::button` render correctly.
- **STRIDE caveat for cartoon hiders (MEDIUM):** v1's Phase 11 SS-inheritance caveat (hider fragment renders as loop `ss='L'`) likely persists in VMD (STRIDE auto-runs on Cartoon reps, verified). A fake `GAM` residue won't be recognized as helix/sheet. **Handle:** Phase 5 research decides whether to (a) accept the caveat (mirrors v1 Phase 11 user-accepted 2026-08-16), (b) use Tube/Trace as SS-independent alternatives to sidestep it, or (c) splice a full residue + `mol ssrecalc` and verify.
- **Material gameplay value (LOW — hypothesis):** VMD's 23-material system is a verified-working API, but the pedagogical value (teaches students to notice material/lighting artifacts) is a hypothesis requiring gameplay validation. **Handle:** Phase 6 delivers the feature as a v2 differentiator; document as MEDIUM-confidence pedagogical value; validate with user feedback post-launch.
- **Large-mol rebuild cost (MEDIUM):** PDB-rebuild cost on 1GZM/3GP6 (~50k atoms) estimated ~1-2s — acceptable but needs user warning before Start. **Handle:** Phase 9 caps hider count as a function of atom count (`max_hiders = min(user_value, n_atoms // 50)`) and warns user before Start on mols >~20k atoms. Back up PDB to temp file (not kept-loaded mol) for large molecules.

## Sources

### Primary (HIGH confidence — runtime-verified against the real VMD 1.9.3 install)
- **VMD 1.9.3 install** (`C:\Program Files (x86)\University of Illinois\VMD\`): `tcl85.dll`/`tk85.dll` (Tcl/Tk version), `scripts/{tcl8.5,tk8.5,8.5.6,vmd}/` (bundled libs + core tcl), `vmd.rc` (startup example), `scripts/vmd/{vmdinit,atomselect,save_state,loadplugins,hotkeys}.tcl` (API usage + extension mechanism + mouse globals + save/restore limits).
- **Headless VMD probes + 19-check smoke test** (`tmp/vmd_test/game_api_smoke.tcl`, `tmp/vmd-test/vmd_test{1..6}.tcl`, `tmp/vmdprobe/probe{,2,3}.tcl` — gitignored under `tmp/`): ran `bash -ic "vmd -dispdev text -e <C:/.tcl> -eofexit < /dev/null"` against the real install; confirmed Tcl 8.5.6, command existence, `mol new`/atomselect/repname/repindex/showrep/modstyle/delrep, pick-trace firing (by simulation), dict round-trip, sidecar round-trip, graphics, lifecycle trace, ttk-unavailable-in-text-mode, Option D (427 atoms in one molecule), sentinel round-trip, 23 materials, `material add`/`change`/`modmaterial`, `save_state` drops beta/user, NO undo, NO per-atom add/delete, NO `json`/`tcllib` package. 19/19 PASS.
- **VMD 1.9.3 User's Guide** (https://www.ks.uiuc.edu/Research/vmd/current/ug/, matches local `vmd-ref/ug.pdf` v1.9.3 Nov 27 2016): node31 (mouse), node33 (Pick Modes — `mouse mode pick 0` = atom pick), node117 (Tcl Text Interface), node120 (Tcl Text Commands index), node122 (`atomselect`), node140 (`mol`), node142 (`molinfo`), node143 (`mouse` — pick modes `4 N`), node154 (`user` — hotkeys + per-atom field), node159 (Tcl callbacks — `vmd_pick_event`/`vmd_pick_mol`/`vmd_molecule`/`vmd_initialize_structure`/`vmd_quit` traces), node251 (`.vmdrc`/`vmd.rc` startup loading).
- **Bundled VMD tcl plugins** (`vmd-ref/plugins/`): `clonerep1.3/clonerep.tcl` (rep management + Tk GUI + `trace variable vmd_molecule` + `vmd_install_extension` pattern + `vmdcon` + `mol delrep 0` loop renumbering), `ramaplot1.1/ramaplot.tcl` (mouse pick callbacks, `trace variable vmd_frame`/`vmd_initialize_structure`, molecule dropdown, `catch {$selection delete}` invalidation), `viewmaster2.6/viewmaster.tcl` (THE canonical save/restore rep pattern: `save_reps`/`restore_reps` + `molinfo $mol get numreps` + per-rep query + `mol addrep`/`mol modstyle`/`mol showrep`/etc. + `save_molecules` viewpoint matrices), `autoionize1.4/autoionize.tcl` (psfgen atom-addition pattern — Option A, rejected as overkill; `catch`/`psfcontext` save-restore error pattern), `mergestructs1.1/mergestructs.tcl` (psfgen merge; `wm protocol WM_DELETE_WINDOW`; the ONE `grab set` use on a transient sub-dialog); all `pkgIndex.tcl` files.
- **VMD-install source (authoritative for pitfalls):** `scripts/vmd/save_state.tcl:39-46,144-269` (explicit "doesn't restore beta/user data/atom mods"; reload-by-path), `scripts/vmd/vmdinit.tcl:27-35,279-280,331-380` (`lassign` proc, `vmd_mouse_mode`/`vmd_mouse_submode` globals, `wm withdraw .`, `vmd_tkmenu_cb` integration), `scripts/vmd/loadplugins.tcl:114-134` (`vmd_install_extension` + GUI-only loading via `tk_version` guard), `scripts/vmd/hotkeys.tcl:109-140` (`mouse mode`/`mouse mode pick N` hotkeys, `user add key`), `scripts/vmd/atomselect.tcl:24-121` (`atomselect` get/set, `upproc`/`upvar` patterns — confirms NO `add`/`insert` method).

### Secondary (HIGH confidence — v1 reference for carry-over assessment)
- **v1 shipped codebase** (`pymol/biochemeleon/`): `setup_state.py` (pure layer — `GAME_REPS = ['lines','sticks','spheres','cartoon','ribbon']`, `DEMO_MANIFEST`, `PDB_POOL`), `registry.py` (pure dict-keyed registry + DI `reconstruct_from_sentinels`), `game.py` (orchestrator), `generators.py` (pure-stdlib hider generators — directly portable to tcl), `backup.py`/`mutation.py` (cmd bridges), `__init__.py` (plugin entry).
- **v1 research** (`.planning/research/{STACK,FEATURES,ARCHITECTURE,PITFALLS,SUMMARY}.md`): the v1 PyMOL 2.5.0 stack being ported; 12 v1 pitfalls assessed for VMD carry-over.
- **v1 milestone audit** (`.planning/milestones/v1-MILESTONE-AUDIT.md`): v1 PASSED 2026-08-18 (46/46 reqs, 12/12 phases) — confirms the feature set is validated.
- **v1 demo data** (`pymol/biochemeleon/data/demos/` + `SOURCES.md` + `DATA_SOURCES.md`): 6 bundled small + 3 fetched large PDBs with human-approved CC0/RCSB/MemProtMD citations — reused verbatim in v2 (PDBs are viewer-agnostic).
- **PROJECT.md + spec.md** (HIGH): v2.0 target features + key decisions (Option D, quick-008 baked in, material exploration, headless testing). spec.md line 61: "VMD has many more materials and representations, do research and suggest to limit the representation this game could play on."

### Tertiary (MEDIUM-LOW — flagged for validation)
- **`vmd-ref/tooltip/`** (`tooltip.tcl` v2.0.4, `pkgIndex.tcl`, `license.terms`): confirmed tklib tooltip under Tcl/Tk license (permissive, non-BSD); staged as reference, **recommendation: do not vendor** (write ~30-line pure-Tk helper or defer).
- **VMD materials.dat** (`vmd-ref/scripts/materials.dat`): 11 entries in file but VMD 1.9.3 ships 23 (newer materials like Edgy/AO*/BlownGlass compiled in — verified via `material list`).
- **Unverified / flagged (MEDIUM — needs human GUI check):** (1) Tk modal `grab` blocking the OpenGL viewer in VMD 1.9.3 (assume block until verified; prevention is modeless either way); (2) exact `mouse callback on` pick-handler contract (the 4-researcher reconciliation point — `vmd_pick_*` globals absent in text mode; needs ONE human-in-GUI test); (3) whether middle/right-drag still rotates in pick mode (affects UX — provide in-panel Rotate/Pick toggle); (4) ttk theme rendering in GUI mode (present in `scripts/tk8.5/ttk/` but unverifiable headless).

---
*Research completed: 2026-08-22*
*Ready for roadmap: yes*
