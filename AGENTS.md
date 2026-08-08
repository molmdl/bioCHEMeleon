# AGENTS.md

High-signal notes for OpenCode sessions. Read before touching code. See `spec.md` and `.planning/PROJECT.md` for full project context.

> **Scope:** v1 (PyMOL 2.5.0 plugin). v2 (VMD tcl script) is deferred per `spec.md` — this file is v1-scoped; revisit it when v2 research begins. When the active milestone becomes v2, flag that AGENTS.md needs a VMD/tcl-specific rewrite.

## Environment — the WSL/Windows split (read first)

This is the single most common way to break things.

- **Dev shell is WSL Ubuntu.** Do NOT install anything, do NOT create conda envs, do NOT `pip install`. `python3.6` (3.6.9) is for syntax checks and unit tests ONLY. (`opencode.json` denies `pip*`, `apt*`, `conda*`, `rm*`.)
- **PyMOL 2.5.0 runs in a Windows conda env**, not WSL. `setenv.bat` is a Windows cmd.exe batch that activates env `chemtools-win10` from `C:\ProgramData\Miniconda3`; it does NOT launch PyMOL — you run `pymol` from the activated shell. A WSL agent CANNOT run the interactive GUI, and CANNOT use Qt (`pymol.Qt.*`) at runtime.
- **Headless PyMOL CAN be run from WSL** (discovered Phase 3, 2026-08-06). `C:\src\run-conda-pymol.bat` accepts args passed through to `python .../pymol/__init__.py %*`. The `-cq` flags run PyMOL without the GUI (command-line, quiet). So a WSL agent CAN execute any pure-cmd script (no Qt, no interactive viewer) headlessly via:
  ```bash
  # 1. Stage the package + script to the Windows-facing path first:
  bash wsl2win_cp.sh                          # copies biochemeleon/ -> tmp/bioCHEMeleon/biochemeleon/
  mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/  # stage the script
  # 2. Run headlessly (no GUI, ~30s for the phase3 smoke). Wrap in timeout + tail to avoid hangs:
  cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -50
  # 3. Check exit code: 0 = clean (or sys.exit(1) caught by wrapper); nonzero = crash.
  ```
  This closes the WSL/Windows runtime gap for cmd-only scripts. It does NOT help with Qt (GUI/prompt tests still need a human in a real PyMOL session). Always `cd` into the staged Windows path first (PyMOL resolves relative paths against the cmd.exe cwd, which is the WSL cwd mapped to `\\wsl$` or the /mnt/c path — use the /mnt/c path so Windows PyMOL can read it).
- **Consequence:** any code path that executes `pymol.Qt.*` at runtime STILL cannot be run from WSL (GUI/Qt needs a real display). Pure `pymol.cmd.*` paths CAN be run headlessly as above. Only the pure data layer (`biochemeleon/setup_state.py`) is unit-testable in WSL without invoking PyMOL at all. Qt/GUI smoke tests remain human-verify checkpoints.
- `wsl2win_cp.sh` copies `biochemeleon/` to `tmp/bioCHEMeleon/` so the Windows PyMOL Plugin Manager (or the headless cmd.exe invocation above) can point at a Windows-side path.

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

Running the interactive PyMOL GUI requires the Windows side (`setenv.bat` → `pymol`); not doable from a WSL agent. But headless cmd-only scripts CAN be run from WSL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` (see the Environment section above). Prefer the Grep tool over `rg` in bash (`rg *` is denied in `opencode.json`).

## Architecture — module dependency direction is strict

```
setup_state.py  (PURE: stdlib only — no pymol, no Qt; unit-testable in WSL)
      ↑
demos.py        (cmd bridge: imports FROM setup_state; uses pymol.cmd)
      ↑
gui_setup.py    (Qt + cmd: imports FROM setup_state AND demos)

Phase 3 stack (mutation-safety; game.py is the composition root):
  registry.py  (PURE: stdlib + GAME_REPS from setup_state; unit-testable in WSL)
  backup.py    (cmd: snapshot/restore/discard/verify_intact — standalone)
  mutation.py  (cmd: insert_hider/fetch_all_hider_ids/cleanup_hiders — standalone)
  game.py      (cmd orchestrator: GameController imports backup+mutation+registry)
```

Never reverse. `setup_state.py` must have NO `from pymol import cmd` and NO `from pymol.Qt import`. `registry.py` (Phase 3) is ALSO pure (stdlib + `GAME_REPS` from setup_state; no `from pymol`) — unit-testable in WSL. `backup.py`/`mutation.py` are standalone cmd bridges (no cross-module imports); `game.py` is the composition root that wires all three. `GAME_REPS` and `DEMO_MANIFEST` live in `setup_state.py` (the pure layer) so pure functions can reference them without importing the cmd-coupled module.

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

### Phase 3 mutation-safety rules

- **Restore = `cmd.delete(target)` + `cmd.create(target, backup)` two-step** — NEVER single-call `cmd.create(existing, backup)` (merge-vs-replace UNVERIFIED C-dispatched; RESEARCH §Q2). Smoke test confirmed single-call create IS REPLACE (`n_after==n_before`), but delete+create stays for an unambiguous failure-path.
- **Hider id via `cmd.identify("obj and name <handle> and segi GAME", mode=0)`** after insert — NEVER rely on `cmd.pseudoatom()`'s return value (smoke test: returns `None`/`NoneType`; RESEARCH §Q1).
- **`cmd.iterate` exposes the atom id as UPPERCASE `ID`**, not lowercase `id` (the Python builtin → `NameError` or wrong value; symbol table editing.py:1444-1449). Smoke test caught a lowercase-`id` transcription bug.
- **Registry keys on atom `id`** (stable across add/delete; smoke test: id stable across `.pse` reload, `pse_sent==[saved_id]`) — NEVER on `index` (fragile, shifts on insert/remove; RESEARCH §Q4, querying.py:1315).
- **`reconstruct_from_sentinels` uses dependency injection** — the iterate fn is passed as a parameter so `registry.py` stays pure (no `from pymol import cmd`); `game.py` injects `lambda: mutation.fetch_all_hider_ids(obj)`.
- **rep is NOT recoverable from sentinels after `.pse` reload** — the sentinel carries only `segi='GAME'` + `b=-999`; `reconstruct_from_sentinels` sets `rep=None`. Phase 8 `.bcm` sidecar reconciles `rep` (RESEARCH Open Risk 6; smoke test confirmed `rep=None` post-reload).
- **`backup.snapshot` MUST precede any `mutation.insert_hider`** — there is NO undo (undocontext is a no-op stub; editor.py:25-36); the backup is the only recovery mechanism.
- **Do NOT re-call `verify_intact` on a backup AFTER `cleanup()`/`abort_on_error()` discarded it** — both already run `verify_intact`/`restore` + `discard` internally; re-calling raises `CmdException` on the deleted object. Assert the orchestrator's RETURN value, not a re-derivation.
- **`cmd.iterate`/`cmd.alter` with `space={'stored': ...}`** — NEVER `space=None` (pollutes global `pymol.__dict__`; RESEARCH §Q3, editing.py:59-60).
- **`cmd.iterate` does NOT expose `x`/`y`/`z` coords** (state-dependent; need `cmd.iterate_state`). `verify_intact` uses `(resn, resi, name, chain, segi)` — count + identity multiset suffices because `cmd.create` copies coords bit-for-bit (RESEARCH §Q6).
- **B-factor sentinel SELECTOR is `b < 0`, NEVER `b -999`** — PyMOL has no exact-match b-factor selector; `b -999` is malformed ("Selector-Error: Malformed selection") and silently matches nothing. The sentinel VALUE stays `-999` (set in `insert_hider`/cleanup docstrings); only the SELECTOR uses the comparison `b < 0` (matches `-999.0`).
- **`cleanup_hiders` uses `segi GAME` ALONE** (sentinel-only; hiders are the only atoms with `segi=GAME`). `b < 0` is for `fetch_all_hider_ids`/read paths; cleanup by `segi GAME` ONLY. NEVER by `resi`/`chain`/per-object `index` (unstable across deletions).
- **`cmd.sort(obj)` after `cmd.alter` of `segi`/`chain`** — defensive (editing.py:1457: stale canonical order confounds later `create`/`byres`). `sort` reassigns `index` but preserves `id` — safe for the id-keyed registry.
- **Architecture: `registry.py` (pure) ← `backup.py`/`mutation.py` (cmd) ← `game.py` (orchestrator)** — strict dependency direction. `registry.py` has NO `from pymol import`. `game.py` wires all three.

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

## Parallel subagent execution (worktree/branch protocol)

When `/gsd-execute-phase` runs **≥2 plans in parallel** (one wave with
multiple autonomous plans), each `gsd-executor` subagent commits on a
**shared git index** — concurrent `git add`/`git commit` calls race and
sweep in each other's staged files (happened in Phase 4 Wave 1: 3 agents,
~3 Rule-3 collision fixes). To eliminate this collision class:

- **One worktree per parallel plan.** Before spawning a wave, the
  orchestrator creates a git worktree (or branch) per parallel plan:
  `git worktree add tmp/exec-04-01 -b exec/04-01` (etc.). Each agent is
  spawned with `workdir=tmp/exec-04-01` so it commits on an isolated
  index — zero shared-index races.
- **Merge back in dependency order.** After all agents in the wave return,
  the orchestrator merges/fast-forwards each branch into the base in
  dependency order (`git merge exec/04-01`, then `exec/04-02`, ...). Real
  conflicts (same file touched by two plans — should be rare given
  disjoint `files_modified` frontmatter) are resolved explicitly here.
- **Single-plan waves skip this.** Waves with one plan (no parallelism)
  need no worktree — commit directly on the base branch. The protocol
  only applies when ≥2 plans run concurrently.
- **TDD multi-commit safety.** Each agent can still do atomic
  RED/GREEN/REFACTOR commits freely on its own branch — the per-task
  commit granularity is preserved (unlike an orchestrator-owned commit
  gate, which would collapse TDD's commit boundaries).

Orchestrators: if `parallelization: true` in `.planning/config.json` and a
wave has >1 plan, use this protocol. See `.planning/quick/001-*` for the
rationale + rejected alternatives (message-board lock, orchestrator commit
gate).

## Git-ignored (don't rely on / don't commit)

`Pymol-script-repo/` (reference plugins for learning how to write PyMOL plugins), `3rd_party_lib/` (vendored libs), `tmp/`, `biochemeleon.zip` (staged fallback install artifact), `*.pyc`.
