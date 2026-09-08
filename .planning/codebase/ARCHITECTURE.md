# Architecture

**Analysis Date:** 2026-09-08

## Pattern Overview

**Overall:** Multi-viewer monorepo of independent host-app plugins, all implementing the same game: load a molecule → generate "hider" atoms/representations that blend into the scene → click-to-find them against a timer → win. Each viewer gets its own top-level directory with its own language, layering, entry point, and test strategy:

| Viewer | Directory | Status | Stack | Host |
|--------|-----------|--------|-------|------|
| v1 | `pymol/` | SHIPPED (frozen 2026-08-18, 12 phases + 04.1) | Python 3.6 / PyQt5 via `pymol.Qt` | PyMOL 2.5.0 |
| v2 | `vmd/` | ACTIVE milestone (v2.0, phases 13–17.2 built; 17.2-12 GUI checkpoint pending) | Tcl 8.5.6 / Tk+ttk (host-bundled) | VMD 1.9.3 |
| v3 | `chimeraX/` | Placeholder only (`chimeraX/.gitkeep`; future milestone candidate, research not started) | — | ChimeraX |

**Key Characteristics:**
- **Plugin-into-host-app, never standalone.** Both shipped viewers are extension scripts loaded by their host (`__init_plugin__` for PyMOL; `source` + `vmd_install_extension` for VMD). All molecule ops go through host commands (`cmd.*` / `mol`/`atomselect`); no independent process.
- **Strict pure-vs-mol-bridge-vs-GUI dependency direction, mirrored in both viewers.** Pure modules (stdlib only, unit-testable in WSL without the host) sit at the bottom; mol-bridge modules depend on them; GUI sits on top; a composition root orchestrates. Never reverse. See per-viewer layer stacks below.
- **DI at the pure boundary.** The registry stays pure (no host commands) by accepting an injected fetch function; the composition root injects the real one (`vmd/lib/game.tcl:323`, the direct port of v1's `pymol/biochemeleon/game.py` pattern).
- **No undo in either host → snapshot/restore is the only recovery.** PyMOL: `cmd.create('_bchm_backup', ...)` snapshot. VMD: record the original PDB path + viewpoint + reps, then whole-molecule reload (`mol delete` + `mol new`).
- **Hiders identified by SENTINEL ONLY.** v1: `segi='GAME'` + `b=-999`. v2: `resname=GAM` + `beta=-999` + `segid=GAME` (residue records: beta −999 on the CA only). Never by `resi`/`chain`/index.
- **The same-core-molecule mechanic differs fundamentally between viewers.** v1 inserts hiders in-place (`cmd.pseudoatom(object=existing)`). v2 cannot add atoms — it REBUILDS the PDB (splice hider records into ATOM/HETATM lines, write a combined file, `mol delete` original, `mol new <combined>`). This PDB-rebuild is v2's single biggest architectural change, encapsulated in `vmd/lib/mutation.tcl`.
- **Composition + DI + data-table dispatch, no inheritance hierarchies.** v2 dispatches per-rep behavior through the tier tables in `vmd/lib/rep_tiers.tcl` (`IMPLEMENTED_TIERS`, `TIER_KINDS`) and `vmd/lib/game.tcl`'s per-tier placement loop, not through strategy classes. v1 does the same via a `mutation.insert_hider_for_rep` dispatcher.
- **Modeless main dialog in both viewers** so the 3D viewer stays interactive for click-to-find. Enforced by grep gates: `grep -rnE "grab set" vmd/gui/` and `grep -rnE "\.exec_\(\)" biochemeleon/` (pymol).
- **Tcl 8.5 / Python 3.6 language ceilings.** v2 forbids Tcl 8.6 idioms (`try`/`lmap`/`tailcall`/`coroutine`/`yield`) — enforced by the 8.5-idiom gate; use `catch` + `foreach`+`lappend`.

## Layers — v2 VMD port (active milestone)

**Entry / bootstrap (thin):**
- Purpose: re-source guard, namespace init, `package provide`, source the lib chain in dependency order, register the Extensions menu, define the user-facing `biochemeleon` command. Sourcing does NOT auto-open the dialog.
- Location: `vmd/biochemeleon.tcl` (179 lines), optional packaged-install form `vmd/pkgIndex.tcl` (`package ifneeded biochemeleon 2.0`).
- Depends on: everything below (sources it, in order).
- Entry path: user runs `source vmd/biochemeleon.tcl` (or `.vmdrc` / Plugin Manager auto-load) → clicks **Extensions → Visualization → bioCHEMeleon** → `biochemeleon_tk_cb` → `::biochemeleon::open_dialog`, or types `biochemeleon` at the VMD console.

**Pure layer (stdlib tcl 8.5 only — NO `mol`/`atomselect`, NO `tk`/`toplevel`; unit-testable in WSL via `tclsh`/`tcltest`):**
- Purpose: data schema, registries, geometry, state machines, dispatch decisions — everything that needs no molecule or GUI.
- Location: `vmd/lib/setup_state.tcl`, `vmd/lib/registry.tcl`, `vmd/lib/generators.tcl`, `vmd/lib/game_logic.tcl`, `vmd/lib/rep_tiers.tcl`, `vmd/lib/splice.tcl`.
- Contains: `GAME_REPS` (10 viable reps), `DEMO_MANIFEST`, `validate_state`/`randomize_state`/`randomize_per_rep` (`setup_state.tcl`); the hider registry keyed by atom index with sentinel reconstruction via DI + the fake-resid→CA block (`registry.tcl`); sphere/bonded placement geometry + seeded `sample` (`generators.tcl`); round state machine idle→countdown→playing→won, timer, log model (`game_logic.tcl`); the tier seam + lock-scene/randomize resolution (`rep_tiers.tcl`); peptide-bond perpendicular displacement math + 78-char PDB line assembly (`splice.tcl`).
- Depends on: stdlib + each other downward (`registry`→`setup_state`; `rep_tiers`→`setup_state`; `splice`→`generators`→`setup_state`).
- Used by: every layer above.
- Purity rule: `setup_state.tcl` and `registry.tcl` must have ZERO `mol`/`atomselect` and ZERO `tk` calls. All module constants (`IMPLEMENTED_TIERS`, `TIER_KINDS`, `RESID_BASE 9001`, `SPLICE_DISPLACEMENT 1.0`) live here.

**Mol-bridge layer (`mol`/`atomselect` allowed, NO Tk; headless-runnable via `vmd -dispdev text`):**
- Purpose: the ONLY place host molecule commands are called. Each bridge is standalone or sources pure modules only — no cross-bridge `source` (exception: `mutation.tcl` re-sources pure constants, harmless).
- Location and responsibilities:
  - `vmd/lib/demos.tcl` — demo loading (`load_demo`), RCSB fetch (`fetch_pdb`), WSL→VMD path guard `to_vmd_path` (`/mnt/c/...` → `C:/...` forward slashes), setup save/load (`.bcm`-style setup files), `atom_count`, `get_active_reps`, `list_loaded_molecules`. Sources `setup_state.tcl`.
  - `vmd/lib/backup.tcl` — snapshot/apply/restore of viewpoint (4-matrix), all reps `{style sel color material}` records, and the original PDB path. **Sources NOTHING** (standalone).
  - `vmd/lib/mutation.tcl` — the PDB-rebuild engine: `make_placeholder_hiders` (free tier), `make_bonded_hiders` (bonded tier, 1.2–1.6 Å from anchor), `make_residue_hiders` (residue tier, fake GAM residue via splice), `write_combined_pdb` (strict 78-col PDB lines, `splice::atom_record`), `tag_sentinels` / `tag_sentinels_mixed` (CA-only beta on residue rounds — Pitfall C6), `fetch_hider_indices` (file-order sentinel list), `mutate` (3-arg dispatch: mol delete original + mol new combined + tag → NEW game_molid). Sources `setup_state.tcl` + `generators.tcl` + `splice.tcl`.
  - `vmd/lib/hiders.tcl` — the visual half: ONE hidden/found rep PAIR per active tier (2N reps, static selections on `user3` tier codes + `user2` found flags), `stamp_tier_codes` (MUST precede `add_hider_reps` — cached rep selections never re-evaluate on a static molecule), `mark_found_visual` (user2 write + modselect re-assert of ALL pairs). Sources NOTHING.
  - `vmd/lib/pick_bridge.tcl` — click delivery: `trace add variable ::vmd_pick_event write _on_event` primary (reads globals `vmd_pick_atom` + `vmd_pick_mol`), dormant labelpoll fallback, mouse-mode save/restore, baseline-guarded label hygiene. Forwards EXACTLY `game::on_pick <index>` (one arg). Sources NOTHING.
- Depends on: `pymol`-side equivalent is `from pymol import cmd`; here it is raw `mol`/`atomselect`/`molinfo`/`label`/`mouse` commands.
- Used by: `vmd/lib/game.tcl` (composition root) and `vmd/gui/*`.

**Composition root (orchestrator):**
- Purpose: wire backup + mutation + registry + rep_tiers + hiders + game_logic into one round lifecycle; own the click-scoring controller. The ONLY module that touches all of them.
- Location: `vmd/lib/game.tcl` (622 lines). **Sources NOTHING** — the entry sources the lib chain before it (re-sourcing `registry.tcl` here would WIPE the populated `_records` dict).
- Contains: `start_game {molid hider_count {per_rep {}} {lock_scene 0}}` (the N-tier DISPATCH composition root), `cleanup {game_state}`, `restart {game_state}`, `on_pick {idx}`, `set_callbacks {log_cb remaining_cb win_cb}`, private `_resolve_pick {idx}` (direct-hit → resid-block fallback two-stage resolver).
- State: namespace var `current_state` — the 4-key game_state dict `{game_molid hider_count snapshot per_rep}` stashed by `start_game`, cleared by `cleanup` (so `pick_bridge` needs to deliver only the index, never the state). Callback prefixes `_cb_log`/`_cb_remaining`/`_cb_win` invoked as `catch {{*}$cb <args>}`.
- DI seam: `registry::reconstruct_from_sentinels` receives `[list apply {{molid} {atomselect...}} $game_molid]` — a command-prefix VALUE, never an immediate `[apply ...]` evaluation (the 13-01 DI bug).

**GUI layer (Tk + ttk + mol — top of stack; GUI-only, cannot run in `-dispdev text`):**
- Purpose: the modeless `ttk::notebook` dialog (Setup + Game tabs) and all widget/timer/refresh handling. NO game logic — routes actions to `game::*` and reads `registry::*`.
- Location: `vmd/gui/dialog.tcl` (sourced by the entry; sources both tab modules at TOP-LEVEL source time so `[info script]` resolves — never inside proc bodies), `vmd/gui/setup_tab.tcl` (target/hiders/difficulty groups, `collect_state`/`apply_state`, molecule-menu refresh trace, demo selection, save/load), `vmd/gui/game_tab.tcl` (`start_round` → `set_callbacks` + `pick_bridge::activate` + countdown chain, 1 Hz `tick`, rolling log, per-rep remaining, win box, `stop_all_timers`).
- Depends on: `::biochemeleon::{demos,game,game_logic,registry,backup?}::*` at CALL time; `setup_tab.tcl` also uses `demos::load_demo`/`atom_count`.
- Used by: the entry's `biochemeleon` / `biochemeleon_tk_cb` procs.

**Module source chain (from `vmd/biochemeleon.tcl:75-118` — the load-order contract):**

```
vmd/biochemeleon.tcl
├── 1. lib/setup_state.tcl   (PURE)
├── 2. lib/registry.tcl      (PURE — sourced EXACTLY ONCE; never re-source)
├── 3. lib/generators.tcl    (PURE)
├── 4. lib/game_logic.tcl    (PURE)
├── 5. lib/rep_tiers.tcl     (PURE; sources setup_state itself — harmless re-init)
├── 6. lib/demos.tcl         (mol; sources setup_state)
├── 7. lib/backup.tcl        (mol; standalone)
├── 8. lib/mutation.tcl      (mol; sources setup_state+generators+splice)
├── 9. lib/hiders.tcl        (mol; standalone)
├──10. lib/game.tcl          (composition root; sources NOTHING)
├──11. lib/pick_bridge.tcl   (mol; standalone)
└──12. gui/dialog.tcl        (Tk; sources gui/setup_tab.tcl + gui/game_tab.tcl)
```

Proc resolution is CALL-TIME in tcl, so `game.tcl` may reference `rep_tiers::*`/`hiders::*`/`registry::*`/`game_logic::*` namespaced procs defined later in the chain — only the namespaces must exist before the first CALL. The hard constraints are: `registry.tcl` exactly once (state wipe), and the pure block before the mol bridges that re-source it.

## Layers — v1 PyMOL plugin (shipped, frozen)

Same four-layer shape in Python. Reference: `pymol/AGENTS.md`.

- **Pure:** `pymol/biochemeleon/setup_state.py`, `registry.py`, `generators.py`, `persistence.py` — stdlib only; WSL-runnable via `python3.6 -m unittest` (with `sys.modules` stubs for `pymol`/`pymol.Qt`).
- **cmd bridges:** `pymol/biochemeleon/backup.py`, `mutation.py`, `demos.py`, `wizard.py` (PickWizard — the v1 click bridge).
- **Orchestrator:** `pymol/biochemeleon/game.py` (`GameController` — composition root of the cmd layer).
- **GUI:** `pymol/biochemeleon/gui_setup.py`, `gui_game.py` (Qt; modeless `dialog.show()`).
- **Entry/composition root:** `pymol/biochemeleon/__init__.py` (`__init_plugin__`, singleton `PluginDialog`, lazy imports inside methods).
- Data: `pymol/biochemeleon/data/demos/` (6 PDBs + `SOURCES.md` — the CANONICAL demo set; v2 reuses these, see `vmd/data/demos/`).
- Tests: `pymol/tests/test_*.py`; smokes: `pymol/smoke/phase*_smoke.py` + `diag_*.py` diagnostics (run headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq`).

## Data Flow — v2 (the full round)

**Start → win → cleanup (`vmd/lib/game.tcl`):**

1. User clicks Start → `::biochemeleon::on_start` (dialog.tcl) fans the Setup form through `setup_state::validate_state` → **4-arg** `game::start_game $molid $hider_count $per_rep $lock_scene`.
2. **Active-game guard** (`game.tcl:158-191`): a non-empty `current_state` stash is cleaned up FIRST (auto-restart with the CALLER's settings; target remapped by liveness if the requested molid was the old game molecule). Stacked hider generations are impossible at this single choke point.
3. `backup::snapshot $molid` — original PDB path + 4-matrix viewpoint + all reps, BEFORE any mutation.
4. Lock-scene detection: `rep_tiers::scene_reps_to_per_rep` over the snapshot's reps (sentinel filter `resname GAM` is defense-in-depth).
5. `rep_tiers::resolve_per_rep` → the EFFECTIVE per_rep (lock-scene restriction / randomize over `IMPLEMENTED_TIERS` / drop-overflow clamp); `effective_total` = P9 effective hider count. `tiers_from_per_rep` → ordered `{code style count}` triples in GAME_REPS order.
6. **Per-tier placement loop** (GAME_REPS order, `game.tcl:242-303`): kind `free` → `mutation::make_placeholder_hiders`; kind `bonded` → `mutation::make_bonded_hiders` with the accumulating `occ_hiders` position list; kind `residue` → `mutation::make_residue_hiders` with the `resid_start` offset (`splice::RESID_BASE 9001` + residue records placed so far — two residue tiers must not collide on the 9001 block). ACTUAL per-tier counts are tracked (tiers may under-generate; supply-0 degrades to 0 records with a warn, never an abort).
7. **ONE `mutation::mutate`** call with ALL records (`game.tcl:311`): writes the combined PDB (simple records first, then residue records with continuing serials), `mol delete` original, `mol new <combined>`, tags sentinels (`tag_sentinels_mixed` when residue records exist — CA-only beta; never `tag_sentinels` on a residue round) → returns the NEW game_molid (monotonic, never reused).
8. `backup::apply` re-applies reps + viewpoint on the NEW game_molid (SC4 forward).
9. `registry::reconstruct_from_sentinels` ONCE with the injected atomselect command prefix; then the sentinel index list is split per tier by a TWO-PASS file-layout walk (all simple tiers, then all residue tiers — the combined PDB is written simple-first, so a plain GAME_REPS-order walk would mis-slice mixed rounds).
10. `hiders::stamp_tier_codes` (user3) THEN `hiders::add_hider_reps` — one hidden/found rep pair per tier (2N reps land LAST, after the base reps; ORDERING CONTRACT: stamp before add, apply before add).
11. `registry::assign_reps` (ONE bulk call — never a per-tier reconstruct loop) + `registry::register_resid_block` (fake-resid → CA index map for the on_pick fallback; skipped when no residue tier).
12. game_state stashed in `current_state`; the Game tab's `start_round` registers callbacks (`game::set_callbacks`), drives `game_logic::round_reset → begin_countdown → countdown_tick ×4 → begin_play`, and activates `pick_bridge::activate $game_molid`.
13. **Click-to-find loop:** real click → VMD writes `::vmd_pick_event` → `pick_bridge::_on_event` → `game::on_pick <index>` → `_resolve_pick` (direct registered hit, or resid-block fallback re-targeting a cartoon-bump N/C/O/CB click to the residue's registered CA) → three-way guard (miss / already-found / hidden) → `hiders::mark_found_visual` + `registry::mark_found` → log + remaining callbacks → on last find: `game_logic::finish_win` (frozen timer) → `win_cb`.
14. `game::cleanup $game_state`: `backup::restore` (mol delete the LIVE game_molid — NOT snapshot.molid, which mutate killed — + mol new original + apply reps/viewpoint) → `registry::reset` → stash cleared.

**State Management:**
- **Hider registry:** `::biochemeleon::registry` namespace singleton (`_records` dict keyed by atom index) — the single source of truth for hiders; rebuilt from sentinels each round (no cross-reload persistence yet; `.bcm` sidecar is a planned phase).
- **Round state:** `game::current_state` (4-key dict) + `game_logic`'s state machine (`state`, timer, log list — pure, namespace vars).
- **GUI state:** `::biochemeleon::state` (entry namespace var) holds setup form state; `setup_tab`/`game_tab` namespace vars hold widget handles, after-ids, and `tier_reps` visual bookkeeping (rep NAME-keyed, never index-keyed).
- **Identity model:** VMD has no global atom id — identity is `(molid, index)`; molids are monotonic and change on reload, so the registry must be reconstructed from sentinels after every cleanup/reload.

## Key Abstractions

**game_state dict (4 keys):**
- Purpose: the round's complete handle, passed to cleanup/restart, stashed for on_pick.
- Examples: built at `vmd/lib/game.tcl:407`; shape `{game_molid hider_count snapshot per_rep}`; `hider_count` is the P9 EFFECTIVE total (sum of resolved per_rep) so win messages never disagree with the registry.
- Pattern: immutable-after-start; cleanup clears the stash, never mutates.

**Hider sentinel (v2 shape):**
- Purpose: the stable identifier for hiders across rebuild/reload/cleanup.
- Examples: set by `vmd/lib/mutation.tcl` (`tag_sentinels` / `tag_sentinels_mixed`: `resname GAM`, `beta -999` — CA only on residue records — `segid GAME`, chain `G`, resids 9001+); read via selector `resname GAM and beta < 0` (comparison, NEVER exact `beta -999`).
- Pattern: sentinel-only identification. Found flags live ONLY in `user2`; tier codes in `user3`; beta stays −999 forever (NEVER write beta after tagging).

**Hider registry (pure):**
- Purpose: source of truth for hider status/rep mapping; stays pure via DI.
- Examples: `vmd/lib/registry.tcl` — `reconstruct_from_sentinels` (injected fetch fn), `is_hider`/`status_of`/`mark_found` (silent idempotent), `count_remaining`/`remaining_by_rep`, `assign_reps` (bulk), `register_resid_block`/`hider_for_resid` (residue-tier pick fallback), `reset`.
- Pattern: namespace singleton; re-sourcing the file wipes it — sourced exactly once in the entry.

**Tier dispatch seam (`vmd/lib/rep_tiers.tcl`):**
- Purpose: per-rep generator routing WITHOUT class hierarchies.
- Examples: `IMPLEMENTED_TIERS` (all 10 GAME_REPS since 17.2-03 — the lists are kept separate on purpose so the seam can diverge again), `TIER_KINDS` dict (`Lines/Licorice/CPK/Points/DynamicBonds` → bonded; `VDW` → free; `Cartoon/NewCartoon/Trace/Tube` → residue), `style_args` (DynamicBonds carries explicit cutoff 1.6 — the spurious-bond rule), `resolve_per_rep`/`effective_total`/`scene_reps_to_per_rep`.
- Pattern: ONE splice (`vmd/lib/splice.tcl`), FOUR residue consumers; game.tcl routes by `tier_kind`.

**PDB-rebuild mutation (Option D):**
- Purpose: reimplement "hiders in the same molecule" under VMD's no-atom-insert constraint.
- Examples: `vmd/lib/mutation.tcl` (`write_combined_pdb`, `_hider_record`, `mutate`) + `vmd/lib/splice.tcl` (`atom_record` — byte-identical 78-col layout; `RESID_BASE 9001` disjoint block; `SPLICE_DISPLACEMENT 1.0 Å` perpendicular to the peptide bond, envelope 1.43 Å).
- Pattern: strict PDB column discipline (`%8.3f` coords with a 9999 overflow guard; element cols 77-78 are the load-bearing blend field; `%6.1f` renders the CA beta as `-999.0` — `%6.2f` would overflow the field and corrupt segid).

**Snapshot/backup:**
- Purpose: the only recovery mechanism (VMD has NO undo, no per-atom delete).
- Examples: `vmd/lib/backup.tcl` — `snapshot` (before any mutation), `apply` (state-only re-assert on the new molid), `restore` (mol delete game + mol new original + apply).
- Pattern: cleanup deletes the LIVE game_molid (snapshot.molid is dead by then); molids are monotonic so liveness checks via `molinfo ... get numatoms` are collision-free.

**PickBridge contract:**
- Purpose: deliver real-mouse clicks to `game::on_pick` with exactly one argument.
- Examples: `vmd/lib/pick_bridge.tcl` — `trace add variable ::vmd_pick_event write` primary (handler MUST be `{args}`); labelpoll fallback dormant; mouse-mode save/restore; label hygiene.
- Pattern: game state NOT threaded through the bridge — `game.tcl` owns `current_state`. Known first-click quirk: one keyboard `p` press per round arms C-side pick delivery (locked, GUI-verified; documented in `vmd/AGENTS.md`).

## Entry Points

**`source vmd/biochemeleon.tcl` → Extensions → Visualization → bioCHEMeleon:**
- Location: `vmd/biochemeleon.tcl` (re-source guard at line 29; menu registration at line 173-177).
- Triggers: user sourcing, `.vmdrc`, or VMD plugin auto-load (optional `vmd/pkgIndex.tcl` enables `package require biochemeleon`).
- Responsibilities: guard → namespace → `package provide biochemeleon 2.0` → source the 12-module chain → define global `biochemeleon` proc (Tk-guarded graceful no-op in `-dispdev text`) + `biochemeleon_tk_cb` → `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"`. Sourcing does NOT auto-open the dialog.

**`game::start_game`:**
- Location: `vmd/lib/game.tcl:147`.
- Triggers: dialog `on_start` (4-arg, per_rep + lock_scene from the Setup form), console calls, `restart`, and the active-game guard's internal re-start.
- Responsibilities: the 14-step dispatch sequence above; returns the 4-key game_state.

**`game::on_pick {idx}`:**
- Location: `vmd/lib/game.tcl:573`.
- Triggers: `pick_bridge::_on_event` only (contract: one argument).
- Responsibilities: state gate → stash guard → resolve → three-way guard → mark → win check. Entirely catch-wrapped (`rc == 1` check — errors are reported via `vmdcon -err`, never re-raised from a pick trace).

**v1 equivalents (frozen):** `pymol/biochemeleon/__init__.py` `__init_plugin__` (Plugins menu) → `run_plugin_gui` → `PluginDialog._on_start` → `GameController.start` (`pymol/biochemeleon/game.py`); picks via `pymol/biochemeleon/wizard.py` PickWizard.

## Error Handling

**Strategy:** no-undo tolerance — every destructive sequence is preceded by a snapshot and is recoverable by whole-molecule reload; runtime errors are caught at boundaries and reported, never allowed to leak from event-loop callbacks.

**Patterns:**
- **catch + error, not try/finally:** Tcl 8.5 has neither — the `catch {script} msg` + explicit restore pattern everywhere (e.g. `game.tcl:161-169` stale-stash recovery re-does `registry::reset` + stash clear in the catch branch).
- **on_pick double-shield:** whole scoring body catch-wrapped with `set rc [catch {...} err]` + `if {$rc == 1}` (a truthy catch test would misfire on TCL_RETURN; `game.tcl:582-621`).
- **Read-back validation, never catch, for mol styles:** `mol modstyle` with a bad style silently no-ops — `hiders::add_hider_reps` reads every rep back via the COMBINED-BRACES `molinfo` form and hard-errors on mismatch (`vmd/lib/hiders.tcl` header, style-validation section).
- **Supply-0 degradation:** under-generation (bonded cap, residue eligible-anchor supply) yields fewer records + a non-blocking `vmdcon -warn`; a round never hard-aborts on a degenerate scene (`game.tcl:262-266`).
- **Unimplemented-tier tolerance:** requested tiers with no generator are dropped with a warn (`game.tcl:208-212`).
- **atomselect hygiene:** every `$sel delete` after use — dangling selections leak and return STALE DATA silently.
- **v1 equivalents:** snapshot-before-mutation invariant, two-step `delete`+`create` restore, `verify_intact` return-value assertion (`pymol/biochemeleon/backup.py`, `game.py`).

## Cross-Cutting Concerns

**Logging:** No logging framework. Player-facing events flow `game_logic::log_append` → `game::set_callbacks` log_cb → `game_tab::on_log_line` rolling text widget. Diagnostics: `vmdcon -info/-warn/-err` for user-visible notes; smoke scripts print PASS/FAIL to stdout and run logs land in `tmp/`.

**Validation:** pure-layer `setup_state::validate_state` (clamps, PDB-code checks, GAME_REPS order-stability) + `hider_count_cap`; GUI `collect_state`/`apply_state` round-trip; per-claim probe verification recorded in `.planning/research/` and phase RESEARCH docs.

**Purity gates (grep-enforced, documented in `vmd/AGENTS.md`):**
- Tcl 8.5 gate: `grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/` — MUST return zero.
- Modeless gate: `grep -rnE "grab set" vmd/gui/` — MUST return zero on the main panel.
- NEVER `mol ssrecalc` in the generation flow (load-time STRIDE already assigns ss; ssrecalc wipes manual writes — Pitfall C2, `vmd/lib/splice.tcl` Option-A record).

**Path hygiene (WSL→Windows split):** `demos::to_vmd_path` (`vmd/lib/demos.tcl:36`) converts `/mnt/c/...` → `C:/...` forward slashes; `vmd/wsl2win_cp.sh` stages `vmd/` → `tmp/biochemeleon-vmd/` so headless VMD's `[pwd]` resolves. v1's analog: `demos.to_windows_path` (`pymol/biochemeleon/demos.py`) with backslashes.

**Authentication:** Not applicable — desktop plugins. `fetch_pdb` uses Tcl `socket`/HTTP and v1 uses stdlib `urllib` against RCSB/MemProtMD/SASBDB; no API keys. Demo PDB provenance: `vmd/data/demos/SOURCES.md` (copied from `pymol/biochemeleon/data/demos/SOURCES.md`).

**Testing boundary:** pure layer → `tclsh vmd/tests/test_*.test` / headless-VMD tcltest suites (6 suites, 205 tests); mol-coupled code → `vmd/smoke/phase*_smoke.tcl` headlessly via `bash -ic "vmd -dispdev text -e ... -eofexit"` on a staged copy; GUI/Tk/real-mouse picking → human-verify checkpoints driven by `vmd/tests/rep_verify.tcl` (GUI auto-driver) — see TESTING.md.

---

*Architecture analysis: 2026-09-08*
