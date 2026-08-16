---
phase: 09-large-demo-fetch-source-attribution
plan: 03
status: complete
subsystem: ui
tags: [pymol, qt, qprogressdialog, modeless, qtimer-drain, worker-thread, pitfall-6, memprotmd, sasbdb, ssl-fallback, tier-labels, sc1, sc2, sc4]

# Dependency graph
requires:
  - phase: 09-large-demo-fetch-source-attribution
    plan: 01
    provides: "TIER_LABELS (difficulty -> 'Easy'/'Hard'/'Challenge'/'Very challenging' display labels) + DEMO_MANIFEST (9 entries with source + cache_name fields)"
  - phase: 09-large-demo-fetch-source-attribution
    plan: 02
    provides: "demos.py split API: download_large_demo (worker, urllib-only, Pitfall 6), finalize_large_demo (main, cmd.load + pure strip + .pdb.gz cache), load_cached_demo, is_cached, temp_download_path, cleanup_temp -- the Qt-orchestration targets"
  - phase: 09-research
    provides: "09-RESEARCH-pipeline.md Pattern 1 (modeless QProgressDialog + QTimer drain + worker + finalize skeleton), Pitfall A (.show() NEVER .exec_()), Pitfall 6 (worker cmd-free), Pitfall D (structural ions), Open Risk 3 (re-entrancy: drain owns continuation)"
  - phase: 08-persistence-and-shareable-puzzles
    provides: "PluginDialog._prepare_and_start (Start button handler) + _on_start (tab switch + countdown) -- the 09-03 modeless-fetch orchestration is grafted onto this flow"
provides:
  - "PluginDialog._resolve_large_demo: modeless cancelable QProgressDialog (.show(), NEVER .exec_()) + threading.Thread worker (demos.download_large_demo, urllib-only, Pitfall 6) + recursive QTimer.singleShot drain on the main thread. Drain owns ALL error/cancel UI; _prepare_and_start returns silently on async-in-progress (no double-dialog)."
  - "PluginDialog._continue_after_large_demo_fetch: behavior-preserving extraction of _prepare_and_start's post-target-resolution body (collapse -> hider_specs -> start game) -- shared by the synchronous path (bundled/loaded/cache-hit-fetched) and the async path (drain's 'done' branch with stashed _pending_large_demo_state)."
  - "PluginDialog._update_export_enabled (BTN-05 async guard): disables Export for uncached fetched demos so _on_export can never reach the async continuation (which bakes in Start's tab-switch + countdown). Wired to demo_combo.currentIndexChanged + called after a successful fetch."
  - "_prepare_and_start large-demo branch + _on_start re-entrancy: fetched cache-miss -> stash pending flags + call _resolve_large_demo + return (None,None,[]) silently; _on_start detects async in progress via _pending_large_demo is not None -> just returns (drain owns tab switch + countdown)."
  - "gui_setup.py demo_combo tier-label display via TIER_LABELS (DIFF-05/SC4): 9 demos surface 'Easy'/'Hard'/'Challenge'/'Very challenging' labels."
  - "Two runtime bug fixes applied during the checkpoint by debugger subagents: (a) MemProtMD finalize cmd.load -- format='pdb' to force the PDB reader past the unrecognized .dry extension (d54f22e); (b) SASBDB SSL fallback -- _urlopen_with_ssl_fallback helper retries without cert verification on SSLCertVerificationError (HARICA root CA absent from Windows conda certifi bundle; e0f8302)."
affects: [11-alt-conf-cartoon-hider (membrane-protein duplicate-anchor-id bug discovered during the 09-03 checkpoint -- native alt-confs in 1gzm/3gp6/sasdpg4 cause insert_cartoon_segment_hider AssertionError; documented in .planning/debug/pending/, NOT a Phase 9 issue -- sphere hiders work, Phase 9 SC1 fetch->start flow completes)]

# Tech tracking
tech-stack:
  added: []  # stdlib only (threading, queue, urllib.request, ssl) -- no new libraries; Qt widgets via the existing `from pymol.Qt import QtWidgets` (auto-selects PyQt5/PySide2)
  patterns:
    - "Modeless-cancelable-fetch orchestration: QProgressDialog (.show(), NonModal, setAutoClose(False), setAutoReset(False), setMinimumDuration(500)) + threading.Thread worker (daemon=True, urllib-only, posts to a queue.Queue) + recursive QTimer.singleShot(100, drain) on the main thread. The drain polls the queue non-blocking and dispatches ('progress', pct)/('done',)/('error', msg)/('canceled',)/empty branches. NO cmd.* in the worker (Pitfall 6); finalize (cmd.*) runs on the main thread inside the drain's 'done' branch."
    - "Async-path continuation pattern: the caller (_prepare_and_start) stashes self._pending_large_demo + self._pending_large_demo_state BEFORE showing the progress dialog and returns (None,None,[]) silently. The drain's 'done' branch resumes by calling _continue_after_large_demo_fetch(obj, stashed_state) + the deferred tab-switch/countdown. The drain clears BOTH pending flags on EVERY terminal branch (done/error/canceled)."
    - "BTN-05 async Export guard: disable the Export button for uncached fetched demos (wired to demo_combo.currentIndexChanged + re-evaluated after a successful fetch) so _on_export can never trigger the async continuation. The disable IS the guard -- _on_export itself is unchanged."
    - "SSL fallback for known academic repos: _urlopen_with_ssl_fallback tries the default verifying context first; on URLError wrapping SSLError it retries with check_hostname=False / CERT_NONE. Posts a ('warning', msg) to the progress queue on fallback (the Qt drain silently ignores unknown event kinds). Acceptable tradeoff for downloading public PDB structures from known academic repos (MemProtMD/SASBDB)."
    - "format='pdb' kwarg on cmd.load to override PyMOL's filename_to_format extension dispatch (importing.py:41-101): the MemProtMD strip writes a .dry intermediate whose extension is not a registered PyMOL file type; passing format='pdb' forces read_pdbstr regardless of extension. Fixes both .dry (MemProtMD) and .raw (SASBDB first-fetch) paths via the shared cmd.load in finalize_large_demo."

key-files:
  created:
    - ".planning/debug/resolved/phase9-memprotmd-dry-load-fails.md -- debugger subagent root-cause analysis for the .dry extension bug (d54f22e)"
    - ".planning/debug/resolved/phase9-sasbdb-ssl-cert-verify.md -- debugger subagent root-cause analysis for the HARICA SSL gap (e0f8302)"
    - ".planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md -- Phase 11 follow-up: membrane-protein cartoon-segment hider AssertionError (native alt-confs); discovered during the 09-03 checkpoint, NOT a Phase 9 issue"
  modified:
    - "biochemeleon/__init__.py -- PluginDialog gained _resolve_large_demo (modeless QProgressDialog + QTimer drain + worker + finalize), _continue_after_large_demo_fetch (async continuation), _update_export_enabled (BTN-05 Export async guard), _prepare_and_start large-demo branch (stash pending flags + silent return), _on_start re-entrancy (detect async in progress); +259 / -24 lines"
    - "biochemeleon/gui_setup.py -- demo_combo population maps meta['difficulty'] through TIER_LABELS to the SC4 display labels ('Easy'/'Hard'/'Challenge'/'Very challenging'); .title() fallback for unmapped values; +13 / -3 lines"
    - "biochemeleon/demos.py -- finalize_large_demo cmd.load gained format='pdb' kwarg (d54f22e); new _urlopen_with_ssl_fallback helper + download_large_demo calls it (e0f8302); +101 / -7 lines across the two fixes"
    - "smoke/phase9_smoke.py -- new Section G: MemProtMD finalize round-trip (.raw -> strip -> .dry -> cmd.load(format='pdb') -> object loads with stripped atoms); +110 / -5 lines"

key-decisions:
  - "Drain owns ALL error/cancel UI (QMessageBox.warning on 'error'; silent close on 'canceled'); _prepare_and_start returns (None,None,[]) SILENTLY on async-in-progress so the fetched-demo path NEVER hits the existing 'Demo failed' QMessageBox (avoids double-dialog). The existing 'Demo failed' QMessageBox is ONLY for the bundled-demo None case (file missing on disk)."
  - "Async-path continuation re-entrancy: when _prepare_and_start returns (None,None,[]) due to async fetch in progress, _on_start detects it via `self._pending_large_demo is not None` and just returns -- the drain's 'done' branch owns the tab switch + countdown (the deferred part of _on_start). Real failure (pending is None) keeps the existing QMessageBox behavior. (09-RESEARCH-pipeline.md Open Risk 3 option (b) for v1 simplicity.)"
  - "BTN-05 Export async guard via button disable (NOT a code change to _on_export): the drain's continuation bakes in Start's tab-switch + countdown, so letting Export reach the async path would be a behavioral regression (spurious game-start from Export). Simplest fix is to prevent the click -- disable Export for uncached fetched demos, re-enable after a successful fetch. The disable IS the guard."
  - "QProgressDialog uses .show() with NonModal + setAutoClose(False) + setAutoReset(False) + setMinimumDuration(500). NEVER .exec_() -- Pitfall A (would block the 3D viewer + trip the exec_ grep gate). The recursive QTimer.singleShot(100, drain) keeps the Qt event loop running so the 3D viewer stays smooth during download."
  - "format='pdb' on the shared cmd.load in finalize_large_demo (NOT per-call) -- fixes both .dry (MemProtMD post-strip) and .raw (SASBDB first-fetch) paths. The .dry/.raw files hold plain PDB content; format='pdb' forces read_pdbstr regardless of the unrecognized extension. Canonical PyMOL way (importing.py load() docstring: 'format is provided explicitly' overrides extension dispatch)."
  - "SSL fallback (check_hostname=False / CERT_NONE) is an acceptable tradeoff for downloading public PDB structures from known academic repos (MemProtMD, SASBDB). The HARICA root CA (SASBDB's chain) is absent from the Windows conda certifi 2023.07.22 bundle but present in the WSL system store. The fallback posts a ('warning', msg) to the progress queue so the drain can surface it if desired (currently silently ignored -- safe because the drain only dispatches known event kinds)."

patterns-established:
  - "Modeless fetch orchestration with worker/main split: QProgressDialog (.show()) + threading.Thread worker (urllib-only) + QTimer.singleShot drain (main thread, calls cmd.*). Reusable for any future long-running fetch (Phase 10+ extensions)."
  - "Async-path continuation via stashed state: caller stashes self._pending_<op> + self._pending_<op>_state before showing the dialog and returns silently; the drain's 'done' branch resumes by calling the extracted continuation with the stashed state + the deferred post-ops (tab switch + countdown). Drain clears BOTH pending flags on EVERY terminal branch."
  - "Async Export guard via button disable: when a button's click could trigger an async continuation that bakes in another button's side effects, disable the first button for the uncached/unsafe case + re-enable after the async completes. The disable IS the guard -- no code change to the click handler."

# Metrics
duration: ~2h 45m wall-clock (incl. human-verify checkpoint pause + 2 debugger subagent runs for runtime fixes)
agent_active_time: ~25min (Task 1 + Task 2 + 2 fix commits + final docs commit; rest was checkpoint pause)
completed: 2026-08-16
commits: [5240ff7, 925cb56, d54f22e, e0f8302, cd87355]
files_modified: [biochemeleon/__init__.py, biochemeleon/gui_setup.py, biochemeleon/demos.py, smoke/phase9_smoke.py]
---

# Phase 9 Plan 03: Qt Progress Dialog + Demo Sub-Menu Summary

**Modeless cancelable `QProgressDialog` in `PluginDialog` orchestrating the 09-02 split API (worker download + main-thread finalize + async continuation) for MemProtMD/SASBDB large-demo fetch, plus 4-tier demo sub-menu labels via `TIER_LABELS` (SC4); two runtime fixes (MemProtMD `.dry` extension + SASBDB SSL HARICA gap) applied during the human-verify checkpoint by debugger subagents.**

## Performance

- **Duration:** ~2h 45m wall-clock (incl. human-verify checkpoint pause + 2 debugger subagent runs)
- **Agent active time:** ~25 min (Task 1 + Task 2 + 2 fix commits + final docs commit)
- **Started:** 2026-08-16T17:58:36Z (Task 1 commit `5240ff7`)
- **Completed:** 2026-08-16T20:42:21Z (Phase 11 debug doc commit `cd87355`)
- **Tasks:** 3 (Task 1 `auto`, Task 2 `auto`, Task 3 `checkpoint:human-verify` -- approved after 2 runtime fixes)
- **Files modified:** 4 (`biochemeleon/__init__.py`, `biochemeleon/gui_setup.py`, `biochemeleon/demos.py`, `smoke/phase9_smoke.py`); **Files created:** 3 debug docs

## Accomplishments
- **SC4 (demo sub-menu tier labels):** `gui_setup.py` demo_combo now maps `meta['difficulty']` through `TIER_LABELS` (imported from `setup_state`) to the exact SC4 display labels -- 9 demos surface as 3 "Easy" (1znf/5e54/1k8p), 3 "Hard" (1xdn/2qbz/4wb3), 1 "Challenge" (sasdpg4 -- Glycoprotein), 2 "Very challenging" (1gzm/3gp6 -- Membrane protein). `.title()` fallback handles any unmapped value defensively. The flat QComboBox is kept (9 items < 15-item QTreeWidget threshold).
- **SC1 (modeless cancelable fetch dialog):** `PluginDialog._resolve_large_demo` shows a modeless `QProgressDialog` (`.show()` + `NonModal` + `setAutoClose(False)` + `setAutoReset(False)` + `setMinimumDuration(500)`), spawns `demos.download_large_demo` on a daemon `threading.Thread` (urllib-only, Pitfall 6 compliant), and drains a `queue.Queue` via recursive `QTimer.singleShot(100, drain)` on the main thread. The 3D viewer stays interactive (rotatable) during download. The drain dispatches `('progress', pct)` / `('done',)` / `('error', msg)` / `('canceled',)` / empty branches; on `('done',)` it calls `finalize_large_demo` (main thread, `cmd.*`) + the continuation + tab switch + countdown + re-enables Export. Cancel aborts the worker via a `threading.Event` and cleans the temp file silently.
- **Async-path continuation (behavior-preserving extraction):** `PluginDialog._continue_after_large_demo_fetch(obj, state)` holds the body of `_prepare_and_start` AFTER target resolution (collapse -> hider_specs -> start game) so BOTH the synchronous path (bundled/loaded/cache-hit-fetched -- calls it directly) and the async path (drain's `('done',)` branch -- calls it with the stashed `self._pending_large_demo_state`) share the same continuation. `_prepare_and_start` stashes BOTH `self._pending_large_demo` and `self._pending_large_demo_state` BEFORE calling `_resolve_large_demo` and returns `(None, None, [])` SILENTLY on async-in-progress (the drain owns all error/cancel UI -- no double-dialog). `_on_start` detects async-in-progress via `self._pending_large_demo is not None` and just returns -- the drain's `('done',)` branch owns the tab switch + countdown.
- **BTN-05 Export async guard:** `PluginDialog._update_export_enabled` disables the Export button for uncached fetched demos (wired to `demo_combo.currentIndexChanged` + called after a successful fetch) so `_on_export` can never reach the async continuation (which bakes in Start's tab-switch + countdown). The disable IS the guard -- `_on_export` itself is unchanged. Bundled demos and already-cached fetched demos keep Export enabled.
- **Runtime fix d54f22e (MemProtMD `.dry` extension):** `finalize_large_demo` wrote the stripped MemProtMD file with a `.dry` extension and called `cmd.load` without a `format` kwarg. PyMOL's `filename_to_format` (importing.py:41-101) dispatches by file extension; `.dry` is not a registered format, so `cmd.load` raised `CmdException('unsupported file type: dry')` which the try/except swallowed, returning `None`. The orphaned `.dry` files persisted because `cleanup_temp` is after the failed load. Fix: add `format='pdb'` to the shared `cmd.load` in `finalize_large_demo` -- forces `read_pdbstr` regardless of the `.dry`/`.raw` extension. Fixes both the MemProtMD `.dry` path and the latent SASBDB `.raw` first-fetch path (SASBDB "worked" only via pre-existing `.pdb.gz` cache hits; its first-fetch `.raw` path had the same latent bug).
- **Runtime fix e0f8302 (SASBDB SSL HARICA gap):** SASBDB's cert chain (HARICA RootCA 2015 -> GEANT TLS RSA 1 -> sasbdb.org) verifies from WSL (system store has HARICA) but fails on Windows conda Python 3.9.13 (certifi 2023.07.22 lacks the HARICA root -> `unable to get local issuer certificate`). `download_large_demo` passed no SSL context to `urlopen`, so the default verifying context failed. Fix: new `_urlopen_with_ssl_fallback(url, timeout, progress_queue=None)` helper in `demos.py`. First attempt uses the default verifying context; on `URLError` wrapping `SSLError` it retries with `check_hostname=False` / `CERT_NONE`. Posts a `('warning', msg)` to the progress queue on fallback (the Qt drain silently ignores unknown event kinds -- verified safe). `download_large_demo` now calls the helper inside its existing `try`; non-SSL errors (404/DNS/timeout) still propagate to the outer `except` -> `('error', msg)`.
- **All WSL gates green:** `py_compile` on all 3 modified modules + `smoke/phase9_smoke.py`; 112 existing unit tests pass (no regression); `exec_` gate unchanged at exactly 1 (`gui_game.py:303` QMessageBox -- the QProgressDialog uses `.show()`); Pitfall-1 gate ZERO package-wide; Pitfall 6 static check (`download_large_demo` body has no `cmd.`). Headless smoke `smoke/phase9_smoke.py` 64/64 PASSED (the d54f22e fix added Section G: MemProtMD finalize round-trip `.raw -> strip -> .dry -> cmd.load(format='pdb') -> object loads with stripped atoms` + a bonus real-orphaned-3gp6.raw.dry load).
- **Human-verify checkpoint approved:** user confirmed all 4 Phase 9 success criteria pass in a real Windows PyMOL GUI session -- SC1 (1gzm + 3gp6 download/finalize/load with membrane visible + no water; play/hint/reveal/restart/clean ALL work with sphere hiders; modeless dialog confirmed -- viewer stays interactive during download), SC2 (sasdpg4 downloads with SSL fallback; glycan HETATM visible -- 2601; mixed-rep works), SC4 (9-demo sub-menu with 4 tier labels confirmed). The Phase 11 cartoon-segment hider bug (native alt-confs in membrane proteins) was discovered and documented -- NOT a Phase 9 issue (sphere hiders work; Phase 9 SC1 only requires fetch->start flow completes).

## Task Commits

Each task was committed atomically on `main` (single-plan wave -- no worktree per AGENTS.md):

1. **Task 1 (demo sub-menu tier display via TIER_LABELS -- SC4):** `5240ff7` (`feat`) -- gui_setup.py demo_combo population maps `meta['difficulty']` through `TIER_LABELS` to the SC4 display labels. +13 / -3 lines.
2. **Task 2 (modeless cancelable QProgressDialog -- SC1):** `925cb56` (`feat`) -- PluginDialog gained `_resolve_large_demo` (modeless QProgressDialog + QTimer drain + worker + finalize), `_continue_after_large_demo_fetch` (async continuation), `_update_export_enabled` (BTN-05 Export async guard), `_prepare_and_start` large-demo branch (stash pending flags + silent return), `_on_start` re-entrancy (detect async in progress). +259 / -24 lines. Includes a Rule-2 auto-fix (finalize-None guard in the drain's 'done' branch).
3. **Task 3 (checkpoint:human-verify -- Full fetch UX + visual correctness):** (checkpoint -- no commit). The checkpoint was approved after two runtime fixes were applied by debugger subagents during the pause.

**Runtime fixes applied DURING the checkpoint by debugger subagents (per GSD deviation Rule 1 -- auto-fix bugs immediately):**

4. **MemProtMD finalize load `.dry` extension fix:** `d54f22e` (`fix`) -- added `format='pdb'` to `cmd.load` in `finalize_large_demo` to force the PDB reader past the unrecognized `.dry` extension. +24 / -7 lines in `demos.py` + new Section G (110 lines) in `smoke/phase9_smoke.py` + new `.planning/debug/resolved/phase9-memprotmd-dry-load-fails.md`.
5. **SASBDB SSL fallback (HARICA cert gap):** `e0f8302` (`fix`) -- new `_urlopen_with_ssl_fallback` helper in `demos.py` retries without cert verification on `SSLCertVerificationError`. +77 / -7 lines in `demos.py` + new `.planning/debug/resolved/phase9-sasbdb-ssl-cert-verify.md`.
6. **Phase 11 bug documentation (out-of-scope discovery):** `cd87355` (`docs`) -- `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` (92 lines). The membrane-protein cartoon-segment hider AssertionError (native alt-confs cause duplicate anchor ids in 1gzm/3gp6/sasdpg4) is a Phase 11 issue, NOT a Phase 9 issue -- Phase 9 SC1 only requires the fetch->start flow completes (sphere hiders work).

**Plan metadata:** `docs(09-03): complete qt-progress-dialog-and-demo-sub-menu plan` (this commit).

## Files Created/Modified
- `biochemeleon/__init__.py` -- PluginDialog gained `_resolve_large_demo` (modeless QProgressDialog `.show()` + recursive `QTimer.singleShot(100, drain)` + `threading.Thread` worker + `demos.finalize_large_demo` on main thread), `_continue_after_large_demo_fetch` (behavior-preserving extraction of `_prepare_and_start`'s post-target-resolution body), `_update_export_enabled` (BTN-05 Export async guard), `_prepare_and_start` large-demo branch (stash `self._pending_large_demo` + `self._pending_large_demo_state` + silent return), `_on_start` re-entrancy (detect async in progress via `_pending_large_demo is not None` -> just return). Drain's `('done',)` branch: `finalize_large_demo` + continuation + tab switch + countdown + `_update_export_enabled()` re-enable. Drain's `('error',)`/`('canceled',)` branches: `progress.close()` + `cleanup_temp` + (error only) `QMessageBox.warning` + clear BOTH pending flags. Includes a Rule-2 auto-fix: finalize-None guard in the drain's `('done',)` branch (if `finalize_large_demo` returns None -- `cmd.load` failed -- show a QMessageBox + clear pending flags instead of crashing the continuation). Docstrings in PROSE (no literal `.exec_()` tokens -- grep-gate hygiene). +259 / -24 lines.
- `biochemeleon/gui_setup.py` -- added `TIER_LABELS` to the existing `from .setup_state import (...)` block; demo_combo population now maps `meta['difficulty']` (identifier-safe keys 'easy'/'hard'/'challenge'/'very_challenging') through `TIER_LABELS` to the SC4 display labels ('Easy'/'Hard'/'Challenge'/'Very challenging'). `.title()` fallback for unmapped values. +13 / -3 lines.
- `biochemeleon/demos.py` -- `finalize_large_demo` `cmd.load` gained `format='pdb'` kwarg (d54f22e -- forces `read_pdbstr` past the unrecognized `.dry`/`.raw` extension). New `_urlopen_with_ssl_fallback(url, timeout, progress_queue=None)` helper (e0f8302 -- first attempt default verifying context, retry with `check_hostname=False` / `CERT_NONE` on `URLError` wrapping `SSLError`, post `('warning', msg)` to progress queue on fallback). `download_large_demo` now calls the helper inside its existing `try`. +101 / -7 lines across the two fixes.
- `smoke/phase9_smoke.py` -- new Section G (MemProtMD finalize round-trip): synthetic `.raw -> strip -> .dry -> cmd.load(format='pdb') -> object loads with stripped atoms`. Verifies the `.dry` extension fix (without `format='pdb'`, `cmd.load` raised `CmdException('unsupported file type: dry')`). Bonus: loads the real orphaned `3gp6.raw.dry` (from the failed GUI run) directly with `format='pdb'` to confirm the fix on real data. +110 / -5 lines. Headless run via `cmd.exe /c run-conda-pymol.bat -cq`: 64/64 PASSED, exit 0.
- `.planning/debug/resolved/phase9-memprotmd-dry-load-fails.md` (NEW, 59 lines) -- debugger subagent root-cause analysis for the `.dry` extension bug (d54f22e).
- `.planning/debug/resolved/phase9-sasbdb-ssl-cert-verify.md` (NEW, 55 lines) -- debugger subagent root-cause analysis for the HARICA SSL gap (e0f8302).
- `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` (NEW, 92 lines) -- Phase 11 follow-up: membrane-protein cartoon-segment hider AssertionError (native alt-confs cause duplicate anchor ids in 1gzm/3gp6/sasdpg4). Discovered during the 09-03 checkpoint, NOT a Phase 9 issue -- sphere hiders work; Phase 9 SC1 only requires fetch->start flow completes.

## Decisions Made
- **Drain owns ALL error/cancel UI; caller returns silently on async-in-progress** (no double-dialog). The existing "Demo failed" QMessageBox in `_prepare_and_start` is ONLY for the bundled-demo None case (file missing on disk); the fetched-demo async path bypasses it (returns silently before reaching it). The drain surfaces fetch errors via its own `QMessageBox.warning` on the `('error',)` branch and closes silently on `('canceled',)`.
- **Async-path continuation via stashed state** (09-RESEARCH-pipeline.md Open Risk 3 option (b) for v1 simplicity). `_prepare_and_start` stashes `self._pending_large_demo` + `self._pending_large_demo_state` BEFORE showing the progress dialog and returns `(None,None,[])` silently. The drain's `('done',)` branch resumes by calling `_continue_after_large_demo_fetch(obj, stashed_state)` + the deferred tab-switch/countdown (which live in `_on_start`, not `_prepare_and_start`, so the drain must add them explicitly). The drain clears BOTH pending flags on EVERY terminal branch (done/error/canceled).
- **BTN-05 Export async guard via button disable** (NOT a code change to `_on_export`). The drain's continuation bakes in Start's tab-switch + countdown, so letting Export reach the async path would be a behavioral regression (spurious game-start from Export). Simplest fix: disable Export for uncached fetched demos + re-enable after a successful fetch (wired to `demo_combo.currentIndexChanged` + called by the drain's `('done',)` branch). The disable IS the guard -- `_on_export` itself is unchanged.
- **QProgressDialog uses `.show()` + `NonModal` + `setAutoClose(False)` + `setAutoReset(False)` + `setMinimumDuration(500)` -- NEVER `.exec_()`** (Pitfall A, 09-RESEARCH-pipeline.md:190-195). The recursive `QTimer.singleShot(100, drain)` keeps the Qt event loop running so the 3D viewer stays smooth during download. `setAutoClose(False)` + `setAutoReset(False)` prevent the dialog from auto-hiding mid-pipeline (09-RESEARCH-pipeline.md:333) -- the drain closes it explicitly on terminal branches.
- **`format='pdb'` on the SHARED `cmd.load` in `finalize_large_demo`** (NOT per-call). The MemProtMD strip writes a `.dry` intermediate; the SASBDB first-fetch writes a `.raw` intermediate. Both extensions are not registered PyMOL file types, so `cmd.load` raised `CmdException('unsupported file type: dry'/'raw')` which the try/except swallowed. `format='pdb'` forces `read_pdbstr` regardless of extension (canonical PyMOL way -- importing.py `load()` docstring: "format is provided explicitly" overrides extension dispatch). One fix covers both paths.
- **SSL fallback (check_hostname=False / CERT_NONE) is an acceptable tradeoff** for downloading public PDB structures from known academic repos (MemProtMD, SASBDB). The HARICA root CA (SASBDB's chain) is absent from the Windows conda certifi 2023.07.22 bundle but present in the WSL system store -- a Windows-only gap. The fallback posts a `('warning', msg)` to the progress queue so the drain can surface it if desired (currently silently ignored -- safe because the drain only dispatches known event kinds). Non-SSL errors (404/DNS/timeout) still propagate to the outer `except` -> `('error', msg)` -> `QMessageBox.warning`.
- **Drain's `('done',)` branch finalize-None guard** (Rule-2 auto-fix, committed in 925cb56). If `finalize_large_demo` returns None (`cmd.load` failed -- e.g. the `.dry` extension bug before d54f22e), show a `QMessageBox` + clear pending flags instead of crashing the continuation (`_continue_after_large_demo_fetch(None, state)` would dereference None). This guard is what surfaced the `.dry` extension bug as a clear "Load failed" message instead of a stack trace during the checkpoint.

## Deviations from Plan

4 deviations (1 Rule-2 auto-fix in Task 2, 2 Rule-1 bug fixes applied by debugger subagents during the checkpoint, 1 out-of-scope Phase 11 discovery). All are documented below.

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added finalize-None guard in the drain's `('done',)` branch**
- **Found during:** Task 2 (modeless QProgressDialog orchestration)
- **Issue:** The plan's drain `('done',)` branch calls `_continue_after_large_demo_fetch(obj, state)` immediately after `finalize_large_demo`. If `finalize_large_demo` returns None (`cmd.load` failed -- e.g. the `.dry` extension bug discovered later), the continuation would dereference None (collapse_to_single_state(None), etc.) and crash the drain with a stack trace instead of a user-readable error.
- **Fix:** Added a guard in the drain's `('done',)` branch: if `finalize_large_demo` returns None, show a `QMessageBox.warning(self.window(), "Load failed", ...)` + clear BOTH pending flags + return (do NOT call the continuation). The guard is what surfaced the `.dry` extension bug as a clear "Load failed" message during the checkpoint (instead of a stack trace) -- which let the debugger subagent diagnose and fix it (d54f22e).
- **Files modified:** `biochemeleon/__init__.py`
- **Verification:** The guard is exercised (in reverse) by the d54f22e fix -- before the fix, `finalize_large_demo` returned None for MemProtMD and the guard showed "Load failed" instead of crashing; after the fix, `finalize_large_demo` returns the obj name and the guard is a no-op. The headless smoke Section G verifies the post-fix path (obj loads with stripped atoms).
- **Committed in:** `925cb56` (Task 2 commit)

**2. [Rule 1 - Bug] MemProtMD finalize load `.dry` extension -- added `format='pdb'` to `cmd.load`**
- **Found during:** Task 3 (checkpoint:human-verify -- the user's first 1gzm/3gp6 attempts hit "Load failed" instead of loading the membrane)
- **Issue:** `finalize_large_demo` writes the stripped MemProtMD file with a `.dry` extension and called `cmd.load` without a `format` kwarg. PyMOL's `filename_to_format` (importing.py:41-101) dispatches by file extension; `.dry` is not a registered format (not in `loadfunctions`, no molfile plugin), so `cmd.load` raised `CmdException('unsupported file type: dry')` which the try/except swallowed, returning None. The orphaned `.dry` files persisted because `cleanup_temp` is after the failed load. SASBDB "worked" only via a pre-existing `.pdb.gz` cache hit; its first-fetch `.raw` path had the same latent extension bug.
- **Fix:** Added `format='pdb'` to the shared `cmd.load` in `finalize_large_demo` -- forces `read_pdbstr` regardless of the `.dry`/`.raw` extension (the canonical PyMOL way; importing.py `load()` docstring: "format is provided explicitly" overrides extension dispatch). Both `.dry` and `.raw` hold plain PDB content. One fix covers both paths.
- **Files modified:** `biochemeleon/demos.py` (1 line: added `format='pdb'` kwarg to the shared `cmd.load`); `smoke/phase9_smoke.py` (new Section G: MemProtMD finalize round-trip + bonus real-orphaned-3gp6.raw.dry load); `.planning/debug/resolved/phase9-memprotmd-dry-load-fails.md` (NEW -- root-cause analysis)
- **Verification:** User confirmed in the checkpoint: "1gzm + 3gp6 download, finalize, load (with membrane visible, no water), play, hint, reveal, restart, clean ALL working with sphere hiders. The `.dry` extension bug is fixed (format='pdb')." Headless smoke `smoke/phase9_smoke.py` Section G: 64/64 PASSED (MemProtMD finalize round-trip loads with stripped atoms).
- **Committed in:** `d54f22e` (applied by debugger subagent during the checkpoint pause)

**3. [Rule 1 - Bug] SASBDB SSL HARICA cert gap -- added `_urlopen_with_ssl_fallback` helper**
- **Found during:** Task 3 (checkpoint:human-verify -- the user's first sasdpg4 attempt hit a `URLError` wrapping `SSLCertVerificationError` on Windows conda Python 3.9.13)
- **Issue:** SASBDB's cert chain (HARICA RootCA 2015 -> GEANT TLS RSA 1 -> sasbdb.org) verifies from WSL (system store has HARICA) but fails on Windows conda Python 3.9.13 (certifi 2023.07.22 lacks the HARICA root -> `unable to get local issuer certificate`). `download_large_demo` passed no SSL context to `urlopen`, so the default verifying context (certifi-backed) failed. MemProtMD worked because its root CA is in certifi.
- **Fix:** New `_urlopen_with_ssl_fallback(url, timeout, progress_queue=None)` helper in `demos.py`. First attempt uses the default verifying context; on `URLError` wrapping `SSLError` it retries with `check_hostname=False` / `CERT_NONE`. Posts a `('warning', msg)` to the progress queue on fallback (the Qt drain silently ignores unknown event kinds -- verified safe). `download_large_demo` now calls the helper inside its existing `try`; non-SSL errors (404/DNS/timeout) still propagate to the outer `except` -> `('error', msg)`. Key implementation detail (corrected from the fix spec): `urlopen` does NOT raise a bare `ssl.SSLError` for a cert-verification failure -- it wraps it as `urllib.error.URLError(reason=SSLCertVerificationError(...))`. So `except URLError as e: if isinstance(e.reason, ssl.SSLError):` is the correct check.
- **Files modified:** `biochemeleon/demos.py` (new `_urlopen_with_ssl_fallback` helper + `download_large_demo` calls it); `.planning/debug/resolved/phase9-sasbdb-ssl-cert-verify.md` (NEW -- root-cause analysis)
- **Verification:** User confirmed in the checkpoint: "sasdpg4 downloads (SSL fallback works -- HARICA cert gap handled), glycan HETATM visible (2601), mixed-rep works ('glycoprotein now working from download, and mixed representation working well')."
- **Committed in:** `e0f8302` (applied by debugger subagent during the checkpoint pause)

**4. [Out-of-scope discovery -- NOT a Phase 9 issue] Phase 11: membrane-protein cartoon-segment hider duplicate anchor id**
- **Found during:** Task 3 (checkpoint:human-verify -- the user's 1gzm/3gp6 attempts with non-sphere hiders hit `AssertionError: expected 1 anchor id, got [25, 25]` / `[24, 24]` / `[25, 25, 19]`)
- **Issue:** Native alternate conformations (alt-confs) in membrane proteins (1gzm, 3gp6) -- and also in the SASBDB glycoprotein sasdpg4 -- match the cartoon-segment anchor selection multiple times, so `insert_cartoon_segment_hider` receives `[25, 25]` instead of `[25]` and fails its `assert len(ids) == 1`. This blocks mixed-rep (cartoon/ribbon) hiders on these demos; sphere hiders work fine.
- **Why this is NOT a Phase 9 issue:** Phase 9 SC1 only requires the fetch->start flow completes ("basic sanity -- the full game loop is Phase 4's job; here just confirm the fetch->start flow completes"). The fetch, finalize, load, and start ALL complete successfully with sphere hiders. The cartoon-segment hider is a Phase 5 generator (line/stick/cartoon) -- its alt-conf handling is a Phase 11 (alt-conf cartoon/ribbon hider) concern.
- **Fix:** Documented in `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` (92 lines) for Phase 11 follow-up. Includes reproduction, exact error messages, stack trace, root-cause hypothesis (native alt-confs match the segment selection multiple times), and candidate fixes (filter to altloc='A' in the anchor selection; or relax the assertion to take the first id).
- **Files modified:** `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` (NEW)
- **Verification:** N/A (out of scope -- documented for Phase 11)
- **Committed in:** `cd87355` (docs)

---

**Total deviations:** 4 (1 Rule-2 missing-critical auto-fix in Task 2; 2 Rule-1 bug fixes applied by debugger subagents during the checkpoint pause; 1 out-of-scope Phase 11 discovery documented for follow-up).
**Impact on plan:** All 3 fixes necessary for correct operation (the plan's SC1/SC2 human-verify would have failed without the two Rule-1 bug fixes; the Rule-2 guard is what surfaced them as readable errors). No scope creep -- all fixes are on the 09-03 modified files (`biochemeleon/demos.py` is a 09-02 file but the fixes are for 09-03's `finalize_large_demo`/`download_large_demo` paths that 09-03's Qt orchestration drives; the 09-02 smoke could not have caught them because it uses a staged `.pdb` sample, not a real `.dry`/`.raw` fetch). The Phase 11 discovery is correctly scoped out (documented, not fixed).

## Issues Encountered
- **Two runtime bugs surfaced only at the GUI human-verify checkpoint** (the `.dry` extension dispatch failure and the SASBDB SSL HARICA gap). Both are Windows/real-network-only -- the 09-02 headless smoke used a staged `.pdb` sample (no real `.dry`/`.raw` fetch) and WSL's system cert store (HARICA present), so neither could have been caught earlier. Both were fixed by debugger subagents during the checkpoint pause (per GSD deviation Rule 1 -- auto-fix bugs immediately) and re-verified by the user before approval. The Rule-2 finalize-None guard (committed in Task 2, 925cb56) is what surfaced the `.dry` bug as a readable "Load failed" message instead of a stack trace -- which made the diagnosis tractable.
- **Phase 11 bug discovered (out of scope).** The membrane-protein cartoon-segment hider AssertionError (native alt-confs cause duplicate anchor ids in 1gzm/3gp6/sasdpg4) is a Phase 11 (alt-conf cartoon/ribbon hider) issue, NOT a Phase 9 issue. Phase 9 SC1 only requires the fetch->start flow completes (sphere hiders work). Documented in `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` for Phase 11 follow-up.

## Authentication Gates
None. The MemProtMD and SASBDB fetches are unauthenticated public PDB downloads (the SASBDB SSL fallback is a cert-bundle gap, not an auth gate -- it's handled transparently by `_urlopen_with_ssl_fallback`).

## User Setup Required
None for 09-03. The plugin fetches from public PDB repos (MemProtMD, SASBDB) with no API keys or auth. The SSL fallback is automatic (transparent to the user). The `.pdb.gz` cache lives in `tmp/phase9-demos/cache/` (repo-relative, gitignored) -- no setup needed for v1 (run-from-repo per AGENTS.md).

## Next Phase Readiness
**Phase 9 complete (09-01 + 09-02 + 09-03 + 09-04 all done).** All 4 Phase 9 success criteria pass:
- SC1: large membrane demos (1gzm, 3gp6) fetch on demand with full membrane, stripped of water/salt, compressed+cached, with a modeless cancelable progress dialog (viewer stays interactive). ✓
- SC2: glycoprotein demo (sasdpg4) fetches from SASBDB on demand, glycan visible (2601 HETATM), source+IDs cited (DATA_SOURCES.md from 09-04). ✓
- SC4: demo sub-menu surfaces 4-tier difficulty metadata (Easy/Hard/Challenge/Very challenging). ✓
- All grep gates green; no regression in existing tests (112 pass). ✓

**Phase 11 follow-up (out of scope, documented):**
- `.planning/debug/pending/phase11-membrane-altconf-duplicate-anchor-id.md` -- membrane-protein cartoon-segment hider duplicate anchor id (native alt-confs). Sphere hiders work on all demos; mixed-rep with cartoon/ribbon blocks on 1gzm/3gp6/sasdpg4. Candidate fixes: filter to altloc='A' in the anchor selection; or relax the assertion to take the first id. This is a Phase 11 (alt-conf cartoon/ribbon hider) concern.

**Concerns:**
- The `.pdb.gz` cache lives in `tmp/phase9-demos/cache/` (repo-relative, gitignored). For an installed plugin (v2), this path won't exist -- Pitfall E (09-RESEARCH-pipeline.md:215-219). Out of scope for v1 (run-from-repo per AGENTS.md).
- The SSL fallback (`check_hostname=False` / `CERT_NONE`) is an acceptable tradeoff for downloading public PDB structures from known academic repos, but it's a security gap in principle. A future hardening pass could bundle the HARICA root CA (or use `certifi.where()` + a supplemental CA bundle). Out of scope for v1.
- The 60s urllib timeout in `download_large_demo` may be tight for slow connections to MemProtMD (7.5-9.3MB wet files). The `('error', msg)` queue event handles it gracefully (shows a QMessageBox). A future pass could make the timeout configurable. Out of scope for v1.

---
*Phase: 09-large-demo-fetch-source-attribution*
*Completed: 2026-08-16*
