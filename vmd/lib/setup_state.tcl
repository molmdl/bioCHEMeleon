# vmd/lib/setup_state.tcl
# PURE layer: stdlib-only tcl. No molecular-viewer API, no GUI toolkit.
# Unit-testable via tcltest (under headless VMD or a standalone tclsh).
# Direct port of v1 pymol/biochemeleon/setup_state.py (Python -> tcl 8.5).

namespace eval ::biochemeleon::setup_state {
    # The 10 in-scope VMD representations for v2 (curated from FEATURES.md).
    # v1 had 5; v2 expands to 10. Surface/volumetric reps are out of scope
    # (anti-features — they do not fit the discrete-atom blend-in mechanic).
    variable GAME_REPS {Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds}

    # JSON schema version tag for setup files (v2, not v1).
    variable SETUP_FORMAT "biochemeleon-setup-v2"

    # Default setup state (port of v1 setup_state.py:118-130).
    # 11 keys: format, target_mode, selected_object, pdb_code, demo_id,
    # hider_count, lock_scene, per_rep, difficulty_easy, lock_source, pdb_pool.
    variable DEFAULTS [dict create \
        format          "biochemeleon-setup-v2" \
        target_mode     "loaded" \
        selected_object "" \
        pdb_code        "" \
        demo_id         "1znf" \
        hider_count     10 \
        lock_scene      0 \
        per_rep         [dict create] \
        difficulty_easy 1 \
        lock_source     0 \
        pdb_pool        [list] ]

    # Demo manifest: 6 BUNDLED demo entries (port of v1 setup_state.py:34-57).
    # PDBs are viewer-agnostic and reused verbatim per ARCHITECTURE.md.
    # The 3 fetched demos (1gzm/3gp6/sasdpg4) are added in a later phase, NOT here.
    variable DEMO_MANIFEST [dict create \
        1znf [dict create category Protein       type protein    difficulty easy source bundled cache_name 1znf.pdb] \
        1xdn [dict create category Protein       type protein    difficulty hard source bundled cache_name 1xdn.pdb] \
        5e54 [dict create category "Nucleic acid" type rna        difficulty easy source bundled cache_name 5e54.pdb] \
        1k8p [dict create category "Nucleic acid" type dna        difficulty easy source bundled cache_name 1k8p.pdb] \
        2qbz [dict create category "Nucleic acid" type rna        difficulty hard source bundled cache_name 2qbz.pdb] \
        4wb3 [dict create category Mixed         type "protein/na" difficulty hard source bundled cache_name 4wb3.pdb] ]

    # Export the public symbols so callers may `namespace import` them.
    # Tests and the entry script use fully-qualified names; the export
    # list documents the public contract.
    namespace export GAME_REPS SETUP_FORMAT DEFAULTS DEMO_MANIFEST hider_count_cap validate_state randomize_state randomize_per_rep format_remaining
}

# Hider-count cap (port of v1 setup_state.py:233-244).
# Heuristic: 1 hider per ~50 atoms, clamped to [1, 50].
# Verified by probe: 0 -> 1, 212 -> 4, 100000 -> 50 (matches v1).
proc ::biochemeleon::setup_state::hider_count_cap {atom_count} {
    if {![string is integer -strict $atom_count] || $atom_count <= 0} {
        return 1
    }
    set cap [expr {$atom_count / 50}]
    if {$cap < 1} { set cap 1 }
    if {$cap > 50} { set cap 50 }
    return $cap
}

# ---- internal helpers (pure; not exported) ----
# Python bool() semantics for setup-state coercion: 0/""/false -> 0, else 1.
proc ::biochemeleon::setup_state::_to_bool {v} {
    if {$v eq "" || $v eq "0" || $v eq "false" || $v eq "False"} { return 0 }
    return 1
}

# randint [lo, hi] inclusive (both ends). Uses the GLOBAL PRNG (Pitfall 4).
proc ::biochemeleon::setup_state::_randint {lo hi} {
    return [expr {$lo + int(rand() * ($hi - $lo + 1))}]
}

# random element of a list.
proc ::biochemeleon::setup_state::_choice {lst} {
    return [lindex $lst [expr {int(rand() * [llength $lst])}]]
}

# n distinct elements of lst (without replacement) -- Fisher-Yates partial
# shuffle. Port of Python's random.sample. n in [1, len] (caller guarantees >=1).
proc ::biochemeleon::setup_state::_sample {lst n} {
    set copy $lst
    set len [llength $copy]
    if {$n > $len} { set n $len }
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {$i + int(rand() * ($len - $i))}]
        set tmp [lindex $copy $i]
        lset copy $i [lindex $copy $j]
        lset copy $j $tmp
    }
    return [lrange $copy 0 [expr {$n - 1}]]
}

# Validate a PDB code: exactly 4 lowercase alnum chars, or "".
proc ::biochemeleon::setup_state::_validate_pdb_code {code} {
    if {$code eq ""} { return "" }
    set c [string tolower [string trim $code]]
    if {[string length $c] == 4 && [regexp {^[a-z0-9]+$} $c]} { return $c }
    return ""
}

# Validate a PDB pool: list of 4-char lowercase alnum codes, deduped, bound to 100.
# v2 DIFFERENCE from v1: an empty/invalid pool returns [list] (empty), NOT the v1
# 33-entry PDB_POOL (v2 has no PDB_POOL constant; fetch is a later phase). The
# empty pool causes randomize_state's fetch mode to re-roll to demo (the guard).
proc ::biochemeleon::setup_state::_validate_pdb_pool {pool} {
    if {![info exists pool] || $pool eq ""} { return [list] }
    set seen [list]
    set seen_set [dict create]
    foreach code $pool {
        set c [_validate_pdb_code $code]
        if {$c ne "" && ![dict exists $seen_set $c]} {
            lappend seen $c
            dict set seen_set $c 1
            if {[llength $seen] >= 100} { break }
        }
    }
    return $seen
}

# ---- validate_state (FULL port of v1 setup_state.py) ----
# DETERMINISTIC clamp: fills missing keys from DEFAULTS, clamps hider_count to
# [1, cap], drops invalid per_rep keys/counts, clamps per_rep sum to <= hider_count
# (insertion-order keep + DROP overflow -- Pitfall 7, never truncate), validates
# enums, coerces bools, validates pdb_pool. Returns a NEW dict in DEFAULTS key
# order (critical for order-stable dict eq in Save/Load -- Pitfall 5). NO randomness.
proc ::biochemeleon::setup_state::validate_state {state {atom_count {}}} {
    variable DEFAULTS
    variable DEMO_MANIFEST
    variable GAME_REPS
    # Start from a fresh copy of DEFAULTS (canonical key order).
    set result $DEFAULTS
    # Non-dict input -> DEFAULTS.
    if {![info exists state] || $state eq "" || [catch {dict size $state}]} { return $result }

    # target_mode
    if {[dict exists $state target_mode]} {
        set mode [dict get $state target_mode]
        if {$mode eq "loaded" || $mode eq "fetch" || $mode eq "demo"} {
            dict set result target_mode $mode
        }
    }
    # selected_object / pdb_code
    if {[dict exists $state selected_object]} { dict set result selected_object [dict get $state selected_object] }
    if {[dict exists $state pdb_code]} {
        dict set result pdb_code [string tolower [string trim [dict get $state pdb_code]]]
    }
    # demo_id
    if {[dict exists $state demo_id]} {
        set did [dict get $state demo_id]
        if {[dict exists $DEMO_MANIFEST $did]} { dict set result demo_id $did }
    }
    # hider_count (clamped to [1, cap]; cap = hider_count_cap(atom_count) or 50)
    if {[string is integer -strict $atom_count] && $atom_count > 0} {
        set cap [hider_count_cap $atom_count]
    } else {
        set cap 50
    }
    if {[dict exists $state hider_count] && [string is integer -strict [dict get $state hider_count]]} {
        set hc [dict get $state hider_count]
    } else {
        set hc [dict get $DEFAULTS hider_count]
    }
    if {$hc < 1} { set hc 1 }
    if {$hc > $cap} { set hc $cap }
    dict set result hider_count $hc

    # lock_scene / difficulty_easy (bool coercion)
    if {[dict exists $state lock_scene]} { dict set result lock_scene [_to_bool [dict get $state lock_scene]] }
    if {[dict exists $state difficulty_easy]} { dict set result difficulty_easy [_to_bool [dict get $state difficulty_easy]] }

    # per_rep: drop invalid keys (not in GAME_REPS), drop zero/negative counts.
    set clean [dict create]
    if {[dict exists $state per_rep] && ![catch {dict size [dict get $state per_rep]}]} {
        dict for {rep cnt} [dict get $state per_rep] {
            if {[lsearch -exact $GAME_REPS $rep] < 0} { continue }
            if {![string is integer -strict $cnt] || $cnt <= 0} { continue }
            dict set clean $rep $cnt
        }
    }
    # per_rep-sum clamp: insertion-order keep + DROP overflow (runs AFTER hider_count clamp).
    set clamped [dict create]
    set remaining $hc
    dict for {rep cnt} $clean {
        if {$cnt <= $remaining} {
            dict set clamped $rep $cnt
            incr remaining -$cnt
        }
    }
    dict set result per_rep $clamped

    # New fields (lock_source + pdb_pool)
    if {[dict exists $state lock_source]} { dict set result lock_source [_to_bool [dict get $state lock_source]] }
    if {[dict exists $state pdb_pool]} {
        dict set result pdb_pool [_validate_pdb_pool [dict get $state pdb_pool]]
    }
    return $result
}

# ---- randomize_per_rep (quick-008 pure helper) ----
# Distribute hider_count across a random NON-EMPTY subset of game_reps.
# Guarantees at least one rep with count > 0 when hider_count > 0 (the quick-008
# fix that replaces the old all-spheres fallback). game_reps is a PARAMETER
# (dependency-injected) so this stays pure. seed -> deterministic (for tests).
proc ::biochemeleon::setup_state::randomize_per_rep {hider_count game_reps {seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    if {$hider_count <= 0 || [llength $game_reps] == 0} { return [dict create] }
    set n [_randint 1 [llength $game_reps]]  ;# NON-EMPTY subset (1..len) -- the quick-008 core
    set reps [_sample $game_reps $n]
    set per_rep [dict create]
    set remaining $hider_count
    foreach rep $reps {
        if {$remaining <= 0} { break }
        set c [_randint 0 $remaining]
        if {$c > 0} {
            dict set per_rep $rep $c
            incr remaining -$c
        }
    }
    # Guarantee non-empty: if every draw came back 0 (possible when hider_count==1),
    # put the full count on a random rep (matches v1 quick-008 line 150-151).
    if {[dict size $per_rep] == 0} {
        dict set per_rep [_choice $game_reps] $hider_count
    }
    return $per_rep
}

# ---- randomize_state (Randomize button; port of v1 setup_state.py) ----
# Returns a complete random state dict (all DEFAULTS keys). If seed given,
# deterministic. Uses the GLOBAL PRNG: seeds once at top (if seed), calls
# randomize_per_rep with NO seed (continues the sequence -- do NOT let
# randomize_per_rep reseed when called from here). lock_source preserves target
# from locked_state; else random mode (weighted toward demo; empty pdb_pool ->
# fetch re-rolls to demo).
proc ::biochemeleon::setup_state::randomize_state {{seed {}} {atom_count {}} {lock_source 0} {locked_state {}} {pdb_pool {}}} {
    variable DEFAULTS
    variable DEMO_MANIFEST
    variable GAME_REPS
    variable SETUP_FORMAT
    if {$seed ne ""} { expr {srand($seed)} }
    # cap + hider_count
    if {[string is integer -strict $atom_count] && $atom_count > 0} {
        set cap [hider_count_cap $atom_count]
    } else {
        set cap 50
    }
    if {$cap < 1} { set cap 1 }
    set hider_count [_randint 1 $cap]
    # resolve the fetch pool (v2: empty default; empty -> fetch re-rolls to demo)
    if {$pdb_pool ne ""} { set pool_for_fetch [_validate_pdb_pool $pdb_pool] } else { set pool_for_fetch [list] }

    # lock_source branch (preserve target; only randomize hider composition)
    if {$lock_source && $locked_state ne "" && ![catch {dict size $locked_state}]} {
        set mode [dict get $locked_state target_mode]
        if {$mode ne "loaded" && $mode ne "fetch" && $mode ne "demo"} { set mode "loaded" }
        set selected_object [dict get $locked_state selected_object]
        set pdb_code [string tolower [string trim [dict get $locked_state pdb_code]]]
        set did [dict get $locked_state demo_id]
        if {![dict exists $DEMO_MANIFEST $did]} { set did "1znf" }
        set demo_id $did
    } else {
        # random mode (weighted toward demo): loaded/fetch/demo/demo
        set mode [_choice [list loaded fetch demo demo]]
        if {$mode eq "fetch" && [llength $pool_for_fetch] == 0} { set mode "demo" }  ;# empty pool -> never fetch
        set selected_object ""
        if {$mode eq "fetch"} {
            set pdb_code [_choice $pool_for_fetch]
        } else {
            set pdb_code ""
        }
        # demo from BUNDLED demos only (offline-safe; Phase 14 manifest is all bundled)
        set bundled_ids [list]
        foreach did [dict keys $DEMO_MANIFEST] {
            if {[dict get $DEMO_MANIFEST $did source] eq "bundled"} { lappend bundled_ids $did }
        }
        set demo_id [_choice $bundled_ids]
    }
    # per_rep via randomize_per_rep (NO seed -> continues the global sequence; quick-008 baked in)
    set per_rep [randomize_per_rep $hider_count $GAME_REPS]
    set lock_scene [_choice [list 0 1]]
    set difficulty_easy [_choice [list 0 1]]
    return [dict create \
        format          $SETUP_FORMAT \
        target_mode     $mode \
        selected_object $selected_object \
        pdb_code        $pdb_code \
        demo_id         $demo_id \
        hider_count     $hider_count \
        lock_scene      $lock_scene \
        per_rep         $per_rep \
        difficulty_easy $difficulty_easy \
        lock_source     [_to_bool $lock_source] \
        pdb_pool        [_validate_pdb_pool $pdb_pool]]
}

# ---- Remaining-hiders label formatter (Phase 16 GAME-03) ----
# Port of v1 setup_state.py:418-447 (pure; no viewer API, no GUI toolkit).
# The Game tab's update_remaining writes the returned string straight onto
# its remaining-count label.
#
# Format: "Remaining: %d" in hard mode; in easy mode with a NON-EMPTY
# counts dict, "Remaining: %d  (Rep: n, ...)" -- EXACTLY TWO SPACES before
# the opening paren, entries in GAME_REPS order (never dict insertion
# order), count > 0 only, comma-space separated. An empty counts dict (or
# an all-zero win state) yields the total-only form so the label never
# shows an empty parenthetical. Unknown rep keys are skipped defensively:
# iteration runs over GAME_REPS, never over the input dict.
proc ::biochemeleon::setup_state::format_remaining {total counts_by_rep easy_mode} {
    variable GAME_REPS
    if {![_to_bool $easy_mode] || [catch {dict size $counts_by_rep}] || [dict size $counts_by_rep] == 0} {
        return "Remaining: $total"
    }
    set parts [list]
    foreach rep $GAME_REPS {
        if {[dict exists $counts_by_rep $rep]} {
            set cnt [dict get $counts_by_rep $rep]
            if {[string is integer -strict $cnt] && $cnt > 0} {
                lappend parts "$rep: $cnt"
            }
        }
    }
    if {[llength $parts] == 0} {
        return "Remaining: $total"
    }
    return "Remaining: $total  ([join $parts {, }])"
}
