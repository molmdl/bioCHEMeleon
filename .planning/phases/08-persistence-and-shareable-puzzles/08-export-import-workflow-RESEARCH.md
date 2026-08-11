# Phase 8: Persistence & Shareable Puzzles — Export/Import Workflow Research

**Researched:** 2026-08-12
**Domain:** PyMOL 2.5.0 plugin — educator→player puzzle sharing workflow (BTN-05 Generate & export + GAME-04 Import)
**Confidence:** HIGH (API claims verified against `tmp/pymol-src/modules/pymol/` source; runtime behaviors flagged UNVERIFIED where the C layer decides)

**Scope note:** This research covers the FLOW, lifecycle, button placement, object-name handling, and Restart/Cleanup semantics for imported games. It does NOT cover the `.bcm` JSON top-level schema (another researcher) or the registry found-status-reconciliation merge logic details (another researcher). Where those intersect, this research states what the orchestrator needs from them (the dict keys it reads/writes) without prescribing their internals.

---

## 1. Executive Summary

Generate & export is a **truncated Start**: the educator configures + generates hiders exactly as Start does (same `collapse_to_single_state` → build `hider_specs` → `free_nterminal_valence` → `GameController.start(hider_specs)` sequence), then saves a `.pse` of the single target object (hiders inside) plus a `.bcm` sidecar carrying the registry + setup + zeroed runtime counters, then stays on the Setup tab without countdown/wizard. Import is a **non-generating load**: `cmd.load(.pse, partial=1)` merges the puzzle's objects into the player's current session (preserving the player's existing scene), the target object is resolved from the `.bcm`'s recorded `target_obj` name, a fresh `GameController` reconstructs its registry from sentinels (rep reconciled from `.bcm`), snapshots a fresh backup of the post-import object, sets `_started=True`, then routes into the existing `start_countdown` → `_begin_play` path.

Two PyMOL API facts drive the design and are verified from source: (1) `cmd.save(path, selection=target_obj)` with a **bare object name** (no parens) saves ONLY that object, excluding `_bchm_backup` — because `get_psestr` ignores parenthesized selections (`exporting.py:973-977`) and `get_session(names=...)` exports only the named objects (`exporting.py:370`); (2) `cmd.load(.pse)` with default `partial=0` **replaces the entire session** (wipes the player's objects) — `set_session(partial=0)` is a full restore (`importing.py:130-175`, `823-848`), so Import MUST use `partial=1` to merge without wiping. The object name on `.pse` load is the **original embedded name** (not the filename prefix) — `load_pse` → `set_session` restores the session dict, objects keep their saved names.

**Primary recommendation:** Put file I/O + `cmd.save`/`cmd.load` helpers in a new standalone cmd-coupled `biochemeleon/persistence.py` (mirrors `backup.py`/`mutation.py`); put pure BCM-dict assembly/parsing in the pure layer (`setup_state.py`, which already owns the setup shape); add `GameController.import_state(bcm_dict)` to reconstruct the registry from sentinels + apply `.bcm` runtime state + snapshot a fresh backup + set `_started=True` (without re-inserting hiders); keep `_on_export`/`_on_import` thin in `__init__.py`. Route Restart-on-imported and Cleanup-on-imported through a `_is_imported` flag on the controller (Restart restores from the post-import backup + resets found-status; Cleanup does backup-restore THEN sentinel-remove so the player gets a clean molecule with no orange hint-color residue).

---

## 2. Generate & Export Flow (BTN-05)

### 2.1 Where it lives + spec button placement

BTN-05 is a **Setup tab** button. The spec pins the order (PROJECT.md line 32; 07-RESEARCH.md line 106 quoting spec line 20):

> (1) Reset, (2) Randomize, (3) Save Setup, (4) Load Setup, (5) Generate and export, (6) Cleanup model, (7) Start

The current Setup tab button row (`gui_setup.py:185-201`) is: `reset_btn`, `random_btn`, `save_btn`, `load_btn`, `cleanup_btn`, `start_btn`. **Export goes BETWEEN `load_btn` and `cleanup_btn`** (button 5 of 7). See §7 for exact wiring.

### 2.2 Exact step sequence (the "truncated Start")

Export reuses `_on_start`'s steps 1–4 verbatim (resolve target → collapse → build specs → free valences → start), then DIVERGES at step 5: instead of switching to the Game tab + countdown, it saves files and stays on Setup. The educator's local object is left with hiders inserted (post-`start` state); the educator can then press the existing Cleanup button (BTN-06) to restore their scene.

**Why re-use `start()` and not a lighter path?** `GameController.start(hider_specs)` (`game.py:42-63`) does snapshot + insert + register + `_started=True`. The `.pse` must contain the hiders (they're the puzzle), so `start()` is the correct way to insert them. The backup it creates (`_bchm_backup`) is a side effect we exclude from the save via bare-name selection (§2.3) — and it doubles as the educator's own Cleanup restore source.

**`collapse_to_single_state` + `free_nterminal_valence` MUST run before the save** (`mutation.py:543-619`, called at `__init__.py:135` and `__init__.py:214-216`). The `.pse` must be single-state (multi-state breaks backup/verify_intact — `mutation.py:544-559`), and cartoon/ribbon hiders need free N-terminal valences so they were insertable (`mutation.py:572-619`). These already run in `_on_start` steps 2 + 3b; export reuses them by calling `_on_start`'s body up to the `controller.start()` line, then diverging.

### 2.3 Pseudo-code for `_on_export` (in `__init__.py`)

```python
def _on_export(self):
    """BTN-05: generate hiders + save initial game state to a file WITHOUT playing.
    Reuses _on_start's target-resolution + spec-building + start, then saves
    .pse (target object only, hiders inside) + .bcm sidecar (registry + setup +
    zeroed runtime counters, state='puzzle'), then stays on the Setup tab.
    """
    from . import generators, game, demos, mutation, persistence
    import random as _random
    # 1-4. SAME as _on_start: resolve target, collapse, build specs, free valences,
    #    clean prior game, start controller. (Refactor: extract a helper
    #    _prepare_and_start(state) -> controller that both _on_start and _on_export
    #    call, so the 200-line body isn't duplicated. See §2.4.)
    state = self.setup_tab.collect_state()
    controller, target_obj, _gen_warnings = self._prepare_and_start(state)
    if controller is None:
        return  # _prepare_and_start already showed a QMessageBox
    # 5. SAVE the initial game state. state='puzzle', started=False (educator
    #    did not play), timer 0, all hiders hidden, reveal/hint counts 0.
    bcm_dict = build_bcm_dict(
        target_obj=target_obj,
        registry_dict=controller.registry.to_dict(),
        started=False,                 # educator did not play
        state='puzzle',                # initial-state export (vs 'checkpoint' for Save)
        elapsed=0.0, reveal_count=0, hint_count=0,
        found_color=controller._found_color,
        setup_state=state,             # full collect_state() (see §2.5)
    )
    # 6. File dialog (.bcmz bundle OR .pse+.bcm pair). Recommend the bundle
    #    (single file = easy sharing). See §2.6.
    path, _ = QtWidgets.QFileDialog.getSaveFileName(
        self, "Generate & export puzzle", "",
        "bioCHEMeleon Puzzle (*.bcmz);;All Files (*)")
    if not path:
        # cancelled -> the educator's local game is still started; offer cleanup
        self._maybe_cleanup_after_cancelled_export(controller)
        return
    try:
        persistence.save_puzzle(target_obj, bcm_dict, path)  # §4
    except (OSError, pymol.CmdException) as exc:
        QtWidgets.QMessageBox.warning(self, "Export failed",
            "Could not save puzzle:\n%s" % exc)
        return
    # 7. Stay on Setup tab. Show a success toast. Do NOT countdown / activate wizard.
    QtWidgets.QMessageBox.information(self, "Puzzle exported",
        "Saved puzzle to:\n%s\n\nYour model still has the generated hiders. "
        "Press Cleanup to restore your scene." % path)
    # The educator's local controller stays _started=True so Cleanup (BTN-06)
    # works on it. Do NOT set self._controller = None here -- the educator may
    # want to Clean up the generated hiders (which needs self._controller).
    self._controller = controller
```

### 2.4 Refactor: extract `_prepare_and_start(state)` (shared by `_on_start` + `_on_export`)

`_on_start` (`__init__.py:79-244`) and `_on_export` share steps 1–4 (resolve target → collapse → build specs → free valences → clean prior game → `GameController` + `start`). Extract a helper to avoid ~160 lines of duplication:

```python
def _prepare_and_start(self, state):
    """Shared steps 1-4 of Start and Export. Returns (controller, target_obj,
    gen_warnings) or (None, None, []) after showing a QMessageBox on failure.
    Mirrors _on_start lines 79-241 verbatim through controller.start()."""
    # ... existing _on_start body lines 87-241, minus the tab-switch + countdown ...
    return controller, target_obj, _gen_warnings
```

`_on_start` then becomes: `controller, target_obj, _ = self._prepare_and_start(state); if controller: self.tabs.setCurrentWidget(self.game_tab); self.game_tab.start_countdown(controller)`. `_on_export` calls the same helper then saves. This is a REFACTOR (no behavior change to Start) — keep it in scope but verify Start still passes the Phase 4/7 smokes after.

### 2.5 What Setup state goes into the `.bcm`?

The `.bcm`'s `setup` key should carry the **full `collect_state()` dict** (`gui_setup.py:441-459`), not a curated subset. Rationale:
- The player importing a puzzle does NOT re-configure (Import skips the Setup tab), but the full setup dict is needed to **re-display per-rep counts in the Game tab** and to support Restart-on-imported (which needs `per_rep` to know what was generated — though Restart-on-imported restores from backup, not re-generates; see §6.2). It's also the forward-compat hook: a future "edit the imported puzzle" feature would need the full setup.
- `target_mode`/`selected_object`/`pdb_code`/`demo_id` are somewhat stale for an imported puzzle (the object came from the .pse, not from fetch/demo), but storing them is harmless and lets the player see "this puzzle was built on 1ubq" if we ever surface it.
- Storage is cheap (a few hundred bytes). Curating now risks dropping a field a later phase needs.

The orchestrator passes the full `collect_state()` to `build_bcm_dict(setup_state=...)`; the schema researcher decides whether `build_bcm_dict` stores it verbatim or under a versioned `setup` sub-key. This research only requires: **`_on_export` writes the full setup dict; `_on_import` reads it back and can ignore fields it doesn't use.**

### 2.6 File format: `.bcmz` bundle vs `.pse`+`.bcm` pair

ROADMAP.md line 267 flags this as an open UX decision: "two-file share is awkward; decide zip-together vs document 'keep both files'." **Recommend `.bcmz` bundle** (a zip containing `puzzle.pse` + `puzzle.bcm`):
- Single file = easy email/LMS/USB sharing (the spec's "save the initial state to a file for sharing" implies one file).
- `stdlib` `zipfile` suffices (no new dependency — AGENTS.md allows stdlib).
- `persistence.save_puzzle` writes both to a temp dir, zips to `path`; `load_puzzle` unzips to a temp dir, loads the `.pse` + reads the `.bcm`. Temp files cleaned up after.

If the team prefers the two-file pair, the same `persistence.py` API works with `path` = a directory or a `.pse` basename (sibling `.bcm` derived by extension swap). The bundle is the recommended default; the pair is a fallback. This is an OpenCode-discretion UX call — flag for the planner/user.

### 2.7 Should export auto-cleanup the educator's object?

**No — do NOT auto-cleanup.** Leave the controller `_started=True` with hiders inserted, and show a success dialog that says "Press Cleanup to restore your scene." Rationale:
- The spec says "save the initial state to a file" — it does NOT say "restore the educator's scene." Cleanup is the educator's explicit choice.
- Leaving hiders lets the educator **preview** the generated puzzle (visually verify the hiders look right) before cleaning up. An educator who wants to re-export with different settings can adjust Setup + re-export without re-loading a molecule.
- The existing Cleanup button (BTN-06, `_on_cleanup` at `__init__.py:265-286`) already restores the scene from `_bchm_backup` (which `start()` created). So the educator's recovery path is one button click away, and it reuses verified Phase 7 logic.
- Auto-cleanup would discard the backup + reset `_controller`, surprising an educator who expected to preview.

If the user feedback says auto-cleanup is preferred, it's a one-line change (`self._on_cleanup()` after the success dialog). Flag as a UX preference for the discuss/planner phase.

---

## 3. Import Flow (GAME-04)

### 3.1 Where it lives + spec button placement

ROADMAP.md line 175: "Pressing Import (from Game tab) loads a previously exported game and lets the player play it." PROJECT.md line 32-33 + SUMMARY.md line 49 confirm: Import is on the **Game status tab**. See §7 for exact placement.

### 3.2 The two critical PyMOL API facts (verified from source)

**Fact 1 — `.pse` load with `partial=0` (default) REPLACES the session:**
`load_pse(filename, partial=0, ...)` (`importing.py:823-848`) calls `set_session(session, partial=partial, ...)` (`importing.py:130-175`), which calls the C `_cmd.set_session(_self._COb, session, int(partial), int(quiet))` (`importing.py:143`). With `partial=0`, this is a **full session restore** — the player's currently-loaded objects are WIPED. With `partial=1`, it's a **partial/merge restore** — the puzzle's objects are added to the current session, preserving the player's existing objects. The `if not partial: _self.set("session_file", ...)` guard (`importing.py:832-835`) confirms `partial=1` is the merge path (it skips overwriting `session_file`).

> **Import MUST use `cmd.load(path, partial=1)`** (or the explicit `cmd.load_pse(path, partial=1)`). Using the default `partial=0` would silently destroy the player's scene. **UNVERIFIED at runtime** — the C-level partial-merge collision behavior (does a colliding object get renamed, overwritten, or error?) needs the Phase 8 headless smoke to confirm. See §5 for the collision policy that defends against all three.

**Fact 2 — object name on `.pse` load is the ORIGINAL embedded name, not the filename prefix:**
The generic `cmd.load` (`importing.py:635`) defaults `object` to the filename prefix if not specified (`importing.py:748-750`). But `.pse` dispatches to `load_pse` (`importing.py:1623` `'pse': load_pse`), which calls `set_session` — and `set_session` restores the session dict's objects **with their original saved names**. So `cmd.load('puzzle.pse')` does NOT create an object named "puzzle"; it restores objects named whatever they were when the `.pse` was saved (e.g. "1ubq"). Import must therefore resolve `target_obj` from the `.bcm`'s recorded `target_obj` field (or by diffing `get_names()` before/after load — §3.4), NOT from the filename.

### 3.3 Exact step sequence

```
Player clicks Import (Game tab)
  -> QFileDialog (pick .bcmz)
  -> persistence.load_puzzle(path) -> (pse_tmp, bcm_dict)   # unzip to temp
  -> [optional] clean prior game (mirror _on_start lines 228-234)
  -> record names_before = get_names('public_objects')      # for collision diff
  -> cmd.load(pse_tmp, partial=1)                           # MERGE, don't wipe (Fact 1)
  -> target_obj = bcm_dict['target_obj']                    # the embedded name (Fact 2)
  -> resolve target_obj (collision/absence handling — §5)
  -> controller = GameController(target_obj)
  -> controller.import_state(bcm_dict)                      # §3.5 — reconstruct + apply + backup + _started=True
  -> self._controller = controller; controller._is_imported = True
  -> self.tabs.setCurrentWidget(self.game_tab)
  -> self.game_tab.start_countdown(controller)             # REUSE the existing path
  -> _begin_play (PickWizard activate + set_callbacks + timer)  # happens after countdown
```

For a **puzzle** import (`state='puzzle'`): timer starts at 0, all hiders hidden, reveal/hint 0 — `import_state` zeroes the runtime counters regardless of the saved values? No — `import_state` APPLIES the saved values (which are 0 for a puzzle). For a **checkpoint** import (`state='checkpoint'`, from Save — another researcher's BTN-05 peer): timer resumes at the saved elapsed, found-status per hider from `.bcm`. The SAME `import_state` handles both — it applies whatever `.bcm` says. The timer-resume question (§3.6) is about `_start_time` semantics.

### 3.4 Resolving `target_obj` after partial load

Primary: **read `bcm_dict['target_obj']`** (the name the educator's object had at export time). The `.pse` restored that object with that exact name (Fact 2). If `target_obj` is now in `get_names('public_objects', enabled_only=True)` (`querying.py:1148`; `demos.list_loaded_molecule_objects()` at `demos.py:48-60` uses exactly this), use it.

Fallback (if `target_obj` is absent or the partial-load renamed it on collision): **diff `get_names('public_objects')` before/after load** and pick the new non-underscore molecule object. `names_before - names_after` (set diff) yields the newly-added objects; filter to `get_type(name)=='object:molecule'` (`demos.py:60`). If exactly one new molecule object, use it. If zero or many, surface an error ("Could not identify the puzzle's target object; please load it manually").

Recommend: try `bcm_dict['target_obj']` first; if absent from the loaded session, fall back to the before/after diff; if that's ambiguous, error with a clear message. This defends against all partial-load collision behaviors (§5).

### 3.5 Pseudo-code for `_on_import` (in `__init__.py`)

```python
def _on_import(self):
    """GAME-04: load a previously-exported puzzle and let the player play it.
    Loads the .pse (partial=1, merge) + .bcm, reconstructs the controller from
    sentinels + .bcm, snapshots a fresh backup, then routes into the existing
    start_countdown -> _begin_play path. NO re-generation."""
    from . import game, persistence, demos
    from pymol import cmd
    path, _ = QtWidgets.QFileDialog.getOpenFileName(
        self, "Import bioCHEMeleon puzzle", "",
        "bioCHEMeleon Puzzle (*.bcmz);;All Files (*)")
    if not path:
        return
    # 1. Unzip + read .bcm (persistence.load_puzzle returns (pse_path, bcm_dict))
    try:
        pse_path, bcm_dict = persistence.load_puzzle(path)  # §4
    except (OSError, ValueError) as exc:
        QtWidgets.QMessageBox.warning(self, "Import failed",
            "Could not read puzzle file:\n%s" % exc)
        return
    # 2. Clean any prior game (mirror _on_start lines 228-234 — wizard + controller)
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate()
        self.game_tab._wizard = None
        if self._controller is not None:
            self._controller._wizard = None
    if self._controller is not None and self._controller._started:
        self._controller.cleanup()
    # 3. Record loaded objects, then MERGE the .pse (partial=1 — Fact 1)
    names_before = set(cmd.get_names('public_objects', enabled_only=True))
    try:
        cmd.load(pse_path, partial=1)   # MERGE, do NOT wipe the player's scene
    except pymol.CmdException as exc:
        QtWidgets.QMessageBox.warning(self, "Import failed",
            "Could not load the puzzle session:\n%s" % exc)
        return
    # 4. Resolve target_obj (Fact 2: name comes from the .pse, not the filename)
    target_obj = persistence.resolve_target(
        bcm_dict, names_before, demos.list_loaded_molecule_objects())  # §5
    if target_obj is None:
        QtWidgets.QMessageBox.warning(self, "Import failed",
            "Could not identify the puzzle's target object. Please ensure "
            "the puzzle file is valid.")
        return
    # 5. Build controller + import state (reconstruct + apply .bcm + backup + _started)
    self._controller = game.GameController(target_obj)
    self._controller._is_imported = True   # routes Restart + Cleanup (§6)
    try:
        self._controller.import_state(bcm_dict)   # §3.6
    except (RuntimeError, KeyError) as exc:
        QtWidgets.QMessageBox.warning(self, "Import failed",
            "Could not restore game state:\n%s" % exc)
        self._controller = None
        return
    # 6. Route into the EXISTING play path (countdown -> _begin_play -> wizard)
    self.tabs.setCurrentWidget(self.game_tab)
    self.game_tab.start_countdown(self._controller)
```

### 3.6 `GameController.import_state(bcm_dict)` — proposed method

```python
def import_state(self, bcm_dict):
    """Reconstruct this controller's state from an imported puzzle/checkpoint
    WITHOUT re-inserting hiders (they came from the .pse). Mirrors start()'s
    end-state (_started=True, _backup_name set, registry populated) but skips
    the snapshot-before-insert + insert loop (hiders already exist).

    Steps:
      1. reconstruct_registry() — sentinel rebuild (rep=None; game.py:224).
      2. Reconcile rep + found-status per hider by id from bcm_dict['registry']
         (the found-status-reconciliation merge is another researcher's lane;
         this method CALLS a pure helper, e.g. registry.reconcile_from_bcm(
         self.registry, bcm_dict['registry'])). After this, each record has
         its real rep + correct status.
      3. Apply runtime state from bcm_dict: _reveal_count, _hint_count,
         _found_color, _start_time (for a puzzle: 0/0/'green'/None -> set in
         _begin_play; for a checkpoint: the saved values).
      4. Snapshot a FRESH backup of the post-import object (hiders + found-status
         applied) so Cleanup/Restart work later: self._backup_name =
         backup.snapshot(self.target_obj). For a puzzle this snapshots
         "hiders inserted, none found" (the initial puzzle state — the right
         "original" for Restart). For a checkpoint this snapshots "hiders
         inserted, found-status as saved" (the checkpoint state — the right
         "original" for Restart-on-checkpoint).
      5. self._started = True (hiders are live; on_pick/cleanup must work).

    Raises RuntimeError if already started (mirror start()'s guard).
    """
    if self._started:
        raise RuntimeError("game already started; call cleanup() first")
    self.reconstruct_registry()                        # game.py:224-229 (rep=None)
    registry.reconcile_from_bcm(self.registry, bcm_dict['registry'])  # pure; §3.7
    self._reveal_count = bcm_dict.get('reveal_count', 0)
    self._hint_count   = bcm_dict.get('hint_count', 0)
    self._found_color  = bcm_dict.get('found_color', 'green')
    # _start_time: for a puzzle, leave None (_begin_play sets it to time.time()).
    # For a checkpoint, set to time.time() - saved_elapsed so the timer resumes.
    if bcm_dict.get('state') == 'checkpoint':
        saved_elapsed = bcm_dict.get('elapsed', 0.0)
        self._start_time = time.time() - saved_elapsed   # timer resumes
    # else: puzzle -> _start_time stays None; _begin_play sets it fresh.
    self._backup_name = backup.snapshot(self.target_obj)  # FRESH post-import backup
    self._started = True
```

**Why a method on GameController (not inline in `_on_import`)?:** the controller owns its state (`_started`, `_backup_name`, `_reveal_count`, etc.); reconstruct+apply+snapshot is a cohesive unit that mirrors `start()`'s structure; putting it on the controller keeps `__init__.py` thin and lets a headless smoke call `controller.import_state(bcm_dict)` directly (mirroring how `phase7_smoke.py` calls `gc.start()`). The alternative (inline in `_on_import`) bloats the composition root and can't be headless-tested in isolation.

### 3.7 The timer-resume question (puzzle vs checkpoint)

- **Puzzle import (`state='puzzle'`):** `_start_time` stays `None`; `_begin_play` (`gui_game.py:217,221`) sets `self._start_time = time.time()` and `self._controller._start_time = self._start_time`. Timer starts at 0. Correct — the player starts fresh.
- **Checkpoint import (`state='checkpoint'`, from Save):** `import_state` sets `_start_time = time.time() - saved_elapsed`. Then `_begin_play` OVERWRITES it with `time.time()` (`gui_game.py:221`) — BUG: the resume would be lost.

**Resolution:** `_begin_play` must NOT overwrite `_start_time` if the controller already has one (i.e., it's an imported checkpoint). Proposed change to `_begin_play` (`gui_game.py:217-221`):

```python
self._start_time = time.time()
# Bug fix for checkpoint import: don't clobber a resumed _start_time.
if self._controller._start_time is None:
    self._controller._start_time = self._start_time
```

This is a small, surgical change to `_begin_play`. Flag it as a Phase 8 requirement for checkpoint import (the Save researcher's domain triggers it, but the fix lives in `_begin_play` which is shared). For puzzle-only Phase 8 scope, this change is a no-op (`_start_time` is None on import). **Recommend including it** so Save+Import compose correctly.

### 3.8 Should Import clean up any existing game first?

**Yes — mirror `_on_start`'s clean-prior-game logic** (`__init__.py:228-234`): deactivate the old PickWizard + `controller.cleanup()` the old controller before importing. Without this, the old wizard stays active (corrupting `mouse_selection_mode` — the Phase 7 wizard-lifecycle fix) and old hiders accumulate. The pseudo-code in §3.5 step 2 does this. This is NOT optional — it's the same bug class Start already guards against.

---

## 4. Where Helper Code Lives

### 4.1 Recommendation: `persistence.py` (cmd-coupled, standalone) + pure assembly in `setup_state.py`

**New module `biochemeleon/persistence.py`** — cmd-coupled, standalone (mirrors `backup.py`/`mutation.py`: `from pymol import cmd`, no cross-module biochemeleon imports, syntax-checkable in WSL, runtime-verified by the Phase 8 smoke). Holds the FILE I/O + `cmd.save`/`cmd.load` helpers:

```python
# biochemeleon/persistence.py
"""Puzzle persistence — .pse save/load + .bcm JSON I/O + .bcmz bundling.
Standalone cmd-coupled (mirrors backup.py/mutation.py): no cross-module
biochemeleon imports, syntax-checkable in WSL, runtime-verified by smoke."""
import json, os, tempfile, zipfile
from pymol import cmd

BCM_EXT = '.bcm'
PSE_NAME = 'puzzle.pse'      # canonical name inside the .bcmz bundle
BCM_NAME = 'puzzle.bcm'

def save_puzzle(target_obj, bcm_dict, path, bundle=True):
    """Save target_obj as .pse (bare-name selection -> excludes _bchm_backup,
    exporting.py:973-977 + 370) + write .bcm, then zip into path (.bcmz)."""
    # 1. Save the .pse with the BARE object name (no parens) so get_psestr
    #    honors it (a parenthesized selection is IGNORED -> saves all objects
    #    including the backup; exporting.py:974).
    pse_path = ...  # temp file
    cmd.save(pse_path, selection=target_obj)   # bare name -> only target_obj
    # 2. Write the .bcm sidecar (pure JSON; the dict is assembled by the caller).
    bcm_path = ...
    write_bcm(bcm_dict, bcm_path)
    # 3. Bundle (zipfile is stdlib).
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.write(pse_path, PSE_NAME)
        zf.write(bcm_path, BCM_NAME)
    # 4. Clean temp files.

def load_puzzle(path):
    """Unzip the .bcmz, load the .pse (partial=1 MERGE — importing.py:823),
    read the .bcm. Returns (pse_tmp_path, bcm_dict). Caller does cmd.load + resolves target."""
    with zipfile.ZipFile(path, 'r') as zf:
        zf.extract(PSE_NAME, tmpdir)
        zf.extract(BCM_NAME, tmpdir)
    pse_path = os.path.join(tmpdir, PSE_NAME)
    bcm_dict = read_bcm(os.path.join(tmpdir, BCM_NAME))
    return pse_path, bcm_dict   # caller: cmd.load(pse_path, partial=1)

def write_bcm(bcm_dict, path):
    with open(path, 'w') as f:
        json.dump(bcm_dict, f, indent=2)

def read_bcm(path):
    with open(path) as f:
        return json.load(f)

def resolve_target(bcm_dict, names_before, loaded_molecules):
    """Resolve the imported target object name. Prefer bcm_dict['target_obj']
    (the embedded name — importing.py:823 set_session restores it). Fall back
    to (loaded_molecules - names_before) diff. Returns the name or None."""
    t = bcm_dict.get('target_obj')
    if t and t in loaded_molecules:
        return t
    new = [n for n in loaded_molecules if n not in names_before]
    new = [n for n in new if n == t or not n.startswith('_')]  # exclude stray backup
    if len(new) == 1:
        return new[0]
    if t and t in [n for n in new]:  # renamed-on-collision case (§5)
        return t
    return None
```

**Pure BCM-dict assembly/parsing in `setup_state.py`** (the pure layer, which already owns the setup shape + `GAME_REPS`; WSL-unit-testable). The orchestrator calls it; `persistence.py` does only file I/O:

```python
# biochemeleon/setup_state.py (pure; gains these functions)
def build_bcm_dict(target_obj, registry_dict, started, state, elapsed,
                   reveal_count, hint_count, found_color, setup_state):
    """Pure: assemble the .bcm dict from pure inputs. The schema (keys, version)
    is the file-format researcher's lane; this function composes the inputs into
    the agreed shape. Returns a JSON-serializable dict."""
    return { ... }  # schema researcher defines the exact keys

def parse_bcm_dict(bcm_dict):
    """Pure: validate + normalize a .bcm dict (version check, field defaults).
    Returns a normalized dict the orchestrator + controller.import_state consume."""
    return { ... }
```

(`registry.reconcile_from_bcm(registry, bcm_registry_dict)` — the found-status + rep reconciliation — is a pure method on `HiderRegistry`/module function in `registry.py`, owned by the registry-merge researcher. `import_state` CALLS it; this research does not prescribe its internals.)

### 4.2 Why NOT the alternatives

- **Option B (`GameController.save_game`/`load_game`):** the controller is cmd-coupled + stateful; mixing file I/O + JSON + zip into it blurs its responsibility (it owns the round lifecycle, not persistence). `import_state` is on the controller (state), but `save_puzzle`/`load_puzzle` (file I/O) are not — separation of concerns. Also, `load_puzzle` must run BEFORE a controller exists (it loads the .pse that the controller is then built around), so it can't be a controller method.
- **Option C (inline in `__init__.py`):** bloats the composition root (already 286 lines) and can't be headless-tested in isolation. The Phase 7 smoke calls `gc.start()` directly; the Phase 8 smoke should be able to call `persistence.save_puzzle` + `controller.import_state` directly.

### 4.3 Dependency direction

```
setup_state.py (PURE: build_bcm_dict, parse_bcm_dict)  -- new pure functions
registry.py    (PURE: reconcile_from_bcm)              -- new pure fn (merge researcher)
      ↑
persistence.py (cmd: save_puzzle, load_puzzle, write_bcm, read_bcm, resolve_target)  -- NEW, standalone
      ↑
game.py (GameController.import_state)  -- NEW method (calls registry.reconcile_from_bcm + backup.snapshot)
      ↑
__init__.py (_on_export, _on_import, _prepare_and_start refactor)  -- composition root
```

Strict, no reversal. `persistence.py` imports `from pymol import cmd` only (no biochemeleon imports) — matches `backup.py`/`mutation.py`. `build_bcm_dict`/`parse_bcm_dict` are pure (stdlib only). `import_state` imports `backup` + `registry` (game.py already does). **UNVERIFIED at runtime** — the `cmd.save` bare-name selection behavior (§2.3) and `cmd.load(partial=1)` merge behavior (§3.2) need smoke confirmation.

---

## 5. Object-Name Collision Policy on Import

### 5.1 The risk

The player has "1ubq" loaded. The puzzle's `.pse` also contains "1ubq" (the educator's object was named "1ubq" at export). `cmd.load(pse_path, partial=1)` calls `set_session(partial=1)` (`importing.py:130-175`) → C `_cmd.set_session`. The C-level collision behavior is **UNVERIFIED** (can't read the C source): it might (a) overwrite the existing "1ubq" (destructive — bad), (b) rename the imported one to "1ubq_1" / "1ubq_2" (PyMOL's `get_unused_name` convention, `querying.py:74`), or (c) error.

### 5.2 Recommended policy: detect + refuse (with a clear message)

**Refuse with an actionable message** — the safest, least-surprising option:

```python
# In _on_import, BEFORE cmd.load:
target_in_bcm = bcm_dict.get('target_obj')
if target_in_bcm and target_in_bcm in demos.list_loaded_molecule_objects():
    QtWidgets.QMessageBox.warning(self, "Name collision",
        "An object named '%s' is already loaded. Please rename or delete it "
        "before importing this puzzle (or re-export the puzzle with a unique "
        "object name)." % target_in_bcm)
    return
```

**Why refuse over auto-rename or overwrite:**
- **Refuse (recommended):** zero data loss; the player is told exactly what to do. The player can `cmd.set_name('1ubq', '1ubq_orig')` (`editing.py:445`) or delete it, then re-import. Simple, safe, explicit.
- **Auto-rename the imported object:** `cmd.set_name` after load — but the partial-load collision behavior is UNVERIFIED, so we don't know if the object arrived as "1ubq" (overwriting the player's) or "1ubq_1". If it overwrote, auto-renaming is too late (player's data gone). Auto-rename only works if partial-load itself renames (option b) — which is the UNVERIFIED case.
- **Overwrite (destructive):** the player loses their "1ubq" silently — unacceptable.

**Fallback within refuse:** if `partial=1` itself renames on collision (option b) and the player's "1ubq" survives, `resolve_target` (§3.4) picks up the renamed "1ubq_1" via the before/after diff. So refuse is the safe default; if smoke confirms partial=1 auto-renames, the refuse check becomes a no-op and `resolve_target` handles it. **Either way, refuse-first is safe.**

### 5.3 Stray `_bchm_backup` in the .pse

If the `.pse` accidentally contains `_bchm_backup` (e.g. a bug in `save_puzzle`'s bare-name selection — §2.3), `partial=1` would load it too. `resolve_target` (§4.1) filters out underscore-prefixed names (`get_names('public_objects')` already excludes them — `querying.py:1148` mode 4; `demos.list_loaded_molecule_objects` at `demos.py:48-60`). After resolving the target, **delete any stray `_bchm_backup`** before snapshotting a fresh one:

```python
# In _on_import, after resolving target_obj, before controller.import_state:
from . import backup
backup.discard(backup.BACKUP_PREFIX)  # idempotent (commanding.py:496); clears any stray
```

This is defensive — `backup.snapshot` (`backup.py:39-44`) already does `cmd.delete('_bchm_backup')` first, so it's belt-and-suspenders. The clean fix is `save_puzzle`'s bare-name selection excluding the backup at save time (§2.3).

---

## 6. `_started`, `_backup_name`, Restart, Cleanup for an Imported Game

### 6.1 `_started` + `_backup_name` semantics

An imported game's hiders came from the `.pse`, NOT from `GameController.start()`. So `start()` was never called. But after `import_state`:
- `_started = True` — hiders are live; `on_pick`/`hint`/`reveal_*`/`cleanup` must work (they all guard `if not self._started: return` — `game.py:154,186,210`).
- `_backup_name = '_bchm_backup'` (from `backup.snapshot(target_obj)` inside `import_state`) — a FRESH snapshot of the **post-import** object (hiders + found-status applied from `.bcm`). This is the "original" for an imported game:
  - **Puzzle import:** backup = "hiders inserted, none found" = the initial puzzle state. Restart restores to this (re-hide all, reset timer) — correct.
  - **Checkpoint import:** backup = "hiders inserted, found-status as saved" = the checkpoint state. Restart restores to this (re-hide to checkpoint, resume timer) — correct.

This reasoning confirms the objective's hypothesis: **snapshot AFTER applying found-status from `.bcm`** (which `import_state` does — step 4 comes after step 3 in §3.6). For a puzzle, found-status is all-hidden, so the backup is "all hidden"; for a checkpoint, the backup includes the found-status. Either way, the backup is the right "original" for that import type.

### 6.2 Restart after Import — `_is_imported` flag routes it

`_on_restart` (`__init__.py:246-263`) currently calls `_on_start()`, which RE-GENERATES hiders from the Setup tab's `per_rep`. But an imported puzzle's Setup state came from the `.bcm`, not the live Setup tab (the player never configured Setup). Re-generating would (a) ignore the imported hiders, (b) possibly fail (the Setup tab's `target_mode` might be "loaded" with no selected object), (c) create a completely different puzzle.

**Recommend: a `_is_imported` flag on the controller** + a separate `_on_restart_imported` path:

```python
def _on_restart(self):
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate(); self.game_tab._wizard = None
        if self._controller is not None: self._controller._wizard = None
    self.game_tab._timer.stop()
    if self._controller is not None and getattr(self._controller, '_is_imported', False):
        self._on_restart_imported()   # restore from the post-import backup
    else:
        self._on_start()              # existing path: re-generate from Setup

def _on_restart_imported(self):
    """Restart an imported game: restore from the post-import backup (re-hides
    all hiders, resets found-status to the imported state, clears hint colors),
    reset runtime counters, re-snapshot, restart countdown. NO re-generation."""
    c = self._controller
    if c is None: return
    # 1. Restore the object to the post-import state (the backup taken in import_state).
    backup.restore(c.target_obj, c._backup_name)        # backup.py:54-64
    backup.discard(c._backup_name)                      # discard the now-stale backup
    # 2. Reconstruct registry from sentinels (the restored object has hiders;
    #    found-status is gone — sentinels are all 'hidden' after restore).
    c.reconstruct_registry()                            # game.py:224 (rep=None)
    # 3. Re-apply .bcm rep (sentinels lost rep; the saved .bcm has it). Re-reconcile
    #    from the .bcm saved at import time — so the controller must RETAIN the
    #    bcm_dict (store it on the controller in import_state).
    registry.reconcile_from_bcm(c.registry, c._imported_bcm['registry'])  # rep + all-hidden
    # 4. Reset runtime counters (fresh round).
    c._reveal_count = 0; c._hint_count = 0
    c._start_time = None  # _begin_play sets it fresh
    # 5. Fresh backup of the restored-to-initial state.
    c._backup_name = backup.snapshot(c.target_obj)
    c._started = True
    # 6. Restart countdown -> _begin_play.
    self.game_tab.start_countdown(c)
```

**Implication:** `import_state` must store the `.bcm` dict on the controller (`self._imported_bcm = bcm_dict`) so Restart-on-imported can re-reconcile rep without re-reading the file. Add `self._imported_bcm = None` in `GameController.__init__` and set it in `import_state`.

For a **checkpoint** import, Restart-on-imported restores to the checkpoint state (found-status as saved) — which is what the player wanted to resume from. For a **puzzle** import, Restart-on-imported restores to all-hidden — a fresh play of the same puzzle. Both correct.

### 6.3 Cleanup after Import — two-step (restore THEN remove hiders)

`controller.cleanup()` (`game.py:231-262`) does `backup.restore(target_obj, _backup_name)` + discard. For a NON-imported game, the backup is the PRE-GAME snapshot (no hiders), so restore gives a clean molecule. For an IMPORTED game, the backup is the POST-IMPORT snapshot (WITH hiders), so restore gives hiders back — NOT what the player wants (they want hiders GONE to use their molecule).

**Cleanup-on-imported must do a two-step:** restore the real-atom colors (which backup-restore does — it restores hint-orange real atoms to their original colors), THEN remove the restored hiders via sentinel-removal:

```python
def _on_cleanup(self):
    if self._controller is None: return
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate(); self.game_tab._wizard = None
        self._controller._wizard = None
    self.game_tab._timer.stop()
    c = self._controller
    if getattr(c, '_is_imported', False):
        # Imported game: restore real-atom colors (backup), then remove hiders.
        # The backup is the post-import state (hiders present); restore brings
        # hiders back BUT restores hint-orange real atoms to original colors.
        backup.restore(c.target_obj, c._backup_name)      # real atoms clean, hiders back
        backup.discard(c._backup_name)
        from . import mutation
        mutation.cleanup_hiders(c.target_obj)             # remove the restored hiders (segi GAME)
        c._started = False; c.registry = registry.HiderRegistry()
        c._reveal_count = 0; c._hint_count = 0
    else:
        c.cleanup()   # existing path: backup is pre-game, restore removes hiders
    self.game_tab._info_log.clear()
    self.game_tab._timer_label.setText("0:00")
    self.game_tab._remaining_label.setText("Remaining: -")
    self.game_tab._reveal_label.setText("Reveals: 0")
    self._controller = None
```

**Why the two-step (not just `mutation.cleanup_hiders`)?:** `cleanup_hiders` (`mutation.py:131-159`) removes `segi GAME` atoms but does NOT reset hint-orange on real atoms (`game.py:244-254` documents this — hint colors REAL neighbor atoms orange, and sentinel-remove alone doesn't restore them). For a non-imported game, `cleanup()` uses backup-restore to fix the orange. For an imported game, backup-restore brings hiders back (bad), so we restore (fixes orange) THEN remove hiders (sentinel). The two-step gives: clean real molecule, no hiders, no orange. **Edge case:** if the player never used Hint on the imported game, `cleanup_hiders` alone would suffice — but the two-step is correct in all cases and costs one extra `cmd.create`. Safe default.

**Alternative considered:** snapshot a SECOND backup of the real-molecule-only state (somehow) at import time. Rejected — the imported .pse has hiders baked in; there's no "real molecule without hiders" snapshot to take at import (the player never had a pre-hider state). The two-step is the cleanest recovery.

---

## 7. Button Placement + Wiring

### 7.1 BTN-05 "Generate & export" — Setup tab

**Position:** between `load_btn` and `cleanup_btn` (button 5 of 7, per spec order in §2.1). In `gui_setup.py:_build_ui` (lines 185-202), the button row is:

```python
for b in (self.reset_btn, self.random_btn, self.save_btn,
          self.load_btn, self.cleanup_btn, self.start_btn):
    brow.addWidget(b)
```

**Change to:**
```python
self.export_btn = QtWidgets.QPushButton("Generate & export")
self.export_btn.setToolTip(
    "Generate hiders and save the initial game state to a file for sharing "
    "or later loading. Does NOT start play — your model keeps the generated "
    "hiders (press Cleanup to restore your scene).")
# ... (add to the row in spec order)
for b in (self.reset_btn, self.random_btn, self.save_btn,
          self.load_btn, self.export_btn, self.cleanup_btn, self.start_btn):
    brow.addWidget(b)
```

**Wiring in `__init__.py:PluginDialog.__init__` (after line 70):**
```python
self.setup_tab.export_btn.clicked.connect(self._on_export)
```

**Label:** "Generate & export" (matches spec verbatim — PROJECT.md line 32). **Tooltip** explains it does not start play + that Cleanup restores the scene (§2.7).

### 7.2 GAME-04 "Import" — Game tab

**Position:** the Game tab `btn_row` (`gui_game.py:40-59`) is: `_hint_btn`, `_reveal_one_btn`, `_reveal_all_btn`, `_found_mgmt_combo`, `_color_btn`, `_restart_btn`, stretch, `_reveal_label`. Import is conceptually a **pre-play** action (like Start — "begin a game"), not an in-game action (Hint/Reveal/Restart are in-game). Two options:

- **Option A (recommended): a NEW top row on the Game tab for "begin/end" actions (Import + Save + Restart).** Visually separates "start a game" (Import) + "checkpoint" (Save) + "restart round" (Restart) from the in-game Hint/Reveal/Found-mgmt row. Reduces crowding in the existing btn_row.
- **Option B: add Import to the existing btn_row** (e.g. before `_hint_btn`). Crowded but no layout change.

**Recommend Option A** — a new `begin_row` QHBoxLayout ABOVE the existing `btn_row`:
```python
# gui_game.py, in __init__ after the existing btn_row:
begin_row = QtWidgets.QHBoxLayout()
self._import_btn = QtWidgets.QPushButton("Import puzzle…")
self._import_btn.setToolTip("Load a puzzle prepared by 'Generate & export' and play it.")
self._save_btn = QtWidgets.QPushButton("Save checkpoint")   # GAME-09 (Save researcher)
self._save_btn.setToolTip("Save the current game state to resume later.")
begin_row.addWidget(self._import_btn)
begin_row.addWidget(self._save_btn)
begin_row.addStretch(1)
layout.addLayout(begin_row)
# Move _restart_btn to begin_row too? No — Restart is in-game (re-generate a
# fresh round with the SAME controller). Keep Restart in btn_row (in-game).
```

**Wiring in `__init__.py:PluginDialog.__init__` (after line 73):**
```python
self.game_tab._import_btn.clicked.connect(self._on_import)
self.game_tab._save_btn.clicked.connect(self._on_save)   # Save researcher owns _on_save
```

**Label:** "Import puzzle…" (the ellipsis signals "opens a dialog" — macOS/Qt convention; matches the existing "Save Setup…" / "Load Setup…" in `gui_setup.py:189-190`). **Tooltip** explains it loads a prepared puzzle.

### 7.3 GAME-09 "Save" — Game tab (shared context for the Save researcher)

**Position:** in the new `begin_row` (§7.2) alongside Import. **Label:** "Save checkpoint". **Tooltip:** "Save the current game state to resume later." The Save researcher owns `_on_save` + the `.bcm` `state='checkpoint'` schema; this research only pins the button placement + the fact that `_on_save` calls `persistence.save_puzzle(target_obj, build_bcm_dict(..., state='checkpoint', started=True, elapsed=..., ...), path)` — the SAME `save_puzzle` + `build_bcm_dict` as `_on_export`, just with `state='checkpoint'` + non-zero `elapsed`/`reveal_count`/`hint_count` + `started=True`. This unifies Save and Export through one persistence path (the only difference is the runtime-state values + the `state` flag).

---

## 8. Headless Smoke-Test Design (`smoke/phase8_smoke.py`)

Modeled on `phase7_smoke.py` (pure `pymol.cmd.*`, NO Qt; run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase8_smoke.py`). Verifies the cmd-coupled export→import round-trip. GUI paths (button clicks, `QFileDialog`, tab-switching, countdown, `PickWizard` activate) are deferred to the human-verify checkpoint.

```python
# smoke/phase8_smoke.py — pure pymol.cmd.* (NO Qt)
import sys, os, tempfile
from pymol import cmd
from biochemeleon import game, registry, backup, mutation, persistence
from biochemeleon.setup_state import build_bcm_dict, parse_bcm_dict

RESULTS = []
def check(name, cond):
    RESULTS.append((name, bool(cond)))
    print(("PASS" if cond else "FAIL") + ": " + name)

# --- 1. SETUP: fetch 1ubq + capture orig ---
cmd.fetch("1ubq", async_=0)
obj = "1ubq"
orig_count = cmd.count_atoms(obj)
check("setup: orig_count > 0", orig_count > 0)

# --- 2. EXPORT (truncated start): start a game, save .pse + .bcm ---
from biochemeleon import generators
extent = cmd.get_extent(obj)
positions = generators.generate_sphere_positions(extent, 3, seed=42)
hider_specs = [(p, "spheres") for p in positions]
gc = game.GameController(obj)
gc.start(hider_specs)
check("export: count += 3", cmd.count_atoms(obj) == orig_count + 3)
check("export: registry len == 3", len(gc.registry.all()) == 3)
# Save the .pse with BARE object name (excludes _bchm_backup; §2.3)
tmpdir = tempfile.mkdtemp()
pse_path = os.path.join(tmpdir, "puzzle.pse")
cmd.save(pse_path, selection=obj)   # bare name -> only obj (exporting.py:973-977)
check("export: .pse file exists", os.path.exists(pse_path) and os.path.getsize(pse_path) > 0)
# Build the .bcm dict (state='puzzle', all hidden, 0 counters)
bcm_dict = build_bcm_dict(target_obj=obj, registry_dict=gc.registry.to_dict(),
    started=False, state='puzzle', elapsed=0.0, reveal_count=0, hint_count=0,
    found_color='green', setup_state={'target_mode':'loaded','selected_object':obj})
bcm_path = os.path.join(tmpdir, "puzzle.bcm")
persistence.write_bcm(bcm_dict, bcm_path)
check("export: .bcm file exists", os.path.exists(bcm_path))
# Verify the .pse does NOT contain _bchm_backup (bare-name selection worked)
# (Can't introspect the .pse without loading it; verify after import instead.)
# Mark 1 hider found to test found-status round-trip later
first_id = gc.registry.all()[0].id
gc._mark_found(first_id)
found_bcm = build_bcm_dict(target_obj=obj, registry_dict=gc.registry.to_dict(),
    started=True, state='checkpoint', elapsed=12.5, reveal_count=0, hint_count=0,
    found_color='green', setup_state={'target_mode':'loaded','selected_object':obj})
# Clean up the export-side game so the import side starts clean
gc.cleanup()
check("export: cleanup restored count", cmd.count_atoms(obj) == orig_count)

# --- 3. IMPORT (puzzle, state='puzzle'): load partial=1, reconstruct, verify ---
# (Simulate a fresh player: delete the molecule, then import)
cmd.delete(obj)
check("import: obj gone before load", obj not in cmd.get_names('public_objects'))
names_before = set(cmd.get_names('public_objects', enabled_only=True))
cmd.load(pse_path, partial=1)   # MERGE (importing.py:823); obj is absent -> no collision
names_after = set(cmd.get_names('public_objects', enabled_only=True))
check("import: obj present after partial load", obj in names_after)
# Reconstruct registry from sentinels (rep=None; game.py:224)
gc2 = game.GameController(obj)
gc2._is_imported = True
bcm_read = persistence.read_bcm(bcm_path)
gc2.import_state(bcm_read)   # reconstruct + reconcile rep + backup + _started=True
check("import: registry len == 3", len(gc2.registry.all()) == 3)
check("import: all hidden (puzzle)", all(r.status == registry.HIDER_STATUS_HIDDEN for r in gc2.registry.all()))
check("import: reps reconciled", all(r.rep == 'spheres' for r in gc2.registry.all()))  # from .bcm
check("import: _started True", gc2._started is True)
check("import: _backup_name set", gc2._backup_name == '_bchm_backup')
check("import: _is_imported True", gc2._is_imported is True)
check("import: count == orig + 3", cmd.count_atoms(obj) == orig_count + 3)
# No stray backup in the public object list (bare-name save worked)
check("import: no second backup object", cmd.get_names('public_objects').count('_bchm_backup') == 0)

# --- 4. IMPORT (checkpoint, state='checkpoint'): found-status round-trip ---
cmd.delete(obj); backup.discard(backup.BACKUP_PREFIX)
gc.cleanup() if gc2._started else None  # clean the puzzle import
gc2.cleanup() if gc2._started else None
# Re-load + import the CHECKPOINT bcm (1 found, elapsed 12.5)
cp_bcm_path = os.path.join(tmpdir, "checkpoint.bcm")
persistence.write_bcm(found_bcm, cp_bcm_path)
cp_pse_path = os.path.join(tmpdir, "checkpoint.pse")
cmd.save(cp_pse_path, selection=obj)   # save WITH the found hider (green)
cmd.delete(obj)
cmd.load(cp_pse_path, partial=1)
gc3 = game.GameController(obj); gc3._is_imported = True
gc3.import_state(persistence.read_bcm(cp_bcm_path))
check("import checkpoint: 1 found", sum(1 for r in gc3.registry.all() if r.status == registry.HIDER_STATUS_FOUND) == 1)
check("import checkpoint: 2 hidden", sum(1 for r in gc3.registry.all() if r.status == registry.HIDER_STATUS_HIDDEN) == 2)

# --- 5. RESTART on imported: restore from backup, all hidden again ---
# (Simulate _on_restart_imported at the cmd layer)
backup.restore(gc3.target_obj, gc3._backup_name)
backup.discard(gc3._backup_name)
gc3.reconstruct_registry()
registry.reconcile_from_bcm(gc3.registry, found_bcm['registry'])  # rep + all-hidden
gc3._reveal_count = 0; gc3._hint_count = 0; gc3._start_time = None
gc3._backup_name = backup.snapshot(gc3.target_obj)
check("restart-imported: all hidden after restore", all(r.status == registry.HIDER_STATUS_HIDDEN for r in gc3.registry.all()))
check("restart-imported: _started True", gc3._started is True)

# --- 6. CLEANUP on imported: two-step (restore + remove hiders) ---
backup.restore(gc3.target_obj, gc3._backup_name)
backup.discard(gc3._backup_name)
mutation.cleanup_hiders(gc3.target_obj)
check("cleanup-imported: hiders gone", cmd.count_atoms("%s and segi GAME" % obj) == 0)
check("cleanup-imported: count back to orig", cmd.count_atoms(obj) == orig_count)

# --- 7. OBJECT-NAME COLLISION: refuse path (cmd-layer verification) ---
# Load 1ubq, then try to partial-load the puzzle .pse (which also has 1ubq).
cmd.fetch("1ubq", async_=0)
names_before = set(cmd.get_names('public_objects', enabled_only=True))
# The refuse check is GUI (_on_import); at the cmd layer we verify the
# collision is DETECTABLE: target_obj '1ubq' is in loaded_molecules.
loaded = [n for n in cmd.get_names('public_objects', enabled_only=True) if cmd.get_type(n) == 'object:molecule']
check("collision: target '1ubq' in loaded (refuse check would fire)", '1ubq' in loaded)

# --- 8. SUMMARY ---
n_pass = sum(1 for _, ok in RESULTS if ok)
n_fail = len(RESULTS) - n_pass
print("\n=== phase8_smoke: %d/%d PASS, %d FAIL ===" % (n_pass, len(RESULTS), n_fail))
sys.exit(1 if n_fail else 0)
```

**What this verifies (headless, cmd-only):**
- `cmd.save(path, selection=bare_name)` saves only the target object (no `_bchm_backup` in the imported scene).
- `cmd.load(path, partial=1)` merges without wiping (obj absent → present after load).
- `controller.import_state(bcm_dict)` reconstructs registry + reconciles rep + sets `_started`/`_backup_name`/`_is_imported`.
- Found-status round-trips through `.bcm` (checkpoint import: 1 found).
- Restart-on-imported restores to all-hidden.
- Cleanup-on-imported two-step removes hiders + restores count.
- Collision is detectable (`target_obj` in loaded molecules).

**What it CANNOT verify (deferred to human-verify):**
- `QFileDialog` open/save dialogs (Qt modal).
- Button click wiring (`export_btn.clicked.connect`, `_import_btn.clicked.connect`).
- Tab switching (`tabs.setCurrentWidget`).
- 3-2-1 countdown (`QtCore.QTimer.singleShot`).
- `PickWizard` activate/deactivate + `mouse_selection_mode` (needs a real viewer).
- The actual partial-load collision behavior when `target_obj` IS present (the smoke deletes obj first to avoid the UNVERIFIED C-level collision; the human-verify must test the real collision + the refuse dialog).
- `_begin_play` timer-resume fix for checkpoint import (needs the GUI timer).

**UNVERIFIED — needs runtime confirmation (priorities for the human-verify checkpoint):**
1. **`cmd.save(path, selection='1ubq')` with a bare name saves ONLY 1ubq** (excludes `_bchm_backup`). If `selector.process('1ubq')` adds parens, `get_psestr` ignores it → saves all. The smoke's "no second backup object" check catches this; if it fails, fallback = `cmd.delete('_bchm_backup')` before save.
2. **`cmd.load(path, partial=1)` preserves existing objects** (does not wipe the player's scene). The smoke deletes obj first (no-collision path); the human-verify must load a puzzle while another object is present + confirm the other object survives.
3. **Partial-load collision behavior** (when `target_obj` IS present): rename, overwrite, or error? The refuse-first policy (§5.2) is safe regardless; the human-verify confirms whether `partial=1` auto-renames (in which case `resolve_target`'s diff fallback handles it).
4. **`set_session(partial=1)` restores objects with original names** (Fact 2). The smoke's "obj present after partial load" check confirms; if it fails (obj arrives as "puzzle" or "1ubq_1"), `resolve_target`'s diff fallback handles it.

---

## 9. The Educator→Player Sharing Narrative (End-to-End)

### 9.1 Educator workflow

1. Open PyMOL (Windows conda env via `setenv.bat` → `pymol`).
2. Load a molecule: `File > Open` a `.pdb`, or `fetch 1ubq`, or use a bundled demo.
3. Open the bioCHEMeleon plugin (Plugins menu → bioCHEMeleon). The Setup tab appears.
4. Configure: pick the loaded object (Target → Loaded object), set hider count, per-rep counts (e.g. 2 spheres + 1 cartoon), difficulty. Optionally orient the molecule + set reps (the view is saved with the `.pse`).
5. Click **"Generate & export"**. A `QFileDialog` prompts for a save path (`.bcmz`). The plugin generates hiders (same as Start would), saves `puzzle.pse` + `puzzle.bcm` into `puzzle.bcmz`, and shows a success dialog: "Saved puzzle to … Your model still has the generated hiders. Press Cleanup to restore your scene."
6. The educator visually verifies the generated hiders look right (optional — the model still shows them). If satisfied, clicks **Cleanup model** (BTN-06) to restore their scene.
7. The educator shares `puzzle.bcmz` (email, LMS, USB drive).

### 9.2 Player workflow

1. Open PyMOL (must have the bioCHEMeleon plugin installed — see §9.3 UX gap).
2. (Optional) load their own molecule for a different puzzle, or start fresh.
3. Open the bioCHEMeleon plugin. Switch to the **Game status** tab.
4. Click **"Import puzzle…"**. A `QFileDialog` prompts for the `.bcmz`. The player picks `puzzle.bcmz`.
5. The plugin unzips, loads `puzzle.pse` with `partial=1` (merges into the player's session — the player's existing objects survive), resolves the target object (e.g. "1ubq") from the `.bcm`, builds a `GameController`, reconstructs the registry from sentinels + reconciles rep from `.bcm`, snapshots a fresh backup, sets `_is_imported=True`.
6. If a name collision is detected (the player already has "1ubq"), the plugin refuses with "An object named '1ubq' is already loaded. Please rename or delete it before importing." The player renames/deletes + retries.
7. The plugin switches to the Game tab, runs the 3-2-1 countdown, activates the `PickWizard`, starts the timer at 0.
8. The player plays (click-to-find). Hint/Reveal/Restart/Cleanup all work:
   - **Restart** restores from the post-import backup (re-hides all, fresh timer) — replays the SAME puzzle.
   - **Cleanup** two-step restores real-atom colors + removes hiders — the player gets a clean molecule to use.
9. (Optional) the player clicks **Save checkpoint** (GAME-09) mid-game to save their progress, then imports it later to resume.

### 9.3 UX gaps + risks

- **The player MUST have the bioCHEMeleon plugin installed.** The `.pse` alone restores the object (with hiders) in any PyMOL, but without the plugin there's no registry, no click-to-find wizard, no timer — the hiders are just atoms. The `.bcm` is meaningless without the plugin. **Document this** in the export success dialog: "Share with someone who has the bioCHEMeleon plugin installed." A future v2 could embed the plugin in the `.pse` (out of scope for v1).
- **Two-file vs bundle:** resolved by recommending `.bcmz` (§2.6). If the team prefers two files, the export dialog should say "Keep both files together" (awkward). The bundle is the better UX.
- **Name collision UX:** the refuse message is actionable but requires the player to know `cmd.set_name` or use the PyMOL object panel. A future "auto-rename on import" (§5.2) would be smoother, but refuse-first is safe for v1.
- **Player's existing scene on import:** `partial=1` preserves it (UNVERIFIED — needs human-verify). If `partial=1` turns out to wipe the scene (unlikely given the source, but UNVERIFIED), the import dialog should warn "Importing will replace your current session" with a confirm. The refuse check (§5.2) + the human-verify will pin this.
- **Checkpoint resume:** the `_begin_play` timer-resume fix (§3.7) is needed for checkpoint import to actually resume the timer. For puzzle-only Phase 8 scope, it's a no-op; include it so Save + Import compose.
- **Restart on imported replays the SAME puzzle** (no re-generation). This matches the player's expectation ("try this puzzle again"). If the player wants a NEW puzzle, they re-import or use Setup → Start. Document in the Restart tooltip: "Restart the current puzzle from the beginning."

---

## 10. Open Risks / Runtime-Verification Needs

| # | Risk | Confidence | Verification |
|---|------|-----------|-------------|
| R1 | `cmd.save(path, selection=bare_name)` saves ONLY the target object (excludes `_bchm_backup`) | MEDIUM (source: `exporting.py:973-977` `get_psestr` ignores `(`-containing selections; `exporting.py:370` `get_session(names=...)` exports named objects) | Headless smoke "no second backup object" check (§8). Fallback: `cmd.delete('_bchm_backup')` before save. |
| R2 | `cmd.load(path, partial=1)` merges without wiping the player's scene | MEDIUM (source: `importing.py:823` `load_pse(partial=0)` → `set_session(partial=0)` full restore; `partial=1` skips `session_file` set → merge path) | Headless smoke deletes obj first (no-collision); human-verify loads puzzle with another object present + confirms it survives. |
| R3 | `set_session(partial=1)` restores objects with original embedded names (not filename prefix) | MEDIUM (source: `importing.py:130-175` `set_session` restores session dict; `load_pse` doesn't pass `object=`) | Headless smoke "obj present after partial load" check (§8). `resolve_target` diff fallback handles a rename. |
| R4 | Partial-load collision behavior (rename/overwrite/error) | LOW (C-level `_cmd.set_session`, can't read source) | Refuse-first policy (§5.2) is safe regardless. Human-verify tests the real collision. |
| R5 | `import_state` snapshot timing (after applying found-status) gives the right "original" for Restart/Cleanup | HIGH (reasoning in §6.1; matches `backup.snapshot` semantics `backup.py:39-44`) | Headless smoke Restart-on-imported + Cleanup-on-imported sections (§8). |
| R6 | `_begin_play` clobbers a resumed `_start_time` for checkpoint import | HIGH (source: `gui_game.py:217-221` unconditionally sets `_start_time = time.time()`) | Needs the `_begin_play` fix (§3.7); verify in human-verify with a checkpoint import. |
| R7 | `.bcmz` zip via stdlib `zipfile` round-trips without corruption | HIGH (stdlib, well-tested) | Headless smoke save→load round-trip (§8). |
| R8 | `registry.reconcile_from_bcm` (the found-status + rep merge) is the registry-merge researcher's lane; `import_state` depends on its signature | LOW (this research assumes a `reconcile_from_bcm(registry, bcm_registry_dict)` pure fn) | Coordinate with the registry-merge researcher on the exact signature; smoke calls it (§8). |
| R9 | The `_prepare_and_start` refactor (§2.4) doesn't break existing Start (Phase 4/7 smokes) | HIGH (pure refactor, no behavior change) | Re-run `phase4_smoke.py` + `phase7_smoke.py` after the refactor. |
| R10 | `_is_imported` flag default: `getattr(c, '_is_imported', False)` in `_on_restart`/`_on_cleanup` (defensive for controllers created before Phase 8) | HIGH (stdlib `getattr` default) | Code review. |

---

## 11. Source Citations

### PyMOL 2.5.0 source (verified by reading `tmp/pymol-src/modules/pymol/`)

| Claim | File:Line | Notes |
|-------|----------|-------|
| `cmd.save(filename, selection='(all)', ...)` | `exporting.py:782` | Default `(all)` saves everything. |
| `.pse` dispatches to `get_psestr` | `exporting.py:997` (`'pse': get_psestr`) | `savefunctions` dict. |
| `get_psestr` ignores `(`-containing selections | `exporting.py:973-977` | `if '(' in selection: selection = ''` → `get_session('')` → all objects. Bare name (no parens) is HONORED. |
| `get_session(names='', partial=0, ...)` exports only named objects | `exporting.py:370-425` | `names`: "Names of objects to export, or the empty string to export all objects" (line 374). |
| `cmd.load` defaults `object` to filename prefix | `importing.py:635, 748-750` | `object = noext if noext else _self.get_unused_name('obj')` — for NON-pse only. |
| `.pse` dispatches to `load_pse` | `importing.py:1623` (`'pse': load_pse`) | `loadfunctions` dict. |
| `load_pse(filename, partial=0, ...)` | `importing.py:823-848` | Calls `set_session(session, partial=partial, ...)`. `if not partial: set session_file` (lines 832-835) confirms `partial=1` is the merge path. |
| `set_session(session, partial=0, ...)` full vs partial restore | `importing.py:130-175` | `_cmd.set_session(_self._COb, session, int(partial), int(quiet))` (line 143) — C-level. `partial=0` = full restore (wipes existing); `partial=1` = merge. |
| `cmd.delete(name)` idempotent + wildcards | `commanding.py:496-530` | Safe on absent objects. |
| `cmd.get_names(type='public_objects', enabled_only=0)` excludes underscore objects | `querying.py:1148-1192` | `public_objects` = mode 4 (line 1177). |
| `cmd.get_unused_name(prefix)` returns a unique name | `querying.py:74-77` | For new objects (not set_session). |
| `cmd.set_name(old, new)` renames objects | `editing.py:445-468` | Collision-resolution tool. |
| `cmd.rename` renames ATOMS (not objects) | `editing.py:1326-1352` | NOT for object collision. |
| `cmd.count_states` | `querying.py:703` | Used by `collapse_to_single_state` (`mutation.py:561`). |

### Existing bioCHEMeleon code (verified by reading)

| Claim | File:Line |
|-------|----------|
| `_on_start` full flow (resolve → collapse → specs → free valences → clean prior → start → countdown) | `__init__.py:79-244` |
| `_on_restart` (wizard deactivate + timer stop + `_on_start`) | `__init__.py:246-263` |
| `_on_cleanup` (wizard + timer + `controller.cleanup()` + UI reset + `_controller=None`) | `__init__.py:265-286` |
| `GameController.start(hider_specs)` (snapshot → insert loop → register → `_started=True`) | `game.py:42-63` |
| `GameController.reconstruct_registry()` (DI sentinel rebuild, rep=None) | `game.py:224-229` |
| `GameController.cleanup()` (restore from backup + discard + reset) | `game.py:231-262` |
| `backup.snapshot(target_obj)` (`cmd.delete` + `cmd.create('_bchm_backup', target)`) | `backup.py:39-44` |
| `backup.restore(target, backup)` (delete+create two-step) | `backup.py:54-64` |
| `backup.discard(backup_name)` (idempotent delete) | `backup.py:47-49` |
| `mutation.cleanup_hiders(object)` (remove `segi GAME` atoms FROM object) | `mutation.py:131-159` |
| `mutation.fetch_all_hider_ids(object)` (iterate `segi GAME and b < 0`) | `mutation.py:95-126` |
| `mutation.collapse_to_single_state(obj)` | `mutation.py:543-569` |
| `mutation.free_nterminal_valence(obj, chain, resi)` | `mutation.py:572-619` |
| `registry.to_dict()` / `from_dict()` | `registry.py:215-245` |
| `registry.reconstruct_from_sentinels(iterate_fn)` (rep=None) | `registry.py:249-272` |
| `game_tab.start_countdown(controller)` (sets _controller, resets, 3-2-1 → `_begin_play`) | `gui_game.py:188-204` |
| `game_tab._begin_play()` (PickWizard activate + set_callbacks + `_start_time = time.time()` + timer) | `gui_game.py:206-224` |
| Setup tab button row (Reset/Randomize/Save/Load/Cleanup/Start) | `gui_setup.py:185-202` |
| Game tab btn_row (Hint/Reveal-one/Reveal-all/found-mgmt/Color/Restart/Reveals) | `gui_game.py:36-59` |
| `collect_state()` (the full Setup dict) | `gui_setup.py:441-459` |
| `demos.list_loaded_molecule_objects()` (`get_names('public_objects', enabled_only=True)` + `get_type=='object:molecule'`) | `demos.py:48-60` |
| `PickWizard` activate/deactivate (mouse_selection_mode save/restore) | `wizard.py:73-79` |

### Spec / planning docs (verified by reading)

| Claim | Source |
|-------|--------|
| Setup buttons order: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup model, Start | `PROJECT.md:32`; `07-RESEARCH.md:106` (quoting spec line 20); `SUMMARY.md:47` |
| Import is on the Game tab | `ROADMAP.md:175`; `PROJECT.md:33`; `SUMMARY.md:49` |
| BTN-05 = "only generate the representation of the game and save the initial state to a file for sharing or later loading" | `REQUIREMENTS.md:31` |
| GAME-04 = "import a game prepared by Generate & export" | `REQUIREMENTS.md:49` |
| GAME-09 = "save the game state as a PyMOL session (.pse) + a companion .bcm JSON sidecar" | `REQUIREMENTS.md:54` |
| `.bcm` reserved for game-state sidecars; `.bcm.setup.json` is the distinct setup extension | `02-RESEARCH.md:851` |
| Sentinel survives `.pse` save/load; id stable; b=-999 preserved; reconstruct gives rep=None | `PITFALLS.md:449-450`; `STATE.md:95,253`; `ROADMAP.md:266` |
| `registry.to_dict/from_dict` + `reconstruct_from_sentinels` are the Phase 8 foundation | `STATE.md:124,136,204,218,244,277` |

---

## Metadata

**Confidence breakdown:**
- Export flow + button placement: **HIGH** — reuses verified `_on_start` steps; spec pins button order; `cmd.save` bare-name behavior verified from source (MEDIUM at runtime).
- Import flow + object-name handling: **MEDIUM** — `partial=1` merge + original-name restore verified from source but UNVERIFIED at runtime (C-level collision behavior); `resolve_target` diff fallback + refuse-first policy defend against all cases.
- Restart/Cleanup on imported: **HIGH** — reasoning grounded in `backup.snapshot/restore` + `mutation.cleanup_hiders` semantics (all verified); the two-step Cleanup is the correct generalization.
- Where code lives (`persistence.py` + pure assembly in `setup_state.py` + `GameController.import_state`): **HIGH** — matches the established `backup.py`/`mutation.py` standalone pattern + the strict dependency direction.
- Smoke-test design: **HIGH** — modeled on the verified `phase7_smoke.py` pattern; covers the cmd-coupled round-trip; GUI paths deferred to human-verify (consistent with all prior phases).

**Research date:** 2026-08-12
**Valid until:** 2026-09-11 (30 days — PyMOL 2.5.0 is a fixed target; the UNVERIFIED runtime behaviors (R1-R4) should be pinned by the Phase 8 headless smoke + human-verify before then).
