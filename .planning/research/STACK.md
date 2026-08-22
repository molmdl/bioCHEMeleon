# Stack Research

**Domain:** VMD 1.9.3 desktop molecular-visualization extension — interactive "hide-and-seek" game (v2.0, tcl/Tk port of v1 PyMOL plugin)
**Researched:** 2026-08-22
**Confidence:** HIGH (core stack & APIs verified by running a 19-check headless smoke test against the actual VMD install — all PASS; corroborated by the official VMD 1.9.3 User's Guide and the bundled plugin/source files)

> **Scope note (v2 supersedes v1 research).** This file documents the **VMD tcl** stack for the v2.0 milestone. The previous STACK.md documented v1's **PyMOL 2.5.0 Python** stack; that verified PyMOL API behavior is now archived in the shipped v1 codebase, the `pymol/` package + tests, and the PyMOL-specific domain rules in `AGENTS.md` (which is explicitly v1-scoped and flagged for a VMD/tcl rewrite). v1's architecture (pure-layer `setup_state.py`/`registry.py`, mutation-safety backup→mutate→restore) is the *conceptual* model v2 ports, but every concrete API below is VMD-verified, not carried over from PyMOL.
>
> **Zero external dependencies.** The headline result: VMD 1.9.3 ships everything the game needs (Tcl/Tk 8.5 + ttk). **No external tcl libraries are required** — `tooltip.tcl` is NOT needed (write a ~30-line helper or defer; see §Supporting Libraries). This is the cleanest possible stack outcome and avoids the non-BSD Tcl/Tk-license tracking that vendoring `tooltip.tcl` would impose.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **VMD** | 1.9.3 (Nov 30 2016) | Host molecular viewer + script runtime | The target platform per `spec.md`. v1's PyMOL plugin can't run here; v2 is a tcl script sourced into VMD. Install verified at `C:\Program Files (x86)\University of Illinois\VMD\` (readable from WSL). Banner: `VMD for WIN32, version 1.9.3`. |
| **Tcl** | **8.5.6** (`info patchlevel` = `8.5.6`) | Implementation language for the entire game | Verified three ways: `tcl85.dll`+`tcldde13.dll`+`tclpip85.dll`+`tclreg12.dll` in the install root (dated 2009-01-30); `scripts/8.5.6/` + `scripts/tcl8.5/` dirs; and `info patchlevel` at runtime = `8.5.6`. **Tcl 8.5 feature set available: `dict`, `lassign` (built-in), `lreverse` (built-in), `expr` `**` operator, `apply` (lambdas), `namespace ensemble`, `trace add/remove variable`.** NOT available (Tcl 8.6): `try`/`finally`/`throw`, `tailcall`, `coroutine`, `yield` — use `catch`/`error` for error handling. `dict` is the right structure for game state (verified round-trip in smoke test). |
| **Tk** | **8.5** (`tk85.dll`) | GUI framework (Setup + Game tabs, dialogs) | Tk loads **only in GUI mode** (`-dispdev win`), NOT in headless `-dispdev text` (verified: `package require Tk` fails headless with "can't find package Tk"). This is the VMD analog of v1's "PyMOL Qt can't run from WSL" split. Use pure Tk (`toplevel`, `frame`, `button`, `label`, `entry`, `menu`, `menubutton`, `listbox`, `tk_messageBox`, `tk_dialog`, `tk_getSaveFile`/`tk_getOpenFile`). |
| **ttk (Tile)** | bundled with Tk 8.5 (`scripts/tk8.5/ttk/`, `::ttk::*`) | Themed widgets — **`ttk::notebook` for the Setup/Game tabbed UI** (analog to v1's PyQt5 `QTabWidget`) | ttk was merged into Tk as `::ttk::*` in 8.5, so it ships with VMD's Tk. Provides `ttk::notebook`, `ttk::frame`, `ttk::button`, `ttk::label`, `ttk::entry`, `ttk::combobox`, `ttk::progressbar`, `ttk::scrollbar`, `ttk::tree`, `ttk::panedwindow`, `ttk::spinbox`, `ttk::separator`. **Confidence MEDIUM-HIGH**: can't verify headless (Tk doesn't load in text mode — smoke test confirmed `package require ttk` returns 0 in text mode, *expected*); the `scripts/tk8.5/ttk/` widget library is present. Flag for first GUI smoke test. |
| **VMD mol/atomselect/molinfo commands** | built-in | Molecule loading, atom manipulation, rep management | The complete game API surface (see §Stack Patterns / §Question-by-question). All verified headlessly against real PDB `1k8p.pdb`: `mol new/addrep/delrep/modstyle/showrep/repname/repindex/delete`, `molinfo numreps/{rep/selection/color/material}`, `atomselect get/set` (incl. `beta`/`user` fields), `molinfo list`. |
| **VMD Tcl variable traces** | built-in (`trace add/remove variable`) | Click-to-find picking + lifecycle callbacks | THE mechanism that replaces v1's PyMOL Wizard `do_pick`. Verified: `trace add variable ::vmd_pick_event write <cb>` fires on pick, callback reads globals `vmd_pick_atom`/`vmd_pick_mol` (smoke test: simulate pick → callback fires, sees atom=5). See §Stack Patterns. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **(none — stdlib only)** | — | — | VMD ships Tcl/Tk 8.5 + ttk. **Do NOT add external tcl libs without explicit user approval** (AGENTS.md dependency rule carries over). The recommendation is to ship with zero external deps. |
| `tooltip.tcl` (tklib) | 2.0.4 (staged in `vmd-ref/tooltip/`) | Hover tooltips on GUI controls | **RECOMMENDATION: DO NOT vendor.** VMD does not ship tklib (verified: `package require tooltip`/`tklib`/`BWidget`/`tablelist` all return 0). If/when tooltips are wanted (they were v1 *polish*, not table stakes), write a ~30-line helper using pure Tk `<Enter>`/`<Leave>` bindings + `after` timer + a borderless `toplevel` with a `label`. This avoids dragging in a 700-line tklib file under the **Tcl/Tk license** (permissive but NOT BSD — would require copying `license.terms` verbatim and tracking a second license). **Defer tooltips to a polish phase; zero-dep MVP first.** |
| `mergestructs` plugin | 1.1 (in `vmd-ref/plugins/`) | Reference only — merging atoms into a molecule | **Reference, not a dependency.** VMD has no `pseudoatom` primitive (PyMOL did). Hider creation likely needs either (a) a separate hider molecule via temp PDB + `mol new`, or (b) selecting real atoms. `mergestucts.tcl` shows the merge idiom if we ever need to inject atoms into an existing molecule. Decision belongs to ARCHITECTURE.md. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| **Headless VMD from WSL** | Run tcl scripts without the GUI for automated smoke tests | Verified command: `bash -ic "vmd -dispdev text -e <relpath>.tcl -eofexit < /dev/null"` from a `/mnt/c` cwd, with the script staged under `/mnt/c`. See §Headless Testing — this is the v2 analog of v1's `run-conda-pymol.bat -cq` headless pattern. |
| **`vmdinfo` command** | Introspect VMD at runtime (`vmdinfo version`, `vmdinfo arch`, `vmdinfo www`) | Verified `HAS_vmdinfo=1`. Use `vmdinfo version` for the version string in save files; `vmdinfo arch` (= `WIN32` here) for platform branches. |
| **`vmdcon` command** | Console logging (`vmdcon -info/-warn/-err`) | VMD's analog of Python `logging`/PyMOL print. `vmdinit.tcl` provides a fallback impl if not compiled in. Use for all diagnostic output. |
| **Bundled plugins (read-only reference)** | Learn the canonical extension pattern | 5 curated plugins in `vmd-ref/plugins/`: `clonerep1.3` (rep management + Tk GUI — **most relevant**), `viewmaster2.6`, `autoionize1.4` (GUI+CLI), `mergestructs1.1`, `ramaplot1.1`. All use `package ifneeded <name> <ver> [list source [file join $dir <file>.tcl]]`. |
| **VMD core tcl scripts** | Authoritative API-usage examples | `scripts/vmd/`: `vmdinit.tcl` (startup, command overrides), `atomselect.tcl` (selection helpers), `save_state.tcl` (the `.vmd` persistence script — shows the full `mol`/`molinfo`/`mol` rep API), `loadplugins.tcl` (extension discovery + `vmd_install_extension`). Read these before non-trivial VMD work. |

---

## Installation

There is **no `npm`/`pip` step** — v2 is a tcl script. Delivery is one of four sourcing methods (the milestone context specifies "sourced tcl script"; the first two are primary):

```tcl
# (1) Interactive — from the VMD Tk Console or text console:
source /path/to/biochemeleon.tcl
biochemeleon            ;# launches the GUI (or auto-launches on source — see §Stack Patterns)

# (2) Auto-load on every VMD start — add to a startup file (UG §13.3, node251):
#     Windows: ./vmd.rc  or  $HOME/vmd.rc  or  $VMDDIR/vmd.rc  (first found wins)
#     Unix:    ./.vmdrc  or  $HOME/.vmdrc  or  $VMDDIR/.vmdrc
#     Append one line:
source /path/to/biochemeleon.tcl

# (3) Command-line (GUI mode, load script then open viewer):
vmd -e /path/to/biochemeleon.tcl

# (4) Full plugin install (OPTIONAL — puts bioCHEMeleon in the VMD Extensions menu):
#     Drop  biochemeleon/<biochemeleon.tcl + pkgIndex.tcl>  into
#       $VMDDIR/plugins/WIN32/tcl/   (or set env VMDPLUGINPATH=<dir>)
#     Then in vmd.rc:
vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"
```

WSL path guard (carries over from v1): Windows VMD cannot read WSL-only paths (`/tmp/…`, `~`). The sourced path must be Windows-visible — use a `/mnt/c/…` path (VMD resolves it) or stage to one. v1's `demos.to_windows_path()` concept applies: convert `/mnt/c/X` → `C:\X` for any path handed to VMD file ops.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| **Sourced tcl script** (`source`/`-e`/`vmd.rc`) | Full packaged plugin (`pkgIndex.tcl` + `vmd_install_extension` into the Extensions menu) | Use the packaged form only if the milestone later requires "appears in VMD Extensions menu automatically." The sourced form is what `spec.md` calls for and is simpler to distribute/iterate. **Design the file to support BOTH** (namespace + `package provide` + a `biochemeleon_tk_cb` proc) — costs nothing and keeps the door open. |
| **Pure Tk + ttk** for the GUI | VMD's built-in FLTK forms / `menu` commands | Tk is the only scriptable GUI in VMD tcl; FLTK forms aren't tcl-accessible. ttk gives native-looking themed widgets + `ttk::notebook` for tabs. No real alternative. |
| **`ttk::notebook`** for Setup/Game tabs | Separate `toplevel` windows | Use one `toplevel` with a `ttk::notebook` (matches v1's single modeless dialog with tabs; keeps the 3D viewer interactive). Separate windows fragment the UX. |
| **`beta` (B-factor) sentinel** (`$sel set beta -999`, selector `beta < 0`) | `user` per-atom field (`$sel set user <val>`) | `beta` is the direct port of v1's `b=-999` sentinel and is human-inspectable in VMD's GUI (Graphical Representations). `user` is "cleaner" (not a real physical prop) but invisible in default GUI. **Use `beta` as primary sentinel (parity with v1), optionally also set `user` as a secondary tag.** Both verified round-trippable in the smoke test. |
| **Custom `.bcm` sidecar (tcl list/dict)** for game state | VMD `save_state` (`.vmd` script) alone | `save_state` **does NOT persist `user`/`beta` per-atom fields** (confirmed in `save_state.tcl` comment: "It doesn't currently restore: User provided data fields such as 'user', 'beta', …"). So the hider sentinel AND the game state are LOST on `.vmd` reload. **Must use a custom sidecar** (v1's `.bcm`/`.bcmz` approach carries over). Use `.vmd` for VMD scene state + `.bcm` (tcl `dict` serialized as a list) for game state; optionally zip both into `.bcmz`. |
| **Headless `-dispdev text` smoke tests from WSL** | Interactive human-only GUI verification | Headless covers ALL pure-`mol`/`atomselect`/`molinfo`/`trace`/`dict`/file logic (the game engine). GUI/Tk/picking-by-real-mouse MUST be human-verified (Tk doesn't load in text mode). Same split as v1. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **`try`/`throw`/`finally`/`tailcall`/`coroutine`** | Tcl 8.6+ features; VMD ships Tcl **8.5.6** (verified). Will be parse errors. | `catch {…} rc; set err $rc` and `error "msg"`; structured cleanup via explicit procs. |
| **`package require tooltip` / `tklib` / `BWidget` / `tablelist` / `tile`** | None ship with VMD 1.9.3 (verified: all return 0). Forcing them adds external deps needing user approval + non-BSD license tracking. | Pure Tk + ttk (bundled). For tooltips: a ~30-line own helper, or defer. |
| **`tile::*`** (standalone Tile package) | Tile was merged into Tk as `::ttk::*` in 8.5; the standalone `tile` package isn't present (`package require tile` = 0). | `::ttk::*` widgets (e.g. `ttk::button`, `ttk::notebook`). |
| **Relying on `save_state`/`.vmd` to persist the hider sentinel or game state** | `save_state.tcl` explicitly omits `user`/`beta` and "any data produced or modified by scripts, even atom positions." The `.vmd` reloads the original file + reps but NOT per-atom script data. | Custom `.bcm` sidecar (tcl `dict` → flat list → file) recording hider atom indices + rep names + game state; re-apply the sentinel on load. |
| **Bare `label`/`menu`/`scale` as if pure Tk** | `vmdinit.tcl` OVERRIDES these three Tcl commands to dispatch between Tk and VMD (Tk if first arg contains `.` → widget path; else VMD command). | This is transparent for normal use (`label .win.x`, `menu .win.m` work as Tk). Just know that `$w.menubar.help` (has `.`) → Tk, while `menu main on` (no `.`) → VMD. Don't `rename` them. |
| **Python (VMD's Python interface) for v2** | `spec.md` says tcl. Mixing Python+tcl doubles the surface (two interp states, callback bridging). v1 was Python; v2 is deliberately tcl. | Pure tcl. (VMD's Python interface exists but is out of scope.) |
| **Tkinter** | That's PyMOL/Python (v1). VMD's GUI is Tk, not Tkinter. | `pymol.Qt`→`pymol` was v1; v2 uses `toplevel`/`ttk::*`. |
| **Adding atoms to an existing molecule via a pseudoatom primitive** | VMD has NO `cmd.pseudoatom` analog. `mol addfile` adds *frames/coords* to the top molecule, not new atoms. | Create hiders as a **separate molecule** (write a temp PDB, `mol new` it) drawn with a matching rep, OR select real atoms as hiders. (Architecture decision — see ARCHITECTURE.md.) |
| **`info loaded` to detect available packages** | Returns loaded shared libs, not tcl packages. (Misleading in the probe.) | `package require <pkg>` in a `catch`, or check `package ifavailable`. |
| **`$env(VMDVERSION)`** | No such env var (smoke test: "can't read env(VMDVERSION)"). | `[vmdinfo version]` for the version string; `$env(VMDDIR)` is set (`C:/Program Files (x86)/University of Illinois/VMD/`). |

---

## Stack Patterns by Variant

### Pattern: Sourced-script extension structure (the canonical VMD tcl plugin form)

Verified against `clonerep.tcl` (the most relevant reference — rep management + Tk GUI) and `loadplugins.tcl` (`vmd_install_extension`). Structure the file so it works as a sourced script AND as a package:

```tcl
# biochemeleon.tcl
namespace eval ::bioCHEMeleon {
    variable version 2.0
    variable w              ;# handle to our toplevel window (GC-prevention: keep at namespace scope)
    variable state [dict create molid {} hiders {} reps {} found {} timer 0]
    namespace export biochemeleon
}
package provide bioCHEMeleon $::bioCHEMeleon::version

# --- engine procs (pure mol/atomselect/molinfo; headless-testable) ---
proc ::bioCHEMeleon::generate_hiders {molid rep} { ... }
proc ::bioCHEMeleon::on_pick {args} {
    global vmd_pick_atom vmd_pick_mol
    # called by trace; vmd_pick_atom/vmd_pick_mol are the picked atom/molecule
}

# --- GUI proc (Tk; only callable when Tk loaded, i.e. GUI mode) ---
proc ::bioCHEMeleon::gui {} {
    variable w
    set w .biochemeleon
    catch {destroy $w}
    toplevel $w
    wm title $w "bioCHEMeleon"
    set nb [ttk::notebook $w.nb]
    ttk::frame $nb.setup ; ttk::frame $nb.game
    $nb add $nb.setup -text "Setup" ; $nb add $nb.game -text "Game"
    pack $nb -fill both -expand yes
    # react to molecule load/delete:
    trace add variable ::vmd_molecule write ::bioCHEMeleon::refresh_mol_list
}

# --- callback for the optional VMD Extensions-menu install ---
proc biochemeleon_tk_cb {} { ::bioCHEMeleon::gui; return $::bioCHEMeleon::w }

# --- self-launch on source (only if Tk is loaded, i.e. not headless) ---
if {[info exists tk_version]} { ::bioCHEMeleon::gui }
```

Key conventions learned from the bundled plugins:
- Namespace `::Name::` with `variable` defs at the top; `package provide Name $ver`.
- GUI in a `*_tk_cb` or `*gui` proc that returns the window path (so `vmd_install_extension` can register it).
- Use `trace variable vmd_molecule w <proc>` to refresh the molecule dropdown when mols load/delete (clonerep does exactly this).
- `vmdcon -info/-warn/-err` for all console output (NOT bare `puts` for diagnostics).
- `wm withdraw .` is already done by `vmdinit.tcl` when Tk is up — don't fight the default toplevel.

### Pattern: Click-to-find (the v2 `do_pick` replacement)

```tcl
# Activate pick-atom mode (UG node143: mouse mode 4 N; N=2 => pick atom)
mouse mode 4 2
# Register the callback (UG node159: trace vmd_pick_event)
trace add variable ::vmd_pick_event write ::bioCHEMeleon::on_pick

proc ::bioCHEMeleon::on_pick {args} {
    global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state
    set atom $vmd_pick_atom
    set mol  $vmd_pick_mol
    # ... check if atom is a hider (by sentinel) -> mark found ...
}

# On game end / window close: ALWAYS remove the trace and restore mouse mode
trace remove variable ::vmd_pick_event write ::bioCHEMeleon::on_pick
mouse mode 0   ;# back to rotate
```
Verified: the trace fires and reads `vmd_pick_atom`/`vmd_pick_mol` (smoke test §picking). `vmd_pick_shift_state` is 1 if shift held (use for "hint" modifier, optional). **Caveat from UG node140**: *"Hidden reps cannot be picked"* — `mol showrep $m $rep off` makes a rep un-pickable. So hider reps must be SHOWN to be clickable; design hint/reveal around `mol showrep`, not around hiding the rep you want clicked.

### Pattern: Hider sentinel (v1's `b=-999`+`segi=GAME` ported)

```tcl
set sel [atomselect $molid "name CA and chain A"]   ;# candidate hider atoms
$sel set beta -999                                  ;# sentinel value
$sel delete
# Later, find all hiders (VMD has no exact-b-factor selector; use beta < 0)
set hiders [atomselect $molid "beta < 0"]
# [$hiders num] == number of hiders; [$hiders get index] == their indices
```
Verified round-trip (smoke test §sentinel). v1 pitfall carries over: **selector is `beta < 0`, NEVER `beta -999`** (no exact-match b-factor selector in VMD either). Optionally also set the `user` field as a secondary tag (`$sel set user <id>`), and/or define a macro: `atomselect macro bchm_hiders "beta < 0"` (verified usable in selections) for readable selection strings.

### Pattern: Stable registry key for reps (v1's id-keyed registry ported)

VMD renumbers reps when one is deleted, BUT `mol repname <molid> <rep>` returns a **stable unique name** that survives renumbering, and `mol repindex <molid> <name>` is the reverse lookup (both verified in smoke test). Use the rep **name** as the registry key (analog to v1 keying on stable atom `id`, never fragile `index`):
```tcl
set repname [mol repname $molid $repidx]     ;# stable
# ... later, after reps may have been added/removed:
set idx [mol repindex $molid $repname]       ;# current index, or -1 if gone
```

### Pattern: Game-state persistence sidecar (v1's `.bcm`/`.bcmz` ported)

Because `save_state` omits `user`/`beta`/script data, persist game state ourselves:
```tcl
# Save: serialize the dict to a flat list, write as a tcl assignment
set pairs [list]; dict for {k v} $st { lappend pairs $k $v }
set fd [open "puzzle.bcm" w]; puts $fd [list set saved_pairs $pairs]; close $fd
# Load: source-style read + rebuild dict
set fd [open "puzzle.bcm" r]; set data [read $fd]; close $fd
eval $data
set loaded [dict create {*}$saved_pairs]
```
Verified round-trip (smoke test §sidecar). For a shareable `.bcmz`, zip the `.vmd` (VMD scene) + `.bcm` (game state) — same as v1. Store hiders as **atom `index`** (stable across add/delete within a session; smoke test confirmed) + the rep name, and re-apply the `beta -999` sentinel on load (since `.vmd` won't carry it).

### Variant: Headless testing (the WSL→Windows split, v2 edition)

**The exact verified command** (quality gate passed — 19/19 checks):
```bash
# 1. Stage the script under /mnt/c (Windows-visible); WSL-only /tmp/ paths FAIL
#    (Windows VMD can't read them — same trap as v1's PyMOL).
mkdir -p tmp/vmd_test && cp your_script.tcl tmp/vmd_test/
# 2. Run headlessly from a /mnt/c cwd (repo root), relative script path,
#    /dev/null on stdin to guarantee EOF-exit (prevents hang on script error):
timeout 180 bash -ic "vmd -dispdev text -e tmp/vmd_test/your_script.tcl -eofexit < /dev/null" 2>&1 | tail -80
# 3. Exit code 0 + "FAILS=0" line = clean; nonzero = crash (inspect full output).
```
Flags: `-dispdev text` (no GUI), `-e <script>` (execute tcl), `-eofexit` (exit on stdin EOF). `bash -ic` loads the `vmd` alias from `~/.bashrc`. **`< /dev/null` is essential** — without it, a script syntax error drops VMD to the `vmd >` prompt and it hangs waiting for stdin.

**What headless CAN test** (verified): `mol new/addrep/delrep/modstyle/showrep/repname/repindex/delete`, `molinfo`, `atomselect get/set`, `trace` (pick + lifecycle — by simulating the variable write), `dict`, file I/O, `graphics`, `atomselect macro`. **What headless CANNOT test** (needs human GUI): real mouse clicks firing `vmd_pick_event`, any Tk/`ttk::*` widget rendering, `tk_getSaveFile`/`tk_messageBox` dialogs, `mouse mode 4 2` actually entering pick mode visually. This mirrors v1's "Qt/GUI smoke tests are human-verify checkpoints."

**The v2 smoke-test template is the verified file `tmp/vmd_test/game_api_smoke.tcl`** (19 PASS checks covering load, sentinel, reps, pick trace, dict, sidecar, graphics, lifecycle, cleanup). Re-use it as the headless gate for every engine phase.

### Variant: GUI verification (human checkpoint)

```bash
# From a Windows shell (or WSL, since vmd.exe opens its own window):
bash -ic "vmd -e /mnt/c/.../biochemeleon.tcl"      # GUI mode (default -dispdev win)
# Human verifies: window appears, tabs work, pick mode engages, click finds a hider, win/restart.
```
Same human-verify-checkpoint discipline as v1's 9 GUI checkpoints.

---

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|------------------|-------|
| VMD | 1.9.3 (Nov 30 2016) | Tcl 8.5.6, Tk 8.5, ttk (bundled) | Verified by `info patchlevel`=8.5.6 + `tcl85.dll`/`tk85.dll`. Banner confirms 1.9.3. |
| Tcl | 8.5.6 | VMD 1.9.3 (bundled) | **No Tcl 8.6 features** (`try`/`tailcall`/`coroutine`/`yield`). `dict`/`lassign`/`lreverse`/`apply`/`trace` ARE available. |
| Tk | 8.5 | Tcl 8.5.6 (bundled) | Loads in GUI mode only. `tk_patchLevel` unavailable headless. |
| ttk | bundled in Tk 8.5 | Tk 8.5 | `::ttk::*`. MEDIUM-HIGH confidence (present in `scripts/tk8.5/ttk/`; verify on first GUI run). |
| Windows VMD ↔ WSL paths | — | `/mnt/c/…` paths only | Windows VMD cannot read WSL-only `/tmp/`, `~`. Stage scripts/data under `/mnt/c` or a Windows path. Convert `/mnt/c/X`→`C:\X` when handing paths to VMD file ops. |
| VMD molfile plugins | 75 loaded at startup (`plugins/WIN32/molfile/*.so`) | All common formats (pdb, psf, dcd, xtc, …) | Banner: "Dynamically loaded 75 plugins." No action needed for PDB/trajectory load. |

---

## Question-by-question answers (the 6 specific questions)

**1. What tcl/Tk version does VMD 1.9.3 ship?** — **Tcl 8.5.6 / Tk 8.5.** Verified three ways: the install root DLLs `tcl85.dll` + `tk85.dll` (+ `tcldde13.dll`, `tclpip85.dll`, `tclreg12.dll`, all 2009-01-30); the `scripts/8.5.6/`, `scripts/tcl8.5/`, `scripts/tk8.5/` library dirs; and runtime `info patchlevel` = `8.5.6`. **Confidence: HIGH.** Consequence: Tcl 8.5 feature set (`dict`, `lassign`, `lreverse`, `apply`, `trace`); NO Tcl 8.6 (`try`/`throw`/`tailcall`/`coroutine`).

**2. What VMD built-in commands are available for each capability?** (all verified headless + UG):
- **Molecule loading:** `mol new [file] [type …]`, `mol addfile`, `mol load <type> <file>`, `mol urlload`, `mol pdbload <4-char>` (RCSB fetch — v1 `cmd.fetch` analog), `mol delete`, `mol list`, `mol top/on/off/active/inactive/rename`. (UG node140)
- **Atom manipulation:** `atomselect <molid> <sel> [frame N]` → a command object with `get`/`set` (single or multi-attr list), `num`, `list`, `delete`, `global`, `frame`, `update`, `move`/`moveby`/`moveto`, `getbonds`/`setbonds`, `writepdb`. Keywords include `name resname resid chain segname x y z beta occupancy user index mass type` etc. `atomselect macro <name> <sel>` defines reusable macros. (UG node122)
- **Representation management:** `mol representation/color/selection/material <X>` (set defaults), `mol addrep <molid>`, `mol modcolor/modmaterial/modstyle/modselect <rep> <molid> <X>`, `mol modrep <rep> <molid>`, `mol delrep <rep> <molid>`, `mol showrep <molid> <rep> [on|off]`, `mol repname <molid> <rep>` (stable name), `mol repindex <molid> <name>`, `mol selupdate/colupdate/scaleminmax/smoothrep/drawframes`, `mol clipplane …`, `molinfo <molid> get numreps/{rep i}/{selection i}/{color i}/{material i}/list/name/drawn/active/fixed`. (UG node140, node142; verified in smoke test)
- **Atom picking:** `mouse mode 4 2` (pick-atom mode) + `trace add variable ::vmd_pick_event write <cb>`; callback reads globals `vmd_pick_atom`/`vmd_pick_mol`/`vmd_pick_shift_state`. `mouse callback on/off` toggles pick callbacks; `mouse mode 0` returns to rotate. (UG node143, node159; verified by simulation)
- **Save/load:** `save_state <file.vmd>` (writes a tcl script; `vmd -e file.vmd` replays) — BUT it does NOT persist `user`/`beta`/script-modified atom data (confirmed in `save_state.tcl`). So use a **custom `.bcm` sidecar** (tcl `dict`→list→file) for game state, optionally zipped with `.vmd` into `.bcmz` (v1 parity). `atomselect0 writepdb <file>` writes a selection; `mol new <file>` reloads.

**3. Do we need any external tcl libs?** — **NO.** Verified `package require tooltip/tklib/BWidget/tablelist/tile` all return 0 (not shipped). **`tooltip.tcl` is NOT needed**: it was v1 *polish*; for v2 either write a ~30-line pure-Tk tooltip helper or defer tooltips. Vendoring `tooltip.tcl` would pull in the non-BSD Tcl/Tk license (must copy `license.terms` verbatim) — avoid. **Zero external dependencies is the recommendation.** Any future external lib must be user-approved per AGENTS.md (carries over).

**4. How does VMD's tcl extension loading work?** — Standard Tcl `package` mechanism:
- `package ifneeded <name> <ver> [list source [file join $dir <file>.tcl]]` in a `pkgIndex.tcl` (verified across all 5 bundled plugins).
- `loadplugins.tcl` prepends `$VMDDIR/plugins/<arch>/tcl` and `$VMDDIR/plugins/noarch/tcl` to `auto_path`, plus `VMDPLUGINPATH` env dirs.
- `vmd_install_extension <package> <tk_callback> "<Menu/Path>"` does `package require <package>` then `menu tk register` → installs in the VMD Extensions menu (loads AFTER `.vmdrc` so users can customize).
- For a **sourced script** (our primary form): `source <file.tcl>` (or `play`, or `-e`, or a line in `.vmdrc`/`vmd.rc`). No `pkgIndex.tcl` required for the sourced form, but including `package provide` + a `biochemeleon_tk_cb` proc costs nothing and enables the optional packaged form.

**5. How to structure a sourced tcl script that adds a command to VMD?** — See §Stack Patterns "Sourced-script extension structure." Canonical form (from `clonerep.tcl`): `namespace eval ::Name:: { variable …; namespace export … }` → `package provide Name $ver` → engine procs → `gui` proc building a `toplevel` with Tk/ttk → `biochemeleon_tk_cb` returning the window path → optional `if {[info exists tk_version]} { ::Name::gui }` to self-launch on source. The user-visible command is just a proc in the namespace (`::bioCHEMeleon::start`) or auto-launch.

**6. Can we run VMD headlessly from WSL? What's the exact command?** — **YES, verified.** `bash -ic "vmd -dispdev text -e <relpath>.tcl -eofexit < /dev/null"` from a `/mnt/c` cwd, script staged under `/mnt/c`. Tk does NOT load in text mode → GUI/picking-by-real-mouse need a human (same split as v1's PyMOL Qt). The verified 19-check smoke test (`tmp/vmd_test/game_api_smoke.tcl`, all PASS) is the v2 headless-gate template.

---

## Sources

- **VMD 1.9.3 install** (`C:\Program Files (x86)\University of Illinois\VMD\`): `tcl85.dll`/`tk85.dll` (Tcl/Tk version), `scripts/{tcl8.5,tk8.5,8.5.6,vmd}/` (bundled libs + core tcl), `vmd.rc` (startup example), `scripts/vmd/{vmdinit,atomselect,save_state,loadplugins}.tcl` (API usage + extension mechanism). — **HIGH confidence** (primary, runtime-verified).
- **Headless VMD probe + 19-check smoke test** (`tmp/vmd_test/probe.tcl`, `tmp/vmd_test/game_api_smoke.tcl`): ran `vmd -dispdev text -e … -eofexit` against the real install; confirmed Tcl 8.5.6, command existence, `mol new`/atomselect/repname/repindex/showrep/modstyle/delrep, pick-trace firing, dict round-trip, sidecar round-trip, graphics, lifecycle trace, ttk-unavailable-in-text-mode. 19/19 PASS. — **HIGH confidence**.
- **VMD 1.9.3 User's Guide** (online, https://www.ks.uiuc.edu/Research/vmd/current/ug/, matches local `vmd-ref/ug.pdf` v1.9.3 Nov 27 2016): node117 (Tcl Text Interface), node120 (Tcl Text Commands index), node122 (`atomselect`), node140 (`mol`), node142 (`molinfo`), node143 (`mouse` — pick modes `4 N`), node154 (`user` — hotkeys; note: `user` is ALSO an atomselect keyword for per-atom values), node159 (Tcl callbacks — `vmd_pick_event`/`vmd_pick_mol`/`vmd_molecule`/`vmd_initialize_structure`/`vmd_quit` traces), node251 (`.vmdrc`/`vmd.rc` startup loading). — **HIGH confidence** (official docs, version-matched).
- **Bundled VMD tcl plugins** (`vmd-ref/plugins/`): `clonerep1.3/clonerep.tcl` (rep management + Tk GUI + `trace variable vmd_molecule` + `vmd_install_extension` pattern + `vmdcon`), `viewmaster2.6`, `autoionize1.4` (GUI+CLI split), `mergestructs1.1`, `ramaplot1.1`; all `pkgIndex.tcl` files. — **HIGH confidence** (authoritative extension-pattern examples).
- **`vmd-ref/tooltip/`** (`tooltip.tcl` v2.0.4, `pkgIndex.tcl`, `license.terms`): confirmed tklib tooltip under Tcl/Tk license (permissive, non-BSD); staged as reference, **recommendation: do not vendor**. — **HIGH confidence**.
- **Confidence caveats (flag for first GUI smoke test):** ttk availability in GUI mode (MEDIUM-HIGH — present in `scripts/tk8.5/ttk/` but unverifiable headless since Tk doesn't load in `-dispdev text`); real-mouse-click firing of `vmd_pick_event` after `mouse mode 4 2` (HIGH on mechanism from UG node159+node143 + trace verified by simulation, but the actual click→trace path is a human GUI checkpoint).

---
*Stack research for: VMD 1.9.3 tcl hide-and-seek game (bioCHEMeleon v2.0)*
*Researched: 2026-08-22*
