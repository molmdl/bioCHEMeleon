---
phase: 01-plugin-bootstrap-dialog-scaffold
plan: 01
subsystem: ui
tags: [pymol, pyqt5, qt, plugin, dialog, qtabwidget]

# Dependency graph
requires: []
provides:
  - "biochemeleon/ PyMOL plugin package (6-file flat layout)"
  - "Plugin entry point (__init_plugin__ + addmenuitemqt registration)"
  - "Modeless PluginDialog (QDialog + QTabWidget, 2 placeholder tabs)"
  - "Module-level dialog singleton pattern (GC prevention)"
  - "3 stub modules (wizard.py, game.py, demos.py) for later phases"
affects: [phase-2-setup-tab, phase-3-mutation-safety, phase-4-mvp-core-loop, phase-5-generators, phase-6-hint-reveal, phase-7-found-management, phase-8-persistence, phase-9-demo-fetch, phase-10-polish]

# Tech tracking
tech-stack:
  added: [pymol.Qt (PyQt5 via pymol.Qt auto-selector), QTabWidget, QDialog]
  patterns:
    - "__init_plugin__(app=None) entry point with local addmenuitemqt import"
    - "module-level dialog singleton (GC prevention)"
    - "modeless dialog.show() (never .exec_())"
    - "lazy import of tab classes inside PluginDialog.__init__"
    - "from pymol.Qt import QtWidgets (never from PyQt5)"

key-files:
  created:
    - biochemeleon/__init__.py
    - biochemeleon/gui_setup.py
    - biochemeleon/gui_game.py
    - biochemeleon/wizard.py
    - biochemeleon/game.py
    - biochemeleon/demos.py
  modified:
    - .gitignore

key-decisions:
  - "PluginDialog lives in __init__.py (Option A) — may extract to gui_dialog.py in Phase 2 if it grows"
  - "Install workflow = copy biochemeleon/ to tmp/ + Plugin Manager (clean-source); scan-path/junction is an alternative for live-edit"
  - "3 stub modules (wizard.py, game.py, demos.py) created now as placeholders so the package structure is stable for later phases"

patterns-established:
  - "__init_plugin__(app=None) entry point with local addmenuitemqt import"
  - "module-level dialog singleton (GC prevention)"
  - "modeless dialog.show() (never .exec_())"
  - "lazy import of tab classes inside PluginDialog.__init__"
  - "from pymol.Qt import QtWidgets (never from PyQt5)"

# Metrics
duration: 35min
completed: 2026-08-03
---

# Phase 1: Plugin Bootstrap & Dialog Scaffold Summary

PyMOL plugin shell — 6-file biochemeleon/ package with modeless QTabWidget dialog (Setup + Game status tabs), Qt-only (no Tk), installs via Plugin Manager and loads on launch.

## Performance

- **Duration:** ~35 min (interactive session with a human checkpoint)
- **Started:** 2026-08-03
- **Completed:** 2026-08-03
- **Tasks:** 3 (2 auto + 1 checkpoint:human-verify)
- **Files modified:** 7 (6 created + .gitignore)

## Accomplishments
- Created the `biochemeleon/` plugin package as a flat 6-file layout — `__init__.py` (entry point + `PluginDialog`), `gui_setup.py` (SetupTab), `gui_game.py` (GameTab), and three docstring-only stubs (`wizard.py`, `game.py`, `demos.py`) so the package structure is stable for every later phase.
- WSL gate passed clean on first full run: 6/6 modules `py_compile` clean, 0 matches for forbidden Tk/Pmw/`exec_` patterns, `pymol.Qt` used in all 3 GUI files, `biochemeleon.zip` (6973 bytes) staged at repo root and gitignored as a fallback install artifact.
- Windows-PyMOL smoke test approved by the user — all 5 steps green: installed via Plugin Manager, restart clean (no tracebacks), "bioCHEMeleon" appears in the Plugins dropdown, clicking it opens the 2-tab window, and the viewer stays interactive while the dialog is open (modeless confirmed).
- Established the four Qt-only patterns that all later phases inherit: `__init_plugin__(app=None)` entry point with a local `addmenuitemqt` import, a module-level dialog singleton (GC prevention), `dialog.show()` (never `.exec_()`), and `from pymol.Qt import QtWidgets` (never `from PyQt5`).
- Confirmed the modeless dialog stays interactive while open — Phase 4's click-to-find loop can rely on the viewer remaining responsive.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create biochemeleon/ package (6 files)** - `5608a1f` (feat)
2. **Task 2: WSL syntax + Pitfall-1/11 gate + zip fallback staging** - `4ce8385` (chore)
3. **(plan edit) Switch Task 3 to scan-path approach** - `309f6d1` (docs)
4. **Task 3: Windows-PyMOL smoke test** - (user approval, no code commit — verification checkpoint)

**Plan metadata:** captured at completion (docs: complete plan)

## Files Created/Modified
- `biochemeleon/__init__.py` - Plugin entry point (`__init_plugin__` + `addmenuitemqt`), module-level dialog singleton, `run_plugin_gui` factory, `PluginDialog` (QDialog + QTabWidget with 2 placeholder tabs)
- `biochemeleon/gui_setup.py` - SetupTab placeholder QWidget ("Setup — coming in Phase 2")
- `biochemeleon/gui_game.py` - GameTab placeholder QWidget ("Game status — coming in Phase 4")
- `biochemeleon/wizard.py` - Stub for Phase 4 (PickWizard)
- `biochemeleon/game.py` - Stub for Phase 3/4 (GameController + HiderRegistry)
- `biochemeleon/demos.py` - Stub for Phase 2 (DemoLoader) + `to_windows_path()` Phase-2 TODO
- `.gitignore` - Appended `biochemeleon.zip` (build/fallback artifact)

## Decisions Made
- PluginDialog lives in `__init__.py` (Option A from RESEARCH §3.2) — may extract to `gui_dialog.py` if it grows in Phase 2
- Install workflow: copy `biochemeleon/` to `tmp/` + Plugin Manager (clean-source copy); scan-path/junction is an alternative for live-edit
- 3 stub modules created now so the package structure is stable for later phases

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] biochemeleon/__init__.py comments reworded to clear grep gates**
- **Found during:** Task 2 (WSL syntax + Pitfall gate)
- **Issue:** Original Task 1 comments/docstrings contained literal tokens `Pmw.NoteBook` and `.exec_()` that tripped the Step 2 (Pitfall-1 `Pmw\.` grep) and Step 5 (`.exec_()` grep) verification gates
- **Fix:** Reworded to "the legacy notebook widget" and "the modal form" respectively — same meaning, grep-clean wording, zero functional change
- **Files modified:** `biochemeleon/__init__.py` (comments only)
- **Verification:** Step 2 and Step 5 greps now return 0 matches; 6/6 `py_compile` still pass
- **Committed in:** `4ce8385`

**2. Task 3 install mechanism switched (user decision)**
- **Found during:** Task 3 (checkpoint prep)
- **Issue:** Original plan used Plugin Manager folder-pick with zip/xcopy fallbacks; user preferred a live-edit dev workflow
- **Fix:** Plan updated (commit `309f6d1`) to make plugin scan-path / junction the PRIMARY method; user ultimately used a copy-to-`tmp/` + Manager variant (same result)
- **Files modified:** `.planning/phases/01-plugin-bootstrap-dialog-scaffold/01-01-PLAN.md`
- **Verification:** User confirmed install + restart + menu item + dialog + modeless (all 5 smoke-test steps)
- **Committed in:** `309f6d1`

---

**Total deviations:** 2 (1 auto-fixed bug, 1 user-driven workflow change)
**Impact on plan:** Both deviations are workflow/gate-related; zero functional impact on the shipped plugin shell. No scope creep.

## Issues Encountered
- None beyond the deviations above. WSL gate passed on first full run after the comment reword. Windows smoke test passed all 5 steps on first attempt.

## Pitfalls Avoided
- **Pitfall 1 (Tk vs Qt):** Avoided — all 3 GUI modules use `from pymol.Qt import QtWidgets`, never `from PyQt5 import`. Entry point is `__init_plugin__(app=None)`, not legacy `__init__(self)`. `addmenuitemqt` imported locally inside `__init_plugin__`. No tkinter/Pmw/Toplevel/mainloop anywhere. Verified by the Step 2/3/4 greps (0 matches for forbidden patterns, 3 files with `from pymol.Qt import`).
- **Pitfall 11 (WSL→Windows path):** Avoided — the user copied the package to a Windows-accessible `tmp/` path before installing via the Manager; the Windows smoke test used Windows paths throughout. The `to_windows_path()` helper is deferred to Phase 2 (documented as a TODO in `biochemeleon/demos.py`).

## User Setup Required
None — no external service configuration required. (The plugin install is a one-time GUI action via PyMOL's Plugin Manager, already completed by the user.)

## Next Phase Readiness
- Plugin shell is stable: every later phase adds to `biochemeleon/` (Setup form in Phase 2, mutation-safety in Phase 3, core loop in Phase 4, etc.)
- The modeless dialog is confirmed working — Phase 4's click-to-find loop can rely on the viewer staying interactive while the dialog is open
- `to_windows_path()` helper is a Phase-2 deliverable (TODO documented in `biochemeleon/demos.py`)
- Phase-2 planner note: `PluginDialog` is in `__init__.py` (Option A) — extract to `gui_dialog.py` if it grows large

---
*Phase: 01-plugin-bootstrap-dialog-scaffold*
*Completed: 2026-08-03*
