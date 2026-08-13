# Phase 9 Research — Fetch Pipeline UX, Threading, Cache, Manifest Tiering, DATA_SOURCES.md

**Researched:** 2026-08-14
**Domain:** PyMOL 2.5.0 plugin — on-demand large-demo fetch (MemProtMD/SASBDB), modeless cancelable Qt progress dialog, threading model (Pitfall 6), .pdb.gz cache, DEMO_MANIFEST schema extension + difficulty tiers (DIFF-05), demo sub-menu display, DATA_SOURCES.md consolidation (DEMO-04)
**Confidence:** HIGH (core mechanics verified against PyMOL 2.5.0 source + Qt 5.15 official docs; MemProtMD/SASBDB URLs left to the dedicated researchers)

## Summary

Phase 9 rounds out the demo set with three large fetched molecules (1GZM + 3GP6 membrane proteins from MemProtMD; one glycoprotein from SASBDB), strips water and salt, compresses to a `.pdb.gz` cache, surfaces a 4-tier difficulty label in the demo sub-menu (DIFF-05), and consolidates every source into a repo-root `DATA_SOURCES.md` (DEMO-04). The fetch is triggered when the user clicks **Start** with a large demo selected (the existing trigger point in `PluginDialog._prepare_and_start`, `__init__.py:140-146`), and shows a **modeless, cancelable `QProgressDialog`** while a worker thread downloads via `urllib`.

The technical pattern is settled at HIGH confidence from four converging sources: (1) **PyMOL 2.5.0 source** (`tmp/pymol-src/modules/pymol/`) — `internal.py:278-308` `file_read()` detects the gzip magic number `\x1f\x8b` and decompresses transparently, so `cmd.load("foo.pdb.gz")` works; `exporting.py:859-914` + `:986-989` show `cmd.save("foo.pdb.gz", obj)` writes gzipped PDB in one step (the `'pdb'` savefunction is `get_str`, which returns a string → the `zipped == 'gz'` branch opens `gzip.open`); `cmd.py:362-365` + `preset.py:24-27` confirm `solvent` and `inorganic` are built-in selector keywords (canonical PyMOL: `wat_sele = "solvent"`, `ion_sele = "(resn CA,HG,K,NA,ZN,MG,CL)"`). (2) **Qt 5.15 official docs** (`doc.qt.io/qt-5/qprogressdialog.html`) — the modeless pattern is literally the documented example: `QTimer` + a separate worker + the `canceled()` signal connected to a cancel slot; `autoClose`/`autoReset` default to `True`; `setRange(0,0)` is the busy-indicator idiom; `setValue()` calls `processEvents()` ONLY in modal mode (modeless needs the QTimer). (3) **`PITFALLS.md` Pitfall 6** (`:160-180`) — the golden rule "all `cmd.*` calls happen on the GUI main thread"; worker computes/posts to a `queue.Queue`; main thread polls with `QTimer.singleShot(0, drain)` and performs the `cmd.*` calls. (4) **Reference plugins** — `Pymol-script-repo/plugins/vina.py:30,140` uses `from urllib.request import urlretrieve; urlretrieve(url, dest)` (the canonical download pattern); `vina.py:202,806` uses `Qt.QtWidgets.QProgressBar` via `pymol.Qt` (same `QtWidgets` namespace as `QProgressDialog`, confirming accessibility); `mtsslDockGui.py:646` uses `threading.Thread(target=...)` (the ecosystem threading pattern, with the Pitfall 6 caveat).

**Primary recommendation:** Add a **split API** to `demos.py` (Qt-free): `download_large_demo(demo_id, dest, progress_queue, cancel_event)` (worker thread, `urllib` only, NO `cmd.*`) + `finalize_large_demo(demo_id, downloaded_path)` (main thread, `cmd.load` + strip + `cmd.save` cache) + `load_cached_demo(demo_id)` (main thread, cache-hit `cmd.load`). The Qt orchestration (the `QProgressDialog` + `QTimer` drain + `processEvents`) lives in `__init__.py`'s `PluginDialog._prepare_and_start` (or a new `_resolve_large_demo` helper), NOT in `demos.py` — because the drain loop needs `processEvents`/`QTimer` (Qt) and `demos.py` must stay Qt-free. Use `.pdb.gz` for the cache (PyMOL reads AND writes it natively — no stdlib `gzip` step needed). Strip with `cmd.remove(f"{obj} and solvent") + cmd.remove(f"{obj} and inorganic")` (defensive no-op on the MemProtMD "_dry" variant). Cache at `tmp/phase9-demos/cache/{cache_name}` (already gitignored — `git check-ignore tmp/phase9-demos` returns exit 0; no `.gitignore` change needed). Extend `DEMO_MANIFEST` with `source`/`source_id`/`fetch_url`/`cache_name`/`citation`/`strip` fields and the 4-tier `difficulty` vocabulary `easy`/`hard`/`challenge`/`very_challenging` (display via a `TIER_LABELS` map: "Easy"/"Hard"/"Challenge"/"Very challenging"). Keep the flat `QComboBox` (9 items < the 15-item QTreeWidget threshold from Phase 2 research). The dialog uses `.show()` (modeless) — NEVER `.exec_()` (it would trip the exec_ grep gate, which currently allows `exec_` only on `QFileDialog`/`QMessageBox`).

## Standard Stack

The established libraries/tools for this domain — all already available, NO new dependencies (per AGENTS.md: assume only what `pymol-open-source` ships):

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `pymol.Qt.QtWidgets.QProgressDialog` | Qt 5.15 (PyMOL 2.5.0 ships PyQt5) | Modeless cancelable progress dialog | Official Qt5 docs; `pymol.Qt` exports the full `QtWidgets` namespace (`Qt/__init__.py` does `from PyQt5 import ... QtWidgets`); prior art `vina.py:202` confirms `Qt.QtWidgets.QProgressBar` accessible via `pymol.Qt` (same namespace) |
| `urllib.request` (stdlib) | Python 3.6+ | HTTP download to temp file (worker thread) | Stdlib (no approval needed per SUMMARY.md:31); canonical pattern `vina.py:30,140` `urlretrieve(url, dest)`; `castp.py:127` |
| `threading` (stdlib) | Python 3.6+ | Worker thread for the download (urllib only, NO `cmd.*`) | Stdlib; ecosystem pattern `mtsslDockGui.py:646`, `tmalign.py:63`; Pitfall 6 compliant IF worker does no `cmd.*` |
| `queue.Queue` (stdlib) | Python 3.6+ | Worker→main progress marshalling | Stdlib; Pitfall 6 recommendation (`PITFALLS.md:171`) |
| `threading.Event` (stdlib) | Python 3.6+ | Cancel flag (worker checks between read blocks) | Stdlib; clean cooperative cancellation |
| `pymol.cmd.load` / `cmd.save` / `cmd.remove` | PyMOL 2.5.0 | Load `.pdb.gz`, save stripped `.pdb.gz`, strip solvent/ions | Verified in PyMOL source (see Strip+Compress section) |
| `os` / `gzip` (stdlib) | Python 3.6+ | Path resolution, temp-file cleanup | `gzip` NOT needed for the cache (cmd.save writes `.pdb.gz` directly) but may be used for temp handling |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `QtCore.QTimer` | Qt 5.15 | Main-thread drain of the progress queue | Modeless dialog updates; `gui_game.py:84-87` is the project's existing QTimer pattern |
| `QtCore.QApplication.processEvents` | Qt 5.15 | Force a repaint between blocking `cmd.*` steps | After `setLabelText`/`setValue`, BEFORE a blocking `cmd.load`/`cmd.save` (so the label paints before the main thread blocks) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `QProgressDialog` (modeless `.show()`) | `QProgressDialog` (modal `.exec_()`) | Modal trips the exec_ grep gate + blocks the 3D viewer (violates SC1 "rotate/zoom while fetch runs"). REJECTED. |
| `QProgressDialog` | `QProgressBar` in a status bar | More invasive (needs a status bar); `vina.py:806` uses a bare `QProgressBar` but we want a labeled cancelable dialog. `QProgressDialog` is the documented fit. |
| Worker-thread download + QTimer drain | `urlretrieve(url, dest, reporthook)` with `processEvents()` inside the reporthook (main-thread download) | Simpler (no thread), but the main thread is blocked inside `urlretrieve`'s socket reads between reporthook calls → the 3D viewer is choppy, not smooth. The worker-thread approach keeps the main thread fully free during download (smooth 3D). KEEP worker-thread as primary; the reporthook approach is a documented fallback (LOW priority). |
| `.pdb.gz` cache | `.zip` cache | `.zip` is NOT read by `cmd.load` (`file_read` only detects gzip/bzip2 magic — `internal.py:299-306`; no zip support). Would need a manual `zipfile` extract step before `cmd.load`. `.pdb.gz` is read AND written natively → strictly better. |
| `tmp/phase9-demos/cache/` | `biochemeleon/data/demos/cache/` | ARCHITECTURE.md:126 originally proposed `data/cache/`, but the user directive stages fetched data under `./tmp/` (repo-local, git-ignored). `tmp/` is already gitignored (`.gitignore` line `tmp`); `data/cache/` would need a new `.gitignore` entry. Use `tmp/phase9-demos/cache/` per the user directive. |

**Installation:** NONE. All libs ship with PyMOL 2.5.0 (`pymol.Qt`, `pymol.cmd`) or are Python stdlib (`urllib`, `threading`, `queue`, `os`, `gzip`). No `pip`/`apt`/`conda` (per AGENTS.md).

## Architecture Patterns

### Recommended additions (dependency direction is STRICT — `AGENTS.md`)
```
setup_state.py   (PURE: stdlib only — DEMO_MANIFEST EXTENDED here + TIER_LABELS + tier vocabulary)
      ↑
demos.py         (cmd bridge: EXTENDS with download_large_demo/finalize_large_demo/load_cached_demo/cache_path_for; urllib+threading+queue — NO Qt)
      ↑
__init__.py      (Qt + cmd: PluginDialog._prepare_and_start EXTENDS to orchestrate the QProgressDialog + QTimer drain for large demos)
```
- `DEMO_MANIFEST` and `TIER_LABELS` live in `setup_state.py` (the pure layer) — same place they live now (`setup_state.py:29-36`).
- The fetch/strip/compress/cache `cmd.*` logic lives in `demos.py` (cmd-coupled, NO Qt — preserves the existing `demos.py` purity).
- The `QProgressDialog` + `QTimer` drain + `processEvents` lives in `__init__.py` (`PluginDialog`), which already imports `from pymol.Qt import ... QtWidgets` (`__init__.py:35`).
- **`demos.py` must NOT import `pymol.Qt` or call `processEvents`.** The worker thread (`download_large_demo`) uses only `urllib`/`threading`/`queue`/`os` (stdlib). The main-thread functions (`finalize_large_demo`, `load_cached_demo`) use `cmd.*` only.

### Pattern 1: Modeless cancelable QProgressDialog (the documented Qt pattern)
**What:** A `QProgressDialog` shown with `.show()` (NOT `.exec_()`), updated by a `QTimer` on the main thread, with a worker thread doing the slow download and posting progress to a `queue.Queue`. The `canceled()` signal (or `wasCanceled()` polled in the drain) sets a `threading.Event` that the worker checks between read blocks.
**When to use:** Any fetch that takes >~500ms and must not freeze the PyMOL 3D viewer (SC1).
**Source:** Qt 5.15 docs (`doc.qt.io/qt-5/qprogressdialog.html`) — the modeless example uses exactly `QTimer` + a worker + `connect(pd, canceled, this, cancel)`. Confirmed HIGH confidence.

```python
# Source: Qt 5.15 official docs (modeless example) + PITFALLS.md Pitfall 6 (:160-180) +
#         project QTimer pattern (gui_game.py:84-87). Lives in __init__.py PluginDialog.

import threading, queue, os, tempfile
from pymol.Qt import QtCore, QtWidgets
from . import demos

def _resolve_large_demo(self, demo_id):
    """Orchestrate cache-hit or fetch+progress for a large (fetched) demo.
    Called from _prepare_and_start when mode=='demo' and the manifest
    entry's source != 'bundled'. Returns obj_name or None (after a QMessageBox
    on failure). Runs entirely on the main thread EXCEPT the urllib download.
    """
    # 1. Cache hit? (synchronous, no dialog)
    obj = demos.load_cached_demo(demo_id)
    if obj is not None:
        return obj  # cache hit — already loaded + (pre-stripped)

    # 2. Cache miss — show modeless cancelable progress dialog
    meta = demos.DEMO_MANIFEST[demo_id]
    progress = QtWidgets.QProgressDialog(
        "Downloading %s…" % demo_id, "Cancel", 0, 100, self.window())
    progress.setWindowModality(QtCore.Qt.NonModal)   # MODELESS (not .exec_)
    progress.setAutoClose(False)   # we close manually (autoClose default True would
    progress.setAutoReset(False)   #   hide the dialog when setValue hits max mid-pipeline)
    progress.setMinimumDuration(500)  # show after 500ms (avoid flicker on instant hits)
    progress.setValue(0)
    progress.show()                 # <-- .show(), NEVER .exec_() (grep gate)

    q = queue.Queue()
    cancel = threading.Event()
    progress.canceled.connect(cancel.set)   # Cancel button -> set the Event

    # 3. Spawn the urllib worker (NO cmd.* in the worker — Pitfall 6)
    tmp_path = demos.temp_download_path(demo_id)
    worker = threading.Thread(
        target=demos.download_large_demo,
        args=(demo_id, tmp_path, q, cancel), daemon=True)
    worker.start()

    # 4. Main-thread drain via QTimer (recursive singleShot — matches Pitfall 6 wording)
    def drain():
        # (a) drain any queued progress events (non-blocking)
        made_progress = False
        while True:
            try:
                ev = q.get_nowait()
            except queue.Empty:
                break
            kind = ev[0]
            if kind == 'progress':
                progress.setRange(0, 100)
                progress.setValue(ev[1])
                progress.setLabelText("Downloading %s…  (%d%%)" % (demo_id, ev[1]))
                made_progress = True
            elif kind == 'done':
                # Download finished — finalize on the MAIN thread (cmd.* here).
                progress.setLabelText("Loading + stripping %s…" % demo_id)
                progress.setRange(0, 0)            # indeterminate busy indicator
                progress.setValue(0)              # (setValue needed to repaint label)
                QtWidgets.QApplication.processEvents()  # paint before blocking cmd.*
                obj = demos.finalize_large_demo(demo_id, tmp_path)  # cmd.load+strip+save
                demos.cleanup_temp(tmp_path)
                progress.close()
                self._on_large_demo_done(demo_id, obj)  # refresh combo / show error
                return
            elif kind == 'error':
                progress.close()
                demos.cleanup_temp(tmp_path)
                QtWidgets.QMessageBox.warning(
                    self.window(), "Fetch failed",
                    "Could not download %s:\n%s" % (demo_id, ev[1]))
                return
            elif kind == 'canceled':
                progress.close()
                demos.cleanup_temp(tmp_path)
                return
        # (b) if the user clicked Cancel (no 'canceled' event yet but flag set)
        if cancel.is_set() and not worker.is_alive():
            progress.close()
            demos.cleanup_temp(tmp_path)
            return
        # (c) keep polling
        QtCore.QTimer.singleShot(100, drain)

    QtCore.QTimer.singleShot(100, drain)
    return None  # async — _on_large_demo_done handles the result
```

### Pattern 2: Pitfall 6 compliance — what runs where
| Step | Thread | API used | Allowed? |
|------|--------|----------|----------|
| urllib HTTP download → temp file | **worker** (`threading.Thread`) | `urllib.request.urlopen` + `resp.read(block)` in a loop; check `cancel_event` between blocks; post `('progress', pct)` / `('done',)` / `('error', msg)` to `queue.Queue` | ✅ stdlib only, NO `cmd.*` |
| `cmd.load(temp, object=did)` | **main** (in the `drain()` 'done' branch) | `cmd.load` | ✅ main thread |
| `cmd.remove(f"{obj} and solvent")` + `cmd.remove(f"{obj} and inorganic")` | **main** | `cmd.remove` | ✅ main thread |
| `cmd.save(cache + ".pdb.gz", obj)` | **main** | `cmd.save` (writes gzipped PDB in one step) | ✅ main thread |
| cache file `os.makedirs` / `os.path.exists` | **main** (or pure helper) | `os` | ✅ either |
| `QProgressDialog.setValue`/`setLabelText`/`setRange`/`close` | **main** (in `drain()`) | `pymol.Qt.QtWidgets` | ✅ main thread (Qt widgets must be touched on the main thread — implicit, but Qt requires it) |

**Anti-Patterns to Avoid (Pitfall 6):**
- **`cmd.*` in the worker thread** → deadlocks/segfaults (Pitfall 6). The worker does ONLY `urllib` + `queue` + `os` (temp file write). It must NOT import `pymol` or call `cmd.*`.
- **`QProgressDialog` touched from the worker** → Qt widgets are not thread-safe. The worker posts to the queue; the main-thread `drain()` touches the dialog.
- **`processEvents()` inside `demos.py`** → that's a Qt import in the cmd module (violates dependency direction). `processEvents` is called in `__init__.py`'s `drain()`, not in `demos.py`.
- **`.exec_()` on the progress dialog** → trips the exec_ grep gate (see grep-gate section) AND blocks the 3D viewer (violates SC1).

## Don't Hand-Roll

Problems that look simple but have existing (verified) solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|------------|-----|
| gzip decompression for `.pdb.gz` load | manual `gzip.open` + write temp `.pdb` + `cmd.load` | `cmd.load("foo.pdb.gz")` directly | `internal.py:278-308` `file_read()` detects the gzip magic `\x1f\x8b` and decompresses transparently. Re-implementing gains nothing. |
| gzip compression for the cache | manual `gzip.open(cache+'.gz','wb').write(cmd.get_pdbstr(...))` | `cmd.save("cache.pdb.gz", obj)` | `exporting.py:859-914` + `:986-989`: the `'pdb'` savefunction (`get_str`) returns a string, and the `zipped == 'gz'` branch opens `gzip.open` for you. One call. |
| water/salt detection | enumerate `resn HOH`/`resn SOL`/ion names manually | `solvent` + `inorganic` selectors | `cmd.py:362-365` confirms these are built-in keywords; `preset.py:25-27` is PyMOL's own canonical usage (`wat_sele="solvent"`, `ion_sele="(resn CA,HG,K,NA,ZN,MG,CL)"`). Broader + maintained. |
| HTTP download with progress | raw socket / `requests` (3rd-party — forbidden) | `urllib.request.urlopen` + `resp.read(block)` + `Content-Length` | `urllib` is stdlib (no approval per SUMMARY.md:31); `vina.py:30,140` `urlretrieve` + `castp.py:127` are the ecosystem pattern. `Content-Length` gives `pct = received*100//total`. |
| modeless progress dialog event loop | manual `while True: processEvents()` spin | `QTimer.singleShot(100, drain)` recursive | The recursive singleShot lets the Qt event loop run between drains (3D viewer stays smooth); a tight spin would starve the viewer. Matches `gui_game.py:84-87`'s QTimer discipline. |
| thread-safe worker→main marshalling | `threading.Lock` + shared variables | `queue.Queue` | `queue.Queue` is thread-safe by design; Pitfall 6 (`PITFALLS.md:171`) explicitly recommends it. |

**Key insight:** PyMOL already reads and writes `.pdb.gz` natively (gzip-magic detection in `file_read`; gzip branch in `save`). The ONLY thing we hand-roll is the urllib download (which PyMOL's `cmd.fetch` does too, but `cmd.fetch` is RCSB-only — MemProtMD/SASBDB need our own URL → `urllib` path). Don't reinvent the cache format, the gzip step, or the selectors.

## Common Pitfalls

### Pitfall A: `.exec_()` on the progress dialog trips the grep gate
**What goes wrong:** `progress.exec_()` adds a new hit to `grep -rnE "\.exec_\(\)" biochemeleon/`. The gate (AGENTS.md) requires exec_ hits to be on `QFileDialog`/`QMessageBox` ONLY — never the main `PluginDialog`/`SetupTab`, and `QProgressDialog` is NOT in the allowlist.
**Why it happens:** `QProgressDialog` inherits `QDialog`, so `.exec_()` is available. The modal pattern is also the simpler Qt example.
**How to avoid:** Use `progress.show()` (modeless) — this is both SC1-compliant ("modeless cancelable") AND gate-compliant. NO `.exec_()` on the progress dialog.
**Warning signs:** `grep -rnE "\.exec_\(\)" biochemeleon/` returns >1 hit (current baseline is exactly 1: `gui_game.py:303` `msg.exec_()` — a `QMessageBox`, allowed). A second hit on a `QProgressDialog` is a Rule-3 violation.
**Current baseline (verified 2026-08-14):** `grep -rnE "\.exec_\(\)" biochemeleon/` → `biochemeleon/gui_game.py:303: msg.exec_()` (QMessageBox — allowed). The static `QFileDialog.getSaveFileName`/`getOpenFileName` (`gui_setup.py:560,579`) do NOT use `.exec_()` from our code (they own their own modal loop). So the gate is at exactly 1 allowed hit. Phase 9 must keep it there.

### Pitfall B: `cmd.*` off the main thread (Pitfall 6)
**What goes wrong:** Putting `cmd.load`/`cmd.remove`/`cmd.save` in the worker thread → deadlocks, segfaults, "Selector-Error" out of nowhere (PITFALLS.md:160-178).
**Why it happens:** Tempting to "do everything in the worker." But PyMOL's `cmd.*` takes a non-reentrant lock (`_self.lockcm` — `creating.py`, every command).
**How to avoid:** Worker = urllib ONLY. The `drain()` callback (main thread) calls `finalize_large_demo` which does the `cmd.*`.
**Warning signs:** `threading.Thread` with `cmd.` anywhere in its target/callees.

### Pitfall C: Confusing the pre-game STRIP with the cleanup-time SENTINEL filter (Pitfall 9)
**What goes wrong:** A reviewer sees `cmd.remove(f"{obj} and solvent")` and flags it as a Pitfall 9 violation ("never use `solvent`/`water`/`hetatm` as the cleanup filter").
**Why it happens:** Pitfall 9 (`PITFALLS.md:247-259`) warns against generic filters for CLEANUP (removing game hiders) — there, ONLY `segi GAME` is allowed. But DEMO-02 explicitly says "strip water and salt" BEFORE the game starts (a deliberate, user-requested transform of a fetched demo, not the hider-cleanup path).
**How to avoid:** Document the distinction clearly in the `demos.finalize_large_demo` docstring: "This is the deliberate pre-game strip (DEMO-02), NOT the cleanup-time sentinel filter (Pitfall 9 uses `segi GAME` only). The membrane lipids (DPPC) are `organic`, NOT `solvent`/`inorganic`, so they survive the strip."
**Warning signs:** A grep for `solvent`/`inorganic` in `demos.py` — expected and correct here (would be WRONG in `mutation.cleanup_hiders`).

### Pitfall D: Structural ions stripped by `inorganic`
**What goes wrong:** `cmd.remove(f"{obj} and inorganic")` removes ALL ions, including a catalytic/structural ZN/CA that the structure needs to fold or render meaningfully.
**Why it happens:** `inorganic` (`preset.py:26` `ion_sele` includes ZN/MG/CA) matches structural metals, not just bulk salt.
**How to avoid:** For 1GZM (bacteriorhodopsin, 7-TM helix) and 3GP6 (OmpA-like beta-barrel), there are no critical catalytic ions, and the MemProtMD "_dry" variant likely has no ions anyway (coarse-grained→atomistic conversion drops them) — so the strip is a defensive no-op. Verify at human-verify that no important ion vanished (visually check the loaded object). If a future demo HAS a structural ion, exclude it: `cmd.remove(f"{obj} and inorganic and not resn ZN")`.
**Warning signs:** A metal sphere disappears after the strip; the structure looks wrong. Flag for human-verify.

### Pitfall E: Cache path breaks for an INSTALLED plugin (v1 scope: run-from-repo)
**What goes wrong:** The cache path `tmp/phase9-demos/cache/` is resolved relative to the repo root (`os.path.dirname(__file__)/../tmp/...`). For a plugin INSTALLED via the Plugin Manager (not run from the repo), `..` from the install dir is wrong and `tmp/` doesn't exist.
**Why it happens:** v1 runs from the repo (per AGENTS.md dev workflow). The install path isn't exercised in v1.
**How to avoid:** For v1, resolve the cache relative to the repo root (mirrors `load_demo`'s `os.path.join(os.path.dirname(__file__), 'data', 'demos', ...)` pattern, `demos.py:128`). `os.makedirs(cache_dir, exist_ok=True)` before writing. Flag the installed-plugin case as an Open Question (v2/follow-up: make the cache dir configurable via `cmd.set` or fall back to a user-writable dir).
**Warning signs:** `cmd.load` raises "File not found" on a cache hit when the plugin is installed (not run from repo).

## Code Examples

Verified patterns from PyMOL 2.5.0 source + Qt5 docs.

### The worker-thread download (demos.py — Qt-free, Pitfall 6 compliant)
```python
# Source: urllib stdlib + vina.py:30,140 (urlretrieve pattern) + PITFALLS.md Pitfall 6.
# Lives in demos.py (NO `from pymol.Qt`, NO `from pymol import cmd` in this function).
import os, threading, queue, urllib.request

def download_large_demo(demo_id, dest_path, progress_queue, cancel_event):
    """Download a large demo's raw file to dest_path via urllib (WORKER THREAD).
    Posts ('progress', pct) / ('done',) / ('error', msg) to progress_queue.
    Checks cancel_event between read blocks. NO cmd.* (Pitfall 6). Returns None
    (result goes via the queue)."""
    meta = DEMO_MANIFEST[demo_id]
    url = meta['fetch_url']
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'bioCHEMeleon/1.0'})
        with urllib.request.urlopen(req, timeout=60) as resp:
            total = int(resp.headers.get('Content-Length', 0))  # 0 = unknown
            received = 0
            with open(dest_path, 'wb') as f:
                while True:
                    if cancel_event.is_set():
                        progress_queue.put(('canceled',))
                        return
                    block = resp.read(65536)  # 64KB blocks
                    if not block:
                        break
                    f.write(block)
                    received += len(block)
                    if total > 0:
                        progress_queue.put(('progress', received * 100 // total))
        progress_queue.put(('done',))
    except Exception as exc:
        progress_queue.put(('error', str(exc)))
```

### The main-thread finalize (demos.py — cmd.*, no Qt)
```python
# Source: cmd.load (importing.py:635) + cmd.remove (mutation.py:158 pattern) +
#         cmd.save('.pdb.gz') (exporting.py:859-914) + to_windows_path (demos.py:24).
def finalize_large_demo(demo_id, downloaded_path):
    """Load the downloaded file, strip water/salt, save stripped .pdb.gz to cache.
    Runs on the MAIN thread (cmd.*). Returns obj_name or None. This is the
    DEMO-02 pre-game strip (NOT the cleanup-time segi-GAME filter — see Pitfall C)."""
    meta = DEMO_MANIFEST[demo_id]
    obj_name = demo_id.lower()
    win_path = to_windows_path(downloaded_path)
    try:
        cmd.load(win_path, object=obj_name, zoom=1)   # file_read detects gzip magic
    except Exception:
        return None
    if meta.get('strip', False):
        # Strip water (solvent) and salt/ions (inorganic). DPPC membrane is
        # `organic` -> survives. Defensive no-op on the MemProtMD "_dry" variant.
        try:
            cmd.remove("%s and solvent" % obj_name)     # preset.py:25 wat_sele
            cmd.remove("%s and inorganic" % obj_name)    # preset.py:26 ion_sele
        except Exception:
            pass  # selectors are no-ops if nothing matches
    # Cache the stripped structure as .pdb.gz (cmd.save writes gzip in one step)
    cache_dir = _cache_dir()               # tmp/phase9-demos/cache/
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, meta['cache_name'])  # e.g. '1gzm.pdb.gz'
    try:
        cmd.save(to_windows_path(cache_path), obj_name)  # exporting.py:912 gzip branch
    except Exception:
        pass  # cache write failure is non-fatal (object is already loaded)
    return obj_name
```

### Cache-hit + cache-path helpers (demos.py)
```python
def _cache_dir():
    """tmp/phase9-demos/cache/ resolved relative to the repo root.
    Mirrors load_demo's os.path.dirname(__file__)/data/demos pattern (demos.py:128)."""
    return os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', 'cache'))

def cache_path_for(demo_id):
    """Absolute path to the cached .pdb.gz for a demo (or None for bundled)."""
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None or meta.get('source') == 'bundled':
        return None
    return os.path.join(_cache_dir(), meta['cache_name'])

def is_cached(demo_id):
    p = cache_path_for(demo_id)
    return bool(p and os.path.exists(p))

def load_cached_demo(demo_id):
    """Cache-hit path: cmd.load the cached .pdb.gz (already stripped). Main thread.
    Returns obj_name or None (None = cache miss / bundled / load failed)."""
    meta = DEMO_MANIFEST.get(demo_id)
    if meta is None or meta.get('source') == 'bundled':
        return None  # bundled demos use load_demo()
    p = cache_path_for(demo_id)
    if not os.path.exists(p):
        return None  # cache miss — caller must download
    obj_name = demo_id.lower()
    try:
        cmd.load(to_windows_path(p), object=obj_name, zoom=1)  # reads .pdb.gz natively
        return obj_name
    except Exception:
        return None
```

### The QProgressDialog modeless skeleton (the full paste-ready version)
See **Pattern 1** above — it is the complete skeleton (construct → show → spawn worker → recursive `QTimer.singleShot(100, drain)` → finalize on 'done' → `progress.close()`). Key API points (Qt 5.15 docs, HIGH confidence):
- `QProgressDialog(labelText, cancelButtonText, minimum, maximum, parent)`.
- `setWindowModality(QtCore.Qt.NonModal)` + `.show()` → modeless.
- `setAutoClose(False)` + `setAutoReset(False)` → prevent the dialog auto-hiding when `setValue` hits `maximum` mid-pipeline (defaults are both `True` — `doc.qt.io` autoClose/autoReset).
- `setMinimumDuration(500)` → show after 500ms (default 4000ms; we lower it because the user explicitly triggered the fetch).
- `setRange(0, 100)` + `setValue(pct)` → determinate bar (download phase).
- `setRange(0, 0)` → **indeterminate busy indicator** (the Qt idiom; the `QProgressBar` inside shows "busy" when min==max==0). Use for the load/strip/save phase (duration unknown). Safe: per the docs, "if you set a new maximum that equals your current value, the dialog will not close regardless" — so `setRange(0,0)` with `value==0` won't auto-close.
- `progress.canceled` signal → connect to `cancel_event.set` (the worker checks the Event between blocks).
- `setValue()` calls `processEvents()` ONLY in modal mode (Qt docs WARNING) — modeless does NOT, so we drive updates via our `QTimer` drain. Confirmed by the docs' modeless example.

## DEMO_MANIFEST Schema Extension

### Current schema (`setup_state.py:29-36`)
```python
DEMO_MANIFEST = {
    '1znf': {'category':'Protein', 'type':'protein', 'difficulty':'easy',  'file':'1znf.pdb'},
    ...
    '4wb3': {'category':'Mixed', 'type':'protein/na', 'difficulty':'mixed', 'file':'4wb3.pdb'},
}
```

### Proposed extended schema (uniform — all entries get all fields)
Add `source`, `source_id`, `fetch_url`, `cache_name`, `citation`, `strip`. Rename `file` → `cache_name` (semantically: the on-disk filename; `source` tells the loader which dir — `data/demos/` for bundled, `tmp/phase9-demos/cache/` for fetched). Keep `category`, `type`, `difficulty`.

```python
# Manifest of all demos (DEMO-01 bundled + DEMO-02/03 fetched).
# Phase 9 (DIFF-05) extends with large fetched demos + 4-tier difficulty.
# Sources cited in repo-root DATA_SOURCES.md (DEMO-04).
DEMO_MANIFEST = {
    # --- Bundled small demos (DEMO-01) — source='bundled', fetch_url=None, strip=False ---
    '1znf': {'category':'Protein', 'type':'protein', 'difficulty':'easy',
             'source':'bundled', 'source_id':'1ZNF', 'fetch_url':None,
             'cache_name':'1znf.pdb', 'citation':'1ZNF', 'strip':False},
    '1xdn': {'category':'Protein', 'type':'protein', 'difficulty':'hard',
             'source':'bundled', 'source_id':'1XDN', 'fetch_url':None,
             'cache_name':'1xdn.pdb', 'citation':'1XDN', 'strip':False},
    '5e54': {'category':'Nucleic acid', 'type':'rna', 'difficulty':'easy',
             'source':'bundled', 'source_id':'5E54', 'fetch_url':None,
             'cache_name':'5e54.pdb', 'citation':'5E54', 'strip':False},
    '1k8p': {'category':'Nucleic acid', 'type':'dna', 'difficulty':'easy',
             'source':'bundled', 'source_id':'1K8P', 'fetch_url':None,
             'cache_name':'1k8p.pdb', 'citation':'1K8P', 'strip':False},
    '2qbz': {'category':'Nucleic acid', 'type':'rna', 'difficulty':'hard',
             'source':'bundled', 'source_id':'2QBZ', 'fetch_url':None,
             'cache_name':'2qbz.pdb', 'citation':'2QBZ', 'strip':False},
    '4wb3': {'category':'Mixed', 'type':'protein/na', 'difficulty':'hard',  # was 'mixed' -> 'hard'
             'source':'bundled', 'source_id':'4WB3', 'fetch_url':None,
             'cache_name':'4wb3.pdb', 'citation':'4WB3', 'strip':False},
    # --- Fetched large demos (DEMO-02 MemProtMD) — source='memprotmd', strip=True ---
    '1gzm': {'category':'Membrane protein', 'type':'protein', 'difficulty':'very_challenging',
             'source':'memprotmd', 'source_id':'1GZM',
             'fetch_url':'<MemProtMD URL for 1GZM _dry — filled by MemProtMD researcher>',
             'cache_name':'1gzm.pdb.gz', 'citation':'1GZM', 'strip':True},
    '3gp6': {'category':'Membrane protein', 'type':'protein', 'difficulty':'very_challenging',
             'source':'memprotmd', 'source_id':'3GP6',
             'fetch_url':'<MemProtMD URL for 3GP6 _dry — filled by MemProtMD researcher>',
             'cache_name':'3gp6.pdb.gz', 'citation':'3GP6', 'strip':True},
    # --- Fetched large demo (DEMO-03 SASBDB) — source='sasbdb', strip=True ---
    '<sasbdb-id>': {'category':'Glycoprotein', 'type':'protein', 'difficulty':'challenge',
             'source':'sasbdb', 'source_id':'<SASBDB ID>',
             'fetch_url':'<SASBDB URL — filled by SASBDB researcher>',
             'cache_name':'<sasbdb-id>.pdb.gz', 'citation':'<SASBDB ID>', 'strip':True},
}

# Display labels for the 4 tiers (DIFF-05). Manifest stores identifier-safe
# values (no spaces); the GUI maps to the human-readable labels the success
# criterion literally specifies: "Easy / Hard / Challenge / Very challenging".
TIER_LABELS = {
    'easy': 'Easy',
    'hard': 'Hard',
    'challenge': 'Challenge',
    'very_challenging': 'Very challenging',
}
```

### Field reference
| Field | Values | Purpose |
|-------|--------|---------|
| `category` | "Protein"/"Nucleic acid"/"Mixed"/"Membrane protein"/"Glycoprotein" | Display grouping (existing) |
| `type` | "protein"/"rna"/"dna"/"protein/na" | Internal (existing) |
| `difficulty` | `easy`/`hard`/`challenge`/`very_challenging` | 4-tier (DIFF-05); mapped to display via `TIER_LABELS` |
| `source` | `bundled`/`memprotmd`/`sasbdb`/`rcsb` | Where the demo comes from; drives the loader branch |
| `source_id` | PDB ID (`1GZM`) or SASBDB ID | External identifier for citation |
| `fetch_url` | URL or `None` | The download URL (`None` for bundled); filled by the MemProtMD/SASBDB researchers |
| `cache_name` | filename | On-disk name: `data/demos/{cache_name}` (bundled) or `tmp/phase9-demos/cache/{cache_name}` (fetched, `.pdb.gz`) |
| `citation` | short ref (`1GZM`, `SASDXX`) | Cross-ref to the DATA_SOURCES.md section (for tooltips/attribution) |
| `strip` | bool | Whether `finalize_large_demo` runs the water/salt strip (`True` for fetched, `False` for bundled) |

### Difficulty-tier vocabulary + mapping (DIFF-05)
The success criterion literally says **"Easy / Hard / Challenge / Very challenging"** (4 tiers). Current values `easy`/`hard`/`mixed` need reconciliation:
- **Manifest stores identifier-safe values** (no spaces — easier as dict keys + grep-able): `easy`, `hard`, `challenge`, `very_challenging`.
- **Display labels** (via `TIER_LABELS`): "Easy", "Hard", "Challenge", "Very challenging" — matches the criterion exactly.
- **`4wb3` mapping:** was `mixed` → map to `hard` (4wb3 is a mid-complexity protein/NA hybrid, 3779 atoms — fits 'hard', not the large-demo tiers). Phase 2 research §12.5 flagged this as LOW impact + deferred to Phase 9; Phase 9 resolves it to `hard`.

### Tier assignment (9 demos → 4 tiers)
| Demo | Category | Tier | Rationale |
|------|----------|------|-----------|
| 1znf | Protein | easy | 212 atoms, zinc finger |
| 5e54 | Nucleic acid (RNA) | easy | riboswitch aptamer |
| 1k8p | Nucleic acid (DNA) | easy | G-quadruplex, 428 atoms |
| 1xdn | Protein | hard | RNA ligase, 2095 atoms |
| 2qbz | Nucleic acid (RNA) | hard | M-Box riboswitch, 3263 atoms |
| 4wb3 | Mixed | hard | protein/NA hybrid, 3779 atoms (was 'mixed') |
| `<sasbdb-id>` | Glycoprotein | challenge | glycoprotein + glycan (new complexity: glycan visualization) |
| 1gzm | Membrane protein | very_challenging | bacteriorhodopsin 7-TM helix, large |
| 3gp6 | Membrane protein | very_challenging | OmpA beta-barrel + full DPPC membrane, 100k+ atoms |

Result: 3 easy + 3 hard + 1 challenge + 2 very_challenging = 9 demos, 4 tiers. Matches the criterion exactly.

## Demo Sub-Menu Display (flat Combo vs QTreeWidget)

**Recommendation: keep the flat `QComboBox`** (9 items < the 15-item QTreeWidget threshold from Phase 2 research, `02-RESEARCH.md:396`: "A flat combo is simpler than a QTreeWidget and is enough for 6 items. If Phase 9 grows the set to ~15+ demos, upgrade to a QTreeWidget").

### Display-string format (tier-surfaced, per DIFF-05)
Current (`gui_setup.py:126-128`): `"{category} — {id} ({difficulty})"`. Extend to map the tier via `TIER_LABELS` so the display uses the criterion's exact labels:

```python
# gui_setup.py — demo_combo population (replace the current format string)
from .setup_state import DEMO_MANIFEST, TIER_LABELS
for did, meta in DEMO_MANIFEST.items():
    tier = TIER_LABELS.get(meta['difficulty'], meta['difficulty'].title())
    self.demo_combo.addItem(
        "{category} — {id} ({tier})".format(
            category=meta['category'], id=did, tier=tier),
        did)
```
Examples: `"Membrane protein — 3gp6 (Very challenging)"`, `"Glycoprotein — <sasbdb-id> (Challenge)"`, `"Protein — 1znf (Easy)"`.

### Ordering (group by tier for discoverability)
`DEMO_MANIFEST` is a dict (insertion-ordered in Py3.6.9). Order the manifest entries by tier (easy → hard → challenge → very_challenging) so the combo shows a natural difficulty progression. (The schema snippet above already lists them in this order.) Optionally insert `QComboBox` separators between tier groups via `self.demo_combo.insertSeparator(idx)` — a nice-to-have, not required; flag for the planner.

### Why NOT QTreeWidget yet
- 9 items is well under the ~15 threshold.
- A flat combo with tier in the label + tier-ordered entries surfaces the DIFF-05 metadata (SC4: "surfaces difficulty-tiered metadata").
- A QTreeWidget (category top-level → demos) is more code + more click depth. Defer to a future phase IF the demo set grows past ~15.

## demos.load_demo Branching

### Current (`demos.py:114-137`)
`load_demo(demo_id)` → resolves `data/demos/{file}` → `cmd.load`. Bundled only.

### Proposed split (keeps `demos.py` Qt-free; the Qt orchestration is in `__init__.py`)
The task proposed a single `fetch_large_demo(demo_id, progress_callback=None) -> obj_name or None`. **That single-function API does NOT cleanly fit** because: (a) the `QProgressDialog` is Qt → can't be created in Qt-free `demos.py`; (b) keeping the 3D viewer interactive during download (SC1) requires the main thread to stay free, which means the download runs on a worker thread and the drain loop (which needs `QTimer`/`processEvents` = Qt) must live in the Qt layer (`__init__.py`); (c) a `progress_callback` called from the worker thread would touch Qt widgets off the main thread (unsafe). The **split API** below is the clean, constraint-compliant version. (The single-function `fetch_large_demo(demo_id, progress_callback)` is a considered-and-rejected alternative — it would either block the main thread during download, violating SC1, or need `processEvents` in `demos.py`, violating the Qt-free rule.)

#### `demos.py` functions (Qt-free)
| Function | Thread | Returns | Purpose |
|----------|--------|---------|---------|
| `load_demo(demo_id)` | main | `obj_name` or `None` | **Extend the existing function.** If `source=='bundled'`: current path (`data/demos/{cache_name}` → `cmd.load`). If `source` is fetched: delegate to `load_cached_demo` (cache hit) or return `None` (cache miss — signals the caller to fetch). Keeps the synchronous bundled path unchanged. |
| `load_cached_demo(demo_id)` | main | `obj_name` or `None` | Cache-hit `cmd.load` of `tmp/phase9-demos/cache/{cache_name}` (`.pdb.gz`, already stripped). `None` = cache miss / bundled. |
| `download_large_demo(demo_id, dest, queue, cancel_event)` | **worker** | `None` (result via queue) | urllib download to `dest`; posts progress/done/error/canceled. NO `cmd.*`. |
| `finalize_large_demo(demo_id, downloaded_path)` | main | `obj_name` or `None` | `cmd.load` downloaded file → strip (if `meta['strip']`) → `cmd.save` `.pdb.gz` cache. |
| `cache_path_for(demo_id)` / `is_cached(demo_id)` / `_cache_dir()` | either | path/bool | pure path helpers. |
| `temp_download_path(demo_id)` / `cleanup_temp(path)` | either | path/None | temp-file management (use `tempfile` or `tmp/phase9-demos/`). |

#### `__init__.py` `PluginDialog` orchestration (Qt)
- Extend `_prepare_and_start` (`__init__.py:136-146`, the `elif mode == "demo":` branch): if `demos.DEMO_MANIFEST[demo_id]['source'] != 'bundled'` AND not `demos.is_cached(demo_id)`, call a new `_resolve_large_demo(demo_id)` (the Pattern 1 skeleton) which shows the `QProgressDialog` + spawns the worker + drains via `QTimer`; on 'done', `finalize_large_demo` loads + strips + caches the object. On cache hit, `demos.load_cached_demo` is synchronous (no dialog).
- The fetch is triggered at the SAME point demos are loaded today (the Start button → `_prepare_and_start`). No new "Load demo to preview" button is needed for v1 scope (flag as deferred — a user may want to load a large demo just to view it).
- Because the fetch is async (worker thread), `_prepare_and_start` must NOT block on it. Two options for the planner: (a) make `_resolve_large_demo` schedule the finalize and have `_prepare_and_start` return early with a "fetching…" state, then re-enter the start flow on 'done' (more complex); (b) show the dialog modally-to-our-flow but modeless-to-the-viewer by spinning a `QTimer` drain that returns control to `_prepare_and_start` only after 'done' (simpler — the viewer stays interactive because `QTimer` pumps events between drains). Recommend (b) for v1 simplicity; the planner decides.

#### Cache workflow
1. User clicks Start with a large demo selected.
2. `_prepare_and_start` → `demos.load_demo(demo_id)` → `load_cached_demo` → if cache hit, `cmd.load(cache.pdb.gz)`, done (fast, no dialog).
3. Cache miss → `_resolve_large_demo` shows modeless `QProgressDialog`, spawns `download_large_demo` (worker, urllib → `tmp/phase9-demos/<id>.raw`), `QTimer` drains → on 'done', `finalize_large_demo` does `cmd.load` + strip + `cmd.save` → `tmp/phase9-demos/cache/<id>.pdb.gz`.
4. Object is now loaded (stripped). The game proceeds (collapse states, build hider_specs, etc. — the rest of `_prepare_and_start`).
5. Next time this demo is selected: step 2 is a cache hit → no download, no dialog.

## Strip + Compress + Cache Pipeline

### Selectors (verified in PyMOL 2.5.0 source — HIGH confidence)
- **Water:** `solvent` — built-in selector keyword (`cmd.py:363` lists `'solvent'` in the selector keyword Shortcut; `preset.py:25` `wat_sele = "solvent"`; `menu.py:845,932` `cmd.select(..., "(sele) and solvent")`). Matches HOH/SOL/other water resnames. BROADER + canonical vs `resn HOH` (which only matches HOH). **Use `solvent`.**
- **Salt/ions:** `inorganic` — built-in (`cmd.py:363`; `menu.py:934` `cmd.select(..., "(sele) and not organic")`). Matches ions. PyMOL's canonical ion selector (`preset.py:26`): `ion_sele = "(resn CA,HG,K,NA,ZN,MG,CL)"` (note: comma-separated, NOT `+` — both work in PyMOL but the source uses `,`). `inorganic` is the keyword equivalent. **Use `inorganic`** (or the explicit `(resn CA,HG,K,NA,ZN,MG,CL)` if you want to exclude structural ZN — see Pitfall D).
- **Both:** `cmd.remove(f"{obj} and solvent")` then `cmd.remove(f"{obj} and inorganic")`. DPPC membrane lipids are `organic` (not solvent/inorganic) → survive. (Pitfall C: this is the deliberate DEMO-02 pre-game strip, NOT the cleanup `segi GAME` filter.)
- **Defensive no-op:** the MemProtMD "_dry" variant is likely already water/ion-free → the selectors match nothing → `cmd.remove` is a no-op. DEMO-02 says strip anyway (defensive; future variants may have them).

### cmd sequence (the exact approach)
```python
# 1. Load the downloaded raw file (cmd.load reads .pdb OR .pdb.gz via file_read magic detection)
cmd.load(to_windows_path(downloaded_path), object=obj_name, zoom=1)
# 2. Strip water + ions (defensive; no-op if already dry)
if meta.get('strip', False):
    cmd.remove("%s and solvent" % obj_name)      # internal.py selectors; preset.py:25
    cmd.remove("%s and inorganic" % obj_name)     # preset.py:26 ion_sele equivalent
# 3. Cache the stripped object as .pdb.gz (ONE cmd.save call writes gzip)
os.makedirs(cache_dir, exist_ok=True)
cmd.save(to_windows_path(cache_pdbgz_path), obj_name)  # exporting.py:912 gzip.open
# (object stays loaded — the user plays immediately)
```

### `.pdb.gz` vs `.zip` — verified from PyMOL source
- **`cmd.load("foo.pdb.gz")` WORKS.** `importing.py:635` `load()` → `internal.py:346` `_load()` → `internal.py:360` `_self.file_read(finfo)` → `internal.py:278-308` `file_read()` detects the gzip magic `contents[:2] == b'\x1f\x8b'` → `gzip.GzipFile(...).read()` → passes decompressed bytes to the C-level `_cmd.load`. So `cmd.load` reads `.pdb.gz` directly. (Also `importing.py:41-101` `filename_to_format` detects `.gz` extension, but the magic-number detection in `file_read` is the load-bearing path.) HIGH confidence.
- **`cmd.save("foo.pdb.gz", obj)` WRITES GZIP in one step.** `exporting.py:833-834` `filename_to_format` → `zipped='gz'`; `:859` `format in savefunctions` → `:989` `'pdb': get_str` → `:892` `contents = func(**kw)` returns the PDB string (get_str has NO 'filename' param, so `:894` does NOT return early) → `:908` `is_string(contents)` True → `:912` `if zipped == 'gz': import gzip; fopen = gzip.open` → writes gzipped PDB. HIGH confidence.
- **`cmd.load` does NOT read inside `.zip`.** `file_read` (`internal.py:299-306`) only detects gzip (`\x1f\x8b`) and bzip2 (`BZ...1AY&SY`) magic — no zip/`PK` magic. A `.zip` would need a manual `zipfile` extract step. So `.pdb.gz` is strictly better than `.zip`.
- **Compression ratio:** gzip ≈ zip (both DEFLATE) → ~6-7x (the staged `.zip` sample was 231KB vs 1.5MB raw ≈ 6.7x; `.pdb.gz` achieves similar).
- **Recommendation:** cache as `.pdb.gz` (one file, `cmd.load` reads it, `cmd.save` writes it, no stdlib `gzip` step).

### Cache location + .gitignore
- **Location:** `tmp/phase9-demos/cache/{cache_name}` (e.g. `1gzm.pdb.gz`).
- **Why `tmp/` not `data/`:** the user directive stages fetched data under `./tmp/` (repo-local). `.gitignore` has `tmp` (line: `tmp`); **verified `git check-ignore tmp/phase9-demos` returns exit 0 (ignored)** — NO `.gitignore` change needed. ARCHITECTURE.md:126 (`data/cache/`) is superseded by this directive (would need a new `.gitignore` entry).
- **Path resolution:** relative to repo root, mirroring `load_demo`'s `os.path.dirname(__file__)/data/demos` pattern (`demos.py:128`):
  `os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'tmp', 'phase9-demos', 'cache'))`.
  Then `to_windows_path(...)` before `cmd.load`/`cmd.save` (Pitfall 11 — Windows PyMOL can't read `/mnt/c/...`).
- **`os.makedirs(cache_dir, exist_ok=True)`** before writing (the dir may not exist on first fetch).
- **Persistence:** `tmp/` is a real on-disk dir (just gitignored) → the cache persists across PyMOL sessions (no re-download). Good.
- **Pitfall E (installed plugin):** for v1 (run-from-repo) this works. An INSTALLED plugin (Plugin Manager) won't have `tmp/` — flag as an Open Question (v2: configurable cache dir).

## DATA_SOURCES.md Consolidation (DEMO-04)

### Location
**Repo root: `DATA_SOURCES.md`** (per DEMO-04: "Produce a `DATA_SOURCES.md`"). NOT inside `biochemeleon/data/demos/`.

### Relationship to existing `biochemeleon/data/demos/SOURCES.md`
**Absorb it.** The existing `SOURCES.md` (64 lines, `biochemeleon/data/demos/SOURCES.md`) already says: "Phase 9 will consolidate this into a repo-root DATA_SOURCES.md (DEMO-04); until then this per-bundle file satisfies DEMO-01's 'sources cited' requirement" (`SOURCES.md:7-8`). Plan 02-02-SUMMARY.md:15 confirms the consolidation plan (`affects: [09-large-demo-fetch (DATA_SOURCES.md will absorb SOURCES.md)]`). Recommendation:
- Move/merge the 6 bundled citations into the repo-root `DATA_SOURCES.md`.
- Replace `biochemeleon/data/demos/SOURCES.md` with a 2-line stub: "Sources consolidated in repo-root `DATA_SOURCES.md` (DEMO-04). See `/DATA_SOURCES.md`." (keeps the old path as a pointer for any external references; OR delete it — the planner decides. Recommend the stub to avoid breaking any hardcoded reference.)
- Update `setup_state.py:27` docstring comment ("Citations live in biochemeleon/data/demos/SOURCES.md (Plan 02-02)") → "Citations live in repo-root DATA_SOURCES.md (DEMO-04, Phase 9)."

### Proposed structure
```markdown
# DATA_SOURCES.md — bioCHEMeleon demo data sources & licenses

All external data sources for the bioCHEMeleon demo set. Every PDB ID, DOI,
SASBDB ID, and MemProtMD attribution is listed here with its license.
Verify before redistribution (DEMO-04).

## 1. Bundled small demos (RCSB PDB) — CC0 1.0
[absorb the 6 entries from biochemeleon/data/demos/SOURCES.md verbatim:
 1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3 — each with PDB ID, DOI, title, authors,
 publication, method, notes]
### License
RCSB PDB data files: CC0 1.0 Public Domain Dedication
(https://www.rcsb.org/pages/policies). Attribution requested: PDB ID + DOI +
publication + PyMOL (Schrödinger LLC).

## 2. Fetched membrane-protein demos (MemProtMD + RCSB) — DEMO-02
### 1GZM — bacteriorhodopsin (very challenging)
- PDB ID: 1GZM (RCSB, CC0) — DOI: https://doi.org/10.2210/pdb1gzm/pdb
- MemProtMD entry: [URL + entry ID — filled by MemProtMD researcher]
- Membrane coordinates: DPPC bilayer from MemProtMD
- Citation: Stansfeld et al., MemProtMD, Nat. Methods 2018
  (https://doi.org/10.1038/s41592-018-0220-9) — VERIFY fetch (was unreachable)
- License: [PDB CC0 for 1GZM; MemProtMD membrane coords — VERIFY per-entry
  license before bundling (PITFALLS.md:521)]
### 3GP6 — OmpA beta-barrel + full DPPC membrane (very challenging)
[same structure]
### License
PDB entries CC0. MemProtMD membrane coordinates: [VERIFY per-entry license —
the DPPC bilayer may carry CC-BY or stricter terms than PDB's CC0
(PITFALLS.md:521). MUST verify before bundling (DEMO-04 SC3).]

## 3. Fetched glycoprotein demo (SASBDB) — DEMO-03
### <SASBDB ID> — Alpha-1-glycoprotein with glycan (challenge)
- SASBDB ID: [filled by SASBDB researcher]
- URL: [filled by SASBDB researcher]
- Citation: [original authors — filled by SASBDB researcher]
- License: "free of all copyright restrictions, made fully and freely available
  for both non-commercial and commercial use. Users should attribute the
  original authors." (SASBDB /about/ — PITFALLS.md:520)

## 4. PDB_POOL (Randomize fetch mode) — RCSB CC0
The 34 curated PDB codes in PDB_POOL (setup_state.py:44-78) are all RCSB entries
(verified 2026-08-05). Blanket attribution: RCSB PDB CC0 1.0 (§1 license above).
Individual citations available at https://www.rcsb.org/structure/{ID}.
[Recommendation: a blanket RCSB CC0 attribution suffices for the pool; the pool
 is fetched on-demand by the user's Randomize, not bundled. Planner confirms.]

## 5. PyMOL
Schrödinger LLC — https://pymol.org — cite per standard practice.
```

### License sections (HIGH confidence for RCSB/SASBDB, MEDIUM for MemProtMD — per PITFALLS.md:517-522)
- **RCSB PDB** (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3, 1GZM, 3GP6): CC0 1.0 (verified `rcsb.org/pages/policies`). Cite PDB ID + DOI + publication + PyMOL.
- **SASBDB**: "free of all copyright restrictions… fully and freely available for non-commercial and commercial use. Users should attribute the original authors." (verified SASBDB `/about/`). Cite SASBDB ID + authors.
- **MemProtMD**: MEDIUM confidence — the site was UNREACHABLE at research time (PITFALLS.md:521). SC3 explicitly requires "MemProtMD per-entry licenses verified before bundling." The MemProtMD researcher must verify the per-entry license of the DPPC membrane coordinates (the PDB entries 1GZM/3GP6 are CC0, but the MEMBRANE coords from MemProtMD may carry CC-BY or stricter terms). Flag as an Open Risk + a human-verify checkpoint (NOT auto-verifiable).
- **PyMOL**: Schrödinger LLC.

## Verification Approach (WSL-testable vs human-verify checkpoint)

### WSL-testable (headless `cmd.exe /c C:\src\run-conda-pymol.bat -cq <script>` — per AGENTS.md)
The fetch+strip+compress+cache **logic** in `demos.py` (urllib download + `cmd.load` + `cmd.remove` strip + `cmd.save` `.pdb.gz` + cache write) is exercisable headlessly (no Qt). The `progress_queue`/`cancel_event` can be a no-op/print in the smoke test (the worker posts to a real queue but the smoke test just joins the thread + asserts the cache file exists). Map these to **auto** task types:

| Smoke check | How (headless) |
|------------|----------------|
| `download_large_demo` urllib → temp | WSL Python `urllib` directly (no PyMOL needed) OR stage a tiny test PDB URL; assert temp file written |
| `finalize_large_demo` `cmd.load` + strip + `cmd.save` cache | Stage the downloaded temp to the Windows path; run `cmd.exe /c C:\src\run-conda-pymol.bat -cq smoke\phase9_smoke.py` headlessly; assert cache `.pdb.gz` exists + `cmd.load(cache)` round-trips + `cmd.count_atoms("obj and solvent")==0` |
| `load_cached_demo` cache hit | headless: pre-place a `.pdb.gz` in `tmp/phase9-demos/cache/`, `cmd.load` it, assert object loaded |
| `cache_path_for`/`is_cached`/`_cache_dir` path resolution | pure `os.path` — unit-testable in WSL Python (no PyMOL) |
| `DEMO_MANIFEST` schema + `TIER_LABELS` + tier values | pure data — unit-testable in WSL (extend `tests/test_setup_state.py` with `test_manifest_has_all_fields`, `test_tier_labels`, `test_4wb3_mapped_to_hard`) |
| grep gates (Pitfall 1, exec_) | `grep -rnE "import Tkinter..." biochemeleon/` (ZERO); `grep -rnE "\.exec_\(\)" biochemeleon/` (must stay at 1: the `QMessageBox` in `gui_game.py:303` — the `QProgressDialog` uses `.show()`, NOT `.exec_()`) |

### Human-verify checkpoint (needs the real Windows PyMOL GUI — NOT WSL-testable)
The Qt/GUI behavior + visual correctness + license accuracy. Map to **checkpoint:human-verify** task types:

| Check | Why human-only |
|-------|----------------|
| `QProgressDialog` is modeless + cancelable + doesn't block the 3D viewer | Qt — can't run from WSL (AGENTS.md); the player must rotate/zoom the molecule WHILE the download progress bar updates (SC1) |
| The Cancel button aborts the in-flight download (worker exits, temp cleaned, dialog closes) | Qt + real network timing |
| The demo sub-menu shows the 4-tier labels ("Easy"/"Hard"/"Challenge"/"Very challenging") for the 9 demos (SC4) | visual Qt combo inspection |
| The membrane protein loads with the DPPC membrane visible (no water, membrane intact) | visual — confirms the strip kept DPPC + removed water (Pitfall C/D) |
| The glycoprotein loads with the glycan visible | visual (DEMO-03) |
| No structural ion was wrongly stripped (Pitfall D) | visual check of the loaded membrane objects |
| `DATA_SOURCES.md` license accuracy — esp. MemProtMD per-entry license verified (SC3, PITFALLS.md:521) | human review of the MemProtMD site (was unreachable at research time) |

### Task-type mapping (for the planner)
- **auto (WSL-testable):** `setup_state.py` manifest extension + `TIER_LABELS` + unit tests; `demos.py` `download_large_demo`/`finalize_large_demo`/`load_cached_demo`/cache helpers + headless smoke; grep gates.
- **checkpoint:human-verify:** `__init__.py` `QProgressDialog` orchestration (modeless/cancelable/viewer-interactive); demo sub-menu tier display; visual load of membrane/glycoprotein; `DATA_SOURCES.md` MemProtMD license verification.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| `cmd.fetch` for all demos (RCSB-only) | `urllib` + `cmd.load` for MemProtMD/SASBDB; `cmd.fetch` still fine for RCSB | Phase 9 | MemProtMD/SASBDB aren't RCSB → need our own URL+download; `cmd.fetch`'s RCSB URL templates (`importing.py:1122-1134`) don't cover them |
| `data/cache/` (ARCHITECTURE.md:126) | `tmp/phase9-demos/cache/` (user directive) | Phase 9 | Already gitignored (no `.gitignore` change); repo-local staging per user preference |
| `difficulty: 'mixed'` (4wb3, Phase 2) | `difficulty: 'hard'` (4wb3, Phase 9 DIFF-05) | Phase 9 | 4-tier vocabulary; 'mixed' → 'hard' (Phase 2 §12.5 deferred this to Phase 9) |
| `file` field (Phase 2) | `cache_name` field (Phase 9) + `source` | Phase 9 | Uniform schema; `source` drives the loader branch (bundled vs fetched) |

**Deprecated/outdated:**
- `biochemeleon/data/demos/SOURCES.md` as the primary citation file → superseded by repo-root `DATA_SOURCES.md` (keep as a stub pointer or delete; planner decides).
- ARCHITECTURE.md's `data/cache/` proposal → superseded by `tmp/phase9-demos/cache/`.

## Open Questions / Open Risks

1. **MemProtMD `fetch_url` + per-entry license** — MEDIUM/LOW confidence. The MemProtMD site was UNREACHABLE at research time (PITFALLS.md:521). The MemProtMD researcher fills `fetch_url` + verifies the per-entry license of the DPPC membrane coordinates (SC3 requires this). My pipeline depends on `fetch_url` being present in the manifest (I just download whatever URL is there). **Recommendation:** the MemProtMD researcher owns the URL + license; my pipeline is URL-agnostic. Flag SC3's MemProtMD license verification as a human-verify checkpoint (NOT auto).

2. **SASBDB `fetch_url` + demo id** — the SASBDB researcher fills these. The glycoprotein demo's `demo_id`/`source_id`/`fetch_url`/`cache_name` are TBD (shown as `<sasbdb-id>` placeholders). My schema + pipeline accommodate whatever they choose (the `demo_id` becomes the PyMOL object name lowercased — ensure it's a valid PyMOL object name, no spaces).

3. **`_prepare_and_start` re-entrancy after async fetch** — the fetch is async (worker thread); `_prepare_and_start` (`__init__.py:96-266`) currently runs synchronously to completion. Two options (documented in the Branching section): (a) return early on cache-miss + re-enter on 'done'; (b) spin a `QTimer` drain that keeps the viewer interactive and resumes `_prepare_and_start` after 'done'. **Recommendation: (b)** for v1 (simpler control flow). The planner picks. LOW risk either way.

4. **Installed-plugin cache path (Pitfall E)** — `tmp/phase9-demos/cache/` is repo-relative. An installed plugin (Plugin Manager) won't have `tmp/`. v1 runs from repo (AGENTS.md) so this is fine for v1. **Recommendation:** flag for v2 (configurable cache dir via `cmd.set('fetch_path', ...)` or a user-writable fallback); out of scope for Phase 9 v1.

5. **`inorganic` strips structural ions (Pitfall D)** — `inorganic` matches ZN/MG/CA (structural) not just bulk salt. For 1GZM/3GP6 + the "_dry" variant, likely a no-op. **Recommendation:** strip with `solvent` + `inorganic`; human-verify no important ion vanished. If a future demo has a structural ion, exclude it: `cmd.remove(f"{obj} and inorganic and not resn ZN")`. LOW risk for these demos.

6. **QProgressDialog `.show()` + `autoClose=False` repaint during blocking `cmd.load`** — after the download 'done' event, `finalize_large_demo` runs `cmd.load`+`cmd.remove`+`cmd.save` on the main thread (blocking). The dialog label was set + `processEvents()` called BEFORE the block (Pattern 1). During the block the dialog won't repaint, but the label is already correct. For a 100k-atom membrane protein, `cmd.load` of a `.pdb.gz` is sub-second to a few seconds. **Recommendation:** acceptable; the indeterminate busy indicator + the pre-set label convey "working." If the block is >2s, consider splitting `finalize` into `QTimer.singleShot(0, ...)` steps (each cmd.* as a separate main-thread callback) — but this is likely over-engineering for v1. LOW risk.

7. **PDB_POOL citation in DATA_SOURCES.md** — the 34 randomize codes (RCSB CC0) — a blanket RCSB CC0 attribution likely suffices (they're user-fetched on demand, not bundled). **Recommendation:** blanket attribution (§4 of DATA_SOURCES.md); planner confirms. LOW risk.

## Sources

### Primary (HIGH confidence)
- **PyMOL 2.5.0 source** (`tmp/pymol-src/modules/pymol/`, tag `v2.5.0`):
  - `internal.py:278-308` — `file_read()` gzip magic detection (`\x1f\x8b`) → `gzip.GzipFile` transparent decompression. Confirms `cmd.load("foo.pdb.gz")` works.
  - `internal.py:346-366` — `_load()` calls `_self.file_read(finfo)` (the gzip path) for string-based formats (incl. PDB).
  - `importing.py:41-101` — `filename_to_format()` detects `.gz`/`.bz2`; `:635-740` `load()`; `:1149-1238` `_fetch()` (fetch_path cache: `:1211` skips download if cached file exists).
  - `exporting.py:833-914` + `:986-989` — `save()`: `'pdb'` savefunction is `get_str` (returns string) → `:912` `if zipped=='gz': gzip.open`. Confirms `cmd.save("foo.pdb.gz", obj)` writes gzip in one step.
  - `cmd.py:362-365` — selector keyword list: `'organic','inorganic','solvent','polymer','guide','hetatm','hydrogens','backbone','sidechain','metals'`. Confirms `solvent`/`inorganic` are built-in.
  - `preset.py:24-27` — `wat_sele="solvent"`, `ion_sele="(resn CA,HG,K,NA,ZN,MG,CL)"`. PyMOL's own canonical water/ion selectors.
  - `menu.py:845,932,934` — `solvent`/`inorganic`/`organic` used in selection menus.
  - `Qt/__init__.py` — `from PyQt5 import QtGui, QtCore, QtOpenGL, QtWidgets` → `QtWidgets` (incl. `QProgressDialog`) accessible via `pymol.Qt`.
- **Qt 5.15 official docs** (`doc.qt.io/qt-5/qprogressdialog.html`, fetched 2026-08-14):
  - `autoClose`/`autoReset` default `True`; `setAutoClose(False)`/`setAutoReset(False)` to prevent auto-hide mid-pipeline.
  - `setRange(0,0)` → indeterminate busy indicator (the QProgressBar idiom); safe (won't auto-close when value==max==0).
  - `canceled()` signal + `wasCanceled()` bool; `cancel()` slot resets + hides.
  - `minimumDuration` default 4000ms (we set 500).
  - `setValue()` calls `processEvents()` ONLY in modal mode (WARNING in docs) → modeless needs our `QTimer` drain.
  - Modeless example = `QTimer` + worker thread + `connect(pd, canceled, ..., cancel)` — exactly our design.
- **Existing project code** (read 2026-08-14):
  - `biochemeleon/setup_state.py:29-36` (DEMO_MANIFEST), `:44-78` (PDB_POOL), `:150-244` (pure functions).
  - `biochemeleon/demos.py:24-43` (to_windows_path), `:67-85` (fetch_pdb async_=0), `:114-137` (load_demo).
  - `biochemeleon/gui_setup.py:122-129` (demo_combo format), `:269-284` (_on_fetch), `:560-580` (QFileDialog static — no .exec_).
  - `biochemeleon/gui_game.py:84-87` (QTimer pattern), `:303` (msg.exec_ QMessageBox — the exec_ gate baseline).
  - `biochemeleon/__init__.py:30` (dialog.show() modeless), `:136-146` (load_demo trigger in _prepare_and_start).
  - `biochemeleon/mutation.py:158` (`cmd.remove(f"{object} and segi GAME")` — the cmd.remove-from-object pattern).
  - `biochemeleon/data/demos/SOURCES.md` (64 lines — to be absorbed into DATA_SOURCES.md).
- **`.gitignore`** — `tmp` (line confirming tmp gitignored); `git check-ignore tmp/phase9-demos` → exit 0 (ignored).

### Secondary (MEDIUM-HIGH confidence)
- **`Pymol-script-repo/plugins/vina.py`** — `:30,140` (`from urllib.request import urlretrieve; urlretrieve(url, dest)`); `:202,806` (`Qt.QtWidgets.QProgressBar` via `pymol.Qt` — confirms QtWidgets accessibility). Reference plugin prior art.
- **`Pymol-script-repo/plugins/castp.py:127-129`** — `urllib.urlretrieve` download pattern.
- **`Pymol-script-repo/plugins/mtsslDockGui.py:646`** — `threading.Thread(target=self.dock)` (ecosystem threading pattern, with the Pitfall 6 caveat).
- **`.planning/research/PITFALLS.md`** — Pitfall 6 (`:160-180`, golden rule + queue.Queue + QTimer.singleShot(0, drain)); Pitfall 9 (`:247-259`, cleanup filter vs strip distinction); Pitfall 11 (`:465-477`, to_windows_path); Pitfall 12 (`:479-493`, modeless cancelable QProgressDialog + never cmd.get_model on large objects); licensing (`:517-522`, RCSB CC0 / SASBDB / MemProtMD verify).
- **`.planning/research/STACK.md`** — `:39` (cmd.fetch async_=0); `:161` (async_ kwarg).
- **`.planning/research/ARCHITECTURE.md`** — `:97` (DemoLoader), `:126` (cache/ git-ignored — superseded by tmp/), `:507` (urllib.request.urlretrieve).
- **`.planning/phases/02-.../02-RESEARCH.md`** — `:396` (flat QComboBox <15 items); `:1140-1141` (4wb3 'mixed' labeling, deferred to Phase 9).
- **`.planning/REQUIREMENTS.md`** — DEMO-02 (`:69`), DEMO-03 (`:70`), DEMO-04 (`:71`), DIFF-05 (`:84`).
- **`.planning/ROADMAP.md`** — Phase 9 (`:186-198`): SC1 (modeless cancelable progress dialog), SC2 (SASBDB cited), SC3 (DATA_SOURCES.md + MemProtMD license verified), SC4 (4-tier sub-menu).

### Tertiary (LOW confidence — flagged for validation)
- **MemProtMD `fetch_url` + per-entry license** — site was unreachable (PITFALLS.md:521); the MemProtMD researcher must fill the URL + verify the license (SC3). My pipeline is URL-agnostic.
- **SASBDB `fetch_url` + demo id** — the SASBDB researcher fills these (placeholders `<sasbdb-id>` in the schema snippet).
- **`setRange(0,0)` busy-indicator behavior** — HIGH confidence from Qt docs + QProgressBar idiom, but the exact visual (spinning box vs 0%) depends on the Qt style; human-verify the indeterminate phase looks right.

## Metadata

**Confidence breakdown:**
- Standard stack (QProgressDialog, urllib, threading, queue, cmd.load/save/remove): **HIGH** — PyMOL source + Qt5 docs + reference plugins + existing project code all corroborate.
- Architecture (split API, modeless pattern, .pdb.gz cache, cache location): **HIGH** — verified against PyMOL source (load/save gzip) + Qt5 docs (modeless example) + .gitignore (tmp ignored).
- DEMO_MANIFEST schema + tier vocabulary + mapping: **HIGH** — straightforward extension of the existing schema; tier labels match the success criterion verbatim; 4wb3 mapping resolves the Phase 2 deferral.
- DATA_SOURCES.md structure + RCSB/SASBDB licenses: **HIGH** — RCSB CC0 + SASBDB terms verified (PITFALLS.md:517-522); absorbs the existing SOURCES.md.
- MemProtMD URL + license: **LOW** — site unreachable; deferred to the MemProtMD researcher + human-verify (SC3).
- Strip-selector structural-ion risk (Pitfall D): **MEDIUM** — `inorganic` matches structural ions; LOW risk for 1GZM/3GP6 "_dry" (likely no-op); human-verify.
- Installed-plugin cache path (Pitfall E): **LOW** — out of scope for v1 (run-from-repo); flag for v2.

**Research date:** 2026-08-14
**Valid until:** 2026-09-13 (30 days — stable PyMOL 2.5.0 + Qt5 APIs; the MemProtMD/SASBDB URLs + licenses may change sooner — re-verify at execution)
