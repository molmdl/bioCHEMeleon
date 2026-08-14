# Pitfalls Research

**Domain:** PyMOL 2.x plugin — interactive "hide-and-seek" game that mutates a loaded molecular object (inserts foreign "hider" atoms into the *same* PyMOL object) and detects atom clicks in the OpenGL viewer.
**Researched:** 2026-08-02
**Confidence:** HIGH (PyMOL API behavior verified against `pymol-open-source` `editor.py` / `creating.py` on `master`; plugin architecture verified against official PyMOL wiki; licensing verified against RCSB PDB and SASBDB official policy pages). MEDIUM for MemProtMD licensing (site unreachable — needs phase-specific verification).

---

## How to read this file

Each critical pitfall has five fields:
- **What goes wrong** — the failure mode
- **Why it happens** — root cause
- **How to avoid** — actionable prevention
- **Warning signs** — early detection
- **Phase to address** — which roadmap phase must prevent it (phases per `PROJECT.md`: **setup** / **generator** / **game loop** / **save-load** / **demos**)

Project-specific phase shorthand used below:
- **setup** = plugin scaffold + setup window + environment wiring
- **generator** = hider generation (atom insertion, rep blending)
- **game loop** = click detection, timer, win condition, hint/reveal
- **save-load** = PyMOL session + game-state checkpointing, restart
- **demos** = demo PDB set, fetch/bundle, attribution

---

## Critical Pitfalls

### Pitfall 1: Building the GUI with Tkinter instead of PyQt5

**What goes wrong:**
The plugin is written against `Tkinter`/`Pmw` (the pattern used by legacy plugins in `Pymol-script-repo/plugins/mole.py`, `rendering_plugin.py`). It "works" initially but: modal `grab_set()` blocks the OpenGL viewer (so the user can't click atoms while the dialog is up), `app.root` parentage is inconsistent, dialogs sometimes appear behind the PyMOL window (the `rendering_plugin` author literally wrote *"NOTE: make sure this window is not on top of the PyMOL window."* in the UI), and after upgrading PyMOL the plugin stops loading.

**Why it happens:**
PyMOL 2.x is Qt-based (PyQt5). Tkinter is a **deprecated legacy layer**. From the official PyMOL wiki (`/Plugins`, edited 2024-05-15):

> "Version 3.0 — Currently, support for plugins written in Tkinter is considered deprecated with full expectation of removal by PyMOL 4.0. Plugin developers should consider migrating legacy plugins to PyQt."

> "Before Version 2.0 — PyMOL 2.x has a legacy layer for Tkinter to support old plugins, but the preferred toolkit for new plugins is PyQt5."

The project brief mentions "Tkinter GUI quirks inside PyMOL" — that framing is itself a pitfall. The reference plugins split cleanly: `mole.py`, `rendering_plugin.py`, `pyanm.py` use Tk/Pmw (legacy); `dynoplot.py`, `show_contacts.py`, `vina.py`, `colorama.py`, `optimize.py`, `outline.py` use `from pymol.Qt import QtWidgets` (modern). New code must follow the modern group.

**How to avoid:**
- GUI entrypoint: `def __init_plugin__(app=None): from pymol.plugins import addmenuitemqt; addmenuitemqt('bioCHEMeleon', run_plugin_gui)`.
- All widgets via `from pymol.Qt import QtWidgets, QtCore, QtGui` and `from pymol.Qt.utils import loadUi`.
- Build the dialog with Qt Designer (`.ui` file) and load with `loadUi(uifile, dialog)` — see `pymol2-demo-plugin` referenced from the official tutorial.
- For modeless behavior (player must click atoms in the viewer while the game panel is open), use `dialog.show()` — **never** `dialog.exec_()` (which is modal and blocks the PyMOL event loop).
- Keep a `global dialog` reference and reuse it (`if dialog is None: dialog = QtWidgets.QDialog(); ...; dialog.show()`) — this is the exact pattern in the official tutorial, because without the global, Python GCs the dialog and it vanishes.

**Warning signs:**
- Import statements `import Tkinter` / `import tkinter` / `import Pmw` in the plugin.
- Any call to `grab_set()`, `mainloop()`, `Toplevel`, `app.root` as a parent.
- The setup window stays on top and the viewer becomes unclickable while it's open.
- After PyMOL upgrade, the menu item no longer appears.

**Phase to address:** **setup** (the very first architectural decision; retrofitting Qt later is a rewrite).

---

### Pitfall 2: Inserting hiders into the wrong place — new object instead of the existing one

**What goes wrong:**
A developer reaches for `cmd.load(...)`, `cmd.create('hiders', selection)`, or `cmd.fragment(...)` to build hiders. These create a *separate* object. The player then defeats the game in one keystroke: `hide everything, hiders` — or just toggles the hider object off in the object menu. The whole "they live in the same object" core mechanic (per `PROJECT.md` Key Decision 2) collapses.

**Why it happens:**
Most PyMOL command verbs (`load`, `create`, `fragment`) are object-creating. The API surface for *in-place mutation of an existing object* is narrower and less discoverable. The relevant verbs are `cmd.pseudoatom(object=existing, ...)`, `cmd.fuse(mobile, target, mode)`, and `cmd.create(existing, "newatoms or existing", ...)` (the merge form).

**How to avoid:**
- Use `cmd.pseudoatom(object=target_obj, pos=[x,y,z], elem=..., resn=..., resi=..., chain=..., segi=..., hetatm=0, ...)` — the official source (`creating.py`) documents: *"adds a pseudoatom to a molecular object, and will creating the molecular object if it does not yet exist."* This is the canonical in-place atom insert.
- For bonded hiders (line/stick mimic, cartoon terminus extension), use `cmd.fuse(mobile_sele, target_sele, mode)` (modes 1/2/3 — see `editor.py` `attach_fragment` / `attach_amino_acid`). Fuse *moves* the mobile atoms into the target object and creates a bond.
- Validate after every insert: `assert cmd.get_names("objects")` does **not** contain any new game object name; `cmd.count_atoms(target_obj)` increased by exactly the expected count.

**Warning signs:**
- A new entry appears in the PyMOL object menu after Generate.
- `cmd.get_names("objects")` grows during generation.
- The player can trivially hide all hiders by toggling one object.

**Phase to address:** **generator**.

---

### Pitfall 3: Pseudoatom defaults make hiders trivially visible

**What goes wrong:**
Calling `cmd.pseudoatom(object)` with default args produces atoms with `elem='PS'`, `resn='PSD'`, `chain='P'`, `segi='PSDO'`, `hetatm=1`, and a `vdw` that's a pseudo-radius. They render as ghostly PS-element spheres, show up in `hetatm` selections, in `not polymer` selections, and in any `select有机`-style filter — instantly filterable with one command. The "blend in" requirement (`PROJECT.md` Hider Generation Logic) is broken before the game even starts.

**Why it happens:**
The defaults in `creating.py:pseudoatom()` are tuned for "label anchor" use, not "mimic a real atom" use. They are inappropriate for this game out of the box.

**How to avoid:**
For every hider, explicitly set:
- `elem` to a plausible element matching the local context (`C`, `N`, `O`, `S`) — never `'PS'`.
- `resn` / `resi` / `chain` / `segi` to **plausible** values (mirror a neighbor's resn/chain so `select有机` by residue name doesn't isolate them) — but see Pitfall 9 for the cleanup marker tradeoff.
- `hetatm=0` so the hider is part of `polymer`/`not hetatm` selections if it's mimicking backbone.
- A real `vdw` radius (per-element) so sphere/line reps render correctly.
- A `b`-factor matching neighbors so `spectrum b` doesn't recolor hiders differently.

After insert, verify with `cmd.iterate(target, "print(elem, resn, chain, hetatm)")` that no hider shows `PS/PSD/P/1`.

**Warning signs:**
- `cmd.select("hetatm")` returns the hider count.
- `cmd.select("elem PS")` returns non-zero.
- `spectrum b, rainbow, target` recolors hiders differently from real atoms.
- Hiders render as flat gray spheres regardless of rep.

**Phase to address:** **generator**.

---

### Pitfall 4: Tracking hiders by an unstable identifier (resi/chain, or per-object `index` after deletions)

**What goes wrong:**
The hider registry stores `(resi, chain)` or `(object, atom_index)` at generation time. Later: (a) the user's molecule already has duplicate `(resi, chain)` across altlocs/segments, so the registry is ambiguous from the start; (b) when a hider is marked "found" and removed, **every hider with a higher `index` shifts down by 1**, so the registry now points at the wrong atoms; (c) insertion codes (`66A`) and insertion mutations break integer assumptions.

**Why it happens:**
- PyMOL `index` is the per-object **ordinal** — not a stable identifier. The official `selector.process` canonical form is `"%s`%d" % (model, index)` (see `selector.py` and `tmalign.py`), but `index` is reassigned when atoms are removed.
- PyMOL `id` is the **global** atom id, set at load time, *more* stable but not guaranteed across `create`/`extract` re-merges.
- `(resi, chain)` collides with real data: a real residue and a hider can share `(resi, chain)` if the hider is mimicking that residue.

**How to avoid:**
- Primary hider identity = **`(object_name, atom_id)`** captured at generation, where `atom_id` is the `id` field fetched via `cmd.iterate(obj_sele, "stored.append(id)", space={'stored':[]})`. `id` survives reordering.
- Secondary safety net = a **sentinel `b`-factor** (e.g., `b = -999.0`) AND a dedicated `segi` value (e.g., `segi = 'GAME'`), set via `cmd.alter`. These survive `id` collisions and let you reconstruct the registry after a session reload (Pitfall 7).
- **Never** delete hider atoms one at a time during the game. Instead, mark found-hiders by recolor/reps change; bulk-remove at "Cleanup" using the sentinel: `cmd.remove("obj and segi GAME and b < -500")`. This avoids index-shift staleness entirely.
- If per-atom deletion is unavoidable, re-iterate the registry from the sentinel after every mutation rather than trusting cached indices.

**Warning signs:**
- After clicking one hider, a different hider is reported as "found".
- `cmd.iterate(obj + " and id N", ...)` returns a different atom after a removal.
- Two atoms answer to the same `(resi, chain)`.

**Phase to address:** **generator** (registry design) + **game loop** (found-marking strategy) + **save-load** (sentinel-based reconstruction). *(Runtime-verified 2026-08-06 via the Phase 3 headless smoke test — atom `id` stable across insert and `.pse` round-trip; see "Phase 3 — Resolved Research Flags" below.)*

---

### Pitfall 5: Assuming "click on atom" = "PyMOL gives me a callback"

**What goes wrong:**
The game loop expects an `on_atom_clicked(atom)` callback. None arrives. Either nothing happens on click, or every drag-to-rotate also fires a "click", or the click only registers in one specific mouse mode, or `sele` from a previous click is still hanging around and the game reads stale state.

**Why it happens:**
PyMOL does **not** expose a generic "atom clicked" event to plugins. Mouse behavior is governed by the active **mouse mode** (`Mouse` menu: Viewing / Picking / Editing / Sculpting). The default is **Viewing** — a left-click does nothing atom-related; it's drag-to-rotate. Only in **Picking** / **Editing** modes do clicks produce atom selections (`pk1` for single-atom pick, `sele` for the multi-atom selection). There is no public `cmd.set_on_pick_callback`. The plugin must either (a) set a specific mouse mode and poll `pk1`/`sele`, (b) bind a mouse button via `cmd.set_key`, or (c) register a frame callback via `cmd.load_callback(self, name)` (the `dynoplot.py` pattern: the `__call__` runs each frame and can inspect `cmd.get_names("selections")`).

**How to avoid:**
Pick one strategy and document it. Recommended:
1. On "Start", force the mouse into a known mode: `cmd.set("button_mode", 4)` (or whatever the picking mode constant is in 2.5.0 — verify at runtime) and save the previous value to restore on exit.
2. Register a frame callback (`cmd.load_callback(self, name)`) whose `__call__` checks whether `pk1` exists in `cmd.get_names("selections")` AND is different from the last-seen pick. If new, run `cmd.iterate("pk1", "stored.append((model, index, id))", space=...)`, look up the id in the hider registry, and clear `pk1` (`cmd.unpick()`) so the same pick isn't processed twice.
3. Disambiguate **click vs drag**: record the mouse-down position and time; if the mouse moved more than ~3 px or more than ~300 ms between down and up, treat as a drag (rotate/zoom), not a click. PyMOL itself does not give you raw mouse events from Python — this must be done by inspecting `pk1` freshness in the frame callback, OR by binding a custom button via `cmd.set_key` (which gives a clean click event but takes over that button for the whole PyMOL session).
4. Modal interference: ensure the game panel is **modeless** (`dialog.show()`, never `dialog.exec_()`) or it blocks the viewer entirely (Pitfall 1).

**Warning signs:**
- Clicking an atom does nothing.
- Rotating the view with the mouse spuriously "finds" hiders.
- The same click fires multiple times.
- The game works on the developer's machine but not on a fresh PyMOL with default settings.

**Phase to address:** **game loop** — but the mouse-mode dependency must be documented in **setup** so the user is warned.

---

### Pitfall 6: Calling `cmd.*` from a background thread / QTimer without the PyMOL lock

**What goes wrong:**
The timer is implemented with a `threading.Thread` (the `mtsslDockGui.py` pattern) or a `QTimer` that fires on a worker thread. From that thread, the code calls `cmd.select(...)`, `cmd.iterate(...)`, etc. Symptoms: random deadlocks, PyMOL freezes, segfaults, "Selector-Error: Invalid selection name" out of nowhere, or corruption that only shows up after the game has run a few minutes.

**Why it happens:**
PyMOL commands take an internal lock (`_self.lock(_self)` / `with _self.lockcm:` — see every command in `creating.py`). The lock is **not reentrant across threads** and PyMOL's C-side state is not thread-safe. The `mtsslDockGui` plugin threads only touch *Python-side queues* and let the main thread do the `cmd.*` work; `autodock_plugin` uses `self.parent.after(100, self._gui_updates_flush)` to marshal back to the Tk main loop.

**How to avoid:**
- **Golden rule: all `cmd.*` calls happen on the GUI main thread.**
- For the timer: use `QTimer` with a 1 s tick on the main thread (no threading). A 1 Hz update of a label is essentially free; do not optimize with threads.
- For long-running work (hider generation on a 100k-atom membrane protein — Pitfall 12): if you must thread, have the worker compute geometry in pure Python/numpy and post results to a `queue.Queue`; the main thread polls the queue with `QTimer.singleShot(0, drain)` and performs the `cmd.pseudoatom` calls.
- If you absolutely must call `cmd` from a thread, use `cmd.async`-style invocation or `with cmd.lock:` — but verify against `pymol-open-source` `creating.py` that the specific command takes the lock cleanly. The safe path is: don't.

**Warning signs:**
- `threading.Thread` or `QThread` in the codebase with any `cmd.` call in its `run`/target.
- PyMOL hangs when "Start" is pressed.
- Hard crash (segfault) after a few minutes of play.
- Works on small molecules, deadlocks on large ones.

**Phase to address:** **game loop** (timer) and **generator** (large-molecule path).

---

### Pitfall 7: Expecting `.pse` save/load to round-trip plugin game state

**What goes wrong:**
"Save game" calls `cmd.save('game.pse')`. On reload, the hider atoms are back (they're part of the object — good), but the timer value, found-status, hider registry, and difficulty setting are gone (bad). The game resumes in an inconsistent state — atoms visible as "found" in the viewer but the rolling info box says 0/10 found, or vice versa.

**Why it happens:**
Per the official wiki (`/Save`): *"If the file extension is '.pse' (PyMOL Session), the complete PyMOL state is always saved to the file (the selection and state parameters are thus ignored)."* "PyMOL state" = atoms, bonds, reps, camera, settings. It does **not** include arbitrary plugin Python objects (timer, registry, found-set) unless they are registered as callbacks with proper pickling.

The canonical pattern (from `dynoplot.py`):
```python
class GameCallback:
    def __init__(self, ...): cmd.load_callback(self, name)
    def __call__(self): ...  # runs each frame
    def __getstate__(self):
        st = dict(self.__dict__)
        st.pop("dialog", None)   # Qt widgets can't be pickled!
        return st
    def __setstate__(self, st):
        self.__dict__.update(st)
        self._rebuild_dialog()   # re-create Qt on reload
```
Even this only round-trips serializable state (numbers, strings, lists, dicts). Qt widgets, file handles, and running `QTimer`s must be dropped from `__getstate__` and rebuilt in `__setstate__`.

**How to avoid:**
- Treat `.pse` as the "geometry save" and a **sidecar `.json`** as the "game state save". Write both on Save, read both on Load. The `.pse` carries atoms + reps + the `segi='GAME'` / `b=-999` sentinels; the `.json` carries `{hiders: [{id, found, ...}], timer, difficulty, setup}`.
- On Load: open the `.pse`, then iterate the object to **reconstruct** the hider registry from the sentinels (Pitfall 4): `cmd.iterate(obj + " and segi GAME", "stored.append((id, b, resi, chain))")`. This is the source of truth — the `.json` is matched to it by `id`. Any hider in the `.pse` not in the `.json` is treated as unrestored (rebuild its record).
- If using `load_callback`, **always** implement `__getstate__`/`__setstate__` and pop non-picklable attributes. Test round-trip on every change.
- Never store a `QTimer` reference, file handle, or `QtWidgets` widget in instance state that gets pickled.

**Warning signs:**
- "Save" then "Load" produces a game with no timer or wrong found-count.
- Loading a `.pse` raises `TypeError: cannot pickle 'QTimer'` (or similar) in the console.
- Hiders reappear but their "found" recolor is lost (because recolor was a runtime state not persisted).

**Phase to address:** **save-load** (the entire phase is essentially this). *(Runtime-verified 2026-08-06 via the Phase 3 headless smoke test — `segi='GAME'` sentinel survives `.pse` reload, `id` stable, `b=-999.0` preserved, `reconstruct_from_sentinels` rebuilds with `rep=None`; see "Phase 3 — Resolved Research Flags" below.)*

---

### Pitfall 8: Cartoon/ribbon reps require a connected backbone — random hider atoms are invisible

**What goes wrong:**
The "cartoon hider" is a `cmd.pseudoatom` placed near the Cα of a residue, expecting it to render as a cartoon extension. It doesn't render at all — the viewer shows the existing cartoon unchanged, and the player can never find that hider because there's nothing to click. The game becomes unwinnable.

**Why it happens:**
`cartoon` and `ribbon` representations in PyMOL are **polymer-trace** representations: they connect consecutive Cα atoms (and N/C for ribbon) along residues flagged as `ss` (helix/sheet/loop) on `polymer` atoms. A lone pseudoatom — even with `elem='C'`, `name='CA'`, `hetatm=0` — is **not** part of the polymer trace unless it is fused into the chain with proper N-C-Cα geometry and consecutive `resi`. `PROJECT.md` Hider Generation Logic already says "extend at a terminal, or replicate a segment (e.g. a loop)" — but the implementation detail (you must use `cmd.fuse`/`attach_amino_acid` with proper dihedrals, not just `pseudoatom`) is easy to miss.

**How to avoid:**
- For **cartoon/ribbon** hiders: use the `editor.py` machinery — `cmd.attach_amino_acid('pk1', 'gly', ss=1, hydro=0)` (or a custom fuse) to extend at a terminus with real backbone geometry, then `cmd.alter` the new residue to a `segi='GAME'` sentinel and `b=-999`. The fused residue IS part of the polymer, so cartoon renders it. This is more invasive than `pseudoatom` but it's the only way cartoon hiders work.
- For **loop replica** hiders: build a short `fab`-built peptide fragment, translate it to the target location, then `cmd.fuse` it into the object. Verify with `cmd.show('cartoon', 'obj and segi GAME')` that it actually renders.
- For **line/stick** hiders: `pseudoatom` + `cmd.bond` to a neighbor works (lines/sticks render bonds between atoms, no polymer requirement).
- For **sphere** hiders: `pseudoatom` with a real `elem` and `vdw` works anywhere.
- For **surface**: out of scope per `PROJECT.md` (good — surface requires a computed mesh and doesn't fit the mechanic).
- **Always visually verify** after generation that each rep-type hider is visible in its target rep. Add a "Reveal-all (debug)" command during development that does `cmd.show('lines|sticks|cartoon|spheres', 'obj and segi GAME')` and visually confirm counts.

**Warning signs:**
- Hider count says 10 but only 7 are visually findable.
- `cmd.count_atoms('obj and segi GAME')` is correct but `cmd.count('cartoon', 'obj and segi GAME')` is lower.
- Player reports the game is unwinnable.

**Phase to address:** **generator**.

---

### Pitfall 9: Cleanup uses a generic filter and deletes real atoms

**What goes wrong:**
"Cleanup model" (per `PROJECT.md` Active requirement) is implemented as `cmd.remove('hetatm')` or `cmd.remove('resn PSD')` or `cmd.remove('not polymer')`. The user loads a membrane protein demo (1GZM or 3GP6 with full membrane — `PROJECT.md` Demo PDBs Note 1), generates hiders, plays, clicks Cleanup. Real ligands, ions, waters, and the **entire DPPC membrane** vanish along with the hiders. The user's carefully prepared scene is destroyed. There is no undo (Pitfall 10).

**Why it happens:**
Hiders, ligands, waters, and membrane lipids are all `hetatm=1` by PDB convention. Any generic filter (`hetatm`, `resn PSD`, `not polymer`, `water`) over-matches. `PROJECT.md` even calls this out: "Cleanup model removes all game-generated representations/atoms not in the original object" — the operative phrase is **"not in the original object"**, which requires knowing the original, not filtering by a chemical property.

**How to avoid:**
- **Sentinel-based removal only.** At generation time, `cmd.alter(hider_sele, "segi='GAME'; b=-999.0", ...)`. At cleanup: `cmd.remove(target_obj + " and segi GAME")` — never anything broader. `segi` is rarely used by real structures (most PDBs leave it blank), so collisions are essentially nil; if paranoid, use a more unique sentinel like `segi='BIOCHM'`.
- **Snapshot the original.** On "Start", record `cmd.count_atoms(target_obj)` and a hash / the list of original atom `id`s (`cmd.iterate(target_obj, "stored.append(id)")`). On Cleanup, after removing `segi GAME`, assert the count matches the snapshot; if not, restore from a hidden backup object (`cmd.create('_bchm_backup', target_obj)` made at Start).
- **Never** use `hetatm`, `water`, `solvent`, `not polymer`, `resn PSD`/`HOH`/`DPPC`/`PC`/`OL` as the cleanup filter.
- Test cleanup explicitly against the 1GZM and 3GP6 membrane demos — this is the exact scenario where the pitfall bites.

**Warning signs:**
- Cleanup removes more atoms than were generated.
- After Cleanup, the membrane or ligands are gone.
- The original atom count after Cleanup != original atom count before Start.

**Phase to address:** **generator** (sentinel assignment) + **game loop** (Cleanup button) — and verify in **demos** with the membrane proteins.

---

### Pitfall 10: Relying on PyMOL's undo to recover from a botched mutation

**What goes wrong:**
A generator bug inserts hiders in the wrong place, or Cleanup deletes real atoms (Pitfall 9), or a fuse creates a bad bond. The developer presses Ctrl-Z expecting PyMOL's undo. Nothing happens, or PyMOL prints an error. The original object is corrupted and the only recovery is to reload from disk.

**Why it happens:**
From `editor.py`:
```python
class undocontext:
    def __init__(self, cmd, sele):
        # not implemented in open-source
        pass
    def __enter__(self): pass   # not implemented in open-source
    def __exit__(self, ...): pass  # not implemented in open-source
```
PyMOL **Open Source has no undo/redo**. The `undocontext` is a no-op stub. (The commercial Schrödinger build may differ, but the project targets `pymol-open-source` 2.5.0 in conda.)

**How to avoid:**
- **Snapshot before every destructive operation.** On "Start": `cmd.create('_bchm_orig_backup', target_obj, zoom=0)` (a hidden backup object) and/or `cmd.save(temp_pse)`. On Cleanup / Restart: `cmd.delete(target_obj); cmd.create(target_obj, '_bchm_orig_backup')` to restore. Delete the backup on plugin unload.
- Implement the "Restart from stored initial state" requirement (`PROJECT.md` Active) via this backup, not via undo.
- Wrap every generator mutation in a try/except that, on failure, restores from the backup and surfaces a clear error.
- Document for the user that PyMOL's Ctrl-Z does **not** undo plugin actions, so the "Cleanup" and "Restart" buttons are the only safety nets.

**Warning signs:**
- A "Restart" button that doesn't actually restore the original (because it was never snapshotted).
- After a generator exception, the object is in a half-mutated state.
- User reports "I clicked the wrong thing and now my molecule is ruined."

**Phase to address:** **setup** (create the backup scaffold) and **save-load** (Restart logic). The generator and game loop must use the backup/restore helpers.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Tkinter + Pmw for the GUI (copy from `mole.py` / `rendering_plugin.py`) | Familiar; lots of examples in `Pymol-script-repo` | Breaks on PyMOL 4.0; modal-blocks the viewer; z-order issues | **Never** for new code on PyMOL 2.5+. Use PyQt5. |
| `cmd.pseudoatom` with defaults (`elem='PS'`, `hetatm=1`) | One-liner; no need to pick plausible values | Hiders trivially filterable; renders as ghost | **Never**. Always set `elem`/`resn`/`hetatm`. |
| Track hiders by `(resi, chain)` | Human-readable in debug | Collisions with real residues; ambiguous | Only as a **secondary** debug aid; primary identity must be `id`. |
| Delete hiders one-by-one on "found" | Feels responsive | Index shift corrupts registry of remaining hiders | **Never**. Mark found (recolor/reps), bulk-remove at Cleanup. |
| `cmd.get_model(obj)` to inspect all atoms | Pythonic; one call | Copies entire structure into Python — OOM on 1GZM/3GP6 | Only for small molecules (<5 k atoms). Use `cmd.iterate` for large. |
| Threaded timer with `cmd.*` calls | "Real-time" feel | Deadlocks / segfaults (Pitfall 6) | **Never**. `QTimer` on main thread is sufficient at 1 Hz. |
| Store game state only in `.pse` | One file to share | Timer/registry lost on reload; inconsistent resume | **Never**. Sidecar `.json` + `.pse` together. |
| Cleanup via `cmd.remove('hetatm')` | One-liner | Deletes ligands/membrane (Pitfall 9) | **Never**. Use `segi GAME` sentinel. |
| Skip the `_bchm_orig_backup` snapshot | Faster Start | No recovery from botched mutation (Pitfall 10) | **Never**. Always snapshot before mutation. |
| Hard-code the mouse pick mode number | Avoids a runtime lookup | Breaks if PyMOL renumbers modes in a minor release | Only with a comment + runtime verification. |
| Inline `cmd.do(...)` string commands | Quick to write | No type checking; harder to debug; selection quoting bugs | Only for one-off admin commands. Use the function API. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| PyMOL Qt event loop | Spinning a separate `Tk().mainloop()` or `QApplication.exec_()` | Use the existing `pymol.Qt` QApplication; `dialog.show()` only, never call `exec_()` on a new loop. |
| `cmd.set_key` shortcuts | Binding `CTRL-A` etc. and not unbinding on unload | Save prior binding, restore on plugin unload (`cmd.set_key(key, prior)`). `bnitools.py` binds `CTRL-A` — note it owns that key for the session. |
| PyMOL `sele` / `pk1` selections | Assuming `sele` is empty at plugin start | A prior user action may have left `sele` non-empty. Always `cmd.select('sele', 'none')` (or read and clear) before relying on it. |
| `cmd.get_names("selections")` | Polling every frame without tracking last-seen state | Cache the last `pk1` identity; ignore unchanged picks. Otherwise the same click fires every frame. |
| `cmd.load_callback` | Forgetting `__getstate__`/`__setstate__` | Implement both; pop non-picklable (Qt, timers, files) in `__getstate__`; rebuild in `__setstate__`. See `dynoplot.py`. |
| `cmd.fuse` modes | Passing mode=0 (default) when you want a bonded insert | Read `editor.py`: mode 1/2/3 differ in bond geometry. Test the resulting bond with `cmd.distance`. |
| `cmd.alter` with `space=` | Using module-globals and hitting scope bugs | Pass an explicit `space={...}` dict (the `editor.py` pattern: `space={'tmp': tmp}`). |
| `cmd.get_unused_name(prefix)` | Hardcoding `tmp1`, `tmp2` names | Use `cmd.get_unused_name('_bchm_tmp')` to avoid collisions with user objects or other plugins. |
| WSL ↔ Windows PyMOL path passing | Passing `os.path.join('/mnt/c/...', 'x.pdb')` to a Windows PyMOL | Normalize to `C:\...\x.pdb` before any `cmd.load` when PyMOL runs via `setenv.bat`. See Pitfall 11. |
| `pymol.plugins.pref_set` | Storing setup as Python objects | Only basic types (`str/int/float/list/tuple/dict`) are supported (per `PluginArchitecture` wiki). JSON-encode anything complex. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `cmd.get_model(obj)` on every click | RAM spikes; click latency grows | Use `cmd.iterate(sele, '...')` with `space=` (streams, no full copy) | >5 k atoms; fatal at 100 k+ (1GZM/3GP6 membrane) |
| Python loop over all atoms to find neighbors | Generate takes minutes | `cmd.select('obj within 8 of hider_pos')` is C-side and fast | >1 k atoms |
| Rebuilding all reps after each insert | Each hider adds seconds | `cmd.show(rep, 'obj and segi GAME')` — only the new hider's rep | >10 hiders on a 50 k atom object |
| `cmd.iterate` without `space=` (uses `stored.` global) | Slow; pollutes global namespace | Pass `space={'out': []}` dict | Always — it's a correctness + perf win |
| Polling `pk1` every frame via `load_callback` | Constant CPU even when idle | Only check `if 'pk1' in cmd.get_names('selections')` and cache last-seen | Long idle sessions |
| `spectrum b` recolor on every found-hider | UI stutter | Recolor only the found hider (`cmd.color('green', 'obj and id N')`) | >5 found hiders |
| Large PDB load without stripping water | Slow load, huge memory | Strip water/salt and compress before bundling (per `PROJECT.md` Demo data strategy) | Membrane proteins with full solvation |
| `cmd.create('_backup', obj)` on every action | Object menu clutter; RAM doubles | Snapshot once at Start; delete on unload | Frequent restarts |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Auto-fetching membrane PDBs from a hardcoded URL on plugin load | Network dependency for offline demos; MITM risk; URL rot | Bundle small PDBs; fetch large ones on-demand *only* when user requests that demo. Validate checksums if available. |
| `cmd.load(user_input_path)` without sanitization | Path traversal / loading arbitrary files (low risk, local user) | This is a local desktop plugin, so risk is low — but still validate extension and catch `CmdException` to give a clean error. |
| Vendoring an unapproved 3rd-party lib into `3rd_party_lib/` without noting its license | License violation; repo contamination | Per `PROJECT.md` Constraints: list every non-PyMOL dep to a file, get user approval, note license in the vendored dir. |
| Shipping membrane coordinates from MemProtMD without verifying their license | License violation; attribution failure | MemProtMD license verified (CC-BY 4.0, 2026-08-14). Cite Newport et al. Nucleic Acids Res. 2019 (DOI: 10.1093/nar/gky1047) + Stansfeld et al. Structure 2015 (DOI: 10.1016/j.str.2015.05.006) and link to the entry page. |
| Including a PDB in the bundle without citing its DOI | Violates RCSB attribution request | Per RCSB policy: cite PDB ID + DOI (`https://doi.org/10.2210/pdbXXXX/pdb`) + corresponding publication. Generate a `DATA_SOURCES.md` with all citations. |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Modal setup window blocks the viewer | User can't see the molecule while configuring | Modeless `dialog.show()`; user can rotate/zoom while setting params |
| "Start" doesn't visually confirm hiders were placed | User unsure if generation worked | Flash the hiders briefly (show as spheres, then revert) — a "did you see them?" moment |
| Click sensitivity: drag-to-rotate registers as a click | Accidental "finds" while navigating | Threshold by mouse displacement + time (Pitfall 5); ignore picks during camera motion |
| No visual feedback on a wrong-atom click | Player doesn't know if they missed or the game is broken | Brief flash on the clicked (non-hider) atom: "not a hider" — cheap, huge UX win |
| Timer keeps running while a Qt modal (file dialog) is open | Times are unfair across save/load operations | Pause timer on any modal dialog; resume on return |
| "Reveal-all" without confirm (per `PROJECT.md`) destroys the score | Accidental reveal ends the game | Confirm dialog (Qt `QMessageBox.question`) — already specced, don't skip |
| Hider count too high for small molecule | Game is unfindable; player quits | Cap based on atom count / rep complexity (per `PROJECT.md`: "capped to a reasonable maximum") |
| Membrane protein (100 k+ atoms) loads with no progress indicator | UI looks frozen | Show a `QProgressDialog` (modeless) during fetch + load + strip; cancelable |
| Found-hider recolor same as a real-atom color | Player can't tell found vs. real | Use a distinct sentinel color (e.g., neon green) and document it in the in-game explanation |

## "Looks Done But Isn't" Checklist

- [ ] **GUI:** Often missing the `global dialog` reference — dialog flashes and disappears. Verify by opening twice in one session.
- [ ] **Generator:** Often missing `elem`/`hetatm` on `pseudoatom` — hiders render as ghost PS spheres. Verify with `cmd.iterate(obj + ' and segi GAME', 'print elem, hetatm')`.
- [ ] **Generator (cartoon):** Often places a Cα pseudoatom and assumes cartoon renders — it doesn't. Verify `cmd.count('cartoon', obj + ' and segi GAME') > 0`.
- [ ] **Game loop (click):** Often works in the dev's mouse mode but not default. Verify on a fresh `pymol -x` with no `~/.pymolrc`.
- [ ] **Game loop (drag):** Often fails to disambiguate drag vs click. Verify by rotating the view and checking no spurious "found".
- [ ] **Save-load:** Often saves `.pse` but not the sidecar `.json`. Verify by Save → quit PyMOL → relaunch → Load → check timer and found-count.
- [ ] **Save-load (callback):** Often missing `__getstate__`/`__setstate__`. Verify by Save → Load and checking no `TypeError` in console.
- [ ] **Cleanup:** Often uses a generic filter. Verify on 1GZM/3GP6: after Generate → Cleanup, atom count == pre-Start count.
- [ ] **Restart:** Often doesn't restore original reps. Verify by setting an unusual rep before Start, Restart, and checking the rep is back.
- [ ] **Demos (large):** Often fetches synchronously and freezes. Verify the 3GP6 demo fetch shows a progress dialog.
- [ ] **Demos (attribution):** Often ships PDBs without a `DATA_SOURCES.md`. Verify the file exists and lists every PDB ID + DOI + MemProtMD/SASBDB entry.
- [ ] **Cross-platform:** Often works in WSL dev syntax-check but breaks in Windows PyMOL. Verify the plugin loads and runs end-to-end via `setenv.bat` (Pitfall 11).
- [ ] **Unload:** Often leaves `cmd.set_key` bindings and `_bchm_*` temp objects. Verify by unloading the plugin and checking `cmd.get_names('all')` is clean.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Tkinter GUI built (Pitfall 1) | **HIGH** (rewrite UI layer) | Port to `pymol.Qt`; rebuild dialogs from `.ui` files; re-test all interactions. |
| Hiders in wrong object (Pitfall 2) | **MEDIUM** | Change generator to use `pseudoatom(object=existing)` / `fuse`; re-test visibility rules. |
| Hiders trivially visible (Pitfall 3) | **LOW** | Add explicit `elem`/`resn`/`hetatm` args to `pseudoatom` calls; re-verify with `iterate`. |
| Registry points at wrong atoms (Pitfall 4) | **MEDIUM** | Switch identity to `id` + sentinel; add reconstruction from sentinel; re-test found-tracking. |
| Click not detected (Pitfall 5) | **MEDIUM** | Add `load_callback` polling `pk1`; add drag threshold; force mouse mode; re-test on fresh PyMOL. |
| Thread deadlock (Pitfall 6) | **MEDIUM** | Move all `cmd.*` to main thread; replace `Thread` with `QTimer`; re-test long sessions. |
| Game state lost on reload (Pitfall 7) | **MEDIUM** | Add sidecar `.json`; add `__getstate__`/`__setstate__` to callback; re-test round-trip. |
| Cartoon hiders invisible (Pitfall 8) | **MEDIUM** | Replace `pseudoatom` with `fuse`/`attach_amino_acid`; verify `cmd.count('cartoon', ...)`; re-test unwinnability. |
| Cleanup deleted real atoms (Pitfall 9) | **HIGH** (data loss if no backup) | If backup exists: `cmd.delete(obj); cmd.create(obj, backup)`. If not: user must reload from disk. Fix: sentinel-based cleanup + snapshot. |
| No undo, object corrupted (Pitfall 10) | **LOW** (if snapshot exists) | `cmd.delete(obj); cmd.create(obj, '_bchm_orig_backup')`. Fix: always snapshot. |
| WSL/Windows path bug (Pitfall 11) | **LOW** | Add a `to_windows_path()` helper; re-test loading a bundled PDB via `setenv.bat`. |
| Large-molecule OOM (Pitfall 12) | **MEDIUM** | Replace `get_model` with `iterate`; add streaming neighbor search; re-test on 3GP6. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Tkinter vs PyQt5 | **setup** | Plugin imports only `pymol.Qt`, no `Tkinter`/`Pmw`. |
| 2. Hiders in wrong object | **generator** | `cmd.get_names("objects")` unchanged after Generate. |
| 3. Pseudoatom defaults visible | **generator** | `cmd.iterate(obj + ' and segi GAME', '...')` shows real elem/hetatm. |
| 4. Unstable hider identity | **generator** + **game loop** + **save-load** | Click each hider in sequence; ids stay correct; reload preserves mapping. |
| 5. Click detection | **game loop** (doc in **setup**) | Works on fresh `pymol -x`; drag doesn't fire finds. |
| 6. Thread safety | **game loop** + **generator** | 30-min play session on 3GP6: no deadlock/segfault. |
| 7. .pse round-trip | **save-load** | Save → quit → relaunch → Load: timer + found-count preserved. |
| 8. Cartoon hiders invisible | **generator** | `cmd.count('cartoon', obj + ' and segi GAME') == cartoon_hider_count`. |
| 9. Cleanup over-matches | **generator** + **game loop** (verify in **demos**) | 1GZM: Generate → Cleanup → atom count == pre-Start. |
| 10. No undo | **setup** + **save-load** | Snapshot at Start; Restart restores original; botched mutation recoverable. |
| 11. WSL/Windows paths | **setup** + **demos** | Bundled PDB loads via `setenv.bat` with no path error. |
| 12. Large-molecule perf | **generator** + **demos** | 3GP6 with membrane: Generate < 30 s; click latency < 200 ms. |
| 13. Demo licensing/attribution | **demos** | `DATA_SOURCES.md` lists every PDB ID + DOI + MemProtMD/SASBDB entry + license. |

---

## Phase 3 — Resolved Research Flags (runtime-verified 2026-08-06)

The Phase 3 smoke test (`smoke/phase3_smoke.py`, plan 03-15) ran headlessly via Windows PyMOL (`cmd.exe /c C:\\src\\run-conda-pymol.bat -cq` from the staged WSL→Windows path) and reached **24/24 ALL PASSED, exit 0**. It resolved the UNVERIFIED/MEDIUM flags from `03-RESEARCH.md` with runtime-confirmed values. **Future research must NOT re-investigate these** — the values below are confirmed at the PyMOL 2.5.0 runtime tier.

Source: `.planning/phases/03-mutation-safety-hider-registry-foundation/03-15-SUMMARY.md`.

### Q1 — `cmd.pseudoatom` return value: RESOLVED (informational)

- **Finding:** `cmd.pseudoatom(...)` returns `None` (type `NoneType`). It does NOT return the new atom's id, a status code, or an object reference.
- **Conclusion:** Code NEVER relies on the return value. `biochemeleon/mutation.py::insert_hider` fetches the stable id via `cmd.identify(f"{object} and name {handle} and segi GAME", mode=0)` + `assert len(ids) == 1` + `return ids[0]` (mode=0 returns the id list, NOT the fragile index — see Pitfall 4). The Q1 finding is informational only.
- **Status:** RESOLVED (informational). Confirms RESEARCH §Q1.

### Q2 — `cmd.create` merge-vs-replace (single-call `create(existing, src)`): RESOLVED (REPLACE)

- **Finding:** A single-call `cmd.create(existing_obj, src_obj)` IS a **REPLACE**, not an append/merge — `n_after == n_before` (the existing object's atom count is unchanged; the source atoms replace the existing object's contents rather than adding to them). No doubling.
- **Conclusion:** `backup.restore` uses the explicit two-step `cmd.delete(target)` + `cmd.create(target, backup)` (delete removes the mutated object entirely; create makes a fresh atom-for-atom copy from the backup) — unambiguous and correct regardless of the single-call behavior. The smoke test confirmed the restore brings the target back atom-for-atom (criterion 4 failure path: `abort_on_error()` returns True, count back to orig). The single-call REPLACE finding documents the behavior but does not change the implementation.
- **Status:** RESOLVED. RESEARCH §Q2 MEDIUM flag cleared. `backup.py` (03-05/03-12) delete+create is canonical.

### Q2b — `cmd.create` id-preservation across copy: RESOLVED

- **Finding:** `cmd.create` copies preserve atom `id`s (the restored target's id-set matches the backup's). The happy-path cleanup (`mutation.cleanup_hiders` by sentinel) preserves all original ids; the abort/restore path rebuilds from a backup whose ids match the pre-game ids.
- **Conclusion:** Affects only the abort/restore path, and the registry is rebuilt fresh on the next `start()` anyway (per the 03-11 contract: `start()` builds a fresh `HiderRegistry`). Happy path (cleanup via `cmd.remove` by sentinel) preserves ids. The registry does NOT depend on ids surviving `create` — it rebuilds from sentinels via `reconstruct_from_sentinels` after `.pse` reload.
- **Status:** RESOLVED.

### PSE — `.pse` round-trip id/sentinel stability: RESOLVED (sentinel-survives is load-bearing; id-stable)

- **Finding:** The `segi='GAME'` sentinel SURVIVES `.pse` save/load (after `cmd.save` + `cmd.delete` + `cmd.load`, `len(pse_sent) == 1` — the sentinel atom is found; `segi=GAME` survives). The atom `id` is STABLE across the round-trip (`pse_sent == [saved_id]` — Pitfall 4 holds at the runtime tier). `b=-999.0` is preserved exactly. `reconstruct_from_sentinels` rebuilds a 1-record registry with `rep=None` (the sentinel carries no rep — RESEARCH Open Risk 6 confirmed; Phase 8 `.bcm` sidecar reconciles `rep`).
- **Conclusion:** Sentinel-survival is LOAD-BEARING (the whole reconstruct-after-reload mechanism depends on it — confirmed). Id-stability is informational (even if ids shifted, `reconstruct_from_sentinels` keys the registry by the post-reload ids it reads via `fetch_all_hider_ids`, so a shift would just produce a different-but-correct key). The `.bcm` sidecar (Phase 8) recovers `rep`, which the sentinel cannot carry.
- **Status:** RESOLVED. Pitfall 4 (id stable across add/remove) and Pitfall 7 (.pse round-trip) both confirmed at the runtime tier.

### New runtime pitfalls discovered during the Phase 3 smoke (all RESOLVED in code)

These were NOT in the original research — discovered when the headless smoke crashed at each; each auto-fixed (Rule 1 bug / Rule 3 blocker) and committed. Recorded here so future phases don't re-trip them.

- **`cmd.iterate` exposes atom `id` as uppercase `ID`, NOT lowercase `id`** (the Python builtin). All iterate expressions must use `ID` (uppercase) — the `03-RESEARCH.md` symbol table was authoritative; lowercase `id` is a transcription error that errors or appends the wrong value. Fixed in `mutation.py` + `smoke/phase3_smoke.py` (commit `e38cff7`). **Rule:** PyMOL iterate symbols are case-sensitive and UPPERCASE (`ID`, `MODEL`, `RESN`, `RESI`, `NAME`, `CHAIN`, `SEGI`, `B`, etc.).
- **`cmd.iterate` does NOT expose `x`/`y`/`z` coordinates** (they are state-dependent; `cmd.iterate_state` is needed for coords). For structure-identity checks, `count` + `(resn, resi, name, chain, segi)` multiset suffices because `cmd.create` copies coords bit-for-bit (RESEARCH §Q6 fallback). `backup.verify_intact` identity tuple is `(resn, resi, name, chain, segi)` WITHOUT coords (commit `5ed6a13`).
- **PyMOL b-factor selectors are COMPARISONS, never exact matches.** `b -999` is INVALID syntax ("Selector-Error: Malformed selection") and SILENTLY matches nothing (no exception — returns `[]`, a dangerous failure mode because the count looks plausible). `b < 0` is valid comparison syntax and matches `-999.0`. The sentinel VALUE stays `-999` (set in `insert_hider` + cleanup docstrings); only the SELECTOR uses `b < 0`. Fixed in `mutation.py:113` `fetch_all_hider_ids` (commit `6a15a29` — the load-bearing fix that unblocked the 2 PSE-reconstruct checks). **Rule:** b-factor sentinels are matched by comparison (`b < 0`, `b > N`), never exact (`b -999`).

---

## Moderate Pitfalls (in the table sections above — called out for emphasis)

### Pitfall 11: WSL dev path vs Windows PyMOL runtime — `setenv.bat` path mismatch

**What goes wrong:** The plugin is developed and syntax-checked in WSL (Python 3.6, per `PROJECT.md` Context). Paths in the code use POSIX form (`/mnt/c/Users/.../data/1znf.pdb`) or `os.path.join` with POSIX separators. The plugin is then run in Windows PyMOL (anaconda) launched via `setenv.bat`. `cmd.load('/mnt/c/...')` fails with "File not found" because Windows PyMOL expects `C:\...\1znf.pdb`. Conversely, `setenv.bat` sets env vars (`PYMOL_PATH`, `PYTHONPATH`, etc.) in the Windows cmd context — those vars are **not** visible to WSL-side syntax checks, and vice versa.

**How to avoid:**
- Define a `to_windows_path(p)` helper that converts `/mnt/c/...` ↔ `C:\...` and normalize all paths before passing to `cmd.load`/`cmd.save`. Detect the environment at runtime (e.g., `sys.platform`).
- For bundled demo PDBs, resolve paths relative to `__file__` of the plugin (PyMOL installs plugins into a known dir; the data dir ships alongside `__init__.py`).
- The `setenv.bat` workflow: it sets env vars then launches `pymol.exe`. The plugin's `__init_plugin__` runs inside that env. Do not assume any WSL-side env var is set.
- Test the full path resolution via `setenv.bat` early in the **setup** phase with one tiny demo PDB; do not wait until **demos** to discover path bugs.

**Warning signs:** `cmd.load` raises `pymol.CmdException: unable to open file`; plugin works when copied manually into the PyMOL startup dir but fails when launched via the bat; `os.path.exists` returns True in WSL but `cmd.load` fails in Windows.

**Phase to address:** **setup** (helper + first end-to-end load test) + **demos** (all bundled PDBs verify).

### Pitfall 12: 100k+ atom membrane proteins (1GZM, 3GP6 with full membrane) — OOM and latency

**What goes wrong:** The generator uses `cmd.get_model(target_obj)` to enumerate atoms and find placement spots. For a 100k+ atom membrane protein with full DPPC membrane, `get_model` copies the entire structure into Python — RAM spikes to multiple GB and the call takes 10+ seconds. Per-hider neighbor search in Python loops takes another 10+ seconds each. The "Start" button appears to freeze; on low-RAM machines PyMOL crashes.

**How to avoid:**
- Never `cmd.get_model` on large objects. Use `cmd.iterate(obj, '...', space=...)` (streams, no copy) for atom enumeration.
- For neighbor search, use C-side selection: `cmd.select('_tmp_nbr', 'obj within 8 of [x,y,z]')` — fast even at 100k atoms.
- For hider placement, sample candidate positions C-side: `cmd.select('_tmp_ca', 'obj and name CA')`, then `cmd.iterate` only the Cα coords into a numpy array (memory: 100k × 3 × 8B ≈ 2.4 MB — fine). Do placement math in numpy, not in Python loops.
- Strip water and salt from large demos before bundling (`PROJECT.md` Demo data strategy); compress with gzip.
- Show a modeless `QProgressDialog` during fetch + load + strip + generate for the large demos; make it cancelable.
- Performance budget: Generate on 3GP6 (with membrane) < 30 s on a mid-range laptop; click latency < 200 ms.

**Warning signs:** "Start" freezes for >5 s on small molecules (the bug scales — it'll be minutes on 3GP6); PyMOL RSS exceeds 2 GB; `cmd.get_model` appears anywhere in the generator.

**Phase to address:** **generator** (memory discipline) + **demos** (verify 3GP6).

---

## Minor Pitfalls

### PyMOL command quirks

- **`cmd.alter(sele, expression, space=...)`** mutates atom properties in place; the expression is Python-evaluated per atom. Use `space={'tmp': tmp}` to pass variables in (the `editor.py` pattern). Without `space=`, you're stuck with the global `stored.` pseudo-module, which is slow and pollutes global state.
- **`cmd.fuse(mobile, target, mode=1|2|3)`** *moves* `mobile` into the target object and bonds them. After fuse, `mobile` no longer exists as a separate selection — don't try to delete it.
- **`cmd.create(name, selection, ..., extract=1)`** moves atoms from source to a new object (the `cmd.extract` shorthand). Useful for "pull hiders out into a preview object" — but breaks the "same object" rule. Use only for debug.
- **`cmd.unpick()`** clears `pk1`/`pk2`/`pk3`/`pk4`. Call it after processing a pick to avoid re-processing.
- **`cmd.get_unused_name('_bchm_tmp')`** generates a unique name — use it for every transient selection/object to avoid clobbering user state or other plugins.
- **`cmd.delete('_bchm_*')`** wildcards work — use a consistent prefix for all plugin-created transients and clean up on unload.
- **`cmd.set_key`** bindings persist for the whole PyMOL session, even after the plugin dialog is closed. Save the prior binding (if any) and restore on unload. `bnitools.py` binds `CTRL-A` — don't collide with it.

### Representation-specific

- `lines` and `sticks` render bonds. A hider atom with no bonds is invisible in `lines`/`sticks`. Use `cmd.bond(hider, neighbor)` to give it a bond, or show it as `spheres`.
- `spheres` renders any atom with a `vdw` radius. Pseudoatoms with `vdw=-1.0` get a default; set `vdw` to the element's radius for correct sizing.
- `cartoon`/`ribbon` require polymer trace (Pitfall 8).
- `surface` is out of scope (`PROJECT.md`) — good, because surface is a computed mesh over an object and doesn't "blend" a foreign atom in any useful way.
- `nonbonded` (dots) can render a lone atom — useful as a fallback rep for sphere hiders.

### Licensing/attribution specifics (HIGH confidence for RCSB/SASBDB/MemProtMD)

- **RCSB PDB** (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3, 1GZM, 3GP6): **CC0 1.0 Public Domain Dedication** (per official wwPDB policy, confirmed at `rcsb.org/pages/policies`). Free to bundle and redistribute. **Attribution is requested**: cite PDB ID + DOI (`https://doi.org/10.2210/pdbXXXX/pdb`) + the corresponding structure publication + the molecular graphics program (PyMOL). Generate a `DATA_SOURCES.md` listing all of these.
- **SASBDB** (Alpha-1-glycoprotein model, per `PROJECT.md` Note 1): per official `/about/` page: *"free of all copyright restrictions and made fully and freely available for both non-commercial and commercial use. Users of the data should attribute the original authors."* Cite the SASBDB entry ID and the original authors.
- **MemProtMD** (1GZM helix, 3GP6 sheets with full DPPC membrane): the site is reachable at `memprotmd.bioch.ox.ac.uk` (the prior "unreachable" was a domain typo — "oxy" instead of "ox" in the hostname). HIGH confidence — the license is CC-BY 4.0 International (verified 2026-08-14 from the site JS bundle). The corrected citations are: Newport TD, Sansom MSP, Stansfeld PJ. *The MemProtMD database: a resource for membrane-embedded protein structures and their lipid interactions.* Nucleic Acids Res. 2019;47(D1):D390-D397. DOI: 10.1093/nar/gky1047 (database paper, primary); Stansfeld PJ et al. *MemProtMD: Automated Insertion of Membrane Protein Structures into Explicit Lipid Membranes.* Structure. 2015;23(7):1350-1361. DOI: 10.1016/j.str.2015.05.006 (methodology). License: CC-BY 4.0 (verified 2026-08-14 from the site JS bundle). **The membrane coordinates (the DPPC bilayer) come from MemProtMD and carry CC-BY 4.0** — attribution is mandatory (stricter than PDB's CC0). The PDB entries (1GZM, 3GP6) themselves are CC0.
- **PyMOL itself**: cite Schrödinger LLC / `pymol.org` per standard practice.

## Sources

- **PyMOL Open Source `editor.py`** (`raw.githubusercontent.com/schrodinger/pymol-open-source/master/modules/pymol/editor.py`) — HIGH. Verified: `cmd.fuse` modes, `cmd.attach_amino_acid`, `cmd.attach_nuc_acid`, `cmd.edit`, `pk1`/`pk2` picking selections, `undocontext` "not implemented in open-source" stub, `cmd.alter(..., space=...)`, `cmd.fragment`, `cmd.delete(tmp_wild)` cleanup pattern, threaded `fab` uses `setDaemon(1)`.
- **PyMOL Open Source `creating.py`** (same repo) — HIGH. Verified: `cmd.pseudoatom` signature + defaults (`elem='PS'`, `resn='PSD'`, `chain='P'`, `segi='PSDO'`, `hetatm=1`), `cmd.create` + `extract`, `cmd.copy`, `cmd.fragment`, `cmd.group` actions, `_self.lock`/`lockcm` threading guards on every command.
- **PyMOL Open Source `selector.py`** — HIGH. Verified canonical atom-id form `"%s`%d" % (model, index)`.
- **PyMOL Wiki `/Plugins`** (edited 2024-05-15) — HIGH. Quote: *"support for plugins written in Tkinter is considered deprecated with full expectation of removal by PyMOL 4.0 ... the preferred toolkit for new plugins is PyQt5."*
- **PyMOL Wiki `/Plugins_Tutorial`** — HIGH. `__init_plugin__(app=None)` + `addmenuitemqt` + `from pymol.Qt import QtWidgets` + `from pymol.Qt.utils import loadUi`; global dialog reference required; demo plugin at `github.com/Pymol-Scripts/pymol2-demo-plugin`.
- **PyMOL Wiki `/PluginArchitecture`** — HIGH. `pymol.plugins.pref_set/get` for settings (basic types only); single-file vs directory layout; `__init_plugin__(app)` legacy Tk note.
- **PyMOL Wiki `/Save`** — HIGH. *".pse ... the complete PyMOL state is always saved ... selection and state parameters are thus ignored."*
- **`Pymol-script-repo/plugins/dynoplot.py`** (ported to PyQt 2024 by Thomas Holder) — HIGH. Patterns: `cmd.load_callback(self, name)` with `__call__` per-frame, `__getstate__`/`__setstate__` popping `canvas` (Qt widget not picklable), atom id form `(%s`%d) % point["meta"]`, `cmd.select('sele', '(%s`%d)' ...)`, `cmd.iterate('sele', '... (model, segi, chain, resn, resi, name)')`.
- **`Pymol-script-repo/plugins/show_contacts.py`** — HIGH. Qt-vs-Tk dual implementation pattern; `cmd.get_names('all', 1)` for object enumeration; `addmenuitemqt` with Tk fallback.
- **`Pymol-script-repo/plugins/mtsslDockGui.py`** — MEDIUM. Threading pattern: `threading.Thread(target=..., setDaemon(1), .start())` + `self.parent.after(50, self.check_thread)` polling — confirms cmd.* must be marshalled to main thread.
- **`Pymol-script-repo/plugins/emovie.py`** — MEDIUM. Explicit `# self.grab_set()  #comment this out so that user can keep storyboard open` — direct evidence that modal grab blocks PyMOL viewer interaction.
- **`Pymol-script-repo/plugins/rendering_plugin.py`** — MEDIUM. UI label *"NOTE: make sure this window is not on top of the PyMOL window."* — direct evidence of Tk z-order issues.
- **`Pymol-script-repo/plugins/bnitools.py`** — MEDIUM. `cmd.set_key('CTRL-A', cmd.select, ("sele", "visible", 1))` — keyboard binding that persists for the session.
- **RCSB PDB `/pages/policies`** — HIGH. *"data files contained in the PDB archive are available under the CC0 1.0 Universal (CC0 1.0) Public Domain Dedication."* Citation policy: cite PDB ID + DOI + publication + graphics program.
- **SASBDB `/about/`** — HIGH. *"free of all copyright restrictions and made fully and freely available for both non-commercial and commercial use. Users of the data should attribute the original authors."*
- **MemProtMD** (`memprotmd.bioch.ox.ac.uk`) — **reachable** (verified 2026-08-14, HTTP 200). HIGH confidence: license is CC-BY 4.0 (verified from site JS bundle); cite Newport et al. Nucleic Acids Res. 2019 (DOI: 10.1093/nar/gky1047, primary) + Stansfeld et al. Structure 2015 (DOI: 10.1016/j.str.2015.05.006, methodology).

---
*Pitfalls research for: PyMOL 2.x plugin — interactive molecular hide-and-seek game (bioCHEMeleon v1)*
*Researched: 2026-08-02*
