# Pitfalls Research — bioCHEMeleon v2 (VMD 1.9.3 port)

**Domain:** VMD 1.9.3 sourced-tcl extension — interactive "hide-and-seek" game ported from the v1 PyMOL 2.5.0 plugin. The game inserts "hider" atoms into a loaded molecule, then detects atom picks in the OpenGL viewer.
**Researched:** 2026-08-22
**Confidence:** **HIGH** for atom-identity / no-undo / no-merge / no-atom-deletion / save_state / WSL-path / Tcl-8.5 / rep-naming / pick-via-labels (all verified by running headless VMD 1.9.3 + reading the VMD-install source `save_state.tcl`, `vmdinit.tcl`, `loadplugins.tcl`, `hotkeys.tcl`, and 4 bundled plugins). **MEDIUM** for Tk modal/grab blocking the 3D viewer and the exact `mouse callback` pick-handler contract (text mode cannot drive the GUI / fire a real pick — needs one human-in-GUI verification).

---

## How to read this file

Each critical pitfall has six fields:
- **What goes wrong** — the failure mode
- **Why it happens** — root cause (with runtime evidence where verified)
- **How to avoid** — actionable prevention (specific tcl commands / patterns)
- **Warning signs** — early detection
- **VMD-specific or v1 carry-over** — whether this is new to VMD or ports from v1
- **Phase to address** — which roadmap phase must prevent it (v2 phase names mirror v1: **setup** / **generator** / **game-loop** / **save-load** / **demos**)

Runtime evidence is cited as `[RUN: <test>]` referring to headless VMD probes in `tmp/vmd-test/` (`pitfalls_out.txt`, `final_out.txt`, probe outputs). VMD-source evidence is cited as `[SRC: <file>:<line>]`.

---

## v1 → VMD carry-over matrix (read first)

Every v1 pitfall was assessed for VMD applicability. **Five carry over (3 with a VMD-specific twist), four do not apply, three are brand-new VMD pitfalls.** This matrix is the single most important table in this file.

| # | v1 pitfall (PyMOL) | VMD status | Detail |
|---|--------------------|------------|--------|
| 1 | Tkinter/Pmw GUI (deprecated in PyMOL 2.x) | **DOES NOT APPLY** | VMD's native toolkit IS Tk 8.5 — there is no "deprecated layer" to avoid. The new VMD-specific version is the Tk modal/grab pitfall (see Pitfall 4). |
| 2 | Hiders in a separate object | **CARRIES OVER — HARDER** | v1 inserted hiders into the existing object via `cmd.pseudoatom(object=existing)`. **VMD cannot add atoms to a loaded molecule at all** (no merge, no in-place insert) — see Pitfall 1. The "same molecule" mechanic must be reimplemented via PDB pre-processing or graphics overlays. |
| 3 | Unstable hider identity (atom `index` shifts on deletion) | **DOES NOT APPLY (different shape)** | VMD's `index` is stable *because atoms cannot be deleted from a loaded molecule* (`[RUN: pitfalls_out.txt:48-50]`). VMD has **no global atom `id`** (`[RUN: pitfalls_out.txt:161-163]`); identity = `(molid, index)`. Molids are monotonic and never reused (`[RUN: final_out.txt:60-70]`). The registry must rebuild from sentinels after a reload because the molid changes — see Pitfall 3. |
| 4 | No atom-click callback | **CARRIES OVER** | VMD's `mouse callback on` + `label list Atoms` is the equivalent of v1's `load_callback` polling `pk1`. Same polling pattern, different API — see Pitfall 5. |
| 5 | Thread safety (QTimer on main thread) | **DOES NOT APPLY** | VMD's Tcl interpreter is single-threaded; there is no `QTimer`/`threading` analogue. Timers use Tcl `after` (main thread by definition). No deadlock risk — see Pitfall 6. |
| 6 | `.pse` doesn't save plugin Python state | **CARRIES OVER — WORSE** | VMD `save_state` is a tcl *replay script* that reloads original files. It explicitly does **not** restore `beta`/`segid` or "any data produced or modified by scripts" (`[SRC: save_state.tcl:39-46]`). Atom mods are lost on reload — see Pitfall 7. |
| 7 | Cartoon hiders invisible (need polymer trace) | **CARRIES OVER** | VMD `Cartoon`/`NewCartoon`/`Ribbons` are also polymer-trace reps. Same geometry requirement as v1 Pitfall 8 — see Pitfall 9. |
| 8 | Cleanup over-matches (sentinel filter deletes real atoms) | **DOES NOT APPLY (different shape)** | VMD cannot delete individual atoms from a loaded molecule, so there is no `cmd.remove`-equivalent to over-match. Cleanup = `mol delete` whole molecule + reload original PDB. The sentinel now identifies hiders for *marking*, not for `remove` — see Pitfall 8. |
| 9 | No undo | **CARRIES OVER** | VMD 1.9.3 has **no `undo` command** (`[RUN: pitfalls_out.txt:19-23]`). Backup = keep the original PDB path + `mol delete` + reload. See Pitfall 2. |
| 10 | WSL/Windows path mismatch | **CARRIES OVER (different conversion)** | Windows VMD cannot resolve `/mnt/c/`, `/tmp/`, or `~/` — needs `C:/...` (forward slashes). `[RUN: pitfalls_out.txt:138-145]`. See Pitfall 10. |
| 11 | Large-molecule OOM (`get_model`) | **PARTIALLY CARRIES OVER** | VMD `atomselect $sel get` is the streaming equivalent of `cmd.iterate` (no full `get_model`-style copy). But `$sel get` on all atoms still builds a Tcl list; `molinfo get numatoms` is lighter. See Pitfall 11. |
| 12 | Demo licensing/attribution | **CARRIES OVER unchanged** | Same PDBs (1znf, 1GZM, 3GP6, etc.) → same CC0/RCSB/MemProtMD licenses already verified in v1 `PITFALLS.md`. No re-research needed. |

**Brand-new VMD pitfalls (no v1 analogue):** Tcl 8.5 language limits (Pitfall 12), extension-loading / re-source guards (Pitfall 13), VMD 1.9.3 age/instability (Pitfall 14).

---

## Critical Pitfalls

### Pitfall 1: VMD cannot add atoms to a loaded molecule — the "same object" core mechanic breaks

**What goes wrong:**
The port reaches for a v1-style `cmd.pseudoatom(object=existing)` analogue to insert hider atoms into the loaded target molecule. **No such API exists in VMD.** The developer tries `mol new atoms N` (creates a *separate* empty molecule), or `atomselect $sel set` (only modifies *existing* atoms, never adds), or searches for a merge/combine command (there is none). Hiders end up in a *separate* molecule, and the player defeats the game in one keystroke by hiding that molecule (`mol off <hider_molid>`). The whole "they live in the same molecule" core mechanic collapses — exactly v1 Pitfall 2, but for a deeper reason: in PyMOL the fix was "use the right verb"; in VMD **there is no verb**.

**Why it happens:**
Runtime-verified `[RUN: pitfalls_out.txt:112-116]`:
- `info commands *merg*` → empty (no merge command)
- `info commands *combin*` → empty (no combine command)
- `mol new atoms 1` works but creates a **new, separate** molecule (`molid` increments).
- `atomselect $sel set` only mutates existing atom fields; it cannot grow the atom list.
- The `mol` command's help (`[RUN: pitfalls_out.txt:52-110]`) lists only `new`, `addfile`, `delete <molid>` (whole molecule), `rename` — **no per-atom add/delete**.

VMD's molecule is a read-only-topology view of loaded file data. To change the atom set you must either (a) load a different file that already has the atoms, or (b) rebuild via `psfgen` (heavy; requires topology files — `autoionize.tcl:14` does `package require psfgen`).

**How to avoid — pick ONE of these strategies and commit to it:**

1. **PDB pre-processing (RECOMMENDED for the port).** Read the user's PDB in pure Tcl (or write a tiny PDB reader), splice hider atoms into the ATOM/HETATM records with sentinel fields (`segid GAME`, `beta -999`), write a modified PDB to a temp file, and `mol new <modified.pdb>`. The hiders and originals are now genuinely one molecule. "Cleanup" = `mol delete` + `mol new <original.pdb>`. This preserves the v1 mechanic and atom pickability. The sentinel is set at write-time (in the PDB text), not via `atomselect set` post-load (which `save_state` would lose — Pitfall 7).
2. **Graphics overlays (PARTIAL — breaks picking).** `graphics $mol sphere {x y z}` draws on the same molecule that has atoms (`[RUN: pitfalls_out.txt:127-128]` confirms graphics on an atom-molecule succeed). But graphics primitives are **not pickable atoms** — they don't appear in `atomselect` or `label add Atoms`. Only viable if the click mechanic is rewritten to pick *positions* (ray-trace against graphics), which is far harder than atom picking. **Not recommended.**
3. **psfgen rebuild (AVOID for this project).** Works but needs CHARMM topology files and a full system rebuild — overkill, adds a heavy dependency, and `psfgen` is not in the "assume only what VMD ships" budget without explicit approval (per `AGENTS.md` Dependencies).

**Warning signs:**
- After "Generate", `molinfo list` shows a new molid (hiders are a separate molecule).
- `atomselect <hider_mol> all` returns hiders but `atomselect <target_mol> all` does not.
- The player can toggle hiders off via the VMD molecule list.

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 2, but the root cause is structural (no API) rather than API-misuse. This is the **single biggest porting risk** — it reshapes the generator architecture.

**Phase to address:** **generator** (architectural decision must be locked before any generator code; retrofitting is a rewrite). Document the chosen strategy in **setup**.

---

### Pitfall 2: No undo, no per-atom delete — backup means "reload the original PDB"

**What goes wrong:**
A generator bug places hiders wrong, or the user clicks "Cleanup" expecting a recoverable action, or a rep edit goes bad. The developer reaches for an `undo` command or a per-atom `remove`. Neither exists. The molecule is in a bad state and the only recovery is to delete the whole molecule and reload.

**Why it happens:**
- `[RUN: pitfalls_out.txt:19-23]`: `info commands undo` → empty; `undo` / `vmd_undo` → "invalid command name".
- `[RUN: pitfalls_out.txt:47-50]`: `atomselect $sel delete` deletes the **selection object**, not atoms (`numatoms` stays 424). `mol delete atoms` → usage error (no such subcommand). The `mol` help confirms only `delete <molid>` (whole molecule) exists.
- v1 Pitfall 10 carried over exactly: PyMOL Open Source `undocontext` was a no-op stub; VMD has no undo at all.

**How to avoid:**
- **Snapshot = keep the original PDB path + a clean reload helper.** On "Start", record `[molinfo $molid get filename]` (the original file) and the original rep state. On "Cleanup"/"Restart": `mol delete $molid; set molid [mol new $original_path]` then re-apply original reps. This replaces v1's `cmd.create('_bchm_backup', target)` snapshot.
- **For the pre-processed-PDB strategy (Pitfall 1):** keep BOTH the original PDB path AND the generated (hider-spliced) PDB path. Cleanup reloads the original; "Save game" keeps the generated one.
- Wrap generator mutations in `catch` (Tcl 8.5 has no `try` — Pitfall 12); on error, reload the original and surface a clear message via `vmdcon -err` or `tk_messageBox`.
- **Never** assume a partial mutation is recoverable in-place — always reload from file.

**Warning signs:**
- A "Restart" button that doesn't restore the original (because no path was recorded).
- After a generator `catch` error, the molecule is half-mutated with no clean state.
- Code calls a non-existent `mol delete atoms` or `undo`.

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 10 (no undo). The recovery mechanism is *simpler* in VMD (reload file) but *less granular* (whole-molecule only, no backup-object side-by-side).

**Phase to address:** **setup** (the reload helper + path recording) and **save-load** (Restart logic). Generator/game-loop must route all destructive ops through the helper.

---

### Pitfall 3: VMD has no global atom `id` — registry must key on `(molid, index)` and rebuild after reload

**What goes wrong:**
The port copies v1's registry design (`key = atom id`) verbatim. But VMD has **no `id`/`atomid`/`uid` attribute** (`[RUN: pitfalls_out.txt:161-163]`: all three → "NOT AVAILABLE"). The registry keys on a non-existent field and silently fails, or keys on `index` and breaks after a cleanup-reload (because the reload gets a *new molid*).

**Why it happens:**
- `[RUN: pitfalls_out.txt:159-163]`: available atom attributes are `index` (0-based per-molecule ordinal), `serial` (1-based, from PDB SERIAL column), `residue` (residue index), `resid`, `segid`/`segname`, `beta`, etc. — **no global unique id**.
- `[RUN: final_out.txt:60-70]`: molids are **monotonic increasing and never reused** (deleted molid 1 was not reused; next was 3). So `molid` is stable for a loaded molecule's lifetime but **changes on reload**.
- `index` is stable for a loaded molecule's lifetime *because atoms can't be added/deleted* (Pitfall 1/2). So v1's "index shifts on deletion" problem **does not arise** — but "molid changes on reload" is the new analogue.
- `[RUN: final_out.txt:91-95]`: a dangling `atomselect` on a deleted molecule returns **stale data silently** (`$s num` still 424 after `mol delete`) — so caching selections across a reload is a silent-corruption trap.

**How to avoid:**
- **Primary hider identity = `(molid, index)`**, captured at generation. Both are stable for the molecule's lifetime.
- **Sentinel for cross-reload reconstruction** = `segid GAME` + `beta -999` (verified settable: `[RUN: pitfalls_out.txt:166-168]` shows `segid=GAME`, `beta=-999.0` round-trip via `atomselect`). On load, rebuild the registry by `atomselect <molid> "segid GAME and beta < 0"` then reading each atom's `index`. This is the direct port of v1's `reconstruct_from_sentinels` — same sentinel, same selector `beta < 0` (VMD also uses comparison, not exact — `[RUN: pitfalls_out.txt:170-171]` `beta -999` exact worked here, but prefer `beta < 0` for safety/consistency with v1).
- **Selection hygiene:** delete every `atomselect` before any `mol delete`; never cache a selection across a reload. Trace `vmd_initialize_structure` (the ramaplot pattern, `ramaplot.tcl:220,267`) to invalidate selections when molecules disappear.
- **`serial` is NOT a stable id:** it comes from the PDB file and can collide/duplicate across residues; use it only as a debug aid, never as a registry key.

**Warning signs:**
- Registry lookups return "no such atom" after a Cleanup/Restart.
- `atomselect $old_molid ...` returns stale data after the molecule was deleted (silent, no error).
- Two hiders answer to the same `serial`.

**VMD-specific or v1 carry-over:** v1 Pitfall 4 *reshaped*. The instability moved from "index shifts on delete" (PyMOL) to "molid changes on reload" (VMD). Sentinel-based reconstruction still applies — this is good news, v1's `reconstruct_from_sentinels` design ports cleanly.

**Phase to address:** **generator** (registry design) + **save-load** (sentinel reconstruction after reload) + **game-loop** (selection hygiene).

---

### Pitfall 4: Tk modal `grab` on the main game panel blocks the 3D viewer (modeless required)

**What goes wrong:**
The game panel is built with `grab set $w` (modal) or `tkwait` on the main toplevel. The 3D viewer stops accepting mouse input — the player cannot pick atoms while the panel is open. The click-to-find loop is dead. This is the exact v1 Pitfall 1 failure mode, but in VMD the cause is Tk `grab`, not PyQt `exec_()`.

**Why it happens:**
- VMD's GUI is Tk 8.5 (`[RUN: probe]` `tcl_version=8.5`, `patchlevel=8.5.6`; install ships `tk85.dll`). `grab set` redirects ALL pointer events to one window — the OpenGL viewer gets nothing.
- v1's "use Qt, never `exec_()`" rule becomes VMD's "use a modeless `toplevel`, never `grab set` on the main panel."
- **Evidence this is a real, known pattern:** the bundled plugins confirm the convention — main windows use `toplevel` + `wm deiconify` (re-show) with **no grab** (`ramaplot.tcl:130`, `viewmaster.tcl:70`, `clonerep.tcl:168`). `grab set` appears only ONCE, on a *transient sub-dialog* forcing a molecule pick (`mergestructs.tcl:138` `grab set ".ibselectmol"`), never on a main plugin window.
- `[SRC: vmdinit.tcl:331-336]`: VMD itself does `wm withdraw .` (hides the root Tk window) and titles it "VMD Tk window" — plugins create their own `toplevel .name`.
- `[SRC: vmdinit.tcl:342-380]`: `vmd_tkmenu_cb` integrates Tk windows with VMD's Extensions menu (WM_DELETE_WINDOW → `menu $name off`).

**How to avoid:**
- Main game panel: `toplevel .biochemeleon` + `wm deiconify` (singleton re-show pattern: `if [winfo exists .biochemeleon] { wm deiconify $w; return }` — the `ramaplot.tcl:125-128` / `viewmaster.tcl:66-69` pattern).
- **Never** `grab set` on the main panel. Short error/confirm dialogs MAY use `tk_messageBox` (modal, used by every bundled plugin — acceptable because they're brief).
- If a forced sub-interaction is needed (e.g. "pick a molecule to start"), `grab set` on a *transient* child toplevel and `grab release` when done (the `mergestructs` pattern) — never on the main panel.
- Register the window with VMD via the `_tk_cb` convention (Pitfall 13) so the Extensions menu tracks its open/close state.
- **MEDIUM-confidence flag:** whether `grab set` on the main panel *fully* blocks the OpenGL viewer in VMD 1.9.3 (vs. just blocking other Tk windows) needs one human-in-GUI verification. v1 PyMOL's `exec_()` definitively blocked the viewer; VMD's `grab` semantics should be assumed identical (block) until verified.

**Warning signs:**
- The 3D viewer becomes unclickable while the game panel is open.
- `grab set $mainpanel` appears anywhere in the code.
- The game works when the panel is closed but not when open.

**VMD-specific or v1 carry-over:** v1 Pitfall 1 *reshaped* — the deprecated-Tkinter cause is gone (Tk is native in VMD), but the modal-blocks-viewer failure mode is identical and the prevention (modeless main window) is identical.

**Phase to address:** **setup** (the first GUI architectural decision; retrofitting is a rewrite).

---

### Pitfall 5: No direct "atom clicked" callback — must poll `label list Atoms` / trace `vmd_pick_*`

**What goes wrong:**
The game loop expects an `on_atom_clicked` callback. None arrives. Either nothing happens on click, or every drag-to-rotate fires a pick, or the pick only registers in one specific mouse mode, or stale labels from a previous session are read as new picks.

**Why it happens:**
VMD does not expose a generic "atom clicked" event to tcl plugins. Picking is a **mouse mode** (`mouse mode pick` / `mouse mode labelatom`) that, on click, creates a **label** (`label add Atoms <molid>/<atomindex>`). The plugin must detect the new label. Runtime-verified:
- `[RUN: final_out.txt:36-49]`: `vmd_pick_atom`, `vmd_pick_mol`, `vmd_pick_atominfo` are **all ABSENT** until a real GUI pick fires (text mode can't trigger them). `vmd_frame` / `vmd_molecule` / `vmd_initialize_structure` globals DO exist (these are the trace targets ramaplot uses).
- `[RUN: final_out.txt:50-59]`: `label add Atoms $m/0` works and appends to `label list Atoms` as `{{molid atomindex} value showstate}`. `label delete Atoms 0` removes by label-index (the list shifts).
- `[RUN: mouse-probe]`: `mouse callback [on|off]` exists — this enables VMD's pick callback (populates the `vmd_pick_*` globals on pick). `mouse mode` submodes include `pick`, `labelatom`, `query`, `center`.
- `[SRC: hotkeys.tcl:109-140]`: hotkeys `r/t/s/p` → rotate/translate/scale/pick; `0`-`9`,`%^&` → `mouse mode pick 0..13` (pick submodes: 0=atom, etc.).

**How to avoid — pick one strategy and document it:**
1. **Trace the pick globals (RECOMMENDED if `mouse callback on` populates them in GUI mode).** On "Start": save `$vmd_mouse_mode`; `mouse mode pick 0` (pick atom); `mouse callback on`; `trace add variable vmd_pick_atominfo write ::BioChm::on_pick`. In `on_pick`, read the picked `(molid, index)`, look up the hider registry, mark found, `label delete` to clear. On "Stop": `mouse callback off`; restore `$vmd_mouse_mode`.
2. **Poll `label list Atoms`** (fallback if the trace contract is unreliable). A `trace add variable vmd_frame w` (ramaplot's per-frame hook) or an `after 200` timer checks `label list Atoms` for new entries vs. a cached last-seen list. Clear processed labels with `label delete Atoms <idx>`.
3. **No raw mouse events for click-vs-drag.** VMD gives no mouse-down/up. Disambiguation is *implicit*: in `pick` mode a click produces a label; a drag does nothing (drag-rotate only happens in `rotate` mode). **UX consequence:** in pick mode the player cannot rotate the view with left-drag — they must toggle to rotate mode (hotkey `r`) and back to pick (`0`). This is a real usability difference from v1 (where PyMOL picking coexisted with middle-drag rotate). Provide an in-panel "Rotate/Pick" toggle and document it.

**Warning signs:**
- Clicking an atom does nothing (wrong mouse mode, or callback off).
- Rotating the view spuriously "finds" hiders (wrong mode active).
- The same click fires multiple times (stale label not cleared).
- Works on the dev's machine but not a fresh VMD (prior mouse mode not restored).

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 5 (no direct callback; polling pattern). The API differs (`mouse callback` + `label list` vs `load_callback` + `pk1`) but the architecture is the same. **New VMD-specific twist:** pick and rotate are mutually exclusive mouse modes — v1 could do both simultaneously.

**Phase to address:** **game-loop** (mouse-mode management + pick detection), with the pick/rotate UX documented in **setup**.

---

### Pitfall 6: No threads, no `QTimer` — timers are Tcl `after` (single-threaded, safe but blocking-prone)

**What goes wrong:**
The port copies v1's `QTimer` timer pattern, or a developer assumes VMD needs thread-safety guards. Either the code needlessly complicates with non-existent threading primitives, or a long-running generator freezes the GUI because Tcl's event loop is blocked.

**Why it happens:**
- VMD's Tcl interpreter is **single-threaded**. `[RUN: probe]` `worker?` → empty (no worker-thread command). There is no `QTimer`/`threading` analogue and **no deadlock risk** — v1 Pitfall 6 (thread-safety) simply does not apply.
- The flip side: a long synchronous tcl proc (e.g. a 100k-atom generator loop) **blocks the VMD event loop** — the GUI freezes, the 3D viewer stops rendering, `after` timers don't fire. There is no "background thread" escape hatch.

**How to avoid:**
- **Timer:** use `after 1000 ::BioChm::tick` (reschedule itself at the end of `tick`) for a 1 Hz countdown. This is the direct equivalent of v1's main-thread `QTimer`. No locks needed.
- **Long generator:** chunk the work and yield to the event loop between chunks: `after 0 ::BioChm::gen_chunk` per chunk (cooperative multitasking). Update a modeless progress label between chunks. Do NOT run a 30-second synchronous loop.
- **Never** call `vmdcon`/`update` from a "thread" — there are no threads. All code runs on the main thread by definition.
- **Golden rule simplifies to:** "don't block the event loop for more than ~200 ms." Use `after 0` chunking for anything longer.

**Warning signs:**
- VMD GUI freezes during "Generate" (synchronous loop too long).
- The timer stops ticking during a generator run (event loop blocked).
- Code references `thread`, `QTimer`, or `vwait` in a way that deadlocks (a bare `vwait var` inside a proc that's supposed to set `var` will hang — `vwait` re-enters the event loop and waits).

**VMD-specific or v1 carry-over:** v1 Pitfall 6 **DOES NOT APPLY** (no threads). This is a *simplification* — remove all thread-safety machinery. But the blocking risk is the new VMD-specific concern.

**Phase to address:** **game-loop** (timer) + **generator** (chunked generation for large molecules).

---

### Pitfall 7: `save_state` reloads original files — atom mods (`beta`/`segid`) and game state are LOST

**What goes wrong:**
"Save game" calls `save_state game.vmd`. On reload (`vmd -e game.vmd`), the hiders' `segid GAME` / `beta -999` sentinels are GONE (original PDB reloaded with original fields), the timer/found-count/registry are gone, and the game resumes inconsistent — hider atoms may be present (if spliced into the PDB) but unrecognizable to the rebuilt registry because their sentinel fields were reset to the PDB's values.

**Why it happens:**
`save_state` is a **tcl replay script**, not a binary snapshot. `[SRC: save_state.tcl:144-269]`: it writes `mol new [lindex $files 0] type [lindex $types 0] ... waitfor all` — it **reloads the original file by path**. The authoritative comment `[SRC: save_state.tcl:39-46]` states explicitly what it does NOT restore:
> `XXX It doesn't currently restore:`
> `  User provided data fields such as "user", "beta", "mol volume", etc.`
> `  Any data produced or modified by scripts, even atom positions etc`

Runtime-confirmed: `[RUN: pitfalls_out.txt:129-137]` — after setting `segid GAME`/`beta -999` on an atom and `save_state`, the session file mentioned `GAME` only **once**, as a `{color Segname {GAME} red}` color definition — **not** as our atom's segid. `-999` appeared **zero** times. The atom mod was not saved.

`save_state` DOES save: graphics objects (`[SRC: save_state.tcl:197-199]` `graphics $mol info $g`), reps, viewpoints, materials, colors, labels, atomselect macros. It does NOT save arbitrary tcl variables (our game state).

**How to avoid:**
- **Treat `save_state` as "geometry + view save" and a sidecar `.bcm` (JSON-like) as "game state save"** — the direct port of v1's `.pse` + `.json` sidecar pattern (v1 Pitfall 7). Write both on Save, read both on Load.
- **For the sentinel to survive reload, the hiders must be IN the loaded file, not added via `atomselect set` post-load.** This forces the PDB pre-processing strategy (Pitfall 1): splice hiders (with `segid GAME`/`beta -999`) into a generated PDB, load THAT. `save_state` reloads the generated PDB → sentinels survive (they're in the file text).
- **On Load:** open the `.vmd` (reloads the generated PDB with hiders + sentinels intact), then rebuild the registry from sentinels (`atomselect <molid> "segid GAME and beta < 0"`) — the `.bcm` sidecar is matched to it by `index`. Any hider in the PDB not in the `.bcm` is unrestored.
- **Game state (timer, found-set, difficulty)** goes ONLY in the `.bcm` sidecar — `save_state` cannot carry it.
- **Path-fragility:** `save_state` stores absolute file paths (`[RUN: pitfalls_out.txt:131]` the session had the full `C:/Users/.../1znf.pdb`). If the PDB moves, reload breaks. Bundle demos relative to a known dir and/or write the generated PDB next to the `.vmd`.
- **Rep is NOT in the sentinel** (same as v1 Open Risk 6) — the `.bcm` sidecar reconciles each hider's target rep.

**Warning signs:**
- Save → quit → relaunch → Load: timer and found-count are zero.
- After Load, `atomselect <molid> "segid GAME"` returns 0 atoms (sentinels lost — atom mods were used instead of file splicing).
- Loading a `.vmd` fails with "file not found" because the PDB path moved.

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 7 and is **WORSE** — PyMOL `.pse` at least saved atom properties (coords, fields); VMD `save_state` saves neither atom mods nor script data. The sidecar pattern ports directly; the file-splicing requirement is the new wrinkle.

**Phase to address:** **save-load** (the entire phase). The file-splicing dependency is locked in **generator** (Pitfall 1).

---

## Moderate Pitfalls

### Pitfall 8: Cleanup can't "remove hiders" — it must reload the original (and the sentinel identifies, not removes)

**What goes wrong:**
The port copies v1's `cmd.remove("obj and segi GAME")` cleanup. VMD has no per-atom remove (Pitfall 2). The developer either (a) tries `atomselect "segid GAME" ... delete` (deletes the *selection object*, not atoms — hiders stay), or (b) does `mol delete` on the whole molecule and loses the user's original structure too, or (c) writes a "cleanup" that over-matches and reloads the wrong file.

**Why it happens:**
`[RUN: pitfalls_out.txt:47-50]`: `atomselect delete` doesn't touch atoms; `mol delete` is whole-molecule only. So "remove just the hiders" is **impossible** without reloading a file. The sentinel's role changes: in v1 it was the `remove` filter; in VMD it's the **identifier** for "which atoms were hiders" (for marking/found-tracking), while cleanup is always "reload original PDB".

**How to avoid:**
- **Cleanup = `mol delete $molid; mol new $original_path` + re-apply original reps.** Always. The original PDB path is recorded at "Start" (Pitfall 2).
- **Sentinel (`segid GAME and beta < 0`) is used to:** (a) identify hiders for the registry, (b) mark found-hiders for recolor, (c) validate "all hiders found" win condition. It is NOT used to `remove` anything.
- **Never** `mol delete` without a recorded original path + rep snapshot — it's destructive and unrecoverable.
- **Test cleanup against the membrane demos** (1GZM, 3GP6) — the v1 Pitfall 9 over-match scenario is structurally impossible now (no per-atom filter), but the "reloaded the wrong file" scenario replaces it.

**Warning signs:**
- Cleanup leaves hiders in the molecule (used `atomselect delete` instead of `mol delete`).
- Cleanup removes the user's whole molecule with no reload (forgot the `mol new` step).
- After Cleanup, the molecule differs from the pre-Start original (reloaded wrong path or wrong reps).

**VMD-specific or v1 carry-over:** v1 Pitfall 9 **RESHAPED** — the over-match failure mode is gone (no per-atom filter), replaced by the "reload the right file" failure mode. Sentinel carries over but changes role.

**Phase to address:** **generator** (sentinel assignment at file-write time) + **game-loop** (Cleanup button) + **demos** (verify membrane round-trip).

---

### Pitfall 9: Cartoon/Ribbon hiders need polymer trace — lone atoms are invisible (carries over from v1)

**What goes wrong:**
A hider atom spliced near a Cα expects to render as a cartoon extension. It doesn't render — the viewer shows the existing cartoon unchanged, the hider is unfindable, the game is unwinnable. Identical to v1 Pitfall 8.

**Why it happens:**
VMD's `Cartoon`, `NewCartoon`, `Ribbons`, `Tube`, `Trace` are all **polymer-trace / backbone-derived reps** — they connect consecutive residues along protein/nucleic backbones. A lone spliced atom (even with `name CA`, `resname GLY`) is not part of the trace unless it has proper consecutive backbone geometry (N-C-Cα) and is recognized as part of the polymer. VMD computes secondary structure via `mol ssrecalc` (`mol` help: `ssrecalc <molid> -- Recalculate secondary structure (Cartoon)`).

**How to avoid:**
- For **Cartoon/Ribbon** hiders: splice a *full residue* (N, CA, C, O backbone) into the PDB at a terminus with proper consecutive `resid`, so VMD's structure analysis includes it in the polymer trace. Run `mol ssrecalc $molid` after load so the new residue gets SS assignment. Verify `molinfo $m get numreps` and visually confirm the cartoon extends.
- For **Lines/Sticks/Bonds** hiders: a single atom is invisible (lines/sticks render *bonds*). Either splice 2+ bonded atoms, or accept that a lone hider must be shown as VDW/Spheres.
- For **VDW/Spheres** hiders: a single atom with a real `element`/`radius` renders anywhere — the easy case.
- **Always visually verify** per rep-type after generation. Add a debug "Reveal all" that sets a VDW rep on `segid GAME` and confirms `[$sel num]` matches visible count.
- **`surface` is out of scope** (same as v1) — VMD `Surf`/`MSMS` are computed meshes and don't blend a foreign atom usefully.

**Warning signs:**
- Hider count says 10 but only 7 are findable.
- `atomselect $m "segid GAME"` count is correct but no cartoon segment appears for hider residues.

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 8 unchanged. The geometry requirement is identical; the splicing happens at PDB-write time (Pitfall 1) rather than via `cmd.fuse`.

**Phase to address:** **generator**.

---

### Pitfall 10: Windows VMD can't resolve `/mnt/c/`, `/tmp/`, or `~/` — paths must be `C:/...`

**What goes wrong:**
Demos load via `mol new /mnt/c/Users/.../1znf.pdb`. Windows VMD reports "couldn't open file: no such file or directory." The plugin works when paths are hand-converted but fails on bundled demos. Same shape as v1 Pitfall 11, different conversion rule.

**Why it happens:**
Runtime-verified `[RUN: pitfalls_out.txt:138-145]`:
- `/tmp/opencode/x` → **MISSING** (Windows VMD can't see WSL `/tmp`)
- `/mnt/c/Users/.../1znf.pdb` → **MISSING** (Windows VMD does NOT understand `/mnt/c/` mount mapping!)
- `C:/Users/.../1znf.pdb` → **RESOLVES** (forward slashes work — no need for backslashes)
- `~/x` → **MISSING** (no `~` expansion to Windows home)
- `pwd` inside VMD = `C:/Users/nglok/Desktop/...` (forward-slash Windows path)
- `$env(HOME)` = `C:\Users\nglok`, `$env(USERPROFILE)` exists.

Note the difference from v1: v1 converted `/mnt/c/` → `C:\` (backslashes for Windows PyMOL). VMD accepts **forward slashes** `C:/...` — simpler. But the `/mnt/c/` blind spot is identical.

**How to avoid:**
- Define a `to_vmd_path(p)` tcl proc that converts `/mnt/c/...` → `C:/...` (forward slashes) and leaves `C:/...` / `D:/...` unchanged. Detect via `string range $p 0 6 == "/mnt/c/"`.
- Resolve bundled demo paths relative to the script's own directory: `[file dirname [info script]]` gives the sourced file's dir (works under VMD). Build demo paths as `[file join $scriptdir data demos 1znf.pdb]` then `to_vmd_path`.
- **Headless-test path resolution early** in **setup** with one tiny PDB (the exact pattern: `bash -ic "vmd -dispdev text -e <script> -eofexit"` with the script at a `C:/...` path). This repo's `tmp/vmd-test/` already proved the workflow.
- For `save_state`, be aware it stores absolute paths (Pitfall 7) — relative demo bundling avoids breakage when the repo moves.

**Warning signs:**
- `mol new` raises "couldn't open file" on a path that `file exists` (in WSL) says is fine.
- Plugin works when the PDB is copied to a `C:\` path but fails from `/mnt/c/`.
- `save_state` reload fails after the repo is moved.

**VMD-specific or v1 carry-over:** CARRIES OVER from v1 Pitfall 11. The conversion rule changes (`/mnt/c/` → `C:/` forward slashes, not `C:\` backslashes) but the failure mode and prevention (path-converter helper + early end-to-end test) are identical.

**Phase to address:** **setup** (helper + first load test) + **demos** (all bundled PDBs verify).

---

### Pitfall 11: `atomselect $sel get` on all atoms builds a huge Tcl list — stream with `molinfo` + narrow selects

**What goes wrong:**
The generator enumerates atoms via `set all [atomselect $m all]; $all get {x y z}` on a 100k-atom membrane protein. The `get` builds a 100k-element Tcl list of triplets — RAM spikes, the call takes seconds, the event loop blocks (Pitfall 6), VMD may freeze. The v1 `get_model` OOM (v1 Pitfall 12) reappears in tcl clothing.

**Why it happens:**
- `atomselect $sel get {x y z}` returns a **Tcl list** of all matched atoms' coords — a full copy in Tcl memory. For 100k atoms × 3 floats, that's a large list and the string↔list conversion in Tcl 8.5 is not cheap.
- `molinfo $m get numatoms` is a single integer — cheap.
- Narrow `atomselect "name CA"` then `$sel get {x y z}` is small (one CA per residue).

**How to avoid:**
- **Never** `$all_sel get` on a large molecule. Use `molinfo $m get numatoms` for counts.
- For placement candidates: `atomselect $m "name CA and protein"` then `$sel get {x y z}` — small list (Cα only).
- For neighbor search: VMD selections are C-side and fast — `atomselect $m "same residue as (within 8 of index $i)"` beats a Tcl loop.
- For per-hider work: select only the hider atoms (`atomselect $m "segid GAME"`) — small set.
- **Always `$sel delete`** when done — atomselect objects leak if not deleted (`[RUN: final_out.txt:91-95]` shows they persist holding stale data; the ramaplot pattern `catch {$selection delete}` on every invalidation).
- **Strip water/salt from large demos before bundling** (same as v1) — `atomselect $m "not water"` then write a trimmed PDB.
- Performance budget (same as v1): Generate on 3GP6 (with membrane) < 30 s; pick latency < 200 ms. Use `after 0` chunking (Pitfall 6) to keep the GUI responsive.

**Warning signs:**
- "Start" freezes for >5 s on small molecules (the bug scales — minutes on 3GP6).
- VMD RSS exceeds 2 GB during Generate.
- `$sel get` appears on an `all` selection in the generator.

**VMD-specific or v1 carry-over:** PARTIALLY CARRIES OVER from v1 Pitfall 12. VMD's `atomselect get` is the streaming equivalent of `cmd.iterate` (no `get_model`-style full object copy), so the *worst* v1 trap (full structure copy) is structurally avoided — but the Tcl-list-building cost is the new analogue.

**Phase to address:** **generator** (memory discipline) + **demos** (verify 3GP6).

---

### Pitfall 12: Tcl 8.5.6 language limits — no `lmap`, no `try`; mind variable scoping and list/string quoting

**What goes wrong:**
The port uses modern Tcl idioms (`lmap`, `try`, `apply`) that don't exist in 8.5 — silent "invalid command name" errors. Or a proc can't see a namespace variable (forgot `variable`), or a selection string with spaces is mis-parsed as a list.

**Why it happens:**
Runtime-verified `[RUN: probe]`: `tcl_version=8.5`, `patchlevel=8.5.6`. Available: `dict` (added 8.5 ✓), `lassign` (defined as a proc in `vmdinit.tcl:27-35` ✓). **Missing:** `lmap` (8.6+), `try` (8.6+). `[RUN: pitfalls_out.txt:151]`: inside a proc, a namespace variable is invisible without `variable`/`global` ("can't read shared: no such variable").

**How to avoid:**
- **No `lmap`** — use `foreach` + `lappend` (or `dict for`). `lassign` IS available.
- **No `try`/`finally`** — use `catch {script} msg; set code $::errorCode; set info $::errorInfo` (the `autoionize.tcl:81-88` pattern: `set errflag [catch {...} errMsg]; ... if $errflag { error $errMsg $savedInfo $savedCode }`). Always restore state in the `catch` branch (no `finally`).
- **Variable scoping:** inside a proc, declare `variable name` (for namespace vars) or `global name` (for global vars) before use. Undeclared access → "no such variable". This is the #1 tcl beginner trap.
- **List vs string:** Tcl lists are strings; `[llength $seltext]` on `"name CA and protein"` is wrong (it's a selection string, not a list). Use `[list ...]` to build lists; quote selection strings with `{}` (braces = literal). `mol selection {$sel}` (the `save_state.tcl:207` pattern) braces the selection.
- **`upvar`/`uplevel`** for pass-by-reference (the `atomselect.tcl:112-120` `upproc` pattern is advanced — avoid unless needed).
- **`expr` quoting:** always `[expr {$a + $b}]` (braced) — unbraced `expr` is slower and a injection risk.

**Warning signs:**
- "invalid command name lmap" / "invalid command name try" at runtime.
- A proc silently can't read a variable that "obviously" exists in the namespace.
- A selection string with spaces is split into multiple list elements.

**VMD-specific or v1 carry-over:** BRAND-NEW VMD pitfall (v1 was Python 3.6; no Tcl). This is the language-learning curve.

**Phase to address:** **setup** (establish the tcl style guide + a `catch`-based error template) — applies to ALL phases.

---

### Pitfall 13: Extension loading — `package require` vs `source`, re-source resets state, GUI-only loading

**What goes wrong:**
The user sources the game script twice (or it's auto-loaded by `.vmdrc` AND sourced manually). Namespace `variable` initializers re-run and **reset game state to defaults** mid-session. Or the menu item doesn't appear because `vmd_install_extension` only runs in GUI mode. Or `package require` fails because `pkgIndex.tcl` is missing from `auto_path`.

**Why it happens:**
- `[RUN: pitfalls_out.txt:152-156]`: `namespace eval ::DoubleTest` twice → second `variable x 10` WINS (x reset to 10). Re-sourcing re-runs the `namespace eval` body, re-initializing variables. Redefined procs silently overwrite (last wins, no error). `package provide` + `package require` own works.
- `[SRC: loadplugins.tcl:114-122,131-134]`: `vmd_install_extension` does `package require $package` then `menu tk register`. `vmd_load_extension_packages` returns early `if ![info exists tk_version]` — **extensions only register in GUI mode**, not text mode.
- `[SRC: *pkgIndex.tcl]`: the `package require` path needs a `pkgIndex.tcl` with `package ifneeded <name> <ver> [list source [file join $dir <file>.tcl]]` AND the dir on `auto_path` (via `.vmdrc` `lappend auto_path /path`).

**How to avoid:**
- **Re-source guard** at the top of the script:
  ```tcl
  namespace eval ::BioChm {
    variable loaded 0
    variable state ;# game state — NOT re-initialized if already set
  }
  if {$::BioChm::loaded} { vmdcon -warn "bioCHEMeleon already loaded"; return }
  set ::BioChm::loaded 1
  ```
  Initialize game state with `if {![info exists ::BioChm::state(timer)]} { set ::BioChm::state(timer) 0 }` so re-sourcing preserves runtime state.
- **Procs are safe to redefine** (silent overwrite) — no guard needed for proc definitions, only for variable init.
- **Loading strategy — pick one:**
  - **`source` directly (SIMPLER, RECOMMENDED for this project).** User runs `source biochemeleon.tcl` (or `.vmdrc` does). No `pkgIndex.tcl` needed. The re-source guard handles double-load.
  - **`package require` (more "proper").** Ship a `pkgIndex.tcl`; user adds the dir to `auto_path` in `.vmdrc`; `vmd_install_extension biochemeleon biochemeleon_tk_cb "Extensions/bioCHEMeleon"`. More setup for the user.
- **GUI-only registration:** guard GUI setup with `if [info exists tk_version] { ... }` so text-mode sourcing doesn't error on Tk commands (which are absent in `-dispdev text` — `[RUN: final_out.txt:80-86]` `grab`/`wm`/`toplevel` all empty in text mode).
- **The `_tk_cb` convention:** define `proc biochemeleon_tk_cb {} { ::BioChm::create_gui; return $::BioChm::w }` — it creates the toplevel and returns its path (the `ramaplot_tk`/`clonerep_tk_cb` pattern).

**Warning signs:**
- Sourcing the script twice resets the timer/found-count to zero.
- The menu item doesn't appear (text-mode loading, or missing `auto_path`/`pkgIndex.tcl`).
- `tk` commands error on headless sourcing (no `tk_version` guard).

**VMD-specific or v1 carry-over:** BRAND-NEW VMD pitfall. v1's `__init_plugin__` had the single-load guarantee from PyMOL's plugin manager; VMD's `source` is re-entrant.

**Phase to address:** **setup** (loading strategy + re-source guard) — the first thing the script must get right.

---

## Minor Pitfalls

### VMD command quirks (runtime-verified)

- **`mol delrep` renumbers reps** — higher reps shift down after a deletion. `[SRC: clonerep.tcl:92-96]` always deletes index 0 in a loop (`for {set i 0} {...} {mol delrep 0 $toid}`) with the comment "they will always be renumbered." Never cache a rep index across a `delrep`.
- **Reps have STABLE NAMES** — `mol repname $m $i` returns a name (`rep0`, `rep1`...); `mol repindex $m $name` looks it up (`[RUN: final_out.txt:76-78]`). **Track game reps by NAME, not index** — this is a VMD advantage over v1 (PyMOL reps were unnamed). v1's `GAME_REPS` list maps to a set of named reps.
- **`atomselect` must be `$sel delete`'d** — leaks otherwise. The `ramaplot` pattern `catch {$selection delete}` on every invalidation. `[RUN: final_out.txt:91-95]` a dangling sel returns stale data silently — never cache across `mol delete`.
- **`label list Atoms` shifts on `label delete`** — entries renumber; clear by tracking the last index, not a stable id (`[RUN: final_out.txt:58-59]`).
- **`molinfo $m get filename`** — the original loaded file path (for the reload-backup, Pitfall 2). Returns a list-of-lists; `[lindex [molinfo $m get filename] 0]` for the first file.
- **`mouse mode` with no arg returns usage, not current mode** (`[RUN: mouse-probe]`). Track current mode via the `$vmd_mouse_mode` global (`[SRC: vmdinit.tcl:279]`).
- **`user add key <char> <command>`** — VMD's hotkey binder (the `[SRC: hotkeys.tcl:109]` pattern), the equivalent of v1's `cmd.set_key`. Save prior binding, restore on unload.
- **`vmdcon -info/-warn/-err`** — the VMD console logger (`[SRC: vmdinit.tcl:67-129]`). Prefer over `puts` for user-visible messages.

### Tcl-specific gotchas

- **`namespace eval` body re-runs on every source** — re-initializes `variable`s (Pitfall 13). Guard state with `info exists`.
- **`upvar #0`** accesses globals; `variable` accesses namespace vars; neither is implicit inside a proc.
- **`{}` braces = literal** (no substitution) — use for selection strings; `""` quotes allow `$` substitution.
- **`expr` must be braced** `[expr {$a+$b}]` for speed/safety.
- **`catch` returns 1 on error, 0 on success** — `if {[catch {cmd} msg]} { handle $msg }`. No `try` in 8.5.
- **`dict` IS available** (8.5+) — use for key→value game state instead of parallel arrays.
- **`vwait varname`** re-enters the event loop and blocks until `var` is written — never `vwait` a var you set in the same proc (infinite loop); use `after` instead.

### VMD 1.9.3 version-specific

- **VMD 1.9.3 is from November 2016** (`[RUN: pitfalls_out.txt:3]` "November 30, 2016"). It is the last 32-bit-Windows-friendly release line; widely deployed but old.
- **No undo** (Pitfall 2), **no per-atom add/delete** (Pitfall 1) — structural, won't change within 1.9.3.
- **Rep instability on bad styles:** `[RUN: test1_out.txt:55]` hit `vmdgridsearch1: exceeded pairlist sanity check, aborted` after an invalid rep style (`Carton` typo). VMD can crash on malformed rep commands — always `catch` `mol representation`/`mol addrep` and validate style strings against the known list (`Lines, Bonds, VDW, CPK, Licorice, Cartoon, NewCartoon, Ribbons, Tube, Trace, ...`).
- **No CUDA here** (`[RUN]` "No CUDA accelerator devices available") — raytracing/some reps may be slower; not a blocker for the game.
- **`-dispdev text` has no Tk** (`[RUN: final_out.txt:80-86]`) — all Tk commands absent in headless. Guard all GUI code with `if [info exists tk_version]`. This is why GUI/modal/grab behavior couldn't be fully verified headlessly (Pitfall 4 MEDIUM flag).

---

## Technical Debt Patterns (VMD-specific)

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hiders in a separate `mol new atoms` molecule | One-liner; no PDB parsing | Player toggles hiders off in one click (Pitfall 1) | **Never.** Pre-process the PDB or use graphics. |
| `atomselect $sel set beta/segid` post-load for sentinels | Easy; no file I/O | `save_state` loses them on reload (Pitfall 7) | **Never.** Splice sentinels into the PDB at write time. |
| `grab set` on the main game panel | "Forces" focus | Blocks the 3D viewer (Pitfall 4) | **Never** on main panel; only on transient sub-dialogs. |
| `lmap`/`try` (Tcl 8.6 idioms) | Concise | "invalid command name" on 8.5 (Pitfall 12) | **Never.** `foreach`+`lappend`; `catch`. |
| `$all_sel get {x y z}` on large mol | Pythonic one-call | Tcl list OOM/freeze (Pitfall 11) | Only <5k atoms. Use narrow selects / `molinfo`. |
| Synchronous generator loop | Simple | Event loop blocks; GUI freezes (Pitfall 6) | **Never** for >200ms. Chunk with `after 0`. |
| Trust `mouse mode` arg to report current mode | Avoids a global read | Returns usage text, not mode (Pitfall 5) | **Never.** Read `$vmd_mouse_mode`. |
| Cache rep index across `delrep` | Convenient | Index shifted; wrong rep edited | **Never.** Track reps by `mol repname` (stable). |
| `save_state` alone for game save | One file | Loses atom mods + game state (Pitfall 7) | **Never.** `save_state` + `.bcm` sidecar. |
| `package require` without `pkgIndex.tcl`/`auto_path` | "Proper" loading | Menu item never appears (Pitfall 13) | Use `source` directly, or ship `pkgIndex.tcl`. |
| `mol delete` without recording original path | Quick cleanup | User's structure gone, no reload (Pitfall 2/8) | **Never.** Record `molinfo get filename` at Start. |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `label add Atoms $m/$i` | Treating the label index as the atom index | Label list is `{{molid atomidx} value show}`; `label delete Atoms <label_index>` (renumbers). Track last-seen atom, not label idx. |
| `trace variable vmd_frame w` | Forgetting to `trace vdelete` on unload | `trace vdelete vmd_frame w $proc` in the unload/cleanup path (the `ramaplot.tcl:266` pattern). |
| `trace variable vmd_initialize_structure w` | Not invalidating selections when a mol is deleted | In the trace, `if [lsearch [molinfo list] $molid] < 0 { catch {$sel delete} }` (`ramaplot.tcl:280-283`). |
| `atomselect` lifetime | Leaking selections (RAM + stale data) | `$sel delete` after use; `catch {$sel delete}` on every invalidation path. |
| `mol addrep` | Setting `mol representation` then `mol addrep` without `mol color/selection/material` first | Set ALL of `representation`/`selection`/`color`/`material` THEN `mol addrep` (the `clonerep.tcl:122-127` pattern). |
| `vmd_install_extension` | Expecting it to work in `-dispdev text` | Guard with `if [info exists tk_version]`; it returns early otherwise (`loadplugins.tcl:134`). |
| `_tk_cb` proc | Not returning the widget path | `proc name_tk_cb {} { ...create toplevel $w...; return $w }` — VMD needs the path for menu tracking. |
| `save_state` path storage | Assuming it stores relative paths | It stores absolute paths (`[SRC: save_state.tcl:186]`); demos break if moved. Bundle relative + convert. |
| WSL→VMD path | Passing `/mnt/c/...` to `mol new` | Convert to `C:/...` (forward slashes) via `to_vmd_path`. |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `$all_sel get {x y z}` on every pick | RAM spike; click latency grows | Narrow `atomselect` per pick; `molinfo` for counts | >5k atoms; fatal at 100k+ (1GZM/3GP6) |
| Synchronous generator loop | GUI freezes during Generate | `after 0 ::gen_chunk` cooperative chunking | >200 ms work |
| Leaking `atomselect` objects | Slow RAM growth over a session | `$sel delete` everywhere; trace invalidation | Long play sessions |
| `mol ssrecalc` on every hider | Seconds of lag | Recalc once after all cartoon hiders spliced | >10 cartoon hiders |
| Polling `label list Atoms` every frame | Constant CPU | `after 200` poll or `trace` `vmd_pick_atominfo` | Long idle sessions |
| Rebuilding all reps after each hider | Each hider adds latency | `mol addrep` only the new hider's rep | >10 hiders on 50k-atom mol |
| `molinfo $m get` for many fields in a loop | Repeated C calls | One `molinfo $m get {f1 f2 f3}` multi-field call | Any loop over mols |

---

## "Looks Done But Isn't" Checklist (VMD)

- [ ] **Loading:** Often missing the re-source guard — sourcing twice resets state. Verify by `source` twice and checking the timer persists.
- [ ] **Generator:** Often puts hiders in a separate `mol new atoms` molecule. Verify `molinfo list` doesn't grow on Generate.
- [ ] **Generator (sentinels):** Often uses `atomselect set beta` post-load — `save_state` loses it. Verify sentinels are in the spliced PDB text, surviving a `save_state`+reload.
- [ ] **Generator (cartoon):** Often splices a lone Cα and assumes Cartoon renders. Verify a cartoon segment appears for the hider residue after `mol ssrecalc`.
- [ ] **Game-loop (pick):** Often works only in pick mode 0. Verify on a fresh VMD with default (rotate) mode that the game forces pick mode and restores it.
- [ ] **Game-loop (rotate):** Often pick mode prevents rotate. Verify the in-panel Rotate/Pick toggle works and document it.
- [ ] **Save-load:** Often saves `.vmd` without the `.bcm` sidecar. Verify Save → quit → relaunch → Load: timer + found-count preserved.
- [ ] **Save-load (sentinel):** Often `save_state` loses atom mods. Verify `atomselect $m "segid GAME"` is non-zero after reload.
- [ ] **Cleanup:** Often uses `atomselect delete` (no-op on atoms). Verify Cleanup removes hiders via `mol delete`+reload, atom count == pre-Start.
- [ ] **Paths:** Often passes `/mnt/c/` to `mol new`. Verify all bundled demos load via `C:/...` converted paths.
- [ ] **Modal:** Often `grab set` on main panel blocks the viewer. Verify the viewer is pickable while the panel is open (HUMAN GUI CHECK).
- [ ] **Unload:** Often leaves `_tk_cb` traces / hotkeys / temp mols. Verify `molinfo list` and `trace` list are clean after unload.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Hiders in separate mol (Pitfall 1) | **HIGH** (rebuild generator) | Switch to PDB pre-processing; re-test visibility + pickability. |
| No-undo corruption (Pitfall 2) | **LOW** (if path recorded) | `mol delete $m; mol new $original_path`; re-apply reps. |
| Registry points at wrong atoms (Pitfall 3) | **MEDIUM** | Switch identity to `(molid,index)` + sentinel reconstruction; re-test. |
| Modal panel blocks viewer (Pitfall 4) | **MEDIUM** | Remove `grab set`; use modeless `toplevel` + `wm deiconify`. |
| Pick not detected (Pitfall 5) | **MEDIUM** | Add `mouse callback on` + trace/poll; force pick mode; restore on exit. |
| GUI freeze (Pitfall 6) | **MEDIUM** | Chunk generator with `after 0`; replace `QTimer` with `after`. |
| `save_state` loses state (Pitfall 7) | **MEDIUM** | Add `.bcm` sidecar; splice sentinels into PDB; re-test round-trip. |
| Cleanup no-op (Pitfall 8) | **LOW** | Replace `atomselect delete` with `mol delete`+reload; record path. |
| Cartoon hiders invisible (Pitfall 9) | **MEDIUM** | Splice full residue + `mol ssrecalc`; verify render. |
| WSL path bug (Pitfall 10) | **LOW** | Add `to_vmd_path`; re-test bundled demos. |
| Large-mol freeze (Pitfall 11) | **MEDIUM** | Narrow selects; `molinfo` for counts; chunk. |
| Tcl 8.5 `lmap`/`try` (Pitfall 12) | **LOW** | Replace with `foreach`/`catch`. |
| Re-source resets state (Pitfall 13) | **LOW** | Add re-source guard + `info exists` state init. |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. No in-place atom add | **generator** (+ doc in setup) | `molinfo list` unchanged after Generate; hiders pickable in target mol. |
| 2. No undo / no per-atom delete | **setup** + **save-load** | Cleanup = `mol delete`+reload; Restart restores original; botched mutation recoverable. |
| 3. No global atom id; molid changes on reload | **generator** + **save-load** | Registry rebuilds from sentinel after reload; (molid,index) stable in-session. |
| 4. Modal grab blocks viewer | **setup** | No `grab set` on main panel; viewer pickable while panel open (HUMAN GUI CHECK). |
| 5. No pick callback | **game-loop** (doc in setup) | `mouse callback`+trace; pick/rotate toggle works; mode restored on exit. |
| 6. Single-thread / blocking | **game-loop** + **generator** | 30-min session on 3GP6: no GUI freeze; `after 0` chunking. |
| 7. `save_state` loses state/mods | **save-load** | Save→quit→relaunch→Load: timer + found-count + sentinels preserved. |
| 8. Cleanup can't remove atoms | **generator** + **game-loop** (verify demos) | 1GZM: Generate→Cleanup→atom count == pre-Start. |
| 9. Cartoon hiders invisible | **generator** | Cartoon segment renders for hider residue after `ssrecalc`. |
| 10. WSL/Windows paths | **setup** + **demos** | Bundled PDBs load via `C:/...` paths; `save_state` survives repo move. |
| 11. Large-mol perf | **generator** + **demos** | 3GP6 with membrane: Generate < 30 s; pick latency < 200 ms. |
| 12. Tcl 8.5 limits | **setup** (style guide) | No `lmap`/`try`; `catch`-based errors; `variable`/`global` declared. |
| 13. Extension loading | **setup** | Re-source guard; `source`-based load; GUI guarded by `tk_version`. |
| 14. VMD 1.9.3 age/instability | **all** | `catch` around `mol representation`/`addrep`; validate rep style strings. |

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| setup (loading) | Re-source resets state (13); menu missing in text mode (13) | Re-source guard; `tk_version` guard; `source`-based load. |
| setup (GUI) | Modal `grab` blocks viewer (4) | Modeless `toplevel` + `wm deiconify`; `_tk_cb` returns widget. |
| setup (paths) | `/mnt/c/` not resolved (10) | `to_vmd_path`; resolve demos via `[info script]` dir. |
| generator | Hiders in separate mol (1); sentinels lost on save (7) | PDB pre-processing; splice sentinel into file text. |
| generator (cartoon) | Lone Cα invisible (9) | Splice full residue; `mol ssrecalc`; verify render. |
| generator (perf) | `all get` OOM (11); blocking loop (6) | Narrow selects; `after 0` chunking. |
| game-loop (pick) | No callback (5); pick/rotate conflict (5) | `mouse callback`+trace; force pick mode; in-panel toggle. |
| game-loop (timer) | Threading assumptions (6) | `after` timer; no threads. |
| save-load | `save_state` loses mods+state (7); molid changes (3) | `.bcm` sidecar; sentinel reconstruct; original-path reload. |
| demos (large) | 3GP6 freeze (11); path bug (10) | Strip water; `C:/...` paths; progress label. |
| demos (attribution) | Missing `DATA_SOURCES.md` | Reuse v1's verified CC0/RCSB/MemProtMD citations (Pitfall 12 carry-over). |
| unload | Leaked traces/selections/hotkeys | `trace vdelete`; `$sel delete`; restore `$vmd_mouse_mode` + hotkeys. |

---

## Open Questions (need phase-specific / human verification)

1. **[MEDIUM] Does `grab set` on the main panel fully block the VMD OpenGL viewer?** Text mode can't test Tk. v1 PyMOL `exec_()` definitively blocked; assume VMD `grab` does too until a human verifies in GUI mode. Prevention is the same either way (modeless main panel).
2. **[MEDIUM] Exact `mouse callback on` pick-handler contract.** The `vmd_pick_atominfo`/`vmd_pick_atom` globals were ABSENT in text mode (no real pick fired). Need ONE human-in-GUI test to confirm: (a) `mouse callback on` populates `vmd_pick_*` on click, (b) which proc/globals get set, (c) whether `trace add variable vmd_pick_atominfo write` fires reliably. Fallback (polling `label list Atoms`) is confirmed working.
3. **[MEDIUM] Can the player rotate while in pick mode?** v1 allowed middle-drag rotate during left-click pick. VMD pick/rotate are separate mouse modes — need to confirm whether middle/right-drag still rotates in pick mode, or whether a hotkey toggle ('r'/'0') is mandatory. Affects UX design (Pitfall 5).
4. **[LOW] `mol repname` stability across `save_state` round-trip.** Rep names (`rep0`...) are stable in-session; unverified whether they survive `save_state`+reload (the session recreates reps via `mol addrep` which auto-names). Likely re-derived as `rep0..repN` — confirm in save-load phase.

---

## Sources

**Runtime-verified (headless VMD 1.9.3, `bash -ic "vmd -dispdev text -e <C:/.tcl> -eofexit"`):**
- `tmp/vmd-test/pitfalls_out.txt` — undo, atom deletion/insertion, save_state, WSL paths, tcl scoping, double-source, atom attributes. HIGH.
- `tmp/vmd-test/final_out.txt` — pick globals, label-based picking, molid reuse, delrep shift, rep naming, grab commands, dangling atomselect. HIGH.
- `tmp/vmd-test/vmd_probe.tcl` output — Tcl 8.5.6, dict/lassign avail, lmap/try absent, `mouse callback` exists. HIGH.
- `tmp/vmd-test/vmd_mouse_probe.tcl` output — full `mouse` usage (modes, callback), `user add key`. HIGH.

**VMD-install source (authoritative):**
- `scripts/vmd/save_state.tcl:39-46,144-269` — explicit "doesn't restore beta/user data/atom mods"; reload-by-path; saves graphics/reps/labels. HIGH.
- `scripts/vmd/vmdinit.tcl:27-35,279-280,331-380` — `lassign` proc, `vmd_mouse_mode` global, `wm withdraw .`, `vmd_tkmenu_cb` integration. HIGH.
- `scripts/vmd/loadplugins.tcl:114-134` — `vmd_install_extension` (package require + menu register), GUI-only loading (`tk_version` guard). HIGH.
- `scripts/vmd/hotkeys.tcl:109-140` — `mouse mode`/`mouse mode pick N` hotkeys, `user add key`. HIGH.
- `scripts/vmd/atomselect.tcl:24-121` — `atomselect` get/set, `upproc`/`upvar` patterns. HIGH.

**Bundled plugins (real-world patterns & anti-patterns):**
- `vmd-ref/plugins/ramaplot1.1/ramaplot.tcl:113-270` — Tk toplevel singleton, `trace variable vmd_frame/vmd_initialize_structure`, `atomselect $sel get`, `catch {$selection delete}`, selection invalidation on mol delete. HIGH.
- `vmd-ref/plugins/clonerep1.3/clonerep.tcl:31-154,237-240` — rep cloning via `molinfo get "{rep $i}..."`, `mol delrep 0` loop (renumbering), `_tk_cb` convention. HIGH.
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:28-169` — `trace variable vmd_initialize_structure`, state-array pattern, molid monotonic assumption ("new molid's are higher"). HIGH.
- `vmd-ref/plugins/mergestructs1.1/mergestructs.tcl:138` — the ONE `grab set` use (transient sub-dialog only). HIGH.
- `vmd-ref/plugins/autoionize1.4/autoionize.tcl:14,80-88` — `package require psfgen`, `catch`/`psfcontext` save-restore error pattern. HIGH.
- `vmd-ref/plugins/*/pkgIndex.tcl` — `package ifneeded` / `package provide` conventions. HIGH.

**v1 reference (carry-over assessment):**
- `.planning/research/PITFALLS.md` (v1, PyMOL 2.5.0) — the 12 v1 pitfalls assessed in the matrix above. HIGH.

**Unverified / flagged:**
- Tk modal/grab blocking the OpenGL viewer (Open Question 1) — MEDIUM, needs human GUI check.
- `mouse callback on` pick-handler contract (Open Question 2) — MEDIUM, needs human GUI check.

---
*Pitfalls research for: VMD 1.9.3 tcl extension — bioCHEMeleon v2 port*
*Researched: 2026-08-22*
