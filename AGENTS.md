# AGENTS.md

High-signal notes for OpenCode sessions. Read before touching code. See `spec.md` and `.planning/PROJECT.md` for full project context.

> **Scope:** v1 (PyMOL 2.5.0 plugin). v2 (VMD tcl script) is deferred per `spec.md` — this file is v1-scoped; revisit it when v2 research begins. When the active milestone becomes v2, flag that AGENTS.md needs a VMD/tcl-specific rewrite.

## Environment — the WSL/Windows split (read first)

This is the single most common way to break things.

- **Dev shell is WSL Ubuntu.** Do NOT install anything, do NOT create conda envs, do NOT `pip install`. `python3.6` (3.6.9) is for syntax checks and unit tests ONLY. (`opencode.json` denies `pip*`, `apt*`, `conda*`, `rm*`.)
- **PyMOL 2.5.0 runs in a Windows conda env**, not WSL. `setenv.bat` is a Windows cmd.exe batch that activates env `chemtools-win10` from `C:\ProgramData\Miniconda3`; it does NOT launch PyMOL — you run `pymol` from the activated shell. A WSL agent cannot run PyMOL or `setenv.bat`.
- **Consequence:** any code path that executes `pymol.cmd.*` or `pymol.Qt.*` at runtime CANNOT be run from WSL. Only the pure data layer (`biochemeleon/setup_state.py`) is unit-testable in WSL. Everything else is verified by a Windows-PyMOL human-verify smoke test (a checkpoint in the plan).
- `wsl2win_cp.sh` copies `biochemeleon/` to `tmp/bioCHEMeleon/` so the Windows PyMOL Plugin Manager can point at a Windows-side path.

## Commands (run from repo root)

```bash
# Syntax-check every module (py_compile checks syntax, NOT imports):
python3.6 -m py_compile biochemeleon/*.py

# Run the pure-layer unit tests (48 tests, currently green):
python3.6 -m unittest tests.test_setup_state -v

# Pitfall-1 gate — MUST return ZERO matches across the package.
# Warning: literal tokens in comments/docstrings trip this grep too
# (we hit a false positive on a docstring that said "from PyQt5 import").
rg -n "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/

# exec_ gate — any hits must be on QFileDialog/QMessageBox, NEVER on the
# main PluginDialog/SetupTab (the main dialog must stay modeless):
rg -n "\.exec_\(\)" biochemeleon/
```

Running PyMOL requires the Windows side (`setenv.bat` → `pymol`); not doable from a WSL agent. Prefer the Grep tool over `rg` in bash (`rg *` is denied in `opencode.json`).

## Architecture — module dependency direction is strict

```
setup_state.py  (PURE: stdlib only — no pymol, no Qt; unit-testable in WSL)
      ↑
demos.py        (cmd bridge: imports FROM setup_state; uses pymol.cmd)
      ↑
gui_setup.py    (Qt + cmd: imports FROM setup_state AND demos)
```

Never reverse. `setup_state.py` must have NO `from pymol import cmd` and NO `from pymol.Qt import`. `GAME_REPS` and `DEMO_MANIFEST` live in `setup_state.py` (the pure layer) so pure functions can reference them without importing the cmd-coupled module.

Plugin entry point and dialog live in `biochemeleon/__init__.py`:
- Entry point is `__init_plugin__(app=None)` (NOT legacy `__init__(self)`); `addmenuitemqt` is imported locally inside it.
- `dialog = None` is a module-level singleton (GC prevention — must be module scope, not inside `__init_plugin__`).
- Main dialog is modeless: `dialog.show()`, NEVER `.exec_()`. Required so the 3D viewer stays interactive for the click-to-find loop.
- All Qt imports via `from pymol.Qt import QtWidgets` (auto-selects PyQt5/PySide2) — NEVER `from PyQt5 import`. `QFileDialog.exec_()` / `QMessageBox.exec_()` on child dialogs ARE allowed.

## Tests

- `tests/test_setup_state.py` stubs `pymol` and `pymol.Qt` with `MagicMock` via `sys.modules` before importing `biochemeleon.*`, because `__init__.py` does `from pymol.Qt import ...` at module level. Keep this stub pattern when adding WSL-runnable tests.
- Pure functions → `setup_state.py` + unit tests. cmd-coupled code → `demos.py`, verified by the Windows smoke test (not WSL tests).

## Domain rules (easy to get wrong)

- **Hiders are inserted INTO the same PyMOL object**, never a separate object (else the player toggles one object to win). Use `cmd.pseudoatom(object=existing, ...)`, not `cmd.load` / `cmd.create('hiders', ...)`.
- **Hider sentinel:** `segi='GAME'` + `b=-999`. Cleanup and session reload identify hiders by this sentinel ONLY — never by `resi`/`chain`/per-object `index` (unstable across deletions).
- **PyMOL Open Source has NO undo.** Every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (Phase 3 establishes this; all later phases rely on it).
- **GAME_REPS** = `['lines','sticks','spheres','cartoon','ribbon']`. `surface` is explicitly out of scope.
- No `cmd.get_representations()` in PyMOL 2.5.0; detect active reps with `cmd.count_atoms("{obj} and rep {rep}") > 0`.
- `cmd.fetch` must use `async_=0` for synchronous load.
- WSL→Windows path guard: `demos.to_windows_path()` converts `/mnt/c/...` → `C:\...` only for WSL mount paths (returns other paths unchanged). Windows PyMOL cannot resolve WSL paths.

## Code & UI standards (spec.md constraints)

- Code must be efficient, traceable, clean, and safe; the repo must be structured.
- UI must be simple and user-friendly, with clear but sufficient in-game explanation.

## Dependencies & attribution (spec.md constraints)

- Assume only what `pymol-open-source` ships (PyQt5 via `pymol.Qt`, numpy). If a specific Python lib is needed beyond that, the agent MUST write the list to a file and explicitly seek user approval first. Then the user either installs it locally, or the agent obtains a local copy for import from `./3rd_party_lib/` (git-ignored) with the library's license noted. When proposing a lib, state whether the user must set up a linux-like env or can keep the "calling cmd from WSL" approach. Do NOT `pip install` silently.
- Do NOT make up anything. ALL claims and citations (DOIs, PDB IDs, sources) MUST be verified against a source and explicitly approved by a human. Bundled demo sources are in `biochemeleon/data/demos/SOURCES.md`.

## GSD workflow (`.planning/`)

This repo uses the OpenCode "get-shit-done" workflow. `.planning/` is the source of truth for scope and state:
- `PROJECT.md` (what & why), `ROADMAP.md` (10-phase plan), `STATE.md` (current position), `REQUIREMENTS.md` (requirement IDs).
- `research/` — `STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `FEATURES.md`, `SUMMARY.md`. Read these before non-trivial PyMOL work; they encode verified API behavior and the pitfalls behind the grep gates above.
- `phases/<NN-name>/` — `NN-MM-PLAN.md`, `NN-MM-SUMMARY.md`, optional `RESEARCH.md` / `VERIFICATION.md` / `UAT.md`.
- Commit style: Conventional Commits with phase-plan scope, e.g. `feat(02-03):`, `docs(02-03):`, `test(02-01):`, `fix(02):`. Planning docs are committed (`commit_docs: true`).

## Git-ignored (don't rely on / don't commit)

`Pymol-script-repo/` (reference plugins for learning how to write PyMOL plugins), `3rd_party_lib/` (vendored libs), `tmp/`, `biochemeleon.zip` (staged fallback install artifact), `*.pyc`.
