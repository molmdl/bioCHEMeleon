# AGENTS.md — v2 VMD 1.9.3 tcl Script

High-signal notes for OpenCode sessions. Read before touching any `vmd/` code. See root `AGENTS.md` for shared/environment concerns, `spec.md`, and `.planning/PROJECT.md` for full project context.

> **Scope:** v2 VMD 1.9.3 tcl script (active milestone). This file is VMD/tcl-specific. For shared concerns (WSL/Windows split, GSD workflow, parallel execution), read root `AGENTS.md` first. For PyMOL/v1 work, read `pymol/AGENTS.md`.

## Environment — VMD specifics (read first; root AGENTS.md has the shared WSL/Windows split)

- **VMD 1.9.3 (November 30, 2016)** — Windows build at `C:\Program Files (x86)\University of Illinois\VMD\`. WSL alias: `vmd` → `vmd.exe`. The install is readable from WSL but **use `vmd-ref/` copies** (gitignored) for reference — do NOT access `/mnt/c/Program Files (x86)/...` directly in plans or code.
- **Tcl 8.5.6** (`info patchlevel` = `8.5.6`; verified three ways: `tcl85.dll`, `info patchlevel`, `scripts/8.5.6/` dir). **Available:** `dict`, `lassign`, `lreverse`, `apply`, `trace add/remove`, `expr **`, `namespace ensemble`. **NOT available (Tcl 8.6):** `try`/`throw`/`finally`/`tailcall`/`coroutine`/`yield`/`lmap` — use `catch`/`error` + `foreach`+`lappend`.
- **Tk 8.5 + ttk** (`tk85.dll`; ttk bundled as `::ttk::*`). Tk loads **only in GUI mode** (`-dispdev win`), NOT in headless `-dispdev text` (`package require Tk` fails in text mode). This is the VMD analog of v1's "PyMOL Qt can't run from WSL" split.
- **Headless VMD from WSL** (the v2 equivalent of v1's `run-conda-pymol.bat -cq`):
  ```bash
  # 1. Write a tcl test script to a Windows-visible path (under /mnt/c/...):
  echo 'puts "VMD version: [vmdinfo version]"; mol new 1k8p.pdb type pdb; puts "atoms: [molinfo top get numatoms]"; exit' > tmp/vmd-test/smoke.tcl
  # 2. Run headlessly (wrap in bash -ic for the alias + < /dev/null to prevent hang):
  bash -ic "vmd -dispdev text -e tmp/vmd-test/smoke.tcl -eofexit" < /dev/null 2>&1 | tail -50
  # 3. Check exit code: 0 = clean; nonzero = crash. Always run from a /mnt/c cwd.
  ```
  This covers ALL pure-`mol`/`atomselect`/`molinfo`/`trace`/`dict`/file logic (the game engine). GUI/Tk/picking-by-real-mouse MUST be human-verified (Tk doesn't load in text mode).
- **VMD reference material:** `vmd-ref/` (gitignored) holds:
  - `ug.pdf` — VMD 1.9.3 User's Guide (full API reference)
  - `plugins/` — 5 curated bundled tcl plugins (`clonerep1.3`, `ramaplot1.1`, `autoionize1.4`, `viewmaster2.6`, `mergestructs1.1`) — read these for extension patterns
  - `scripts/` — 17 VMD core tcl scripts (`vmdinit.tcl`, `save_state.tcl`, `loadplugins.tcl`, `atomselect.tcl`, `materials.dat`, `colordefs.dat`, etc.)
  - `tooltip/` — tklib tooltip.tcl (Tcl/Tk license terms — NOT BSD; reference only, NOT needed per research)
  - **Use `vmd-ref/` paths in plans, not `/mnt/c/Program Files (x86)/...`**

## Commands (run from repo root, or `vmd/` subdir)

```bash
# Syntax-check a tcl file (tclsh is available in WSL):
tclsh vmd/lib/setup_state.tcl  # pure layer should load with no error

# Run pure-layer unit tests via tcltest (tcl's built-in test framework):
tclsh vmd/tests/registry.test  # pure-layer tests, no VMD needed

# Headless VMD smoke test (the v2 engine gate):
bash -ic "vmd -dispdev text -e vmd/smoke/headless_smoke.tcl -eofexit" < /dev/null 2>&1 | tail -50

# Tcl 8.5 gate — MUST return ZERO matches (no 8.6 idioms):
grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/

# Modeless gate — MUST return ZERO matches on main panel (grab blocks viewer):
grep -rnE "grab set" vmd/gui/
# (grab set on transient sub-dialogs IS allowed — mergestructs pattern)
```

## Architecture — module dependency direction is strict (mirrors v1)

```
vmd/lib/setup_state.tcl   (PURE: stdlib tcl — no mol, no tk; unit-testable in WSL via tclsh/tcltest)
      ↑
vmd/lib/demos.tcl          (mol bridge: sources setup_state; uses mol/atomselect)
      ↑
vmd/gui/setup_tab.tcl      (Tk + mol: sources setup_state AND demos)

Phase 15 stack (mutation-safety; vmd/lib/game.tcl is the composition root):
  vmd/lib/registry.tcl     (PURE: stdlib tcl + GAME_REPS from setup_state; unit-testable in WSL)
  vmd/lib/backup.tcl        (mol: snapshot viewpoint+reps+atom-fields; restore)
  vmd/lib/mutation.tcl      (mol: rebuild PDB + reload + sentinel + cleanup)
  vmd/lib/game.tcl          (orchestrator: GameController wires backup+mutation+registry)
```

Never reverse. `setup_state.tcl` must have NO `mol`/`atomselect` and NO `tk`/`toplevel` calls. `registry.tcl` (Phase 15) is ALSO pure (stdlib + `GAME_REPS` from setup_state; no `mol`) — unit-testable in WSL via `tclsh`/`tcltest`. `backup.tcl`/`mutation.tcl` are standalone mol bridges; `game.tcl` is the composition root.

Extension entry point lives in `vmd/biochemeleon.tcl`:
- Entry: `package provide biochemeleon <ver>` + `namespace eval ::BCM::` + `biochemeleon_tk_cb` proc + `vmd_install_extension biochemeleon biochemeleon_tk_cb "Extensions/bioCHEMeleon"` (pattern from `clonerep.tcl:237`, `loadplugins.tcl:114`).
- Re-source guard: `if {$::BCM::loaded} { vmdcon -warn "bioCHEMeleon already loaded"; return }` — `namespace eval` body re-runs on every `source`, re-initializing `variable`s. Guard state with `if {![info exists ::BCM::state(timer)]} { set ::BCM::state(timer) 0 }`.
- Main dialog is modeless: `toplevel .biochemeleon` + `wm deiconify`, NEVER `grab set` on the main panel. Required so the 3D viewer stays interactive for click-to-find.
- GUI-only registration: guard Tk setup with `if [info exists tk_version] { ... }` so headless sourcing (`-dispdev text`) doesn't error on absent Tk commands.

## Tests

- Pure-layer tcl (`setup_state.tcl`, `registry.tcl`) → `tcltest` unit tests in WSL via `tclsh` (no VMD, no Python needed — direct port of v1's `python3.6 -m unittest` pattern).
- mol-coupled code → `vmd/lib/` (backup.tcl, mutation.tcl, etc.), verified by headless VMD smoke test (`vmd -dispdev text -e <script> -eofexit`), NOT tclsh tests.
- GUI/Tk/picking → human-verify checkpoints (Tk doesn't load in text mode — same split as v1's Qt).

## Domain rules (easy to get wrong)

- **VMD CANNOT add atoms to a loaded molecule.** No `pseudoatom` analog, no merge, no in-place insert, no per-atom delete. `mol new atoms N` creates a SEPARATE molecule. The "same molecule" core mechanic is reimplemented via **PDB-rebuild**: write a combined PDB (real + hider atoms with strict column format), `mol delete` original, `mol new <combined.pdb>`. This is the single biggest v1→v2 architectural change.
- **VMD has NO undo** (`info commands undo` → empty). Backup = record original PDB path (`molinfo $molid get filename`) + `mol delete` + `mol new <original>`. There is NO per-atom `remove` — cleanup is always whole-molecule reload.
- **VMD has NO global atom `id`** (no `id`/`atomid`/`uid` attribute). Identity = `(molid, index)`. Molids are monotonic, never reused. `index` is stable for a molecule's lifetime (atoms can't be added/deleted) but **molid changes on reload** → registry must rebuild from sentinels after cleanup/restart.
- **Hider sentinel: `resname=GAM` + `beta=-999` + `segid=GAME`.** Set in-place via `atomselect` after load (robust against PDB column bugs). Selector: `resname GAM and beta < 0`. NEVER use `beta -999` as exact selector (use comparison `beta < 0`). `resname` is 3 chars (PDB resname is 3 cols — a 4-char "GAME" is silently dropped).
- **`save_state` does NOT persist `beta`/`user`/`segid` or any script-modified data** (`save_state.tcl:39-46`). It reloads original files by path. Must use a custom `.bcm` sidecar for game state (registry, timer, found-status) — same pattern as v1's `.bcm`/`.bcmz`. No `json` package in VMD 1.9.3 → hand-roll JSON with tcl 8.5 `dict`.
- **GAME_REPS** = `Lines, VDW, Licorice, CPK, Cartoon, NewCartoon, Trace, Tube, Points, DynamicBonds` (10 viable reps, research-driven). Surface/volumetric reps (QuickSurf, Surf, MSMS, VolumeSlice, Isosurface, etc.) are anti-features — don't fit discrete-atom blend-in mechanic.
- **Reps have STABLE NAMES** (`mol repname $m $i` → `rep0`, `rep1`, ...). Track game reps by NAME, never by index (`mol delrep` renumbers — always delete index 0 in a loop, per `clonerep.tcl:92-96`).
- **Rep management is command-based** (`mol addrep`, `mol modstyle`, `mol delrep`), NOT GUI-layered like PyMOL. VMD default is Lines only. Must set up reps via commands before the game can use them.
- **Random total distribution across all reps from start** (v1.1 quick-008 fix baked in — never default to all-spheres when only a total count is set).
- WSL→VMD path guard: `to_vmd_path()` converts `/mnt/c/...` → `C:/...` (forward slashes, NOT backslashes). Windows VMD cannot resolve `/mnt/c/`, `/tmp/`, or `~/`.

### Picking mechanism (LOCKED — GUI-verified 2026-08-30 plan 16-12; first-click quirk verified 2026-09-03 plans 16-16/16-17)

**CONFIRMED (a complete round was WON through this path in a real GUI session, 2026-08-30 — see `.planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md`):**

- Delivery path = `trace add variable ::vmd_pick_event write <proc>` with a `{args}` proc (receives `name1 name2 op` — a positional signature makes VMD's own write FAIL and loses the pick) reading globals `vmd_pick_atom` (0-based index — the registry key) + `vmd_pick_mol` (the molid), per UG Table 9.4 + shipped `www.tcl`. A full round was won through it (win box, timer frozen 5:14, remaining 0).
- Forbidden forms unchanged: `mouse mode 4 2` = USERPOINT (UG table stale vs the 1.9.3 binary); `mouse mode pick 0` = QUERY — never the game mode; only `mouse mode pick 2` engages atom picking. Reliance on `::vmd_pick_atom_callbacks` is FORBIDDEN — phantom, falsified in-GUI 2026-08-30 (registered proc never fired on any click).
- **Hidden reps cannot be picked** (UG node140 — GUI-confirmed: click at a hidden hider picked the real atom behind it with no find; after re-show the find worked). Found-marking must never hide a rep containing unfound hiders.
- Pick labels are ALWAYS created on labelatom clicks (labelpoll fallback premise — GUI-confirmed: every click logged `Added new Atoms label ...`; the game's auto-clean left count at baseline).
- **PickBridge** = `vmd/lib/pick_bridge.tcl` (trace primary + dormant labelpoll fallback via `mechanism`; save/restore of the user's `vmd_mouse_mode`/`submode`; baseline-guarded label hygiene).
- **Pick and rotate are MUTUALLY EXCLUSIVE mouse modes in VMD** (unlike PyMOL where picking coexisted with middle-drag rotate). Player toggles between them (hotkey `r` = rotate, `1` = pick atom, or the in-panel Rotate/Pick toggle).

**FIRST-CLICK QUIRK (known behavior, verified 2026-09-03 — 16-16 re-verify session + 16-17 headless probe; caveat CLOSED):**

- One keyboard `p` press per round arms real pick delivery for the whole round; clicks before it land in labelatom (labels ARE added, the in-game count never changes). Pasted `mouse mode pick|pick 0|pick 2` never arms delivery; a fresh VMD restart also clears the quirk (16-12: picks worked with no `p` after restart). The arming difference is the DISPATCH PATH (VMD's `user add key` hotkey binding — hotkeys.tcl:112 `p` = `mouse mode pick` — vs a pasted text command), NOT the submode value: the 16-17 headless probe maps `pick 2` = labelatom/2 (the shipped "# atom" mode, hotkeys.tcl:118) vs `pick 0` = query/0, and the GUI record rules the wrong-submode fix out (the 16-12 round was WON on pick 2; pasted query never armed). VMD 1.9.3 has NO mode-query form — the `mouse` usage text is the only introspection.
- `mouse callback` A/B DOWNGRADED to non-blocking (2026-09-03): finds fired in the untouched default callback state; the `User Pick:` console echo is callback-state-independent. NO `mouse callback` commands in pick_bridge — mechanism byte-untouched (16-17 branch c2). Player guidance: if finds don't register, press `p` (or `1`) once on the VMD display.
- Panel checkbox desync (known behavior, minor UX): pressing hotkey `r` switches VMD to rotate but the Game-tab checkbox stays "Pick" — pick_bridge does not observe hotkey-driven mode changes.
- Do NOT treat a text-mode smoke PASS as proof of C-side firing — text mode cannot fire a real pick (that is what the GUI verification sessions are for).

**Phase-19 note:** the Game tab has NO Cleanup/Restart buttons yet (Phase 19 scope); until then cleanup is console-only. `start_game` auto-restarts via the active-game guard (landed 16-13, headless-proven 16-15, GUI-confirmed 16-16): a double-Start cleans the active round and starts fresh on the caller's settings — it can no longer stack game generations (the 2026-08-30 561-atom / `Segments: 3` defect is fixed). Setup-tab "Reset" resets setup fields only — it does NOT clear hiders (expectation mismatch, registered for gap closure).

### Mutation-safety rules (Phase 15)

- **Backup = record original PDB path + viewpoint + rep list.** On Start: save `molinfo $molid get filename`, viewpoint, and per-rep state. On Cleanup/Restart: `mol delete $molid; set molid [mol new $original_path]` + re-apply saved reps + restore viewpoint.
- **Hider generation = PDB-rebuild.** Read original PDB, splice hider atoms into ATOM/HETATM records with sentinel fields, write combined PDB to temp file, `mol delete` original, `mol new <combined.pdb>`. Hiders and originals are genuinely one molecule.
- **Sentinel set via `atomselect` after load** (robust against PDB column alignment bugs): `set sel [atomselect $molid "resname GAM"]; $sel set beta -999; $sel set segid GAME; $sel delete`.
- **Registry keys on atom `index`** (stable within a molid's lifetime). Reconstruct from sentinels on reload: `atomselect $molid "resname GAM and beta < 0"` → read each atom's `index`.
- **`reconstruct_from_sentinels` uses dependency injection** — the atomselect iterate fn is passed as a parameter so `registry.tcl` stays pure (no `mol`/`atomselect`); `game.tcl` injects the real fn.
- **Always `$sel delete`** after use — `atomselect` objects leak if not deleted. A dangling `atomselect` on a deleted molecule returns **stale data silently** (no error). Trace `vmd_initialize_structure` to invalidate selections when molecules disappear (ramaplot pattern, `ramaplot.tcl:220,267`).
- **Never cache a selection across `mol delete`/reload** — molid changes; the old selection silently returns stale data.

### Tcl 8.5 gotchas

- **No `lmap`** — use `foreach` + `lappend` (or `dict for`). `lassign` IS available (built-in).
- **No `try`/`finally`** — use `catch {script} msg; set code $::errorCode` (the `autoionize.tcl:81-88` pattern). Always restore state in the `catch` branch.
- **Variable scoping:** inside a proc, declare `variable name` (namespace vars) or `global name` (global vars) before use. Undeclared access → "no such variable" (the #1 tcl beginner trap).
- **List vs string:** Tcl lists are strings; `[llength $seltext]` on `"name CA and protein"` is wrong. Use `[list ...]` to build lists; quote selection strings with `{}` (braces = literal).
- **`expr` must be braced** `[expr {$a + $b}]` — unbraced is slower + injection risk.
- **`vwait varname`** re-enters the event loop — never `vwait` a var you set in the same proc (infinite loop); use `after` instead.
- **`namespace eval` body re-runs on every `source`** — re-initializes `variable`s. Guard state with `info exists`.

## Dependencies & attribution

- Assume only what VMD 1.9.3 ships (Tcl/Tk 8.5 + ttk + built-in tcl plugins). Zero external deps confirmed. `tooltip.tcl` is NOT needed — write a ~30-line pure-Tk helper if tooltips are wanted.
- Any additional tcl lib must be user-approved and vendored under `vmd/3rd_party_lib/` (git-ignored) with its license noted. `tooltip.tcl` uses the Tcl/Tk license terms (permissive but NOT BSD — copy `license.terms` verbatim if vendoring).
- Demo PDBs reused from v1 (`pymol/biochemeleon/data/demos/`) — PDBs are viewer-agnostic. Sources in `SOURCES.md` (human-approved in v1: RCSB CC0, MemProtMD CC-BY 4.0, SASBDB free with attribution).

## Performance (large molecules — 1GZM/3GP6 have 100k+ atoms)

- **Never `$all_sel get {x y z}` on a large molecule** — builds a huge Tcl list. Use `molinfo $m get numatoms` for counts; narrow `atomselect "name CA"` for placement candidates.
- **Never block the event loop >200ms** — Tcl is single-threaded. Use `after 0 ::gen_chunk` for cooperative chunking on long generators (the v2 equivalent of v1's QTimer + worker queue).
- **Strip water/salt from large demos before bundling** (same as v1).
- Budget: Generate on 3GP6 < 30s; pick latency < 200ms.

## Git-ignored (don't rely on / don't commit)

`vmd-ref/` (VMD reference material — UG PDF, bundled tcl plugins, core scripts, tklib tooltip), `vmd/3rd_party_lib/` (v2 vendored libs), `tmp/` (headless test artifacts, probe scripts).
