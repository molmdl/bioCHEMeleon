# vmd/gui/setup_tab.tcl -- Phase 14 Setup tab (GUI layer).
# Tk/ttk + mol (via ::biochemeleon::demos bridge). NOT pure.
# Sourced by gui/dialog.tcl at load time. Namespace: ::biochemeleon::setup_tab.
#
# Builds the full Setup form (4 groups: Target / Hiders / Difficulty / Actions)
# + state plumbing (collect_state / apply_state with the _loading guard) +
# switch_page. Callback procs (Plan 04): full impls -- refresh_mol_menu (trace
# -> repopulate the loaded-mol menu), select_demo / select_loaded_mol (set
# target + update cap), on_rep_toggled (enable/disable per-rep spinbox),
# update_cap / recompute_per_rep_maxes (spinbox -to caps + live per-rep sum
# capping so the per-rep sum never exceeds hider_count), do_reset /
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
    # Tcl 8.5 `variable a b` is a name-VALUE pair (sets a=b), NOT two links.
    # `variable rep_sel rep_cnt` would do a scalar `set rep_sel "rep_cnt"` --
    # which fails once rep_sel is an array (checkbuttons init it as one).
    # So each namespace var gets its own `variable` (link-only, no value).
    variable mode
    variable selected_mol
    variable pdb_code
    variable demo_id
    variable hider_count
    variable lock_scene
    variable rep_sel
    variable rep_cnt
    variable difficulty_easy
    variable lock_source
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
    # Tcl 8.5 `variable a b` is a name-VALUE pair (sets a=b), NOT two links
    # (see collect_state). One `variable` per name (link-only, no value).
    variable mode
    variable selected_mol
    variable pdb_code
    variable demo_id
    variable hider_count
    variable lock_scene
    variable rep_sel
    variable rep_cnt
    variable difficulty_easy
    variable lock_source
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
# `args` form accepts and ignores them. update_cap / recompute_per_rep_maxes /
# on_rep_toggled's live-cap are guarded by `_loading` (they reconfigure widget
# -to caps + clamp counts; the authoritative clamp is the pure-layer
# validate_state on Save/Start). on_rep_toggled itself runs OUTSIDE `_loading`
# (so apply_state's per-rep pass enables checked-rep spinboxes), but its
# live-cap clamp is guarded so apply_state's validated values aren't fought.
# recompute_per_rep_maxes dynamically caps the per-rep SUM (Issue 2): each
# checked rep's -to = hider_count - sum(other checked reps), so the sum can
# never exceed hider_count via arrow interaction. do_save runs validate_state
# + warns if clamping occurred (Issue 1: covers the entry-typing bypass).
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
#
# Issue 2 live-cap: when ENABLING a rep (user-checked the box), cap its count
# to the REMAINING allowance = hider_count - sum(all OTHER checked per-rep
# counts) so the per-rep sum can NEVER exceed hider_count in the GUI. The
# live-cap is guarded by `_loading` so apply_state (which sets validated values
# directly from a clean dict) isn't fighting the clamp. The spinbox enable/
# disable itself runs unguarded (apply_state needs it to enable checked reps).
proc ::biochemeleon::setup_tab::on_rep_toggled {rep} {
    variable _loading
    variable w
    variable hider_count
    variable rep_sel
    variable rep_cnt
    set row [lsearch -exact $::biochemeleon::setup_state::GAME_REPS $rep]
    if {$row < 0} { return }
    if {![info exists w] || $w eq ""} { return }
    set sp $w.nb.setup.hiders.perrep.s$row
    if {![winfo exists $sp]} { return }
    if {[info exists rep_sel($rep)] && $rep_sel($rep)} {
        $sp configure -state normal
        # Live-cap (Issue 2): clamp this rep's count to the remaining allowance
        # so the per-rep sum stays <= hider_count. Only during user interaction
        # (NOT during apply_state, which already sets validated values).
        if {!$_loading} {
            set hc 0
            if {[info exists hider_count] && $hider_count ne ""} { set hc $hider_count }
            if {$hc < 1} { set hc 1 }
            set total_others 0
            foreach r $::biochemeleon::setup_state::GAME_REPS {
                if {$r ne $rep && [info exists rep_sel($r)] && $rep_sel($r)} {
                    set c 0
                    if {[info exists rep_cnt($r)]} { set c $rep_cnt($r) }
                    incr total_others $c
                }
            }
            set remaining [expr {$hc - $total_others}]
            if {$remaining < 0} { set remaining 0 }
            set cur 0
            if {[info exists rep_cnt($rep)]} { set cur $rep_cnt($rep) }
            if {$cur > $remaining} { set rep_cnt($rep) $remaining }
        }
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
#
# Issue 2: when a smaller molecule is loaded (cap shrinks), the existing per-rep
# sum may now exceed the new hider_count. Clamp the per-rep counts in insertion
# order (keep early reps, reduce later ones) so the sum fits, then call
# recompute_per_rep_maxes to update the per-rep spinbox -to values. Guarded by
# _loading. The authoritative clamp is validate_state on Save/Start.
proc ::biochemeleon::setup_tab::update_cap {} {
    variable _loading
    variable current_molid
    variable hider_count
    variable rep_sel
    variable rep_cnt
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
    if {![info exists hider_count] || $hider_count eq ""} { return }
    if {$hider_count > $cap} { set hider_count $cap }
    # Clamp the per-rep sum to the (possibly reduced) hider_count. Insertion-
    # order keep + reduce: early reps keep their count, later reps are reduced
    # to fit. This matches validate_state's drop-overflow intent but is gentler
    # (reduce instead of drop) so the user keeps some distribution.
    set running 0
    foreach r $::biochemeleon::setup_state::GAME_REPS {
        if {![info exists rep_sel($r)] || !$rep_sel($r)} { continue }
        set c 0
        if {[info exists rep_cnt($r)]} { set c $rep_cnt($r) }
        if {$c <= 0} { continue }
        if {$running + $c > $hider_count} {
            set rep_cnt($r) [expr {$hider_count - $running}]
            if {$rep_cnt($r) < 0} { set rep_cnt($r) 0 }
            set running $hider_count
        } else {
            set running [expr {$running + $c}]
        }
    }
    ::biochemeleon::setup_tab::recompute_per_rep_maxes
}

# recompute_per_rep_maxes -- reconfigure each per-rep spinbox -to so the
# per-rep SUM can never exceed hider_count (Issue 2 live-cap). For each CHECKED
# rep, the -to = hider_count - sum(all OTHER checked per-rep counts) (min 0);
# this makes the remaining reps' maxes shrink as the user increases one rep.
# Unchecked reps get -to 0 (their spinbox is disabled anyway). If a count
# exceeds its dynamic cap (e.g. hider_count decreased via arrows), clamp it
# down. Suppressed during apply_state. The authoritative clamp is the pure-
# layer validate_state (called on Save/Start); this is a GUI-level prevention
# so the user never sees an inconsistent state via normal arrow interaction.
proc ::biochemeleon::setup_tab::recompute_per_rep_maxes {} {
    variable _loading
    variable hider_count
    variable rep_sel
    variable rep_cnt
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
            if {[info exists rep_sel($rep)] && $rep_sel($rep)} {
                # Dynamic cap: hider_count minus the sum of all OTHER checked
                # reps' counts. This ensures the SUM stays within hider_count.
                set total_others 0
                foreach r2 $::biochemeleon::setup_state::GAME_REPS {
                    if {$r2 ne $rep && [info exists rep_sel($r2)] && $rep_sel($r2)} {
                        set c 0
                        if {[info exists rep_cnt($r2)]} { set c $rep_cnt($r2) }
                        incr total_others $c
                    }
                }
                set remaining [expr {$hc - $total_others}]
                if {$remaining < 0} { set remaining 0 }
                $sp configure -to $remaining
                # Clamp the current count down if it exceeds the dynamic cap.
                set cur 0
                if {[info exists rep_cnt($rep)]} { set cur $rep_cnt($rep) }
                if {$cur > $remaining} { set rep_cnt($rep) $remaining }
            } else {
                $sp configure -to 0
            }
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
#
# Issue 1 fix: BEFORE saving, run the collected widget state through
# validate_state. If clamping occurred (collected != validated), show a popup
# warning detailing what changed, apply_state the validated dict (so the
# WIDGETS reflect the clamped values immediately), and save the VALIDATED state.
# This makes save->load perfectly consistent (the saved file contains the same
# values the user sees on screen after the warning). Covers the entry-typing
# bypass (the spinbox -to only clamps arrow clicks, not direct text entry -- a
# future minor UX refinement could add -validatecmd to the entry; this popup is
# the immediate safety net).
proc ::biochemeleon::setup_tab::do_save {} {
    variable w
    variable current_molid
    set fname [tk_getSaveFile -defaultextension ".bcm" \
        -title "Save bioCHEMeleon Setup" \
        -filetypes [list {{bioCHEMeleon} {.bcm}} {{All files} {*}}] \
        -parent $w]
    if {$fname eq ""} { return }
    # Collect the widget state + validate it against the current molecule's cap.
    set collected [collect_state]
    set atom_count 0
    if {[info exists current_molid] && $current_molid ne ""} {
        set atom_count [::biochemeleon::demos::atom_count $current_molid]
    }
    set validated [::biochemeleon::setup_state::validate_state $collected $atom_count]
    # Both dicts are in DEFAULTS key order, so `eq` (string comparison) is a
    # reliable equality check (Pitfall 5: tcl dict eq is ORDER-SENSITIVE, but
    # the order matches here). If they differ, build a human-readable diff.
    if {$collected eq $validated} {
        set toSave $collected
    } else {
        set msg "Some values were out of range and have been adjusted:\n\n"
        # Compare scalar keys; build a human-readable line for each difference.
        foreach key {target_mode pdb_code demo_id hider_count lock_scene difficulty_easy lock_source} {
            set cv [_dget $collected $key ""]
            set vv [_dget $validated $key ""]
            if {$cv ne $vv} {
                switch -- $key {
                    target_mode     { set label "Target mode" }
                    pdb_code        { set label "PDB code" }
                    demo_id         { set label "Demo" }
                    hider_count     { set label "Hider count" }
                    lock_scene      { set label "Lock scene" }
                    difficulty_easy { set label "Difficulty" }
                    lock_source     { set label "Lock source" }
                    default         { set label $key }
                }
                append msg "$label: $cv -> $vv\n"
            }
        }
        # per_rep: if the sub-dict differs, report as a single line.
        set pc [_dget $collected per_rep [dict create]]
        set pv [_dget $validated per_rep [dict create]]
        if {$pc ne $pv} {
            append msg "Per-rep counts: adjusted to fit the hider count total\n"
        }
        append msg "\nThe saved file will contain the adjusted (valid) values."
        tk_messageBox -icon info -parent $w -title "Values Adjusted" -message $msg
        # Update widgets to reflect the clamped state so the screen matches the
        # saved file.
        apply_state $validated
        set toSave $validated
    }
    if {[catch {::biochemeleon::demos::save_setup $toSave $fname} err]} {
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
