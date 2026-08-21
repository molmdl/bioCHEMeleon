---
status: resolved
trigger: "Hardcoded path to fetched glycoprotein/membrane protein demos breaks when the plugin runs on a separate computer (outside the dev repo). Testing the bundled example glycoprotein and membrane protein on a separate computer produces an error looking for PATH/../tmp/phase9-demos/FILE.raw."
created: 2026-08-22T00:00:00Z
updated: 2026-08-22T00:30:00Z
---

## Current Focus

hypothesis: CONFIRMED — see Resolution.
test: N/A (root cause confirmed, fix applied + verified).
expecting: N/A.
next_action: Archive + commit.

## Symptoms

expected: Selecting the glycoprotein (sasdpg4) or membrane protein (1gzm, 3gp6) demo on a separate computer (plugin installed from the zip, NOT running from the dev repo) should download + load the demo successfully, same as on the dev machine.
actual: Error looking for a path like `<package_dir>/../tmp/phase9-demos/FILE.raw` which does not exist on the separate computer.
errors: Path-related error referencing `PATH/../tmp/phase9_demos/FILE.raw` after the download step. (User paraphrased the path; code uses hyphen `phase9-demos`.)
reproduction: Install the plugin on a fresh computer (from bioCHEMeleon_v1_pymol-open-src-2.5.0.zip), open it in PyMOL, select the glycoprotein or membrane protein demo from the demo dropdown, start the game. The fetch path resolves to a `tmp/phase9-demos/` directory that only exists in the dev repo.
started: Worked on the dev machine because the git-ignored `tmp/phase9-demos/` dir was created during development. Fails on any machine where that dir does not exist.

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-22T00:01
  checked: pymol/biochemeleon/demos.py _cache_dir() (lines 203-218)
  found: Returns `os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', 'cache'))`. Resolves to `<package>/../tmp/phase9-demos/cache/`. Docstring (lines 211-212) EXPLICITLY acknowledges: "v1 runs from the repo (AGENTS.md); an installed plugin would need a configurable cache dir (Open Risk 4 / Pitfall E -- v2)."
  implication: This is a KNOWN deferred issue (Pitfall E / Open Risk 4) that is now biting v1 because the plugin is installed on a separate computer.

- timestamp: 2026-08-22T00:02
  checked: pymol/biochemeleon/demos.py temp_download_path() (lines 253-267)
  found: Returns `os.path.join(os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', demo_id + '.raw')`. Same dev-repo-relative pattern as _cache_dir().
  implication: The .raw temp download path also points at the dev-repo-local tmp/ dir.

- timestamp: 2026-08-22T00:03
  checked: pymol/biochemeleon/demos.py download_large_demo() (lines 338-392)
  found: Worker opens dest_path for writing at line 378 (`with open(dest_path, 'wb') as f:`) but NEVER creates the parent directory first. There is NO os.makedirs call anywhere in the worker. On a fresh machine the parent dir `<package>/../tmp/phase9-demos/` does not exist -> `open()` raises FileNotFoundError -> caught by `except Exception as exc: progress_queue.put(('error', str(exc)))` at line 391-392 -> drain shows "Could not download <id>: [Errno 2] No such file or directory".
  implication: PRIMARY FAILURE POINT is the missing os.makedirs before open() in the worker, combined with the dev-repo-relative path that doesn't exist on a fresh install.

- timestamp: 2026-08-22T00:04
  checked: pymol/biochemeleon/demos.py finalize_large_demo() (lines 395-493)
  found: DOES call `os.makedirs(cache_dir, exist_ok=True)` at line 481 — but ONLY for the cache subdir, AFTER the download succeeds (reached on the 'done' event). This is too late for the download itself, and the cache_dir path is the dev-repo-relative one anyway.
  implication: The cache dir creation is not the primary failure (it's downstream of the download). But the dev-repo-relative cache path is still wrong for an installed plugin even if the download succeeded.

- timestamp: 2026-08-22T00:05
  checked: pymol/biochemeleon/__init__.py _resolve_large_demo() (lines 525-654)
  found: Line 554: `obj = demos.load_cached_demo(demo_id)` (cache hit -> sync return). Line 573: `tmp_path = demos.temp_download_path(demo_id)` (the dev-repo-relative .raw path). Line 575-576: spawns worker with `demos.download_large_demo(demo_id, tmp_path, q, cancel)`. Line 600: on 'done', calls `demos.finalize_large_demo(demo_id, tmp_path)`. The tmp_path is NOT converted via to_windows_path here — conversion happens INSIDE finalize_large_demo (line 462) and load_cached_demo (line 520). The worker receives the raw path and uses Python's open() (not PyMOL), so it uses the OS-native path directly.
  implication: Confirms the full fetch flow. The worker's open(dest_path) is the exact failure point on a fresh machine.

- timestamp: 2026-08-22T00:06
  checked: .gitignore + zip artifact contents
  found: .gitignore line 14 = `tmp` (gitignored). Zip `bioCHEMeleon_v1_pymol-open-src-2.5.0.zip` has 42 entries, ZERO matching tmp/phase9 (verified via python zipfile). The zip contains `biochemeleon/` (the package) + `data/demos/` (bundled PDbs) but NO `tmp/` dir.
  implication: Confirmed: a fresh install from the zip has NO `tmp/phase9-demos/` dir. The path resolution to `<package>/../tmp/phase9-demos/` cannot work.

- timestamp: 2026-08-22T00:07
  checked: DEMO_MANIFEST in setup_state.py (lines 34-57)
  found: 6 bundled demos (1znf, 5e54, 1k8p, 1xdn, 2qbz, 4wb3) load from data/demos/*.pdb (offline, always available). 3 fetched demos: sasdpg4 (SASBDB glycoprotein, strip=False), 1gzm + 3gp6 (MemProtMD membrane proteins, strip=True). The fetched demos are the ones that hit the broken path.
  implication: The bug only affects the 3 fetched demos (the user's "bundled example glycoprotein and membrane protein"). The 6 truly-bundled demos work fine offline.

- timestamp: 2026-08-22T00:08
  checked: to_windows_path() behavior with a ~/.biochemeleon path (demos.py lines 59-78)
  found: to_windows_path only converts paths starting with `/mnt/<letter>/` (WSL mount paths). A home-dir-expanded path (e.g. `C:\Users\<user>\.biochemeleon\cache\...` on Windows, or `/home/<user>/.biochemeleon/...` on Linux) does NOT start with `/mnt/`, so it is returned UNCHANGED. No mangling.
  implication: Using `os.path.expanduser('~/.biochemeleon/')` as the cache/temp base is safe — to_windows_path will not mangle it. On Windows PyMOL (the runtime), expanduser('~') returns the Windows user home, which is always writable.

- timestamp: 2026-08-22T00:09
  checked: pymol/smoke/phase9_smoke.py path dependencies
  found: The smoke test stages INPUT samples at `os.getcwd()/tmp/phase9-demos/` (hardcoded in the smoke, lines 102-103, 237) — NOT via _cache_dir()/temp_download_path(). The cache write/read goes through finalize_large_demo/load_cached_demo/cache_path_for/is_cached (which use _cache_dir()). Smoke asserts only on the cache filename SUFFIX (line 184-185: endswith 'SASDPG4_fit2_model1.pdb.gz'), NOT the directory. Changing _cache_dir() to ~/.biochemeleon/cache/ would still pass the smoke (cache write/read round-trips through the new location; finalize creates the dir via os.makedirs).
  implication: The fix is compatible with the existing smoke test. No smoke test changes needed for correctness (though the smoke's staged input path is independent).

## Resolution

root_cause: Two compounding defects in pymol/biochemeleon/demos.py: (1) `_cache_dir()` and `temp_download_path()` resolved paths relative to the package via `os.path.dirname(__file__)/../tmp/phase9-demos/` — a git-ignored dev-repo-local dir that does NOT exist on a fresh install from the zip (zip has 42 entries, none under tmp/). (2) The download worker `download_large_demo()` called `open(dest_path, 'wb')` WITHOUT first creating the parent directory via `os.makedirs()`. On a fresh machine the parent dir `<install>/../tmp/phase9-demos/` didn't exist, so `open()` raised FileNotFoundError, the worker posted `('error', str(exc))`, and the drain showed "Could not download <id>: ...". This was the explicitly-deferred "Pitfall E / Open Risk 4" now biting v1.

fix: (1) Added `_app_dir()` helper returning `os.path.join(os.path.expanduser('~'), '.biochemeleon')` — a per-user, always-writable, session-persistent dir that works on dev repo AND fresh install (cross-platform: `C:\Users\<user>\.biochemeleon\` on Windows, `/home/<user>/.biochemeleon/` on Linux). (2) `_cache_dir()` now returns `~/.biochemeleon/cache/`; `temp_download_path()` now returns `~/.biochemeleon/tmp/<id>.raw`. (3) Added `os.makedirs(os.path.dirname(dest_path), exist_ok=True)` in `download_large_demo` before `open(dest_path, 'wb')` (inside the try block so failures are caught + reported). `to_windows_path` passes home-expanded paths through unchanged (verified — they don't start with `/mnt/`). Updated stale comments in setup_state.py + test_setup_state.py + planning docs (STACK.md, INTEGRATIONS.md, v1-MILESTONE-AUDIT.md).

verification:
- Syntax gate: `python3.6 -m py_compile pymol/biochemeleon/*.py` — ALL PASSED.
- Pure unit tests: `python3.6 -m unittest tests.test_setup_state` — 125 tests OK (all green).
- Path-construction assertions: all paths under `~/.biochemeleon/`, correct suffixes, `to_windows_path` passthrough confirmed.
- Fresh-computer simulation: set HOME to empty temp dir (no ~/.biochemeleon/), called `temp_download_path` → `~/.biochemeleon/tmp/sasdpg4.raw`, worker's `os.makedirs` created parent, `open(dest_path, 'wb')` succeeded, finalize's `os.makedirs(cache_dir)` + cache write succeeded, `is_cached` returned True. ALL PASSED.
- Pitfall-1 gate: zero matches (clean). exec_ gate: only existing allowed QMessageBox/QDialog calls (no new ones).
- HUMAN-VERIFY NEEDED (cannot run from WSL): actual network fetch (SASBDB/MemProtMD download) + interactive GUI flow (QProgressDialog + QTimer drain) + headless smoke test (phase9_smoke.py needs Windows PyMOL + staged sample). The path-construction + makedirs logic is fully verified; the network + GUI + Qt paths remain a human-verify checkpoint.

files_changed:
- pymol/biochemeleon/demos.py: added _app_dir() helper; _cache_dir() + temp_download_path() relocated to ~/.biochemeleon/; download_large_demo worker adds os.makedirs before open().
- pymol/biochemeleon/setup_state.py: updated stale cache-path comment.
- pymol/tests/test_setup_state.py: updated stale cache-path comment.
- .planning/codebase/STACK.md: updated cache location description.
- .planning/codebase/INTEGRATIONS.md: updated cache + temp download location descriptions.
- .planning/milestones/v1-MILESTONE-AUDIT.md: marked Phase 9 cache path as resolved (was v2 concern).
