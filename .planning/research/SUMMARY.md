# Project Research Summary

**Project:** bioCHEMeleon
**Domain:** PyMOL 2.5.0 desktop plugin — interactive molecular "hide-and-seek" game (v1: PyMOL PyQt5 plugin; v2: VMD tcl, deferred)
**Researched:** 2026-08-03
**Confidence:** HIGH (overall) — one spec deviation (Qt vs Tk) resolved in favor of Qt via follow-up verification (see STACK.md "FOLLOW-UP VERIFICATION")

---

## Executive Summary

bioCHEMeleon is a **single-process PyMOL 2.5.0 desktop plugin** that turns a loaded molecular object into a hide-and-seek puzzle: foreign "hider" atoms are inserted INTO the user's existing object (so they can't be isolated by toggling an object off), and the player click-to-finds them by representation type (line/stick, sphere, cartoon/ribbon). It is a novel concept — no competitor exists in the PyMOL/VMD/MolStar/ChimeraX ecosystem (LOW confidence on absence, but no evidence surfaced). Experts build modern PyMOL plugins as a Python package directory with `__init__.py` defining `__init_plugin__(app=None)` + `addmenuitemqt`, using `pymol.Qt` (PyQt5) for the GUI, `pymol.wizard.Wizard` for atom-picking callbacks, and `pymol.cmd` for object mutation. The architecture is layered (GUI → controller → pymol_io) so the game-logic layer is Qt-free and cmd-free, making it unit-testable in WSL python3.6 without PyMOL installed.

**The recommended approach is unambiguous: PyQt5 via `pymol.Qt`** for the GUI (NOT Tkinter — the spec's "Tkinter" hypothesis is overturned by the in-tree `lightingsettings_gui` plugin, the official PyMOL wiki's Tk-deprecation notice ("removal by 4.0"), the absence of a live Tk root under the Qt GUI (`legacysupport.get_tk_root()` returns `None`), and 6/6 actively-maintained reference plugins using `__init_plugin__` + `pymol.Qt`), **numpy + Python stdlib** for everything else, and **zero external dependencies** for v1 (PyQt5 and numpy are both already runtime deps of conda-forge `pymol-open-source`, so the spec's "only libs required by pymol-open-source" rule is satisfied without any approval or vendoring). Tkinter is NOT a stdlib "anti-Pmw" alternative for this project — it is the *same legacy family* as Pmw (both need a live Tk root, which the Qt build does not provide). Ship as a `biochemeleon/` package directory installed via the **GUI Plugin Manager** (universal across Windows/Linux/macOS; works with the WSL-dev / Windows-conda-PyMOL-via-`setenv.bat` workflow via `\\wsl$\…` paths or Windows-side copy). Hiders are inserted via `cmd.pseudoatom(object=existing)` (sphere) or `cmd.fuse`/`cmd.create`-merge (line/stick, cartoon terminus extension), tagged with a `segi='GAME'` + `b=-999` sentinel, and tracked by `id` in a HiderRegistry. Picking uses a `pymol.wizard.Wizard` subclass overriding `do_pick` (the only supported atom-click callback mechanism). Save/load is `.pse` (PyMOL scene) + companion `.bcm` JSON (game metadata), with the registry rebuilt from sentinels on load.

**Key risks cluster around four areas.** (1) **Object mutation safety**: PyMOL Open Source has NO undo (`undocontext` is a no-op stub), so every destructive operation must be preceded by a `cmd.create('_bchm_backup', target)` snapshot and followed by a restore-from-backup on Cleanup/Restart. (2) **Hider blending quality** — the educational differentiator: cartoon/ribbon hiders require real polymer-trace geometry (`cmd.fuse`/`cmd.attach_amino_acid`, not bare `pseudoatom`), and they are the "L"-complexity swing feature most likely to slip. (3) **Cleanup safety**: must remove hiders by `segi='GAME'` sentinel ONLY — never by generic filters like `hetatm`/`water`/`not polymer`, which would delete real ligands and the entire DPPC membrane on the 1GZM/3GP6 demos. (4) **Save/load fidelity**: `.pse` does NOT round-trip plugin Python state (timer, registry, found-status); a sidecar JSON is mandatory, and the registry must be rebuilt from sentinels on load. Licensing is a softer risk — RCSB PDB is CC0 (cite PDB ID + DOI), SASBDB is free with attribution, but MemProtMD was unreachable at research time and must be verified per-entry at the demos phase.

---

## Key Findings

### Recommended Stack

The stack is **deliberately minimal**: PyQt5 via `pymol.Qt` + numpy + Python stdlib. All three are already present in the conda-forge `pymol-open-source` environment (PyQt5 and numpy are run-deps), so v1 needs zero installs, zero approvals, zero vendoring. This is the cleanest possible outcome for the spec's strict dependency-approval constraint — the approval step never triggers. WSL is for syntax-checking only (`python3.6 -m py_compile`); functional testing happens in Windows PyMOL launched via `setenv.bat` into the `chemtools-win10` conda env.

**Core technologies:**
- **PyQt5 via `pymol.Qt`** — plugin GUI (Setup tab + Game-status tab) — the only modern, supported, community-adopted plugin toolkit; auto-selects PyQt5/PySide2/PyQt4/PySide; already a runtime dep of `pymol-open-source`. Never `from PyQt5 import` directly (breaks on PySide2 builds).
- **PyMOL Wizard API (`pymol.wizard.Wizard`)** — atom-picking callback (click-to-find) — GUI-agnostic; `do_pick(self, bondFlag)` fires on atom picks regardless of Tk/Qt GUI; the only clean, supported Python callback for atom clicks.
- **PyMOL `cmd` API** — object mutation, save/load, queries: `cmd.pseudoatom(object=existing)`, `cmd.fuse` (modes 1/2/3), `cmd.create`-merge, `cmd.index('pk1')`, `cmd.iterate(..., space=...)`, `cmd.save`/`cmd.load_pse`, `cmd.alter` (sentinel tagging). All verified present in v2.5.0 source.
- **numpy** — coordinate math for hider placement — already a PyMOL build/run requirement; free to use under the spec's strictest rule.
- **Python stdlib** (json, random, math, os, gzip/zlib, urllib) — game-state sidecar, randomized placement, demo-PDB bundling/compression, on-demand large-PDB fetch. `urllib.request` is stdlib, so MemProtMD/SASBDB fetch needs no approval.
- **`biochemeleon/` package dir** with `__init__.py` defining `__init_plugin__(app=None)` + `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` — installed via GUI Plugin Manager (universal; WSL→Windows-conda via `\\wsl$\…` path or Windows-side copy).

**Critical version notes:**
- PyMOL 2.5.0 (open-source, anaconda) — verified at tag `v2.5.0`, commit `9ea504e`.
- `pymol.Qt` accepts PyQt5 (preferred, conda default), PySide2, PyQt4, PySide — auto-selects in order.
- `cmd.fetch(..., async_=0)` — force synchronous load (interactive default is async — a subtle trap).
- `pymol.plugins.addmenuitemqt` raises `QtNotAvailableError` if no Qt — the loader catches it (acceptable; the game needs the GUI anyway).

### Expected Features

bioCHEMeleon is novel — no direct competitor exists. Table-stakes map 1:1 to the spec's "load → generate → click-to-find → win" core loop. Differentiators lean into the educational angle (players learn to recognize molecular-representation artifacts). Anti-features are explicitly documented to prevent scope creep.

**Must have (table stakes — v1):**
- Standard PyMOL plugin install via Plugin Manager (`__init_plugin__` + `addmenuitemqt`)
- Setup window: object selector (loaded + demo + PDB fetch), hider count input (capped), "lock current scene" checkbox, per-rep hider list with optional per-rep counts, difficulty toggle
- 7 setup buttons: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup model, Start (with 3-2-1 countdown + tab switch)
- Hider generation: **sphere + line/stick** (MVP); **cartoon/ribbon** is v1 per spec but is the highest-risk "L"-complexity item — phase if needed
- Game status tab: rolling info box, timer (counts up, no fail state), remaining count (total + optionally per-rep), Import, Hint (color N neighbors), Reveal-one, Reveal-all (both with confirm), found-hider mgmt dropdown, Save, Restart
- Click-to-find mechanic (Wizard `do_pick` → registry lookup → mark found)
- Win condition (all found → stop timer → winning message with time)
- Save/load game state = `.pse` + `.bcm` JSON sidecar
- Bundled small demo PDBs with sources cited; in-game explanation + controls help

**Should have (differentiators):**
- **Hint colors neighbors (not the hider itself)** — preserves challenge while teaching spatial context (strong genre-aware differentiator)
- **Post-game debrief** — "show all hiders" + explanation of why each was hard to spot — THE teachable moment, where molecular-representation education actually happens
- Reveal counter + win-screen stats (time, hints, reveals)
- Per-rep difficulty reflected in stats (surfaces that some reps are harder to spot)
- Non-destructive to user's scene (Cleanup restores original — framed as a guarantee)
- Shareable puzzle files (Generate & export → Import) — classroom workflow
- Color picker for found-hider highlight (accessibility)
- Bundled small PDBs work offline (classroom/exam)
- Difficulty-tiered demo metadata surfaced in UI

**Defer (v2+):**
- **VMD tcl plugin** — different tech stack; deferred milestone
- Fetched large demo PDBs (MemProtMD 1GZM/3GP6) on demand — trigger: users want harder demos (also needs water/salt strip + compress pipeline + per-entry license verification)
- Post-v1 polish: sound effects (needs audio lib approval), local achievements, optional puzzle-authoring mode

**Anti-features (deliberately NOT build):**
- Surface representation hiders — doesn't fit blend-in mechanic; spec-excluded
- Web backend / cloud / online leaderboard / real-time multiplayer — out of scope (offline educational tool)
- Auto-pip-installing external libs silently — must be approved + user-installed or vendored into `./3rd_party_lib`
- Hard time limit / fail state — timer is for scoring, not failure (cozy-educational tone)
- Touch/mobile support — PyMOL is desktop OpenGL
- Procedural novel-molecule generation — risks scientific inaccuracy (game inserts atoms INTO existing objects, doesn't synthesize)
- Adaptive AI difficulty, custom 3D shaders, in-app self-update, modifying real atoms — all out of scope

### Architecture Approach

Single-process plugin inside the PyMOL host. No backend, no networking, no threads for v1 (QTimer on main thread is sufficient). The architecture is **layered** so game logic never calls Qt directly and GUI never calls `cmd` directly — this keeps the click→found→refresh loop traceable and makes the game-logic layer unit-testable in WSL python3.6 without PyMOL installed.

**Major components:**
1. **`__init_plugin__(app=None)` + `addmenuitemqt`** (entry) — register Plugin-menu item; create singleton dialog lazily with module-level `dialog = None` ref to prevent GC (pattern from `optimize.py`/`outline.py`).
2. **PluginDialog** (gui) — `QDialog` + `QTabWidget` [Setup | Game status]; tab switching driven by GameController state; Setup tab read-only/disabled during active play.
3. **SetupTab / GameTab** (gui) — params form + 7 buttons / timer + remaining + rolling info + hint/reveal/save/restart; emit intents to controller, never mutate PyMOL.
4. **GameController** (logic) — the orchestrator: `start()`, `on_pick(index)`, `hint()`, `reveal_one/all()`, `save()`, `restart()`, `cleanup()`. Pure Python, Qt-free, cmd-free — unit-testable.
5. **HiderGenerator** (logic) — one strategy class per rep (`SphereStrategy`, `LineStickStrategy`, `CartoonStrategy`); computes a placement spec, delegates atom insertion to ObjectMutator.
6. **HiderRegistry** (logic) — source of truth: `id → {rep, status, found_at, hint_used}` + per-rep counters. Built once post-insertion; never `cmd.sort()` or atom-delete while live.
7. **StateStore** (logic) — `.pse` (via `cmd.save`) + `.bcm` JSON sidecar (registry, timer, setup, reveal counts). Rebuild registry from sentinels on load.
8. **PickWizard** (pymol_io) — `Wizard` subclass overriding `do_pick`; saves/restores user's pre-existing wizard; forwards picked `index` to `GameController.on_pick`.
9. **ObjectMutator** (pymol_io) — the ONLY component that adds/removes atoms: `backup_original()`, `add_hider_atoms(spec)` (pseudoatom/fuse/create-merge), `remove_hiders()` (by sentinel), `restore_original()`.
10. **PymolAdapter** (pymol_io) — thin read-only `cmd.*` wrappers (get_names, get_reps, iterate, color, show/hide, select).
11. **DemoLoader** (pymol_io) — manifest JSON + bundled small PDBs + on-demand fetch for large membrane PDBs + source attribution.

**Key patterns:** Plugin entry + lazy singleton dialog; Wizard for atom-picking; singleton dialog with explicit tab state; companion-file save (`.pse` + `.bcm`); hider registry keyed by `id` + sentinel; object-mutation safety (backup → mutate → cleanup/restore).

### Critical Pitfalls

1. **Tkinter GUI (Pitfall 1)** — Use PyQt5 via `pymol.Qt` ONLY. Tkinter is deprecated (PyMOL wiki: "removal by 4.0"), has no live Tk root under the Qt GUI, modal `grab_set()` blocks the viewer, and z-order issues. Verify: no `import Tkinter`/`Pmw`/`app.root` in the codebase; plugin imports only `pymol.Qt`. Recovery cost if missed: HIGH (UI rewrite).
2. **Hiders in a separate object (Pitfall 2)** — Use `cmd.pseudoatom(object=existing)` / `cmd.fuse` / `cmd.create`-merge INTO the existing object. Verify: `cmd.get_names("objects")` unchanged after Generate; player cannot trivially hide hiders by toggling one object.
3. **Unstable hider identity (Pitfall 4)** — Key registry by `id` (survives reordering), NOT by `(resi, chain)` (collides with real data) or per-object `index` (shifts on deletion). Add `segi='GAME'` + `b=-999` sentinel via `cmd.alter` as a safety net for session-reload reconstruction. Never delete hiders one-by-one during the game — mark found by recolor, bulk-remove at Cleanup.
4. **No "atom clicked" callback (Pitfall 5)** — Use the `pymol.wizard.Wizard` `do_pick(self, bondFlag)` pattern (the only supported mechanism). Save/restore user's pre-existing wizard. Disambiguate click vs drag (mouse displacement + time threshold). Force a known mouse pick mode on Start; restore on exit.
5. **Thread safety (Pitfall 6)** — All `cmd.*` calls on the GUI main thread. Use `QTimer` (1 Hz) for the timer — never `threading.Thread` with `cmd.*` calls (deadlock/segfault risk). For long-running work, worker computes geometry in pure Python/numpy and posts to a `queue.Queue`; main thread drains via `QTimer.singleShot(0, drain)` and does the `cmd.*` calls.
6. **`.pse` doesn't save plugin state (Pitfall 7)** — Treat `.pse` as "geometry save" + sidecar `.bcm` JSON as "game state save" (registry, timer, found-status, setup, reveal counts). On Load: open `.pse`, then iterate to reconstruct the hider registry from the `segi='GAME'`/`b=-999` sentinel — the sentinel is the source of truth, the JSON is matched to it by `id`.
7. **Cartoon hiders invisible (Pitfall 8)** — `cartoon`/`ribbon` require polymer-trace geometry; a bare pseudoatom does NOT render. Use `cmd.fuse`/`cmd.attach_amino_acid` with proper N-C-Cα dihedrals for cartoon terminus extension, or build a short peptide fragment + `cmd.fuse` for loop replica. Verify: `cmd.count('cartoon', 'obj and segi GAME') == cartoon_hider_count`.
8. **Cleanup over-matches (Pitfall 9)** — Remove hiders by `segi='GAME'` sentinel ONLY: `cmd.remove(target_obj + " and segi GAME")`. NEVER `hetatm`/`water`/`solvent`/`not polymer`/`resn PSD`/`HOH`/`DPPC` — these would delete real ligands and the entire DPPC membrane on 1GZM/3GP6. Snapshot original atom count at Start; assert match after Cleanup. Test explicitly against the membrane demos.
9. **No undo (Pitfall 10)** — PyMOL Open Source `undocontext` is a no-op stub. Always `cmd.create('_bchm_backup', target)` before mutation; Restart/Cleanup restores from backup. Wrap every generator mutation in try/except that restores from backup on failure. Document for the user that Ctrl-Z does not undo plugin actions.
10. **WSL/Windows path mismatch (Pitfall 11)** — `cmd.load('/mnt/c/...')` fails in Windows PyMOL. Add a `to_windows_path()` helper; resolve bundled demo paths relative to `__file__`. Test end-to-end via `setenv.bat` early in the setup phase.
11. **100k+ atom membrane OOM (Pitfall 12)** — Never `cmd.get_model` on large objects (copies entire structure into Python — GB-scale RAM). Use `cmd.iterate(..., space=...)` (streams) for atom enumeration; C-side `cmd.select('obj within 8 of [x,y,z]')` for neighbor search; numpy for placement math. Strip water/salt + compress large demos before bundling. Show a modeless cancelable `QProgressDialog` during fetch/load/strip/generate. Budget: Generate on 3GP6 < 30 s; click latency < 200 ms.
12. **Demo licensing/attribution (Pitfall 13)** — RCSB PDB = CC0 (cite PDB ID + DOI `https://doi.org/10.2210/pdbXXXX/pdb` + publication + PyMOL). SASBDB = free with attribution (cite entry ID + authors). **MemProtMD was unreachable at research time — verify per-entry license at the demos phase** (the DPPC membrane coordinates may carry their own terms beyond PDB's CC0). Generate a `DATA_SOURCES.md` listing every PDB ID + DOI + MemProtMD/SASBDB entry + license.

---

## Implications for Roadmap

The phase structure below is derived from the dependency DAG in ARCHITECTURE.md. The ordering is dictated by three forces: (a) **de-risk the highest-uncertainty area (object mutation) early** so generators aren't built on wrong assumptions; (b) **land the MVP core value loop (Phase 3) as fast as possible** per PROJECT.md's "if nothing else works, this loop must work"; (c) **defer persistence and polish** until the loop is proven. Cartoon/ribbon is the most likely phase to slip ("L" complexity, novel geometry).

### Phase 0-1: Bootstrap + Qt-vs-Tk Validation + Setup Scaffolding
**Rationale:** The plugin must register cleanly before anything else. The Qt-vs-Tk decision is the single most consequential architectural call and must be settled here — research has already resolved it in favor of Qt, but a runtime smoke test (confirm `pymol.Qt` import works in the `setenv.bat`-launched PyMOL) closes the last LOW-confidence gap. Once the entry point + empty PluginDialog + PymolAdapter read-only wrappers + DemoLoader (manifest + bundled small PDB load) + SetupTab form are in place, every later phase has a stable foundation.
**Delivers:** `biochemeleon/__init__.py` with `__init_plugin__` + `addmenuitemqt`; empty `PluginDialog` (QDialog + QTabWidget); `PymolAdapter` (get_names, get_reps, iterate); `DemoLoader` (manifest + bundled small PDBs); `SetupTab` form (params + 7 buttons, only Reset/Randomize/Save/Load Setup wired); `data/` layout; `to_windows_path()` helper; first end-to-end load test via `setenv.bat`.
**Addresses (features):** Standard plugin install, Setup window with configurable params, object selector (loaded + demo), demo PDB set (bundled small).
**Avoids (pitfalls):** Pitfall 1 (Tkinter — use PyQt5), Pitfall 11 (WSL/Windows path — `to_windows_path` + early load test).

### Phase 2: Mutation Safety + Registry Foundation (DE-RISK EARLY)
**Rationale:** Object mutation is the highest-risk, lowest-confidence area (the `cmd.create`-merge append-vs-replace semantics are MEDIUM confidence; `.pse` round-trip `id`/`index` stability is MEDIUM). De-risk it with a 5-line smoke test before building generators on top of assumptions that might be wrong. The HiderRegistry is the foundation every later phase reads from.
**Delivers:** `ObjectMutator` (backup_original / restore_original / add_hider_atoms via pseudoatom / remove_hiders by sentinel); `HiderRegistry` (id → status + per-rep counters); tiny test harness. Smoke test: insert 1 pseudoatom into 1znf, read its `id`, delete by `segi GAME`, restore from backup, confirm atom count matches pre-Start.
**Uses (stack):** `cmd.pseudoatom`, `cmd.create`-merge, `cmd.alter` (sentinel), `cmd.iterate` (id), `cmd.remove` (sentinel), `cmd.create` (backup).
**Avoids (pitfalls):** Pitfall 2 (wrong object), Pitfall 3 (pseudoatom defaults), Pitfall 4 (unstable identity), Pitfall 9 (cleanup over-match), Pitfall 10 (no undo — backup/restore).

### Phase 3: MVP Core Loop (THE PROJECT.md CORE VALUE)
**Rationale:** This is the heartbeat — "load → generate → click-to-find → win". Per PROJECT.md, if nothing else works, this loop must work. Build PickWizard + GameController + GameTab as a unit (none makes sense alone) and ship the simplest generator (SphereStrategy — "place anywhere", single `pseudoatom`, no bonds) to prove the loop end-to-end. This is the phase that validates the whole project.
**Delivers:** `PickWizard` (Wizard subclass, do_pick → on_pick, save/restore user's wizard); `GameController` (start / on_pick / win); `GameTab` (timer via QTimer, remaining, rolling info); `SphereStrategy`; Start button end-to-end (setup → backup → generate spheres → registry → 3-2-1 countdown → pick → find → win → stop timer → winning message).
**Uses (stack):** `pymol.wizard.Wizard`, `cmd.set_wizard`/`get_wizard`, `cmd.index('pk1')`, `QTimer`, numpy (sphere placement).
**Addresses (features):** Click-to-find mechanic, timer + win condition, Start + countdown + tab switch, sphere hider generation, rolling info box, remaining count, Restart.
**Avoids (pitfalls):** Pitfall 5 (no click callback — Wizard), Pitfall 6 (thread safety — QTimer on main thread). Pitfall 8 (cartoon) is N/A for sphere.

### Phase 4: Remaining Generators (Line/Stick + Cartoon)
**Rationale:** With the loop proven on spheres, add the harder generators. Line/stick needs bond topology mimicry (via `cmd.create`-merge of a pre-built fragment or `cmd.fuse`). Cartoon is the "L"-complexity swing feature — it requires real polymer-trace geometry (`cmd.fuse`/`attach_amino_acid` with proper dihedrals, NOT bare `pseudoatom`); this is the most likely phase to slip and may need its own sub-phase or a phasing deferral to v1.x. Also add per-rep hider counts + "lock scene" rep detection here (they depend on having multiple generator types).
**Delivers:** `LineStickStrategy` (mimic connected atoms / alternate positions); `CartoonStrategy` (extend terminal / replicate segment as alternate position — HARDEST); per-rep hider counts; "lock scene" rep detection.
**Uses (stack):** `cmd.fuse` (modes 1/2/3), `cmd.create`-merge, `cmd.attach_amino_acid`, `cmd.get_model` (small molecules only), `cmd.alter_state` (coords).
**Addresses (features):** Line/stick hiders, cartoon/ribbon hiders, per-rep hider list with optional per-rep counts, lock-scene checkbox.
**Avoids (pitfalls):** Pitfall 8 (cartoon invisible — use fuse/attach_amino_acid, verify `cmd.count('cartoon', ...) > 0`), Pitfall 12 (large-molecule perf — use iterate + C-side neighbor search, not get_model).

### Phase 5: Persistence + Meta Actions
**Rationale:** Save/load is table-stakes but NOT on the critical path of the core loop (Phase 3). Once the loop is proven, add the checkpointing + give-up + restart + cleanup layer. Generate & export / Import are a paired file format — define once, both ends use it. Hint colors N neighbors (not the hider itself) — the genre-aware differentiator. All of these read the same HiderRegistry + found-status, so centralize that state.
**Delivers:** `StateStore` (.pse + .bcm JSON save/load); Generate & export + Import buttons (paired `.bcm` format); Hint button (color N neighbors via `cmd.expand`/`around`); Reveal-one / Reveal-all (with confirm + reveal-count tracking); Restart (restore from backup, regenerate); Cleanup model (sentinel-based remove + backup restore).
**Uses (stack):** `cmd.save`/`cmd.load_pse`, stdlib `json`, `cmd.remove` (sentinel), `cmd.create` (backup restore), `cmd.color`/`cmd.select` (hint), `cmd.expand`/`around`.
**Addresses (features):** Save/load game state, Generate & export / Import, Hint, Reveal-one/all, Restart, Cleanup model.
**Avoids (pitfalls):** Pitfall 7 (.pse round-trip — sidecar JSON + sentinel reconstruction), Pitfall 9 (cleanup — sentinel only), Pitfall 10 (no undo — Restart from backup).

### Phase 6: Polish + Demos + Attribution
**Rationale:** With the engine complete, polish the UX and round out the demo set. The large membrane demos (1GZM/3GP6) need water/salt stripping + compression + a fetch/cache pipeline + a modeless cancelable progress dialog. This is also where licensing is finalized — MemProtMD was unreachable at research time and MUST be verified per-entry before bundling. The difficulty toggle (total-only vs per-rep remaining) and found-hider visibility/color dropdown land here.
**Delivers:** Found-hider visibility/color dropdown; difficulty toggle; rolling info box polish; winning message with time + hints + reveals; large-demo fetch + strip/compress pipeline (1GZM, 3GP6); `DATA_SOURCES.md` with all citations; difficulty-tiered demo metadata in UI.
**Uses (stack):** `cmd.fetch(..., async_=0)`, `urllib.request` (stdlib), `gzip`/`zlib`, `QProgressDialog` (modeless, cancelable), `cmd.iterate` (streaming, not get_model).
**Addresses (features):** Difficulty toggle, found-hider mgmt dropdown, large fetched demos, source citations, demo-tier metadata in UI.
**Avoids (pitfalls):** Pitfall 12 (OOM — iterate + C-side neighbor search + strip water/salt), Pitfall 13 (licensing — verify MemProtMD per-entry, generate DATA_SOURCES.md).

### Phase Ordering Rationale

- **Phase 0-1 before Phase 2:** The plugin must register cleanly and the Qt-vs-Tk decision must be locked before any game code is written — retrofitting Qt later is a rewrite (Pitfall 1 recovery cost = HIGH).
- **Phase 2 before Phase 3:** Object mutation is the highest-risk area; de-risk it with a smoke test before building generators on assumptions that might be wrong. The HiderRegistry is the foundation every later phase reads from.
- **Phase 3 is the MVP value:** Per PROJECT.md, "if nothing else works, this loop must work" — ship it as soon as the foundation (Phase 0-2) is in place. Sphere is the fastest path to a working loop (single pseudoatom, no bonds).
- **Phase 4 after Phase 3:** Line/stick and cartoon are strictly harder than sphere; build them once the loop is proven so you're not debugging geometry and game-loop bugs simultaneously.
- **Phase 5 after Phase 3:** Save/load is table-stakes but not on the critical path; the loop is. All Phase-5 features read the same registry, so centralize that state in Phase 2-3.
- **Phase 6 last:** Polish, large demos, and licensing verification are independent of the engine and can be prepared in parallel — but they ship last.
- **Cartoon may slip:** Its "L" complexity and novel geometry (terminal extension / loop replica) make it the most likely candidate for a Phase-4 slip into its own sub-phase or a v1.x deferral. The roadmap should flag cartoon as "needs deeper research".

### Research Flags

**Phases likely needing deeper `/gsd-research-phase` during planning:**
- **Phase 0-1:** Qt-vs-Tk runtime validation — confirm `pymol.Qt` import works in the `setenv.bat`-launched PyMOL (closes the last LOW-confidence gap). Light research — mostly a smoke test.
- **Phase 2:** `cmd.create` merge-append vs replace semantics into an existing object's current state (MEDIUM confidence); `.pse` round-trip `id`/`index` stability (MEDIUM). A 5-line smoke test resolves both. Also confirm chempy `cmd.get_model`/`cmd.load_model` as a fallback if `create`-merge proves unreliable.
- **Phase 4 (cartoon):** How to "replicate a segment (loop) as alternate position" via C-alpha — genuinely novel geometry; needs a dedicated research spike on cartoon representation internals (`cmd.get_fasta`, secondary structure, C-alpha chain endpoints, `cmd.attach_amino_acid` dihedrals). **This is the highest-research-flag phase.**
- **Phase 5:** `.pse` + companion file co-location UX — two-file share is awkward; decide whether to zip them or document "keep both files together".

**Phases with standard patterns (skip research-phase):**
- **Phase 3:** Wizard `do_pick` + `cmd.index('pk1')` + QTimer are all well-documented, verified patterns (`mtsslWizard.py`, official wiki, `lightingsettings_gui`). Standard implementation.
- **Phase 6 (polish):** `QProgressDialog`, `cmd.fetch(async_=0)`, `urllib.request`, `gzip` are all standard stdlib/PyMOL patterns. The only research need is MemProtMD license verification (a single web check, not a phase-research).

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against cloned PyMOL 2.5.0 source (`v2.5.0` commit `9ea504e`) + conda-forge feedstock `meta.yaml` + 6 modern reference plugins (`outline`, `optimize`, `dynoplot`, `views`, `vina`, `colorama`) + in-tree `lightingsettings_gui` template. PyQt5-via-`pymol.Qt` is unambiguous. The only spec deviation (Qt vs Tk) is resolved by follow-up verification (STACK.md "FOLLOW-UP VERIFICATION" section) — Tkinter is the same legacy family as Pmw, not an alternative. |
| Features | HIGH (features) / MEDIUM (educational framing) / LOW (competitor absence) | Features map 1:1 to spec. Educational framing is inferred from genre conventions + PROJECT.md constraints. No direct competitor could be verified (absence not positively confirmable). |
| Architecture | HIGH (plugin mechanics, picking, save/load, object-mutation, build order) / MEDIUM (`cmd.create`-merge semantics, `.pse` `id`/`index` stability — both closeable with a Phase-2 smoke test) | Layering (GUI → controller → pymol_io) is the consensus pattern. The build order is dictated by a dependency DAG. |
| Pitfalls | HIGH (PyMOL API behavior, plugin architecture, RCSB/SASBDB licensing) / MEDIUM (MemProtMD licensing — site unreachable at research time) | Pitfalls verified against `pymol-open-source` `editor.py`/`creating.py`/`selector.py`, official PyMOL wiki, RCSB/SASBDB policy pages. MemProtMD needs per-entry license verification at the demos phase. |

**Overall confidence:** HIGH

### Gaps to Address

- **`cmd.create`-merge append-vs-replace semantics** (MEDIUM) — Resolve with a 5-line smoke test in Phase 2: insert a fragment into an existing object's current state and verify atoms are appended (not replacing). Fallback: chempy `cmd.get_model`/`cmd.load_model` rebuild.
- **`.pse` round-trip `id`/`index` stability** (MEDIUM) — Confirm in Phase 2 that `id` survives a save/load `.pse` cycle. Mitigation: build registry to fall back to `(chain, resi, name)` identity if `id` reindexes; the `segi='GAME'` + `b=-999` sentinel is the ultimate safety net for session-reload reconstruction.
- **Cartoon hider geometry** (MEDIUM-LOW) — The "replicate a segment (loop) as alternate position" mechanic is genuinely novel; no reference plugin does this. Needs a dedicated research spike in Phase 4 on `cmd.attach_amino_acid` dihedrals, C-alpha chain endpoints, and secondary-structure handling. May phase to v1.x if timeline forces.
- **MemProtMD licensing** (MEDIUM — site unreachable) — Verify per-entry license at the demos phase (Phase 6) before bundling membrane coordinates. The PDB entries (1GZM, 3GP6) are CC0; the DPPC membrane coordinates from MemProtMD may carry stricter terms (CC-BY etc.).
- **WSL→Windows path passing** (LOW-MEDIUM) — `cmd.load('/mnt/c/...')` fails in Windows PyMOL. Resolve in Phase 0-1 with a `to_windows_path()` helper + early end-to-end load test via `setenv.bat`.
- **Click vs drag disambiguation** (MEDIUM) — PyMOL gives no raw mouse events from Python; the Wizard `do_pick` fires on picks, but drag-to-rotate may register as picks depending on mouse mode. Resolve in Phase 3 with a mouse-displacement + time threshold, and force a known pick mode on Start (save/restore prior).
- **Competitor existence** (LOW — absence not confirmable) — No direct competitor found; bioCHEMeleon appears novel. No action needed except to note the differentiators are what earn "educational tool" rather than "novelty toy" status.

---

## Sources

### Primary (HIGH confidence)
- **PyMOL open-source v2.5.0 source** (cloned `schrodinger/pymol-open-source` tag `v2.5.0`, commit `9ea504e`) — `_PyMOL_VERSION`, plugin loader (`__init_plugin__` vs legacy `__init__`), `addmenuitemqt` (raises `QtNotAvailableError` if no Qt), `pymol.Qt` auto-select (PyQt5/PySide2/PyQt4/PySide), `Wizard` base class + `do_pick` + `event_mask_pick`, `cmd.create`/`alter`/`iterate`/`index`/`get_model`/`load_model`/`save`/`fetch`/`pseudoatom`/`set_wizard`/`refresh_wizard`, `data/startup/lightingsettings_gui/` canonical template (`__init_plugin__` + `addmenuitemqt` + `pymol.Qt` + `QtWidgets.QDialog`), `setup.py` (`--bundled-pmw` removed → Pmw not bundled; numpy build-req), `legacysupport.get_tk_root()` returns `None` under Qt GUI.
- **conda-forge `pymol-open-source` feedstock `meta.yaml`** — confirms `pyqt` and `pmw` are runtime deps (PyQt5 already in user's env — zero installs needed for v1).
- **PyMOL Wiki** — `/Plugins` (Tk deprecated, "removal by 4.0"; PyQt5 preferred), `/Plugins_Tutorial` (`__init_plugin__` + `addmenuitemqt` + `pymol.Qt` + `loadUi` + global dialog ref), `/PluginArchitecture` (`pref_set` basic types only), `/Pseudoatom` ("adds to existing object if it exists"), `/Iterate` (`index` unique per object, sensitive to sort/remove; `ID`/`rank` not guaranteed unique), `/Create` (merge/state semantics), `/Wizard` (`cmd.set_wizard()`), `/Save` (`.pse` saves complete PyMOL state, ignores plugin Python objects).
- **RCSB PDB `/pages/policies`** — CC0 1.0 Public Domain Dedication; cite PDB ID + DOI + publication + graphics program.
- **SASBDB `/about/`** — free of copyright restrictions for non-commercial and commercial use; attribute original authors.

### Secondary (MEDIUM-HIGH confidence)
- **`Pymol-script-repo/plugins/`** (git-ignored reference) — `outline.py` (Schrodinger-authored modern Qt plugin — exact `__init_plugin__(app=None)` + `pymol.Qt` pattern; Pillow dep caveat: don't copy imports wholesale), `optimize.py` (Qt port, `QTabWidget` replaces `Pmw.NoteBook`, explicit Tk→Qt migration comments), `dynoplot.py` ("Ported to PyQt 2024 by Thomas Holder"), `views.py`/`vina.py`/`colorama.py` (modern Qt entry points — 6/6 actively-maintained plugins use `__init_plugin__` + `pymol.Qt`), `show_contacts.py` (hybrid: Qt primary + Tk+Pmw fallback — anti-pattern: don't keep the Tk fallback class), `mtsslWizard.py` (Wizard/`do_pick` pattern, reads `(sele)`), `bnitools.py` (`cmd.create(name, "(%s or %s)" % (a, b))` merge idiom, `cmd.alter`), `annocryst.py` (`cmd.index(self.selection)` for unique atom IDs), `emovie.py` (`.pse` + companion `.emov` pickle save/load — proof of companion-file pattern), `msms.py`/`rendering_plugin.py`/`mole.py`/`contact_map_visualizer.py`/`pytms.py` (legacy Tk anti-patterns: `def __init__(self):` + `self.menuBar.addmenuitem(...)` + `app.root` + `Pmw.Dialog`).
- **`pymol-open-source` `editor.py`** — `cmd.fuse` modes (1/2/3 differ in bond geometry), `cmd.attach_amino_acid`, `cmd.attach_nuc_acid`, `undocontext` no-op stub (no undo in open-source), `cmd.alter(..., space=...)` pattern, `pk1`/`pk2` picking selections.
- **`pymol-open-source` `creating.py`** — `cmd.pseudoatom` signature + defaults (`elem='PS'`, `resn='PSD'`, `chain='P'`, `segi='PSDO'`, `hetatm=1` — inappropriate for hiders, must override), `_self.lock`/`lockcm` threading guards on every command.
- **`pymol-open-source` `selector.py`** — canonical atom-id form `"%s`%d" % (model, index)`.
- **Hidden object game genre** (Wikipedia) — conventions: hints, remaining counter, timer, zoom booster, time extension (we adopt hint + remaining + timer; skip zoom booster + time extension per cozy-educational tone).

### Tertiary (MEDIUM-LOW confidence — needs validation)
- **MemProtMD** (`memprotmd.bioch.ox.ac.uk`) — reachable (verified 2026-08-14, HTTP 200; the prior "unreachable" was a domain typo — "oxy" instead of "ox" in the hostname). License: CC-BY 4.0 (verified from site JS bundle). Cite Newport et al., *The MemProtMD database*, Nucleic Acids Res. 2019;47(D1):D390-D397 (DOI: 10.1093/nar/gky1047, primary) + Stansfeld et al., *MemProtMD*, Structure 2015;23(7):1350-1361 (DOI: 10.1016/j.str.2015.05.006, methodology). Per-entry license verified: CC-BY 4.0 for membrane coordinates (DPPC bilayer); PDB entries (1GZM, 3GP6) are CC0.
- **Competitor existence** — no verified existing "molecular hide-and-seek" game; searched PyMOL/VMD/MolStar/ChimeraX/Jmol via webfetch — could not positively confirm absence, but no evidence surfaced. bioCHEMeleon appears novel.

---
*Research completed: 2026-08-03*
*Ready for roadmap: yes*
