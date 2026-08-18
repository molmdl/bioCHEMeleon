# Coding Conventions

**Analysis Date:** 2026-08-18

## Language & Runtime

**Python 3.6.9** in the WSL dev shell (syntax checks + unit tests only). **PyMOL 2.5.0** (conda, Windows) ships its own Python at runtime. Use ONLY stdlib + what `pymol-open-source` ships (`pymol.Qt` → PyQt5, `numpy`). Per `spec.md`: do NOT `pip install` silently; any other lib must be listed, user-approved, and vendored into `3rd_party_lib/` (git-ignored) with its license noted.

## Naming Patterns

**Package / modules:**
- Plugin package: lowercase `biochemeleon` (import name); display name `bioCHEMeleon` (window title, menu item).
- Modules: lowercase snake_case — `setup_state.py`, `gui_setup.py`, `game.py`, `registry.py`, `backup.py`, `mutation.py`, `persistence.py`, `generators.py`, `wizard.py`, `demos.py`.

**Files:**
- Test files: `tests/test_<module_under_test>.py` — mirrors the module. Examples: `tests/test_setup_state.py` ↔ `biochemeleon/setup_state.py`; `tests/test_registry.py` ↔ `biochemeleon/registry.py`; `tests/test_game_controller.py` ↔ `biochemeleon/game.py`.
- Smoke scripts: `smoke/phase<N>_smoke.py` (numbered by phase); diagnostics: `smoke/diag_<topic>.py` / `smoke/verify_<topic>.py`.

**Functions:**
- `snake_case` throughout. Pure generators: `generate_sphere_positions`, `generate_line_stick_offsets`, `pick_terminal_residues`, `pick_segments`, `generate_middle_displacement`.
- Cmd-coupled verbs: `snapshot`, `restore`, `discard`, `verify_intact`, `insert_hider`, `cleanup_hiders`, `fetch_all_hider_ids`.
- Private helpers: leading underscore — `_mark_found`, `_remaining`, `_on_start`, `_prepare_and_start`.

**Variables / fields:**
- Module constants: `UPPER_CASE` — `GAME_REPS`, `DEMO_MANIFEST`, `DEFAULTS`, `SETUP_FORMAT`, `PDB_POOL`, `BACKUP_PREFIX`, `HINT_RADIUS`, `HINT_COLOR`, `BCM_MAGIC`, `BCM_VERSION`, `HIDER_STATUS_HIDDEN`, `HIDER_STATUS_FOUND`.
- Private object state: leading underscore — `self._started`, `self._backup_name`, `self._reveal_count`, `self._found_color`, `self._is_imported`.

**Types:**
- Classes: `PascalCase` — `HiderRecord`, `HiderRegistry`, `GameController`, `PluginDialog`, `SetupTab`, `GameTab`, `ReconcileMismatches` (a `namedtuple`).
- `HiderRecord` uses `__slots__` (compact + surfaces typos as `AttributeError`); slot set is the documented contract (see `tests/test_registry.py::TestHiderRecord::test_slots_defined`).

**Sentinel / marker values (domain):**
- Backup object: `_bchm_backup` — underscore prefix = private (hidden from `cmd.get_names('public_objects')`). See `biochemeleon/backup.py:34`.
- Hider sentinel: `segi='GAME'` + `b=-999` (the **value**). Cleanup identifies hiders by `segi GAME` ALONE.
- b-factor **selector**: `b < 0` (NEVER `b -999` — malformed, silently matches nothing).
- Plugin temp-object prefix: `_bchm_*` (e.g. `_bchm_backup`, `_bchm_tmp`) — `cmd.delete('_bchm_*')` wildcard cleanup.

## Code Style

**Formatting:**
- No auto-formatter config (no `.prettierrc`, no `black`, no `isort` — none detected). Style is enforced by the grep gates (see Quality Gates) and review.
- Indentation: 4 spaces. Line length: not strictly enforced; long lines are common (manifest entries, docstrings).
- Single quotes for short strings, double quotes for strings containing apostrophes / HTML — both appear; consistency is per-file.

**Linting:**
- No `.flake8`, no `pylint`, no `mypy` config. The `# noqa: F401` marker appears in `biochemeleon/persistence.py:28` for an intentional re-export, indicating flake8-style awareness even without a configured runner.

## Architecture Rules (ENFORCED — never reverse)

The module dependency direction is strict. See `AGENTS.md` "Architecture" section.

**Pure layer (stdlib only — NO `from pymol import`, NO `from pymol.Qt import`; WSL-unit-testable):**
- `biochemeleon/setup_state.py` — setup schema, `GAME_REPS`, `DEMO_MANIFEST`, `DEFAULTS`, `PDB_POOL`, validation/randomization.
- `biochemeleon/registry.py` — `HiderRecord` + `HiderRegistry` + `ReconcileMismatches`. Imports only `collections` + `setup_state.GAME_REPS`.
- `biochemeleon/generators.py` — pure geometry/selection (stdlib `random` only). NO `pymol`, NO `numpy`.
- `biochemeleon/persistence.py` — `.bcm`/`.bcmz` assembly + I/O (stdlib `json`/`os`/`tempfile`/`time`/`zipfile` + `registry` + `setup_state`).

**cmd-coupled layer (`from pymol import cmd`; standalone, no cross-imports except via the orchestrator):**
- `biochemeleon/demos.py`, `biochemeleon/backup.py`, `biochemeleon/mutation.py`, `biochemeleon/wizard.py`.

**Orchestrator (cmd; composition root wiring backup + mutation + registry):**
- `biochemeleon/game.py` — `GameController` imports `backup`, `mutation`, `registry`.

**Qt + cmd layer (GUI):**
- `biochemeleon/__init__.py` (entry point + `PluginDialog`), `biochemeleon/gui_setup.py`, `biochemeleon/gui_game.py`.

`setup_state.py` MUST have NO `from pymol import cmd` and NO `from pymol.Qt import`. `registry.py` and `generators.py` and `persistence.py` are ALSO pure. `GAME_REPS` and `DEMO_MANIFEST` live in `setup_state.py` (the pure layer) so pure functions can reference them without importing a cmd-coupled module.

## Plugin Entry-Point Conventions

In `biochemeleon/__init__.py`:
- Entry point is `def __init_plugin__(app=None):` (NOT legacy `__init__(self)`). `addmenuitemqt` is imported LOCALLY inside it so a Qt-unavailable failure is caught cleanly instead of crashing module load (`biochemeleon/__init__.py:129-138`).
- `dialog = None` is a MODULE-LEVEL singleton (GC prevention — MUST be module scope, not inside `__init_plugin__`); see `biochemeleon/__init__.py:5`.
- Main dialog is MODELESS: `dialog.show()` + `dialog.raise_()` + `dialog.activateWindow()` (`biochemeleon/__init__.py:148-153`). NEVER `.exec_()` on the main `PluginDialog` — required so the 3D viewer stays interactive for the click-to-find loop.
- `QFileDialog.exec_()` / `QMessageBox.exec_()` / child-`QDialog.exec_()` on MODAL CHILD dialogs ARE allowed (e.g. `biochemeleon/__init__.py:952 help_dlg.exec_()`, `biochemeleon/gui_game.py:345` / `:404` `msg.exec_()`).
- Qt imports via `from pymol.Qt import QtCore, QtGui, QtWidgets` (auto-selects PyQt5/PySide2). NEVER `from PyQt5 import` / `import PyQt5` — the grep gate enforces this.

## Domain Rules (the "easy to get wrong" list — ALL enforced)

These are reproduced from `AGENTS.md` "Domain rules" and `.planning/research/PITFALLS.md`. Violations have caused real bugs.

**Hider insertion:**
- Hiders are inserted INTO the same PyMOL object via `cmd.pseudoatom(object=existing, ...)`, NOT a separate object (`cmd.load` / `cmd.create('hiders', ...)` would let the player toggle one object to win). See `biochemeleon/mutation.py`.
- Hider sentinel: `segi='GAME'` + `b=-999`. Identify hiders by sentinel ONLY — NEVER by `resi`/`chain`/per-object `index` (unstable across deletions).
- `cleanup_hiders` uses `segi GAME` ALONE (hiders are the only atoms with `segi=GAME`).
- b-factor sentinel SELECTOR is `b < 0`, NEVER `b -999` (PyMOL has no exact-match b-factor selector; `b -999` is malformed and SILENTLY matches nothing). The sentinel VALUE stays `-999`.
- `cmd.fetch` must use `async_=0` for synchronous load.

**Backup / mutation-safety (PyMOL Open Source has NO undo):**
- Every destructive op needs `backup.snapshot()` (`cmd.create('_bchm_backup', ...)`) BEFORE the mutation + restore-on-failure. See `biochemeleon/backup.py`.
- Restore = `cmd.delete(target)` + `cmd.create(target, backup)` TWO-STEP — NEVER single-call `cmd.create(existing, backup)` (merge-vs-replace ambiguity). See `biochemeleon/backup.py:54-64`.
- `backup.snapshot` MUST precede any `mutation.insert_hider` — there is NO undo (`undocontext` is a no-op stub).
- Do NOT re-call `verify_intact` on a backup AFTER `cleanup()`/`abort_on_error()` discarded it — both already run `verify_intact`/`restore` + `discard` internally; re-calling raises `CmdException` on the deleted object. Assert the orchestrator's RETURN value, not a re-derivation.

**Atom identity (registry):**
- Hider id via `cmd.identify("obj and name <handle> and segi GAME", mode=0)` after insert — NEVER rely on `cmd.pseudoatom()`'s return value (returns `None`).
- `cmd.iterate` exposes the atom id as UPPERCASE `ID`, NOT lowercase `id` (the Python builtin → `NameError` or wrong value).
- Registry keys on atom `id` (stable across add/delete + `.pse` reload) — NEVER on `index` (fragile, shifts on insert/remove). See `biochemeleon/registry.py`.
- `cmd.sort(obj)` after `cmd.alter` of `segi`/`chain` (defensive; stale canonical order confounds later `create`/`byres`). `sort` reassigns `index` but preserves `id` — safe for the id-keyed registry.

**Iterate/alter hygiene:**
- `cmd.iterate`/`cmd.alter` with `space={'stored': ...}` — NEVER `space=None` (pollutes global `pymol.__dict__`). See `biochemeleon/backup.py:80-84`.
- `cmd.iterate` does NOT expose `x`/`y`/`z` coords (state-dependent; need `cmd.iterate_state`). `verify_intact` uses `(resn, resi, name, chain, segi)` — count + identity multiset suffices.
- Use `resv` (numeric residue value, already int) NOT `int(resi)` — the hygienic `space=` dict does not expose Python builtins, so `int(resi)` raises `NameError`. See `biochemeleon/__init__.py:406-411`.

**Representations:**
- `GAME_REPS = ['lines', 'sticks', 'spheres', 'cartoon', 'ribbon']`. `surface` is explicitly OUT OF SCOPE.
- No `cmd.get_representations()` in PyMOL 2.5.0 → detect active reps with `cmd.count_atoms("{obj} and rep {rep}") > 0`.

**Dependency injection:**
- `reconstruct_from_sentinels` uses dependency injection — the iterate fn is passed as a parameter so `registry.py` stays pure (no `from pymol import cmd`); `game.py` injects `lambda: mutation.fetch_all_hider_ids(obj)`. See `biochemeleon/registry.py:420-443`.

**Path handling:**
- `demos.to_windows_path()` converts `/mnt/c/...` → `C:\...` only for WSL mount paths (returns other paths unchanged). Windows PyMOL cannot resolve WSL paths.

## Error Handling

**Strategy:** raise for caller-bugs; return True/False for environment/runtime failures; never raise from a reconciliation/parse path (degraded = playable).

**Patterns:**

- **Backup restore-on-failure** (`biochemeleon/backup.py:54-64`): `restore()` wraps `cmd.delete` + `cmd.create` in `try/except Exception` and returns `True`/`False`. The caller (`GameController.abort_on_error`) asserts the return value, NOT a re-derived `verify_intact`.
  ```python
  def restore(target_obj, backup_name=BACKUP_PREFIX):
      try:
          cmd.delete(target_obj)
          cmd.create(target_obj, backup_name)
          return True
      except Exception:
          return False
  ```

- **Idempotent cleanup**: `discard()` and `cmd.delete` are safe on absent objects. `cleanup_hiders` by `segi GAME` is idempotent.

- **Validation raises** (`biochemeleon/registry.py:111-112`, `:213`): `HiderRecord` raises `ValueError` for `rep not in GAME_REPS` (caller bug); `register` raises `KeyError` on duplicate `(object, id)` (caller bug). `mark_found` raises `KeyError` on unregistered `(object, id)` — a clean `KeyError` surfaces a caller bug immediately rather than silently no-op-ing.

- **Reconciliation never raises** (`biochemeleon/registry.py:447-510`): `reconcile_with_bcm` returns a `ReconcileMismatches` namedtuple of `(missing_from_bcm, missing_from_pse, bad_rep)`. A bad rep leaves `rec.rep = None` (do NOT raise — a corrupt sidecar should not kill the load). Malformed `.bcm` entries are `continue`d. The caller decides whether to log warnings or refuse the load.

- **Parse validates magic + version** (`biochemeleon/persistence.py`): `parse_bcm_dict` raises `ValueError` for wrong `magic` or unsupported `version` (clear "please update" error rather than silent mis-parse); `apply_bcm_dict` refuses wrong magic / unsupported version.

- **GUI error UI**: `QtWidgets.QMessageBox.warning(self, "<title>", "<message>")` for user-facing failures (fetch failed, no object, name collision). The async large-demo drain owns ALL error/cancel UI (no double-dialog — `_prepare_and_start` returns silently so the drain owns it). See `biochemeleon/__init__.py`.

- **Game-already-started guard** (`biochemeleon/game.py:57-58`): `start()` raises `RuntimeError("game already started; call cleanup() first")`; the GUI catches `RuntimeError` and shows a QMessageBox. See `biochemeleon/__init__.py:519-522`.

- **Timer rebase across modal dialogs** (`biochemeleon/__init__.py:725-768`): `_on_save` stops the timer before the modal `QFileDialog`, then rebases `self._controller._start_time = _time.time() - elapsed` after so the dialog+save time is NOT counted (Pitfall: timer must not advance during the modal file dialog).

## Logging

**Framework:** No logging framework. Use `print()` for console diagnostics (PyMOL console); the GUI `GameTab._log(msg)` appends to an in-dialog rolling `QTextEdit` info box (`biochemeleon/gui_game.py`). The game loop calls `self._on_log("Miss!" | "Already found!" | "Found one!")` callbacks (set via `set_callbacks`); the GUI wires these to the info box.

**Patterns:**
- Pure modules NEVER log (no side effects).
- `GameController` invokes the injected `_on_log` callback; default is a no-op `lambda msg: None` (`biochemeleon/game.py:28`). Tests pass `MagicMock()` and assert call args.
- Generation warnings (`_gen_warnings`) are collected during generation and shown via a single `QMessageBox.warning` AFTER start (non-blocking — the game still starts with the hiders that WERE generated). See `biochemeleon/__init__.py:486-488`.

## Comments

**When to Comment:**
- Module docstrings are MANDATORY and extensive: purpose, purity tier (PURE / cmd-coupled), dependency direction, what functions it exports, and run command for the matching test file. See `biochemeleon/registry.py:1-26`, `biochemeleon/generators.py:1-20`, `biochemeleon/persistence.py:1-20`.
- PyMOL API citations as inline `file:line` comments at the call site — e.g. `# creating.py:960`, `# editing.py:1490`, `# commanding.py:496`. See `biochemeleon/backup.py:42-49`.
- Pitfall/bug-fix provenance comments — e.g. `biochemeleon/__init__.py:404-411` ("Bug 2: captured BEFORE any insert"), `biochemeleon/registry.py:109` ("rep=None is allowed (post-reload reconstruction)").
- "Why" comments over "what" comments — the code already says what it does.

**JSDoc/TSDoc:**
- Python docstrings (Google-ish style, not strict Sphinx). Class docstrings list attributes + types + meaning. Method docstrings describe behavior, preconditions, return value, and what raises. See `biochemeleon/registry.py:56-102` (HiderRecord docstring), `:194-215` (register).
- `:returns:`, `Raises:`, `Precondition:` prose (not formal `:rtype:`). Examples: `biochemeleon/backup.py:40-41`, `biochemeleon/registry.py:387-407`.

## Import Organization

**Order:**
1. stdlib (`import os`, `import sys`, `import random`, `import json`, `import zipfile`, `from collections import OrderedDict, namedtuple`).
2. PyMOL (`from pymol import cmd`, `from pymol.Qt import QtCore, QtGui, QtWidgets`, `from pymol.wizard import Wizard`) — at module top in cmd-coupled modules; locally inside functions for late-bound plugin entry (e.g. `from pymol.plugins import addmenuitemqt` inside `__init_plugin__`).
3. Intra-package (`from . import backup, mutation, registry`, `from .setup_state import GAME_REPS`, `from .registry import HiderRegistry`).
4. Late-bound local imports inside GUI handlers (`from . import demos`, `from . import persistence`, `from pymol import cmd`) to keep plugin load robust — a bug in a sibling module doesn't break load (only runs on first open). See `biochemeleon/__init__.py:177-178`, `:289`.

**Path Aliases:**
- None. Intra-package imports use relative form (`from .setup_state import ...`). Tests insert repo root on `sys.path` (`sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))`) so `from biochemeleon.X import Y` resolves.

## Function Design

**Size:** Small, single-purpose. Pure generators are < 30 lines. `GameController` methods are short; the orchestration sprawl lives in `__init__.py` handlers (`_prepare_and_start`, `_continue_after_large_demo_fetch`, `_resolve_large_demo` — the longest functions, documented with behavior-preserving-extraction provenance comments).

**Parameters:**
- Pure functions take data IN, return data OUT (no `cmd`, no side effects). `generators.py` functions take `extent`/`cas_by_chain` (built by the cmd-coupled caller) and return positions/segments.
- Keyword args for optional/Phase-later additions — e.g. `randomize_state(seed=..., lock_source=False, locked_state=None, pdb_pool=None, atom_count=None)`. Backward-compatible defaults are the norm (Phase 11 alt-conf fields default to non-altconf so Phase 3/4/5 callers are unaffected).
- `id` parameters are coerced to `int` (str ids from JSON round-trip correctly): `HiderRecord.__init__` does `self.id = int(id)`; `HiderRegistry.get`/`remove`/`mark_found` do `int(id)`. See `biochemeleon/registry.py:113`, `:223`, `:236`, `:312`.

**Return Values:**
- `None` signals "nothing to do" (e.g. `build_found_selection([], "obj") -> None` so the caller can early-return without issuing a malformed selection). See `biochemeleon/registry.py:515-534`.
- `True`/`False` for operation success (`backup.restore`, `HiderRegistry.remove`).
- Fresh lists (not internal state) for queries (`HiderRegistry.all` returns `list(self._records.values())` — mutating it doesn't affect the registry).
- `self` for fluent chaining (`reconstruct_from_sentinels` returns `self`).

## Module Design

**Exports:**
- Modules export the public API at module top (constants) and via classes. No barrel files.
- `persistence.py` re-exports `HiderRegistry` + `ReconcileMismatches` for callers with a `# noqa: F401` marker (`biochemeleon/persistence.py:28`).

**Purity tier is the organizing principle:**
- PURE modules (`setup_state.py`, `registry.py`, `generators.py`, `persistence.py`): stdlib only, WSL-unit-testable, NO `from pymol`.
- cmd-coupled modules: `from pymol import cmd` at top, standalone (no cross-imports among themselves except via `game.py`).
- `game.py` is the composition root that wires `backup` + `mutation` + `registry`.
- Qt+cmd GUI modules import from both pure and cmd-coupled layers.

**Barrel Files:** None. The package `__init__.py` is the plugin entry point (not a re-export barrel).

## Quality Gates (the project's enforced gates)

Run from repo root (per `AGENTS.md` "Commands"). Verified green during this analysis (2026-08-18):

```bash
# 1. Syntax-check every module (py_compile checks syntax, NOT imports):
python3.6 -m py_compile biochemeleon/*.py
#   STATUS: PASSES (PY_COMPILE_OK).

# 2. Run the pure-layer unit tests (334 tests across 5 modules — AGENTS.md says
#    "48 tests" but that count predates phases 3-11; current is 334):
python3.6 -m unittest discover -s tests -v
#   STATUS: 334 tests, OK (0.063s). Per-module: test_setup_state=125,
#   test_registry=102, test_persistence=37, test_generators=35,
#   test_game_controller=35.

# 3. Pitfall-1 gate — MUST return ZERO matches across the package.
#    (Warning: literal tokens in comments/docstrings trip this grep too —
#    we hit a false positive on a docstring that said "from PyQt5 import".)
grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" biochemeleon/
#   STATUS: ZERO matches (exit 1 = no matches).

# 4. exec_ gate — any hits must be on QFileDialog/QMessageBox/child QDialog,
#    NEVER on the main PluginDialog/SetupTab (the main dialog must stay modeless):
grep -rnE "\.exec_\(\)" biochemeleon/
#   STATUS: 3 matches, ALL on child dialogs (compliant):
#     biochemeleon/gui_game.py:345:   msg.exec_()        (QMessageBox)
#     biochemeleon/gui_game.py:404:   msg.exec_()        (QMessageBox)
#     biochemeleon/__init__.py:952:   help_dlg.exec_()   (modal child QDialog)
```

**WSL→Windows runtime gap:** Pure `pymol.cmd.*` paths can be run headlessly from WSL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` (stage to `tmp/bioCHEMeleon/` first via `wsl2win_cp.sh`). `pymol.Qt.*` paths CANNOT run from WSL (need a real display) — GUI/Qt smoke tests remain human-verify checkpoints.

## Code & UI Standards (from `spec.md`)

- Code must be **efficient, traceable, clean, and safe**; the repo must be **structured**.
- UI must be **simple, user-friendly, with clear but sufficient in-game explanation**.
- Do NOT make up anything. ALL claims and citations (DOIs, PDB IDs, sources) MUST be verified against a source and explicitly approved by a human. Bundled demo sources are in `biochemeleon/data/demos/SOURCES.md` and repo-root `DATA_SOURCES.md`.

---

*Convention analysis: 2026-08-18*
