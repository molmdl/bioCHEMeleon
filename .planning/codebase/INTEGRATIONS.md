# External Integrations

**Analysis Date:** 2026-08-18

## Host Application: PyMOL Plugin Contract

bioCHEMeleon is a **PyMOL 2.5.0 desktop plugin**, NOT a standalone app. There is no backend, no server, no web layer. The "integration" is the plugin-loader contract with PyMOL itself.

**Plugin entry point:**
- Location: `biochemeleon/__init__.py`
- Symbol: `__init_plugin__(app=None)` (modern signature). PyMOL's plugin loader (`pymol/plugins/__init__.py`) imports the package and calls this once on load.
- Registration: `from pymol.plugins import addmenuitemqt` (local import inside `__init_plugin__`) → `addmenuitemqt('bioCHEMeleon', run_plugin_gui)`. Adds the "bioCHEMeleon" item to PyMOL's Plugins menu. Raises `QtNotAvailableError` if no Qt — the loader catches it.
- Singleton dialog: module-level `dialog = None`; `run_plugin_gui()` lazily creates `PluginDialog()` on first open, then `dialog.show()` (modeless) on subsequent opens.

**PyMOL API surface used (all verified against `tmp/pymol-src/modules/pymol/` v2.5.0):**
- `pymol.cmd` — molecular commands (`create`, `delete`, `load`, `save`, `fetch`, `alter`, `alter_state`, `iterate`, `identify`, `count_atoms`, `get_names`, `get_type`, `get_extent`, `show`, `hide`, `color`, `pseudoatom`, `sort`, `select`, `button`, `set_wizard`, `refresh_wizard`). Imported at module level in `demos.py`, `backup.py`, `mutation.py`, `game.py`, `gui_setup.py`, `gui_game.py`, `__init__.py`.
- `pymol.wizard.Wizard` — base class for the click-to-find `PickWizard` (`biochemeleon/wizard.py`). Overrides `do_pick(self, bondFlag)`, `get_event_mask`, `get_prompt`, `get_panel`.
- `pymol.editor` — `from pymol import editor` (local import in `mutation.py:410`) for `editor.attach_amino_acid` (fragment attach; `editor.py:85`).
- `pymol.Qt` — `QtCore, QtGui, QtWidgets` (GUI widgets). Imported in `__init__.py`, `gui_setup.py`, `gui_game.py`.

**Key PyMOL API pitfalls (see `AGENTS.md` + `.planning/research/PITFALLS.md` for full detail):**
- PyMOL Open Source has NO undo. Every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (`biochemeleon/backup.py`).
- Hiders are inserted INTO the same object via `cmd.pseudoatom(object=existing, ...)` — NEVER a separate object.
- `cmd.fetch` must use `async_=0` for synchronous load (`biochemeleon/demos.py:117`).
- No `cmd.get_representations()` in 2.5.0; detect reps with `cmd.count_atoms("{obj} and rep {rep}") > 0` (`biochemeleon/demos.py:140`).
- `cmd.iterate` exposes atom id as UPPERCASE `ID` (not lowercase `id`); use `space={'stored': ...}` (never `space=None`).

## APIs & External Services

**Molecular structure data sources (the ONLY network integrations):**

1. **RCSB PDB (wwPDB)** — PDB code fetch.
   - SDK/Client: `pymol.cmd.fetch` (built into PyMOL; no separate SDK).
   - Implementation: `biochemeleon/demos.py` `fetch_pdb(code, name=None)` — wraps `cmd.fetch(code, name=obj_name, async_=0)` in try/except. Returns object name or `None`.
   - Auth: None (public).
   - Used by: Setup tab "fetch" target mode (user enters a PDB code); also the Randomize fetch mode draws from a curated `PDB_POOL` of 34 verified codes (`biochemeleon/setup_state.py:78`).

2. **MemProtMD** (`https://memprotmd.bioch.ox.ac.uk`) — membrane-protein demos with full DPPC membrane.
   - SDK/Client: stdlib `urllib.request` (no SDK). Downloaded in a worker thread.
   - Endpoints (in `DEMO_MANIFEST`, `biochemeleon/setup_state.py:49-56`):
     - `1gzm`: `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/1gzm_default_dppc/files/structures/at.pdb`
     - `3gp6`: `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/3gp6_default_dppc/files/structures/at.pdb`
   - Auth: None (public).
   - Processing: water/salt (resn `SOL`/`NA`/`CL`) stripped in pure Python BEFORE `cmd.load` (the ~95k-atom wet file never enters PyMOL); dry ~19k-atom result cached as `.pdb.gz` in `tmp/phase9-demos/cache/`.

3. **SASBDB** (`https://www.sasbdb.org`) — glycoprotein demo (Alpha-1-glycoprotein model).
   - SDK/Client: stdlib `urllib.request`.
   - Endpoint: `SASDPG4` → `https://www.sasbdb.org/media/pdb_file/SASDPG4_fit2_model1.pdb` (`biochemeleon/setup_state.py:46`).
   - Auth: None (public).
   - SSL caveat: SASBDB's HARICA root CA may be absent from Windows conda's bundled cert list. `biochemeleon/demos.py` `_urlopen_with_ssl_fallback()` retries without cert verification on SSL failure (acceptable for public structure files; posts a `'warning'` event to the drain).
   - Processing: `strip=False` — glycan HETATM is preserved (NOT stripped).

**Async large-demo fetch architecture (Phase 9):**
- Worker thread (`biochemeleon/demos.py` `download_large_demo`): stdlib ONLY (`urllib`/`queue`/`os`/`threading`/`ssl`). Makes NO `pymol.cmd` calls (Pitfall 6). Posts `('progress', pct)`/`('done',)`/`('error', msg)`/`('canceled',)` to a `queue.Queue`. Reads in 64KB blocks; checks `cancel_event` between blocks. Sets `User-Agent: bioCHEMeleon/1.0` (SASBDB blocks bare default urllib UA).
- Main-thread drain (`biochemeleon/__init__.py` `_resolve_large_demo`): recursive `QTimer.singleShot(100, drain)` polls the queue, updates a MODELESS `QProgressDialog` (so the 3D viewer stays rotatable during download). On `'done'`: calls `finalize_large_demo` (cmd.* on main thread) → continuation (tab switch + countdown). Owns ALL error/cancel UI (no double-dialog).

## Data Storage

**Databases:**
- None. No SQL/NoSQL/graph DB. No ORM.

**File Storage:**
- **Bundled demos (offline):** `biochemeleon/data/demos/` — 6 PDB files (`1znf.pdb`, `1xdn.pdb`, `5e54.pdb`, `1k8p.pdb`, `2qbz.pdb`, `4wb3.pdb`). Committed to the repo. Located via `os.path.dirname(__file__)/data/demos/` so the path works whether run from repo or installed plugin dir.
- **Fetched-demo cache:** `tmp/phase9-demos/cache/` (gitignored). `.pdb.gz` files written by `cmd.save` (PyMOL writes gzip in one step when filename ends `.gz`). Persists across sessions. `PyMOL reads .pdb.gz natively` (gzip magic auto-detected).
- **Temp downloads:** `tmp/phase9-demos/<demo_id>.raw` (raw download) + `.dry` (stripped intermediate). Cleaned by `cleanup_temp()` after cache write.
- **Game checkpoints / puzzles:** `.bcmz` archives (user-chosen path via `QFileDialog.getSaveFileName`). Format = `zipfile.ZIP_DEFLATED` containing `game.pse` (PyMOL session, written by `cmd.save`) + `game.bcm` (JSON sidecar). Implemented in `biochemeleon/persistence.py` `write_bcmz`/`read_bcmz` (pure stdlib `zipfile` + `json`).
- **Setup configs:** user Save/Load Setup writes/reads JSON (`SETUP_FORMAT = "biochemeleon-setup-v1"`). Via `QFileDialog`.

**Caching:**
- Fetched-demo `.pdb.gz` cache (above). No general-purpose cache layer (no Redis/memcached).

## Game-State Persistence Format

**`.bcmz` archive** (`biochemeleon/persistence.py`):
- `game.pse` — PyMOL session file (binary pickle of the scene + objects; written by `cmd.save(pse_path, target_obj)` scoped to exclude `_bchm_backup`).
- `game.bcm` — JSON sidecar. Magic header `BCM_MAGIC = 'BIOCHEMELEON-BCM'` + `BCM_VERSION = 1`. `parse_bcm_dict` refuses wrong magic or version > `BCM_VERSION` with a clear "please update" error. Contains: target object name, per-hider registry (`registry.to_dict()`), timer elapsed, reveal_count, hint_count, found_color, setup state dict, `kind` (`'checkpoint'` | `'puzzle'`).
- `.bcm` schema is forward-compat-hooked (`found_color_rgb` reserved, not wired in v1).

## Authentication & Identity

**Auth Provider:**
- None. This is a local desktop plugin. No user accounts, no login, no tokens, no API keys. All external data sources (RCSB, MemProtMD, SASBDB) are public and unauthenticated.

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry, no telemetry). Errors surface as `QMessageBox.warning` dialogs to the user, or as return-`None` contracts (e.g. `load_demo` returns `None` on failure rather than raising).

**Logs:**
- In-game rolling info log: `gui_game.py` `_info_log` (`QTextEdit`) — game events (hits, misses, hints, reveals) appended at runtime. Not persisted to disk.
- `print`/stderr for dev debugging (visible in the PyMOL console / headless cmd.exe output).

## CI/CD & Deployment

**Hosting:**
- Local desktop (Windows PyMOL via conda). No cloud hosting.

**CI Pipeline:**
- None (no GitHub Actions / no automated CI). Verification is manual: `python3.6 -m py_compile` + `python3.6 -m unittest` in WSL; headless smoke via `run-conda-pymol.bat -cq`; GUI smoke = human-verify checkpoint.

**Deployment / Install:**
- End-user: PyMOL GUI *Plugin → Plugin Manager → Install New Plugin* → point at the `biochemeleon/` package directory (accepts a package dir with `__init__.py`). Copies into `%APPDATA%/pymol/startup/biochemeleon/`. Loader calls `__init_plugin__` on next PyMOL launch.
- Dev: run from the repo's Windows path; or stage via `wsl2win_cp.sh` to `tmp/bioCHEMeleon/` for headless smoke.

## Environment Configuration

**Required env vars:**
- None. Conda env activation (`setenv.bat`) handles PATH. No runtime env vars.

**Secrets location:**
- None. No secrets, no API keys. `.gitignore` excludes `*.env`, `**/secrets.toml`, `**/auth.json` defensively.

## WSL→Windows Bridge (the dev-to-runtime integration)

This is the key "integration" between the dev shell and the runtime:

- `setenv.bat` — Windows cmd.exe batch. Sets `CONDAPATH=C:\ProgramData\Miniconda3`, `ENVNAME=chemtools-win10`, resolves `ENVPATH` to `%USERPROFILE%\.conda\envs\chemtools-win10`, calls `activate.bat`. Does NOT launch PyMOL.
- `run-conda-pymol.bat` — Same activation + `python %ENVPATH%\Lib\site-packages\pymol\__init__.py %*` + `conda deactivate`. Passthrough args. For headless: `-cq <script>`.
- `wsl2win_cp.sh` — `cp -r ./biochemeleon tmp/bioCHEMeleon/`. Stages the package to a Windows-readable path (`/mnt/c/...`).
- `demos.to_windows_path(path)` (`biochemeleon/demos.py:59`) — converts `/mnt/<letter>/...` WSL mount paths to `<LETTER>:\...` Windows paths. GUARD, not unconditional: only `/mnt/<single-letter>/` paths are converted; already-Windows and genuine-Linux paths pass through unchanged. Required because Windows PyMOL cannot resolve WSL paths.

**Headless run recipe (from `AGENTS.md`):**
```bash
bash wsl2win_cp.sh                          # stage package
mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/
cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -50
```
Exit 0 = clean; nonzero = crash. Qt/GUI paths STILL need a human in a real PyMOL session.

## PyMOL Source Mirror (API verification only — NOT a runtime dependency)

- `tmp/pymol-src/modules/pymol/` — PyMOL 2.5.0 open-source Python modules (gitignored, NOT present in parallel-execution worktrees). Readable from any worktree via the main-repo absolute path `/mnt/c/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/pymol-src/modules/pymol/`.
- Purpose: confirm API signatures / debug unexpected runtime behavior when a citation (e.g. `creating.py:960`, `editing.py:1424`, `querying.py:1302`) behaves differently than expected. Key modules: `creating.py`, `editing.py`, `querying.py`, `viewing.py`, `commanding.py`, `wizard/__init__.py`.
- NOT shipped, NOT imported at runtime, NOT a dependency.

## Webhooks & Callbacks

**Incoming:**
- None. No webhook endpoints (no server).

**Outgoing:**
- None. No outbound webhooks. The only outbound network traffic is the urllib GETs to RCSB/MemProtMD/SASBDB for demo PDB downloads (above).

## Data Attribution

- `biochemeleon/data/demos/SOURCES.md` — points to repo-root `DATA_SOURCES.md` (DEMO-04, Phase 9). All demo sources + IDs cited there.
- `DATA_SOURCES.md` (repo root) — consolidated source citations for bundled + fetched demos.
- `LICENSE` — project license. `LICENSE_pymol-open-source` — PyMOL open-source license (for attribution compliance).

---

*Integration audit: 2026-08-18*
