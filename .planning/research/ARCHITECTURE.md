# Architecture Research

**Domain:** VMD 1.9.3 sourced-tcl extension — interactive "molecular hide-and-seek" game (port of v1 PyMOL plugin). Foreign atoms blended into a molecule's own object via PDB-rebuild + reload; click-to-find via VMD pick callbacks.
**Researched:** 2026-08-22
**Confidence:** HIGH (extension structure, GUI pattern, atom manipulation, pick mechanism, persistence, build order) / MEDIUM (exact pick-callback arg signature — headless can't fire a click; Phase-1 validation point)

---

## Method & Sources

Findings were verified by (a) reading 5 real VMD bundled plugins + VMD core scripts, and (b) running 3 headless VMD probes from WSL (`vmd -dispdev text -e <script> -eofexit`) against the Windows VMD 1.9.3 install. Every API claim below is backed by either a cited plugin file:line or a probe result. Probes are reproducible: `tmp/vmdprobe/probe{,2,3}.tcl` (gitignored under `tmp/`).

| Source | What it verified | Confidence |
|--------|------------------|------------|
| `vmd-ref/plugins/clonerep1.3/clonerep.tcl` | package+namespace+`_tk_cb`+toplevel GUI pattern, `trace variable vmd_molecule` | HIGH |
| `vmd-ref/plugins/ramaplot1.1/ramaplot.tcl` | toplevel GUI, `trace variable vmd_frame`/`vmd_initialize_structure`, destroy cleanup, `ramaplot_tk` (alt naming) | HIGH |
| `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl` | tcl-script state save/restore, `states` array, `material`/`colorinfo` APIs, `viewmaster_tk_cb` | HIGH |
| `vmd-ref/plugins/autoionize1.4/autoionize.tcl` | atom insertion = psfgen rebuild + `mol delete`/`mol new` (NOT in-place); `atomselect` get/set; `delatom`/`segment`/`coord` | HIGH |
| `vmd-ref/plugins/mergestructs1.1/mergestructs.tcl` | mol merge via psfgen; `wm protocol WM_DELETE_WINDOW "menu X off"`; `grab set` on modal sub-dialogs | HIGH |
| `…/VMD/scripts/vmd/loadplugins.tcl:114` | `vmd_install_extension` + `menu tk register` — THE menu-registration mechanism | HIGH |
| `…/VMD/scripts/vmd/save_state.tcl:38-46` | VMD `save_state` does NOT restore beta/user/segid/script-modified data | HIGH |
| `…/VMD/scripts/vmd/vmdinit.tcl:279,333` | `vmd_mouse_mode`/`vmd_mouse_submode` globals; `wm withdraw .` | HIGH |
| VMD UG node33 (Pick Modes) | `mouse mode pick 0` = Label→Atom pick; hot keys 1-4 = atom/bond/angle/dihedral | HIGH |
| Headless probe 1 | atomselect set/get beta/segid/user works in-place; `mol addfile` same-molid REJECTS count mismatch; NO undo; 24 materials; save_state drops beta/user; `trace vmd_initialize_structure` fires on mol new | HIGH |
| Headless probe 2 | `vmd_pick_atom_callbacks` list is the pick hook; `user`/`user2` custom fields work + are selectable; tcl 8.5 + `dict` | HIGH |
| Headless probe 3 | combined-PDB rebuild loads hider into SAME molid as reals (invariant holds); `resname HID` selectable; pick-callback registration + mouse-mode snapshot works | HIGH |

---

## Standard Architecture

### System Overview

bioCHEMeleon v2 is a **single sourced tcl script** running inside the VMD host. No backend, no threads, no networking for v2. All state lives in one tcl namespace (`::BCM::`) plus the VMD molecule session. The architecture is layered so that **game logic never calls `mol`/`atomselect` directly** and **GUI never mutates molecules except through controller procs** — mirroring v1's strict layering so the click→found→refresh loop stays traceable and the pure layer stays unit-testable in WSL via `tclsh` + `tcltest` (tcl's own interpreter — no Python, no VMD needed for pure-logic tests).

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GUI LAYER  (gui/)  — Tk widgets only, holds NO game logic, NO mol calls   │
│  ┌──────────────────────┐   ┌──────────────────────────┐                   │
│  │ SetupTab (ttk frame)  │   │ GameTab (ttk frame)       │                  │
│  │  - params form        │   │  - timer/remaining labels │                  │
│  │  - 7 buttons          │   │  - hint/reveal/save/restart│                 │
│  └──────────┬────────────┘   └─────────────┬────────────┘                  │
│             │  -command callbacks             │  -command callbacks          │
│  ┌──────────┴────────────────────────────────┴────────────┐              │
│  │     PluginDialog (toplevel .biochemeleon + ttk::notebook) │              │
│  │     modeless: NO grab, NO tkwait/vwait at toplevel        │              │
│  └──────────────────────────┬─────────────────────────────┘              │
└─────────────────────────────┼────────────────────────────────────────────┘
                              │  calls controller procs only
┌─────────────────────────────┴────────────────────────────────────────────┐
│  CONTROLLER / GAME-LOGIC LAYER  (lib/)  — pure tcl where possible           │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ GameController│  │ HiderGenerator │  │ HiderRegistry│  │ StateStore   │   │
│  │  - start      │  │  - per-rep     │  │  - dict idx→  │  │ - .bcm JSON  │   │
│  │  - on_pick    │  │    placement   │  │    {rep,status}│  │ - combined   │   │
│  │  - hint/reveal│  │  - sphere/line/│  │  - per-rep cnt │  │   PDB save   │   │
│  │  - restart    │  │    cartoon     │  │                  │  │              │   │
│  └──────┬────────┘ └───────┬────────┘ └────────┬─────────┘ └──────┬──────┘   │
└─────────┼──────────────────┼───────────────────┼──────────────────┼──────────┘
          │                  │                   │                  │
┌─────────┴──────────────────┴───────────────────┴──────────────────┴─────────┐
│  VMD INTEROP LAYER  (lib/)  — the ONLY place that calls mol/atomselect       │
│  ┌──────────────┐  ┌───────────────┐  ┌────────────────┐  ┌──────────────┐   │
│  │ VmdAdapter   │  │ PickBridge     │  │ ObjectMutator  │  │ DemoLoader   │   │
│  │ - get_mols   │  │ - vmd_pick_    │  │ - backup_scene │  │ - manifest   │   │
│  │ - get_reps   │  │   atom_cb list │  │ - rebuild_pdb  │  │ - mol new    │   │
│  │ - recolor    │  │ - mouse mode  │  │ - add_hiders   │  │ - fetch big  │   │
│  │ - addrep     │  │   save/restore│  │ - restore_scene│  │ - sources    │   │
│  └──────┬───────┘  └───────────────┘  └────────────────┘  └──────────────┘   │
└─────────┼───────────────────────────────────────────────────────────────────┘
          │  mol / atomselect / molinfo / mouse / material / label  (VMD tcl API)
┌─────────┴────────────────────────────────────────────────────────────────────┐
│  VMD CORE — tcl API + OpenGL viewer (internal) + .vmd save_state            │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation | Talks To |
|-----------|----------------|----------------------|----------|
| **`biochemeleon.tcl` (entry)** | `package provide` + `namespace eval ::BCM::`; register menu via `vmd_install_extension`; define `biochemeleon_tk_cb` (returns window handle) and a plain `biochemeleon` console command (headless-testable). Source all `lib/` + `gui/` sub-modules. | Pattern from `clonerep.tcl:237` (`clonerep_tk_cb`) + `loadplugins.tcl:114` (`vmd_install_extension`). | VMD plugin loader, PluginDialog |
| **PluginDialog** (gui) | `toplevel .biochemeleon` + `ttk::notebook` (Setup/Game); route `-command` to GameController procs; own singleton lifetime via `variable w`. Modeless (no `grab`/`tkwait`). | `toplevel`+`wm title` from every ref plugin; `ttk::notebook` for tabs (tcl 8.5 ttk). | SetupTab, GameTab, GameController |
| **SetupTab** (gui) | Params form + 7 buttons (Reset/Randomize/Save Setup/Load Setup/Generate & export/Cleanup/Start); emits intents, never mutates molecules. | ttk widgets (`ttk::labelframe`, `ttk::entry`, `ttk::combobox`, `ttk::checkbutton`, `ttk::button`); pattern from `mergestructs.tcl:56-83`. | PluginDialog |
| **GameTab** (gui) | Timer label, remaining counters (total + per-rep), rolling info box, hint/reveal/save/restart buttons. | ttk widgets + `after` loop for the timer tick (tcl's `after $ms <cmd>` = QTimer equivalent). | PluginDialog |
| **GameController** (logic) | Orchestrator: `start`, `on_pick`, `hint`, `reveal_one/all`, `save`, `restart`, `cleanup`. Holds registry + state + adapter refs. | tcl namespace with procs + `variable` state; the "brain". | HiderGenerator, HiderRegistry, StateStore, VmdAdapter, PickBridge, GUI (via callbacks) |
| **HiderGenerator** (logic) | Decide *where* and *what* hider atoms per rep; produce a spec list (resname, coords, beta, segid, user-id) handed to ObjectMutator. | One proc per rep strategy (`gen_sphere`, `gen_lines`, `gen_cartoon`, …). | VmdAdapter (read geometry), ObjectMutator (execute) |
| **HiderRegistry** (logic, PURE) | Source of truth for hider identity + status. `dict` keyed by atom `index` → `{rep status found_at hint_used}`; per-rep remaining counters; serialize/deserialize. **stdlib-only tcl — no `mol`/`atomselect`; unit-testable via `tcltest` in WSL.** | tcl `dict` + procs; mirrors v1 `registry.py` (OrderedDict→dict). | GameController, StateStore |
| **StateStore** (logic) | Save/load: writes the **combined PDB** (game scene, via `atomselect writepdb`/manual append) + **`.bcm` JSON sidecar** (registry, timer, setup, reveal counts). Hand-rolled JSON (no `json` package in VMD 1.9.3). | tcl 8.5 `dict` + manual JSON emit/parse; combined-PDB path verified by probe3. | GameController, VmdAdapter, HiderRegistry |
| **PickBridge** (interop) | The atom-picking callback bridge. Registers a proc in `::vmd_pick_atom_callbacks`; on pick, reads `vmd_pick_atom`/`vmd_pick_molecule` globals and forwards `(molid, index)` to `GameController.on_pick`. Saves/restores the user's prior `mouse mode` + the callbacks list. | `lappend ::vmd_pick_atom_callbacks ::BCM::on_pick`; `mouse mode pick 0`; snapshot `vmd_mouse_mode`/`vmd_mouse_submode` first (probe2/3 verified). | GameController, VMD core |
| **VmdAdapter** (interop) | Thin wrapper over `mol`/`molinfo`/`atomselect` for queries: `get_mols`, `get_reps`, `recolor`, `addrep`/`modstyle`/`modselect`/`modcolor`/`modmaterial`, `showrep`. All read-only-ish mol calls go here so logic stays mol-free. | procs; rep commands verified by probe1 Q2. | VMD core |
| **ObjectMutator** (interop) | The ONLY component that **adds/removes atoms**. `backup_scene` (snapshot viewpoint+reps+atom fields, keep original molid), `rebuild_with_hiders` (write combined PDB → `mol delete` original → `mol new` combined → set sentinels in-place via atomselect → restore viewpoint+reps on new molid), `cleanup` (restore original from backup). | PDB-rebuild pattern (autoionize/mergestructs use psfgen; we use plain PDB append — lighter, no topology file needed). Verified by probe3. | VMD core, HiderGenerator |
| **DemoLoader** (interop) | Bundled-small-PDB manifest + on-demand fetch for large membrane PDBs; caching + source attribution. **Reuse v1's `data/demos/` PDB files + `SOURCES.md`** (PDBs are format-identical for VMD). | manifest.tcl (`dict`); `mol new $pdb type pdb waitfor all`. | VMD core, data dir |

---

## Recommended Project Structure

```
vmd/                              # <<< v2 code (mirrors pymol/ layout)
├── biochemeleon.tcl              # entry: package provide + namespace eval ::BCM:: +
│                                 #   biochemeleon_tk_cb + vmd_install_extension +
│                                 #   plain `biochemeleon` console command + source all lib/gui
├── pkgIndex.tcl                  # package ifneeded biochemeleon <ver> [list source [file join $dir biochemeleon.tcl]]
├── 3rd_party_lib/                # git-ignored; tooltip.tcl vendored HERE if user approves (Tcl/Tk license)
├── data/
│   ├── demos/                    # REUSED from v1 (PDBs are viewer-agnostic)
│   │   ├── protein/  nucleic/  mixed/  glycoprotein/
│   │   │   └── *.pdb.gz
│   │   └── SOURCES.md            # human-readable citations (reuse v1's)
│   └── manifest.tcl              # demo catalog as tcl dict/list (mirrors v1 manifest.json)
├── lib/                          # sourced sub-modules, each `namespace eval ::BCM::<Sub>`
│   ├── setup_state.tcl           # PURE: stdlib tcl — GAME_REPS, defaults, validate_state, DEMO_MANIFEST (tcltest in WSL)
│   ├── registry.tcl              # PURE: stdlib tcl — dict-based HiderRegistry (tcltest in WSL)
│   ├── backup.tcl                # cmd: snapshot viewpoint+reps+atom-fields; restore
│   ├── mutation.tcl              # cmd: rebuild PDB + reload + sentinel via atomselect + cleanup
│   ├── pick.tcl                  # cmd: vmd_pick_atom_callbacks registration + mouse mode save/restore
│   ├── game.tcl                  # orchestrator: wires backup+mutation+registry+pick (composition root)
│   ├── persistence.tcl          # hand-rolled JSON .bcm sidecar + combined-PDB save/load
│   ├── demos.tcl                 # cmd: mol new/load demos + manifest lookup
│   └── generators.tcl            # per-rep hider placement (sphere/lines/cartoon/...)
├── gui/
│   ├── dialog.tcl                # toplevel + ttk::notebook (Setup + Game), modeless
│   ├── setup_tab.tcl            # setup form (ttk widgets)
│   └── game_tab.tcl             # timer/remaining/info/buttons (ttk + `after` loop)
└── tests/
    ├── test_setup_state.test     # tcltest pure-layer (WSL-runnable: `tclsh` runs tcltest)
    └── test_registry.test        # tcltest pure-layer
```

### Structure Rationale

- **`vmd/` mirrors `pymol/`** (per PROJECT.md decision: multi-viewer project, each viewer self-contained). A user installs v2 by sourcing `vmd/biochemeleon.tcl` (or adding `source …/biochemeleon.tcl` to `.vmdrc`).
- **`lib/` + `gui/` split enforces layering.** `lib/setup_state.tcl` and `lib/registry.tcl` are stdlib-only tcl (NO `mol`, NO `atomselect`, NO `tk`) → unit-testable in WSL via `tcltest` (tcl's own interpreter; no VMD install needed). This is the **direct tcl analog of v1's `setup_state.py` + `registry.py` pure layer** (which was unit-testable in WSL python3.6). The other `lib/` modules are cmd-coupled and verified by headless VMD smoke tests, not WSL tcltest.
- **One-file entry vs package directory:** tcl packages are a directory with `pkgIndex.tcl` + one or more `.tcl` files. Splitting logic into `lib/*.tcl` (each a `namespace eval ::BCM::<Sub>`) keeps files tractable and matches the v1 module-per-file structure. `biochemeleon.tcl` sources them all at load (via `package provide` + `source [file join $dir lib X.tcl]`), so the user still sees one `source biochemeleon.tcl`.
- **`tests/*.test` with `tcltest`:** tcl ships `tcltest` (the tcl unit framework). Pure-layer tests run in WSL via `tclsh tests/test_setup_state.test` — NO VMD, NO Python needed. This preserves v1's "honest WSL tests" discipline (v1 used python3.6 `unittest`; v2 uses `tcltest`). Cmd-coupled code is verified by headless VMD smoke (`vmd -dispdev text -e smoke.tcl -eofexit`), the v2 equivalent of v1's `run-conda-pymol.bat -cq`.
- **`data/demos/` reused verbatim from v1:** PDB files are viewer-agnostic; v1's bundled 1znf/1xdn/5E54/1K8P/2QBZ/4WB3 + SOURCES.md load identically in VMD. Only the manifest format changes (json→tcl dict).
- **`3rd_party_lib/` for tooltip.tcl:** `vmd-ref/tooltip/` ships `tooltip.tcl` (Tcl/Tk license terms). If the GUI needs tooltips (Polish phase), vendor under `vmd/3rd_party_lib/` per the spec's dependency-approval rule (seek user approval first; note license; git-ignore the dir). No linux-like env needed — `source` works from WSL-staged Windows paths.

---

## Architectural Patterns

### Pattern 1: Sourced-script entry — `package provide` + `vmd_install_extension` + dual command/menu

**What:** The VMD extension entry. `package provide` makes it loadable via `package require`; a `<name>_tk_cb` proc creates the GUI and returns the window handle; `vmd_install_extension` registers it in VMD's Extensions menu. For a *sourced* script (spec requirement: "loaded by sourcing the vmd tcl then calling certain command"), the script calls `vmd_install_extension` itself at source-time, AND defines a plain console command as a fallback.

**When to use:** Always — this is the canonical VMD 1.9.3 extension entry. Verified: `clonerep.tcl:237` (`clonerep_tk_cb`), `viewmaster.tcl:1087` (`viewmaster_tk_cb`), `ramaplot.tcl:663` (`ramaplot_tk`), `mergestructs.tcl:992` (`mergestructs_tk`); `loadplugins.tcl:114` defines `vmd_install_extension {package tk_callback menupath {winname ""}}` → `package require` + `menu tk register`.

**Trade-offs:**
- Pro: auto-appears in Extensions menu (VMD's `menu tk register` integrates the toplevel with VMD's window manager — `wm protocol WM_DELETE_WINDOW "menu <name> off"` works, see `mergestructs.tcl:54`).
- Pro: dual mode (menu + console command) — the console command `biochemeleon` lets headless tests open the GUI path without a menu, and lets users `source X; biochemeleon` from `.vmdrc`.
- Con: `vmd_install_extension` calls `package require` which needs `pkgIndex.tcl` on `auto_path`. For a single sourced file, we ALSO `source` sub-modules directly so the script works even if the user copies just `biochemeleon.tcl` into a non-package dir.

**Example:**
```tcl
# vmd/biochemeleon.tcl
package provide biochemeleon 2.0

namespace eval ::BCM:: {
    variable version 2.0
    variable w        ;# handle to the toplevel dialog (GC prevention)
}

# Source sub-modules (relative to this file's dir)
set ::BCM::dir [file dirname [info script]]
foreach f {lib/setup_state.tcl lib/registry.tcl lib/backup.tcl lib/mutation.tcl \
           lib/pick.tcl lib/game.tcl lib/persistence.tcl lib/demos.tcl \
           lib/generators.tcl gui/dialog.tcl gui/setup_tab.tcl gui/game_tab.tcl} {
    source [file join $::BCM::dir $f]
}

# Menu callback (VMD convention: <name>_tk_cb returns the window handle)
proc biochemeleon_tk_cb {} {
    ::BCM::gui::show_dialog
    return $::BCM::w
}

# Plain console command (headless-testable; also the .vmdrc entry point)
proc biochemeleon {} { ::BCM::gui::show_dialog }

# Self-register in VMD's Extensions menu (idempotent — VMD handles re-register)
if {[llength [info commands vmd_install_extension]]} {
    vmd_install_extension biochemeleon biochemeleon_tk_cb "Extensions/bioCHEMeleon"
}
```

### Pattern 2: Modeless Tk toplevel with `ttk::notebook` (the click-loop enabler)

**What:** A `toplevel` window holding a `ttk::notebook` with two tabs (Setup, Game status). The toplevel is **modeless by default** — no `grab set`, no `tkwait window`, no `vwait` at toplevel scope. This is REQUIRED so the OpenGL viewer stays interactive for the click-to-find loop (direct analog of v1's "PluginDialog must be modeless: `dialog.show()`, NEVER `.exec_()`"). Tab switching is driven by GameController state (Start → Game; Restart/Cleanup → Setup), not free user-clicking.

**When to use:** Always for this GUI. Verified modeless pattern in every ref plugin (`clonerep.tcl:168` `toplevel $w`, no grab; `ramaplot.tcl:130`; `viewmaster.tcl:70`). `grab set` is used ONLY on small modal sub-dialogs (e.g. `mergestructs.tcl:138` for the "select molecule" popup), never on the main window.

**Trade-offs:**
- Pro: viewer stays live; user can rotate while the dialog is open — essential for the hide-and-seek mechanic.
- Pro: `ttk::notebook` is built into tcl 8.5 ttk (VMD 1.9.3 ships tcl 8.5, probe3 confirmed); no external widget lib needed (unlike v1's Pmw risk).
- Con: must lock tab order to game state (`$nb.tab configure -state disabled`) to prevent the user editing setup mid-game — same constraint as v1.

**Example:**
```tcl
# vmd/gui/dialog.tcl
namespace eval ::BCM::gui:: {
    variable w
}

proc ::BCM::gui::show_dialog {} {
    variable w
    if {[winfo exists .biochemeleon]} { wm deiconify $w; return $w } ;# singleton
    set w [toplevel .biochemeleon]
    wm title $w "bioCHEMeleon"
    wm protocol $w WM_DELETE_WINDOW "menu biochemeleon off"   ;# VMD menu integration

    set nb [ttk::notebook $w.nb]
    set setup [::BCM::gui::setup::build $nb.setup]
    set game  [::BCM::gui::game::build  $nb.game]
    $nb add $setup -text "Setup"
    $nb add $game  -text "Game status"
    $nb tab $game -state disabled      ;# Game tab locked until Start
    pack $nb -fill both -expand yes
    return $w
}

proc ::BCM::gui::switch_to {tab} {
    variable w
    $w.nb select $w.nb.$tab
    $w.nb tab $w.nb.game -state [expr {$tab eq "game" ? "normal" : "disabled"}]
    $w.nb tab $w.nb.setup -state [expr {$tab eq "setup" ? "normal" : "disabled"}]
}
```

### Pattern 3: Pick callback via `vmd_pick_atom_callbacks` + `mouse mode pick 0` (THE click-to-find bridge)

**What:** VMD's atom-picking mechanism. Register a proc in the global list `::vmd_pick_atom_callbacks`; set the mouse to atom-pick mode (`mouse mode pick 0` = "Label → Atom", VMD UG node33). On each click, VMD sets the globals `vmd_pick_atom` (atom index), `vmd_pick_molecule` (molid), `vmd_pick_state`, `vmd_pick_selection` and invokes every proc in `::vmd_pick_atom_callbacks`. Save the user's prior `mouse mode` + submode (globals `vmd_mouse_mode`/`vmd_mouse_submode`, vmdinit.tcl:279) BEFORE switching, restore on deactivate.

**When to use:** This is the supported VMD callback for "user clicked an atom". Verified: probe2 confirmed `lappend ::vmd_pick_atom_callbacks ::bcm_pick_cb` succeeds (VMD recognizes the list); probe1 confirmed `mouse mode pick` is accepted; VMD UG node33 documents `mouse mode pick 0` = atom pick. This is the **direct VMD analog of v1's `PickWizard.do_pick`** (the Wizard is PyMOL-specific; VMD uses the callback-list + mouse-mode pattern instead).

**Trade-offs:**
- Pro: native, no polling, no hijacking mouse buttons.
- Pro: multiple callbacks can coexist (we `lappend`, not `set`) — we can chain with any existing pick callback the user registered (cache the prior list, restore on deactivate).
- Con: headless VMD CANNOT fire a click (probe2/3: the `vmd_pick_*` globals stay unset), so the exact callback arg signature can't be verified from WSL. **Phase-1 validation point:** confirm whether VMD calls the callback with `(molid atom)` args or with no args (read globals inside the proc). Defensive code reads BOTH the args (if given) and the globals as fallback.
- Con: only one mouse mode active at a time — must restore the user's prior mode on exit (don't leave them stuck in pick mode). Same discipline as v1's "save/restore the user's wizard".

**Example:**
```tcl
# vmd/lib/pick.tcl
namespace eval ::BCM::pick:: {
    variable saved_mode    ""
    variable saved_submode ""
    variable saved_cbs      {}     ;# prior callbacks list (don't clobber)
    variable active 0
}

proc ::BCM::pick::activate {molid} {
    variable saved_mode saved_submode saved_cbs active
    global vmd_mouse_mode vmd_mouse_submode vmd_pick_atom_callbacks
    # Snapshot BEFORE switching (vmdinit.tcl:279 sets these globals)
    set saved_mode    $vmd_mouse_mode
    set saved_submode $vmd_mouse_submode
    catch {set saved_cbs $vmd_pick_atom_callbacks}   ;# may not exist yet
    set ::BCM::pick::target_mol $molid
    set vmd_pick_atom_callbacks {}                   ;# we own the list during play
    lappend vmd_pick_atom_callbacks ::BCM::pick::on_pick
    mouse mode pick 0                                ;# atom-pick mode
    set active 1
}

proc ::BCM::pick::on_pick {args} {
    # VMD sets these globals on pick (probe2: unset until a click fires).
    # Args may carry (molid atom); fall back to globals if empty.
    global vmd_pick_atom vmd_pick_molecule
    set molid [lindex $args 0]
    set idx   [lindex $args 1]
    if {$molid eq "" || $idx eq ""} { set molid $vmd_pick_molecule; set idx $vmd_pick_atom }
    if {$molid ne $::BCM::pick::target_mol} return   ;# ignore picks on other mols
    ::BCM::game::on_pick $idx                        ;# forward to controller
}

proc ::BCM::pick::deactivate {} {
    variable saved_mode saved_submode saved_cbs active
    global vmd_pick_atom_callbacks
    mouse mode $saved_mode $saved_submode            ;# restore user's mode
    catch {set vmd_pick_atom_callbacks $saved_cbs}  ;# restore user's callbacks
    set active 0
}
```

### Pattern 4: Object-mutation safety — backup scene → rebuild PDB with hiders → reload → restore scene

**What:** The core spec invariant (*hiders live in the SAME molecule as the real structure*, so the player can't isolate them by hiding one object). VMD CANNOT insert atoms in-place (probe1 Q1c: `mol addfile` to a same molid rejects count mismatch — "Mismatch between existing molecule or structure file atom count"). So the VMD-native way to add atoms is the **PDB-rebuild** pattern (autoionize/mergestructs use `psfgen` for the same effect; we use plain PDB append — lighter, no topology file needed). Safe protocol:

1. **Backup the scene BEFORE mutate:** snapshot viewpoint (`molinfo $mol get {center_matrix rotate_matrix scale_matrix global_matrix}`), reps (per-rep `{rep sel color material …}` via `molinfo` + `mol showperiodic` etc., exactly as `viewmaster.tcl:246-270` / `save_state.tcl:80-108` do), and the original molid. Keep the original molecule loaded but hidden (`mol off $mol`) as the restore source — OR write its PDB (`atomselect writepdb`) so we can rebuild it. **VMD has NO undo** (probe1 Q8: no `undo` command) so the backup is the ONLY recovery.
2. **Build the combined PDB:** read all atoms (`atomselect $mol all` → `get {name resname resid chain segid beta occupancy x y z element}`), append hider ATOM records (column-aligned, see Pattern 5), write combined PDB.
3. **Reload:** `mol delete $orig_molid; mol new combined.pdb type pdb waitfor all`. The new molid holds **real + hider atoms together** (probe3 confirmed: numatoms=5, `resname HID` atoms=1, real ALA=4, same molid → invariant HOLDS).
4. **Apply sentinels in-place** (robust — survives any PDB column rounding): `set h [atomselect $new "resname HID"]; $h set beta -999; $h set segid GAME; $h set user <hider_id>`. (probe1 confirmed `$sel set beta/segid` works; probe2 confirmed `user` works + is selectable.)
5. **Restore viewpoint + reps on the new molid** (`molinfo $new set {…} $vm`; re-`mol addrep` from the saved rep list). molid changed — update `GameController`'s molid handle.
6. **Cleanup/Restart = restore from backup:** `mol delete $game_molid; mol new <original.pdb>` (or un-hide the kept original) + restore viewpoint/reps. Simpler and corruption-proof — never surgically un-find hiders.

**When to use:** On Start, Restart, Cleanup, Generate & export, and plugin exit.

**Trade-offs:**
- Pro: faithful to v1's "same object" invariant — verified the hider shares the game molid with real atoms (probe3).
- Con: **molid changes on every rebuild** (unlike v1 where the PyMOL object name stayed stable). Mitigation: GameController holds the *current* molid as a `variable`, updated on rebuild; the registry keys by atom `index` (stable within a molid's lifetime — only changes on rebuild, and we rebuild the registry on each Start anyway).
- Con: viewpoint/reps reset on `mol new`. Mitigation: save/restore via `molinfo` matrices + rep list (viewmaster/save_state do exactly this). ~20 lines of tcl.
- Con: rebuild cost = write+read PDB. For demo PDBs (~1k atoms) trivial; for large membrane (~50k) acceptable (~1s). Document it.

**Anti-corruption guarantees (direct port from v1):**
- Never mutate a backup molecule.
- Always `mol delete` the backup/extra molecules on plugin exit / Cleanup to avoid polluting the session.
- Registry is rebuilt from sentinels on each Start (don't persist `index` across a rebuild — indices are only stable within one molid lifetime; the `.bcm` sidecar reconciles post-load — see Pattern 7).

### Pattern 5: Hider sentinel + selector (direct port of v1's `segi GAME` + `b=-999`)

**What:** Tag every hider atom so it's bulk-selectable for cleanup/color, and individually addressable for the registry. v1 used `segi='GAME'` + `b=-999` (PyMOL selectors). VMD uses the same sentinel VALUES, set in-place via atomselect after the PDB rebuild.

**When to use:** On every hider, immediately after `mol new combined.pdb`.

**Trade-offs:**
- Pro: identical sentinel concept to v1 → registry/reconstruct logic ports directly; `SOURCES.md`/docs reuse.
- Pro: VMD `atomselect` supports `beta < 0`, `segid GAME`, `resname HID`, `user <N>` selectors (probe1 Q1b, probe2 Q-USER all verified).
- Con: PDB write can round beta/coords; setting sentinels in-place (not via PDB columns) sidesteps PDB column bugs (probe3: a misaligned beta column dropped the value; in-place `atomselect set` is robust). **Always set sentinels via atomselect after load, never rely on PDB columns alone.**

**Example:**
```tcl
# vmd/lib/mutation.tcl
namespace eval ::BCM::mut:: { variable HID_SENTINEL_BETA -999; variable HID_SEGID "GAME"; variable HID_RESNAME "HID" }

proc ::BCM::mut::tag_hiders {new_molid} {
    set h [atomselect $new_molid "resname $::BCM::mut::HID_RESNAME"]
    $h set beta  $::BCM::mut::HID_SENTINEL_BETA   ;# sentinel value
    $h set segid $::BCM::mut::HID_SEGID
    # user = stable hider id (probe2: user/user2 fields work + are selectable)
    set ids [$h get index]
    $h set user [list] ;# clear
    set i 0
    foreach idx $ids { $h set user [lreplace [$h get user] $i $i $i]; incr i }  ;# per-atom id
    $h delete
}

# Bulk cleanup handle (NEVER by resid/chain — unstable; same rule as v1)
proc ::BCM::mut::cleanup_select {molid} {
    # resname HID is the primary (loads reliably from PDB); beta<0 is the secondary
    return [atomselect $molid "resname $::BCM::mut::HID_RESNAME"]
}
```

### Pattern 6: `trace variable` for update loops (VMD's signal mechanism)

**What:** VMD fires tcl `trace` callbacks when its global state changes. `vmd_initialize_structure` (mol add/delete), `vmd_molecule` (mol list), `vmd_frame` (array, per-mol frame) are VMD-defined globals that triggers traces. Use these to refresh the GUI's molecule dropdown / per-rep counters when the VMD session changes — the VMD analog of Qt signals.

**When to use:** Whenever the GUI must react to VMD session state. Verified: `clonerep.tcl:232` (`trace variable vmd_molecule w ::CloneRep::UpdateMolecule`), `ramaplot.tcl:217-220` (`vmd_frame`, `vmd_initialize_structure`), `viewmaster.tcl:123`. On dialog destroy, `trace vdelete` to clean up (`ramaplot.tcl:265-267`).

**Trade-offs:** Pro: push-based, no polling. Con: trace callbacks receive `args` (name1 name2 op) — ignore them and re-read state inside the proc.

**Example:**
```tcl
# refresh molecule dropdown when mols are added/deleted
global vmd_initialize_structure
trace variable vmd_initialize_structure w ::BCM::gui::setup::refresh_mol_menu
# ... on dialog destroy:
trace vdelete vmd_initialize_structure w ::BCM::gui::setup::refresh_mol_menu
```

### Pattern 7: Companion-file save — combined PDB + hand-rolled `.bcm` JSON sidecar

**What:** VMD's native `save_state` writes a `.vmd` tcl script that reloads molecules **from their original files** (`save_state.tcl:186` `mol new $file`) and **does NOT preserve beta/user/segid or any script-modified atom data** (save_state.tcl:38-46 header; probe1 Q5: a saved `.vmd` contained NO `beta`/`user`/`segid`). So we save TWO files: the **combined PDB** (the exact game scene — real + hider atoms, written via `atomselect writepdb` + manual append) and a **`.bcm` JSON sidecar** (game metadata: registry found/hidden, timer, setup params, reveal counts, target molid-name). Load reverses both. This is the **direct analog of v1's `.pse` + `.bcm`** (VMD has no binary session format that preserves our sentinels, so the combined PDB replaces the `.pse`).

**When to use:** Save, Load, Generate & export (shareable puzzle), checkpointing.

**Trade-offs:**
- Pro: combined PDB preserves the EXACT game scene (hiders included) — reload is faithful.
- Pro: `.bcm` JSON is human-readable/debuggable and format-identical to v1's sidecar → load logic ports.
- Con: VMD 1.9.3 has **no `json` or `tcllib` package** (probe3 Q-SIDELOAD: `package require json` → "can't find package"). So JSON is **hand-rolled** in tcl 8.5 (use `dict` for structure; a ~40-line emit/parse pair). No external lib needed — but it's manual. Alternative: write a tcl-script state file (the VMD-native pattern, viewmaster.tcl:704-747 `save_state` writes tcl that reconstructs). **Recommend hand-rolled JSON** for v1-consistency + debuggability; the tcl-script approach is the fallback if JSON parsing gets fiddly.
- Con: two files = must keep together on share. Mitigation: same as v1 — document, or offer a `.zip`/tar wrapper.

**Example (`<name>.bcm` schema — mirrors v1's):**
```json
{
  "format": "biochemeleon-save-v2",
  "target_name": "1znf",
  "scene_file": "1znf_game.pdb",
  "setup": { "hider_count": 8, "lock_scene": true, "difficulty": "hard", "per_rep": {} },
  "started_at": "2026-08-22T12:00:00Z",
  "elapsed_seconds": 142.3,
  "reveal_count": 0,
  "hiders": [
    { "index": 482, "rep": "VDW",     "status": "found",  "found_at": 95.1 },
    { "index": 903, "rep": "Cartoon", "status": "hidden", "found_at": null }
  ]
}
```

### Pattern 8: Pure-layer registry with dependency-injected sentinel reconstruction (port of v1)

**What:** `lib/registry.tcl` is stdlib-only tcl — a `dict` keyed by atom `index` → `{rep status found_at hint_used}`, plus per-rep counters, `mark_found`, and `to_dict`/`from_dict` for the `.bcm` sidecar. It has NO `mol`/`atomselect` calls. Sentinel reconstruction (rebuild the registry from the loaded molecule's `resname HID` atoms) takes an injected `fetch_hider_ids` proc, so `registry.tcl` stays pure while `game.tcl` injects `lambda { ::BCM::mut::fetch_all_hider_ids $molid }`. **Direct port of v1's `registry.py` + `reconstruct_from_sentinels` DI.**

**When to use:** Always — this is the testable-core pattern. Verified analogous: v1 `registry.py:1-25` docstring spells out the exact same DI contract.

**Trade-offs:**
- Pro: `tcltest tests/test_registry.test` runs in WSL via `tclsh` with NO VMD install — honest, fast unit tests (tcl's own interpreter; no Python needed). Matches v1's "pure layer is WSL-unit-testable".
- Pro: `dict` (tcl 8.5) is the right structure (v1 used `OrderedDict`; tcl dicts preserve insertion order).
- Con: `index` is only stable within a molid's lifetime (changes on rebuild). Mitigation: rebuild registry on each Start (post-reload); the `.bcm` sidecar reconciles found/hidden post-load by matching on `index` (with a fallback to `(resname resid name)` if index drifted — same caveat as v1's `.pse` reload, v1 ARCHITECTURE.md:449).

---

## Data Flow

### Flow A — Click-to-find (the critical loop)

Every component boundary is crossed exactly once per click, in one direction, traceably (mirrors v1 Flow A):

```
 USER clicks an atom in the OpenGL viewer (mouse mode pick 0 active)
        │
        ▼
 VMD core sets vmd_pick_atom / vmd_pick_molecule globals
        │  + invokes every proc in ::vmd_pick_atom_callbacks
        ▼
 ::BCM::pick::on_pick (interop layer)
        │  reads vmd_pick_molecule (== game molid?) + vmd_pick_atom (index)
        │  filters: ignore picks on molecules other than the game molid
        ▼
 ::BCM::game::on_pick index (controller — no mol, no Tk)
        │
        ├──► ::BCM::registry::is_hider index  →  False? → log "miss" to GameTab; return
        │
        │   True:
        ├──► ::BCM::registry::mark_found index elapsed  → mutates dict
        ├──► ::BCM::adapter::recolor_or_hide molid index → atomselect + mol modcolor / hide rep
        ├──► ::BCM::gui::game::refresh remaining_total remaining_per_rep → ttk label configure
        └──► if [::BCM::registry::all_found]: ::BCM::game::win → stop `after` timer, winning message
        │
        ▼
 viewer ready for next click (mouse stays in pick 0 until deactivate)
```

**Direction strictly enforced:** `pick → game → {registry, adapter, gui}`. GUI never inspects the registry; registry never calls `mol`; pick never touches Tk. This is what makes `::BCM::game::on_pick` unit-testable in WSL (inject a fake registry + fake adapter).

### Flow B — Start

```
 SetupTab (user clicks Start) → ::BCM::gui::dialog::_on_start $params
      → ::BCM::game::start params:
            1. ::BCM::adapter::resolve_target params        # loaded mol / fetch / demo
            2. ::BCM::mut::backup_scene $molid             # snapshot viewpoint+reps, keep original
            3. ::BCM::gen::generate $molid $params         # decide placement per rep → spec list
                 └─ ::BCM::mut::rebuild_with_hiders $molid $specs   # write combined PDB, mol new, tag sentinels
            4. set game_molid [::BCM::mut::current_molid]   # molid changed; update handle
            5. ::BCM::registry::build [::BCM::mut::fetch_all_hider_ids $game_molid]  # dict from sentinels
            6. ::BCM::state::mark_started                  # start_time, setup snapshot
            7. ::BCM::gui::switch_to game                  # enable Game tab, disable Setup
            8. ::BCM::gui::game::countdown 3 2 1 → ::BCM::pick::activate $game_molid  # mouse → pick 0
            9. ::BCM::gui::game::start_timer               # `after 1000` loop
```

### Flow C — Save / Load (checkpointing)

```
 SAVE  (GameTab → ::BCM::game::save):
       1. set snap [::BCM::registry::to_dict]              # dict → JSON-able
       2. ::BCM::state::write_combined_pdb $path_game.pdb  # atomselect all → writepdb (+hiders, sentinels set)
       3. ::BCM::state::write_bcm $path.bcm $snap          # hand-rolled JSON (registry+timer+setup)
       (share: hand user both files together)

 LOAD  (GameTab → ::BCM::game::load):
       1. mol new $path_game.pdb type pdb waitfor all      # restores atoms + hiders + (some) sentinels
       2. ::BCM::mut::tag_hiders $molid                     # re-apply beta/segid/user in-place (robust)
       3. set snap [::BCM::state::read_bcm $path.bcm]       # parse JSON → dict
       4. ::BCM::registry::reconstruct [::BCM::mut::fetch_all_hider_ids $molid]
       5. ::BCM::registry::reconcile_with_bcm $snap         # apply found/hidden + timer
       6. ::BCM::game::resume $snap → switch_to game, ::BCM::pick::activate
```

**Load fidelity:** the combined PDB restores real + hider atoms (probe3). The `.bcm` restores found/hidden + timer. Indices in a reloaded PDB match the save-time indices (atoms load in file order) — but we reconcile via the `resname HID` sentinel rebuild regardless, so index drift between save and load is tolerated (the rebuild keys by current index; `.bcm` matches by index with `(resname resid name)` fallback, same as v1).

---

## Suggested Build Order (phase structure for the v2 roadmap)

The order mirrors v1's successful de-risking sequence (v1-ROADMAP.md), adapted to VMD-specific risks. The single overriding principle (from v1): **ship the load → generate → click-to-find → win loop as soon as the foundation allows**, because if nothing else works, that loop must work.

| Phase | Goal | De-risks what (VMD-specific) | v1 analogue |
|-------|------|------------------------------|-------------|
| **1. Bootstrap & Sourced Entry** | `biochemeleon.tcl` sources cleanly, `vmd_install_extension` registers an Extensions menu item, `biochemeleon` console command opens a modeless `ttk::notebook` dialog with 2 placeholder tabs. Headless smoke: `source` + `biochemeleon` run without error. | extension loading, menu registration, modeless ttk GUI, pkgIndex | v1 Phase 1 |
| **2. Setup Tab + Bundled Demos** | ttk setup form (7 buttons), demo manifest, `mol new` loads bundled PDBs (reused from v1). | VMD `mol new`/`molinfo`, ttk form widgets, demo loading | v1 Phase 2 |
| **3. Mutation Safety & Hider Registry** ⚠️ **HIGHEST RISK** | backup scene → rebuild combined PDB → `mol new` → tag sentinels (atomselect) → cleanup restores original. `registry.tcl` pure dict + sentinel reconstruct (DI). Smoke: backup → rebuild → cleanup → restore leaves original intact. | **the PDB-rebuild approach** (VMD's "no in-place insertion"), **molid-change handling**, viewpoint/rep restore, sentinel robustness (probe3 column lesson) | v1 Phase 3 (de-risked pseudoatom; v2 de-risks PDB rebuild) |
| **4. MVP Core Loop (sphere)** | Player completes a round with sphere hiders: pick callback (`vmd_pick_atom_callbacks` + `mouse mode pick 0`), registry lookup, recolor, `after`-timer, win. **PROJECT core value.** | **pick-callback signature** (Phase-1 validation flag), mouse-mode save/restore, `after` timer loop | v1 Phase 4 |
| **5. Rep Setup + Generator Strategy** | VMD reps are command-based (`mol addrep`/`modstyle`/`modselect`/`modcolor`/`modmaterial`). Per-rep generators (Lines/VDW/Licorice/Cartoon/NewCartoon + sphere). Lock-scene vs randomize. Research which reps blend. | rep command workflow, which VMD reps are viable for the blend-in mechanic (PROJECT requirement) | v1 Phases 5-6 |
| **6. Materials Exploration** (v2 differentiator) | VMD's 24 materials (Glass1/2/3, Translucent, BlownGlass, BlownGlass, EdgyGlass, Ghost, …) as a blending dimension beyond reps. Research which materials aid hiding. | material system integration (`material add`/`change`/`settings`; `mol modmaterial`) — no v1 equivalent | (new — v2 differentiator) |
| **7. In-game Actions** | Hint (recolor N atoms/residues around a hider), reveal-one/reveal-all (confirm), found-hider visibility/color dropdown, restart, save/load. | atomselect recolor, per-rep remaining display (easy mode), restart-from-backup | v1 Phases 7 + 04.1 |
| **8. Persistence** | Combined-PDB + `.bcm` JSON sidecar save/load; Import (Generate & export); restart-on-imported. | hand-rolled JSON (no `json` package — probe3), PDB round-trip fidelity, `.bcm` reconciliation | v1 Phase 8 |
| **9. Large Fetched Demos + Attribution** | 1GZM/3GP6 (MemProtMD) + SASBDB glycoprotein; strip water/salt, compress; reuse v1 `SOURCES.md`. | large-file fetch/cache, VMD load of stripped PDBs | v1 Phase 9 |
| **10. Polish + Help + Demos Reps** | In-game help, endgame stats, demo-specific rep presets, optional `tooltip.tcl` (vendor under `vmd/3rd_party_lib/` if user approves — seek approval per spec). | UX polish, demo rep presets, tooltip approval | v1 Phases 10-11 |

**Phase ordering rationale:**
- **Phase 3 before 4** — the rebuild approach is the highest-risk VMD-specific unknown (no in-place insertion). Proving backup→rebuild→cleanup→restore first means the MVP loop (Phase 4) builds on a verified foundation. (v1 did the same: Phase 3 de-risked mutation before Phase 4 MVP.)
- **Phase 4 before 5/6** — the pick-callback signature is the second unknown (headless can't fire a click). Phase 4 validates it via the simplest generator (sphere = "place anywhere"). Rep-specific generators (Phase 5) and materials (Phase 6) come after the loop is proven.
- **Materials (Phase 6) after reps (Phase 5)** — reps are the primary blend mechanism (proven in v1); materials are a *new* v2 dimension explored once reps are solid.
- **Persistence (Phase 8) after the loop + actions** — saving is meaningful only once a full game is playable.

**Research flags for phases (deeper research likely needed):**
- **Phase 3:** the exact "restore viewpoint + reps on a NEW molid" sequence (viewmaster does it; validate the rep-list round-trip on a `mol new`'d molecule).
- **Phase 4:** the `vmd_pick_atom_callbacks` arg signature — headless CANNOT verify (probe2/3: globals stay unset without a real click). **MUST validate in a real VMD GUI session** (human-verify checkpoint, like v1's Qt-GUI checkpoints).
- **Phase 5:** which VMD reps actually blend (Lines/VDW/Cartoon are obvious; MSMS/Surf/QuickSurf are surface-like and likely excluded like v1's `surface`; research needed).
- **Phase 8:** combined-PDB round-trip fidelity for large molecules (does `atomselect writepdb` preserve all needed fields? does the reload preserve `index` order?).

---

## Scaling Considerations

"Scale" = molecule size, not users (single-user desktop extension).

| Concern | Demo PDB (~1k atoms) | Medium (4WB3, ~5k) | Large membrane (1GZM full, ~50k+ atoms) |
|---------|----------------------|--------------------|------------------------------------------|
| Backup memory (keep original mol hidden) | trivial | fine | ~2× RAM (one extra mol); document, or back up PDB to disk instead of keeping mol loaded |
| Rebuild cost (write+read PDB) | <50ms | ~200ms | ~1-2s — acceptable; warn user before Start on large mols |
| `atomselect` to build registry | <10ms | ~20ms | ~100ms — iterate only `resname HID` (small set), not `all` |
| Picking responsiveness | instant | instant | instant (pick is O(1) dict lookup) |
| `.bcm` + combined-PDB save size | small | small | combined PDB large but acceptable |

### Scaling Priorities

1. **First bottleneck:** rebuild cost on large membrane proteins — cap hider count as a function of atom count (spec's "cap a reasonable number": e.g. `max_hiders = min(user_value, n_atoms // 50)`), and warn the user before Start on mols > ~20k atoms.
2. **Second bottleneck:** backup memory for membrane proteins — back up the PDB to a temp file (not a kept-loaded mol) for large molecules; restore = `mol new <backup.pdb>`.

---

## Anti-Patterns

### Anti-Pattern 1: Putting hiders in a SEPARATE molecule
**What people do:** Create a `hiders` molecule and show it alongside the target. **Why it's wrong:** Defeats the core mechanic — the player just hides the `hiders` molecule and wins trivially. **Do this instead:** PDB-rebuild so hiders and real atoms share ONE molid (Pattern 4; probe3 confirmed the invariant holds). Hard spec requirement (direct port of v1's Anti-Pattern 1).

### Anti-Pattern 2: Trying to insert atoms in-place via `mol addfile`
**What people do:** `mol addfile hiders.pdb molid $existing` expecting an append. **Why it's wrong:** VMD rejects it — "Mismatch between existing molecule or structure file atom count" (probe1 Q1c). `mol addfile` adds FRAMES/coords to an existing structure, NOT new atoms. **Do this instead:** PDB-rebuild — write combined PDB (original + hiders), `mol delete` + `mol new` (Pattern 4). This is the VMD-specific trap that has no v1 equivalent (PyMOL's `cmd.pseudoatom(object=existing)` DID insert in-place).

### Anti-Pattern 3: Relying on PDB columns for the beta/segid sentinel
**What people do:** Write the hider's `beta -999` / `segid GAME` into the PDB ATOM record and expect it to round-trip. **Why it's wrong:** PDB columns are strict and a misaligned beta/occupancy column silently drops the value (probe3 Q-REBUILD2: `beta<0` returned 0 because `1.00-999.00` ran together). **Do this instead:** Load the combined PDB (hider tagged by `resname HID`, which loads reliably), then set `beta`/`segid`/`user` in-place via `atomselect` (Pattern 5; robust against PDB column bugs).

### Anti-Pattern 4: Keying the registry by `resid`/`chain`/`serial`
**What people do:** Use the PDB `serial` or `resid` as the registry key. **Why it's wrong:** Not unique; shifts on edit. **Do this instead:** Key by VMD atom `index` (stable within a molid's lifetime; `$sel get index`); rebuild the registry from sentinels on each Start so index drift across rebuilds is tolerated (direct port of v1's Anti-Pattern 2).

### Anti-Pattern 5: Clobbering the user's mouse mode / pick callbacks
**What people do:** `mouse mode pick 0` on Start without saving the user's current mode, and `set vmd_pick_atom_callbacks {}` without saving the prior list. **Why it's wrong:** Leaves the user stuck in pick mode and destroys any pick callback they registered. **Do this instead:** Snapshot `vmd_mouse_mode`/`vmd_mouse_submode` and the prior `vmd_pick_atom_callbacks` BEFORE switching; restore both on deactivate (Pattern 3; direct port of v1's "save/restore the user's wizard").

### Anti-Pattern 6: Calling `mol`/`atomselect` from GUI procs, or calling Tk from game logic
**What people do:** A button `-command` does `mol addrep …` directly, or `::BCM::game::on_pick` calls `tk_messageBox`. **Why it's wrong:** Couples layers — the pure layer (`registry.tcl`/`setup_state.tcl`) becomes untestable in WSL `tcltest`, and changes ripple everywhere. **Do this instead:** GUI → controller proc → adapter/mutator/pick. Controller notifies GUI via a small callback (`variable on_remaining_cb` etc.) the dialog sets (direct port of v1's Anti-Pattern 4).

### Anti-Pattern 7: Relying on `save_state` to preserve game state
**What people do:** `save_state game.vmd` and expect the hiders + found-status to reload. **Why it's wrong:** VMD `save_state` reloads molecules from their ORIGINAL files (no hiders) and does NOT preserve beta/user/segid or script-modified data (save_state.tcl:38-46; probe1 Q5). **Do this instead:** combined-PDB + `.bcm` sidecar (Pattern 7).

### Anti-Pattern 8: Using `grab set` on the main dialog
**What people do:** `grab set $w` on the PluginDialog to make it modal. **Why it's wrong:** Blocks the OpenGL viewer — the user can't rotate/click, breaking the click-to-find loop. **Do this instead:** Modeless toplevel (Pattern 2). `grab set` is ONLY for small modal sub-dialogs (e.g. a "confirm give up" popup), never the main window (mergestructs.tcl:138 uses `grab set` only on its "select molecule" popup, not the main window).

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes / Gotchas |
|---------|---------------------|-----------------|
| **VMD tcl API** (`mol`, `molinfo`, `atomselect`, `mouse`, `material`, `label`, `graphics`) | Call directly from `lib/` interop procs only. | Single-threaded (VMD main thread); no threads needed for v2. `atomselect` objects MUST be `$sel delete`'d (leaked selections accumulate — every ref plugin deletes them, e.g. `ramaplot.tcl:269`). |
| **VMD pick system** | `lappend ::vmd_pick_atom_callbacks ::BCM::pick::on_pick` + `mouse mode pick 0`; read `vmd_pick_atom`/`vmd_pick_molecule` globals. | Callback arg signature UNVERIFIED headlessly (Phase-4 human-verify). Save/restore user's prior mode + callback list. |
| **VMD Extensions menu** | `vmd_install_extension biochemeleon biochemeleon_tk_cb "Extensions/bioCHEMeleon"` (loadplugins.tcl:114). | Auto-loads via `package require` → needs `pkgIndex.tcl` on `auto_path`. Also define a plain `biochemeleon` command for headless/`.vmdrc` use. |
| **VMD `save_state` (.vmd)** | Do NOT use for game state (drops beta/user/segid). | Use combined-PDB + `.bcm` sidecar instead (Pattern 7). `save_state` IS useful for the user's general session, just not our game state. |
| **RCSB PDB fetch** (demo) | `mol new $url type pdb` or download via tcl `http`/`socket`. | For demos prefer bundled files (reused from v1); fetch is fallback. |
| **MemProtMD / SASBDB** (large/challenge demos) | tcl `http::geturl` into `data/demos/cache/`. | Large files; strip water/salt + compress before bundling (reuse v1's processed files). |
| **tklib `tooltip.tcl`** (optional, Polish) | `source` from vendored `vmd/3rd_party_lib/tooltip/`. | **Seek user approval first** (spec dependency rule); Tcl/Tk license; git-ignore the dir. `vmd-ref/tooltip/pkgIndex.tcl` shows `package ifneeded tooltip 2.0.4`. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| GUI ↔ Controller | `-command` callbacks (GUI→controller); controller → GUI via `variable` callback procs the dialog registers | One-way each direction; no GUI imports in `lib/game.tcl`; no `mol` calls in `gui/`. |
| Controller ↔ Registry | Direct proc calls | Registry is pure tcl `dict`; no I/O. |
| Controller ↔ Adapter/Mutator/Pick | Direct proc calls | All `mol`/`atomselect` confined to `lib/adapter.tcl`/`mutation.tcl`/`pick.tcl`. |
| Controller ↔ StateStore | Direct proc calls | StateStore does file I/O (hand-rolled JSON + PDB) + asks adapter for the combined PDB. |
| Generator ↔ Mutator | Generator computes a *spec* (resname, coords, beta, segid, user-id); Mutator executes the rebuild | Keeps geometry math (testable) separate from VMD side-effects (direct port of v1's Generator↔Mutator split). |
| Pick ↔ Controller | `::BCM::pick::on_pick` calls `::BCM::game::on_pick $idx` | Pick holds a target-molid filter; controller does NOT import pick (avoids cycle). |

---

## Reuse from v1 vs New for v2

| Concept | v1 (PyMOL) | v2 (VMD) | Reuse? |
|---------|-----------|----------|--------|
| Hider sentinel (`segi GAME` + `b=-999` + `resn HID`) | `cmd.pseudoatom` + `cmd.alter` | `atomselect set beta/segid/user` in-place after PDB rebuild | ✅ concept direct-port; mechanism differs |
| Hider registry (keyed by `index`, found/hidden, per-rep counts) | `registry.py` (OrderedDict, pure) | `lib/registry.tcl` (dict, pure) | ✅ direct-port (OrderedDict→dict) |
| Pure layer (stdlib-only, WSL-unit-testable) | `setup_state.py` + `registry.py` (python3.6 unittest) | `lib/setup_state.tcl` + `lib/registry.tcl` (tcltest) | ✅ direct-port (python→tcl) |
| Backup/restore discipline (no undo) | `cmd.create('_bchm_backup', target)` | snapshot viewpoint+reps + keep original mol / write backup PDB | ✅ concept direct-port; mechanism differs |
| 7-button Setup + 2-tab dialog + modeless | Qt `QTabWidget`, `dialog.show()` | Tk `ttk::notebook`, modeless `toplevel` | ✅ UX direct-port; toolkit swap |
| Click→found→refresh loop | `PickWizard.do_pick` → `GameController.on_pick` | `vmd_pick_atom_callbacks` → `::BCM::game::on_pick` | ✅ shape direct-port; mechanism differs |
| `.bcm` JSON sidecar | stdlib `json` | hand-rolled JSON (no `json` package) | ✅ format direct-port; encoder hand-rolled |
| Demo PDB set + `SOURCES.md` | `data/demos/` | `data/demos/` (reused verbatim) | ✅ data direct-reuse |
| Atom insertion mechanism | `cmd.pseudoatom(object=existing)` (in-place) | PDB-rebuild + `mol new` (no in-place) | ❌ NEW — biggest VMD-specific change |
| Rep system | PyMOL GUI-layered reps (`cmd.show`) | VMD command-based reps (`mol addrep`/`modstyle`) | ❌ NEW mechanism (Pattern for Phase 5) |
| Materials as blend dimension | (none — v1 rep-only) | VMD 24 materials (Glass/Translucent/…) | ❌ NEW differentiator (Phase 6) |
| Extension entry | `__init_plugin__` + `addmenuitemqt` | `package provide` + `vmd_install_extension` + `_tk_cb` | ❌ NEW mechanism (Pattern 1) |
| Update loops | Qt signals | `trace variable vmd_*` | ❌ NEW mechanism (Pattern 6) |

---

## Sources

- **VMD bundled plugins** (read in full, cited by file:line above): `vmd-ref/plugins/clonerep1.3/clonerep.tcl`, `ramaplot1.1/ramaplot.tcl`, `autoionize1.4/autoionize.tcl`, `viewmaster2.6/viewmaster.tcl`, `mergestructs1.1/mergestructs.tcl` + each `pkgIndex.tcl`.
- **VMD core scripts**: `…/VMD/scripts/vmd/loadplugins.tcl` (vmd_install_extension), `save_state.tcl` (state-save limits), `vmdinit.tcl` (mouse globals, wm withdraw), `atomselect.tcl` (selection helpers).
- **VMD User's Guide** (https://www.ks.uiuc.edu/Research/vmd/current/ug/): node31 (mouse), node33 (Pick Modes — `mouse mode pick 0` = atom pick, hot keys 1-4).
- **Headless VMD probes** (reproducible at `tmp/vmdprobe/probe{,2,3}.tcl`, gitignored): verified atomselect set/get (beta/segid/user), `mol addfile` count-mismatch rejection, NO undo, 24 materials + `material add/change/settings`, `save_state` drops beta/user, `trace vmd_initialize_structure` fires, `vmd_pick_atom_callbacks` list recognized, `user`/`user2` selectable, combined-PDB rebuild loads hider into same molid, tcl 8.5 + `dict` available, no `json`/`tcllib` package.
- **v1 architecture** (`.planning/research/ARCHITECTURE.md`, `.planning/milestones/v1-ROADMAP.md`, `pymol/biochemeleon/{game,registry}.py`): the layering, registry DI, backup/restore discipline, and build-order rationale being ported.

---
*Architecture research for: VMD 1.9.3 sourced-tcl hide-and-seek game (bioCHEMeleon v2.0)*
*Researched: 2026-08-22*
