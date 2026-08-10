# Phase 7: Found-Hider Management, Restart & Cleanup - Research

**Researched:** 2026-08-11
**Domain:** PyMOL 2.5.0 plugin integration — GUI buttons + cmd-layer cleanup/restart + found-hider selector logic
**Confidence:** HIGH (all claims about current code verified by reading source with file:line citations; Qt/QColorDialog verified from PyMOL 2.5.0 source `tmp/pymol-src/modules/pymol/Qt/__init__.py`; `cmd.set_color` verified from `viewing.py:2107`)

## Summary

Phase 7 adds four features: (1) a found-hider management dropdown (GAME-08) on the Game tab, (2) a Restart button (GAME-10) on the Game tab, (3) a Cleanup button (BTN-06) on the Setup tab, and (4) a color picker (DIFF-04) integrated with the dropdown. This is a standard-pattern integration phase — the underlying primitives (backup.restore, cleanup(), sentinel selection, registry queries, PickWizard lifecycle) all exist and are verified. The work is GUI wiring + one small pure helper + threading a color parameter through `_mark_found`.

The single most important finding: **GameController does NOT retain `hider_specs`** (game.py:36-57), but Restart does NOT need them — the success criteria says "regenerates hiders for a fresh round" = NEW hiders, not the same ones. So Restart = re-run `_on_start()` (which already handles prior-game cleanup at `__init__.py:220-221`). No `restart()` method on GameController is needed. The two things `_on_start()` does NOT currently handle that Phase 7 MUST add: (a) deactivate the old PickWizard before cleanup (wizard lifecycle bug — see §2), and (b) clear the Game tab log for the fresh round.

**Primary recommendation:** Restart button calls a new `_on_restart()` in `__init__.py` that deactivates the wizard + clears the log + calls `_on_start()`. Cleanup button calls a new `_on_cleanup()` that deactivates the wizard + calls `controller.cleanup()` + stops the timer + resets UI. The found-hider dropdown lives in `gui_game.py` btn_row and queries `registry.all()` filtered by `status=='found'`. The color picker uses `QtWidgets.QColorDialog.getColor()` (available via `pymol.Qt` — confirmed) and registers a custom PyMOL color via `cmd.set_color()`.

## 1. Current State (verified by reading source)

### GameController (`biochemeleon/game.py`)
- **Does NOT store `hider_specs`**: `start(hider_specs)` at game.py:36-57 receives specs, iterates them (line 52: `for i, (payload, rep) in enumerate(hider_specs)`), but never assigns them to `self`. There is no `self._hider_specs` attribute.
- **`cleanup()` restores from backup + resets counters** (game.py:225-256): calls `backup.restore` (delete+create two-step), `backup.discard`, sets `_started=False`, fresh `HiderRegistry()`, `_reveal_count=0`, `_hint_count=0`. Returns the `backup.restore` bool. Idempotent when not started (line 241-242: `if not self._started: return True`).
- **`cleanup()` does NOT deactivate the wizard**: no reference to `self._wizard` in cleanup() or abort_on_error(). The wizard lifecycle is owned by the GUI (game.py:114-126 docstring: "The GUI owns the wizard lifecycle").
- **`_mark_found` hardcodes `'green'`** (game.py:108-111): `cmd.color('green', "%s and id %s" % (self.target_obj, hider_id))`. Phase 7 DIFF-04 must parameterize this.
- **`self._wizard = None`** in `__init__` (game.py:27), set by the GUI in `_begin_play` (gui_game.py:131). The controller holds a reference but never deactivates it.

### GameTab (`biochemeleon/gui_game.py`)
- **btn_row** (gui_game.py:36-49): QHBoxLayout with Hint/Reveal-one/Reveal-all QPushButtons + reveal counter QLabel. This is where the found-hider dropdown + Restart button go.
- **`start_countdown`** (gui_game.py:110-117): sets `_controller`, resets `_reveal_label` to "Reveals: 0", logs "Get ready...", starts countdown. Does NOT clear `_info_log`.
- **`_begin_play`** (gui_game.py:127-144): creates PickWizard, activates it, sets `controller._wizard`, registers callbacks, starts timer. Creates a NEW wizard each time — does NOT deactivate a prior one.
- **`_finish_win`** (gui_game.py:163-195): deactivates wizard (line 178-181), shows win dialog (line 191: `msg.exec_()`), then calls `controller.cleanup()` (line 195). This is the ONLY place the wizard is deactivated.
- **Button guard pattern** (gui_game.py:78-81): `if self._controller is None or not self._controller._started: return` + `if self._controller._remaining() == 0: return`.
- **Controller is DUCK-TYPED** (no `game.py` import in gui_game.py).

### PluginDialog (`biochemeleon/__init__.py`)
- **`self._controller = None`** (init.py:67): the Phase 7 hook (04-05 SUMMARY confirmed: "holds the active GameController across the round so Phase 7 cleanup/restart can reach it").
- **`_on_start`** (init.py:76-231): the BTN-07 fan-in. Line 220-221: `if self._controller is not None and self._controller._started: self._controller.cleanup()` — defensively cleans up a prior game. Does NOT deactivate the wizard.
- **Start button wired** (init.py:70): `self.setup_tab.start_btn.clicked.connect(self._on_start)`.

### Registry (`biochemeleon/registry.py`)
- **`HIDER_STATUS_FOUND = 'found'`** (registry.py:39).
- **`all()`** returns all records in insertion order (registry.py:153-155). **No "found filter" method exists** — filter via `[r for r in registry.all() if r.status == HIDER_STATUS_FOUND]`.
- **`HiderRecord` has `id`, `object`, `rep`, `status`, `pos`** (registry.py:70). The `rep` field is needed for "show found hiders" (each hider may have a different rep).
- **`by_rep(rep)`** (registry.py:168-176) filters by rep, NOT by status.

### PickWizard (`biochemeleon/wizard.py`)
- **`activate()`** (wizard.py:73-75): saves current wizard (`self._saved_wizard = cmd.get_wizard()`) + sets self.
- **`deactivate()`** (wizard.py:77-79): restores saved wizard + restores `mouse_selection_mode`.
- **`__init__`** (wizard.py:33-41): saves `mouse_selection_mode` + sets it to 0 (atomic pick) + deselects. If a prior wizard's `deactivate()` was never called, `mouse_selection_mode` stays at 0 (corrupted).

### Backup (`biochemeleon/backup.py`)
- **`restore(target, backup)`** (backup.py:54-64): `cmd.delete(target)` + `cmd.create(target, backup)` two-step. Returns True/False.
- **`verify_intact(target, backup)`** (backup.py:69-85): compares `(resn, resi, name, chain, segi)` tuples — NOT atom ids. This confirms **atom ids are NOT preserved across delete+create** (if they were, verify_intact would use them).

### Mutation (`biochemeleon/mutation.py`)
- **`cleanup_hiders(obj)`** (mutation.py:131-159): `cmd.remove(f"{obj} and segi GAME")` — sentinel-only removal. Returns count removed. NOT used by cleanup() anymore (Phase 6 fix: cleanup uses backup.restore instead).
- **`fetch_all_hider_ids(obj)`** (mutation.py:95-126): iterate `segi GAME and b < 0`, returns `[(object_name, id)]` tuples.
- **`_id_sele(ids)`** pattern (mutation.py:412-415): `"id " + "+".join(str(i) for i in ids)` — the canonical PyMOL `id a+b+c` selector from stable atom ids.

## 2. Restart Design

### State retention: NOT needed
GameController does NOT store `hider_specs` (game.py:36-57). But the success criteria says "regenerates hiders for a fresh round" = NEW hiders, not the same ones. So Restart does NOT need to retain specs.

**Critical finding on id stability:** after `backup.restore` (delete+create), atom ids are NOT preserved (backup.py:69-85 uses identity tuples, NOT ids, for verification — confirming ids shift across delete+create). This means line/stick hider payloads containing `neighbor_id` from the prior round would be STALE after restore. Re-running `_on_start()` re-collects `neighbor_ids` from the restored object (init.py:146-148) — SAFE. Storing specs on the controller for reuse would be UNSAFE for line/stick hiders.

### Restart = cleanup + start, via `_on_start()`
**Recommendation: Restart button calls `_on_start()`** (the existing BTN-07 fan-in). _on_start already:
1. Cleans up the prior game (init.py:220-221: `if self._controller is not None and self._controller._started: self._controller.cleanup()`)
2. Re-collects neighbor_ids from the restored object (init.py:146-148)
3. Re-generates hider_specs from the Setup tab state (init.py:161-198)
4. Creates a new GameController + starts it (init.py:222-224)
5. Switches to Game tab + starts countdown (init.py:230-231)

No new `restart()` method on GameController is needed.

### Wizard lifecycle bug on Restart (MUST FIX)
**The problem:** `_on_start()` calls `controller.cleanup()` (init.py:221) but does NOT deactivate the PickWizard. Then `start_countdown` → `_begin_play` creates a NEW PickWizard (gui_game.py:129). The old wizard's `deactivate()` is never called, so:
- `mouse_selection_mode` stays at 0 (set by old wizard's `__init__`, never restored)
- The new wizard's `__init__` saves `mouse_selection_mode` = 0 (wrong — should be the pre-game value)
- The new wizard's `activate()` saves the OLD wizard as `_saved_wizard` (stale reference)
- On new wizard deactivate: restores wizard to the OLD wizard (stale) + restores `mouse_selection_mode` to 0 (wrong)

**The fix:** Add a new `_on_restart()` method in `__init__.py` (or enhance `_on_start`) that deactivates the wizard BEFORE cleanup:
```python
def _on_restart(self):
    # Deactivate the old wizard before cleanup (wizard lifecycle:
    # _on_start creates a NEW wizard in _begin_play, but the OLD one
    # must be deactivated first to restore mouse_selection_mode + prior wizard)
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate()
        self.game_tab._wizard = None
        if self._controller is not None:
            self._controller._wizard = None
    self.game_tab._info_log.clear()  # fresh round = clean log
    self._on_start()
```

**Alternative:** fold this into `_on_start` itself (fixes the same bug for the Start button when clicked mid-game). Recommended — the bug exists for BOTH Start and Restart.

### Timer/log/counters reset
- **Timer:** `_begin_play` sets `_start_time = time.time()` + `self._timer.start(1000)` (gui_game.py:138-143). But it does NOT stop a prior timer. Add `self._timer.stop()` before starting (defensive — timer may still be running from a prior round if Restart fires mid-game).
- **Log:** `start_countdown` does NOT clear `_info_log` (gui_game.py:110-117). Must add `self._info_log.clear()` for a fresh round.
- **Counters:** `start()` resets `_reveal_count=0` + `_hint_count=0` (game.py:50-51). `start_countdown` resets `_reveal_label` (gui_game.py:115). Already handled.

## 3. Cleanup Button Design (BTN-06)

### Placement: Setup tab (per spec.md:20)
Spec line 20: "the bottom of the popup within would have 7 buttons: (1) Reset, (2) Randomize, (3) Save Setup, (4) Load Setup, (5) Generate and export, (6) Cleanup model (7) Start". Cleanup is button 6 — a SETUP TAB button, not a Game tab button.

### Distinction from Restart
| | Cleanup (BTN-06) | Restart (GAME-10) |
|---|---|---|
| Location | Setup tab | Game tab |
| Action | Restore original + END round | Restore original + BEGIN new round |
| New hiders? | NO | YES (fresh round) |
| Tab after | Stays on / returns to Setup | Switches to Game tab + countdown |
| Controller after | `_started=False`, no new game | New GameController, `_started=True` |
| Wizard | Deactivated | Re-activated (new PickWizard) |
| Timer | Stopped | Reset + started |

### `_on_cleanup()` method in `__init__.py`
```python
def _on_cleanup(self):
    if self._controller is None:
        return  # no game to clean up
    # Deactivate wizard (if active)
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate()
        self.game_tab._wizard = None
        self._controller._wizard = None
    # Stop timer
    self.game_tab._timer.stop()
    # Restore original + reset controller state
    self._controller.cleanup()
    # UI reset: log, labels
    self.game_tab._info_log.clear()
    self.game_tab._timer_label.setText("0:00")
    self.game_tab._remaining_label.setText("Remaining: -")
    self.game_tab._reveal_label.setText("Reveals: 0")
```

**Guard:** Cleanup should no-op if no game is running. cleanup() is idempotent (returns True if not started), but the button should still guard to avoid unnecessary UI resets. Guard: `if self._controller is None or not self._controller._started: return` (but allow cleanup after win — _finish_win already calls cleanup, so `_started=False` by then; a second cleanup is a harmless no-op).

**Better guard:** `if self._controller is None: return` (cleanup() handles the `_started=False` case internally). This allows Cleanup to fire after win (harmless no-op) but not before any game.

### Does Cleanup deactivate the PickWizard?
**YES — it must.** The wizard's `deactivate()` restores `mouse_selection_mode` + prior wizard (wizard.py:77-79). If Cleanup doesn't deactivate, the user is left in atomic-pick mode with a dangling wizard. The `_on_cleanup()` method above handles this.

### Does Cleanup clear the GameTab log?
**YES — per the `_on_cleanup()` sketch above.** "Clean the model back to its original state" (success criteria) implies a clean slate. Clear `_info_log`, reset timer/remaining/reveal labels.

## 4. Found-Hider Management Dropdown (GAME-08)

### Placement: Game tab btn_row (per spec.md:41)
Spec line 41: "dropdown to hide/show/change color of the hider(s) with a 'found' status" — this is a Game status tab feature. Add a QComboBox to the btn_row in `gui_game.py` (after the Hint/Reveal buttons).

### Selector strategy: registry-driven (NOT color-based)
**Do NOT filter by color** (e.g., `color green`) — the color is player-chosen (DIFF-04) and may change. **Filter by registry status:**
```python
found_records = [r for r in self._controller.registry.all()
                 if r.status == registry.HIDER_STATUS_FOUND]
```
Then build the selection from stable atom ids (the `id a+b+c` pattern from mutation.py:412-415):
```python
if not found_records:
    return  # nothing to manage
ids = [r.id for r in found_records]
sele = "%s and id %s" % (self._controller.target_obj, "+".join(str(i) for i in ids))
```

### Three modes

**Hide found:**
```python
cmd.hide("everything", sele)
```
Hides ALL representations for found hiders. Found hiders don't need to be clickable (they're already found). `cmd.hide("everything", ...)` is the thorough choice — `cmd.hide(rep, ...)` would leave them visible in other reps.

**Show found:**
Per-rep (each found hider may have a different rep — the registry record has `rep`):
```python
# Group by rep for efficiency
by_rep = {}
for r in found_records:
    by_rep.setdefault(r.rep, []).append(r.id)
for rep, ids in by_rep.items():
    cmd.show(rep, "%s and id %s" % (obj, "+".join(str(i) for i in ids)))
```

**Recolor found:**
```python
cmd.color(self._controller._found_color, sele)
```
Uses the player-chosen color (stored on the controller — see §5).

### Hide-vs-clickability tradeoff
**Hidden atoms CANNOT be clicked in PyMOL** — picking requires visible rendered geometry (the PickWizard.do_pick/do_select path in wizard.py:43-71 relies on visible geometry to create `pk1`/`sele`). Hiding found hiders makes them unclickable. **This is FINE** — found hiders are already marked found in the registry; `on_pick` returns "Already found!" (game.py:98-99) if clicked again. Hiding them just removes visual clutter. The dropdown's "show" mode re-exposes them if desired.

**No conflict with the click-to-find loop:** the loop only cares about HIDDEN hiders (status=='hidden'). Hidden-STATUS hiders must remain VISIBLE (shown as their rep) to be clickable. The dropdown only operates on FOUND hiders.

## 5. Color Picker (DIFF-04)

### QColorDialog is available via `pymol.Qt` (HIGH confidence)
Verified from PyMOL 2.5.0 source (`tmp/pymol-src/modules/pymol/Qt/__init__.py`):
- Line 28: `from PyQt5 import QtGui, QtCore, QtOpenGL, QtWidgets` (PYQT_NAME='PyQt5')
- Line 36: `from PySide2 import QtGui, QtCore, QtOpenGL, QtWidgets` (PYQT_NAME='PySide2')
- Both PyQt5 and PySide2 have `QColorDialog` as a standard `QtWidgets` class.

**Usage pattern:**
```python
from pymol.Qt import QtWidgets
color = QtWidgets.QColorDialog.getColor()
if color.isValid():
    # user picked a color; convert to PyMOL RGB
    r, g, b, a = color.getRgbF()  # floats 0.0-1.0
    from pymol import cmd
    cmd.set_color('found_highlight', [r, g, b])  # viewing.py:2107
    self._controller._found_color = 'found_highlight'
```

### `cmd.set_color` signature (verified from viewing.py:2107-2124)
```python
def set_color(name, rgb, mode=0, quiet=1, *, _self=cmd):
```
- `name`: string (new or existing color name)
- `rgb`: list of [r, g, b] in range (0.0, 1.0) or (0, 255)

### QColorDialog is MODAL — no `.exec_()` from our code
`QColorDialog.getColor()` is a static method that runs its own modal event loop internally and returns a `QColor` (invalid if cancelled). **Our code does NOT call `.exec_()` on it** — the exec_ grep gate (currently 1 hit on `msg.exec_()` in `_finish_win`) stays at 1. The QColorDialog is a child dialog (like QFileDialog/QMessageBox), so it does NOT violate the "main dialog stays modeless" rule.

### Where to store the chosen color
**On GameController as a string (PyMOL color name):**
```python
# In GameController.__init__ (game.py:20-34):
self._found_color = 'green'  # default; DIFF-04 overrides via set_color

# In _mark_found (game.py:108-111):
def _mark_found(self, hider_id):
    self.registry.mark_found(self.target_obj, hider_id)
    cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))
```

This keeps game.py decoupled from Qt (the color is a plain string). The GUI:
1. Gets QColor from `QColorDialog.getColor()`
2. Converts to RGB floats via `getRgbF()`
3. Registers via `cmd.set_color('found_highlight', [r, g, b])`
4. Sets `controller._found_color = 'found_highlight'`
5. Recolors existing found hiders via the dropdown's "recolor" mode

### Applying to future + existing found hiders
- **Future finds:** `_mark_found` uses `self._found_color` (parameterized above). Automatic.
- **Existing found hiders:** the dropdown's "recolor" mode calls `cmd.color(self._found_color, found_sele)`. Explicit.
- **Open question (LOW confidence):** does re-calling `cmd.set_color('found_highlight', new_rgb)` update atoms already colored `'found_highlight'`? PyMOL colors are stored by name reference, so re-defining the name MAY update all atoms using it — but this is unverified. **Safe approach:** always re-apply `cmd.color(...)` explicitly after changing the color. The "recolor" dropdown mode does this.

## 6. Button Guards

### Guard patterns across game states

| State | Cleanup | Restart | Dropdown | Hint/Reveal (existing) |
|---|---|---|---|---|
| No game started (`_controller is None`) | no-op | no-op (or = Start) | no-op | no-op (existing) |
| Countdown (before `_begin_play`) | disable or no-op | disable or no-op | no-op | no-op (existing) |
| Mid-game (`_started=True`, wizard active) | WORKS (deactivate + cleanup) | WORKS (deactivate + cleanup + new game) | WORKS (if found hiders exist) | WORKS (existing) |
| After win (`_started=False`, wizard deactivated) | no-op (already cleaned) | WORKS (= Start) | no-op (no controller) | no-op (existing) |
| After cleanup (`_started=False`) | no-op | WORKS (= Start) | no-op | no-op (existing) |

**Recommended guards:**
- **Cleanup:** `if self._controller is None: return` (cleanup() handles `_started=False` internally as idempotent no-op; UI reset is safe to skip when no game ever started)
- **Restart:** always fires (calls `_on_start` which handles all states). Optionally disable during countdown to prevent double-start — but `_on_start` has a `RuntimeError` catch for double-start (init.py:225-228).
- **Dropdown:** `if self._controller is None or not self._controller._started: return` + `found = [r for r in registry.all() if r.status == 'found']; if not found: return`

**Button enable/disable (Qt):** The existing buttons (Hint/Reveal) use no-op guards (silent early return), NOT enable/disable. For consistency, Cleanup/Restart/dropdown should follow the same pattern — no-op guards, not enable/disable. The human-verify checkpoint confirms the guard behavior.

## 7. `_controller` Ownership Flow (`__init__.py`)

### Current state
- `self._controller = None` (init.py:67)
- `_on_start` creates a new GameController (init.py:222: `self._controller = game.GameController(target_obj)`)
- `_finish_win` calls `self._controller.cleanup()` (gui_game.py:195) but does NOT set `_controller = None`

### Phase 7 wiring
**Cleanup button** → `_on_cleanup()`:
1. Deactivate wizard (if active)
2. Stop timer
3. `self._controller.cleanup()` (restore + reset)
4. Reset UI (log, labels)
5. Keep `self._controller` referenced (for Restart) OR set `None` (Restart re-creates via `_on_start` anyway)

**Recommendation: set `self._controller = None` after cleanup.** Rationale: after cleanup, the controller is in a "not started" state with no backup, no registry, no hiders. Keeping it serves no purpose — Restart calls `_on_start` which creates a fresh controller. Setting `None` makes the guard `if self._controller is None: return` work correctly for subsequent Cleanup clicks.

**Restart button** → `_on_restart()`:
1. Deactivate wizard (if active) — wizard lifecycle fix
2. Clear log
3. Call `self._on_start()` (which creates a new controller + starts the round)

**Dropdown** → `_on_found_mgmt(mode)`:
1. Guard: `if self._controller is None or not self._controller._started: return`
2. Query found records from `self._controller.registry.all()`
3. Build selection from found ids
4. Switch on mode: hide / show / recolor

**Color picker** → `_on_pick_color()`:
1. `color = QtWidgets.QColorDialog.getColor()`
2. `if not color.isValid(): return`
3. `r, g, b, _ = color.getRgbF()`
4. `cmd.set_color('found_highlight', [r, g, b])`
5. `self._controller._found_color = 'found_highlight'`
6. Optionally auto-recolor existing found hiders

## 8. Headless-Testable vs Human-Verify

### Headless-testable (phase7_smoke.py)
A `smoke/phase7_smoke.py` (pure `pymol.cmd.*`, NO Qt — modeled on phase6_smoke.py) can test:

| Test | Headless? | How |
|---|---|---|
| Restart: start → cleanup → start again → verify_intact | YES | `gc.start(specs)` → `gc.cleanup()` → `gc2.start(specs2)` → `backup.verify_intact` True + count matches |
| Cleanup: start → cleanup → verify_intact + count-back + no GAME atoms | YES | Same as phase6 smoke C9 (already proven); re-verify for the explicit Cleanup path |
| Found-management selector: mark found → build id selection → hide/show/recolor | YES | `gc.start` → `gc.on_pick(id)` (mark found) → build `"obj and id X"` → `cmd.hide("everything", sele)` → `cmd.count_atoms("obj and rep spheres and id X") == 0` → `cmd.show("spheres", sele)` → count back up |
| Color: `cmd.set_color('found_highlight', [0.5, 0.5, 0.0])` → `cmd.color('found_highlight', sele)` → verify color changed | YES | `cmd.iterate(sele, "stored.append(color)")` — check color index changed |
| `_found_color` parameter threading | YES | `gc._found_color = 'cyan'` → `gc._mark_found(id)` → `cmd.color` called with 'cyan' not 'green' |
| Pure helper `build_found_selection(records)` | YES (unit test) | Pure function — no cmd, testable in WSL |

### Human-verify only (GUI checkpoint)
| Feature | Why |
|---|---|
| QColorDialog modal picker | Qt widget — cannot run headless |
| Dropdown QComboBox UI | Qt widget |
| Cleanup/Restart button enable/disable + click behavior | Qt + wizard lifecycle in real PyMOL |
| Wizard deactivation on Restart (mouse_selection_mode restore) | Requires real PyMOL GUI to verify mouse mode |
| Log clearing on Restart | Qt QTextEdit |
| Timer reset on Restart | Qt QTimer + real PyMOL |
| Tab switch (Cleanup → Setup, Restart → Game) | Qt QTabWidget |

## 9. TDD Candidates

### Pure helper: `build_found_selection(records, object_name)` (HIGH value)
**What:** Takes a list of HiderRecords + object name, returns a PyMOL selection string for all FOUND hiders.
**Why pure:** No `from pymol`, no Qt. Pure string building. WSL-unit-testable.
**Where:** Could live in `registry.py` (pure layer) as a module-level function, or in a new section. Keeps registry.py as the single source of hider-selection logic.
**Signature:**
```python
def build_found_selection(records, object_name):
    """Build a PyMOL selection string for all FOUND hiders.
    Returns '<object_name> and id X+Y+Z' or None if no found records."""
    found_ids = [r.id for r in records if r.status == HIDER_STATUS_FOUND]
    if not found_ids:
        return None
    return "%s and id %s" % (object_name, "+".join(str(i) for i in found_ids))
```
**Tests:** empty records → None; no found → None; 1 found → `"obj and id 100"`; 3 found → `"obj and id 100+101+102"`; mixed hidden/found → only found ids.

### Pure helper: `group_found_by_rep(records)` (MEDIUM value)
**What:** Groups found records by rep for per-rep `cmd.show`.
**Why pure:** Dict building from records. WSL-testable.
**Signature:**
```python
def group_found_by_rep(records):
    """Return {rep: [ids]} for all FOUND records. Skips rep=None records."""
    out = {}
    for r in records:
        if r.status == HIDER_STATUS_FOUND and r.rep is not None:
            out.setdefault(r.rep, []).append(r.id)
    return out
```

### Controller test: `_found_color` threading (MEDIUM value)
**What:** Test that `_mark_found` uses `self._found_color` instead of hardcoded 'green'.
**How:** Same mock pattern as test_game_controller.py: set `gc._found_color = 'cyan'`, call `gc._mark_found(100)`, assert `cmd.color` called with `'cyan'` not `'green'`.

### Controller test: Restart via cleanup + start (LOW value)
**What:** Test that `cleanup()` followed by a new `start()` works (counters reset, fresh registry).
**How:** Already covered by `test_cleanup_resets_counters` (test_game_controller.py:438-453). The headless smoke covers the full start→cleanup→start cycle.

## 10. Open Risks / Pitfalls

### Risk 1: Wizard lifecycle on Restart (MEDIUM — must fix)
**What:** `_on_start` does NOT deactivate the old PickWizard before cleanup. Creating a new wizard without deactivating the old corrupts `mouse_selection_mode` (stays at 0) + loses the prior-wizard reference.
**Fix:** `_on_restart()` (or `_on_start` itself) deactivates the wizard before cleanup. See §2.
**Detection:** Human-verify (mouse mode in real PyMOL GUI). Headless smoke cannot catch this (no wizard in headless).

### Risk 2: `cmd.set_color` re-define behavior (LOW — safe approach documented)
**What:** Re-calling `cmd.set_color('found_highlight', new_rgb)` on an existing color name — does it update atoms already colored `'found_highlight'`?
**Impact:** If YES, changing the color auto-updates all found hiders. If NO, must explicitly re-apply `cmd.color`.
**Safe approach:** Always explicitly re-apply `cmd.color(self._found_color, found_sele)` after changing the color (the "recolor" dropdown mode does this). Don't rely on set_color auto-propagation.
**Verification:** Headless smoke can test this: `set_color` + `color` + iterate to check color index, then `set_color` again + iterate to check if it changed without re-applying `color`.

### Risk 3: `_mark_found` color threading (LOW — straightforward)
**What:** `_mark_found` (game.py:108-111) hardcodes `'green'`. Phase 7 parameterizes to `self._found_color`.
**Impact:** Existing tests assert `cmd.color` called with `'green'` (test_game_controller.py:95, 343, 411). These tests must update to use `gc._found_color` (default 'green' — tests still pass if the default stays 'green').
**Fix:** Change `_mark_found` to use `self._found_color`. Add `self._found_color = 'green'` to `__init__`. Existing tests pass unchanged (default is 'green').

### Risk 4: Restart during countdown (LOW — guarded by RuntimeError)
**What:** If the user clicks Restart during the 3-2-1 countdown (before `_begin_play`), `_on_start` creates a new controller + starts, but the old countdown's `singleShot` chain is still pending — it will fire `_begin_play` on the NEW controller mid-countdown.
**Fix:** The countdown's `singleShot` chain (gui_game.py:119-125) should be cancelable. Or: disable Restart during countdown. Or: the countdown should check if the controller is still the same one before calling `_begin_play`.
**Low risk:** The countdown is 3 seconds; the user is unlikely to click Restart during it. But the planner should be aware. Simplest fix: store the countdown timer ID + cancel it in `_on_restart` before calling `_on_start`.

### Risk 5: Dropdown QComboBox + exec_ gate (LOW — no issue)
**What:** QComboBox does NOT use `.exec_()` — it's a dropdown, not a modal dialog. QColorDialog.getColor() uses its own internal event loop (no `.exec_()` from our code).
**Impact:** The exec_ grep gate stays at 1 (existing `msg.exec_()` in `_finish_win`). No new `.exec_()` calls from Phase 7.

### Risk 6: `cmd.hide("everything", sele)` vs per-rep hide (LOW — documented choice)
**What:** Hiding found hiders with `cmd.hide("everything", sele)` hides ALL reps. Re-showing with `cmd.show(rec.rep, sele)` shows only the original rep (not all reps).
**Impact:** After hide → show, the hider shows only its original rep. This is correct behavior (the hider was originally shown in only its rep by `insert_hider_for_rep`).
**Verification:** Headless smoke can test: `cmd.hide("everything", sele)` → `cmd.count_atoms("obj and rep spheres and id X") == 0` → `cmd.show("spheres", sele)` → `cmd.count_atoms("obj and rep spheres and id X") == 1`.

### Risk 7: Cleanup button placement (LOW — spec says Setup tab)
**What:** Spec.md:20 says Cleanup is button 6 on the Setup tab. But the Phase 7 success criteria describe it as a game-management action. The planner must add the button to `gui_setup.py` (Setup tab), NOT `gui_game.py` (Game tab).
**Impact:** The button is on the Setup tab but operates on the active GameController (held by PluginDialog). Wiring: `self.setup_tab.cleanup_btn.clicked.connect(self._on_cleanup)` in `__init__.py`.

## Standard Stack

No new libraries. Everything uses existing PyMOL 2.5.0 primitives:

| Tool | Source | Purpose | Confidence |
|------|--------|---------|------------|
| `QtWidgets.QColorDialog.getColor()` | `pymol.Qt` (re-exports from PyQt5/PySide2) | Modal color picker (DIFF-04) | HIGH (Qt/__init__.py:28,36) |
| `cmd.set_color(name, rgb)` | `pymol/viewing.py:2107` | Register custom PyMOL color from RGB floats | HIGH (source verified) |
| `cmd.hide("everything", sele)` | PyMOL 2.5.0 | Hide all reps for found hiders | HIGH |
| `cmd.show(rep, sele)` | `pymol/viewing.py:491` | Show specific rep for found hiders | HIGH (cited in mutation.py:248,479) |
| `cmd.color(name, sele)` | PyMOL 2.5.0 | Apply color to found hiders | HIGH (used throughout game.py) |
| `QtWidgets.QComboBox` | `pymol.Qt` | Found-hider management dropdown | HIGH |
| `QtWidgets.QPushButton` | `pymol.Qt` | Restart + Cleanup buttons | HIGH |
| `backup.restore` | `biochemeleon/backup.py:54` | Restore original object | HIGH (existing, verified) |
| `GameController.cleanup()` | `biochemeleon/game.py:225` | Restore + reset controller | HIGH (existing, verified) |

## Code Examples

### Restart flow (`__init__.py`)
```python
def _on_restart(self):
    """Restart: deactivate wizard + clear log + re-run _on_start (fresh round)."""
    # Wizard lifecycle: deactivate OLD wizard before _on_start creates a NEW one
    # (otherwise mouse_selection_mode stays at 0 + prior-wizard ref is lost)
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate()
        self.game_tab._wizard = None
        if self._controller is not None:
            self._controller._wizard = None
    # Stop any running timer (defensive — may still be running mid-game)
    self.game_tab._timer.stop()
    # Fresh round = clean log
    self.game_tab._info_log.clear()
    # Re-run the full start flow (handles prior-game cleanup + new specs)
    self._on_start()
```

### Cleanup flow (`__init__.py`)
```python
def _on_cleanup(self):
    """Cleanup: restore original + END round (no new hiders)."""
    if self._controller is None:
        return  # no game to clean up
    # Deactivate wizard (restore mouse_selection_mode + prior wizard)
    if self.game_tab._wizard is not None:
        self.game_tab._wizard.deactivate()
        self.game_tab._wizard = None
        self._controller._wizard = None
    # Stop timer
    self.game_tab._timer.stop()
    # Restore original + reset controller state (idempotent if not started)
    self._controller.cleanup()
    # UI reset
    self.game_tab._info_log.clear()
    self.game_tab._timer_label.setText("0:00")
    self.game_tab._remaining_label.setText("Remaining: -")
    self.game_tab._reveal_label.setText("Reveals: 0")
    self._controller = None  # released; Restart re-creates via _on_start
```

### Found-hider dropdown handler (`gui_game.py`)
```python
def _on_found_mgmt(self, mode):
    """Found-hider management dropdown (GAME-08).
    mode: 'hide' / 'show' / 'recolor'"""
    if self._controller is None or not self._controller._started:
        return
    from pymol import cmd
    from .registry import HIDER_STATUS_FOUND
    found = [r for r in self._controller.registry.all()
             if r.status == HIDER_STATUS_FOUND]
    if not found:
        return
    obj = self._controller.target_obj
    ids = [r.id for r in found]
    sele = "%s and id %s" % (obj, "+".join(str(i) for i in ids))
    if mode == 'hide':
        cmd.hide("everything", sele)
    elif mode == 'show':
        # Per-rep show (each found hider may have a different rep)
        by_rep = {}
        for r in found:
            if r.rep is not None:
                by_rep.setdefault(r.rep, []).append(r.id)
        for rep, rep_ids in by_rep.items():
            cmd.show(rep, "%s and id %s" % (obj, "+".join(str(i) for i in rep_ids)))
    elif mode == 'recolor':
        cmd.color(self._controller._found_color, sele)
```

### Color picker handler (`gui_game.py`)
```python
def _on_pick_color(self):
    """Color picker for found-hider highlight (DIFF-04)."""
    from pymol.Qt import QtWidgets
    color = QtWidgets.QColorDialog.getColor()
    if not color.isValid():
        return  # user cancelled
    from pymol import cmd
    r, g, b, _ = color.getRgbF()  # floats 0.0-1.0
    cmd.set_color('found_highlight', [r, g, b])  # viewing.py:2107
    self._controller._found_color = 'found_highlight'
    # Optionally auto-recolor existing found hiders
    self._on_found_mgmt('recolor')
```

### Pure helper for TDD (`registry.py`)
```python
def build_found_selection(records, object_name):
    """Build a PyMOL selection string for all FOUND hiders.
    Pure (no cmd, no Qt) — WSL-unit-testable.

    Returns '<object_name> and id X+Y+Z' for found records, or None if none found.
    """
    found_ids = [r.id for r in records if r.status == HIDER_STATUS_FOUND]
    if not found_ids:
        return None
    return "%s and id %s" % (object_name, "+".join(str(i) for i in found_ids))
```

## Open Questions

1. **`cmd.set_color` re-define propagation** — does re-calling `set_color('found_highlight', new_rgb)` update atoms already colored `'found_highlight'`? LOW confidence (training data only). Safe approach: always explicitly re-apply `cmd.color`. The headless smoke can test this (set_color + color + iterate color index, then set_color again + iterate without re-applying color, check if index changed).

2. **Countdown cancellation on Restart** — if the user clicks Restart during the 3-2-1 countdown, the pending `singleShot` chain (gui_game.py:119-125) will fire `_begin_play` on the NEW controller. LOW risk (3-second window). Simplest fix: store the `singleShot` timer ID + cancel it in `_on_restart`. Or: have `_begin_play` verify the controller hasn't changed. The planner can defer this to human-verify (if it's not a problem in practice, don't fix it).

3. **Cleanup button: keep `_controller` or set `None`?** — Recommendation is `None` (cleaner; Restart re-creates via `_on_start`). But if the planner wants Cleanup to be reversible (undo cleanup), keep the controller. Given no undo in PyMOL and the spec says Cleanup "removes" game-generated content, `None` is the right choice.

## Sources

### Primary (HIGH confidence)
- `biochemeleon/game.py` — GameController source (read in full, 271 lines)
- `biochemeleon/gui_game.py` — GameTab source (read in full, 195 lines)
- `biochemeleon/__init__.py` — PluginDialog source (read in full, 231 lines)
- `biochemeleon/registry.py` — HiderRegistry source (read in full, 272 lines)
- `biochemeleon/backup.py` — backup module (read in full, 85 lines)
- `biochemeleon/mutation.py` — mutation module (read in full, 620 lines)
- `biochemeleon/wizard.py` — PickWizard source (read in full, 83 lines)
- `tmp/pymol-src/modules/pymol/Qt/__init__.py` — Qt wrapper (read in full, 97 lines) — confirms QtWidgets re-export from PyQt5/PySide2
- `tmp/pymol-src/modules/pymol/viewing.py:2107-2124` — `set_color` signature verified
- `tests/test_game_controller.py` — mock pattern for controller tests (read in full, 486 lines)
- `smoke/phase6_smoke.py` — headless smoke pattern (read in full, 131 lines)
- `.planning/REQUIREMENTS.md` — requirement definitions (read in full)
- `spec.md` — UI standards + button placement (read in full)

### Secondary (MEDIUM confidence)
- PyMOL picking requires visible geometry (from wizard.py do_pick/do_select pattern + training data) — hidden atoms unclickable
- `cmd.set_color` re-define propagation behavior — training data only, LOW confidence, safe approach documented

## Metadata

**Confidence breakdown:**
- Current state analysis: HIGH — all claims verified by reading source with file:line citations
- Restart design: HIGH — `_on_start` already handles the flow; wizard lifecycle bug identified + fix documented
- Cleanup design: HIGH — cleanup() is existing + verified; UI reset is straightforward
- Found-hider dropdown: HIGH — selector pattern from mutation.py:412-415; cmd.hide/show/color are standard
- Color picker: HIGH — QColorDialog availability verified from PyMOL source; set_color signature verified
- Button guards: HIGH — follows existing pattern (gui_game.py:78)
- TDD candidates: HIGH — pure helpers are clearly pure (no cmd, no Qt)

**Research date:** 2026-08-11
**Valid until:** 2026-09-11 (30 days — PyMOL 2.5.0 is a fixed target; codebase patterns are stable unless Phase 8/11 refactor the controller, which is not planned)
