# Phase 10 Research: Help, Tooltips & Controls (UX-01 + UX-02 + README)

**Researched:** 2026-08-17
**Domain:** PyMOL 2.5.0 plugin UX — tooltips, help dialog, mouse/keyboard controls reference, README finalization
**Confidence:** HIGH (controls verified against PyMOL 2.5.0 open-source in `tmp/pymol-src/`; widget inventory read from live code)

## Summary

The implementation is a low-risk, additive UX pass: (1) add concise `setToolTip()` text to every user-facing widget in `gui_setup.py` / `gui_game.py` that lacks one, plus per-representation explanations on the 5 per-rep checkboxes; (2) add a **Help** button to `PluginDialog` (`__init__.py`) that opens a **modal child `QDialog`** with a read-only rich-text `QTextEdit` covering what bioCHEMeleon is, the Setup/Game tabs, the 5 representations, PyMOL controls, and the "switch reps to spot hiders" strategy; (3) finalize `README.md` from "UNDER DEVELOPMENT" to "v1 complete." The PyMOL controls reference is the one piece that must be **verified, not invented** — and it has been: the default 3-Button Viewing mouse mapping was read directly from `controlling.py` (the authoritative source that defines the defaults). The single most important — and counterintuitive — finding is that in the default mode the **plain scroll wheel adjusts the clipping slab, NOT zoom**; zoom is Right-drag or Shift+Left-drag (box zoom) or Ctrl+wheel. The click-to-find action is a **single left-click** on an atom (the `PickWizard` re-routes selection clicks through `do_pick` while keeping left-drag rotation working).

**Primary recommendation:** Add tooltips to all un-tooltipped widgets, add a modal Help `QDialog` launched from a Help button in the `PluginDialog` button row, write the controls text from the verified mapping below (NOT from memory), and rewrite the README to reflect the shipped v1 feature set including the endgame (assume SC3/SC4 land in the same phase).

---

## UX-01: Widget Tooltip Inventory

Source: read of `biochemeleon/gui_setup.py`, `biochemeleon/gui_game.py`, `biochemeleon/__init__.py`, plus `grep -rnE "setToolTip" biochemeleon/` (7 existing tooltips confirmed).

**Existing tooltips (already set — leave as-is unless refining):**

| Widget | File:line | Has tooltip | Existing text |
|--------|-----------|-------------|---------------|
| `obj_refresh_btn` | gui_setup.py:86 | YES | "Refresh loaded objects" |
| `export_btn` | gui_setup.py:207 | YES | "Generate hiders and save the initial game state to a file for sharing or later loading. Does NOT start play — your model keeps the generated hiders (press Cleanup to restore your scene)." |
| `cleanup_btn` | gui_setup.py:215 | YES | "Remove all game-generated hiders and restore the model to its original state. (Does not start a new round — use Start for that.)" |
| `_color_btn` | gui_game.py:54 | YES | "Choose highlight color for found hiders" |
| `_restart_btn` | gui_game.py:57 | YES | "Start a fresh round with new hiders" |
| `_import_btn` | gui_game.py:67 | YES | "Load a puzzle prepared by 'Generate & export' and play it." |
| `_save_btn` | gui_game.py:70 | YES | "Save the current game state to resume later." |

**Tooltips to ADD (draft text — keep to 1 sentence, student-friendly):**

### `gui_setup.py` (Setup tab)

| Widget | Line | Draft tooltip |
|--------|------|---------------|
| `mode_combo` (Source) | 72 | "Choose where the target molecule comes from: a loaded object, a PDB code fetched online, or a bundled demo." |
| `obj_combo` (loaded-objects combo) | 81 | "Pick a molecule already loaded in PyMOL, or type its object name." |
| `pdb_edit` (PDB fetch field) | 92 | "Type a 4-character PDB code (e.g. 1ubq) to download from the RCSB. Needs an internet connection." |
| `fetch_btn` | 94 | "Download the typed PDB code from the RCSB website." |
| `pool_list` (QListWidget) | 103 | "Your pool of PDB codes for Randomize's fetch mode. Empty list = use the bundled pool." |
| `pool_add_btn` ("+ Add") | 111 | "Add a new PDB code to the pool (must be 4 lowercase letters/digits)." |
| `pool_edit_btn` ("✎ Edit") | 112 | "Edit the selected PDB code in the pool." |
| `pool_remove_btn` ("− Remove") | 113 | "Remove the selected PDB code(s) from the pool." |
| `pool_default_btn` ("Use bundled pool") | 114 | "Reset the pool to the 34 bundled, pre-verified PDB codes." |
| `pool_choose_btn` ("Choose random") | 115 | "Pick a random code from the pool and put it in the fetch field." |
| `demo_combo` (bundled demo) | 124 | "Pick a bundled demo molecule. Tier (Easy → Very challenging) is shown in the name." |
| `lock_source_cb` | 146 | "When checked, Randomize keeps the current target and only re-rolls the hider composition." |
| `hider_spin` (Hider count) | 155 | "How many hider atoms to insert. Capped to a sane max for the chosen molecule." |
| `lock_scene_cb` | 159 | "Use the molecule's currently-shown representations instead of picking reps manually (locks the per-rep checkboxes to match the scene)." |
| per-rep `cb` ×5 (lines/sticks/spheres/cartoon/ribbon) | 168 | "Check to put some hiders in this representation. Leave unchecked to let the game decide (random). See Help for what each representation looks like." (This base tooltip applies to all 5; the per-rep *explanation* is a separate longer tooltip — see the next section.) |
| per-rep `spin` ×5 | 169 | "Number of hiders to hide in this representation (counts toward the total hider count)." |
| `diff_easy_cb` | 188 | "Easy: show how many hiders remain per representation. Hard: show only the total remaining." |
| `reset_btn` | 197 | "Reset every Setup field to the defaults." |
| `random_btn` | 198 | "Randomize the target, hider count, and representations." |
| `save_btn` ("Save Setup…") | 199 | "Save your current Setup to a .bcm.setup.json file to reuse later." |
| `load_btn` ("Load Setup…") | 200 | "Load a previously-saved Setup from a .bcm.setup.json file." |
| `start_btn` | 218 | "Generate the hiders and start the game (switches to the Game tab after a 3-2-1 countdown)." |

### `gui_game.py` (Game tab)

| Widget | Line | Draft tooltip |
|--------|------|---------------|
| `_info_log` (QTextEdit) | 24 | (Optional) "Rolling log of game events: hits, misses, hints, reveals." |
| `_timer_label` | 26 | "Elapsed time since the round began (counts up)." |
| `_remaining_label` | 27 | "How many hiders are still hidden. Easy mode shows a per-representation breakdown." |
| `_hint_btn` | 38 | "Reveal a clue: temporarily highlights atoms near one hider to point you toward it (counts as a hint used)." |
| `_reveal_one_btn` | 39 | "Give up on one random hider — it gets revealed and marked found (counts as a reveal used)." |
| `_reveal_all_btn` | 40 | "Give up and reveal every remaining hider at once. This ends the game." |
| `_found_mgmt_combo` | 47 | "After finding hiders, choose how to display them: Hide, Show, or Recolor the found hiders." |
| `_reveal_label` ("Reveals: 0") | 41 | "How many hiders you've revealed (via Reveal one / Reveal all). Shown on the win screen too." |

### `__init__.py` (PluginDialog) — NEW widget

| Widget | Draft tooltip |
|--------|---------------|
| `help_btn` (NEW "Help" button) | "Open the help panel: what each control does, what representations mean, and how to use the PyMOL viewer." |

> **Per-rep checkbox tooltips (UX-01 "what each representation means"):** The per-rep checkboxes should carry BOTH (a) the generic "check to put hiders in this rep" tooltip above AND (b) the representation explanation. The simplest way: make the per-rep checkbox tooltip the *concatenation* — e.g. for `cartoon`: "Check to put hiders in the cartoon representation. **Cartoon** = secondary-structure cartoon: helices, sheets, and loops drawn through the backbone. Leave unchecked for random." (See the Representation Explanations section for the 5 texts.) Recommendation: **put the short rep explanation directly in the per-rep checkbox tooltip**, AND repeat the full explanations in the Help panel (redundancy is good for discoverability — a tooltip appears on hover; the help panel is the comprehensive reference).

---

## UX-01: Representation Explanations (the 5 reps, student-friendly + accurate)

The 5 reps in `GAME_REPS` (`setup_state.py:23`) are a subset of PyMOL's full `rep_list` (`viewing.py:51-53`: lines, sticks, spheres, dots, surface, mesh, nonbonded, nb_spheres, cartoon, ribbon, labels, slice, ellipsoids, volume). The descriptions below are student-friendly and consistent with how PyMOL renders each rep (verified against the `show` docstring at `viewing.py:491-525` and standard PyMOL rendering behavior).

| Rep | Student-friendly explanation (draft — use in tooltip + Help panel) |
|-----|-------------------------------------------------------------------|
| **lines** | "Thin lines connecting bonded atoms. A lightweight overview of the whole molecule — fast and simple." |
| **sticks** | "Each bond drawn as a thin cylinder. Shows the bonding detail more clearly than lines." |
| **spheres** | "Each atom drawn as a sphere (roughly its Van der Waals radius). Gives a space-filling view of the molecule's surface." |
| **cartoon** | "A cartoon drawn through the backbone: helices as ribbons/coils, sheets as arrows, loops as tubes. The classic way to see secondary structure." |
| **ribbon** | "A flat ribbon drawn through the backbone. Simpler than cartoon — shows the overall fold without secondary-structure detail." |

> Accuracy notes: "spheres" uses Van der Waals radii (the `vdw_radius` setting scales them). "cartoon" requires backbone atoms (CA for protein, P for nucleic — see `__init__.py` `_continue_after_large_demo_fetch` which selects `name CA or name P`). "ribbon" is the simpler backbone trace. These match the game's generator behavior (cartoon/ribbon hiders copy a mid-chain backbone segment per Phase 11; lines/sticks hiders bond to a backbone anchor; spheres hiders are free-space). The phrasing stays at the "clear but sufficient" level the spec wants — no jargon without explanation.

---

## UX-01: Help Panel Design

### Dialog type: **Modal child `QDialog` with `.exec_()`** (RECOMMENDED)
- A reference dialog the user reads then dismisses → modal is the right UX (focus, dismiss with OK/Esc, blocks stray clicks in the 3D viewer behind it).
- **This is ALLOWED by the repo's Qt rules.** The exec_ grep gate currently returns **1** (the existing `_finish_win` `QMessageBox` at `gui_game.py:312`). Adding a Help `QDialog.exec_()` raises it to **2**, which is fine — AGENTS.md explicitly states: *"child QDialog .exec_() is ALLOWED (would increase the count — that's fine as long as it's only on child dialogs, never the main PluginDialog)."* The main `PluginDialog` stays modeless (`dialog.show()` — never `.exec_()`).
- Precedent in the codebase: `QMessageBox.question` (gui_game.py:114), `QInputDialog.getText` (gui_setup.py:374), `QFileDialog.getSaveFileName` (gui_setup.py:570), `QColorDialog.getColor` (gui_game.py:197) are all modal children. A Help `QDialog` follows the same pattern.

### Implementation: `QDialog` + `QVBoxLayout` + read-only `QTextEdit` (rich text) + OK button
- **Recommended widget stack** (simplest that renders well with headings/bullets/tables):
  ```python
  help_dlg = QtWidgets.QDialog(self)          # parent = PluginDialog
  help_dlg.setWindowTitle("bioCHEMeleon — Help")
  help_dlg.setMinimumSize(520, 600)
  layout = QtWidgets.QVBoxLayout(help_dlg)
  text = QtWidgets.QTextEdit()
  text.setReadOnly(True)
  text.setHtml(HELP_HTML)                    # module-level rich-text constant
  layout.addWidget(text)
  ok = QtWidgets.QPushButton("OK")
  ok.clicked.connect(help_dlg.accept)
  layout.addWidget(ok)
  help_dlg.exec_()                            # modal — allowed (child dialog)
  ```
- **Why `QTextEdit` read-only over `QLabel` in a `QScrollArea`:** `QTextEdit` natively scrolls long rich text, renders `<h2>`/`<ul>`/`<table>` cleanly, and supports copy-paste (users can copy a control description). A `QLabel` in a scroll area also works but is more verbose and tables render less reliably. `QTextEdit` is the standard Qt approach for a help/manual window.
- **Keep the help text in a module-level constant** (e.g. `HELP_HTML` in `__init__.py`, or a new `biochemeleon/help_text.py` if it's long). A string literal is fine — no need for a separate file unless it exceeds ~150 lines. **Recommendation:** put `HELP_HTML` directly in `__init__.py` as a module constant near the `PluginDialog` class (keeps the help close to the dialog that shows it; one file to edit).

### Content sections (the 6 the objective specifies)
1. **What is bioCHEMeleon** (1–2 sentences): "A hide-and-seek game on molecular structures. Foreign 'hider' atoms are inserted into a molecule's own object, styled to blend in — find them all by clicking atoms in the 3D viewer."
2. **Setup tab overview** (target, hiders, reps, difficulty, actions): one line per control group, mirroring the tooltips.
3. **Game tab overview** (log, timer, remaining, Hint, Reveal one/all, found-management dropdown, Color, Restart, Import, Save): one line per button, mirroring the tooltips.
4. **Representations explained** (the 5 reps — same text as the per-rep tooltips above, formatted as a list or table).
5. **PyMOL controls** (cross-ref to UX-02 — paste the verified controls table from the next section).
6. **Tips — switch reps to spot hiders** (the legitimate strategy; see the dedicated section below).

### Help button placement in `PluginDialog`
- **Recommended: a button row BELOW the `QTabWidget`**, right-aligned:
  ```python
  # In PluginDialog.__init__, after layout.addWidget(self.tabs):
  btn_row = QtWidgets.QHBoxLayout()
  btn_row.addStretch(1)
  self.help_btn = QtWidgets.QPushButton("Help")
  self.help_btn.clicked.connect(self._show_help)
  btn_row.addWidget(self.help_btn)
  layout.addLayout(btn_row)
  ```
- Why below the tabs (not a corner "?"): always visible regardless of active tab, doesn't crowd the tab bar, matches the existing layout (a `QVBoxLayout` containing the `QTabWidget`). A single right-aligned button is the simplest accessible-from-anywhere affordance.
- Alternative considered: a `Qt.WindowFlags` "?" context-help button. Rejected — it only shows a tiny per-widget tooltip on click in some Qt styles and is unreliable across platforms; a dedicated Help dialog is clearer for students.

---

## UX-02: PyMOL Controls Reference (VERIFIED — cite source files)

**This is the critical, must-not-be-invented section.** Every claim below is verified against the PyMOL 2.5.0 open-source in `tmp/pymol-src/`. Do NOT write controls from memory — use this verified mapping.

### What the default is
- The default mouse preset is **3-Button Viewing** (`three_button_viewing`). Source: `modules/pymol/controlling.py:130-132` defines `three_button` ring = `['three_button_viewing', 'three_button_editing']`; `controlling.py:204` sets `mouse_ring = ring_dict['three_button']` (the default ring); the first mode in the ring is `three_button_viewing`. The GUI menu (`_gui.py:819`) lists "3 Button Viewing" as the standard option. **HIGH confidence.**
- `mouse_selection_mode` has 7 values; the menu (`_gui.py:806-814`) labels them: 0=Atoms, 1=Residues, 2=Chains, 3=Segments, 4=Objects, 5=Molecules, 6=C-alphas. **HIGH confidence.**

### How `PickWizard` changes the mouse during play
- Read `biochemeleon/wizard.py`: the wizard sets `mouse_selection_mode=0` (Atoms — single-atom pick) on activate (`wizard.py:44`) and restores the saved mode on deactivate (`wizard.py:92`). **It does NOT change `button_mode`** (the 3-Button Viewing preset stays active). Source: `wizard.py:42-45`.
- **Consequence:** during play, left-drag still rotates (essential for spin-to-find — the wizard.py docstring calls this out explicitly: *"This preserves left-drag rotation (essential for spin-to-find)"*). A single left-click routes through `do_select` → `do_pick` → `GameController.on_pick` (the click-to-find path). Source: `wizard.py:69-84`.
- The wizard's `get_panel` (`wizard.py:94-96`) adds a "Done (quit game)" entry to PyMOL's wizard panel — users can also quit the game that way.

### The verified 3-Button Viewing mouse mapping
Source: `modules/pymol/controlling.py:320-348` (the `three_button_viewing` mode dict), decoded with the action-code legend at `controlling.py:57-123` and the `cButMode*` enum in `layer1/ButMode.h`.

| Action | Mouse input | PyMOL action (code) | What it does |
|--------|-------------|---------------------|--------------|
| **Rotate** | Left-drag | `rota` (cButModeRotXYZ) | Rotate the molecule about X/Y |
| **Translate / Pan** | Middle-drag | `move` (cButModeTransXY) | Move the molecule in the view plane |
| **Zoom** | Right-drag | `movz` (cButModeTransZ) | Move the view toward/away (zoom) |
| **Box zoom (in)** | Shift + Left-drag | `+box` (cButModeSeleAddBox) | Drag a box to zoom into that region |
| **Box zoom (out)** | Shift + Middle-drag | `-box` (cButModeSeleSubBox) | Drag a box to zoom out |
| **Clipping plane** | Shift + Right-drag | `clip` (cButModeClipNF) | Adjust the near/far clipping plane |
| **Slab (clipping width)** | Scroll wheel (plain) | `slab` (cButModeScaleSlab) | **Adjust the clipping slab — NOT zoom!** |
| **Zoom (wheel)** | Ctrl + Scroll wheel | `mvsz` (cButModeMoveSlabAndZoom) | Move slab + zoom |
| **Zoom (wheel, pure)** | Ctrl + Shift + Scroll wheel | `movz` (cButModeTransZ) | Zoom in/out |
| **Center on a point** | Single Middle-click | `cent` (cButModeCent) | Center the view on the clicked atom |
| **Context menu** | Single Right-click | `menu` (cButModeMenu) | Open the right-click menu |
| **Pick / click-to-find** | Single Left-click | `+/-` (cButModeSeleToggle) → with PickWizard active, routes to `do_select` → `do_pick` | **Click an atom to check if it's a hider** (during play) |

**Key, counterintuitive finding — flag this prominently in the Help text:** In the default 3-Button Viewing mode, **the plain scroll wheel adjusts the clipping slab (moves the near/far clipping planes), NOT zoom.** This is a well-known PyMOL gotcha. To zoom with the wheel, the user must hold **Ctrl** (or Ctrl+Shift). To zoom by dragging, use **Right-drag** or **Shift + Left-drag** (box zoom). The controls help MUST say this explicitly so students don't assume the wheel is broken.

### Draft controls-help text (student-friendly — paste-ready, verified)
```
Moving around the molecule (default 3-Button Viewing mode):

  • Rotate: Left-drag
  • Move / pan: Middle-drag
  • Zoom: Right-drag  (or Shift + Left-drag to box-zoom a region)
  • Zoom with the wheel: hold Ctrl + scroll  (the plain scroll wheel
    adjusts the clipping plane, not zoom — a common PyMOL surprise)
  • Center on an atom: Middle-click that atom
  • Reset the view: middle-click empty space, or use PyMOL's
    "reset" command

Clicking to find hiders (during a game):

  • Click an atom (single Left-click) to check if it's a hider.
    A found hider turns green; a miss is logged in the info log.
  • Left-DRAG still rotates the molecule — so you can spin to look
    around while you hunt. A quick click picks; a drag rotates.
  • To stop the game without winning, open PyMOL's wizard panel
    (bottom-left in the external GUI) and pick "Done (quit game)",
    or click Restart / Cleanup model in the plugin.
```

> **Phrasing note on "Right-drag = zoom":** PyMOL's `movz` (cButModeTransZ) technically translates the scene along the Z-axis, which makes objects grow/shrink — i.e. it is functionally zoom. The official PyMOL docs and most tutorials call this "zoom." Phrasing it as "Zoom: Right-drag (move the view toward/away)" is accurate and student-friendly.

### Keyboard shortcuts (brief — keep optional)
PyMOL's `keyboard.py` is mostly copy/cut/paste selection helpers (`editing_ring`), not view navigation. There is **no default arrow-key navigation** in 3-Button Viewing — the mouse is the primary input. Useful commands the student can type in PyMOL's command line (mention as "advanced" in Help, optional):
- `reset` — reset the view
- `zoom` — zoom to all visible objects (or `zoom objName`)
- `orient` — orient the molecule nicely
- `hide everything; show cartoon` — a quick way to switch reps (cross-ref to the strategy section)

**Recommendation:** Keep the Help panel's keyboard section to 2–3 lines (reset / zoom / orient commands), framed as "type these in PyMOL's command line." Do NOT claim arrow keys navigate — they don't by default.

---

## UX-02: "Switch Reps to Spot Hiders" Strategy (draft text)

This is the planning note from the roadmap (legitimate observation strategy, not a cheat). Draft help-panel text:

```
Tip — switch representations to spot hiders (a legitimate strategy):

  Hiders are styled to blend into ONE representation. A hider placed
  in the cartoon rep, for example, is hard to see while cartoon is on
  — but if you hide cartoon and show spheres, that same hider (which
  is really just an extra atom inserted into the molecule) will often
  stick out as a sphere that doesn't belong.

  Try this when you're stuck:
    1. In PyMOL, hide the rep you think the hider is in
       (e.g. hide cartoon).
    2. Show a different rep (e.g. show spheres or show sticks).
    3. Look for an atom that appears in the new rep but seems out of
       place — that's a likely hider.
    4. Click it to check. You can switch reps back when done.

  This is fair play: you're using PyMOL's own view tools to study the
  structure, exactly as a structural biologist would. It is NOT
  cheating — the hiders are in the same object as the real atoms, so
  toggling reps affects both equally; you still have to spot the
  impostor.
```

This text should appear in BOTH the Help panel (UX-01 section 6) and as a short note near the controls reference (UX-02), and a one-line version should be added to the README "Tips" section.

---

## README: Feature Inventory + Update Guidance (SC5)

### Current README state (read 2026-08-17)
- Line 4: "> UNDER DEVELOPMENT" — **MUST CHANGE** to reflect v1 complete.
- Line 12: "> **Status:** Planning complete. v1 (PyMOL plugin) is being built; v2 (VMD tcl script) is deferred." — **MUST UPDATE** to "v1 (PyMOL plugin) complete; v2 (VMD tcl) deferred."
- "What It Does" (lines 17–24): covers Setup/Game/Core loop/Persistence/Demos. **Missing:** endgame (win screen stats + teachable debrief), help panel/tooltips, controls reference.
- "Usage" (lines 43–52): step 6 says win screen shows time only — **MUST UPDATE** to reflect time + hints + reveals + debrief (the SC3/SC4 target).
- "Demo Molecules" table (lines 55–66): uses ad-hoc tier labels (Protein Easy, RNA Easy…). **Should align** to the 4-tier system (Easy/Hard/Challenge/Very challenging) from `TIER_LABELS` (`setup_state.py:65-70`). Also should note which demos need a network connection (the 3 fetched: sasdpg4, 1gzm, 3gp6).
- Line 91: "Last updated: 2026-08-03" — update to the ship date.
- Lines 1–2 (vibe-coding warning): **KEEP verbatim** per the objective.

### Feature inventory (what the README must reflect — from completed phases 1–9 + 11 + 4.1)
Verified against the live code and `ROADMAP.md`:

| Feature | Where in README |
|---------|-----------------|
| Plugin install via Plugin Manager, modeless tabbed dialog (Setup + Game) | Install + What It Does |
| Setup tab: 3 target modes (loaded / PDB fetch / bundled demo), hider count cap, lock-scene, per-rep hider counts, difficulty (easy/hard), Reset/Randomize/Save/Load Setup, lock-source, PDB-pool editor | What It Does (Setup tab) |
| 9 demos: 6 bundled (offline) + 3 fetched (network: SASBDB glycoprotein, 2 MemProtMD membrane proteins), 4-tier difficulty (Easy/Hard/Challenge/Very challenging), source attribution in `DATA_SOURCES.md` | Demo Molecules table |
| Game loop: 3-2-1 countdown, click-to-find via PickWizard, hit/miss log, count-up timer, remaining-hiders counter (easy: per-rep breakdown; hard: total only) | What It Does (Game tab) + Usage |
| Hint (color neighbors), Reveal one / Reveal all (with confirm), reveal counter | What It Does (Game tab) + Usage |
| Found-hider management (Hide/Show/Recolor), Color picker, Restart | What It Does (Game tab) |
| Persistence: save game as `.bcmz` (`.pse` + `.bcm` sidecar); Generate & export puzzle; Import puzzle/checkpoint; Save checkpoint with resume | What It Does (Persistence) + Usage |
| 5 representations: lines, sticks, spheres, cartoon, ribbon (surface out of scope) | What It Does / Help |
| **[NEW — Phase 10]** Tooltips on all controls + Help panel (what each button does, what each rep means, PyMOL controls, switch-reps strategy) | **ADD to What It Does** |
| **[NEW — Phase 10]** Win screen shows time + hints used + reveals used (SC3) | **UPDATE Usage step 6** |
| **[NEW — Phase 10]** Post-game debrief highlighting why each hider was hard to spot (SC4) | **ADD to What It Does + Usage** |
| **[NEW — Phase 10]** PyMOL controls reference (rotate/pan/zoom/click) | **ADD to What It Does / Help** |

### Recommended README structure (outline for the implementer)
```
> vibe-coding warning (KEEP lines 1-2 verbatim)
[remove "UNDER DEVELOPMENT" line — or replace with a one-line "v1 ships as a PyMOL plugin" tag if a tag is desired]

# bioCHEMeleon
[1-paragraph intro — KEEP current line 8 mostly, it's good]
[audience line — KEEP current line 10]

> **Status:** v1 (PyMOL plugin) is complete. v2 (VMD tcl script) is deferred.
> See `.planning/ROADMAP.md` for the phase breakdown.

---

## What It Does
- **Setup tab** — ... (existing + mention Help button / lock-source / pool editor)
- **Game tab** — ... (existing + mention found-management + color picker)
- **Core loop** — Start → 3-2-1 countdown → click atoms → win
- **Endgame & debrief** — [NEW] win screen shows your time, hints used, and
  reveals used, then a debrief highlights each hider and why it was hard to spot
  (the teachable moment)
- **Help & tooltips** — [NEW] every control has a tooltip; a Help button opens
  a panel explaining each representation, the PyMOL controls (rotate/pan/zoom/
  click), and a tip on switching representations to spot hiders
- **Persistence** — ... (existing)
- **Demos** — ... (existing, add the 4-tier + network note)

## Requirements  (KEEP — accurate)

## Install  (KEEP — accurate)

## Usage
1. Load a molecule ... (KEEP)
2. Open Plugins → bioCHEMeleon ... (KEEP)
3. Configure ... (KEEP)
4. Press Start ... (KEEP)
5. Use Hint / Reveal ... (KEEP)
6. Find all hiders to win — the timer stops and a win screen shows your time,
   hints used, and reveals used, followed by a debrief highlighting each hider.
7. Save / Restart / Cleanup ... (KEEP)
> Tip: stuck? Open the Help button for how to rotate, zoom, and click — and
> for a strategy on switching representations to spot hiders.

## Tips — How to spot hiders  [NEW SECTION]
- Hiders blend into one representation. Switch reps to make an impostor
  stand out (e.g. hide cartoon, show spheres — a cartoon hider will stick
  out as an extra sphere). See the in-app Help panel for details.
- This is a legitimate observation strategy, not a cheat.

## Demo Molecules  (UPDATE table to 4-tier + network column)
| Tier | Category | Source | ID(s) | Needs network? |
| Easy | Protein | RCSB PDB | 1znf | no (bundled) |
| Easy | RNA | RCSB PDB | 5e54 | no (bundled) |
| Easy | DNA | RCSB PDB | 1k8p | no (bundled) |
| Hard | Protein | RCSB PDB | 1xdn | no (bundled) |
| Hard | RNA | RCSB PDB | 2qbz | no (bundled) |
| Hard | Mixed | RCSB PDB | 4wb3 | no (bundled) |
| Challenge | Glycoprotein | SASBDB | SASDPG4 | yes (fetched) |
| Very challenging | Membrane protein | MemProtMD | 1GZM | yes (fetched) |
| Very challenging | Membrane protein | MemProtMD | 3GP6 | yes (fetched) |
Full attribution in `DATA_SOURCES.md`.

## Project Structure  (KEEP — accurate)
## License  (KEEP)
## Acknowledgements  (KEEP)

---
*Last updated: <ship date>.*  (UPDATE date)
```

### Tone + rules for the implementer
- **Tone:** clear, concise, engaging, professional but simple — understandable by students. No jargon without explanation (e.g. explain "representation" / "rep" on first use).
- **DO NOT** mention internal phase numbers, plan IDs, or the GSD workflow — the README is user-facing. (Current README already follows this — keep it.)
- **DO** keep the existing accurate sections (Requirements, Install, Project Structure, License, Acknowledgements) largely as-is.
- **Dependency note:** the win-screen stats (SC3) and the debrief (SC4) are the *other* portion of Phase 10 (endgame), not this research's scope. The README should describe the **final shipped** state, so its win-screen + debrief copy depends on SC3/SC4 landing. If the planner sequences the endgame plans before/alongside this UX work, the README reflects both; if the endgame is deferred, drop the debrief line from the README. **Flag this dependency to the planner.**

---

## Implementation Guidance (concrete steps for the planner)

1. **Tooltips pass (no behavior change, pure additive):**
   - In `gui_setup.py`: add `setToolTip()` calls for every widget in the "Tooltips to ADD — gui_setup.py" table. The per-rep loop at lines 166–179 is the place to add per-rep checkbox + spinbox tooltips (the rep name is `rep` in the loop variable — use it to build the rep-specific tooltip text).
   - In `gui_game.py`: add `setToolTip()` for `_hint_btn`, `_reveal_one_btn`, `_reveal_all_btn`, `_found_mgmt_combo`, `_timer_label`, `_remaining_label`, `_reveal_label`, and optionally `_info_log`.
   - **No new tests needed** (tooltips are Qt-string-only; `python3.6 -m py_compile` syntax-checks them; the grep gates are unaffected — `setToolTip` doesn't match either gate).
   - **Human-verify checkpoint:** hover each widget in a real PyMOL session (Qt tooltips can't be rendered headlessly from WSL — AGENTS.md: Qt needs a real display).

2. **Help button + dialog (additive, one new file or one constant):**
   - In `__init__.py`: add `HELP_HTML` module constant (the 6 sections above) and a `self.help_btn` + `_show_help(self)` method on `PluginDialog`. Place the button in a `QHBoxLayout` below `self.tabs` (right-aligned, per the design section).
   - `_show_help` builds a `QDialog` + `QTextEdit` (read-only, `setHtml(HELP_HTML)`) + OK button, then `help_dlg.exec_()`.
   - **Grep-gate impact:** the exec_ gate rises from 1 → 2. This is ALLOWED (child dialog). Verify with `grep -rnE "\.exec_\(\)" biochemeleon/` after the change — expect 2 hits, both on child dialogs (gui_game.py `_finish_win` QMessageBox + the new Help QDialog), NEVER on the main PluginDialog.
   - **No new tests** (the dialog is Qt-rendered; can't be unit-tested headless). Human-verify: open Help from both tabs, confirm it's modal, scrolls, dismisses with OK/Esc.

3. **Controls text:** use the verified mapping in the "UX-02: PyMOL Controls Reference" section verbatim. Do NOT paraphrase the wheel behavior — keep the explicit "plain wheel = clipping, not zoom" callout.

4. **README:** rewrite per the structure above. Keep lines 1–2, update lines 4 + 12 + the What-It-Does + Usage + Demo table + last-updated date. No phase numbers.

5. **Verification gates to run after implementation:**
   - `python3.6 -m py_compile biochemeleon/*.py` (syntax)
   - `python3.6 -m unittest tests.test_setup_state -v` (pure layer still green — should be unaffected)
   - `grep -rnE "import Tkinter|...|import PyQt5" biochemeleon/` → must stay 0
   - `grep -rnE "\.exec_\(\)" biochemeleon/` → 2 (allowed), both on child dialogs
   - **Human-verify (Windows PyMOL session):** tooltips render on hover; Help opens modal; controls text accurate; wheel behavior matches.

---

## Open Questions / Risks

1. **[RISK — HIGH priority, but mitigated] The "plain wheel = slab, not zoom" finding.** This is verified directly from `controlling.py:336` (`('w','none','slab')`), which IS the code that defines the default. It contradicts a common belief that the wheel zooms in PyMOL. The source is authoritative, but because this is user-facing text and the cost of being wrong is embarrassment, **recommend a 30-second human-verify in a real PyMOL 2.5.0 session** (load a molecule, scroll the wheel, confirm it adjusts clipping; then Ctrl+scroll to confirm zoom). Per AGENTS.md, GUI behavior is human-verify-territory anyway. If a human finds the wheel DOES zoom (e.g. a conda-build default differs from open-source), adjust the Help text to match the observed behavior — but the open-source source says slab.

2. **[DEPENDENCY] README win-screen + debrief copy depends on SC3/SC4.** This research covers SC1/SC2/SC5 only. The README's "Endgame & debrief" line and Usage step 6 describe the *target* shipped state (time + hints + reveals + debrief). If the Phase 10 endgame plans (SC3/SC4) are sequenced after this UX work or deferred, the implementer must drop/soften those README lines to match what actually ships. **Planner: sequence the endgame plans first (or in the same wave), then the README finalization last** so the README reflects reality.

3. **[LOW] Help text length / scroll.** If `HELP_HTML` exceeds ~200 lines, consider moving it to a `biochemeleon/help_text.py` module to keep `__init__.py` readable. A module-level string in `__init__.py` is fine up to that size. No functional difference either way.

4. **[LOW] Per-rep tooltip duplication.** Putting the rep explanation in both the per-rep checkbox tooltip AND the Help panel is intentional (hover-discoverability + comprehensive reference). If the implementer worries about tooltip length on the checkbox, the checkbox tooltip can be just the generic "check to put hiders in this rep" + a pointer ("see Help for what this rep looks like"), with the full explanation only in Help. **Recommendation: include the short rep explanation in the checkbox tooltip** — it's the highest-value UX-01 text and a student hovering "cartoon" deserves the explanation right there.

5. **[VERIFIED — no action] Does PickWizard change the click button?** Confirmed NO — it only sets `mouse_selection_mode=0`; left-click routes through `do_select`→`do_pick`, left-drag stays rotate. So the controls help's "Left-click to find, Left-drag to rotate" is accurate for the play state. Source: `wizard.py:42-45, 69-84`.

6. **[VERIFIED — no action] Are arrow keys / keyboard nav available?** No default arrow-key view navigation in 3-Button Viewing (`keyboard.py` is copy/cut/paste helpers, not nav). The Help can mention `reset`/`zoom`/`orient` as command-line shortcuts but should not claim arrow keys navigate.

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 open-source, read directly)
- `tmp/pymol-src/modules/pymol/controlling.py:57-123` — action-code legend (`rota`, `movz`, `slab`, `pkat`, `+box`, etc. → integer codes)
- `tmp/pymol-src/modules/pymol/controlling.py:127-204` — `ring_dict` + default `mouse_ring = ring_dict['three_button']` (default = 3-Button Viewing)
- `tmp/pymol-src/modules/pymol/controlling.py:320-348` — `three_button_viewing` full mapping (the verified default mouse controls)
- `tmp/pymol-src/layer1/ButMode.h:25-54` — `cButMode*` enum (RotaXYZ/TransXY/TransZ/ClipNF/Cent/Menu/PickAtom/PickAtom1/SeleSet/SeleToggle/SeleAddBox/SeleSubBox/ScaleSlab/MoveSlab/MoveSlabAndZoom)
- `tmp/pymol-src/modules/pymol/_gui.py:803-830` — Mouse menu: selection-mode labels (0=Atoms…6=C-alphas) + mouse-mode commands
- `tmp/pymol-src/modules/pymol/wizard/measurement.py:227-240` — `mouse_selection_mode` → atom/residue/chain/segment/object/molecule/C-alpha labels
- `tmp/pymol-src/modules/pymol/viewing.py:51-53, 491-525` — full `rep_list` + `show` docstring (confirms the 5 in-scope reps)
- `biochemeleon/wizard.py:42-45, 69-84, 92` — PickWizard sets `mouse_selection_mode=0`, does NOT change `button_mode`, `do_select`→`do_pick` routing, restores on deactivate

### Secondary (HIGH confidence — live repo code, read directly)
- `biochemeleon/gui_setup.py` — SetupTab widget inventory (lines 50–250) + existing tooltips (lines 86, 207, 215)
- `biochemeleon/gui_game.py` — GameTab widget inventory (lines 21–89) + existing tooltips (lines 54, 57, 67, 70) + `_finish_win` (lines 284–326, current win = time only)
- `biochemeleon/__init__.py` — `PluginDialog` (lines 39–103), no Help button yet, modeless `dialog.show()` rule
- `biochemeleon/setup_state.py:23, 34-70` — `GAME_REPS` (5 reps) + `DEMO_MANIFEST` (9 demos) + `TIER_LABELS` (4-tier)
- `README.md` — current state (2026-08-03, "UNDER DEVELOPMENT")
- `.planning/ROADMAP.md:222-237` — Phase 10 scope + the switch-reps planning note
- `.planning/REQUIREMENTS.md:75-76, 174-175` — UX-01/UX-02 requirement IDs (Phase 10, Pending)

### Tertiary (LOW — web cross-check FAILED, noted for transparency)
- `https://pymol.org/pymol.html` — official site; no fetchable mouse-mapping docs (marketing page only)
- `https://pymolwiki.org/index.php/Mouse_Configuration`, `/Mouse`, `/3-Button_Viewer` — all returned 404 (wiki appears down/renamed)
- **Mitigation:** the source code (`controlling.py`) IS the authoritative definition of the defaults, so the web cross-check is not required for HIGH confidence; the controls finding stands on the source. A real-PyMOL human-verify (Open Question 1) is the recommended final check.

## Metadata

**Confidence breakdown:**
- PyMOL controls mapping: **HIGH** — read from the authoritative source that *defines* the defaults (`controlling.py`); cross-checked against `ButMode.h` enum + `_gui.py` menu labels. (Web cross-check failed but not required.)
- PickWizard interaction model: **HIGH** — read from `wizard.py` directly.
- Widget tooltip inventory: **HIGH** — read from live `gui_setup.py`/`gui_game.py`/`__init__.py` + grep-confirmed existing tooltips.
- Representation descriptions: **HIGH** — rep names verified from `viewing.py:51-53`; visual descriptions are standard PyMOL rendering behavior, consistent with the game's generators.
- Help-dialog design (modal QDialog allowed): **HIGH** — verified exec_ gate is 1 today, AGENTS.md explicitly permits child-dialog `.exec_()`.
- README update guidance: **HIGH** — feature inventory cross-checked against live code + ROADMAP; current README read in full.

**Research date:** 2026-08-17
**Valid until:** 2027-08-17 (stable — PyMOL 2.5.0 mouse defaults and the repo's Qt rules are not changing; the wheel=slab finding is a fixed property of the 2.5.0 source). Re-verify the wheel behavior in a real PyMOL session before shipping the controls text (Open Question 1).
