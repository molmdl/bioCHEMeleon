# Phase 14: Setup Tab & Bundled Demos — Research (GUI/UX aspect)

**Researched:** 2026-08-29
**Domain:** VMD 1.9.3 Tcl/Tk 8.5.6 + ttk GUI — Setup-tab form, molecule dropdown, Save/Load, collect_state/apply_state round-trip
**Confidence:** HIGH (widget availability + dropdown refresh + save format all cross-verified against reference plugins, the Tcler's Wiki, and the Phase 13 entry script)

## Summary

This document answers "what do I need to know to PLAN the Setup-tab GUI well?" It covers the ttk/Tk widget availability under VMD 1.9.3's bundled Tk 8.5.6, the recommended form layout (widget tree + the 3-mode target selector + 10 per-rep rows), the molecule-dropdown refresh strategy, the Save/Load file format, the `collect_state`/`apply_state` round-trip with the `_loading` guard, and a concrete tcl-8.5-clean skeleton for `gui/setup_tab.tcl`.

Three findings drive the plan:

1. **`ttk::spinbox` is NOT available in Tk 8.5.6.** The Tcler's Wiki explicitly states ttk::spinbox is "New command in Ttk (since tk8.5.9)"; VMD 1.9.3 ships Tk 8.5.6 (`info patchlevel` = 8.5.6, verified three ways per `vmd/AGENTS.md`). The hider-count input must use the **plain (non-ttk) `spinbox`** widget (available since Tk 8.4) or a `ttk::entry` + two small `ttk::button`s + `-validatecommand`. This **corrects** `.planning/research/STACK.md` line 22, which listed `ttk::spinbox` as a provided ttk widget under "Confidence MEDIUM-HIGH (can't verify headless)". It cannot be verified headless precisely because Tk doesn't load in `-dispdev text` — the first GUI smoke is where the absence would bite. The other ttk widgets (notebook/frame/labelframe/button/checkbutton/radiobutton/entry/label/combobox/separator) ARE available (core ttk 8.5.0; Phase 13's entry already uses `ttk::notebook`/`ttk::frame`/`ttk::label` successfully).

2. **The VMD molecule-dropdown idiom is `menubutton` + `menu` (NOT combobox), refreshed via `trace variable vmd_molecule w`.** All 5 reference plugins use plain Tk widgets exclusively (zero `ttk::` matches across `vmd-ref/plugins/`); `clonerep.tcl:231-232` is the canonical pattern (`global vmd_molecule; trace variable vmd_molecule w ::CloneRep::UpdateMolecule` → re-populates the menu from `[molinfo list]`). This is already a locked decision (`.planning/research/FEATURES.md:40`, `SUMMARY.md:141`). A `ttk::combobox` (available in 8.5.0) is an acceptable modern-styled alternative, but the trace-refresh + menubutton pattern is the proven VMD way and matches the ecosystem.

3. **Save/Load uses the VMD-canonical "serialize-as-tcl via `[list]`, load via `source`" pattern** (viewmaster `save_state` line 704-747, VMD core `save_state.tcl` line 144-219). `[list]` gives perfect tcl quoting for the nested dict (per_rep) and list (pdb_pool) values with no hand-rolled parser; `validate_state` (pure layer) clamps on load.

**Primary recommendation:** Build `vmd/gui/setup_tab.tcl` as a flat `::biochemeleon::setup_tab` namespace that populates the `$nb.setup` frame with a `ttk::labelframe`-grouped form (Target / Hiders / Difficulty / Actions); use plain `spinbox` for the hider count; use `menubutton`+`menu` for the loaded-molecule and demo selectors, refreshed by `trace variable vmd_molecule w`; use 3 `ttk::radiobutton`s + frame-`raise` for the loaded/fetch/demo mode selector (the QStackedWidget analog); and round-trip state through `collect_state`/`apply_state` guarded by a namespace `_loading` flag, persisting via `[list set ::biochemeleon::_setup_loaded $state]` + `source`.

## Standard Stack

### Core widgets (verified available in Tk 8.5.6)

| Widget | Available in 8.5.6? | Source / Evidence |
|--------|---------------------|-------------------|
| `ttk::notebook` | YES (8.5.0, core ttk) | Phase 13 entry `vmd/biochemeleon.tcl:91` uses it successfully |
| `ttk::frame` | YES | Phase 13 entry `:92-93` uses it |
| `ttk::labelframe` | YES (core ttk) | `autoionizegui.tcl:104` (plain `labelframe`); ttk variant is core |
| `ttk::label` | YES | Phase 13 entry `:98-99` uses it |
| `ttk::button` | YES (core ttk) | Core ttk widget; reference plugins use plain `button` (style choice) |
| `ttk::checkbutton` | YES (core ttk) | Core ttk; plain `checkbutton` used in `viewmaster.tcl:87` |
| `ttk::radiobutton` | YES (core ttk) | Core ttk; plain `radiobutton` in `mergestructs.tcl:339-362`, `autoionizegui.tcl:105-116` |
| `ttk::entry` | YES (core ttk) | Core ttk; plain `entry` in every reference plugin |
| `ttk::combobox` | YES (8.5.0, core ttk) | Core ttk (original ttk 0.8 widget set). No reference plugin uses it. |
| `ttk::separator` | YES (core ttk) | Core ttk widget |
| **`ttk::spinbox`** | **NO — added in Tk 8.5.9** | **Tcler's Wiki `ttk::spinbox` page: "New command in Ttk (since tk8.5.9). Introduced in Tk version 8.5.9."** VMD 1.9.3 = 8.5.6. **CORRECTS STACK.md:22.** |
| **plain `spinbox`** | **YES — since Tk 8.4** | **Tcler's Wiki `spinbox` page: example opens with `package require Tk 8.4`.** Has `-from`/`-to`/`-increment`/`-command`/`-textvariable`/`-validate`. |
| `menubutton` + `menu` | YES (classic Tk) | `clonerep.tcl:193-199`, `ramaplot.tcl:172-180`, `mergestructs.tcl:145-150` — THE molecule-selector idiom |
| `tk_optionMenu` | YES (built-in Tk proc) | `autoionizegui.tcl:96` — convenience for a fixed-option dropdown menubutton |
| `tk_messageBox` | YES | `clonerep.tcl:183`, `viewmaster.tcl:784`, `ramaplot.tcl` (errors) |
| `tk_dialog` | YES | `clonerep.tcl:46,54,62`, `ramaplot.tcl:478,483` |
| `tk_getOpenFile` | YES | `viewmaster.tcl:753,789`, `mergestructs.tcl:102,115`, `autoionizegui.tcl:72,79`, `save_state.tcl:155` |
| `tk_getSaveFile` | YES | `viewmaster.tcl:684,692`, `ramaplot.tcl:244`, `save_state.tcl:156`, `graphlabels.tcl:110` |
| `trace variable … w` / `trace add variable … write` | YES (Tcl 8.5) | `clonerep.tcl:232` (old form), `autoionizegui.tcl:192` (`trace add variable … write` — new form). Both work in 8.5.6. |

### Confidence note (important caveat)

Widget availability is **HIGH** confidence for ttk::spinbox (absent) and plain spinbox (present) — both explicitly dated on the Tcler's Wiki. For the other ttk widgets it is **MEDIUM-HIGH**: ttk loads (Phase 13 proves `ttk::notebook`/`ttk::frame`/`ttk::label` work) and these are all original-ttk-set widgets present since 8.5.0, but **none can be verified headless** (Tk doesn't load in `-dispdev text` — `package require Tk` fails). The first Phase-14 GUI smoke (human-verify checkpoint) is where any ttk surprise surfaces. Plan a single GUI smoke that creates one of each ttk widget to confirm rendering.

### What the reference plugins actually use (the VMD ecosystem idiom)

`grep ttk:: vmd-ref/plugins/` → **zero matches**. All 5 reference plugins use classic (non-ttk) Tk widgets. This does NOT mean ttk is unavailable (Phase 13 proves it is) — the reference plugins are older code that predates ttk adoption. **Implication for the plan:** mixing plain `spinbox` with ttk widgets is visually slightly inconsistent but fully functional and supported. The plain `spinbox` is the pragmatic choice for the hider count; everything else can be ttk for a modern look.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| plain `spinbox` (hider count) | `ttk::entry` + two `ttk::button`s (−/+) + `-validatecommand` | Fully ttk-styled + more code; no native up/down arrows. Plain `spinbox` is simpler + has native arrows. |
| `menubutton`+`menu` (molecule dropdown) | `ttk::combobox` (available 8.5.0) | combobox is editable + modern; menubutton matches reference plugins + the locked `trace variable vmd_molecule` refresh pattern + is non-editable (safer for loaded-mol names). Recommend menubutton; combobox is acceptable for the demo selector. |
| 3 radiobuttons + frame-`raise` (mode selector) | nested `ttk::notebook` | Nested notebook double-tabs (the outer is already Setup/Game). Radiobuttons+raise is the QStackedWidget analog and the mergestructs/autoionize idiom. |
| `[list]`+`source` save format | hand-rolled `key=value` parser | Parser avoids `source`'s code-execution risk but needs custom quoting for nested dict/list values. `[list]`+`source` is VMD-canonical + robust. |

**Installation:** No packages to install. All widgets ship with VMD 1.9.3's bundled Tcl/Tk 8.5.6. `package require Tk` is implicit in GUI mode (the entry guards GUI code with `if {[info exists ::tk_version]}`).

## Architecture Patterns

### Recommended Project Structure (extends Phase 13)

```
vmd/
├── biochemeleon.tcl        # Phase 13 entry (bootstrap). Phase 14 ADDS:
│                          #   source [file join $_dir gui dialog.tcl]
├── lib/
│   ├── setup_state.tcl     # PURE (Phase 13). Phase 14 EXTENDS: validate_state, randomize_state (mol/logic researcher)
│   ├── registry.tcl        # PURE (Phase 13)
│   └── demos.tcl           # NEW (Phase 14, mol bridge): mol new / molinfo list / fetch_pdb / get_active_reps
│                          #   (the mol/logic researcher owns this; GUI calls it)
├── gui/
│   ├── dialog.tcl          # NEW (Phase 14): ::biochemeleon::open_dialog (toplevel + ttk::notebook) + sources setup_tab.tcl
│   └── setup_tab.tcl       # NEW (Phase 14): ::biochemeleon::setup_tab namespace — the Setup form
└── data/demos/             # Phase 13 (6 bundled PDBs: 1znf 1xdn 5e54 1k8p 2qbz 4wb3)
```

**Locked decision (extract `open_dialog` to `gui/dialog.tcl`):** `.planning/research/ARCHITECTURE.md:123` already specifies `gui/dialog.tcl` (toplevel + ttk::notebook) + `gui/setup_tab.tcl` + `gui/game_tab.tcl` as the GUI layer. This keeps the entry script a thin bootstrap (re-source guard + `package provide` + `namespace eval` + source lib/gui + `vmd_install_extension`) and scales to Phase 16 (Game tab). **Recommendation: extract.** The entry keeps the public procs (`biochemeleon`, `biochemeleon_tk_cb`) and the menu registration; `gui/dialog.tcl` defines `::biochemeleon::open_dialog` and sources `gui/setup_tab.tcl` (and, later, `gui/game_tab.tcl`). Proc resolution is at call-time in tcl, so sourcing `gui/dialog.tcl` at load-time before any user interaction is safe.

**Namespace (locked by Phase 13):** `::biochemeleon::` (flat, NOT the pre-Phase-13 `::BCM::` seen in older research docs). The new module is `::biochemeleon::setup_tab` (mirroring `::biochemeleon::setup_state` for `lib/setup_state.tcl`). The mol bridge is `::biochemeleon::demos`.

### Pattern 1: Modeless toplevel + ttk::notebook (Phase 13 — already built)

`open_dialog` (moving to `gui/dialog.tcl`) creates `toplevel .biochemeleon`, a `ttk::notebook $w.nb` with Setup + Game tabs, and calls `::biochemeleon::setup_tab::build $nb.setup` to populate the Setup tab. NO `grab set` on the main panel (ENTRY-01). Singleton re-show via `winfo exists` + `wm deiconify`. (Phase 13 established this; Phase 14 only adds the `setup_tab::build` call + the `source gui/dialog.tcl` line.)

### Pattern 2: 3-mode target selector — radiobuttons + frame-`raise` (the QStackedWidget analog)

**What:** v1 used a `QComboBox` (mode) + `QStackedWidget` (3 pages: loaded-object combo / PDB-fetch entry / demo combo). The tcl/ttk idiom is 3 `ttk::radiobutton`s sharing a `-variable`, each `-command` raising the corresponding page frame.

**When to use:** The Setup tab's "Target" group (SETUP-01): loaded molecule / fetch from PDB / bundled demo.

**Example (verified idiom — grid all 3 pages in ONE cell, `raise` the chosen one):**
```tcl
# Source: the standard tcl "stacked frames in one grid cell" idiom
# (analog of QStackedWidget; used by mergestructs.tcl:56-83 grid layout).
namespace eval ::biochemeleon::setup_tab {
    variable mode "loaded"   ;# "loaded" | "fetch" | "demo"
    variable _pages          ;# page-frame path array
}

proc ::biochemeleon::setup_tab::build_target_group {parent} {
    variable mode
    variable _pages
    set g [ttk::labelframe $parent.target -text "Target" -padding 6]

    ttk::radiobutton $g.rload -text "Loaded object" -value loaded \
        -variable ::biochemeleon::setup_tab::mode \
        -command {::biochemeleon::setup_tab::switch_page}
    ttk::radiobutton $g.rfetch -text "Fetch from PDB" -value fetch \
        -variable ::biochemeleon::setup_tab::mode \
        -command {::biochemeleon::setup_tab::switch_page}
    ttk::radiobutton $g.rdemo -text "Bundled demo" -value demo \
        -variable ::biochemeleon::setup_tab::mode \
        -command {::biochemeleon::setup_tab::switch_page}
    grid $g.rload $g.rfetch $g.rdemo -sticky w -padx 2

    # The stacked-pages container — all 3 gridded in the SAME cell; raise one.
    set p [ttk::frame $g.pages]
    grid $p -row 1 -column 0 -columnspan 3 -sticky news -pady 4

    set pl [ttk::frame $p.loaded]   ;# page 0: loaded-mol menubutton + Refresh
    set pf [ttk::frame $p.fetch]    ;# page 1: PDB code entry + Fetch button
    set pd [ttk::frame $p.demo]     ;# page 2: demo menubutton/combobox
    set _pages(loaded) $pl
    set _pages(fetch)  $pf
    set _pages(demo)   $pd
    grid $pl -row 0 -column 0 -sticky news
    grid $pf -row 0 -column 0 -sticky news
    grid $pd -row 0 -column 0 -sticky news
    raise $pl    ;# default page
    return $g
}

proc ::biochemeleon::setup_tab::switch_page {} {
    variable mode
    variable _pages
    if {[info exists _pages($mode)]} { raise $_pages($mode) }
}
```

### Pattern 3: Molecule dropdown — `menubutton` + `menu` + `radiobutton` entries (the VMD idiom)

**What:** A non-editable dropdown built from a `menubutton` (shows the current value via `-textvariable`) + a `menu` whose entries are `radiobutton`s (one per loaded molecule, sharing the `-variable`). On molecule add/delete, a `trace` re-populates the menu.

**When to use:** The "loaded object" page (SETUP-01) and the "bundled demo" page (fixed list of 6).

**Example (the clonerep pattern, lines 193-199 + 243-288):**
```tcl
# Source: vmd-ref/plugins/clonerep1.3/clonerep.tcl:193-199, 231-232, 243-288
proc ::biochemeleon::setup_tab::build_loaded_page {parent} {
    menubutton $parent.mol -relief raised -bd 2 -direction flush \
        -textvariable ::biochemeleon::setup_tab::selected_mol \
        -menu $parent.mol.menu
    menu $parent.mol.menu -tearoff no
    button $parent.refresh -text "Refresh" -width 8 \
        -command {::biochemeleon::setup_tab::refresh_mol_menu}
    pack $parent.mol -side left -fill x -expand yes
    pack $parent.refresh -side left -padx 4
    # Register the trace that auto-refreshes on mol add/delete:
    global vmd_molecule
    trace variable vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu
    refresh_mol_menu   ;# populate now
}

proc ::biochemeleon::setup_tab::refresh_mol_menu {args} {
    variable w
    set menu $w...mol.menu   ;# resolve the menu path (see skeleton)
    $menu delete 0 end
    foreach id [molinfo list] {
        if {[molinfo $id get filetype] eq "graphics"} continue  ;# skip dummy 'graphics' mols
        $menu add radiobutton -value $id \
            -label "$id [molinfo $id get name]" \
            -variable ::biochemeleon::setup_tab::selected_mol
    }
    if {[llength [molinfo list]] == 0} {
        $menu add command -label "None loaded" -state disabled
    }
}
```
**Note:** `trace variable vmd_molecule w` passes `args` (the trace callback signature is `{name1 name2 op}`); the proc must accept `args` or those three. `vmd_molecule` is an ARRAY (`.planning/research/FEATURES.md:40` — verified) so the trace fires on element writes; the `args`-accepting proc handles both array and scalar forms.

### Pattern 4: Per-rep rows — `grid` with `incr row` (10 reps)

**What:** One row per rep in `GAME_REPS` (10 reps in v2 vs v1's 5): a `ttk::checkbutton` (select the rep) + a `spinbox` (per-rep count, disabled when unchecked) + a `ttk::label` showing "random" when unchecked.

**When to use:** The "Hiders → Per-rep hider counts" group (SETUP-04).

**Layout concern (10 rows):** 10 rows + a hider-count row + lock-scene checkbox may exceed a short screen. **Recommendation:** build the plain grid first (10 rows fit on most laptop screens at default font); if the human-verify checkpoint shows overflow, wrap the per-rep group in a scrollable frame (`canvas` + `ttk::scrollbar` + inner `ttk::frame`, the standard tcl scrollable-frame idiom). Don't pre-build the scrollable wrapper — it adds complexity for a case that may not occur.

**Example:**
```tcl
proc ::biochemeleon::setup_tab::build_per_rep_group {parent} {
    set g [ttk::labelframe $parent.per_rep -text "Per-rep hider counts (unchecked = random)" -padding 6]
    set row 0
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        set cb [ttk::checkbutton $g.c$row -text $rep \
            -variable ::biochemeleon::setup_tab::rep_sel($rep) \
            -command [list ::biochemeleon::setup_tab::on_rep_toggled $rep]]
        set sp [spinbox $g.s$row -from 0 -to 50 -increment 1 -width 5 \
            -textvariable ::biochemeleon::setup_tab::rep_cnt($rep) \
            -command [list ::biochemeleon::setup_tab::recompute_per_rep_maxes] \
            -state disabled]
        set lb [ttk::label $g.l$row -text "random"]
        grid $cb -row $row -column 0 -sticky w
        grid $sp -row $row -column 1 -sticky w -padx 4
        grid $lb -row $row -column 2 -sticky w
        incr row
    }
    return $g
}
```

### Pattern 5: Hider count — plain `spinbox` with dynamic cap

**What:** The hider count needs up/down spinner semantics + a cap that changes with the loaded molecule's atom count. Use the **plain `spinbox`** (ttk::spinbox is absent in 8.5.6). Cap via `configure -to $cap`; clamp manual entry via a `-validatecommand` or a trace on the `-textvariable`.

**Example:**
```tcl
# Source: Tcler's Wiki spinbox page (package require Tk 8.4) + v1 gui_setup.py:199-205
proc ::biochemeleon::setup_tab::build_hider_count {parent} {
    set f [ttk::frame $parent.hcount]
    ttk::label $f.l -text "Hider count:"
    # plain spinbox (NOT ttk::spinbox — absent in 8.5.6). -to is reconfigured on target change.
    spinbox $f.spin -from 1 -to 50 -increment 1 -width 6 \
        -textvariable ::biochemeleon::setup_tab::hider_count \
        -command {::biochemeleon::setup_tab::recompute_per_rep_maxes}
    pack $f.l -side left -padx 4
    pack $f.spin -side left
    return $f
}
# On target change (loaded mol selected), recompute cap:
proc ::biochemeleon::setup_tab::update_cap {} {
    variable w
    variable hider_count
    set atom_count [::biochemeleon::demos::atom_count_for_current] ;# bridge; 0/{} if none
    set cap [::biochemeleon::setup_state::hider_count_cap $atom_count]
    $w...hcount.spin configure -to [expr {max(1,$cap)}]
    if {$hider_count > $cap} { set hider_count $cap }   ;# clamp overflow
}
```

### Pattern 6: `collect_state` / `apply_state` + `_loading` guard (v1 round-trip, ported to tcl)

**What:** `collect_state` snapshots every widget into a tcl `dict`; `apply_state` repopulates every widget from a dict (used by Reset/Load/Randomize/init). A namespace `_loading` flag suppresses cascading recompute callbacks during `apply_state` (the direct port of v1's `self._loading` boolean, `gui_setup.py:567-617`).

**When to use:** Every action button (Reset → `apply_state DEFAULTS`; Randomize → `apply_state [randomize_state ...]`; Load → `apply_state [validate_state $loaded]`), plus dialog init.

**The `_loading` guard in tcl:** In tcl, programmatically setting a `-textvariable`-bound variable DOES fire any `trace` on that variable, and `$widget invoke`/`-command` callbacks fire if you invoke them. The guard prevents the cascade (e.g., setting `mode` would fire `switch_page`; setting hider_count would fire `recompute_per_rep_maxes`). Each recompute/refresh callback checks `if {$::biochemeleon::setup_tab::_loading} { return }` at the top.

**Example:**
```tcl
namespace eval ::biochemeleon::setup_tab {
    variable _loading 0   ;# guard: suppress cascading callbacks during apply_state
}

proc ::biochemeleon::setup_tab::collect_state {} {
    variable mode selected_mol pdb_code demo_id hider_count lock_scene
    variable rep_sel rep_cnt difficulty_easy lock_source
    set per_rep [dict create]
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        if {[info exists rep_sel($rep)] && $rep_sel($rep)} {
            set c [expr {[info exists rep_cnt($rep)] ? $rep_cnt($rep) : 0}]
            if {$c > 0} { dict set per_rep $rep $c }
        }
    }
    return [dict create \
        format          $::biochemeleon::setup_state::SETUP_FORMAT \
        target_mode     $mode \
        selected_object [string trim $selected_mol] \
        pdb_code        [string tolower [string trim $pdb_code]] \
        demo_id         $demo_id \
        hider_count     [expr {int($hider_count)}] \
        lock_scene      [expr {!!$lock_scene}] \
        per_rep         $per_rep \
        difficulty_easy [expr {!!$difficulty_easy}] \
        lock_source     [expr {!!$lock_source}] \
        pdb_pool        [list] ]   ;# pool editor is a later refinement (Gap 4)
}

proc ::biochemeleon::setup_tab::apply_state {state} {
    variable _loading
    variable mode selected_mol pdb_code demo_id hider_count lock_scene
    variable rep_sel rep_cnt difficulty_easy lock_source
    set _loading 1   ;# suppress cascading callbacks (the v1 _loading port)
    # use catch so a half-populated dict can't leave _loading set
    set code [catch {
        set mode          [dict get $state target_mode]
        set selected_mol  [dict get $state selected_object]
        set pdb_code      [dict get $state pdb_code]
        set demo_id       [dict get $state demo_id]
        set hider_count   [dict get $state hider_count]
        set lock_scene    [dict get $state lock_scene]
        set difficulty_easy [dict get $state difficulty_easy]
        set lock_source   [dict get $state lock_source]
        ::biochemeleon::setup_tab::switch_page   ;# reflect new mode
        set pr [dict get $state per_rep]
        foreach rep $::biochemeleon::setup_state::GAME_REPS {
            if {[dict exists $pr $rep]} {
                set rep_sel($rep) 1
                set rep_cnt($rep) [dict get $pr $rep]
            } else {
                set rep_sel($rep) 0
                set rep_cnt($rep) 0
            }
        }
        # on_rep_toggled re-enables spinboxes for selected reps (guarded by _loading)
        foreach rep $::biochemeleon::setup_state::GAME_REPS {
            ::biochemeleon::setup_tab::on_rep_toggled $rep
        }
    } err]
    set _loading 0
    if {$code} { error $err }   ;# re-throw; _loading is already reset (no try/finally in 8.5)
    # persist the last-applied state so it survives dialog destroy/recreate
    dict set ::biochemeleon::state setup $state
}
```
**Note on the guard + error handling:** Tcl 8.5 has no `try`/`finally`, so the `catch`-around-body + explicit `set _loading 0` after is the idiomatic way to guarantee the flag resets (the `autoionize.tcl:81-88` catch pattern). `dict get` on a missing key errors — Phase 14's `apply_state` should accept a dict that may lack keys (use `dict get $state key $default` — the 3-arg form, available in 8.5) OR have `validate_state` fill all keys first (recommended: always pass a `validate_state`-filled dict to `apply_state`).

### Pattern 7: Setup-state persistence across dialog destroy/recreate

**Where setup state lives:** Phase 13's entry already creates `::biochemeleon::state` with a `setup` key (`biochemeleon.tcl:46-48`: `set state [dict create timer 0 found [list] setup [dict create]]`). Phase 14's `apply_state` writes the last-applied state into `dict set ::biochemeleon::state setup $state` (see Pattern 6). On `open_dialog`, if `[dict get $::biochemeleon::state setup]` has a `format` key, `apply_state` from it; else `apply_state DEFAULTS`. This survives the user closing the toplevel (which destroys the widgets — Phase 13 has no `WM_DELETE_WINDOW` handler) and re-running `biochemeleon`.

**Recommendation:** Add a `wm protocol $w WM_DELETE_WINDOW ::biochemeleon::on_close` handler in `gui/dialog.tcl` that does `dict set ::biochemeleon::state setup [::biochemeleon::setup_tab::collect_state]; destroy $w` so in-progress (un-applied) edits are also preserved. (Phase 13 has no such handler; Phase 14 should add it — small, clean.)

### Anti-Patterns to Avoid

- **Do NOT use `ttk::spinbox`** — it doesn't exist in Tk 8.5.6. Use plain `spinbox` or `ttk::entry`+buttons. (Would silently fail at first GUI run.)
- **Do NOT use `grab set` on the main `.biochemeleon` toplevel** — blocks the 3D viewer for click-to-find (ENTRY-01). `grab set` IS allowed on brief transient children (e.g., a modal confirm sub-dialog — the `mergestructs.tcl:138` pattern), but the Setup tab needs none.
- **Do NOT use `lmap`/`try`/`throw`/`finally`/`tailcall`/`coroutine`/`yield`** — Tcl 8.6 idioms, absent in 8.5.6. Use `foreach`+`lappend`, `catch`, and explicit state-reset (the `vmd/AGENTS.md` Tcl 8.5 gotchas + the grep gate `grep -rnE "\blmap\b|\btry\b|\bthrow\b|\btailcall\b|\bcoroutine\b|\byield\b|\bfinally\b" vmd/lib/ vmd/gui/` must return zero).
- **Do NOT put raw `mol`/`atomselect`/`tk`/`toplevel`/`ttk` in `vmd/lib/`** — the pure-layer grep gate (`vmd/lib/` must have ZERO such references). `mol`/`molinfo`/`atomselect` belong in `vmd/lib/demos.tcl` (the mol bridge — owned by the mol/logic researcher) and `vmd/gui/setup_tab.tcl` (which may use them). `setup_state.tcl`/`registry.tcl` stay pure.
- **Do NOT use bare `tk_version` inside a proc** — checks LOCAL scope only (the locked Phase 13 lesson). Use `info exists ::tk_version` (global qualifier).
- **Do NOT forget `trace vdelete` on dialog destroy** — leaking a `trace variable vmd_molecule w` callback to a destroyed widget causes errors on later mol add/delete. Follow the `ramaplot.tcl:265-267` cleanup pattern in the `WM_DELETE_WINDOW` handler (or a `<Destroy>` bind).
- **Do NOT cache a `menubutton`'s menu path in a proc-local var across dialog destroy** — use `winfo exists` guards. The menu path is stable for the toplevel's lifetime, but after destroy+recreate the path is fresh.
- **Do NOT use `vwait` on a variable you set in the same proc** — infinite loop (Tcl 8.5 gotcha). The Setup tab has no need for `vwait` (it's event-driven via `-command`/`trace`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Molecule dropdown | custom listbox+buttons | `menubutton`+`menu`+`radiobutton` entries | The clonerep/ramaplot pattern; refresh via `trace variable vmd_molecule w` is free; native VMD look |
| Dropdown refresh | poll `[molinfo list]` on a timer / on focus | `trace variable vmd_molecule w` | Event-driven, zero-overhead, the locked VMD idiom (FEATURES.md:40) |
| Spinner (hider count) | custom `ttk::entry` + 2 buttons + wheel binding | plain `spinbox` (`-from`/`-to`/`-increment`/`-command`) | Native arrows + built-in clamping via `-to`; ttk::spinbox is absent in 8.5.6 |
| File dialogs (Save/Load Setup) | custom toplevel + entry + browse | `tk_getSaveFile` / `tk_getOpenFile` | Built-in, modal, `-filetypes`/`-defaultextension`/`-parent` (viewmaster/ramaplot pattern) |
| Error/info popups | custom toplevel + label + OK button | `tk_messageBox` / `tk_dialog` | Built-in, modal, themed (clonerep/ramaplot pattern) |
| Setup-state serialization | custom key=value parser with manual quoting | `[list set ::var $dict]` + `source` | Tcl's `[list]` quotes nested dict/list values perfectly (viewmaster/save_state canonical) |
| State validation on load | ad-hoc clamping in the GUI | `::biochemeleon::setup_state::validate_state` (pure) | The pure layer owns clamping; keeps GUI thin + unit-testable (the mol/logic researcher extends validate_state) |
| Mode selector (loaded/fetch/demo) | nested `ttk::notebook` | `ttk::radiobutton`s + frame-`raise` | Avoids double-tab; the QStackedWidget analog; mergestructs/autoionize idiom |

**Key insight:** Every GUI interaction that needs mol state goes through `::biochemeleon::demos::*` (the mol bridge — owned by the mol/logic researcher). The GUI holds NO game logic and mutates molecules ONLY by calling the bridge (e.g., selecting a bundled demo calls `::biochemeleon::demos::load_demo $demo_id`, which does `mol new`). This keeps `setup_tab.tcl` testable in isolation (the bridge can be stubbed) and matches `.planning/research/ARCHITECTURE.md:84` ("SetupTab emits intents, never mutates molecules" — mutation happens via the bridge).

## Common Pitfalls (GUI-specific)

### Pitfall 1: `ttk::spinbox` silently absent (the objective's flagged risk)
**What goes wrong:** Code uses `ttk::spinbox .s -from 1 -to 50`; first GUI run errors "invalid command name ttk::spinbox".
**Why it happens:** ttk::spinbox was added in Tk 8.5.9; VMD 1.9.3 ships 8.5.6. STACK.md:22 listed it under "MEDIUM-HIGH confidence" but it was never verified (can't verify headless — Tk doesn't load in `-dispdev text`).
**How to avoid:** Use plain `spinbox` (since Tk 8.4) for the hider count. If ttk visual consistency is required, use `ttk::entry` + two `ttk::button`s + `-validatecommand`. **Add a Phase-14 GUI smoke that creates `spinbox .s` + one of each ttk widget to confirm rendering.**
**Warning signs:** "invalid command name ttk::spinbox" at first GUI run.

### Pitfall 2: `trace variable vmd_molecule w` callback signature
**What goes wrong:** `proc refresh_mol_menu {} {...}` errors "wrong # args" when the trace fires.
**Why it happens:** A write-trace callback is invoked with 3 args (`name1 name2 op`); for an array-traced variable, all 3 are passed. A proc that takes no args rejects them.
**How to avoid:** Define `proc refresh_mol_menu {args} {...}` (accept any args, ignore them). This is the ramaplot `ramaUpdateMolecules {args}` pattern (`ramaplot.tcl:272`) and the viewmaster `update_molecules {args}` pattern (`viewmaster.tcl:132`).
**Warning signs:** "wrong # args: should be ... ::biochemeleon::setup_tab::refresh_mol_menu" on mol load.

### Pitfall 3: `_loading` guard left set after an error in `apply_state`
**What goes wrong:** A `dict get` on a missing key errors mid-`apply_state`; `_loading` stays 1; all subsequent user callbacks no-op (the form appears frozen).
**Why it happens:** Tcl 8.5 has no `finally`; a bare error mid-body skips the `set _loading 0`.
**How to avoid:** Wrap the body in `catch` and ALWAYS `set _loading 0` after (the Pattern 6 idiom), OR always pass a `validate_state`-filled dict to `apply_state` (so no key is missing). Prefer both.
**Warning signs:** Form stops responding after a Load/Reset; `_loading` is 1.

### Pitfall 4: `source`-ing a Setup file executes arbitrary tcl
**What goes wrong:** A malicious/corrupt `.bcm.setup` file runs arbitrary tcl on Load.
**Why it happens:** The recommended save format is `[list set ::var $dict]` + `source` (the viewmaster canonical pattern) — `source` evaluates the file.
**How to avoid:** It's the user's own file (same trust model as viewmaster/save_state which `source` files). `validate_state` clamps values. If a no-code-execution path is preferred, hand-roll a `key [list VALUE]` line parser (more fragile quoting for nested dict/list values). Recommend the `[list]`+`source` pattern; note the tradeoff.
**Warning signs:** None (the risk is silent code execution). Mitigated by user-chosen file + validate_state.

### Pitfall 5: Leaked `trace variable vmd_molecule w` after dialog destroy
**What goes wrong:** User closes the toplevel; later `mol new` fires the trace; the callback touches a destroyed widget → error spam.
**Why it happens:** Phase 13 has no `WM_DELETE_WINDOW` handler; the toplevel is destroyed but the trace persists.
**How to avoid:** In the `WM_DELETE_WINDOW` handler (Pattern 7), `trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu` before `destroy` (the `ramaplot.tcl:265-267` cleanup pattern). Or use a `<Destroy>` bind on the toplevel.
**Warning signs:** "invalid command name" errors on mol load after closing+reopening the dialog.

### Pitfall 6: Plain `spinbox` `-to` cap not reconfigured on target change
**What goes wrong:** User loads a small molecule (cap 4); the spinbox still allows up to 50 (the default `-to`); they set 10 hiders for a 212-atom molecule.
**Why it happens:** `-to` is set once at build time; the cap must be reconfigured when the target changes.
**How to avoid:** In the target-change callback (trace on `selected_mol` / demo-select command / fetch-success), call `$spinbox configure -to $cap` and clamp the current value. (Pattern 5.)
**Warning signs:** Hider count exceeds the molecule's sane cap.

### Pitfall 7: `expr` unbraced / unbraced variable in `-command` scripts
**What goes wrong:** `-command {set x $y + 1}` silently mis-evaluates; or `expr $a+$b` is an injection risk.
**Why it happens:** Tcl 8.5 gotcha (`vmd/AGENTS.md`).
**How to avoid:** Always brace `expr`: `[expr {$a + $b}]`. For `-command` scripts that need runtime values, build them with `[list ...]` (e.g., `-command [list ::proc $rep]`), NOT string interpolation.
**Warning signs:** Wrong numeric results; "syntax error in expression".

### Pitfall 8: Mixing `trace variable` (old) and `trace add variable` (new) forms
**What goes wrong:** Inconsistent trace forms; `trace vdelete` doesn't match the `trace add variable` registration.
**Why it happens:** Both forms work in 8.5; `trace variable v w` is the old form, `trace add variable v write` is the new form. Their delete counterparts differ (`trace vdelete` vs `trace remove variable`).
**How to avoid:** Pick ONE form per module. The reference plugins use the old form (`trace variable … w` / `trace vdelete … w`). Recommend the old form for consistency with clonerep/ramaplot (the patterns the planner will mirror). Delete with `trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu`.

## Code Examples

### Save/Load format (VMD-canonical `[list]` serialization + `source`)

```tcl
# Source: vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:704-747 (save_state) + 751-765 (load_state)
#         vmd-ref/scripts/save_state.tcl:144-219 (VMD core save_state — same source-back pattern)

# Save: serialize the setup dict via [list] (perfect tcl quoting for nested dict/list).
proc ::biochemeleon::setup_tab::do_save {} {
    variable w
    set fname [tk_getSaveFile -defaultextension ".bcm.setup" \
        -title "Save bioCHEMeleon Setup" \
        -filetypes [list {{bioCHEMeleon Setup} {.bcm.setup}} {{All files} {*}}] \
        -parent $w]
    if {$fname eq ""} { return }
    set fd [open $fname w]
    puts $fd "# bioCHEMeleon setup v2 (machine-generated; source-ing loads it)"
    # [list] serializes the entire command with full quoting — handles per_rep dict + pdb_pool list.
    puts $fd [list set ::biochemeleon::_setup_loaded [collect_state]]
    close $fd
}

# Load: source the file (sets ::biochemeleon::_setup_loaded), read+unset, validate, apply.
proc ::biochemeleon::setup_tab::do_load {} {
    variable w
    set fname [tk_getOpenFile -defaultextension ".bcm.setup" \
        -title "Load bioCHEMeleon Setup" \
        -filetypes [list {{bioCHEMeleon Setup} {.bcm.setup}} {{All files} {*}}] \
        -parent $w]
    if {$fname eq ""} { return }
    if {[catch {uplevel #0 [list source $fname]} err]} {
        tk_messageBox -icon warning -parent $w -title "Load failed" \
            -message "Could not read setup file:\n$err"
        return
    }
    if {![info exists ::biochemeleon::_setup_loaded]} {
        tk_messageBox -icon warning -parent $w -title "Load failed" \
            -message "Setup file did not set the setup state."
        return
    }
    set state $::biochemeleon::_setup_loaded
    unset ::biochemeleon::_setup_loaded
    # validate_state (pure layer) clamps/fills defaults before apply_state.
    apply_state [::biochemeleon::setup_state::validate_state $state]
}
```

### Action buttons (Reset / Randomize / Save / Load)

```tcl
proc ::biochemeleon::setup_tab::build_actions {parent} {
    set f [ttk::frame $parent.actions]
    ttk::button $f.reset  -text "Reset"        -command {::biochemeleon::setup_tab::do_reset}
    ttk::button $f.random -text "Randomize"   -command {::biochemeleon::setup_tab::do_randomize}
    ttk::button $f.save   -text "Save Setup…" -command {::biochemeleon::setup_tab::do_save}
    ttk::button $f.load   -text "Load Setup…" -command {::biochemeleon::setup_tab::do_load}
    pack $f.reset $f.random $f.save $f.load -side left -padx 4 -pady 4
    return $f
}

proc ::biochemeleon::setup_tab::do_reset {} {
    apply_state $::biochemeleon::setup_state::DEFAULTS
}

proc ::biochemeleon::setup_tab::do_randomize {} {
    # randomize_state is pure (the mol/logic researcher extends it from the stub).
    # Pass the current target's atom_count so the cap is respected; lock_source preserved.
    set atom_count [::biochemeleon::demos::atom_count_for_current]   ;# bridge
    set lock_src [info exists ::biochemeleon::setup_tab::lock_source] ;# read the var
    apply_state [::biochemeleon::setup_state::randomize_state \
        -atom_count $atom_count -lock_source $lock_src]
}
```

### Concrete skeleton — `vmd/gui/setup_tab.tcl` (verified tcl-8.5-clean, planner-ready)

```tcl
# vmd/gui/setup_tab.tcl -- Phase 14 Setup tab (GUI layer).
# Tk/ttk + mol (via ::biochemeleon::demos bridge). NOT pure.
# Sourced by gui/dialog.tcl. Namespace: ::biochemeleon::setup_tab.
# Tcl 8.5.6: NO lmap/try/finally -- foreach+lappend + catch only.

namespace eval ::biochemeleon::setup_tab {
    # Live widget-bound state (read by collect_state, set by apply_state).
    variable mode            "loaded"   ;# "loaded" | "fetch" | "demo"
    variable selected_mol    ""         ;# loaded-mol id (menubutton -textvariable)
    variable pdb_code        ""         ;# fetch entry
    variable demo_id         "1znf"      ;# demo menubutton/combobox
    variable hider_count     10
    variable lock_scene     0
    variable difficulty_easy 1
    variable lock_source    0
    variable rep_sel                    ;# array rep -> 0/1 (checkbutton)
    variable rep_cnt                    ;# array rep -> int  (spinbox)
    variable _loading      0            ;# guard: suppress cascading callbacks in apply_state
    variable _pages                     ;# array mode -> page-frame path
    variable w                          ;# toplevel handle (set by build)
    namespace export build collect_state apply_state
}

# Build the Setup tab into $parent (the $nb.setup frame from open_dialog).
proc ::biochemeleon::setup_tab::build {parent} {
    variable w
    set w [winfo toplevel $parent]
    # Target group (SETUP-01): 3-mode selector + stacked pages + lock-source
    set tg [build_target_group $parent]
    # Hiders group (SETUP-02/03/04): hider count + lock-scene + per-rep rows
    set hg [build_hiders_group $parent]
    # Difficulty group (SETUP-05)
    set dg [build_diff_group $parent]
    # Actions group (BTN-01..04)
    set ag [build_actions $parent]
    pack $tg $hg $dg $ag -side top -fill x -padx 8 -pady 6
    # Initialize widgets from persisted state or DEFAULTS
    set saved [dict get $::biochemeleon::state setup]
    if {[dict exists $saved format]} {
        apply_state [::biochemeleon::setup_state::validate_state $saved]
    } else {
        apply_state $::biochemeleon::setup_state::DEFAULTS
    }
}

# --- group builders (build_target_group / build_hiders_group / build_diff_group /
#     build_actions) — see Patterns 2/4/5 + the action-buttons example above. ---

# --- collect_state / apply_state — see Pattern 6. ---

# --- switch_page / refresh_mol_menu / on_rep_toggled / recompute_per_rep_maxes /
#     update_cap / do_reset / do_randomize / do_save / do_load — see Patterns + examples. ---
```

(The skeleton is intentionally open: each `build_*` + each callback maps to one plan task. The planner splits these into TDD tasks: build the widget tree, wire collect_state, wire apply_state, wire each button, wire the trace refresh, then the GUI smoke.)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ttk::spinbox` (assumed available) | plain `spinbox` (Tk 8.4+) for VMD 1.9.3 | ttk::spinbox = Tk 8.5.9 (2009); VMD 1.9.3 ships 8.5.6 | Hider count uses classic spinbox; minor visual inconsistency with ttk widgets |
| `QComboBox` (v1 PyMOL) | `menubutton`+`menu`+`radiobutton` (v2 VMD) | v1→v2 toolkit swap | Non-editable dropdown; refresh via `trace variable vmd_molecule w` |
| `QStackedWidget` (v1) | 3 `ttk::radiobutton`s + frame-`raise` (v2) | v1→v2 toolkit swap | Same UX (one page visible at a time), tcl idiom |
| `json` package (v1 Python) | `[list]` serialization + `source` (v2 tcl) | No `json` in VMD 1.9.3 | Setup files are tcl scripts; `[list]` quoting handles nested dict/list |

**Deprecated/outdated (within VMD 1.9.3):**
- Pre-Phase-13 `::BCM::` namespace (older research docs) — replaced by `::biochemeleon::` (Phase 13 locked).
- STACK.md:22's listing of `ttk::spinbox` as provided — **corrected here** (absent in 8.5.6).

## Open Questions

1. **Does `trace variable vmd_molecule w` fire BEFORE or AFTER a `mol new`-loaded molecule is ready (in `[molinfo list]`)?**
   - What we know: `clonerep.tcl:232` uses exactly this trace and re-reads `[molinfo list]` in the callback — so by callback time the mol is in the list. HIGH confidence the pattern works.
   - What's unclear: whether there's a race for `molinfo $id get numatoms` immediately after (matters for the cap recompute).
   - Recommendation: in `refresh_mol_menu`, recompute the cap lazily (on first user interaction with the hider count), not in the trace callback. The mol/logic researcher's headless smoke can verify `mol new` → `molinfo list` ordering.

2. **Should the demo selector be a `menubutton`+`menu` (like loaded-mol) or a `ttk::combobox`?**
   - What we know: the demo list is static (6 entries from `DEMO_MANIFEST`) and selecting one triggers `mol new` (a side effect).
   - What's unclear: whether a combobox's `-values` + `<<ComboboxSelected>>` binding is cleaner than a menubutton+menu with per-entry `-command`.
   - Recommendation: `menubutton`+`menu` with per-entry `-command {::biochemeleon::demos::load_demo $id}` (consistent with the loaded-mol page + the clonerep pattern). A `ttk::combobox` is acceptable if the planner prefers one widget family for both selectors.

3. **Does the per-rep group (10 rows) overflow on the test machine's screen?**
   - What we know: 10 reps × (checkbox + spinbox + label) + hider count + lock-scene + 3 other groups.
   - What's unclear: actual pixel height at the user's default Tk font.
   - Recommendation: build the plain grid first; the GUI human-verify checkpoint decides whether to add a scrollable-frame wrapper. Don't pre-build the wrapper.

4. **`vmd_molecule` vs `vmd_initialize_structure` for the loaded-mol dropdown refresh.**
   - What we know: `clonerep` uses `vmd_molecule`; `ramaplot`/`viewmaster` use `vmd_initialize_structure`. Both fire on mol add/delete. `FEATURES.md:40` (locked) names `vmd_molecule` ("vmd_molecule is an ARRAY (verified)").
   - Recommendation: use `vmd_molecule` (the locked decision + clonerep analog). If the GUI smoke shows the menu doesn't refresh after a `mol new`, fall back to `vmd_initialize_structure` (or trace both).

## Sources

### Primary (HIGH confidence)
- **Tcler's Wiki `ttk::spinbox` page** (https://wiki.tcl-lang.org/page/ttk%3A%3Aspinbox) — "New command in Ttk (since tk8.5.9). Introduced in Tk version 8.5.9." → ttk::spinbox ABSENT in 8.5.6.
- **Tcler's Wiki `spinbox` page** (https://wiki.tcl-lang.org/page/spinbox) — example opens with `package require Tk 8.4` → plain `spinbox` AVAILABLE in 8.5.6; documents `-from`/`-to`/`-increment`/`-command`/`-format`/`-values`.
- **`vmd-ref/plugins/clonerep1.3/clonerep.tcl`** — the molecule-dropdown + refresh pattern: `menubutton`+`menu`+`radiobutton` (lines 193-199), `trace variable vmd_molecule w ::CloneRep::UpdateMolecule` (line 232), `UpdateMolecule` re-populates from `[molinfo list]` filtering `filetype != "graphics"` (lines 243-288).
- **`vmd-ref/plugins/ramaplot1.1/ramaplot.tcl`** — `trace variable vmd_initialize_structure w` (line 220), `ramaUpdateMolecules {args}` callback signature (line 272), `trace vdelete` cleanup on destroy (lines 265-267).
- **`vmd-ref/plugins/viewmaster2.6/viewmaster.tcl`** — canonical save/load: `save_state` via `[list ...]` + `puts` (lines 704-747), `load_state` via `source` + error-rollback (lines 751-765); `tk_getSaveFile`/`tk_getOpenFile` with `-filetypes` (lines 684, 753); `labelframe` grouping (line 105).
- **`vmd-ref/plugins/mergestructs1.1/mergestructs.tcl`** — grid form layout with `incr row` (lines 56-126), `grab set` on a transient sub-dialog (line 138, the allowed case), `tk_getOpenFile` Browse buttons (lines 102, 115).
- **`vmd-ref/plugins/autoionize1.4/autoionizegui.tcl`** — `trace add variable … write` (new form, line 192), `tk_optionMenu` (line 96), `labelframe` mode group (line 104), grid layout, `-textvariable ${ns}::var` binding.
- **`vmd-ref/scripts/save_state.tcl`** (VMD core, lines 144-219) — the official VMD save format = executable tcl script via `[list]`, loaded back by `source`.
- **`vmd/biochemeleon.tcl`** (Phase 13 entry) — proves `ttk::notebook`/`ttk::frame`/`ttk::label` render; `::biochemeleon::state` dict with `setup` key (lines 46-48); `info exists ::tk_version` guard (lines 117, 147); singleton re-show (line 87).
- **`vmd/lib/setup_state.tcl`** (Phase 13) — `GAME_REPS` (10 reps), `DEFAULTS` (11 keys), `DEMO_MANIFEST` (6 bundled), `hider_count_cap`, `validate_state` STUB. Namespace `::biochemeleon::setup_state`.
- **`vmd/tests/test_setup_state.test` + `test_registry.test` + `vmd/smoke/phase13_smoke.tcl`** — the tcltest + smoke patterns Phase 14 must follow (`BCHM_TEST_RESULT` / `BCHM_SMOKE_RESULT` markers, `[pwd]`-based path resolution under `vmd -e`).
- **`.planning/research/ARCHITECTURE.md:84,123,358` + `FEATURES.md:40` + `SUMMARY.md:78,141`** — locked decisions: ttk widget set for SetupTab, `gui/dialog.tcl`+`gui/setup_tab.tcl` structure, `trace variable vmd_molecule w` dropdown refresh.

### Secondary (MEDIUM confidence)
- **`.planning/research/STACK.md:22`** — lists `ttk::spinbox` as provided under "MEDIUM-HIGH (can't verify headless)"; **corrected by this research** (absent in 8.5.6 per the Tcler's Wiki).

### Tertiary (LOW confidence)
- None. All findings are cross-verified against ≥2 sources (reference plugins + official-ish docs).

## Metadata

**Confidence breakdown:**
- Standard stack (widget availability): **HIGH** — ttk::spinbox absent (Tcler's Wiki explicit, dated); plain spinbox present (Tcler's Wiki explicit, `package require Tk 8.4`); other ttk widgets present (core ttk 8.5.0, Phase 13 proves ttk loads). Caveat: ttk widgets except spinbox are MEDIUM-HIGH (can't verify headless — first GUI smoke confirms).
- Architecture (layout, mode selector, per-rep rows): **HIGH** — patterns taken directly from 4 reference plugins + v1 port source + Phase 13 entry.
- Dropdown refresh: **HIGH** — `trace variable vmd_molecule w` is the clonerep pattern (lines 231-232) + a locked decision (FEATURES.md:40). Minor open question on vmd_molecule vs vmd_initialize_structure (documented).
- Save/Load format: **HIGH** — `[list]`+`source` is the viewmaster (704-765) + VMD-core save_state (144-219) canonical pattern. Code-execution caveat documented with mitigation.
- collect_state/apply_state + `_loading` guard: **HIGH** — direct port of v1 `gui_setup.py:539-617`, adapted to tcl 8.5 (catch-based error handling, no try/finally).
- Pitfalls: **HIGH** — each grounded in a reference plugin line or a `vmd/AGENTS.md` gotcha.

**Research date:** 2026-08-29
**Valid until:** 2026-09-28 (30 days — stable domain; VMD 1.9.3/Tk 8.5.6 are fixed legacy versions, no upstream change expected)
