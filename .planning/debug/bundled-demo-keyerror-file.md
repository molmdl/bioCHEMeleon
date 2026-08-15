---
status: investigating
trigger: "Bundled demo mode raises KeyError: 'file' when clicking Start in the bioCHEMeleon Setup tab with target_mode=demo. Observed during Phase 11 GUI human-verify but CONFIRMED PRE-EXISTING on main (introduced by an earlier phase, not Phase 11). User asked to write a debug file for another agent to investigate."
created: 2026-08-16T00:00:00Z
updated: 2026-08-16T00:00:00Z
---

## Current Focus

hypothesis: `DEMO_MANIFEST` entries at some point stopped carrying a `'file'` key (schema drift between the manifest definition in `setup_state.py:DEMO_MANIFEST` and the loader `demos.load_demo` which does `meta['file']`). `demos.load_demo` raises `KeyError('file')` instead of returning None, which propagates up through `_prepare_and_start` (line 142) and `_on_start` (line 90) as an uncaught traceback (the `try/except` in `load_demo` only wraps `cmd.load`, NOT the `meta['file']` access at line 128). Root cause is likely one of: (a) the manifest entries were refactored to a different key name (e.g. `'path'`, `'pdb'`) and `load_demo` was not updated; (b) the manifest entries are nested (e.g. `{'file': {...}}` vs flat) and the access path changed; (c) a new demo id is being passed that maps to a sentinel/placeholder entry without a `'file'` key. NEEDS VERIFICATION: read `DEMO_MANIFEST` in `setup_state.py` and compare its actual key schema against `demos.load_demo`'s `meta['file']` access.
test: Read `biochemeleon/setup_state.py` around the `DEMO_MANIFEST` definition (grep found it at line 34). Compare each entry's keys against `demos.py:128`'s `meta['file']` access. Also check `gui_setup.py:125` (`for did, meta in DEMO_MANIFEST.items()`) to see what keys the Setup-tab combo population expects — if gui_setup and demos disagree on the schema, that's the drift.
expecting: Either the manifest entries use a different key (schema drift -> fix the key in `load_demo` OR rename in the manifest), OR a specific demo id has a malformed entry (-> fix that entry), OR the `try/except` in `load_demo` needs to widen to cover the `meta['file']` access (defensive, but the real fix is the schema).
next_action: Read `setup_state.py:34` (DEMO_MANIFEST) fully; cross-reference with `demos.py:114-137` (load_demo) and `gui_setup.py:122-125` (combo population). Confirm the schema mismatch. Then decide fix scope (loader vs manifest vs both). Verify the fix headlessly if possible (the load_demo path is pure `pymol.cmd` + os.path — a headless script can call `demos.load_demo(demo_id)` for each manifest id and assert no KeyError + returns a valid obj name). GUI final check is a human-verify checkpoint.

## Symptoms

expected: Selecting a bundled demo (target_mode=demo) in the bioCHEMeleon Setup tab and clicking Start loads the demo PDB into PyMOL and starts the game (no exception).
actual: Clicking Start with target_mode=demo raises an uncaught `KeyError: 'file'` traceback in the PyMOL console. The game does not start. The error fires 8+ times in the observed session (user clicked Start repeatedly / retried).
errors: VERBATIM traceback from the PyMOL console (Windows PyMOL 2.5.0 GUI, plugin loaded from `tmp/bioCHEMeleon/biochemeleon/`):

```
Traceback (most recent call last):
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/bioCHEMeleon\biochemeleon\__init__.py", line 90, in _on_start
    controller, target_obj, _ = self._prepare_and_start(state)
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon\tmp\bioCHEMeleon\biochemeleon\__init__.py", line 142, in _prepare_and_start
    target_obj = demos.load_demo(demo_id)
  File "C:\Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon\tmp\bioCHEMeleon\biochemeleon\demos.py", line 128, in load_demo
    path = os.path.join(os.path.dirname(__file__), 'data', 'demos', meta['file'])
KeyError: 'file'
```

(Repeated 8 times across the session — each Start click re-triggered it.)

reproduction:
1. Launch Windows PyMOL (`setenv.bat` -> `pymol`).
2. Load the bioCHEMeleon plugin (Plugin Manager -> point at the biochemeleon/ path).
3. In the Setup tab, set target_mode = **demo** (bundled demo mode), pick any demo id from the combo.
4. Click **Start**.
5. Observe: `KeyError: 'file'` traceback in the PyMOL console; game does not start.
started: Pre-existing on `main` (user confirmed: "main also has this issue"). Introduced by an earlier phase (NOT Phase 11). Phase 11 work is on branch `exec/11` (worktree `tmp/exec-11`); this bug reproduces on BOTH `main` and `exec/11`, so it is independent of the Phase 11 cartoon/ribbon refactor.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-16T00:00:00Z
  checked: `biochemeleon/demos.py:114-137` (load_demo) on `exec/11` worktree
  found: |
    `load_demo(demo_id)` does:
      meta = DEMO_MANIFEST.get(demo_id)         # line 125 -- returns None if id missing
      if meta is None: return None              # line 126-127 -- handles missing id
      path = os.path.join(..., 'data', 'demos', meta['file'])  # line 128 -- <-- KeyError HERE
      if not os.path.exists(path): return None  # line 129-130
      win_path = to_windows_path(path)          # line 131
      ...
      try: cmd.load(win_path, object=obj_name, zoom=1)  # line 133-134
      except Exception: return None                      # line 135-136
    The `try/except` wraps ONLY `cmd.load`. The `meta['file']` access at line 128 is OUTSIDE the try block, so a missing 'file' key raises an UNCAUGHT KeyError that propagates to `_prepare_and_start` (line 142) -> `_on_start` (line 90).
  implication: The bug is a schema mismatch between `DEMO_MANIFEST` entries and `load_demo`'s `meta['file']` access. The defensive `try/except` does not cover this line. Two fix angles: (a) fix the schema (make manifest entries have 'file'), or (b) widen the guard (but the real bug is the schema).

- timestamp: 2026-08-16T00:00:00Z
  checked: `biochemeleon/__init__.py:136-146` (the demo-mode branch of `_prepare_and_start`) on `exec/11`
  found: |
    elif mode == "demo":
        demo_id = state.get("demo_id", "")
        target_obj = demo_id.lower() if demo_id else ""
        if not target_obj or target_obj not in demos.list_loaded_molecule_objects():
            target_obj = demos.load_demo(demo_id)   # line 142 -- calls the buggy fn
            if target_obj is None:                   # line 143 -- expects None on failure
                QtWidgets.QMessageBox.warning(...)   # line 144-145
                return None, None, []
    `_prepare_and_start` EXPECTS `load_demo` to return None on failure (line 143 checks `if target_obj is None`). But `load_demo` RAISES KeyError instead of returning None when 'file' is missing — so the None-check never fires and the traceback propagates. This confirms the contract violation: `load_demo`'s docstring says "Returns ... None on failure" but it raises on a schema gap.
  implication: The fix should restore the documented contract — either the manifest has 'file' (so the happy path works) AND/OR the loader catches the KeyError (so the None-on-failure contract holds even for malformed entries).

## Resolution

root_cause: (empty — pending confirmation by reading DEMO_MANIFEST in setup_state.py:34)
fix: (empty)
verification: (empty)
files_changed: []

## Context for the next agent

**Where to work:** This bug is PRE-EXISTING on `main` and independent of Phase 11. The user has NOT specified a worktree. Recommend investigating on `main` directly (read-only investigation) and applying the fix on `main` (or a fresh branch off `main`) since this is not Phase 11 work. If you prefer isolation, create a new worktree: `git worktree add tmp/debug-demo-keyerror -b fix/demo-keyerror` from the main repo. DO NOT work in `tmp/exec-11` — that worktree is for Phase 11 and is about to be merged; mixing this unrelated fix there would entangle the branches.

**Key files to read (on main, same paths as exec/11 since this bug is shared):**
- `biochemeleon/setup_state.py:34` — `DEMO_MANIFEST` definition (CONFIRM the actual key schema of each entry; this is the #1 unknown).
- `biochemeleon/demos.py:114-137` — `load_demo` (the buggy `meta['file']` access + the too-narrow `try/except`).
- `biochemeleon/gui_setup.py:122-125` — the Setup-tab combo population (`for did, meta in DEMO_MANIFEST.items()` — see which keys the combo reads; if it reads a different key than 'file', that's the drift smoking gun).
- `biochemeleon/__init__.py:90,136-146` — `_on_start` and the demo branch of `_prepare_and_start` (the call site + the None-on-failure contract).

**AGENTS.md rules that apply:**
- `setup_state.py` is the PURE layer (stdlib only, no `from pymol import cmd`, no Qt). If the fix touches `DEMO_MANIFEST`, keep it pure. `demos.py` is the cmd bridge (imports from setup_state, uses pymol.cmd).
- Pure-layer unit tests: `python3.6 -m unittest tests.test_setup_state -v` must stay green. There may be existing tests asserting the DEMO_MANIFEST schema — check `tests/test_setup_state.py` for `DEMO_MANIFEST` references and update them if the schema changes.
- Pitfall-1 grep gate: 0 matches. exec_ gate: only on QFileDialog/QMessageBox.
- Headless verification IS possible for this bug: the `load_demo` path is pure `pymol.cmd` + `os.path` (no Qt). A headless script can iterate `DEMO_MANIFEST` ids, call `demos.load_demo(did)` for each, and assert (a) no KeyError, (b) returns a valid obj name or None. Run via the WSL->Windows bridge:
  ```bash
  bash wsl2win_cp.sh
  mkdir -p tmp/bioCHEMeleon/smoke && cp <your_diag_script>.py tmp/bioCHEMeleon/smoke/
  cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\<your_diag_script>.py" 2>&1 | tail -50
  ```
  GUI final check (does the demo actually LOAD and the game START) is a human-verify checkpoint.

**Hypothesis ranking (investigate in this order):**
1. SCHEMA DRIFT (most likely): `DEMO_MANIFEST` entries use a key other than `'file'` (e.g. `'path'`, `'pdb'`, `'filename'`) and `load_demo` was not updated when the schema changed. Fix: align the key (prefer renaming in the loader to match the manifest, OR rename the manifest key to `'file'` — pick whichever minimizes test churn). Cross-check `gui_setup.py:125` to see which key the combo population reads — if it reads the SAME wrong key as `load_demo`, then the manifest was renamed and BOTH call sites drifted; if it reads a DIFFERENT key, only `load_demo` drifted.
2. NESTED/PARTIAL ENTRY: one specific demo id (e.g. a placeholder added for a not-yet-bundled PDB) has an entry without 'file'. Fix: complete the entry OR have `load_demo` skip entries without 'file' (return None).
3. NONE-CONTRACT GAP (defensive, layer on top of the real fix): `load_demo`'s `try/except` should cover the `meta['file']` access (and the `os.path.exists` check) so a malformed entry returns None per the docstring instead of raising. This is defense-in-depth, NOT the primary fix.

**Deliverable:** A minimal fix that makes `load_demo` honor its "Returns None on failure" contract for ALL manifest entries AND resolves the schema mismatch so the happy path works. Headless test iterating all `DEMO_MANIFEST` ids passing. Smoke green. GUI human-verify: demo mode Start loads the PDB and starts the game.
