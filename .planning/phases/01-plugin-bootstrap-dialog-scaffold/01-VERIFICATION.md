---
phase: 01-plugin-bootstrap-dialog-scaffold
verified: 2026-08-03T00:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: No — initial verification
---

# Phase 1: Plugin Bootstrap & Dialog Scaffold Verification Report

**Phase Goal:** The plugin installs cleanly into PyMOL and opens a dialog from the Plugins menu — the stable shell every later phase builds on.
**Verified:** 2026-08-03
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

All 5 truths are runtime behaviors that require a running Windows PyMOL with PyQt5 to confirm. They were verified by the user's Windows-PyMOL smoke test (Task 3 `checkpoint:human-verify`, approved 2026-08-03 per `01-01-SUMMARY.md` lines 70 + 125). The codebase checks below provide the supporting evidence that the code which produces each behavior is present and correct — but the runtime truths themselves stand on the user's checkpoint approval, which is the formal gate per the plan's `<verification>` section.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User installs the plugin via PyMOL's GUI Plugin Manager and PyMOL loads it on launch without errors | ✓ human-verified (user approved 2026-08-03) | SUMMARY.md:70 "installed via Plugin Manager, restart clean (no tracebacks)"; SUMMARY.md:125 "passed all 5 steps on first attempt". Codebase support: 6/6 `py_compile` clean, `__init_plugin__(app=None)` entry point at `__init__.py:8`, local `addmenuitemqt` import at `__init__.py:16`, `from pymol.Qt import` (no PyQt5/Tk) — the code that produces a clean load. |
| 2 | A 'bioCHEMeleon' item appears under the Plugins menu | ✓ human-verified (user approved 2026-08-03) | SUMMARY.md:70 "'bioCHEMeleon' appears in the Plugins dropdown". Codebase support: `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` at `__init__.py:17` (KL1 wired). |
| 3 | Clicking the 'bioCHEMeleon' menu item opens the plugin dialog window | ✓ human-verified (user approved 2026-08-03) | SUMMARY.md:70 "clicking it opens the 2-tab window". Codebase support: `run_plugin_gui` at `__init__.py:20` lazily creates `PluginDialog()` + calls `dialog.show()` (`__init__.py:29-30`); module-level `dialog = None` singleton at `__init__.py:5` prevents GC (the "flashes and vanishes" failure mode). |
| 4 | The dialog shows a tabbed interface with 'Setup' and 'Game status' tabs (placeholder content is acceptable) | ✓ human-verified (user approved 2026-08-03) | SUMMARY.md:70 "opens the 2-tab window". Codebase support: `self.tabs.addTab(self.setup_tab, "Setup")` at `__init__.py:61` and `self.tabs.addTab(self.game_tab, "Game status")` at `__init__.py:62` (KL3 wired); placeholder labels "Setup — coming in Phase 2" (`gui_setup.py:13`) and "Game status — coming in Phase 4" (`gui_game.py:13`) match the spec. |
| 5 | The 3D viewer stays interactive while the dialog is open (dialog is modeless, NOT modal) | ✓ human-verified (user approved 2026-08-03) | SUMMARY.md:70 "the viewer stays interactive while the dialog is open (modeless confirmed)". Codebase support: `dialog.show()` (modeless) at `__init__.py:30` + `dialog.raise_()` + `dialog.activateWindow()` at `__init__.py:31-32`; `.exec_()` grep returns 0 matches across the package (KL2 + Pitfall-5 greps clean). |

**Score:** 5/5 truths verified (all via human checkpoint with codebase support)

### Required Artifacts

All 6 artifacts present, substantive (meet `min_lines` where specified, contain all required tokens), and wired.

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `biochemeleon/__init__.py` | entry point + singleton + PluginDialog (min 30 lines; contains `__init_plugin__`, `run_plugin_gui`, `dialog = None`, `class PluginDialog`, `addTab`) | ✓ VERIFIED | 66 lines (≥30 ✓). Tokens: `__init_plugin__` (×2: def line 8 + docstring line 9), `run_plugin_gui` (×2: def line 20 + call line 17), `dialog = None` (×1, line 5 — module-level ✓ not inside `__init_plugin__`), `class PluginDialog` (×1, line 38), `addTab` (×2, lines 61 + 62). |
| `biochemeleon/gui_setup.py` | SetupTab placeholder (contains `class SetupTab`) | ✓ VERIFIED | 13 lines. `class SetupTab(QtWidgets.QWidget)` at line 5; constructs a `QVBoxLayout` + `QLabel("Setup — coming in Phase 2")` — constructible so `PluginDialog` can `addTab(SetupTab(), 'Setup')`. |
| `biochemeleon/gui_game.py` | GameTab placeholder (contains `class GameTab`) | ✓ VERIFIED | 13 lines. `class GameTab(QtWidgets.QWidget)` at line 5; constructs a `QVBoxLayout` + `QLabel("Game status — coming in Phase 4")` — constructible so `PluginDialog` can `addTab(GameTab(), 'Game status')`. |
| `biochemeleon/wizard.py` | Phase 4 stub (contains `PickWizard`) | ✓ VERIFIED | 1 line. Docstring-only stub `"""PickWizard (pymol.wizard.Wizard subclass) — populated in Phase 4."""`. Never imported in Phase 1 (confirmed: no `import wizard` / `from .wizard` anywhere in package). |
| `biochemeleon/game.py` | Phase 3/4 stub (contains `GameController`) | ✓ VERIFIED | 1 line. Docstring-only stub `"""GameController + HiderRegistry — populated in Phase 3/4."""`. Never imported in Phase 1. |
| `biochemeleon/demos.py` | Phase 2 stub + `to_windows_path` TODO (contains `DemoLoader`, `to_windows_path`) | ✓ VERIFIED | 8 lines. Docstring stub naming `DemoLoader` (line 1) + explicit `TODO (Phase 2): implement to_windows_path() helper here` (line 3) — carries the Phase-2 deferral reminder as specified. Never imported in Phase 1. |

### Key Link Verification

All 4 key links wired (grep-verified with the exact patterns from the plan frontmatter).

| From | To | Via | Status | Grep Result |
|------|----|-----|--------|-------------|
| `__init__.py::__init_plugin__` | `pymol.plugins.addmenuitemqt` | local import + `addmenuitemqt('bioCHEMeleon', run_plugin_gui)` | ✓ WIRED | `__init__.py:17: addmenuitemqt('bioCHEMeleon', run_plugin_gui)` matches `addmenuitemqt\(['"]bioCHEMeleon['"]\s*,\s*run_plugin_gui\)` |
| `__init__.py::run_plugin_gui` | `__init__.py::PluginDialog` | module-level `dialog = None` singleton + lazy create + `dialog.show()` (modeless) + `raise_()` + `activateWindow()`; NEVER `dialog.exec_()` | ✓ WIRED | `__init__.py:30: dialog.show()` matches `dialog\.show\(\)`; `.exec_()` grep returns 0 matches package-wide |
| `__init__.py::PluginDialog.__init__` | `gui_setup.py::SetupTab` + `gui_game.py::GameTab` | lazy import inside `__init__` + `addTab(SetupTab(), 'Setup')` + `addTab(GameTab(), 'Game status')` | ✓ WIRED | `__init__.py:61: self.tabs.addTab(self.setup_tab, "Setup")` and `:62: ...addTab(self.game_tab, "Game status")` both match `addTab\(.*['"]Setup['"]\)\|addTab\(.*['"]Game status['"]\)` |
| all 3 GUI modules (`__init__.py`, `gui_setup.py`, `gui_game.py`) | `pymol.Qt` | `from pymol.Qt import QtWidgets` (auto-selects PyQt5/PySide2); NEVER `from PyQt5 import` | ✓ WIRED | 3 matches: `__init__.py:35: from pymol.Qt import QtCore, QtGui, QtWidgets`; `gui_setup.py:2: from pymol.Qt import QtWidgets`; `gui_game.py:2: from pymol.Qt import QtWidgets`. PyQt5 grep returns 0 matches. |

### Requirements Coverage

Phase 1 is mapped to PLUGIN-01, PLUGIN-02, PLUGIN-03 (REQUIREMENTS.md traceability table lines 132-134).

| Requirement | Definition (REQUIREMENTS.md) | Status | Supporting Evidence |
|-------------|------------------------------|--------|----------------------|
| PLUGIN-01 | Plugin installs as a standard PyMOL plugin via the GUI Plugin Manager (universal across platforms; works with Windows conda PyMOL accessed via setenv.bat from WSL) | ✓ SATISFIED | Truth 1 (human-verified): user installed via Plugin Manager and PyMOL loaded it on launch with no tracebacks. Codebase: syntactically clean 6-file package with the standard `__init_plugin__` entry point. |
| PLUGIN-02 | Plugin registers a menu item "bioCHEMeleon" via `__init_plugin__` + `addmenuitemqt`; when the user manually activates the plugin (clicks the menu item), the setup window pops up | ✓ SATISFIED | Truths 2 + 3 (human-verified): menu item appears, clicking opens the dialog. Codebase: KL1 wired (`addmenuitemqt('bioCHEMeleon', run_plugin_gui)` at `__init__.py:17`) + KL2 wired (`dialog.show()` at `__init__.py:30` with module-level singleton). |
| PLUGIN-03 | Plugin packaged as a `biochemeleon/` package directory with `__init__.py` (multi-file: gui_setup, gui_game, wizard, game, demos) | ✓ SATISFIED | All 6 files present with required content (see Artifacts table). Flat 5-module layout matches the requirement exactly — NOT the nested `gui/`/`game/`/`pymol_io/` tree from ARCHITECTURE.md (deferred per plan). |

### Anti-Patterns Found

The only matches in the anti-pattern scan are EXPECTED per the plan (placeholder content is explicitly allowed by Success Criterion 3; the `demos.py` TODO is the deliberate Phase-2 deferral marker required by the plan's File 6 spec).

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `biochemeleon/demos.py` | 3 | `TODO (Phase 2): implement to_windows_path() helper here` | ℹ️ Info | Expected — the plan's File 6 spec explicitly requires this TODO as a Phase-2 deferral reminder. Not a stub of Phase-1 work. |
| `biochemeleon/gui_setup.py` | 13 | `QLabel("Setup — coming in Phase 2")` | ℹ️ Info | Expected — Success Criterion 3 explicitly allows placeholder tab content. Phase 2 populates the Setup form. |
| `biochemeleon/gui_game.py` | 13 | `QLabel("Game status — coming in Phase 4")` | ℹ️ Info | Expected — placeholder tab content. Phase 4 populates the Game status tab. |
| `biochemeleon/__init__.py` | 41 | docstring "Phase 1 ships placeholder tabs only" | ℹ️ Info | Expected — descriptive docstring, not a code stub. |
| `biochemeleon/__pycache__/*.pyc` | — | compiled bytecode artifacts | ℹ️ Info | Build artifacts from `py_compile`. Not tracked as source. (Note: `__pycache__/` is not in `.gitignore`; out of scope for Phase 1 — the plan only required `biochemeleon.zip` gitignored. Flag for Phase-2 hygiene if desired.) |

**No blocker or warning anti-patterns.** Zero Tkinter/Pmw/`app.root`/`grab_set`/`menuBar.addmenuitem`/`def __init__(self)`/`mainloop`/`Toplevel`/`Pmw.` patterns. Zero `from PyQt5 import`/`import PyQt5`. Zero `.exec_()` calls. Zero unexpected TODO/FIXME/placeholder in shipped logic.

### Human Verification

The 5 observable truths are runtime behaviors that cannot be re-verified from WSL — they require a running Windows PyMOL with PyQt5 (only available in the `chemtools-win10` conda env launched by `setenv.bat`). The user already completed this verification in Task 3 (`checkpoint:human-verify`) and approved it on 2026-08-03.

**User checkpoint approval record (from `01-01-SUMMARY.md`):**
- Line 70: "Windows-PyMOL smoke test approved by the user — all 5 steps green: installed via Plugin Manager, restart clean (no tracebacks), 'bioCHEMeleon' appears in the Plugins dropdown, clicking it opens the 2-tab window, and the viewer stays interactive while the dialog is open (modeless confirmed)."
- Line 125 (Issues Encountered): "Windows smoke test passed all 5 steps on first attempt."

This satisfies the plan's `<resume-signal>`: "Type 'approved' if all 5 steps PASS." The 5 steps map 1:1 to the 5 truths:
1. Clean load → Truth 1
2. Menu item appears → Truth 2
3. Clicking opens dialog → Truth 3
4. Dialog has 2 tabs with placeholder content → Truth 4
5. Viewer stays interactive (modeless) → Truth 5

**No additional human verification is required** — the checkpoint already closed the runtime-truth gap. The codebase greps provide independent structural confirmation that the code producing each runtime behavior is present and correct.

### Gaps Summary

No gaps. All 6 artifacts present with required content. All 4 key links wired. All 3 Pitfall greps (Tk/Pmw legacy patterns, raw PyQt5 import, modal `.exec_()`) return 0 matches. All 6 modules pass `python3.6 -m py_compile`. The user approved the Windows-PyMOL smoke test (all 5 steps) on 2026-08-03, closing the runtime-truth gap that WSL cannot reach. Phase 1's goal — a clean-install, menu-registered, modeless, tabbed plugin shell — is achieved. Ready to proceed to Phase 2.

**Note for Phase 2 planner (forwarded from Phase 1 SUMMARY):**
- `PluginDialog` lives in `__init__.py` (Option A from RESEARCH §3.2) — extract to `gui_dialog.py` if it grows large in Phase 2.
- `to_windows_path()` is a Phase-2 deliverable (TODO documented in `biochemeleon/demos.py:3`).

---

## Codebase Evidence

Raw outputs of the verification greps and `py_compile` checks (run 2026-08-03 from the repo root).

### Key-link greps (all 4 wired)

```
$ grep -nE "addmenuitemqt\(['\"]bioCHEMeleon['\"]\s*,\s*run_plugin_gui\)" biochemeleon/__init__.py
17:    addmenuitemqt('bioCHEMeleon', run_plugin_gui)
exit=0   # KL1 WIRED

$ grep -nE "dialog\.show\(\)" biochemeleon/__init__.py
23:    Uses dialog.show() (modeless) so the 3D viewer stays interactive while the
30:    dialog.show()
exit=0   # KL2 WIRED (line 30 is the call; line 23 is a docstring mention)

$ grep -nE "addTab\(.*['\"]Setup['\"]\)|addTab\(.*['\"]Game status['\"]\)" biochemeleon/__init__.py
61:        self.tabs.addTab(self.setup_tab, "Setup")
62:        self.tabs.addTab(self.game_tab, "Game status")
exit=0   # KL3 WIRED (both addTab calls present)

$ grep -rnE "from pymol\.Qt import" biochemeleon/__init__.py biochemeleon/gui_setup.py biochemeleon/gui_game.py
biochemeleon/__init__.py:35:from pymol.Qt import QtCore, QtGui, QtWidgets
biochemeleon/gui_setup.py:2:from pymol.Qt import QtWidgets
biochemeleon/gui_game.py:2:from pymol.Qt import QtWidgets
exit=0   # KL4 WIRED (3/3 GUI modules)
```

### Pitfall greps (all 3 return 0 matches)

```
$ grep -rnE "import[[:space:]]+(Tkinter|tkinter|Pmw)|from[[:space:]]+(Tkinter|tkinter|Pmw)|app\.root|grab_set|menuBar\.addmenuitem|def[[:space:]]__init__\(self\)|mainloop|Toplevel|Pmw\." biochemeleon/
exit=1   # 0 matches — no legacy Tk/Pmw/__init__(self)/mainloop/Toplevel leaked in

$ grep -rnE "from PyQt5 import|import PyQt5" biochemeleon/
exit=1   # 0 matches — no raw PyQt5 import (use pymol.Qt instead)

$ grep -rn "\.exec_()" biochemeleon/
exit=1   # 0 matches — no modal dialog call
```

### py_compile (all 6 modules pass under python3.6)

```
$ for f in __init__.py gui_setup.py gui_game.py wizard.py game.py demos.py; do
    python3.6 -m py_compile "biochemeleon/$f" && echo "PASS: biochemeleon/$f"
  done
PASS: biochemeleon/__init__.py
PASS: biochemeleon/gui_setup.py
PASS: biochemeleon/gui_game.py
PASS: biochemeleon/wizard.py
PASS: biochemeleon/game.py
PASS: biochemeleon/demos.py
# 6/6 PASS, exit 0 each, no output (no SyntaxError/IndentationError)
```

### Line counts

```
$ wc -l biochemeleon/*.py
  66 biochemeleon/__init__.py     # ≥30 min_lines ✓
   8 biochemeleon/demos.py
   1 biochemeleon/game.py
  13 biochemeleon/gui_game.py
  13 biochemeleon/gui_setup.py
   1 biochemeleon/wizard.py
 102 total
```

### Module-level singleton confirmation

```
$ grep -nE "^dialog = None" biochemeleon/__init__.py
5:dialog = None   # module-level (not inside __init_plugin__) — GC prevention ✓
```

### Modeless ergonomics confirmation

```
$ grep -nE "raise_\(\)|activateWindow\(\)" biochemeleon/__init__.py
31:    dialog.raise_()
32:    dialog.activateWindow()
```

### Build-fallback artifact + .gitignore hygiene

```
$ grep -nxF 'biochemeleon.zip' .gitignore
15:biochemeleon.zip   # gitignored ✓

$ ls -la biochemeleon.zip
-rwxrwxrwx 1 lwng lwng 6973 Aug  3 02:26 biochemeleon.zip   # staged at repo root, 6973 bytes (non-empty) ✓
```

---

_Verified: 2026-08-03_
_Verifier: OpenCode (gsd-verifier)_
