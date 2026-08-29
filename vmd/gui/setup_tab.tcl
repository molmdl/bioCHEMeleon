# vmd/gui/setup_tab.tcl -- Phase 14 Setup tab (GUI layer).
# Tk/ttk + mol (via ::biochemeleon::demos bridge). NOT pure.
# Sourced by gui/dialog.tcl at load time. Namespace: ::biochemeleon::setup_tab.
#
# Builds the full Setup form (4 groups: Target / Hiders / Difficulty / Actions)
# + state plumbing (collect_state / apply_state with the _loading guard) +
# switch_page. Callback procs (Plan 04): full impls -- refresh_mol_menu (trace
# -> repopulate the loaded-mol menu), select_demo / select_loaded_mol (set
# target + update cap), on_rep_toggled (enable/disable per-rep spinbox),
# update_cap / recompute_per_rep_maxes (spinbox -to caps), do_reset /
# do_randomize / do_save / do_load (action buttons). The WM_DELETE_WINDOW
# handler (collect_state + trace cleanup + destroy) lives in gui/dialog.tcl.
#
# Tcl 8.5.6 constraints (vmd/AGENTS.md): uses foreach+lappend + catch (no 8.6
# control-flow idioms). Brace all expr. `variable` inside procs for namespace
# vars. `::tk_version` (global qualifier) for any Tk guard (Phase 13 lesson:
# the unqualified form checks LOCAL scope only).
#
# Widgets: plain `spinbox` (the ttk spinbox variant is ABSENT in Tk 8.5.6,
# Pitfall 1); menubutton+menu for dropdowns (the clonerep idiom); 3
# ttk::radiobuttons + frame-`raise` for the mode selector (QStackedWidget
# analog). Save/Load uses ::biochemeleon::demos::save_setup/load_setup
# (key-value format, LOCKED DECISION #1) with the `.bcm` extension -- the
# do_save/do_load procs use tk_getSaveFile / tk_getOpenFile + the bridge.

namespace eval ::biochemeleon::setup_tab {
    # Live widget-bound state (read by collect_state, set by apply_state).
    variable mode            "loaded"   ;# "loaded" | "fetch" | "demo"
    variable selected_mol    ""         ;# loaded-mol display string (menubutton -textvariable)
    variable pdb_code        ""         ;# fetch entry
    variable demo_id         "1znf"     ;# demo menubutton -textvariable
    variable hider_count     10
    variable lock_scene      0
    variable difficulty_easy 1
    variable lock_source     0
    # Arrays: `variable name` (no value) leaves them undefined so `set name($k) v`
    # later creates them as arrays (probe-verified under VMD tcl 8.5.6).
    variable rep_sel                    ;# array rep -> 0/1 (checkbutton)
    variable rep_cnt                    ;# array rep -> int  (spinbox)
    variable _loading      0            ;# guard: suppress cascading callbacks in apply_state
    variable _pages                     ;# array mode -> page-frame path
    variable w                          ;# toplevel handle (set by build)
    variable current_molid              ;# for cap computation (set by Plan 04 callbacks)
    namespace export build collect_state apply_state
}

# ---------------------------------------------------------------------------
# _dget -- dict-get-with-default (PRIVATE helper).
# Tcl 8.5 `dict get` has NO 3-arg default form (`dict get $d key default`
# interprets `default` as a NESTED key -> "missing value to go with key"
# error; probe-verified under VMD tcl 8.5.6). The plan/research called for
# `dict get $state key $default`; that form does NOT exist, so this helper
# implements the same safety intent via `dict exists` + `dict get`.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::_dget {state key default} {
    if {[dict exists $state $key]} { return [dict get $state $key] }
    return $default
}

# ---------------------------------------------------------------------------
# build -- populate the Setup tab into $parent (the $nb.setup frame).
# Builds the 4 groups, packs them, initializes widgets from the persisted
# state (or DEFAULTS), and registers the molecule-menu refresh trace.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::build {parent} {
    variable w
    set w [winfo toplevel $parent]
    # Target group (SETUP-01): 3-mode selector + stacked pages.
    set tg [build_target_group $parent]
    # Hiders group (SETUP-02/03/04): hider count + lock-scene + per-rep rows.
    set hg [build_hiders_group $parent]
    # Difficulty group (SETUP-05).
    set dg [build_diff_group $parent]
    # Actions group (BTN-01..04).
    set ag [build_actions $parent]
    pack $tg $hg $dg $ag -side top -fill x -padx 8 -pady 6

    # Initialize widgets from persisted state (if a setup was previously
    # applied) or DEFAULTS. `::biochemeleon::state setup` is created by the
    # entry (Phase 13) as an empty dict; apply_state writes the full dict.
    set saved [dict get $::biochemeleon::state setup]
    if {[dict exists $saved format]} {
        apply_state [::biochemeleon::setup_state::validate_state $saved]
    } else {
        apply_state $::biochemeleon::setup_state::DEFAULTS
    }

    # Register the molecule-menu refresh trace (refresh_mol_menu repopulates
    # the loaded-mol menu on mol add/delete). vmd_molecule is a VMD global array
    # (FEATURES.md:40). `global` resolves it; `trace variable` on a not-yet-
    # existing variable is allowed (creates the trace). The WM_DELETE_WINDOW
    # handler (gui/dialog.tcl) does the matching trace cleanup on close.
    global vmd_molecule
    trace variable vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu
    ::biochemeleon::setup_tab::refresh_mol_menu
}

# ---------------------------------------------------------------------------
# build_target_group -- SETUP-01: 3-mode selector (Loaded/Fetch/Demo) via
# ttk::radiobuttons sharing `-variable mode` + stacked pages in ONE grid cell
# (`raise` the selected). Loaded page = menubutton+menu+Refresh (clonerep
# pattern); Fetch page = PDB code entry + info label; Demo page = menubutton+
# menu with the 6 bundled demos from DEMO_MANIFEST.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::build_target_group {parent} {
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

    # Stacked-pages container: all 3 gridded in the SAME cell; raise the selected.
    set p [ttk::frame $g.pages]
    grid $p -row 1 -column 0 -columnspan 3 -sticky news -pady 4

    set pl [ttk::frame $p.loaded]   ;# page 0: loaded-mol menubutton + Refresh
    set pf [ttk::frame $p.fetch]    ;# page 1: PDB code entry + info label
    set pd [ttk::frame $p.demo]     ;# page 2: demo menubutton + menu (6 entries)
    set _pages(loaded) $pl
    set _pages(fetch)  $pf
    set _pages(demo)   $pd
    grid $pl -row 0 -column 0 -sticky news
    grid $pf -row 0 -column 0 -sticky news
    grid $pd -row 0 -column 0 -sticky news
    raise $pl    ;# default page (matches DEFAULTS target_mode=loaded)

    # Loaded page: menubutton + menu + Refresh button (clonerep.tcl:193-199).
    menubutton $pl.mol -relief raised -bd 2 -direction flush \
        -textvariable ::biochemeleon::setup_tab::selected_mol \
        -menu $pl.mol.menu
    menu $pl.mol.menu -tearoff no
    button $pl.refresh -text "Refresh" -width 8 \
        -command {::biochemeleon::setup_tab::refresh_mol_menu}
    pack $pl.mol -side left -fill x -expand yes
    pack $pl.refresh -side left -padx 4

    # Fetch page: PDB code entry + info label (fetch is Phase 16+; Phase 14
    # ships bundled demos only).
    ttk::entry $pf.code -textvariable ::biochemeleon::setup_tab::pdb_code -width 8
    ttk::label $pf.note -text "Phase 14: bundled demos only; fetch at Start (Phase 16+)"
    pack $pf.code -side left -padx 2
    pack $pf.note -side left -padx 4

    # Demo page: menubutton + menu with one entry per bundled demo id.
    menubutton $pd.pick -relief raised -bd 2 -direction flush \
        -textvariable ::biochemeleon::setup_tab::demo_id \
        -menu $pd.pick.menu
    menu $pd.pick.menu -tearoff no
    foreach did [dict keys $::biochemeleon::setup_state::DEMO_MANIFEST] {
        $pd.pick.menu add command -label $did \
            -command [list ::biochemeleon::setup_tab::select_demo $did]
    }
    pack $pd.pick -side left -fill x -expand yes

    return $g
}

# ---------------------------------------------------------------------------
# build_hiders_group -- SETUP-02/03/04: hider count (plain spinbox) +
# lock-scene checkbutton + 10 per-rep rows (checkbutton + spinbox + "random"
# label). Plain `spinbox` (the ttk variant is absent in 8.5.6, Pitfall 1).
# Per-rep spinboxes start disabled; on_rep_toggled (Plan 04) enables them when
# the checkbutton is checked.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::build_hiders_group {parent} {
    set g [ttk::labelframe $parent.hiders -text "Hiders" -padding 6]

    # Top row: hider count + lock-scene (packed left-to-right).
    set top [ttk::frame $g.top]
    ttk::label $top.hcl -text "Hider count:"
    spinbox $top.hcspin -from 1 -to 50 -increment 1 -width 6 \
        -textvariable ::biochemeleon::setup_tab::hider_count \
        -command {::biochemeleon::setup_tab::recompute_per_rep_maxes}
    ttk::checkbutton $top.lock -text "Lock current scene" \
        -variable ::biochemeleon::setup_tab::lock_scene
    pack $top.hcl -side left -padx 4
    pack $top.hcspin -side left
    pack $top.lock -side left -padx 12
    pack $top -side top -fill x -pady 2

    # Per-rep rows: one per GAME_REPS rep (10 in v2). grid with `incr row`.
    set pr [ttk::frame $g.perrep]
    set row 0
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        set cb [ttk::checkbutton $pr.c$row -text $rep \
            -variable ::biochemeleon::setup_tab::rep_sel($rep) \
            -command [list ::biochemeleon::setup_tab::on_rep_toggled $rep]]
        set sp [spinbox $pr.s$row -from 0 -to 50 -increment 1 -width 5 \
            -textvariable ::biochemeleon::setup_tab::rep_cnt($rep) \
            -command {::biochemeleon::setup_tab::recompute_per_rep_maxes} \
            -state disabled]
        set lb [ttk::label $pr.l$row -text "random"]
        grid $cb -row $row -column 0 -sticky w
        grid $sp -row $row -column 1 -sticky w -padx 4
        grid $lb -row $row -column 2 -sticky w
        incr row
    }
    pack $pr -side top -fill x -pady 2
    return $g
}

# ---------------------------------------------------------------------------
# build_diff_group -- SETUP-05: Easy (show remaining per-rep) vs Hard (total
# only). 2 ttk::radiobuttons sharing `-variable difficulty_easy`.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::build_diff_group {parent} {
    set g [ttk::labelframe $parent.diff -text "Difficulty" -padding 6]
    ttk::radiobutton $g.easy -text "Easy (show per-rep remaining)" -value 1 \
        -variable ::biochemeleon::setup_tab::difficulty_easy
    ttk::radiobutton $g.hard -text "Hard (total only)" -value 0 \
        -variable ::biochemeleon::setup_tab::difficulty_easy
    pack $g.easy -side top -anchor w
    pack $g.hard -side top -anchor w
    return $g
}

# ---------------------------------------------------------------------------
# build_actions -- BTN-01..04: Reset / Randomize / Save Setup... / Load Setup...
# The -command scripts reference the do_* stubs (this plan); Plan 04 fills them.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::build_actions {parent} {
    set f [ttk::frame $parent.actions]
    ttk::button $f.reset  -text "Reset"          -command {::biochemeleon::setup_tab::do_reset}
    ttk::button $f.random -text "Randomize"     -command {::biochemeleon::setup_tab::do_randomize}
    ttk::button $f.save   -text "Save Setup..." -command {::biochemeleon::setup_tab::do_save}
    ttk::button $f.load   -text "Load Setup..." -command {::biochemeleon::setup_tab::do_load}
    pack $f.reset $f.random $f.save $f.load -side left -padx 4 -pady 4
    return $f
}

# ---------------------------------------------------------------------------
# collect_state -- snapshot all widget-bound vars into a DEFAULTS-key-order
# dict (Pattern 6). Builds per_rep from rep_sel/rep_cnt (only checked reps
# with count > 0). pdb_pool = [list] (pool editor is a later refinement).
# Bool coercion via `expr {!!$v}`; hider_count via `expr {int($v)}`.
# ---------------------------------------------------------------------------
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
        pdb_pool        [list] ]
}

# ---------------------------------------------------------------------------
# apply_state -- repopulate all widget vars from a state dict (Pattern 6).
# The `_loading` guard suppresses cascading callbacks (switch_page /
# recompute_per_rep_maxes / on_rep_toggled) while widgets are being set
# programmatically. Tcl 8.5 has no 8.6 cleanup idiom, so the body is wrapped
# in `catch` and `_loading` is ALWAYS reset to 0 afterward (Pitfall 3).
# `_dget` provides dict-get-with-default (tcl 8.5 `dict get` has no 3-arg
# default form -- see _dget). Persists the applied state to
# `::biochemeleon::state setup` so it survives dialog destroy/recreate.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::apply_state {state} {
    variable _loading
    variable mode selected_mol pdb_code demo_id hider_count lock_scene
    variable rep_sel rep_cnt difficulty_easy lock_source
    set _loading 1
    set code [catch {
        set mode            [_dget $state target_mode "loaded"]
        set selected_mol    [_dget $state selected_object ""]
        set pdb_code        [_dget $state pdb_code ""]
        set demo_id         [_dget $state demo_id "1znf"]
        set hider_count     [_dget $state hider_count 10]
        set lock_scene      [_dget $state lock_scene 0]
        set difficulty_easy [_dget $state difficulty_easy 1]
        set lock_source     [_dget $state lock_source 0]
        ::biochemeleon::setup_tab::switch_page
        # per_rep: check + count per rep; unchecked reps get 0/0.
        set pr [_dget $state per_rep [dict create]]
        foreach rep $::biochemeleon::setup_state::GAME_REPS {
            if {[dict exists $pr $rep]} {
                set rep_sel($rep) 1
                set rep_cnt($rep) [dict get $pr $rep]
            } else {
                set rep_sel($rep) 0
                set rep_cnt($rep) 0
            }
        }
        # on_rep_toggled re-enables spinboxes for selected reps. It runs
        # OUTSIDE the _loading guard (see the callback) so the spinbox
        # enable/disable is applied here; the recompute it triggers is itself
        # guarded (a no-op during this pass).
        foreach rep $::biochemeleon::setup_state::GAME_REPS {
            ::biochemeleon::setup_tab::on_rep_toggled $rep
        }
    } err]
    set _loading 0
    if {$code} { error $err }   ;# re-raise; _loading already reset (no 8.6 cleanup idiom)
    # Persist so the last-applied state survives dialog destroy/recreate.
    dict set ::biochemeleon::state setup $state
}

# ---------------------------------------------------------------------------
# switch_page -- raise the page frame for the current mode (the QStackedWidget
# analog). Called by the radiobutton -command and by apply_state.
# ---------------------------------------------------------------------------
proc ::biochemeleon::setup_tab::switch_page {} {
    variable mode
    variable _pages
    if {[info exists _pages($mode)]} { raise $_pages($mode) }
}

# ---------------------------------------------------------------------------
# Callbacks (Plan 04) -- full implementations. refresh_mol_menu takes `args`
# because the trace callback signature is `{name1 name2 op}` (Pitfall 2); the
# `args` form accepts and ignores them. update_cap / recompute_per_rep_maxes
# are guarded by `_loading` (they reconfigure widget -to caps, which is a UI
# affordance; the authoritative clamp is the pure-layer validate_state on
# Save/Start). on_rep_toggled deliberately runs OUTSIDE the `_loading` guard so
# apply_state's per-rep pass enables the spinboxes for checked reps (without
# that, a loaded/reset state would show checked boxes with disabled spinboxes);
# the recompute it triggers is itself guarded.
# ---------------------------------------------------------------------------

# refresh_mol_menu -- repopulate the loaded-molecule menu from [molinfo list].
# Called by the `trace variable vmd_molecule w` (registered in build) and by
# the Refresh button. Skips `graphics`-filetype mols (clonerep pattern). Adds a
# radiobutton per mol whose -command selects it + updates the cap. Adds a
# disabled "None loaded" entry when no mols are loaded.
proc ::biochemeleon::setup_tab::refresh_mol_menu {args} {
    variable w
    if {![info exists w] || $w eq ""} { return }
    set menu $w.nb.setup.target.pages.loaded.mol.menu
    if {![winfo exists $menu]} { return }
    $menu delete 0 end
    set any 0
    foreach id [molinfo list] {
        if {[catch {molinfo $id get filetype} ft]} { continue }
        if {$ft eq "graphics"} { continue }
        set any 1
        $menu add radiobutton -value $id \
            -label "$id [molinfo $id get name]" \
            -variable ::biochemeleon::setup_tab::selected_mol \
            -command [list ::biochemeleon::setup_tab::select_loaded_mol $id]
    }
    if {!$any} {
        $menu add command -label "None loaded" -state disabled
    }
}

# select_demo -- load a bundled demo via the mol bridge, set mode=demo, and
# update the hider-count cap. On error the bridge returns -code error; show a
# warning. The parameter `demo_id` shadows the namespace var of the same name,
# so the ns var is set via its fully-qualified path (Pitfall 7 -- build runtime
# values with [list], not string interpolation; here the FQ set avoids the
# shadow so the menubutton -textvariable updates correctly).
proc ::biochemeleon::setup_tab::select_demo {demo_id} {
    variable w
    variable mode
    variable current_molid
    set ::biochemeleon::setup_tab::demo_id $demo_id
    set mode "demo"
    switch_page
    if {[catch {::biochemeleon::demos::load_demo $demo_id} molid]} {
        tk_messageBox -icon warning -parent $w -message "Could not load demo: $molid"
        return
    }
    set current_molid $molid
    update_cap
}

# select_loaded_mol -- pick an already-loaded molecule as the target. Set
# mode=loaded + current_molid + the menubutton textvariable, then update cap.
proc ::biochemeleon::setup_tab::select_loaded_mol {molid} {
    variable selected_mol
    variable current_molid
    variable mode
    set selected_mol $molid
    set current_molid $molid
    set mode "loaded"
    switch_page
    update_cap
}

# on_rep_toggled -- enable/disable a per-rep spinbox when its checkbutton is
# toggled. Unchecked reps get count 0. Runs outside the `_loading` guard (see
# the block comment above) so apply_state's pass enables checked-rep spinboxes.
# Resolves the spinbox path from the row index (lsearch GAME_REPS).
proc ::biochemeleon::setup_tab::on_rep_toggled {rep} {
    variable w
    variable rep_sel
    variable rep_cnt
    set row [lsearch -exact $::biochemeleon::setup_state::GAME_REPS $rep]
    if {$row < 0} { return }
    if {![info exists w] || $w eq ""} { return }
    set sp $w.nb.setup.hiders.perrep.s$row
    if {![winfo exists $sp]} { return }
    if {[info exists rep_sel($rep)] && $rep_sel($rep)} {
        $sp configure -state normal
    } else {
        $sp configure -state disabled
        set rep_cnt($rep) 0
    }
    recompute_per_rep_maxes
}

# update_cap -- reconfigure the hider-count spinbox -to from the current
# molecule's atom count (demos::atom_count + hider_count_cap), then clamp the
# current value into range. Suppressed during apply_state. No-op if no
# molecule is selected yet (current_molid unset/empty).
proc ::biochemeleon::setup_tab::update_cap {} {
    variable _loading
    variable current_molid
    variable hider_count
    variable w
    if {$_loading} { return }
    if {![info exists current_molid] || $current_molid eq ""} { return }
    set atom_count [::biochemeleon::demos::atom_count $current_molid]
    set cap [::biochemeleon::setup_state::hider_count_cap $atom_count]
    if {![info exists w] || $w eq ""} { return }
    set sp $w.nb.setup.hiders.top.hcspin
    if {[winfo exists $sp]} {
        $sp configure -to [expr {max(1,$cap)}]
    }
    if {[info exists hider_count] && $hider_count > $cap} { set hider_count $cap }
}

# recompute_per_rep_maxes -- reconfigure each per-rep spinbox -to to the
# current hider_count (per-rep counts can't exceed the total). Suppressed
# during apply_state. The authoritative clamp is the pure-layer validate_state
# (called on Save/Start); this is a UI affordance.
proc ::biochemeleon::setup_tab::recompute_per_rep_maxes {} {
    variable _loading
    variable hider_count
    variable w
    if {$_loading} { return }
    if {![info exists w] || $w eq ""} { return }
    set pr $w.nb.setup.hiders.perrep
    if {![winfo exists $pr]} { return }
    set hc 50
    if {[info exists hider_count] && $hider_count ne ""} { set hc $hider_count }
    if {$hc < 1} { set hc 1 }
    set row 0
    foreach rep $::biochemeleon::setup_state::GAME_REPS {
        set sp $pr.s$row
        if {[winfo exists $sp]} {
            $sp configure -to $hc
        }
        incr row
    }
}

# do_reset -- restore the DEFAULTS state to all widgets (BTN-01).
proc ::biochemeleon::setup_tab::do_reset {} {
    apply_state $::biochemeleon::setup_state::DEFAULTS
}

# do_randomize -- produce a random valid state (BTN-02). No seed = random
# (non-deterministic; Plan 01's randomize_state). The current atom_count feeds
# the cap; lock_source preserves the target; collect_state is the locked_state.
# quick-008 (random non-empty per_rep subset) is baked into randomize_state.
proc ::biochemeleon::setup_tab::do_randomize {} {
    variable current_molid
    variable lock_source
    set atom_count 0
    if {[info exists current_molid] && $current_molid ne ""} {
        set atom_count [::biochemeleon::demos::atom_count $current_molid]
    }
    set lock_src 0
    if {[info exists lock_source]} { set lock_src $lock_source }
    apply_state [::biochemeleon::setup_state::randomize_state "" $atom_count $lock_src [collect_state]]
}

# do_save -- write the current setup to a .bcm file via the mol bridge
# (BTN-03; LOCKED DECISION #1 -- key-value format, NOT [list]+source).
proc ::biochemeleon::setup_tab::do_save {} {
    variable w
    set fname [tk_getSaveFile -defaultextension ".bcm" \
        -title "Save bioCHEMeleon Setup" \
        -filetypes [list {{bioCHEMeleon} {.bcm}} {{All files} {*}}] \
        -parent $w]
    if {$fname eq ""} { return }
    if {[catch {::biochemeleon::demos::save_setup [collect_state] $fname} err]} {
        tk_messageBox -icon warning -parent $w -message "Save failed: $err"
    }
}

# do_load -- read a .bcm setup file via the mol bridge (BTN-04). load_setup
# calls validate_state internally (Plan 02), so $result is a validated dict;
# apply_state repopulates the widgets from it.
proc ::biochemeleon::setup_tab::do_load {} {
    variable w
    set fname [tk_getOpenFile -defaultextension ".bcm" \
        -title "Load bioCHEMeleon Setup" \
        -filetypes [list {{bioCHEMeleon} {.bcm}} {{All files} {*}}] \
        -parent $w]
    if {$fname eq ""} { return }
    if {[catch {::biochemeleon::demos::load_setup $fname} result]} {
        tk_messageBox -icon warning -parent $w -message "Load failed: $result"
        return
    }
    apply_state $result
}
