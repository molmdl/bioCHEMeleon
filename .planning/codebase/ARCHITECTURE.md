# Architecture

**Analysis Date:** 2026-08-18

## Pattern Overview

**Overall:** Layered single-process PyMOL 2.5.0 plugin with a strict pure-vs-cmd-vs-Qt dependency direction and a composition-root orchestrator. The package is FLAT (one directory, 12 sibling `.py` modules) — NOT the nested `gui/`+`game/`+`pymol_io/` sketch in `.planning/research/ARCHITECTURE.md`; that research doc was the *recommended* shape, the shipped implementation is flat.

**Key Characteristics:**
- **Strict layering by purity, not by folder.** Four pure modules (stdlib-only, WSL-unit-testable) sit at the bottom; cmd-coupled bridge modules depend on them; a Qt GUI layer sits on top; `__init__.py` is the GUI composition root and `game.py` is the cmd-layer composition root.
- **Dependency injection at the pure boundary.** `registry.py` stays pure (no `from pymol`) by accepting an injected iterate callable in `reconstruct_from_sentinels`; `game.py` injects `lambda: mutation.fetch_all_hider_ids(obj)`.
- **No undo, manual backup mandatory.** PyMOL Open Source ships a no-op `undocontext` stub, so every destructive op is bracketed by `backup.snapshot` (before) and `backup.discard` (happy) / `backup.restore` (failure).
- **Hiders mutate the SAME object** (in-place `cmd.pseudoatom(object=existing)`), tagged with the sentinel `segi='GAME'` + `b=-999`. Cleanup/reload identify hiders by sentinel ONLY.
- **Modeless main dialog** so the 3D viewer stays interactive for the click-to-find loop. Modal `.exec_()` is allowed ONLY on child dialogs (QMessageBox/QFileDialog/QDialog), NEVER on `PluginDialog`.
- **Composition + DI over inheritance.** No strategy-class hierarchy; per-rep divergence is dispatched inside `mutation.insert_hider_for_rep`. `GameTab` duck-types the controller (no `game.py` import) to avoid a circular import.

## Layers

**Pure data layer (WSL-unit-testable, stdlib only — NO `from pymol`, NO Qt):**
- Purpose: hold the game's data schema, the hider registry, geometry decisions, and persistence sidecar assembly. Everything here runs under `python3.6 -m unittest` in WSL without PyMOL installed.
- Location: `biochemeleon/setup_state.py`, `biochemeleon/registry.py`, `biochemeleon/generators.py`, `biochemeleon/persistence.py`
- Contains: dataclasses/namedtuples (`HiderRecord`), `OrderedDict`-backed registries, pure geometry/selection functions, JSON/zip sidecar builders/parsers.
- Depends on: stdlib + each other (only downward: `registry`→`setup_state`, `persistence`→`registry`+`setup_state`). `generators` imports nothing from siblings.
- Used by: every layer above.

**cmd-coupled bridge layer (standalone — `from pymol import cmd`, no cross-bridge imports):**
- Purpose: the ONLY place that calls `cmd.*` for mutation, backup, demo loading, and click handling. Each bridge module is independent (does not import sibling bridges) to keep the surface minimal and headless-smoke-testable.
- Location: `biochemeleon/backup.py`, `biochemeleon/mutation.py`, `biochemeleon/demos.py`, `biochemeleon/wizard.py`
- Contains: snapshot/restore/verify lifecycle, hider insertion + sentinel + cleanup, demo fetch/load + WSL→Windows path, the `PickWizard` click callback.
- Depends on: `pymol.cmd` (and `pymol.wizard` for `wizard.py`); `demos.py` additionally imports `from .setup_state import ...` (bridge→pure is allowed).
- Used by: `game.py` (orchestrator) and `__init__.py` (composition root).

**Orchestrator layer (cmd composition root):**
- Purpose: wire backup + mutation + registry into a single round lifecycle (`start` → play → `cleanup`/`abort_on_error`). Holds the registry and per-round state; emits GUI callbacks.
- Location: `biochemeleon/game.py`
- Contains: `GameController` class — `start`, `on_pick`, `hint`, `reveal_one`/`reveal_all`, `win`, `mark_found`, `cleanup`, `abort_on_error`, `reconstruct_registry`, `import_state`.
- Depends on: `from pymol import cmd` + `from . import backup, mutation, registry`. Injects the iterate fn into the pure registry.
- Used by: `__init__.py` (constructs and holds `self._controller`), `gui_game.py` (duck-typed, via `start_countdown(controller)`), `smoke/phase*_smoke.py`.

**GUI layer (Qt + cmd — top of stack):**
- Purpose: Qt widgets only. Holds NO game logic and calls NO `cmd` directly for mutation; routes button signals to controller methods. `gui_game.py` is Qt-only at module level (cmd imported lazily inside methods) and duck-types the controller.
- Location: `biochemeleon/gui_setup.py` (SetupTab + PyMOLObjectCombo), `biochemeleon/gui_game.py` (GameTab)
- Contains: QWidget subclasses, QTabWidget children, QTimer (1 Hz main-thread timer — NEVER `threading.Thread`), modal child dialogs.
- Depends on: `from pymol.Qt import QtCore, QtGui, QtWidgets` (NEVER raw `PyQt5`), `from .setup_state import ...`; `gui_setup.py` also `from .demos import ...` and `from pymol import cmd`.
- Used by: `__init__.py` (lazy-imports `SetupTab`/`GameTab` inside `PluginDialog.__init__`).

**Composition root / entry (Qt + cmd + lazy-imports everything):**
- Purpose: the PyMOL plugin entry point (`__init_plugin__`), the singleton `PluginDialog`, and ALL button→controller wiring. This is where the GUI, the orchestrator, the bridges, and the pure layer are knitted together.
- Location: `biochemeleon/__init__.py`
- Contains: `__init_plugin__`, `run_plugin_gui`, `PluginDialog` (with `_on_start`/`_on_export`/`_on_import`/`_on_save`/`_on_cleanup`/`_on_restart`/`_show_help`/`_resolve_large_demo` + `HELP_HTML`).
- Depends on: `from pymol.Qt import ...` + `from pymol import cmd` at module level; lazy-imports `gui_setup`, `gui_game`, `demos`, `generators`, `game`, `wizard`, `persistence`, `mutation` INSIDE methods (avoids pulling `pymol.wizard`/heavy modules at plugin load).
- Used by: the PyMOL plugin loader (calls `__init_plugin__` once at startup).

## Data Flow

**A full game round (Start → win → cleanup):**

1. PyMOL loader calls `__init_plugin__(app=None)` → registers `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` (`biochemeleon/__init__.py:129`).
2. User opens the menu → `run_plugin_gui()` lazily builds the singleton `PluginDialog` and calls `dialog.show()` (MODELESS) (`biochemeleon/__init__.py:141`).
3. User configures the Setup tab → clicks Start → `PluginDialog._on_start` → `_prepare_and_start(state)` resolves the target (loaded object / PDB fetch / bundled or fetched demo) (`biochemeleon/__init__.py:242`).
4. `_continue_after_large_demo_fetch` calls `cmd.get_extent`, then pure `generators.generate_*` to build `hider_specs` (a list of `(payload, rep)` tuples) (`biochemeleon/__init__.py:348`).
5. `GameController(target_obj).start(hider_specs)` (`biochemeleon/game.py:48`):
   - `backup.snapshot(target)` — deep-copy BEFORE any mutation (no undo).
   - For each `(payload, rep)`: `mutation.insert_hider_for_rep(...)` inserts a pseudoatom INTO the existing object (sentinel `segi='GAME'`+`b=-999`), then `cmd.identify(mode=0)` returns the stable `aid`.
   - `registry.register(object=target, id=aid, rep=rep, **extra)` — keyed by `(object, id)`.
6. `cmd.show(rep, "obj and segi GAME")` → switch to Game tab → `game_tab.start_countdown(controller)` → 3-2-1 QTimer chain → `_begin_play` lazily imports `PickWizard`, activates it, registers `set_callbacks`, starts the 1 Hz QTimer.
7. **Click-to-find:** user clicks → PyMOL routes to `PickWizard.do_select`/`do_pick` (builds `pk1`, reads `(model, ID, alt, resv)`) → `GameController.on_pick(aid, alt, resv)` (`biochemeleon/game.py:118`).
8. `on_pick`: `registry.get(id)` anchor lookup; if None + resv: `get_altconf_by_resv(resv)` (Phase 11 alt-conf). If hider + hidden → `_mark_found` → `cmd.color(_found_color, ...)` + status='found' → callbacks (`on_log`, `on_remaining_changed`) → if remaining==0: `win()`.
9. `win()` → stop timer, deactivate wizard, `on_win(elapsed)` → GUI `_finish_win` modal QMessageBox → `_show_all_hiders_for_debrief` (fragment-aware `cmd.show`) → `_finish_debrief` → cleanup gate (`biochemeleon/game.py:215`, `biochemeleon/gui_game.py`).
10. `cleanup` → `mutation.cleanup_hiders(target)` (sentinel `segi GAME` remove) → `backup.verify_intact` → `backup.discard`. Failure path: `abort_on_error` → `backup.restore` (delete+create two-step) → `backup.discard` (`biochemeleon/game.py:369`).

**Persistence flow (Phase 8 save/import):**
- Save: `persistence.build_bcm_dict(registry, ...)` (pure) → `cmd.save` of `.pse` (cmd, in GUI handler) → `persistence.write_bcmz` zips `.pse`+`.bcm` into `.bcmz`.
- Import: `persistence.read_bcmz` extracts `.pse`+`.bcm` → `cmd.load` (.pse) → `GameController.import_state(bcm_dict)` → `registry.reconcile_with_bcm` (sentinel rebuild vs sidecar, returns `ReconcileMismatches`) → `persistence.apply_bcm_dict`.

**State Management:**
- **Game registry:** `HiderRegistry` (pure `OrderedDict`, keyed by `(object, int(id))`) is the single source of truth for inserted hiders. Reset fresh per round in `start()`.
- **Per-round orchestrator state:** `GameController` holds `_backup_name`, `_started`, `_start_time`, `_wizard`, `_reveal_count`/`_hint_count`, `_found_color`, `_is_imported`/`_imported_bcm`.
- **GUI state:** `PluginDialog` holds `self._controller` (active GameController) and `_pending_large_demo`/`_pending_large_demo_state` (async fetch). The active controller is held across the round so Restart/Cleanup can reach it.
- **PyMOL session:** the `.pse` file holds the hider atoms (with the `segi='GAME'`+`b=-999` sentinel); `.bcm` JSON sidecar holds the registry + setup params + timer (the sentinel carries NO rep, so `reconstruct_from_sentinels` sets `rep=None` and the `.bcm` sidecar reconciles rep).

## Key Abstractions

**HiderRecord + HiderRegistry:**
- Purpose: pure data container + the source of truth for every inserted hider, keyed by the stable `(object, atom_id)` tuple.
- Examples: `biochemeleon/registry.py:56` (`HiderRecord`), `biochemeleon/registry.py:164` (`HiderRegistry`).
- Pattern: `OrderedDict`-backed CRUD (`register`/`get`/`all`/`remove`) + queries (`by_rep`/`counts_by_rep`/`remaining_by_rep`) + status (`mark_found`) + serialization (`to_dict`/`from_dict`) + sentinel reconstruction via DI (`reconstruct_from_sentinels`). Module-level helpers `build_found_selection`/`group_found_by_rep` (`registry.py:515`/`537`).

**GameController (composition root of the cmd layer):**
- Purpose: orchestrate one round — snapshot → insert loop → register → (play: on_pick/hint/reveal) → cleanup/abort. Wires `backup`+`mutation`+`registry` and emits GUI callbacks.
- Examples: `biochemeleon/game.py:15`.
- Pattern: thin orchestrator; per-rep divergence is delegated to `mutation.insert_hider_for_rep` (dispatcher), NOT to a strategy-class hierarchy. `import_state` + `reconstruct_registry` use DI to keep the registry pure.

**PickWizard (click→on_pick bridge):**
- Purpose: subclass `pymol.wizard.Wizard` to receive atom picks from the OpenGL viewer and forward the stable atom id to `GameController.on_pick`.
- Examples: `biochemeleon/wizard.py:34`.
- Pattern: overrides `do_pick`/`do_select` (canonical select→pick map from `measurement` wizard); reads `(model, ID, alt, resv)` from `pk1`; caches and restores the user's prior wizard on activate/deactivate.

**Hider sentinel:**
- Purpose: the stable identifier for hiders across cleanup and `.pse` reload (since `index` shifts on add/remove but `id` is stable).
- Examples: set in `biochemeleon/mutation.py` (`insert_hider` sets `segi='GAME'`+`b=-999`); read by `fetch_all_hider_ids` (selector `segi GAME and b < 0` — comparison, NOT exact `b -999` which is malformed); cleanup by `segi GAME` ALONE.
- Pattern: sentinel-only identification. NEVER by `resi`/`chain`/per-object `index`. `reconstruct_from_sentinels` rebuilds the registry from these after a `.pse` reload (with `rep=None`).

**Backup snapshot:**
- Purpose: the ONLY recovery mechanism (no undo in PyMOL Open Source).
- Examples: `biochemeleon/backup.py` — `BACKUP_PREFIX='_bchm_backup'` (underscore-hidden from `public_objects`); `snapshot`/`restore`/`discard`/`verify_intact`.
- Pattern: `snapshot` before any mutation; `verify_intact` (count + `(resn,resi,name,chain,segi)` identity multiset — NO coords, `cmd.iterate` has none); restore = `cmd.delete(target)` + `cmd.create(target, backup)` two-step (NEVER single-call `cmd.create(existing, backup)`).

**PluginDialog (GUI composition root):**
- Purpose: the singleton modeless `QDialog` holding the `QTabWidget` (Setup + Game status) and wiring every button to the active `GameController`.
- Examples: `biochemeleon/__init__.py:160`.
- Pattern: module-level `dialog = None` (GC prevention); `run_plugin_gui` lazily builds + `dialog.show()` (NEVER `.exec_()`); lazy-imports tab classes + controllers inside methods; holds `self._controller` across the round.

## Entry Points

**`__init_plugin__(app=None)`:**
- Location: `biochemeleon/__init__.py:129`
- Triggers: PyMOL plugin loader calls it once at startup (or on manual load via the Plugin Manager).
- Responsibilities: locally imports `addmenuitemqt` (clean failure if Qt unavailable) and registers the `bioCHEMeleon` Plugins-menu item pointing at `run_plugin_gui`. Does NOT build the dialog.

**`run_plugin_gui()`:**
- Location: `biochemeleon/__init__.py:141`
- Triggers: user clicks the Plugins → bioCHEMeleon menu item.
- Responsibilities: lazily creates the singleton `PluginDialog` (GC-protected by module-level `dialog`) and calls `dialog.show()`/`raise_()`/`activateWindow()`. Modeless — the 3D viewer stays interactive.

**`GameController.start(hider_specs)`:**
- Location: `biochemeleon/game.py:48`
- Triggers: `PluginDialog._on_start` → `_continue_after_large_demo_fetch` (after target resolution + spec building).
- Responsibilities: snapshot → insert loop → register → set `_started`. Returns the backup name on success, `None` on failure.

**`GameController.on_pick(picked_id, alt='', resv=None)`:**
- Location: `biochemeleon/game.py:118`
- Triggers: `PickWizard.do_pick`/`do_select` (PyMOL click callback).
- Responsibilities: registry lookup (anchor + alt-conf resv gate) → score → `_mark_found` → callbacks → `win()` if last.

## Error Handling

**Strategy:** Backup-restore is the ONLY recovery mechanism (PyMOL Open Source `undocontext` is a no-op stub). Every destructive op is bracketed by snapshot (before) and discard/restore (after).

**Patterns:**
- **Snapshot-before-mutation invariant:** `GameController.start` calls `backup.snapshot` BEFORE the insert loop; `backup.snapshot` MUST precede any `mutation.insert_hider`.
- **Two-step restore:** `backup.restore` = `cmd.delete(target)` + `cmd.create(target, backup)` (NEVER single-call `cmd.create(existing, backup)` — merge-vs-replace unverified). `GameController.abort_on_error` uses this on the failure path.
- **verify_intact proof:** `backup.verify_intact` returns the bool that gates `cleanup`'s success and `abort_on_error`'s restore. Do NOT re-call `verify_intact` after `cleanup`/`abort_on_error` discarded the backup — both already run verify+discard internally; assert the orchestrator's RETURN value.
- **Idempotent when not started:** `cleanup()` and `abort_on_error()` return `True` early if `not _started` (defensive for UI double-clicks).
- **Lazy local imports** inside `__init_plugin__`/`_begin_play`/GUI handlers so a failing sibling module doesn't crash plugin load; Qt-unavailable raises are caught by the plugin loader.
- **GUI failure UX:** every `_on_*` failure path shows a `QMessageBox.warning` (modal child — `.exec_()` allowed on child dialogs only). Async large-demo fetch failures are owned by the `_resolve_large_demo` drain (QMessageBox on 'error', silent on 'canceled').
- **Imported-game degradation:** `reconcile_with_bcm` returns `ReconcileMismatches`; the registry stays usable (degraded = playable) regardless; `rep=None` records are skipped by `counts_by_rep`/`remaining_by_rep`.

## Cross-Cutting Concerns

**Logging:** No logging framework. Player-facing events flow through `GameController.set_callbacks` → `on_log(msg)` → `GameTab`'s append-only `QTextEdit` rolling log (`biochemeleon/gui_game.py`). Diagnostic output goes to stdout in `smoke/phase*_smoke.py` only.

**Validation:**
- **Pure layer:** `setup_state.validate_state` + `hider_count_cap` (pure, unit-tested) — clamps per-rep sums, validates PDB codes, validates the 11-key DEFAULTS schema.
- **GUI layer:** `SetupTab.collect_state`/`apply_state` round-trip; `_validate_pdb_code` on pool entries; `QMessageBox.warning` on every failure path in `_prepare_and_start`.
- **PyMOL selectors:** b-factor sentinel SELECTOR is `b < 0` (comparison), NEVER `b -999` (malformed, silently matches nothing); cleanup uses `segi GAME` ALONE.

**Authentication:** Not applicable — single-process desktop plugin, no network auth. Large-demo fetch (`demos.py`) uses stdlib `urllib`+`ssl` against RCSB/MemProtMD/SASBDB; no API keys.

**Path hygiene (WSL/Windows split):** `demos.to_windows_path()` converts `/mnt/c/...` → `C:\...` ONLY for WSL mount paths (returns others unchanged); Windows PyMOL cannot resolve WSL paths. `wsl2win_cp.sh` stages `biochemeleon/` → `tmp/bioCHEMeleon/` for the Windows-facing path.

**Purity gates (enforced in AGENTS.md and verified by grep):**
- Pitfall-1 gate: ZERO matches for `Tkinter`/`Pmw`/`from PyQt5`/`import PyQt5`/`mainloop`/`Toplevel`/`grab_set` across `biochemeleon/` (use `from pymol.Qt import QtWidgets` only).
- exec_ gate: every `\.exec_\(\)` hit must be on a child `QFileDialog`/`QMessageBox`/`QDialog` (`gui_game.py` `_finish_win`/`_finish_debrief`, `__init__.py` `_show_help`), NEVER on the main `PluginDialog` (which uses `dialog.show()`).

**Testing boundary:** pure layer (4 modules) → `python3.6 -m unittest tests.test_*` in WSL (125 tests, stubs `pymol`/`pymol.Qt` via `sys.modules`). cmd/Qt layer → `smoke/phase*_smoke.py` run headlessly via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq` (pure `pymol.cmd.*`, NO Qt). GUI/Qt interactive paths → human-verify checkpoints in a real Windows PyMOL session.

---

*Architecture analysis: 2026-08-18*
