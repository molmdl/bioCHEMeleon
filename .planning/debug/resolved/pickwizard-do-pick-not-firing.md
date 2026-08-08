---
status: resolved
trigger: "PickWizard.do_pick never fires on real GUI clicks (Phase 4 human-verify failing)"
created: 2026-08-08T00:00:00Z
updated: 2026-08-08T00:01:00Z
---

## Current Focus

hypothesis: (root cause VERIFIED by user) Click routing depends on button_mode
(Selecting vs Picking), NOT mouse_selection_mode. PickWizard sets
mouse_selection_mode=0 but never switches button mode, so left-click stays in
cButModeSeleSet -> creates "sele" -> WizardDoSelect (not WizardDoPick) -> do_pick
never fires.
test: implement Option 2 (do_select) per canonical measurement.py pattern
expecting: real GUI clicks route to do_select -> build pk1 from sele -> do_pick ->
controller.on_pick -> recolor/count/win
next_action: write do_select in wizard.py, run WSL gates, commit, re-stage + smoke

## Symptoms

expected: clicking hider atoms in real PyMOL GUI recolors them green, decrements
remaining count, triggers win at 0.
actual: clicks create a "sele" selection (grows to 3 atoms) but do NOT recolor,
update count, or trigger win. Headless smoke (calls do_pick(0) directly) passes
18/18; real mouse clicks don't reach do_pick.
errors: none (silent). User output: "You clicked /1znf/GAME/H/HIDER`9001/H002"
+ "Selector: selection 'sele' defined with 1 atoms."
reproduction: real Windows PyMOL, load 1znf demo, start game, click a hider.
started: Phase 4 plan 04-06 Task 2 human-verify (C6 click->recolor fails).

## Eliminated

- hypothesis: mouse_selection_mode=0 is sufficient to route clicks to do_pick
  evidence: user verified reading PyMOL C source -- SceneMouse.cpp:331-357
  shows cButModeSeleSet (default in 3-Button Viewing) creates "sele" +
  WizardDoSelect, NEVER WizardDoPick. mouse_selection_mode only controls
  selection GRANULARITY (atom/residue/chain), not pick-vs-select routing.
  timestamp: 2026-08-08

## Evidence

- timestamp: 2026-08-08
  checked: tmp/pymol-src/modules/pymol/wizard/__init__.py (base Wizard)
  found: get_event_mask() default returns event_mask_pick + event_mask_select
  (line 56). do_select(self,name) at line 79 returns None by default. PickWizard
  inherits both -> do_select IS routable, just unimplemented.
  implication: implementing do_select is sufficient; no need to override
  get_event_mask.

- timestamp: 2026-08-08
  checked: tmp/pymol-src/modules/pymol/wizard/measurement.py:295-305
  found: PyMOL's OWN measurement wizard implements do_select as the canonical
  select->pick map: cmd.unpick(); cmd.select("pk1", name + ...); cmd.delete(name);
  self.do_pick(0). It sets mouse_selection_mode=0 (same as us, line 97) and does
  NOT switch button mode. It relies on do_select to handle selection-mode clicks.
  implication: Option 2 is the idiomatic, PyMOL-blessed pattern. Battle-tested.

- timestamp: 2026-08-08
  checked: tmp/pymol-src/layer1/Wizard.cpp:171-189 (WizardDoSelect)
  found: WizardDoSelect checks isEventType(cWizEventSelect) (line 176, passes
  via inherited mask) then calls do_select(name) (line 189) with name = the
  selection just created ("sele"). Confirms Option 2 routes correctly.
  implication: do_select("sele") will fire on every selection-mode left-click.

- timestamp: 2026-08-08
  checked: tmp/pymol-src/layer1/SceneMouse.cpp:331-470 (click dispatch)
  found: cButModeSeleSet (line 337) -> SelectorCreate("sele",...) (339) ->
  WizardDoSelect("sele") (356). cButModePickAtom1/PickAtom (403/429) -> create
  pk1 (cEditorSele1) -> WizardDoPick (426/467). Two disjoint paths.
  implication: with default 3-Button Viewing (left=Sele), only do_select fires.
  do_pick fires ONLY if user manually in a Picking button mode.

- timestamp: 2026-08-08
  checked: tmp/pymol-src/modules/pymol/controlling.py:799-868 (cmd.button)
  found: cmd.button(button, modifier, action) is WRITE-ONLY -- calls
  _cmd.button(COb, but_code, act_code). No Python getter to read current
  button action (ButModeGet exists in C, unexposed). Saving/restoring a single
  button's prior action is not possible from Python without snapshotting all
  ~80 slots or saving the whole preset index.
  implication: Option 1 (per-button save/restore) is fragile/impractical.

- timestamp: 2026-08-08
  checked: button_mode preset semantics (controlling.py:620-680, ButMode.cpp)
  found: button_mode indexes a MODE PRESET (3-Button Viewing/Editing/Motions).
  Switching to "3-Button Editing" makes left=PkAt but ALSO changes middle/right
  and REMOVES rotation from left-drag. In a hide-and-seek game the user MUST
  rotate the molecule to spot hiders -- hijacking left-click for picking
  destroys the spin-to-find UX.
  implication: Option 1 has a severe UX conflict (breaks rotation). Option 2
  preserves rotation (left-drag=rotate, left-click=select->pick). Option 2 wins.

## Resolution

root_cause: PickWizard sets mouse_selection_mode=0 (selection granularity) but
never switches the BUTTON MODE from Selecting to Picking. In the default
3-Button Viewing preset, left-click is cButModeSeleSet -> C layer creates "sele"
+ calls WizardDoSelect (SceneMouse.cpp:337-356), NOT WizardDoPick. PickWizard
implements do_pick but NOT do_select, so selection-mode clicks silently no-op
(base Wizard.do_select returns None). do_pick only fires in Picking button modes
(cButModePickAtom/PickAtom1), which the user is not in.
fix: Option 2 -- implement do_select(name) following the canonical
pymol.wizard.measurement.do_select pattern: build pk1 from the just-created
selection, delete the selection (C layer recreates it next click), dispatch
through do_pick(0). This reuses the existing do_pick logic unchanged, preserves
left-drag rotation (essential for spin-to-find), works in any selection button
mode, and needs no fragile button-mode save/restore.
verification: py_compile clean; 160 unit tests OK; pitfall-1 gate 0; exec_ gate
0; wizard.py standalone (no sibling imports); no cmd.index; cmd.identify present.
Headless smoke 19/19 ALL PASSED -- existing do_pick spike still PASS (no
regression) AND new do_select spike PASS ("do_select via simulated sele marks
found"). Real-GUI click test remains a human-verify checkpoint (orchestrator
re-presents).
files_changed: [biochemeleon/wizard.py, smoke/phase4_smoke.py]
