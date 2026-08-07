# Phase 4: MVP Core Loop (Sphere) — Research

**Researched:** 2026-08-08
**Domain:** PyMOL 2.5.0 Wizard API (click-to-find), QTimer (game timer), sphere hider generation, Qt Game tab UI
**Confidence:** HIGH (Wizard API verified against PyMOL 2.5.0 source at `tmp/pymol-src/modules/pymol/wizard/__init__.py` + `wizarding.py` + `querying.py` + 8 built-in wizards; QTimer from PyQt5 docs + PITFALLS.md Pitfall 6; sphere generator from `querying.py` get_extent + Phase 3 proven foundation)

---

## 1. Executive Summary

Phase 4 builds the **player-facing core loop** on top of the Phase 3 proven foundation (registry/backup/mutation/game.py). The four pieces are: (1) a **PickWizard** (`pymol.wizard.Wizard` subclass) that receives `do_pick` callbacks on atom clicks and forwards the picked atom's stable `id` to `GameController.on_pick`; (2) a **sphere generator** (pure geometry function producing `(pos, rep)` specs, fed into the proven `GameController.start(hider_specs)`); (3) a **Game tab UI** (QTextEdit rolling log + QLabel timer + QLabel remaining count, driven by a 1 Hz QTimer); (4) **Start button wiring** (resolve target → snapshot → generate → switch tab → 3-2-1 countdown → activate wizard → start timer).

**The highest-risk item is the Wizard `do_pick` → `pk1` → `cmd.identify(mode=1)` → registry lookup chain.** This is verified against the PyMOL 2.5.0 source: `do_pick(self, bondFlag)` is the base-class signature (wizard/__init__.py:76); the picked atom lands in `pk1`; `cmd.identify("pk1", mode=1)` returns `[(model, id)]` where `id` is the SAME stable integral identifier that `mutation.insert_hider` returns via `cmd.identify(..., mode=0)` (querying.py:1269-1300). The `cmd.index("pk1")` alternative returns `(model, index)` where `index` is FRAGILE — the docstring itself warns "use integral atom identifiers instead of indices" (querying.py:1313-1317). **Use `cmd.identify("pk1", mode=1)`, NEVER `cmd.index("pk1")`.**

**Primary recommendation:** Build the PickWizard following the canonical built-in wizard pattern (save `mouse_selection_mode` → set to 0/atomic → override `do_pick` → read `pk1` via `cmd.identify(mode=1)` → `cmd.unpick()` → restore on cleanup). Split the sphere generator into a pure `generators.py` (WSL-testable geometry) + the existing `game.py` start loop (cmd-coupled insertion). Wire the Game tab with QTextEdit + QLabel + QTimer, using a callback interface (`on_log`/`on_remaining_changed`/`on_win`) so the GameController stays testable. The 3-2-1 countdown uses `QTimer.singleShot` (never `time.sleep`). The winning message uses `QMessageBox.information` (modal child dialog — allowed per AGENTS.md).

---

## A. Wizard API (Q1-Q8) — HIGHEST PRIORITY

### Q1: do_pick signature

**Verified:** `def do_pick(self, bondFlag)` — the base-class signature in `pymol/wizard/__init__.py:76`.

```python
# tmp/pymol-src/modules/pymol/wizard/__init__.py:76
def do_pick(self,bondFlag):
    return None
```

- The parameter name is `bondFlag` (a boolean/int: 0 = atom pick, nonzero = bond pick).
- The mtsslWizard override uses `def do_pick(self, picked_bond):` (mtsslWizard.py:332) — the param name in the override is flexible, but conventionally `bondFlag`.
- **Returns `None`** — no meaningful return value. The return value is ignored by PyMOL.
- All 8+ built-in wizards use `def do_pick(self, bondFlag):` (measurement.py:307, distance.py:148, mutagenesis.py:715, pair_fit.py:152, appearance.py:186, label.py:79, charge.py:142, box.py:420, filter.py:115, density.py:197, cleanup.py:164, nucmutagenesis.py:160).

**Recommendation:** `def do_pick(self, bondFlag):` — follow the base-class convention exactly.

### Q2: Reading the picked atom's identity (CRITICAL — must match registry key)

**Verified:** After `do_pick` fires, the picked atom is in `pk1` (the single-atom pick selection). The canonical way to read its identity is `cmd.identify("pk1", mode=1)`.

```python
# tmp/pymol-src/modules/pymol/querying.py:1269-1300
def identify(selection="(all)", mode=0, quiet=1, *, _self=cmd):
    '''
    mode 0: only return a list of identifiers (default)
    mode 1: return a list of tuples of the object name and the identifier
    '''
    r = _cmd.identify(_self._COb,"("+str(selection)+")",int(mode))
    return r
```

- **`cmd.identify("pk1", mode=0)`** → returns `[id]` (list of ints — just the stable atom id).
- **`cmd.identify("pk1", mode=1)`** → returns `[(model, id)]` (list of `(object_name, id)` tuples).
- The `id` returned here is the **SAME stable integral identifier** that `mutation.insert_hider` returns via `cmd.identify(..., mode=0)`. This is the value the registry keys on as `(object, id)`.
- **`cmd.id_atom("pk1")`** → returns the single id (or raises `CmdException` if 0 or >1 atoms). Convenience wrapper (querying.py:1235-1267).

**NEVER use `cmd.index("pk1")`:**
```python
# tmp/pymol-src/modules/pymol/querying.py:1302-1330
def index(selection="(all)", quiet=1, *, _self=cmd):
    '''
    NOTE
      Atom indices are fragile and will change as atoms are added
      or deleted.  Whenever possible, use integral atom identifiers
      instead of indices.
    '''
    r = _cmd.index(_self._COb,"("+str(selection)+")",0)
    return r  # returns [(model, index)] — index is FRAGILE, NOT id
```

The `cmd.index` docstring explicitly warns against using indices. The registry keys on `id` (stable), NOT `index` (fragile). Using `cmd.index("pk1")` would return the WRONG identifier — it would not match the registry keys.

**How the built-in measurement wizard reads the pick:**
```python
# tmp/pymol-src/modules/pymol/wizard/measurement.py:307-310
def do_pick(self,bondFlag):
    (what,code) = self.get_selection_name()
    self.cmd.select("pk1", code + "(pk1)")  # refine pk1 by mouse_selection_mode
    # ... then uses (pk1) for distance measurement
```

The measurement wizard reads from `pk1`, NOT from `(sele)`. The mtsslWizard reads from `(sele)` (mtsslWizard.py:348) — but `(sele)` may contain atoms from a prior selection, while `pk1` is exactly the one atom just picked. **For our click-to-find game, `pk1` is the right choice.**

**Recommended do_pick implementation:**
```python
def do_pick(self, bondFlag):
    # Read the picked atom's (model, id) from pk1
    pairs = cmd.identify("pk1", mode=1)  # [(model, id)]
    cmd.unpick()  # clear pk1 for next pick (measurement.py:468 pattern)
    if not pairs:
        return  # empty pick (shouldn't happen, but defensive)
    model, aid = pairs[0]
    if model != self.target_object:
        # clicked a non-target object — miss, no-op
        return
    self.controller.on_pick(aid)  # forward to GameController
    cmd.refresh_wizard()  # update prompt/panel
```

### Q3: Activate/deactivate wizard

**Verified:** `pymol/wizarding.py:110-118`:
```python
def set_wizard(wizard=None, replace=0, _self=cmd): # INTERNAL
    r = DEFAULT_ERROR
    try:
        _self.lock(_self)
        r = _cmd.set_wizard(_self._COb, wizard, replace)
    finally:
        _self.unlock(r, _self)
    ...
```

- **`cmd.set_wizard(wiz)`** — activates the wizard (passes the wizard object to the C function).
- **`cmd.set_wizard()`** — deactivates (default param `wizard=None`, passes `None` to C).
- **`cmd.set_wizard(None)`** — identical to `cmd.set_wizard()` (same default `None`).
- There is **NO difference** between `cmd.set_wizard()` and `cmd.set_wizard(None)` — both pass `None`.

All built-in wizards use `cmd.set_wizard()` (no args) to deactivate (measurement.py:202, mtsslWizard.py:253).

### Q4: Save/restore pre-existing wizard

**Verified:** `pymol/wizarding.py:156-164`:
```python
def get_wizard(_self=cmd): # INTERNAL
    r = DEFAULT_ERROR
    try:
        _self.lock(_self)
        r = _cmd.get_wizard(_self._COb)
    finally:
        _self.unlock(r, _self)
    if _self._raising(r,_self): raise pymol.CmdException
    return r
```

- **`cmd.get_wizard()`** returns the current wizard object, or **`None`** if no wizard is active. The C function `_cmd.get_wizard` returns the wizard or `None`; `_raising` only raises on error codes, not on `None`.
- Save: `self._saved_wizard = cmd.get_wizard()` before activating our wizard.
- Restore: `cmd.set_wizard(self._saved_wizard)` — if `_saved_wizard` is `None`, this clears the wizard (same as `cmd.set_wizard()`). If a wizard was active, it restores it.

**Recommended activate/deactivate pattern:**
```python
def activate(self):
    self._saved_wizard = cmd.get_wizard()  # save (None if no wizard active)
    cmd.set_wizard(self)
    # also save + set mouse_selection_mode (see Q6)

def deactivate(self):
    cmd.set_wizard(self._saved_wizard)  # restore (or clear if None)
    # also restore mouse_selection_mode
```

### Q5: Does do_pick fire on every click?

**Verified:** The Wizard base class `get_event_mask()` returns `event_mask_pick + event_mask_select` by default (wizard/__init__.py:55-56):
```python
def get_event_mask(self):
    return Wizard.event_mask_pick + Wizard.event_mask_select
```

`do_pick` fires on **atom picks** (when the user clicks an atom and a pick is registered). `do_select` fires on selections. Both fire only in picking-capable mouse modes.

**To filter to only the target object's atoms:** Use `cmd.identify("pk1", mode=1)` which returns `[(model, id)]` — check if `model == self.target_object`. If not, the click was on a non-target object (ignore/miss). The mtsslWizard does this by iterating objects and checking which contains the sele (mtsslWizard.py:353-358); our approach using `cmd.identify(mode=1)` is simpler and more direct.

`do_pick` fires on clicks on ANY object's atoms (not just the target). The filtering is our responsibility in the `do_pick` handler.

### Q6: Mouse mode — does the wizard force picking mode?

**Verified:** Activating a wizard does **NOT** automatically put the viewer in picking mode. Every built-in wizard explicitly sets `mouse_selection_mode`:

```python
# Canonical pattern from measurement.py:96-97
self.selection_mode = self.cmd.get_setting_int("mouse_selection_mode")  # save
self.cmd.set("mouse_selection_mode", 0)  # 0 = atomic (single-atom selection)

# cleanup (measurement.py:212)
self.cmd.set("mouse_selection_mode", self.selection_mode)  # restore
```

This pattern is used by ALL built-in wizards:
| Wizard | mouse_selection_mode | Source |
|--------|---------------------|--------|
| measurement | 0 (atomic) | measurement.py:97 |
| distance | 0 (atomic) | distance.py:70 |
| pair_fit | 0 (atomic) | pair_fit.py:25 |
| appearance | 0 (atomic) | appearance.py:69 |
| label | 0 (atomic) | label.py:34 |
| mutagenesis | 1 (residue) | mutagenesis.py:91 |
| nucmutagenesis | 1 (residue) | nucmutagenesis.py:97 |
| mtsslWizard | 1 (residue) | mtsslWizard.py:297 |

`mouse_selection_mode` ranges 0-6 (controlling.py:640-646: `if sm>6: sm = 0; if sm<0: sm = 6`). Mode 0 = atomic (single atom), mode 1 = residue.

**For our game: use mode 0 (atomic)** — each click selects exactly one atom, so we can match it against the registry by `id`.

The `button_mode` setting (controlling.py:196) controls the overall mouse mode (Viewing/Picking/Editing). The built-in wizards do NOT change `button_mode` — they only change `mouse_selection_mode`. This means: when a wizard is active with `event_mask_pick`, PyMOL routes pick events to the wizard regardless of `button_mode`. The user can left-click to pick (in the default 3-Button Viewing mode, left-click picks an atom when a wizard is active).

[MEDIUM confidence on the left-click=pick behavior] — the C-level pick dispatch isn't visible in the Python source. But the empirical evidence is conclusive: all 8+ built-in wizards work with just `mouse_selection_mode` set, without changing `button_mode`. The user clicks an atom and `do_pick` fires.

**Recommended wizard init/cleanup:**
```python
class PickWizard(Wizard):
    def __init__(self, controller, target_object, _self=cmd):
        Wizard.__init__(self, _self)
        self.controller = controller
        self.target_object = target_object
        self._saved_wizard = None
        # Save + set mouse mode (canonical pattern)
        self._saved_selection_mode = cmd.get_setting_int("mouse_selection_mode")
        cmd.set("mouse_selection_mode", 0)  # 0 = atomic
        cmd.deselect()

    def cleanup(self):
        # Restore mouse mode (canonical pattern)
        cmd.set("mouse_selection_mode", self._saved_selection_mode)
```

### Q7: get_panel() format

**Verified:** `get_panel()` returns a list of `[type, label, command]` entries. The panel appears in the right-side viewer menu.

```python
# Wizard base class (wizard/__init__.py:52-53)
def get_panel(self):
    return self.panel  # defaults to None

# Measurement wizard (measurement.py:195-203)
def get_panel(self):
    return [
        [ 1, 'Measurement',''],                                    # type 1 = title/header
        [ 3, self.mode_name[self.mode],'mode'],                    # type 3 = submenu (refs self.menu[tag])
        [ 2, 'Delete Last Object' , 'cmd.get_wizard().delete_last()'],  # type 2 = button (executes command string)
        [ 2, 'Done','cmd.set_wizard()'],                           # type 2 = button (deactivates wizard)
    ]
```

Panel entry types:
- `1` = title/header (non-interactive label)
- `2` = button (executes the command string when clicked)
- `3` = submenu (references `self.menu[tag]` for a nested menu)

The command string is evaluated as a PyMOL command. `cmd.get_wizard()` returns the active wizard, so `cmd.get_wizard().controller.on_pick(...)` works from the panel.

**Recommended get_panel for bioCHEMeleon:**
```python
def get_panel(self):
    return [
        [1, 'bioCHEMeleon', ''],
        [2, 'Done (quit game)', 'cmd.get_wizard().deactivate()'],
    ]
```

### Q8: Does do_pick fire on drag-to-rotate?

**Evidence:** [MEDIUM-HIGH confidence] — `do_pick` fires on PICKS, not on drags. The built-in measurement/distance/mutagenesis wizards do NOT implement any drag-disambiguation logic — they just override `do_pick` and it works in practice. PyMOL internally distinguishes click from drag before calling `do_pick` (a drag-to-rotate does not register a pick; only a click without significant mouse movement registers a pick).

The RESEARCH SUMMARY flagged this as MEDIUM: "Disambiguate click vs drag (mouse displacement + time threshold)." However, the built-in wizards' complete lack of drag handling is strong evidence that PyMOL handles this internally. The PITFALLS.md Pitfall 5 mentions drag disambiguation, but also says "the Wizard `do_pick` fires on picks" — and the recommended solution is to use the Wizard pattern (which we're doing).

**Recommendation:** Do NOT implement custom drag disambiguation. Trust PyMOL's built-in click-vs-drag distinction (as all built-in wizards do). If spurious picks are observed during human-verify testing, add a displacement threshold as a fallback — but this is unlikely to be needed.

---

## B. QTimer for the Game Timer (Q9-Q11)

### Q9: 1 Hz QTimer pattern

**Verified:** `QTimer` is available via `from pymol.Qt import QtCore`. The pattern:

```python
from pymol.Qt import QtCore

# In GameTab.__init__ or start:
self._timer = QtCore.QTimer()
self._timer.setInterval(1000)  # 1 Hz (1000 ms)
self._timer.timeout.connect(self._on_tick)

# Start the timer:
self._timer.start()
# Or: self._timer.start(1000)  # start with 1000ms interval

# Stop the timer:
self._timer.stop()
```

`QTimer.timeout` is a signal that fires on each interval. Connect it to a slot (callback). The timer runs on the Qt main event loop.

### Q10: QTimer thread safety

**Verified (HIGH confidence):** QTimer fires on the **main Qt event loop thread**. PyMOL's `cmd.*` calls also run on the main thread. Therefore, QTimer callbacks can safely:
- Call `cmd.*` (e.g., `cmd.color`, `cmd.count_atoms`)
- Update Qt widgets (e.g., `label.setText(...)`)

This is confirmed by PITFALLS.md Pitfall 6: "Golden rule: all `cmd.*` calls happen on the GUI main thread. For the timer: use `QTimer` with a 1 s tick on the main thread (no threading)."

**NEVER use `threading.Thread` with `cmd.*` calls** — deadlocks/segfaults (Pitfall 6).

### Q11: Elapsed time tracking

**Recommended:** `time.time()` at start, compute delta on each tick.

```python
import time

# On game start (after countdown):
self._start_time = time.time()
self._timer.start(1000)

# On each tick:
def _on_tick(self):
    elapsed = time.time() - self._start_time
    mins = int(elapsed) // 60
    secs = int(elapsed) % 60
    self._timer_label.setText("%d:%02d" % (mins, secs))

# On win:
self._timer.stop()
elapsed = time.time() - self._start_time
```

This is drift-free (each tick computes from the absolute start time, not from accumulated ticks). A counter variable (`self._elapsed += 1` each tick) would drift if ticks are delayed by UI activity.

---

## C. Sphere Hider Generator (Q12-Q15)

### Q12: Bounding box / get_extent

**Verified:** `cmd.get_extent(selection)` returns `[[minX, minY, minZ], [maxX, maxY, maxZ]]` — a list of two 3-element lists.

```python
# tmp/pymol-src/modules/pymol/querying.py:1371-1392
def get_extent(selection="(all)", state=ALL_STATES, quiet=1, *, _self=cmd):
    '''
    "get_extent" returns the minimum and maximum XYZ coordinates of a
    selection as an array:
     [ [ min-X , min-Y , min-Z ],[ max-X, max-Y , max-Z ]]
    '''
    r = _cmd.get_min_max(_self._COb, str(selection), int(state)-1)
    return r
```

Usage: `extent = cmd.get_extent(object)` → `extent[0]` = `[xmin, ymin, zmin]`, `extent[1]` = `[xmax, ymax, zmax]`.

### Q13: Algorithm for placing N sphere hiders

**Spec:** "Sphere hiders — place anywhere in the bounding region" (HIDER-04).

**MVP algorithm (simplest, spec-compliant):** Random uniform points within the bounding box.

```python
import random

def generate_sphere_positions(extent, n, seed=None):
    """Generate n random [x,y,z] positions within the bounding box.
    
    extent: [[xmin,ymin,zmin], [xmax,ymax,zmax]] from cmd.get_extent
    n: number of positions to generate
    seed: optional int for deterministic output (testability)
    Returns: list of [x,y,z] lists
    """
    rng = random.Random(seed)
    (xmin, ymin, zmin) = extent[0]
    (xmax, ymax, zmax) = extent[1]
    positions = []
    for _ in range(n):
        positions.append([
            rng.uniform(xmin, xmax),
            rng.uniform(ymin, ymax),
            rng.uniform(zmin, zmax),
        ])
    return positions
```

**Design rationale:**
- "Anywhere in the bounding region" = uniform random in the bounding box. No distance constraint to real atoms.
- Hiders in empty space within the bounding box are FINDABLE (they're visible as spheres) but not trivially obvious (the player has to scan the whole volume).
- No need to avoid overlapping real atoms — for sphere hiders, being near/inside the atom cloud is good (harder to spot).
- The `seed` parameter makes the function deterministic for unit testing.

**Future improvement (Phase 5+):** Place near real atoms (pick N random atom positions + small offset) for better blending. But for MVP, uniform random is spec-compliant and simplest.

### Q14: Generator purity — split pure geometry + cmd-coupled insertion

**Recommended:** YES, split (mirrors the Phase 3 registry.py pure / mutation.py cmd pattern).

- **Pure geometry function** (WSL-testable): `generate_sphere_positions(extent, n, seed=None) -> list of [x,y,z]`. stdlib `random` only. NO `from pymol`. Unit-testable in WSL.
- **Cmd-coupled wiring** (NOT WSL-testable): `game.py` (or a thin helper) calls `cmd.get_extent(object)`, passes the extent to the pure function, gets back positions, and loops `mutation.insert_hider(object, pos, rep, handle)` for each — exactly what `GameController.start(hider_specs)` already does.

The pure function goes in a new `biochemeleon/generators.py` module (pure: stdlib only, NO `from pymol`, NO `from pymol.Qt`). The cmd-coupled wiring stays in `game.py` (already cmd-coupled).

**numpy availability:** numpy IS available (PyMOL build/run requirement, confirmed in STACK.md). But for the MVP sphere generator, `random.uniform` suffices — numpy is overkill for uniform random sampling. Use numpy if the geometry gets more complex (Phase 5 line/stick/cartoon).

### Q15: Sphere hider visibility

**Verified:** Pseudoatoms DO render as spheres when the 'spheres' representation is shown. `mutation.insert_hider` creates a pseudoatom with `elem='PS'` (creating.py:1082). To make it visible:

```python
cmd.show('spheres', f"{object} and segi GAME")
```

Or per-hider during insertion:
```python
cmd.show('spheres', f"{object} and name {handle}")
```

The `elem='PS'` gives the pseudoatom a VDW radius, so it renders as a sphere. For MVP, `elem='PS'` is fine — the hider is a visible sphere the player must find by clicking. Blending quality (matching real element colors/sizes) is a Phase 5+ improvement.

**PITFALLS.md Pitfall 3 caveat:** Pseudoatom defaults make hiders trivially filterable (`elem='PS'`, `hetatm=1`). The current `insert_hider` already overrides `resn='HIDER'`, `chain='H'`, `segi='GAME'`, `b=-999` — so hiders ARE filterable by `segi GAME` (which is our sentinel). This is intentional (cleanup uses `segi GAME`). For Phase 4, the hider just needs to be VISIBLE and CLICKABLE — not visually blended. Visual blending is the Phase 5 line/stick/cartoon work.

---

## D. Found-hider Visual Feedback (Q16-Q18)

### Q16: Recoloring/hiding a single atom

**Verified:** The `id` selector is valid in PyMOL 2.5.0 (selecting.py:142: `'id': 1` in the selector keyword dictionary).

```python
# Recolor a single atom by its stable id:
cmd.color('green', f"{object} and id {aid}")

# Hide the spheres rep of a single atom:
cmd.hide('spheres', f"{object} and id {aid}")
```

**IMPORTANT — `id` selector (lowercase) in selection expressions vs `ID` (uppercase) in iterate expressions:**
- In **selection expressions** (e.g., `cmd.color(color, "obj and id 123")`): use **lowercase `id`** — it's a selector keyword.
- In **iterate expressions** (e.g., `cmd.iterate(sele, "stored.append(ID)")`): use **UPPERCASE `ID`** — it's a Python symbol exposed by iterate (Phase 3 discovery).

These are different contexts with different casing rules. The `id N` selector in `cmd.color`/`cmd.hide` is correct (lowercase).

### Q17: Color choice — recolor vs hide

**Spec:** "Hiders with a 'found' status either change in color or becomes hidden" (spec.md:44).

**Recommended for MVP: RECOLOR** to a distinct color (e.g., `'green'` or `'brightorange'`).

Rationale:
- Recoloring lets the player SEE which hiders they've already found (progress feedback).
- Hiding makes found hiders vanish — the player can't see their progress, which may be confusing.
- Recoloring is simpler to implement (`cmd.color` — one call, no rep management).
- Phase 7 adds the found-hider management dropdown (hide/show/recolor) for full control.

```python
cmd.color('green', f"{self.target_obj} and id {picked_id}")
```

### Q18: Single-atom recolor without affecting the rest

**Verified:** `cmd.color(color, f"{object} and id {aid}")` recolors JUST that one atom. The `id N` selector matches exactly one atom (the atom with `id == N`). Other atoms in the object are unaffected. This is the standard PyMOL single-atom operation.

---

## E. Start Button Wiring (Q19-Q22)

### Q19: collect_state() fields

**Verified from gui_setup.py:432-450:**
```python
def collect_state(self):
    return {
        "format": SETUP_FORMAT,
        "target_mode": "loaded" | "fetch" | "demo",
        "selected_object": str,        # loaded object name (mode='loaded')
        "pdb_code": str,               # PDB code (mode='fetch')
        "demo_id": str,                # manifest id (mode='demo')
        "hider_count": int,
        "lock_scene": bool,
        "per_rep": {rep: count},       # checked reps with counts (empty = random)
        "difficulty_easy": bool,
        "lock_source": bool,
        "pdb_pool": [str],
    }
```

For Phase 4 MVP (sphere-only), the Start button needs:
- `target_mode` — to resolve the target object
- `selected_object` / `pdb_code` / `demo_id` — the target identifier
- `hider_count` — how many sphere hiders to generate
- `per_rep` — for sphere-only MVP, this is either empty (random) or `{'spheres': N}`. If empty and lock_scene is False, all hiders are spheres (the only generator in Phase 4).
- `difficulty_easy` — controls whether per-rep counts are shown (MVP: total only is fine)

### Q20: Target resolution flow

**Verified from demos.py:**
- mode='loaded': `target_obj = state["selected_object"]` (already loaded in PyMOL)
- mode='fetch': `target_obj = demos.fetch_pdb(state["pdb_code"])` (returns object name or None on failure)
- mode='demo': `target_obj = demos.load_demo(state["demo_id"])` (returns object name or None on failure)

If target resolution returns `None`, show a `QMessageBox.warning` and abort Start.

**Flow:**
```python
def _on_start(self):
    state = self.setup_tab.collect_state()
    # 1. Resolve target
    mode = state["target_mode"]
    if mode == "loaded":
        target_obj = state["selected_object"]
        if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
            QMessageBox.warning(self, "No object", "Please select a loaded object.")
            return
    elif mode == "fetch":
        target_obj = demos.fetch_pdb(state["pdb_code"])
        if target_obj is None:
            QMessageBox.warning(self, "Fetch failed", "...")
            return
    elif mode == "demo":
        target_obj = demos.load_demo(state["demo_id"])
        if target_obj is None:
            QMessageBox.warning(self, "Demo failed", "...")
            return
    # 2. Generate sphere hider specs
    extent = cmd.get_extent(target_obj)
    positions = generators.generate_sphere_positions(extent, state["hider_count"])
    hider_specs = [(pos, 'spheres') for pos in positions]
    # 3. Start the game (snapshot → insert → register)
    self._controller = GameController(target_obj)
    self._controller.start(hider_specs)
    # 4. Show hiders as spheres
    cmd.show('spheres', f"{target_obj} and segi GAME")
    # 5. Switch to Game tab
    self.tabs.setCurrentWidget(self.game_tab)
    # 6. 3-2-1 countdown → activate wizard → start timer
    self.game_tab.start_countdown(self._controller)
```

### Q21: 3-2-1 countdown

**Recommended:** `QTimer.singleShot` chain (NEVER `time.sleep` — it blocks the Qt event loop and freezes PyMOL).

```python
def start_countdown(self, controller):
    self._controller = controller
    self._countdown_step(3)

def _countdown_step(self, n):
    if n > 0:
        self._log("{}".format(n))
        QTimer.singleShot(1000, lambda: self._countdown_step(n - 1))
    else:
        self._log("GO!")
        self._begin_play()

def _begin_play(self):
    # Activate the PickWizard
    self._wizard = PickWizard(self._controller, self._controller.target_obj)
    self._wizard.activate()
    # Start the timer
    self._start_time = time.time()
    self._timer.start(1000)
    self._controller.set_callbacks(
        on_log=self._log,
        on_remaining_changed=self._update_remaining,
        on_win=self._on_win,
    )
```

### Q22: Tab switching + controller wiring

**Verified from __init__.py:** `PluginDialog` owns `self.tabs` (QTabWidget), `self.setup_tab`, `self.game_tab`. Tab switching: `self.tabs.setCurrentWidget(self.game_tab)`.

**Wiring pattern (callback interface — keeps GameController testable):**
- `PluginDialog` owns `GameController` + `SetupTab` + `GameTab` + `PickWizard`.
- `SetupTab` Start button → `PluginDialog._on_start()`.
- `PluginDialog._on_start()` → resolve target → generate specs → `GameController.start(hider_specs)` → switch tab → `GameTab.start_countdown()`.
- `GameTab.start_countdown()` → countdown → `_begin_play()` → create + activate `PickWizard` → register callbacks → start timer.
- `PickWizard.do_pick()` → `GameController.on_pick(aid)`.
- `GameController.on_pick()` → registry lookup → mark_found → `cmd.color` → callbacks (`on_log`, `on_remaining_changed`) → if all found: `win()` → `on_win` callback → `GameTab._on_win()` → stop timer → QMessageBox.

**GameController callback interface:**
```python
class GameController:
    def set_callbacks(self, on_log=None, on_remaining_changed=None, on_win=None):
        self._on_log = on_log or (lambda msg: None)
        self._on_remaining_changed = on_remaining_changed or (lambda remaining: None)
        self._on_win = on_win or (lambda elapsed: None)
```

This keeps the controller testable (pass mock callbacks in WSL tests) and avoids importing Qt in the controller.

---

## F. Game Tab UI (Q23-Q26)

### Q23: Rolling info log widget

**Recommended:** `QTextEdit` (read-only, append-only).

```python
self._info_log = QtWidgets.QTextEdit()
self._info_log.setReadOnly(True)
# Append a line (auto-scrolls to bottom):
self._info_log.append("Found one! 3 remaining")
```

`QTextEdit.append(text)` adds a paragraph and auto-scrolls. `setReadOnly(True)` prevents user editing. This is the simplest append-only log widget.

Alternative: `QListWidget` — but that's overkill for a text log. `QTextEdit` is simpler and more natural for a rolling info box.

### Q24: Remaining-hiders count

**Recommended:** `QLabel` updated on each find via the `on_remaining_changed` callback.

```python
self._remaining_label = QtWidgets.QLabel("Remaining: ?")

def _update_remaining(self, remaining):
    self._remaining_label.setText("Remaining: %d" % remaining)
```

The count comes from the GameController, which computes it from the registry:
```python
def _remaining(self):
    return sum(1 for r in self.registry.all() if r.status == HIDER_STATUS_HIDDEN)
```

For Phase 4 MVP (sphere-only, total count only): a single QLabel showing "Remaining: N". Phase 5+ can add per-rep counts (using `registry.counts_by_rep()`) when `difficulty_easy` is True.

### Q25: Timer display

**Recommended:** `QLabel` showing "M:SS" updated each second by QTimer.

```python
self._timer_label = QtWidgets.QLabel("0:00")

def _on_tick(self):
    elapsed = time.time() - self._start_time
    mins = int(elapsed) // 60
    secs = int(elapsed) % 60
    self._timer_label.setText("%d:%02d" % (mins, secs))
```

### Q26: Winning message

**Recommended:** `QMessageBox.information` — a modal child dialog (allowed per AGENTS.md: `QMessageBox.exec_()` on child dialogs IS allowed).

```python
def _on_win(self, elapsed):
    self._timer.stop()
    mins = int(elapsed) // 60
    secs = int(elapsed) % 60
    QtWidgets.QMessageBox.information(
        self, "You win!",
        "You found all hiders in %d:%02d!" % (mins, secs))
```

The main plugin dialog stays modeless; only the winning message is modal (brief, celebratory). After the player dismisses the message, the Game tab shows the final state. The wizard should be deactivated (or left active for the player to admire the result — design choice; recommend deactivate on win).

---

## G. GameController Extensions (Q27-Q30)

### Q27: New start() signature

**Recommendation:** Keep `start(hider_specs)` UNCHANGED. The caller (PluginDialog) produces `hider_specs` from the setup dict + sphere generator.

Rationale: `start(hider_specs)` is already proven by the Phase 3 smoke test (24/24 ALL PASSED). It does snapshot → insert loop → register. Changing its signature would break the proven contract. Instead:
- `PluginDialog._on_start()` resolves the target, calls `generators.generate_sphere_positions()`, builds `hider_specs = [(pos, 'spheres') for pos in positions]`, and calls `GameController.start(hider_specs)`.
- New methods `on_pick(aid)` and `win()` are ADDED to GameController.
- New method `set_callbacks(on_log, on_remaining_changed, on_win)` registers the GUI callbacks.

### Q28: on_pick(picked_id) logic

```python
def on_pick(self, picked_id):
    """Handle a picked atom. Called by PickWizard.do_pick."""
    rec = self.registry.get(self.target_obj, picked_id)
    if rec is None:
        # Miss — clicked a non-hider atom
        self._on_log("Miss!")
        return
    if rec.status == HIDER_STATUS_FOUND:
        # Already found — no-op
        self._on_log("Already found!")
        return
    # Found a hidden hider!
    self.registry.mark_found(self.target_obj, picked_id)
    cmd.color('green', f"{self.target_obj} and id {picked_id}")
    remaining = self._remaining()
    self._on_log("Found one! %d remaining" % remaining)
    self._on_remaining_changed(remaining)
    if remaining == 0:
        self.win()
```

**Key points:**
- `registry.get(object, id)` returns `None` for non-hiders → miss (no-op, no harm). This is the "clicking a non-hider does nothing harmful" requirement (LOOP-01).
- `registry.mark_found` sets `status = 'found'` (LOOP-02: single source of truth).
- `cmd.color('green', ...)` recolors the found hider (visual feedback).
- `self._remaining()` counts hidden hiders → drives the remaining counter.
- Win check: `if remaining == 0: self.win()`.

### Q29: win() — state transitions

```python
def win(self):
    """All hiders found — stop timer, notify GUI, deactivate wizard."""
    elapsed = time.time() - self._start_time
    self._on_win(elapsed)
    # The GUI callback (_on_win) stops the QTimer and shows QMessageBox
    # Deactivate the wizard (restore user's prior wizard + mouse mode)
    if self._wizard:
        self._wizard.deactivate()
        self._wizard = None
    # Game is over — _started stays True until cleanup() is called
```

State transitions:
- During play: `_started=True`, wizard active, timer running.
- On win: timer stops, wizard deactivates, `_started` stays True (the hiders are still in the object; cleanup() removes them when the player is ready).
- On cleanup (player clicks Cleanup/Restart): `GameController.cleanup()` removes hiders, discards backup, resets `_started=False`.

### Q30: Callback interface vs direct GameTab reference

**Recommended:** Callback interface (`on_log`, `on_remaining_changed`, `on_win`).

Rationale:
- Keeps GameController testable (pass mock callbacks in WSL unit tests — no Qt needed).
- Avoids importing Qt widgets in the controller (the controller is cmd-coupled, not Qt-coupled).
- Follows the ARCHITECTURE.md pattern: "GUI → controller method calls, controller → GUI via callbacks."
- The GameTab registers callbacks via `controller.set_callbacks(...)` when the game starts.

```python
class GameController:
    def set_callbacks(self, on_log=None, on_remaining_changed=None, on_win=None):
        self._on_log = on_log or (lambda msg: None)
        self._on_remaining_changed = on_remaining_changed or (lambda remaining: None)
        self._on_win = on_win or (lambda elapsed: None)
```

---

## H. Testing Strategy (Q31-Q34)

### Q31: WSL-testable (pure, no pymol/no Qt)

| Component | WSL-testable? | How |
|-----------|--------------|-----|
| `generators.generate_sphere_positions(extent, n, seed)` | YES | Pure stdlib `random`. Unit test: verify count, verify positions within bounds, verify determinism with seed. |
| `GameController.on_pick` logic (registry lookup, status check, remaining count) | PARTIALLY | If `cmd.color` is mocked (via `sys.modules['pymol'] = MagicMock()`), the logic can be tested. But the `cmd.color` call is a side-effect that can't be verified in WSL. Test the LOGIC (miss/found/already-found/win) with a mock cmd + mock callbacks. |
| `GameController._remaining()` | YES | Pure: `sum(1 for r in registry.all() if r.status == 'hidden')`. Test with a populated registry. |
| `GameController.win()` logic | PARTIALLY | The callback + wizard deactivation can be tested with mocks. The `time.time()` call is pure. |

**Recommended WSL unit tests:**
- `tests/test_generators.py`: `generate_sphere_positions` — count, bounds, determinism, edge cases (n=0, n=1, negative extent).
- `tests/test_game_controller.py` (if feasible): `on_pick` logic with mock cmd + mock callbacks + a populated registry. Test: miss (non-hider id), found (hidden hider), already-found (found hider), win (last hider).

### Q32: Headless PyMOL smoke test

| Component | Headless-testable? | How |
|-----------|-------------------|-----|
| Sphere generator + insertion | YES | Like phase3_smoke.py: fetch 1ubq, `cmd.get_extent`, `generate_sphere_positions`, `GameController.start(hider_specs)`, verify hiders inserted + registered + sentinel. |
| `cmd.show('spheres', ...)` | YES | Verify `cmd.count_atoms("obj and rep spheres and segi GAME") > 0`. |
| `cmd.color('green', "obj and id N")` | YES | Verify color changed (via `cmd.iterate` reading color index). |
| `do_pick` (click handler) | [UNVERIFIED — needs runtime spike] | `do_pick` requires a real pick populating `pk1`. In headless mode, `pk1` is empty. **Possible workaround:** manually set `pk1` to a hider atom (`cmd.select("pk1", f"{obj} and id {hider_id}")`), then call `wizard.do_pick(0)` — this MIGHT work (the measurement wizard calls `self.do_pick(0)` internally after setting pk1). Needs a runtime spike to confirm. |
| Wizard activation (`cmd.set_wizard`) | [UNVERIFIED — needs runtime spike] | `cmd.set_wizard(wiz)` might work headlessly (it's a cmd call, not Qt). But `cmd.get_setting_int("mouse_selection_mode")` and `cmd.set("mouse_selection_mode", 0)` should work. Needs a runtime spike. |

**Recommended headless smoke test scope:**
1. Fetch 1ubq, get extent, generate sphere positions, start game (snapshot → insert → register).
2. Verify hiders visible as spheres (`cmd.count_atoms("obj and rep spheres and segi GAME") == hider_count`).
3. Simulate finding a hider: `cmd.color('green', f"{obj} and id {hider_id}")` → verify color changed.
4. Simulate the pick handler: `cmd.select("pk1", f"{obj} and id {hider_id}")` → `wizard.do_pick(0)` → verify registry.mark_found was called. [MEDIUM confidence — needs runtime spike]
5. Simulate win: mark all hiders found → verify `_remaining() == 0` → win() callback fires.
6. Cleanup: `GameController.cleanup()` → verify structure intact (like Phase 3 smoke C4).

### Q33: Human-verify checkpoints (Qt GUI — cannot run from WSL)

ALL of these require a human in a real PyMOL session (Qt GUI, real mouse clicks):
- PluginDialog tab switching (Setup → Game on Start).
- 3-2-1 countdown display (QTimer.singleShot chain, QTextEdit.append).
- QTimer ticking (QLabel updating each second).
- Click-to-find loop (real mouse clicks in the OpenGL viewer → `do_pick` fires).
- Found-hider recolor (visible color change in the viewer).
- Remaining count updating (QLabel text change on each find).
- Winning message (QMessageBox appearing on win).
- Wizard activation/deactivation (right-side viewer menu appearing/disappearing).
- Wizard `mouse_selection_mode` save/restore (verify pre-game mode restored after game).

**These are the Phase 4 success criteria verification.** The human runs the plugin in Windows PyMOL (`setenv.bat` → `pymol`), plays a complete round (load → start → click-to-find → win), and confirms all 4 success criteria.

### Q34: Generator split — pure geometry + cmd-coupled insertion

**Recommended:** YES, split (mirrors Phase 3 pattern).

```
generators.py  (PURE: stdlib random only; NO from pymol; WSL-testable)
       ↑
game.py        (cmd-coupled orchestrator: calls cmd.get_extent + generators + mutation.insert_hider)
```

- `generators.py`: `generate_sphere_positions(extent, n, seed=None)` — pure geometry, returns `[[x,y,z], ...]`. WSL-unit-testable.
- `game.py`: `GameController.start(hider_specs)` already takes `(pos, rep)` tuples. The caller (PluginDialog) calls `cmd.get_extent`, `generators.generate_sphere_positions`, builds `hider_specs`, and calls `start(hider_specs)`.
- Phase 5 adds `generate_line_stick_positions()`, `generate_cartoon_positions()` to `generators.py`.

---

## I. Architecture Decision: Where Does the Generator Live? (Q35)

**Recommendation:** New `biochemeleon/generators.py` module (PURE: stdlib only, NO `from pymol`).

The codebase is FLAT (biochemeleon/*.py, no subdirectories). The ARCHITECTURE.md research proposed a `generators/` subdirectory with strategy classes, but the actual codebase doesn't use subdirectories. Phase 4 should follow the established flat-module pattern.

**Module breakdown:**

| Module | Layer | Phase 4 changes | Lines (est.) |
|--------|-------|-----------------|-------------|
| `biochemeleon/generators.py` | PURE (new) | NEW: `generate_sphere_positions(extent, n, seed)` | ~30 |
| `biochemeleon/wizard.py` | cmd-coupled (populate stub) | Populate: `PickWizard(Wizard)` class with `do_pick`, `activate`, `deactivate`, `get_panel`, `cleanup` | ~60 |
| `biochemeleon/gui_game.py` | Qt + cmd (populate stub) | Populate: `GameTab` with QTextEdit log, QLabel timer, QLabel remaining, QTimer, countdown, callbacks | ~120 |
| `biochemeleon/game.py` | cmd-coupled (extend) | ADD: `on_pick(aid)`, `win()`, `set_callbacks(...)`, `_remaining()`, `_start_time` | +40 (69→~110) |
| `biochemeleon/__init__.py` | Qt (extend) | ADD: `_on_start()` wiring (resolve target → generate → start → switch tab → countdown) | +40 (66→~106) |
| `tests/test_generators.py` | PURE (new) | NEW: WSL unit tests for `generate_sphere_positions` | ~60 |
| `smoke/phase4_smoke.py` | cmd-coupled (new) | NEW: headless smoke test (sphere gen + insertion + simulate find + cleanup) | ~80 |

**Dependency direction (strict, never reversed):**
```
setup_state.py (PURE) ← generators.py (PURE, new)
                        ← registry.py (PURE, Phase 3)
demos.py (cmd) ← gui_setup.py (Qt+cmd, Phase 2)
backup.py (cmd) ← game.py (cmd orchestrator, Phase 3 + Phase 4 extend)
mutation.py (cmd) ← game.py
wizard.py (cmd, Phase 4 populate) ← __init__.py (Qt, Phase 4 extend)
gui_game.py (Qt+cmd, Phase 4 populate) ← __init__.py
```

`generators.py` has NO `from pymol` (pure) — WSL-unit-testable, like `registry.py` and `setup_state.py`.

---

## Recommended Implementation Approach

### Module breakdown + suggested plan order

**Wave 1 (parallelizable — pure + standalone):**
1. **`generators.py` + `tests/test_generators.py`** (PURE, WSL-testable): `generate_sphere_positions(extent, n, seed)`. Unit test: count, bounds, determinism, edge cases.
2. **`wizard.py`** (cmd-coupled, standalone): `PickWizard(Wizard)` with `do_pick`, `activate`, `deactivate`, `get_panel`, `cleanup`. Follows the canonical built-in wizard pattern (save `mouse_selection_mode` → set to 0 → override `do_pick` → read `pk1` via `cmd.identify(mode=1)` → `cmd.unpick()` → restore on cleanup).

**Wave 2 (depends on Wave 1):**
3. **`game.py` extensions**: ADD `on_pick(aid)`, `win()`, `set_callbacks(...)`, `_remaining()`. The `start(hider_specs)` method stays unchanged. `on_pick` calls `registry.get`/`mark_found`/`cmd.color`/callbacks.

**Wave 3 (depends on Wave 2):**
4. **`gui_game.py`** (Qt + cmd): Populate `GameTab` with QTextEdit log, QLabel timer, QLabel remaining, QTimer, countdown (`QTimer.singleShot` chain), `_begin_play` (create + activate PickWizard, register callbacks, start timer), `_on_win` (stop timer, QMessageBox).

**Wave 4 (depends on Wave 3):**
5. **`__init__.py` extensions**: ADD `_on_start()` wiring in PluginDialog (resolve target → `cmd.get_extent` → `generators.generate_sphere_positions` → `GameController.start(hider_specs)` → `cmd.show('spheres', ...)` → switch tab → `GameTab.start_countdown`). Wire the Start button (`setup_tab.start_btn.clicked` → `_on_start`). ADD a Start button to `gui_setup.py` if not already present (currently only Reset/Randomize/Save/Load — need to add Start).

**Wave 5 (depends on all):**
6. **`smoke/phase4_smoke.py`**: Headless smoke test (sphere gen + insertion + simulate find + cleanup). Stage to `tmp/bioCHEMeleon/` and run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`.
7. **Human-verify checkpoint**: Play a complete round in Windows PyMOL (Start → countdown → click-to-find → win). Verify all 4 success criteria.

### Parallelizable?
- Wave 1 (generators.py + wizard.py) — YES, fully parallel (file-disjoint, no cross-dependency).
- Wave 2 (game.py) — depends on Wave 1 generators (imports) but not wizard.
- Wave 3 (gui_game.py) — depends on Wave 2 game.py (callback interface).
- Wave 4 (__init__.py) — depends on all prior.
- Wave 5 (smoke + human-verify) — depends on all.

---

## Risks & Open Questions

### 1. [MEDIUM] Can `do_pick` be simulated headlessly for smoke testing?

**What we know:** `do_pick` fires on real picks (mouse clicks). The picked atom lands in `pk1`. In headless mode, no mouse clicks happen, so `pk1` is empty.

**Possible workaround:** Manually set `pk1` to a hider atom, then call `wizard.do_pick(0)` directly. The measurement wizard calls `self.do_pick(0)` internally after setting `pk1` (measurement.py:298-300), so this pattern is used in the source.

**What's unclear:** Whether `cmd.select("pk1", selection)` works in headless mode (it should — it's a cmd call, not Qt), and whether `do_pick(0)` reads `pk1` correctly when called directly.

**Recommendation:** Try the workaround in the smoke test. If it doesn't work, test the `on_pick` LOGIC via WSL unit tests (with mock cmd) and leave the full pick-chain to the human-verify checkpoint.

### 2. [MEDIUM] Does wizard activation automatically make left-click = pick?

**What we know:** All built-in wizards set `mouse_selection_mode` but do NOT change `button_mode`. The wizard's `get_event_mask()` returns `event_mask_pick`, telling PyMOL to route pick events to the wizard.

**What's unclear:** Whether left-click produces a pick in the default 3-Button Viewing mode when a wizard is active, or whether the user needs to be in a specific button mode (e.g., Picking mode). The C-level pick dispatch isn't visible.

**Recommendation:** Follow the canonical pattern (set `mouse_selection_mode=0`, don't touch `button_mode`). If clicks don't register during human-verify, investigate whether `button_mode` also needs to be set (save/restore like `mouse_selection_mode`).

### 3. [LOW] `cmd.identify("pk1", mode=1)` return shape after `cmd.select("pk1", ...)`

**What we know:** `cmd.identify(selection, mode=1)` returns `[(model, id)]` for the atoms in the selection. `pk1` should contain exactly one atom after a pick.

**What's unclear:** Whether `pk1` is always a single-atom selection (it should be — it's the "pick 1" selection), or whether `mouse_selection_mode` affects how many atoms end up in `pk1` (mode 0/atomic = 1 atom, mode 1/residue = all atoms in the residue).

**Recommendation:** Use `mouse_selection_mode=0` (atomic) to ensure `pk1` is always a single atom. `cmd.identify("pk1", mode=1)` returns `[(model, id)]` — take `pairs[0]`.

### 4. [LOW] Start button not yet in gui_setup.py

**What we know:** `gui_setup.py` currently has Reset/Randomize/Save/Load buttons (BTN-01..04). The Start button (BTN-07) is NOT yet in the UI — it needs to be added.

**Recommendation:** Add a Start button to `gui_setup.py` in the "Setup actions" group. Wire it to `PluginDialog._on_start()` (or emit a signal/callback that the PluginDialog connects to). Also add a Cleanup button (BTN-06) for post-game cleanup — but BTN-06 is Phase 7 scope; for Phase 4, just add Start.

### 5. [LOW] `elem='PS'` makes sphere hiders visually distinct

**What we know:** `mutation.insert_hider` uses `elem='PS'` (pseudoatom element). PS spheres have a default VDW radius and render as gray spheres. They're VISIBLE but don't blend with real atoms (which are C/N/O colored).

**Impact:** For Phase 4 MVP, this is acceptable — the hider is a visible sphere the player finds by clicking. Visual blending is Phase 5+ work. But the hiders may be TOO easy to spot if they're a different color/size than real atoms.

**Recommendation:** Accept `elem='PS'` for MVP. If hiders are too easy to spot, consider setting `elem='C'` and `vdw` to carbon's radius in a future improvement. The game's challenge for sphere hiders comes from the 3D volume search, not visual blending.

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 source, directly read)

- `tmp/pymol-src/modules/pymol/wizard/__init__.py` — Wizard base class: `do_pick(self, bondFlag)` (:76), `get_event_mask()` (:55-56), `get_prompt()` (:49-50), `get_panel()` (:52-53), `cleanup()` (:88-89), `event_mask_pick=1` (:6), `__init__` sets `self.cmd=_self` (:22), `__getstate__` pops `cmd` (:29-31).
- `tmp/pymol-src/modules/pymol/wizarding.py` — `set_wizard(wizard=None, replace=0)` (:110-118, default None = clear), `get_wizard()` (:156-164, returns wizard or None), `refresh_wizard()` (:130-144), `wizard(name=None)` (:62-92, None = clear).
- `tmp/pymol-src/modules/pymol/querying.py` — `identify(selection, mode=0)` (:1269-1300, mode=0 returns [id], mode=1 returns [(model,id)]), `index(selection)` (:1302-1330, returns [(model,index)], docstring warns "use integral atom identifiers instead of indices"), `id_atom(selection)` (:1235-1267, single-atom convenience), `get_extent(selection)` (:1371-1392, returns [[min],[max]]).
- `tmp/pymol-src/modules/pymol/selecting.py` — `'id': 1` (:142, confirms `id` is a valid selector keyword).
- `tmp/pymol-src/modules/pymol/controlling.py` — `mouse_selection_mode` ranges 0-6 (:640-646), `button_mode` (:196), mouse ring modes (:204-232).
- `tmp/pymol-src/modules/pymol/wizard/measurement.py` — Canonical wizard pattern: save `mouse_selection_mode` (:96), set to 0 (:97), `do_pick(self, bondFlag)` (:307), reads `pk1` (:310), `cmd.unpick()` (:468), `get_panel()` (:195-203), `cleanup()` restores mouse mode (:205-212).
- `tmp/pymol-src/modules/pymol/wizard/distance.py` — Same pattern: save (:69), set 0 (:70), `do_pick` (:148), cleanup restore (:104).
- `tmp/pymol-src/modules/pymol/wizard/mutagenesis.py` — Same pattern with mode 1 (residue): save (:90), set 1 (:91), `do_pick` (:715), cleanup restore (:310).
- `Pymol-script-repo/plugins/mtsslWizard.py` — Reference plugin: `do_pick(self, picked_bond)` (:332), reads `(sele)` (:348), `get_panel()` (:241-254), `get_prompt()` (:222-239), `cmd.set("mouse_selection_mode",1)` (:297), `cmd.set_wizard()` to clear (:253).

### Secondary (MEDIUM-HIGH confidence — project research, Phase 3 verified)

- `.planning/research/SUMMARY.md` — Wizard `do_pick` + `cmd.index('pk1')` + QTimer patterns (HIGH).
- `.planning/research/ARCHITECTURE.md` — Pattern 2 (Wizard for atom-picking), Pattern 3 (singleton dialog), Flow A (click-to-find data flow).
- `.planning/research/PITFALLS.md` — Pitfall 5 (no click callback — Wizard), Pitfall 6 (thread safety — QTimer on main thread), Pitfall 3 (pseudoatom defaults).
- `.planning/research/STACK.md` — PyQt5 via `pymol.Qt`, numpy availability, `cmd.identify` for click-to-find.
- `.planning/phases/03-.../03-SUMMARY.md` — Phase 3 foundation (registry/backup/mutation/game.py proven), 9 residual risks, Phase 4 readiness table.
- `biochemeleon/game.py` — Current `GameController.start(hider_specs)` (proven by Phase 3 smoke).
- `biochemeleon/mutation.py` — `insert_hider` uses `cmd.identify(..., mode=0)` for stable id.
- `biochemeleon/gui_setup.py` — `collect_state()` fields, existing Setup tab UI.
- `smoke/phase3_smoke.py` — Headless smoke test pattern (run via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`).

### Tertiary (LOW confidence — needs runtime spike)

- `do_pick` simulation in headless mode (manually setting `pk1` then calling `do_pick(0)`) — needs runtime spike to confirm.
- Wizard activation + left-click behavior in default 3-Button Viewing mode — needs human-verify to confirm clicks register.

---

## Metadata

**Confidence breakdown:**
- Wizard API (do_pick, identify, set_wizard, get_wizard, get_panel, mouse_selection_mode): HIGH — verified against PyMOL 2.5.0 source (wizard/__init__.py, wizarding.py, querying.py, 8 built-in wizards, mtsslWizard.py).
- QTimer: HIGH — standard PyQt5 pattern, confirmed by PITFALLS.md Pitfall 6.
- Sphere generator: HIGH — `cmd.get_extent` verified (querying.py:1371-1392), pure geometry is straightforward.
- Found-hider feedback: HIGH — `id` selector confirmed (selecting.py:142), `cmd.color` is standard.
- Start button wiring: HIGH — `collect_state()` fields verified from gui_setup.py, target resolution from demos.py.
- Game tab UI: HIGH — standard Qt widgets (QTextEdit, QLabel, QTimer, QMessageBox).
- GameController extensions: HIGH — builds on proven Phase 3 foundation, `on_pick`/`win` logic is straightforward.
- Testing strategy: MEDIUM — headless `do_pick` simulation is [UNVERIFIED — needs runtime spike].
- Architecture: HIGH — flat-module pattern established, generators.py pure split mirrors Phase 3.

**Research date:** 2026-08-08
**Valid until:** 2026-09-08 (30 days — PyMOL 2.5.0 source is stable; the API findings won't change)
