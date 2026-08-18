# Phase 10 Human-Verify: APPROVED (with 3 follow-up items)

**Verified:** 2026-08-18
**Verifier:** User (real Windows PyMOL 2.5.0 GUI session, conda env `chemtools-win10`)
**Result:** APPROVED — all 8 checks PASS. 3 follow-up items raised by the user during the checkpoint; all 3 addressed (1 fixed in HELP_HTML, 1 documented as intended behavior, 1 documented as a Phase 9 debug artifact — not our code).

## Checks Passed

| # | Check | SC | Result |
|---|-------|----|--------|
| 1 | Win dialog shows time + hints + reveals (incl 0/0) | SC3/DIFF-02 | PASS |
| 2 | Debrief dialog + hiders shown + explanations | SC4/DIFF-03 | PASS |
| 3 | Per-rep explanations accuracy | SC4 | PASS |
| 4 | Cleanup after debrief (non-imported + imported) | DIFF-03 | PASS |
| 5 | Setup + Game tooltips render | SC1/UX-01 | PASS |
| 6 | Help dialog (6 sections, modal, scrolls, dismisses) | SC1/UX-02 | PASS |
| 7 | PyMOL controls accuracy (wheel=slab gotcha verified) | SC2/UX-02 | PASS |
| 8 | Reps explained match GAME_REPS (5 reps, no surface) | SC1 | PASS |

All 5 Phase 10 success criteria are human-verified in a real Windows PyMOL GUI session.

## Follow-up Items Raised by the User

The user ran all 8 checks; all passed. Three additional observations were reported (verbatim user messages in quotes). Each is addressed below.

### Issue 1 — Help dialog controls text: Ctrl+Left-drag should also do move  →  FIXED

> "help in pymol control: (pls check) ctrl+left mouse click should also do move"

**Investigation.** The default 3-Button Viewing mode is defined in `tmp/pymol-src/modules/pymol/controlling.py:320-348`. The relevant entries:

- `('l','none','rota')`  — Left-drag = **rotate** (line 321)
- `('m','none','move')`  — Middle-drag = **move/pan** (line 322)
- `('r','none','movz')`  — Right-drag = **zoom** (line 323)
- `('l','ctrl','move')`  — **Ctrl + Left-drag = move** (line 327)  ← the user is correct
- `('l','alt','move')`   — Alt + Left-drag = move (line 333, not called out in Help)
- `('w','none','slab')`  — plain wheel = clipping slab (line 336)
- `('w','ctrl','mvsz')`  — Ctrl + wheel = zoom (line 338)

The HELP_HTML "Move / pan" line previously listed only Middle-drag. The user correctly identified that Ctrl+Left-drag is ALSO a move/pan binding (an alternative on mice without a middle button).

**Fix.** `biochemeleon/__init__.py` HELP_HTML, "Move / pan" bullet updated:
- Before: `<li><b>Move / pan</b> — Middle-drag</li>`
- After:  `<li><b>Move / pan</b> — Middle-drag, or hold Ctrl + Left-drag (a handy alternative on mice without a middle button)</li>`

Verified against `controlling.py:327` `('l','ctrl','move')`. (Alt+Left-drag at line 333 is also a move binding, but was not called out to keep the Help concise — the user's feedback was specifically about Ctrl+Left.)

**Commit:** `36d5de4` (`fix(10-09): add Ctrl+Left-drag=Move to Help controls (user checkpoint feedback)`)

### Issue 2 — Help dialog freezes the viewer  →  DOCUMENTED AS INTENDED (+ brief note added)

> "when help dialog is shown, the pymol viewer is frozen, back after closing, idk if this is intended?"

**Investigation.** This is INTENDED behavior. The Help dialog is a modal child `QDialog` opened via `help_dlg.exec_()` (`biochemeleon/__init__.py:952`). Modal dialogs block the parent's event loop, so the PyMOL 3D viewer cannot process input while Help is open. This matches the Phase 10 plan design:

- AGENTS.md rule: the **main** `PluginDialog` stays modeless (`dialog.show()`, NEVER `.exec_()`), so the 3D viewer stays interactive during gameplay.
- AGENTS.md rule: **child** dialogs (QFileDialog/QMessageBox/QInputDialog/QColorDialog) CAN be modal (`.exec_()` is allowed on them).
- Precedent: the win/debrief `QMessageBox` dialogs (`gui_game.py:345`, `gui_game.py:404`) are also modal child dialogs — they freeze the viewer while open too. The Help dialog follows the same pattern.

The user confirmed the viewer unfreezes on close ("back after closing"), which is the expected modal-child behavior.

**Action taken (no code logic change).** `exec_()` was NOT changed to `show()` — that would violate the plan's modal-child design and the exec_ gate expectations (the gate must stay at exactly 3 hits, all on child dialogs; changing to `show()` would drop it to 2 and make Help modeless, which would let the user open multiple Help dialogs and clutter the screen).

As an OPTIONAL UX improvement (permitted by the checkpoint instructions), a brief italic note was added at the top of `HELP_HTML` (right under the title) so the user knows the pause is expected and how to resume:
```
<p><i>This panel pauses the 3D viewer while open. Close it (OK button or
Esc) to go back to moving the molecule.</i></p>
```
This is a content-only addition (no new `<h2>` — the section count stays at 7; no new `.exec_()` — the gate stays at 3). It documents the modal behavior IN the dialog itself so future users aren't surprised.

**Commit:** `36d5de4` (same commit as Issue 1 — both are HELP_HTML content edits).

### Issue 3 — PyMOL autoloads a "phase9_ssl_probe" debug script at startup  →  DOCUMENTED (Phase 9 debug artifact, NOT our code)

> "also starting pymol autoload some debug scripts it seems?"
> (clarified: "should be within tmp dir in this repo")

The PyMOL startup output showed:
```
Unable to initialize plugin 'phase9_ssl_probe' (pmg_tk.startup.phase9_ssl_probe).
```

**Investigation.** Located the source:

1. **Found in this repo's `tmp/` (staged Windows-facing path):** `tmp/bioCHEMeleon/phase9_ssl_probe.py` (5030 bytes, dated 2026-08-16 20:20). This is a Phase 9 SSL diagnostic probe — it reproduces the SASBDB HARICA certificate bug and verifies the `_urlopen_with_ssl_fallback` fix in `biochemeleon/demos.py`. The file header documents its purpose:
   > "phase9_ssl_probe.py — reproduce the SASBDB SSL bug + verify the fix on the ACTUAL Windows conda Python (the env that manifests the HARICA cert gap). Run headlessly: `cmd.exe /c C:\src\run-conda-pymol.bat -cq phase9_ssl_probe.py`. This is a DIAGNOSTIC probe (not a committed smoke). It uses real network."
   It imports `from biochemeleon.demos import _urlopen_with_ssl_fallback` and runs 3 tests (T1 reproduce / T2 fix SASBDB / T3 regression MemProtMD).

2. **NOT part of the bioCHEMeleon package proper:** `biochemeleon/phase9*` → no such file. The package directory contains only the production modules (setup_state, demos, backup, mutation, registry, game, generators, wizard, gui_setup, gui_game, __init__). Confirmed via `ls biochemeleon/phase9*` → "No such file or directory".

3. **NOT installed in the conda env's pmg_tk/startup/:** Checked `/mnt/c/Users/nglok/.conda/envs/chemtools-win10/Lib/site-packages/pmg_tk/startup/` — contents: `Caver3`, `__init__.py`, `__pycache__/`, `apbsplugin.py`, `autodock_plugin.py`, `optimize.py`, `renumber.py`. No `phase9_ssl_probe.py` (and no `phase9_ssl_probe.cpython-39.pyc` in `__pycache__/` — only the 5 listed plugins' .pyc files). So the probe was NOT permanently installed into the conda env's plugin startup directory.

4. **Gitignored:** `git check-ignore tmp/bioCHEMeleon/phase9_ssl_probe.py` returns the path (exit 0) — `tmp/` is gitignored per AGENTS.md ("Git-ignored: ... tmp/ ..."). The probe is NOT tracked in the repo; it's a local working artifact staged to the Windows-facing path during Phase 9.

**How PyMOL picked it up.** The error message `pmg_tk.startup.phase9_ssl_probe` indicates PyMOL's plugin loader resolved `phase9_ssl_probe` as if it were in the `pmg_tk.startup` package. The most likely path: the user launched PyMOL with the working directory set to the staged `tmp/bioCHEMeleon/` (the Windows-facing path used for headless Phase 9/11 runs per AGENTS.md), and PyMOL's plugin loader scans `pmg_tk.startup` entries which may resolve from a directory exposed via cwd/PYTHONPATH. Regardless of the exact mechanism, the key facts are: (a) the source is the Phase 9 diagnostic probe in our gitignored `tmp/`, (b) it is NOT bioCHEMeleon code, (c) the load failure is harmless (the probe is a script, not a plugin module — it runs network tests at import time, which PyMOL's plugin loader catches and reports as "Unable to initialize").

**Action taken.** NO code fix. This is a Phase 9 debug artifact, not a bioCHEMeleon bug. The probe is gitignored and not shipped with the plugin. If the user wants to silence the startup warning, they can delete `tmp/bioCHEMeleon/phase9_ssl_probe.py` (and the staged `__pycache__/phase9_ssl_probe.cpython-39.pyc` if present). Per the checkpoint instructions: "Do NOT modify the conda env."

## Conclusion

All 5 Phase 10 success criteria are human-verified (8/8 checks PASS). The 3 follow-up items are resolved:
- Issue 1 fixed in HELP_HTML (Ctrl+Left-drag=Move, verified against `controlling.py:327`).
- Issue 2 documented as intended modal-child behavior + a brief in-dialog note added (no logic change; `exec_()` preserved per plan design).
- Issue 3 documented as a Phase 9 debug artifact in the gitignored `tmp/` (not bioCHEMeleon code, not in the conda env's startup, harmless load failure).

Phase 10 may proceed to Plan 10-10 (README finalization). No plan needs to be re-opened.

## WSL Gate State (post-fix)

- `python3.6 -m py_compile biochemeleon/*.py` → clean (exit 0).
- `python3.6 -m unittest tests.test_setup_state` → 125 tests, all pass (no regression).
- Pitfall-1 grep (`import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5`) → **0** matches (exit 1 = no match).
- exec_ grep (`.exec_\(\)`) → **3** hits, all on child dialogs (UNCHANGED — the fix added NO new exec_ calls):
  - `biochemeleon/gui_game.py:345: msg.exec_()` — `_finish_win` QMessageBox (child, UNCHANGED).
  - `biochemeleon/gui_game.py:404: msg.exec_()` — `_finish_debrief` QMessageBox (child, UNCHANGED).
  - `biochemeleon/__init__.py:952: help_dlg.exec_()` — `_show_help` QDialog (child, UNCHANGED).
- `<h2>` count in `biochemeleon/__init__.py` → **7** (1 "Help" title + 6 content sections — UNCHANGED; the Issue 2 note uses `<p><i>`, not a new `<h2>`).
