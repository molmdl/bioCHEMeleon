# External Integrations

**Analysis Date:** 2026-09-08

## Overview

bioCHEMeleon is two **host-application plugins**, not a standalone app. There is no backend, no server, no web layer.

- **v2 (ACTIVE milestone):** a VMD 1.9.3 Tcl/Tk script (`vmd/`) — attaches to VMD via the source/pkgIndex plugin contract. **All data is local**: 6 bundled PDBs; `fetch_pdb` is a deliberate STUB (VMD 1.9.3's http package lacks tls → HTTPS impossible).
- **v1 (SHIPPED, frozen):** a PyMOL 2.5.0 Python/PyQt5 plugin (`pymol/biochemeleon/`) — the only real network integrations in the repo (RCSB, MemProtMD, SASBDB), all frozen since 2026-08-22.

| Integration | v1 (`pymol/`) | v2 (`vmd/`) |
|---|---|---|
| RCSB PDB fetch | REAL (`cmd.fetch`) | **STUB** (`vmd/lib/demos.tcl:106` — errors) |
| MemProtMD downloads | REAL (urllib worker) | Not present (bundled only) |
| SASBDB downloads | REAL (urllib + SSL fallback) | Not present (bundled only) |
| Setup save/load | REAL (JSON `.bcm`) | REAL (key-value `.bcm`, `vmd/lib/demos.tcl:116-181`) |
| Game-state persistence | REAL (`.bcmz` zip, `pymol/biochemeleon/persistence.py`) | **NOT BUILT** (Phase 18+; `save_state` does not persist beta/user/segid) |
| Demo data | 6 bundled PDBs + 3 fetched | 6 bundled PDBs (own copy at `vmd/data/demos/`) |
| Atom picking | `Wizard.do_pick` (GUI) | `trace ::vmd_pick_event` (GUI-only delivery) |
| Rep detection | `cmd.count_atoms("{obj} and rep X")` | `molinfo` combined-braces rep fields |

## Host Application: VMD 1.9.3 Plugin Contract (v2)

**Entry point:** `vmd/biochemeleon.tcl`
- Re-source guard BEFORE the namespace body (`vmd/biochemeleon.tcl:29-32`) — `info exists ::biochemeleon::loaded` is safe on a not-yet-created namespace; top-level `return` terminates a re-source cleanly.
- `package provide biochemeleon 2.0` BEFORE `vmd_install_extension` so its internal `package require` is a no-op (`vmd/biochemeleon.tcl:59`).
- Sources all modules in strict dependency order (`vmd/biochemeleon.tcl:76-118`): `setup_state` → `registry` (exactly ONCE — re-sourcing would wipe `_records`) → `generators` → `game_logic` → `rep_tiers` → `demos` → `backup` → `mutation` → `hiders` → `game` → `pick_bridge` → `gui/dialog.tcl`.
- `biochemeleon` console proc — `::tk_version`-guarded (headless `-dispdev text` prints a warn and no-ops, `vmd/biochemeleon.tcl:140-149`).
- `biochemeleon_tk_cb` — menu callback returning the toplevel widget path (pattern from `clonerep.tcl:237`, verified across 4 bundled plugins).
- Registration: `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"` (`vmd/biochemeleon.tcl:175`), Tk-guarded. Menu path is **Visualization/bioCHEMeleon** (locked decision — NOT `Extensions/`).
- Optional packaged install: `vmd/pkgIndex.tcl` — `package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]` for the `auto_path` + `package require` form.

**GUI integration:** `vmd/gui/dialog.tcl` — modeless `toplevel .biochemeleon` + `ttk::notebook` (Setup + Game tabs); NEVER `grab set` on the main panel (the 3D viewer must stay interactive for click-to-find). `vmd/gui/game_tab.tcl` registers log/remaining/win callbacks via `game::set_callbacks` and deactivates the pick bridge on win. All GUI setup is Tk-guarded so headless sourcing is silent.

## VMD Tcl API Surface (what the plugin actually calls)

**Molecule lifecycle** (`vmd/lib/mutation.tcl`, `vmd/lib/backup.tcl`):
- `mol new <path> type pdb` / `mol delete $molid` — the ONLY mutation/reload mechanism (VMD cannot add atoms or delete individual atoms).
- `mol addrep` / `mol delrep` / `mol modstyle` / `mol modselect` / `mol modcolor` / `mol modmaterial` — rep management is command-based, never GUI-layered. `mol delrep` renumbers → always delete index 0 in a loop.
- `mol repname $m $i` / `mol repindex $m $name` — reps tracked by STABLE NAME (`rep0`, `rep1`, … monotonic, never reset), never by index (`vmd/lib/hiders.tcl` name-keyed `tier_reps` dict).

**Molecule introspection:**
- `molinfo $m get {filename numatoms numreps name}` (`vmd/lib/backup.tcl` snapshot; `vmd/lib/demos.tcl:186` `atom_count`).
- Rep fields via the **COMBINED-BRACES form** — `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` (`vmd/lib/demos.tcl:94`, `vmd/lib/backup.tcl` snapshot). The single-field form `molinfo get {rep $i}` FAILS (verified pitfall).
- `measure minmax $sel` → `{{xmin ymin zmin} {xmax ymax zmax}}` (`vmd/lib/mutation.tcl:93`) — bounding box for free-tier placement.

**Selections:** `atomselect` + `$sel get/set/delete`. `$sel delete` after EVERY use (dangling selections leak and return stale data silently). Selections never cached across `mol delete`/reload. The registry's atomselect touchpoint is INJECTED by the composition root as an `apply` lambda command prefix (`vmd/lib/game.tcl:323-328` — `[list apply {{molid} {...}} $game_molid]`, never an immediately-evaluated `[apply ...]`).

**Picking (LOCKED mechanism — GUI-verified 2026-08-30, a full round was won through it):**
- PRIMARY: `trace add variable ::vmd_pick_event write <proc>` with a **`{args}` signature** (a positional signature makes VMD's own write FAIL and loses the pick). Handler reads globals `vmd_pick_atom` (0-based atom index — the registry key) + `vmd_pick_mol` (`vmd/lib/pick_bridge.tcl:1-25`).
- Game mode engages via `mouse mode pick 2` only. FORBIDDEN: `mouse mode 4 2` (USERPOINT — UG table stale vs binary), `mouse mode pick 0` (QUERY). `::vmd_pick_atom_callbacks` is a PHANTOM — never read, never gated on.
- FIRST-CLICK QUIRK (locked known behavior): one keyboard `p` press per round arms C-side pick delivery; pasted `mouse mode` commands never arm. Player guidance: press `p` (or `1`) once on the VMD display.
- Fallback: dormant label-poll diff via `label list Atoms` / `label delete Atoms <n>` (delete from END only — renumbering; `vmd/lib/pick_bridge.tcl:65-68`). Never active by default.
- Hidden reps CANNOT be picked (UG node140) → `vmd/lib/hiders.tcl` never hides a rep; found hiders stay visible (green).
- Pick and rotate are MUTUALLY EXCLUSIVE mouse modes (hotkey `r` = rotate, `1` = pick atom).

**Console/messaging:** `vmdcon -info/-warn/-err` everywhere (non-blocking warns for under-generation/dropped tiers — `vmd/lib/game.tcl:210,263,290`).

**NEVER call:** `mol ssrecalc` (destructive — wipes manual `set structure` writes; load-time STRIDE already assigns the fake residue `T`; `vmd/lib/splice.tcl:17-30` decision record).

## Atom-Field Channels (the sentinel + visual protocol)

Set in-place via `atomselect` after load; these fields ARE the game's data plane:

| Field | Value | Purpose |
|---|---|---|
| `resname` | `GAM` (3 cols) | hider sentinel (4-char "GAME" silently dropped) |
| `beta` | `-999` (selector: `resname GAM and beta < 0`, NEVER exact `beta -999`) | hider sentinel; NEVER rewritten after tagging (registry reconstruct + cleanup depend on it) |
| `segid` | `GAME` (4 cols) | hider sentinel |
| `chain` | `G` (simple tiers) / anchor's chain (residue tiers) | classification |
| `resid` | 9001+k (residue tiers, disjoint block) | `resid` → CA map for pick fallback |
| `user2` | 0/1 | found flag (`user2 > 0` = found rep selection) |
| `user3` | 1..N (tier code) | per-atom tier channel; exact-match selectable `user3 1`; float read-back (compare numerically) |
| `element` | copied from anchor | cols 77-78 — THE load-bearing blend field (blank degrades to radius-1.50 X) |

Residue tiers: CA-only beta stamping via `tag_sentinels_mixed` (`vmd/lib/mutation.tcl`; NEVER `tag_sentinels` on a residue round — Pitfall C6).

## PDB File Handling (the core mechanic)

**Bundled demo loading** (`vmd/lib/demos.tcl:58-82` `load_demo`):
- Path = `script_dir/../data/demos/<cache_name>` where `script_dir` was frozen at source time (`[info script]` is empty at call time under `vmd -e`).
- Rejects any non-`bundled` source entry (`return -code error`); GUI catches and shows a dialog.
- 6 PDBs at `vmd/data/demos/{1znf,1xdn,5e54,1k8p,2qbz,4wb3}.pdb` + `SOURCES.md` — committed, offline, viewer-agnostic (v1 has its own copy under `pymol/biochemeleon/data/demos/`).

**PDB-rebuild hider insertion** (`vmd/lib/mutation.tcl` — VMD cannot add atoms):
1. Generators produce records: free tiers = uniform-random points in the `measure minmax` box; bonded tiers = 1.2–1.6 Å from a heavy anchor (`vmd/lib/generators.tcl` constants `D_MIN 1.2`/`D_MAX 1.6`/`MIN_SEP_REAL 1.4`/`MIN_SEP_HIDER 4.0`/`MAX_TRIES 25`/`RELAX_ROUNDS 2`); residue tiers = ONE fake GAM residue (N/CA/C/O/CB) displaced `SPLICE_DISPLACEMENT 1.0` Å perpendicular to the peptide-bond vector (`vmd/lib/splice.tcl` — hard envelope 1.43 Å, `RESID_BASE 9001`, `MIN_ANCHOR_SEP 5.0`).
2. `write_combined_pdb` emits strict 78-column ATOM records (`splice::atom_record`, `vmd/lib/splice.tcl:270-284` — VERBATIM sibling of `mutation.tcl::_hider_record`): name cols 13-16, resname GAM 18-20, chain 22, resid 23-26, coords 31-54 (%8.3f), occupancy 1.00, beta 61-66 (CA via `%6.1f` → `-999.0` — `%6.2f` would OVERFLOW the 6-col field and corrupt segid), segid GAME 73-76, element 77-78 (ALWAYS emitted).
3. `%8.3f` overflow guard: any |coord| > 9999.0 is rejected/relaxed (`generators.tcl MAX_COORD`, `splice::assemble_record max_coord`) — a coordinate ≥ 10000 shifts the whole line right and silently corrupts the element field.
4. `mol delete` original → `mol new <combined.pdb>` → sentinel tagging via `atomselect` (`resname GAM`; `beta -999`; `segid GAME`). Load-time distance search auto-bonds: atoms bond iff `d < 0.6*(r_i+r_j)` (radii C 1.70/N 1.55/O 1.52/S 1.80/P 1.55/H 1.00/unknown 1.50) — extra bonds are NORMAL (assert `numbonds >= 1`, never `== 1`).
5. Load-time STRIDE assigns the fake residue ss `T` (renders as a coil/turn tube — accepted Option A); `mol ssrecalc` is NEVER called.

## APIs & External Services

**v2 (vmd/):** NONE — zero network. `fetch_pdb` (`vmd/lib/demos.tcl:106-108`):
```tcl
proc ::biochemeleon::demos::fetch_pdb {code} {
    return -code error "fetch_pdb not implemented in Phase 14 (VMD 1.9.3 lacks tls for HTTPS); use a bundled demo"
}
```
Signature mirrors v1; the GUI shows the fetch option but catches the error and points to bundled demos. The `pdb_pool` setup key exists but stays empty in v2 (no `PDB_POOL` constant; `randomize_state` re-rolls fetch→demo when the pool is empty — `vmd/lib/setup_state.tcl:263`). Real network fetch is Phase 21 scope (would need a tls strategy).

**v1 (pymol/) — REAL, shipped, frozen:**
1. **RCSB PDB** — `pymol/biochemeleon/demos.py` `fetch_pdb` wraps `cmd.fetch(code, name=obj, async_=0)`; curated 34-code `PDB_POOL` (`pymol/biochemeleon/setup_state.py:78`).
2. **MemProtMD** (`https://memprotmd.bioch.ox.ac.uk`) — `1gzm`/`3gp6` `at.pdb` endpoints in `DEMO_MANIFEST` (`pymol/biochemeleon/setup_state.py:49-56`); stdlib `urllib.request` worker thread, 64KB blocks, water/salt (SOL/NA/CL) stripped in pure Python BEFORE `cmd.load`; dry result cached as `.pdb.gz` in `<cwd>/cache/`.
3. **SASBDB** (`https://www.sasbdb.org`) — `SASDPG4` fit model (`setup_state.py:46`); `_urlopen_with_ssl_fallback()` retries without cert verification on SSL failure; `User-Agent: bioCHEMeleon/1.0` (SASBDB blocks bare urllib UA); `strip=False` (glycan preserved).
- Async drain: main-thread `QTimer.singleShot(100, drain)` polls a `queue.Queue`, updates a MODELESS `QProgressDialog` (`pymol/biochemeleon/__init__.py` `_resolve_large_demo`).

## Data Storage

**Databases:** None. No SQL/NoSQL/ORM in either viewer.

**Files:**
- Bundled demos: `vmd/data/demos/*.pdb` (v2, committed) / `pymol/biochemeleon/data/demos/*.pdb` (v1, committed).
- Setup files: `.bcm` key-value line files (v2, user-chosen via `tk_getSaveFile`, `vmd/gui/setup_tab.tcl:606-623`; format tag `biochemeleon-setup-v2` guards version mismatch) / JSON `.bcm` (v1, `QFileDialog`).
- v1 only: `.bcmz` game archives (`persistence.py` — zip containing `game.pse` + JSON `game.bcm`, magic `BIOCHEMELEON-BCM` v1); fetched-demo cache `<cwd>/cache/*.pdb.gz` + temp `.raw`/`.dry`.
- v2 game-state sidecar: NOT BUILT — VMD `save_state` does not persist `beta`/`user`/`segid`; a custom `.bcm` sidecar is a registered future requirement (`vmd/AGENTS.md`). Until Phase 19 there are no Cleanup/Restart buttons (console-only cleanup).

**Caching:** v2 none (bundled files only). v1: the `<cwd>/cache/` fetched-demo cache.

## Authentication & Identity

None. Local desktop plugins; no accounts, tokens, or API keys. All v1 data sources are public/unauthenticated. `.gitignore` excludes `*.env`, `**/secrets.toml`, `**/auth.json` defensively.

## Monitoring & Observability

**Error tracking:** None (no Sentry/telemetry).
**Logs:**
- v2: `vmdcon -info/-warn/-err` to the VMD console; GUI drivers auto-log to `rep_verify_log.txt` (cwd, open-append + flush per line — `vmd/tests/rep_verify.tcl:71-81`); headless smoke runs tee to root `splice-smoke-run*.log` / `reg-*.log` (gitignored).
- v1: in-game rolling `QTextEdit` log (not persisted); `print`/stderr in headless runs.

## CI/CD & Deployment

**Hosting:** Local desktop only.
**CI:** None. Manual verification ladder: pure-layer suites (WSL) → headless host smokes (Windows, WSL-driven) → GUI auto-driver + human checkpoints (`rep_verify.tcl`, real-mouse picking).
**Install:** v2 = `source vmd/biochemeleon.tcl` / `.vmdrc` / `auto_path`+`package require`; v1 = PyMOL Plugin Manager (package dir or `biochemeleon.zip` fallback, gitignored).

## WSL→Windows Bridge (dev-to-runtime integration)

- `vmd/wsl2win_cp.sh` — stages `vmd/` → `tmp/biochemeleon-vmd/vmd/` so Windows VMD's `[pwd]` resolves to `C:/...`.
- `vmd/lib/demos.tcl:36` `to_vmd_path` — `/mnt/c/...` → `C:/...` (forward slashes; defensive — bundled paths are already script-relative `C:/`).
- `pymol/biochemeleon/demos.py:59` `to_windows_path` — `/mnt/c/...` → `C:\...` (backslashes).
- Headless VMD: `bash -ic "cd tmp/biochemeleon-vmd && vmd -dispdev text -e <script> -eofexit" < /dev/null 2>&1 | tail -50`.
- Headless PyMOL: `cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq <script>" 2>&1 | tail -50`.
- GUI verify drivers (`vmd/tests/rep_verify.tcl`, `vmd/tests/pick_verify.tcl`): the human pastes `source vmd/tests/rep_verify.tcl`, presses `p` once per round, clicks; the driver auto-issues commands and auto-logs state dumps + pick events.

## Webhooks & Callbacks

**Incoming:** None (no server).
**Outgoing:** v2 none. v1: only the urllib GETs to RCSB/MemProtMD/SASBDB.

## Data Attribution

- `vmd/data/demos/SOURCES.md` + repo-root `DATA_SOURCES.md` — RCSB (CC0), MemProtMD (CC-BY 4.0), SASBDB (free with attribution); human-approved in v1 and reused by v2.
- `LICENSE`, `LICENSE_pymol-open-source` — project + PyMOL license attribution.

---

*Integration audit: 2026-09-08*
