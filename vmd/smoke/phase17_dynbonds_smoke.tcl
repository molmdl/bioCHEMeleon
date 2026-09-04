# vmd/smoke/phase17_dynbonds_smoke.tcl
# Phase-17.1 (17.1-12) headless smoke: the DYNAMICBONDS tier END-TO-END
# through the real 17.1-06 dispatch -- the explicit-cutoff rep (the last of
# the four bond-family smokes; structure + Tachyon probe pattern copied from
# phase17_points_smoke.tcl per its SUMMARY).
#
# Proves (the 17.1-12 must-haves), on demo 1znf (424 atoms) with the scene
# rep 0 PRE-STYLED to bare DynamicBonds (user-scene parity per 17.1-10: a
# user scene carries its own DynamicBonds rep; the scene rep's own default
# cutoff -- 3.0 -- applies to IT, which is the user's choice, not ours) and
#   game::start_game $molid 3 [dict create DynamicBonds 3] 0:
#   1. ROUND: 427-atom game molecule; hider indices {424 425 426} (file order
#      == record order); user3 == 1.0 numeric on all three (float read-back,
#      P10); registry count_hiders 3; remaining_by_rep == {DynamicBonds 3}
#      with the BARE GAME_REPS name as the key (the registry rep field
#      carries the bare name even though the style args are multi-word --
#      assert the key is `DynamicBonds`, NOT `DynamicBonds 1.6`).
#   2. MIMICRY + BONDS: per hider -- element in {C N O S P}; radius == the
#      element's VDW radius (eps 1e-6); name in the real atom-name set;
#      numbonds >= 1 (certifies Lines/Licorice/CPK blend chemistry even
#      though DynamicBonds ignores the static bond list -- its bond search
#      is per-frame distance-based).
#   3. OFFSET-VS-CUTOFF (the P-5 rule): per hider, nearest-real-atom
#      distance <= 1.61 ALWAYS -- the hider draws at a fresh 1.2-1.6 A from
#      its anchor (relaxation only shrinks the OTHER seps, 17.1-03) and
#      %8.3f PDB rounding adds <= 0.001 (the read-back-safe form of the
#      strict < 1.6 drawn-offset contract, pinned by 17.1-05's chemistry
#      smoke). Full-sep accepts also sit in [1.19, 1.61]; relaxed accepts
#      (nearest < 1.19 -- a NON-anchor real atom can sit at 0.39-0.92 A,
#      17.1-05 discovery, normal on crowded anchors) are LOGGED and only
#      asserted non-degenerate (> 1e-6). Every hider thus has a real
#      partner strictly inside the explicit 1.6 hider-rep cutoff -> every
#      hider stub DRAWS under {DynamicBonds 1.6}.
#   4. REP READ-BACK (THE multi-word validation -- the one style whose
#      read-back carries params): hidden/found reps' read-back style ==
#      `DynamicBonds 1.6` EXACTLY (derived as [join [style_args
#      DynamicBonds] " "] and cross-checked against the lib's own stored
#      tier_styles entry -- never hand-typed); hidden color `Element`;
#      found `ColorID 7`; the literal user3-1 selections; numreps ==
#      pre_start + 2. Read-back string-compare, NEVER catch (a bad style
#      only prints console ERROR) and no-ops -- viability P-1; bare
#      `DynamicBond`/`Point` are INVALID no-ops -- style strings always
#      come from rep_tiers::style_args).
#   5. TACHYON RENDERS (headless pixel-proxy, viability sec 2/sec 7; probe
#      rep added LAST and deleted LAST; `axes location off` first; all
#      OTHER reps emptied by modselect to a null selection because `mol
#      showrep off` is IGNORED in text mode -- probe F6):
#      a. Baseline-zero: probe selection "index 999999" -> 0 Sphere + 0
#         FCylinder (harness proof: the parser really counts the scene).
#      b. Hider-rep exclusive (probe styled {*}{DynamicBonds 1.6} via
#         rep_tiers::style_args, color Element, selection
#         "resname GAM and beta < 0"): 0 primitives -- 0 FCylinder (the
#         hiders are >= 4 A apart so no GAM-GAM pair is within the strict-<
#         1.6 cutoff; both-endpoints rule) AND 0 Sphere. EVIDENCE-PINNED
#         CORRECTION of the plan's "draws dots" expectation: DynamicBonds'
#         per-frame bond search runs over ALL atoms, not just selected ones
#         (p6_geom evidence: its GAM scene had 2 LONE hiders + 2 BONDED
#         hiders; p6_dynbonds_16.dat exports exactly 2 spheres = the lone
#         ones). An atom with a within-cutoff partner (selected or not) is
#         "bonded" -> no dot; the both-endpoints rule then suppresses the
#         cylinder. Every hider has its anchor < 1.6 (the offset-vs-cutoff
#         invariant above), so a hiders-only DynamicBonds rep is
#         geometrically SILENT for bonded hiders: any sphere here would
#         mean an anchor-less hider (offset violation), any cylinder a
#         GAM-GAM pair within 1.6. Selection liveness + the element-color /
#         no-salmon checks are proven by the Points discriminator sub-render
#         below (same selection, Points style -> exactly 3 dots -- the
#         17.1-08 cross-check).
#      b2. Points discriminator (same probe rep re-styled Points via
#         style_args, same GAM selection): exactly 3 sphere dots (Rad <
#         0.02, p6-pinned 0.002 class), every parsed Color within eps 0.01
#         of an element color, NO salmon (1.0 0.6 0.6 -- the GAM-name
#         Name-coloring trap). Proves the (b) selection was live, so (b)'s
#         0/0 is genuinely the DynamicBonds bonded-hider behavior.
#      c. Scene-diff (scene rep = the pre-styled BARE DynamicBonds,
#         selection all): render A "all" vs render B "not resname GAM" ->
#         (A.cyl - B.cyl) >= 3 (the hider stubs drawn by the SCENE rep via
#         the both-endpoints rule; the scene rep's own default 3.0 cutoff
#         draws the < 1.6 stubs) and (A.sph - B.sph) == 0 (no orphan dots
#         either way: 1znf has no isolated atoms under a 3.0 cutoff and no
#         real atom's only partner is a hider). Supplementary pin: every
#         scene FCylinder is BOND-class -- uniform radius across all
#         cylinders and an order of magnitude above the 0.002 dot class.
#         (The p6-probe absolute 0.00991189 is NOT portable: Tachyon export
#         radii scale with the scene -- 0.00991189 on the 2-atom p6 scene
#         vs 0.0175322 uniform on this 427-atom scene -- so the assert is
#         the scale-safe class band, not the absolute value.)
#      .dat format pinned from the research probes + 17.1-08: one
#      "Sphere "/FCylinder header line per primitive, "   Rad <f> " after
#      Center/Base/Apex, per-primitive color on the "Phong Plastic ... Color
#      R G B TexFunc 0" line. The two "Directional_Light ... Color 1 1 1"
#      header lines carry a Color token and are FILTERED (a naive
#      whole-file Color regex counts the lights).
#   6. FOUND-MARKING: hiders::mark_found_visual $gm 426 -> user2(426) > 0
#      numeric; found selection num == 1 / hidden == 2 (per-tier
#      partition); remaining_by_rep DynamicBonds == 2. The mark's mandatory
#      modselect re-assert also RESTORES the pair selections that the
#      render phase emptied (unchanged-string contract, hiders.tcl).
#   7. CLEANUP: game::cleanup $gs -> registry 0; game molid DEAD; restored
#      original intact (numatoms 424) with numreps == pre_start (no leak)
#      AND rep-0 style reading back `DynamicBonds` EXACTLY (the pre-styled
#      scene rep survived snapshot -> backup::apply round-trip).
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and is
# recorded for a gap-closure plan -- never patched from a tier smoke
# (wave-disjointness).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- same order as phase17_points_smoke): setup_state, registry,
# rep_tiers, generators, game_logic, demos, backup, mutation, hiders, game.
# registry is sourced EXACTLY ONCE (re-sourcing would WIPE _records).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root). VMD does NOT propagate tcl exit codes (Pitfall 4)
# -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD -e catches top-level
# errors and CONTINUES (false-PASS risk) -> every step is catch-wrapped +
# _bail'd, and the runner scans the FULL log for ERROR) / bad switch lines
# (the regexp -- false-PASS lesson).
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently). NEVER mol showrep (ignored in text mode -- probe F6).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (user2/user3/radius are FLOATS -- numeric only,
# P10). Read-back is float32 (e.g. 1.7000000476) so eps 1e-6 suffices.
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Per-channel color proximity (eps 0.01 for the element-color pin).
proc _cnear {c ref eps} {
    if {[llength $c] != 3 || [llength $ref] != 3} { return 0 }
    foreach a $c b $ref {
        if {[expr {abs(double($a) - double($b))}] > $eps} { return 0 }
    }
    return 1
}

# Parse a Tachyon .dat: line-based primitive counting (research probe_e
# pattern) + per-primitive Rad/Color extraction. Directional_Light lines
# carry "Color 1 1 1" and are skipped (not primitives -- see header). Rad
# lines are attributed to the CURRENT primitive block (Sphere vs FCylinder)
# so the caller can check the dot class (0.002) against the bond class
# (0.00991189) separately. Returns {nsph ncyl sphrads cylrads colors};
# nsph/ncyl == -1 signals an unreadable file (so a missing file can never
# masquerade as an empty scene).
proc _parse_dat {path} {
    set nsph -1
    set ncyl -1
    set srads [list]
    set crads [list]
    set cols [list]
    if {[catch {open $path r} fh]} {
        return [list $nsph $ncyl $srads $crads $cols]
    }
    set nsph 0
    set ncyl 0
    set mode ""
    set dat [read $fh]
    close $fh
    foreach line [split $dat \n] {
        if {[string match "Sphere*" $line]} { incr nsph; set mode sph; continue }
        if {[string match "FCylinder*" $line]} { incr ncyl; set mode cyl; continue }
        if {[string match "Directional_Light*" $line]} { continue }
        if {[regexp -- {Rad\s+(-?[0-9.eE+-]+)} $line -> r]} {
            if {$mode eq "sph"} {
                lappend srads $r
            } elseif {$mode eq "cyl"} {
                lappend crads $r
            }
        }
        if {[regexp -- {Color\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)} $line -> cr cg cb]} {
            lappend cols [list $cr $cg $cb]
        }
    }
    return [list $nsph $ncyl $srads $crads $cols]
}

# Defensive init so a failed earlier step never masks as a substitution error.
set orig_molid -1
set gs [list]
set gm -1
set pre_reps -1
set n0 -1
set hider_idxs [list]
set real_names [list]
set probe_idx -1
set restored_molid -1

# Pinned constants (probe/colordefs evidence -- see header).
# Element VDW radii (atomselect radius read-back; VMD's element table).
set vdw_rad [dict create C 1.70 N 1.55 O 1.52 S 1.80 P 1.55]
# Element-method resolved RGBs (eps 0.01). C cyan / N blue / O red / S yellow
# probe-pinned from the research renders AND the 17.1-08 probe render (cyan
# 0.25 0.75 0.75, red 1 0 0 observed byte-exact). P tan is the pinned
# approximate value from colordefs.dat (Element P -> tan): INERT on 1znf
# (no P atoms) -- re-pin from a render if a P-bearing demo is ever used.
set elem_colors [list \
    {0.25 0.75 0.75} \
    {0.0 0.0 1.0} \
    {1.0 0.0 0.0} \
    {1.0 1.0 0.0} \
    {0.5 0.5 0.31}]
# SALMON (1.0 0.6 0.6) = Name-coloring leak on GAM-named atoms. Must NEVER
# appear in a hider render (hiders are anchor-named + reps use Element).
set salmon {1.0 0.6 0.6}
# Dot radius bound (probe-pinned: DynamicBonds unbonded-atom dots AND
# Points dots export Rad 0.002 -- tmp/p17-research-d/p6_dynbonds_*.dat show
# exactly 0.002 on their lone-atom spheres; same bound the Points/Lines
# smokes pin).
set max_dot_rad 0.02
# DynamicBonds bond-cylinder CLASS bounds. The Tachyon export radius scales
# with the scene (0.00991189 on the 2-atom p6 scene, 0.0175322 uniform on
# this 427-atom 1znf scene), so the portable assert is the CLASS: an order
# of magnitude above the 0.002 dot class, uniform across the whole rep.
set bond_rad_min 0.005
set bond_rad_max 0.05
set bond_rad_uniform_eps 1.0e-6

# ---- 0. Source the lib files in dependency order ([pwd]-relative; [info
#      script] is empty under -e). ----
foreach {nm path} [list \
    setup_state [file join [pwd] vmd lib setup_state.tcl] \
    registry    [file join [pwd] vmd lib registry.tcl] \
    rep_tiers   [file join [pwd] vmd lib rep_tiers.tcl] \
    generators  [file join [pwd] vmd lib generators.tcl] \
    game_logic  [file join [pwd] vmd lib game_logic.tcl] \
    demos       [file join [pwd] vmd lib demos.tcl] \
    backup      [file join [pwd] vmd lib backup.tcl] \
    mutation    [file join [pwd] vmd lib mutation.tcl] \
    hiders      [file join [pwd] vmd lib hiders.tcl] \
    game        [file join [pwd] vmd lib game.tcl]] {
    if {![file exists $path]} {
        _bail "${nm}_not_found" $path
    } elseif {[catch {source $path} err]} {
        _bail "${nm}_source_error" $err
    }
}

# ---- 0b. The pure-layer style args for the tier (derived AFTER sourcing,
#      NEVER hand-typed -- bare "DynamicBond" is an invalid no-op).
#      style_args DynamicBonds -> {DynamicBonds 1.6}; the joined form is the
#      exact read-back expectation used everywhere below. ----
set dynargs [list]
set exp_style ""
if {[catch {::biochemeleon::rep_tiers::style_args DynamicBonds} dargs]} {
    _bail style_args $dargs
} elseif {$dargs ne [list DynamicBonds 1.6]} {
    _bail style_args "exp={DynamicBonds 1.6} got=$dargs"
    set dynargs $dargs
    set exp_style [join $dargs " "]
} else {
    set dynargs $dargs
    set exp_style [join $dargs " "]
}

# ---- 1. SETUP + ROUND: load 1znf (424 atoms), PRE-STYLE the scene rep 0 to
#         bare DynamicBonds (user-scene parity), capture pre-start state and
#         the real-atom reference sets, start an EXPLICIT DynamicBonds-only
#         round. ----
if {[catch {::biochemeleon::demos::load_demo 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
    # Scene pre-style: BARE DynamicBonds on rep 0 (as a user scene would be).
    # The scene rep's own default cutoff (3.0) applies to IT -- the user's
    # choice, not ours. P-1: validate by read-back (the bare form echoes the
    # style name EXACTLY -- probe p1; no params are appended).
    if {[catch {mol modstyle 0 $orig_molid DynamicBonds} pserr]} {
        _bail scene_prestyle $pserr
    } else {
        set ps0 ""; set psl0 ""; set pcl0 ""; set pmt0 ""
        if {[catch {foreach {ps0 psl0 pcl0 pmt0} [molinfo $orig_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} psrb]} {
            _bail scene_prestyle_rb $psrb
        } elseif {$ps0 ne "DynamicBonds"} {
            _bail scene_prestyle "exp=DynamicBonds got=$ps0 (bare form must read back the bare name)"
        }
    }
    # Real-atom reference sets, collected ONCE pre-start (424 atoms -- a bulk
    # read is fine at this size). real_names is the mimicry name pool;
    # real_el_rad is the per-element REAL radius (mimicry ground truth).
    if {![catch {atomselect $orig_molid all} sall]} {
        set real_names [$sall get name]
        set real_elems [$sall get element]
        set real_rads [$sall get radius]
        $sall delete
    } else {
        _bail real_refs $sall
    }
    set real_el_rad [dict create]
    foreach e $real_elems r $real_rads {
        if {![dict exists $real_el_rad $e]} { dict set real_el_rad $e $r }
    }
    if {[catch {::biochemeleon::game::start_game $orig_molid 3 [dict create DynamicBonds 3] 0} gs]} {
        _bail start_game $gs
        set gs [list]
    } else {
        if {[catch {dict get $gs game_molid} gm]} {
            _bail gs_key_game_molid "missing (gs=$gs)"
            set gm -1
        }
    }
}

# ---- 2. ROUND ASSERTS (require a live game molid). ----
if {$gm >= 0} {
    # 2a: 424 + 3 = 427 atoms on the combined molecule.
    set n1 [molinfo $gm get numatoms]
    if {$n1 != 427} { _bail game_atoms "exp=427 got=$n1" }
    # 2b: hider indices == {424 425 426} (file order == record order; the
    #     single tier owns the whole list).
    if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hider_idxs]} {
        _bail fetch_idx $hider_idxs
        set hider_idxs [list]
    } elseif {$hider_idxs ne {424 425 426}} {
        _bail hider_idx "got=$hider_idxs"
    }
    # 2c: user3 == 1.0 numeric on all three (float read-back, P10); the tier
    #     table is DERIVED (tiers_from_per_rep over the stashed per_rep) and
    #     pinned to the single-tier code 1 with the BARE style name.
    if {[catch {dict get $gs per_rep} pr]} {
        _bail gs_per_rep $pr
    } elseif {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr} tiers]} {
        _bail tiers_from_per_rep $tiers
        set tiers [list]
    } elseif {[llength $tiers] != 1} {
        _bail tier_table "exp=1 tier got=$tiers"
    } else {
        lassign [lindex $tiers 0] tcode tstyle tcnt
        if {$tcode != 1 || $tstyle ne "DynamicBonds" || $tcnt != 3} {
            _bail tier1 "got=[lindex $tiers 0] (single DynamicBonds tier, code 1)"
        }
        foreach idx $hider_idxs {
            if {![catch {atomselect $gm "index $idx"} s]} {
                set u3 [lindex [$s get user3] 0]
                if {![_feq $u3 1.0]} { _bail user3_$idx "exp=1.0 got=$u3" }
                $s delete
            } else { _bail user3_sel_$idx $s }
        }
        # A real atom keeps user3 == 0.0 (P6: the sentinel conjunct must keep
        # excluding them -- catches a stamp-broadcast spill).
        if {![catch {atomselect $gm "index 100"} s100]} {
            set u3r [lindex [$s100 get user3] 0]
            if {![_feq $u3r 0.0]} { _bail user3_real "exp=0.0 got=$u3r" }
            $s100 delete
        } else { _bail user3_sel_real $s100 }
    }
    # 2d: registry count + per-tier remaining (fresh round -- all hidden).
    #     The registry rep field carries the BARE GAME_REPS name: assert the
    #     key set is exactly {DynamicBonds}, NOT the multi-word style string.
    set ch [::biochemeleon::registry::count_hiders]
    if {$ch != 3} { _bail reg_count "exp=3 got=$ch" }
    if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
        _bail remaining_by_rep $rbr
    } else {
        set rbrkeys [dict keys $rbr]
        if {[llength $rbrkeys] != 1 || [lindex $rbrkeys 0] ne "DynamicBonds"} {
            _bail rbr_key "exp=exact key {DynamicBonds} (bare GAME_REPS name) got=$rbrkeys"
        }
        if {[catch {dict get $rbr DynamicBonds} got] || $got != 3} {
            _bail rbr_dynbonds "exp=3 got=$got"
        }
    }
}

# ---- 3. MIMICRY + BOND LAW per hider (requires the hider indices + the
#         real-atom reference sets). ----
if {$gm >= 0 && [llength $hider_idxs] == 3 && [llength $real_names] > 0} {
    foreach idx $hider_idxs {
        if {[catch {atomselect $gm "index $idx"} s]} {
            _bail mimic_sel_$idx $s
            continue
        }
        set nm [lindex [$s get name] 0]
        set el [lindex [$s get element] 0]
        set rd [lindex [$s get radius] 0]
        set nb [lindex [$s get numbonds] 0]
        $s delete
        # element in {C N O S P} (heavy-atom anchor set).
        if {[lsearch -exact {C N O S P} $el] < 0} {
            _bail mimic_elem_$idx "got=$el (expect C N O S P)"
            continue
        }
        # radius == the element's VDW radius (eps 1e-6) -- AND == the real
        # same-element radius in this molecule (the exact mimicry ground
        # truth; both come from VMD's element table).
        if {[dict exists $vdw_rad $el]} {
            if {![_feq $rd [dict get $vdw_rad $el]]} {
                _bail mimic_rad_$idx "exp=[dict get $vdw_rad $el] got=$rd"
            }
        }
        if {[dict exists $real_el_rad $el]} {
            if {![_feq $rd [dict get $real_el_rad $el]]} {
                _bail mimic_rad_real_$idx "exp=[dict get $real_el_rad $el] got=$rd"
            }
        }
        # name in the real atom-name set (copied from the anchor).
        if {[lsearch -exact $real_names $nm] < 0} {
            _bail mimic_name_$idx "got=$nm (not a real atom name)"
        }
        # Bond law: every hider numbonds >= 1 (certifies the shared bonded
        # chemistry -- Lines/Licorice/CPK blend in the same combined PDB --
        # even though DynamicBonds ignores the static bond list and
        # recomputes per frame; extra bonds are normal, viability sec 3).
        if {![string is integer -strict $nb] || $nb < 1} {
            _bail bond_$idx "numbonds=$nb (expect >= 1)"
        }
    }
}

# ---- 3b. OFFSET-VS-CUTOFF (the P-5 rule): the hider-vs-explicit-cutoff
#          constraint. The ANCHOR draw is always a fresh 1.2-1.6 A
#          (relaxation only shrinks the OTHER seps, 17.1-03) -> nearest real
#          atom <= 1.61 ALWAYS with %8.3f rounding (the read-back-safe form
#          of the strict < 1.6 drawn-offset contract, 17.1-05-pinned; a
#          literal < 1.60 read-back assert would false-fail on a 1.5998 A
#          true draw rounding up). Full-sep accepts also >= 1.19; relaxed
#          accepts (nearest < 1.19 -- a NON-anchor real atom at 0.39-0.92 A,
#          17.1-05 discovery, common on crowded anchors) are LOGGED and only
#          asserted non-degenerate. Every hider keeps a real partner inside
#          the explicit 1.6 hider-rep cutoff -> every stub draws.
if {$gm >= 0 && [llength $hider_idxs] == 3} {
    set rcoords_ok 0
    if {![catch {atomselect $gm "index < 424"} rsel]} {
        set rcoords [$rsel get {x y z}]
        $rsel delete
        set rcoords_ok 1
    } else {
        _bail real_coords $rsel
    }
    if {$rcoords_ok} {
        set k 0
        foreach idx $hider_idxs {
            incr k
            if {[catch {atomselect $gm "index $idx"} hsel]} {
                _bail offset_sel_$idx $hsel
                continue
            }
            set hc [lindex [$hsel get {x y z}] 0]
            $hsel delete
            lassign $hc hx hy hz
            set mind2 1e30
            foreach rc $rcoords {
                lassign $rc rx ry rz
                set dx [expr {$hx - $rx}]
                set dy [expr {$hy - $ry}]
                set dz [expr {$hz - $rz}]
                set d2 [expr {$dx*$dx + $dy*$dy + $dz*$dz}]
                if {$d2 < $mind2} { set mind2 $d2 }
            }
            set mind [expr {sqrt($mind2)}]
            if {$mind > 1.61} {
                _bail offset_over_cutoff "hider $k nearest-real-dist=$mind > 1.61 (no real atom within the explicit 1.6 hider-rep cutoff band -- stub would not draw)"
            } elseif {$mind >= 1.19} {
                puts "BCHM_DYNBONDS: hider $k (idx $idx) nearest-real-dist=$mind (full-sep accept, strictly < 1.6 cutoff)"
            } else {
                puts "BCHM_DYNBONDS_RELAX: hider $k (idx $idx) nearest-real-dist=$mind < 1.19 (relaxed accept on a crowded anchor; the anchor draw itself stays in the 1.2-1.6 bond band)"
                if {$mind <= 1e-6} {
                    _bail offset_degenerate "hider $k coincident with a real atom (dist=$mind)"
                }
            }
        }
    }
}

# ---- 4. REP READ-BACK via tier_reps + repindex (COMBINED-BRACES form; the
#         exact literal selections per the 17.1-08 contract). THE multi-word
#         validation: the expected style string is derived from the pure
#         layer (style_args -> {DynamicBonds 1.6}) and cross-checked against
#         the lib's stored tier_styles entry -- then string-compared to the
#         actual read-back. Must run BEFORE the render phase empties the
#         pair selections. ----
if {$gm >= 0} {
    set nreps [molinfo $gm get numreps]
    if {$nreps != $pre_reps + 2} {
        _bail rep_count "exp=[expr {$pre_reps + 2}] got=$nreps"
    }
    if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
        _bail tier_reps_missing 1
    } else {
        # The lib's own stored style string must equal the pure-layer
        # derivation (never hand-typed anywhere in this smoke).
        if {![catch {dict get $::biochemeleon::hiders::tier_styles 1} stored_style]} {
            if {$stored_style ne $exp_style} {
                _bail tier_style_stored "exp=$exp_style got=$stored_style"
            }
        } else {
            _bail tier_styles_missing 1
        }
        lassign [dict get $::biochemeleon::hiders::tier_reps 1] hn fn hs fs
        foreach {rname rrep rexp_sel} [list \
                hidden $hn {resname GAM and beta < 0 and user2 < 1 and user3 1} \
                found  $fn {resname GAM and beta < 0 and user2 > 0 and user3 1}] {
            if {[catch {mol repindex $gm $rrep} ridx] || $ridx < 0} {
                _bail ${rname}_repindex "name=$rrep repindex=$ridx"
                continue
            }
            set st ""; set sl ""; set cl ""; set mt ""
            if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }} rb]} {
                _bail ${rname}_readback $rb
                continue
            }
            if {$st ne $exp_style} {
                _bail ${rname}_style "exp=$exp_style got=$st (multi-word read-back must match EXACTLY)"
            }
            if {$rname eq "hidden"} { set exp_col "Element" } else { set exp_col {ColorID 7} }
            if {$cl ne $exp_col} {
                _bail ${rname}_color "exp=$exp_col got=$cl"
            }
            if {$sl ne $rexp_sel} {
                _bail ${rname}_sel "exp=$rexp_sel got=$sl"
            }
        }
    }
}

# ---- 5. TACHYON RENDERS (headless pixel-proxy; probe rep LAST, deleted
#         LAST; other reps EMPTIED by modselect -- showrep is ignored in
#         text mode). Files land in [pwd] (the staging root, gitignored). ----
if {$gm >= 0} {
    if {[catch {axes location off} axerr]} {
        _bail axes_off $axerr
    }
    # Probe rep setup: added last (index == current numreps == pre_reps + 2).
    set probe_idx [molinfo $gm get numreps]
    if {[catch {mol addrep $gm} perr]} {
        _bail probe_addrep $perr
        set probe_idx -1
    }
    if {$probe_idx >= 0} {
        # Style args flow from the pure layer via {*}$dynargs -- the same
        # path tier_specs -> mol modstyle takes in production (never
        # hand-typed: bare "DynamicBond" is an invalid no-op).
        mol modstyle $probe_idx $gm {*}$dynargs
        mol modcolor $probe_idx $gm Element
        mol modselect $probe_idx $gm {index 999999}
        # P-1: validate the probe rep by read-back (a bad style never
        # raises).
        set pst ""; set psl ""; set pcl ""; set pmt ""
        if {[catch {foreach {pst psl pcl pmt} [molinfo $gm get "{rep $probe_idx} {selection $probe_idx} {color $probe_idx} {material $probe_idx}"] { break }} prb]} {
            _bail probe_readback $prb
        } elseif {$pst ne $exp_style} {
            _bail probe_style "exp=$exp_style got=$pst"
        }
        # Empty ALL other reps (scene + hidden + found) so every render is
        # attributable to the probe rep alone. The pair selections are stored
        # literals -- mark_found_visual re-asserts (restores) them in step 6.
        for {set i 0} {$i < $probe_idx} {incr i} {
            mol modselect $i $gm {index 999999}
        }

        # (a) Baseline-zero: 0 primitives -- the harness proof (a missing
        #     file parses as -1 and bails; a real empty scene parses 0/0).
        if {[catch {render Tachyon [file join [pwd] dyn_base.dat]} rerr]} {
            _bail render_base $rerr
        } else {
            lassign [_parse_dat [file join [pwd] dyn_base.dat]] b0s b0c b0sr b0cr b0cl
            if {$b0s != 0 || $b0c != 0} {
                _bail baseline_zero "exp=0/0 primitives got=$b0s/$b0c"
            }
        }

        # (b) Hider-rep exclusive ({DynamicBonds 1.6} + Element + GAM-only):
        #     0 primitives. 0 FCylinder (hiders >= 4 A apart -- no GAM-GAM
        #     pair within the strict-< 1.6 cutoff; both-endpoints rule) AND
        #     0 Sphere (evidence-pinned correction of the plan's "3 dots":
        #     DynamicBonds' per-frame bond search runs over ALL atoms -- p6
        #     scene data -- so every BONDED hider (anchor < 1.6, the offset
        #     invariant) is "bonded" -> no dot; the unselected anchor then
        #     suppresses the cylinder. A sphere here would expose an
        #     anchor-less hider; a cylinder a GAM-GAM pair within 1.6).
        mol modselect $probe_idx $gm {resname GAM and beta < 0}
        if {[catch {render Tachyon [file join [pwd] dyn_hiders.dat]} rerr]} {
            _bail render_hiders $rerr
        } else {
            lassign [_parse_dat [file join [pwd] dyn_hiders.dat]] hsph hcyl hsrads hcrads hcols
            if {$hcyl != 0} {
                _bail hider_fcyl "exp=0 got=$hcyl (hiders >= 4 A apart -- no GAM-GAM pair within the 1.6 cutoff)"
            }
            if {$hsph != 0} {
                _bail hider_dots "exp=0 got=$hsph (a bonded hider draws NO dot -- a sphere would mean an anchor-less hider: offset-vs-cutoff violation)"
            }
        }

        # (b2) Points discriminator (same probe rep, same GAM selection,
        #      re-styled via the pure layer): exactly 3 tiny sphere dots.
        #      Proves the (b) selection was LIVE (so its 0/0 is genuinely
        #      the DynamicBonds bonded-hider behavior, not an empty
        #      selection) and carries the element-color / no-salmon checks.
        set pargs [::biochemeleon::rep_tiers::style_args Points]
        mol modstyle $probe_idx $gm {*}$pargs
        if {[catch {render Tachyon [file join [pwd] dyn_hiders_pts.dat]} rerr]} {
            _bail render_hiders_pts $rerr
        } else {
            lassign [_parse_dat [file join [pwd] dyn_hiders_pts.dat]] psph pcyl psrads pcrads pcols
            if {$psph != 3} {
                _bail discr_dots "exp=3 got=$psph (Points on the same GAM selection must draw one dot per hider -- (b)'s selection-liveness proof)"
            }
            if {$pcyl != 0} { _bail discr_fcyl "exp=0 got=$pcyl" }
            foreach r $psrads {
                if {[catch {expr {double($r) < $max_dot_rad}} ok] || !$ok} {
                    _bail discr_dot_rad "rad=$r (expect < $max_dot_rad, p6-pinned 0.002)"
                    break
                }
            }
            if {[llength $pcols] != $psph} {
                _bail discr_color_count "exp=$psph colors got=[llength $pcols]"
            }
            foreach c $pcols {
                set ok 0
                foreach ref $elem_colors {
                    if {[_cnear $c $ref 0.01]} { set ok 1; break }
                }
                if {!$ok} { _bail discr_color "$c not within 0.01 of an element color" }
                if {[_cnear $c $salmon 0.01]} {
                    _bail discr_salmon "SALMON leak (Name-coloring trap): $c"
                }
            }
        }

        # (c) Scene-diff: probe emptied; the SCENE rep(s) (indices
        #     0..pre_reps-1, restored by backup::apply from the PRE-STYLED
        #     bare-DynamicBonds snapshot) render A = all vs B =
        #     "not resname GAM". The hider stubs are drawn by the scene rep
        #     (both-endpoints rule; the scene's own default 3.0 cutoff covers
        #     the < 1.6 stubs): A loses >= 3 cylinders in B; spheres equal
        #     (no orphan dots either way -- no 1znf atom is isolated under a
        #     3.0 cutoff and no real atom's only partner is a hider). Every
        #     scene cylinder must be BOND-class: uniform radius (one rep,
        #     one param set) and an order of magnitude above the 0.002 dot
        #     class. (The p6 absolute 0.00991189 is scene-scale-dependent --
        #     0.0175322 on this 427-atom scene -- so the assert is the
        #     scale-safe class band, not the absolute value.)
        mol modselect $probe_idx $gm {index 999999}
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm all
        }
        set rA_ok 0
        set rB_ok 0
        if {[catch {render Tachyon [file join [pwd] dyn_sceneA.dat]} rerr]} {
            _bail render_sceneA $rerr
        } else {
            lassign [_parse_dat [file join [pwd] dyn_sceneA.dat]] asph acyl asrads acrads acls
            set rA_ok 1
        }
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm {not resname GAM}
        }
        if {[catch {render Tachyon [file join [pwd] dyn_sceneB.dat]} rerr]} {
            _bail render_sceneB $rerr
        } else {
            lassign [_parse_dat [file join [pwd] dyn_sceneB.dat]] bsph bcyl bsrads bcrads bcls
            set rB_ok 1
        }
        if {$rA_ok && $rB_ok} {
            set dcyl [expr {$acyl - $bcyl}]
            if {$dcyl < 3} {
                _bail scene_stub_cyl "exp=A.cyl - B.cyl >= 3 got=$dcyl (A=$acyl B=$bcyl; hider stubs via both-endpoints rule under the scene's own cutoff)"
            }
            set dsph [expr {$asph - $bsph}]
            if {$dsph != 0} {
                _bail scene_dot_sph "exp=A.sph - B.sph == 0 got=$dsph (A=$asph B=$bsph)"
            }
            # Bond-class radius pin on BOTH scene renders (the stubs are
            # DynamicBonds bond sticks, not hairlines/dots): scale-safe band
            # + uniformity across every cylinder.
            set crmin 1e30
            set crmax -1e30
            foreach cr [concat $acrads $bcrads] {
                if {[catch {expr {double($cr)}} crv]} {
                    _bail scene_cyl_rad "unparseable cylinder rad=$cr"
                    break
                }
                if {$crv < $crmin} { set crmin $crv }
                if {$crv > $crmax} { set crmax $crv }
                if {$crv <= $bond_rad_min || $crv >= $bond_rad_max} {
                    _bail scene_cyl_rad "cylinder rad=$crv outside the bond-class band ($bond_rad_min, $bond_rad_max)"
                    break
                }
            }
            if {$crmax >= $crmin && [expr {$crmax - $crmin}] > $bond_rad_uniform_eps} {
                _bail scene_cyl_uniform "cylinder radii not uniform: min=$crmin max=$crmax"
            }
            foreach sr [concat $asrads $bsrads] {
                if {[catch {expr {double($sr) < $max_dot_rad}} ok] || !$ok} {
                    _bail scene_dot_rad "sphere rad=$sr (expect < $max_dot_rad)"
                    break
                }
            }
        }
        # Restore the scene selection + delete the probe rep (highest index
        # -- deleting it never renumbers earlier reps).
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm all
        }
        if {[catch {mol delrep $probe_idx $gm} derr]} {
            _bail probe_delrep $derr
        }
        set nreps2 [molinfo $gm get numreps]
        if {$nreps2 != $pre_reps + 2} {
            _bail rep_count_post_render "exp=[expr {$pre_reps + 2}] got=$nreps2"
        }
    }
}

# ---- 6. FOUND-MARKING (the on_pick find sequence, single tier): flag 426,
#         then the partition re-splits ONLY the DynamicBonds tier. ----
if {$gm >= 0 && [llength $hider_idxs] == 3} {
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 426} merr]} {
        _bail mark_found_visual $merr
    } else {
        if {![catch {atomselect $gm "index 426"} s]} {
            set u2 [lindex [$s get user2] 0]
            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                _bail found_user2 "exp=user2 > 0 got=$u2"
            }
            $s delete
        } else { _bail found_sel $s }
        foreach {selstr expn tag} [list \
                {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 dynbonds_found \
                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 dynbonds_hidden] {
            if {![catch {atomselect $gm $selstr} s]} {
                if {[$s num] != $expn} {
                    _bail $tag "exp=$expn got=[$s num]"
                }
                $s delete
            } else { _bail ${tag}_sel $s }
        }
        if {[catch {::biochemeleon::registry::mark_found 426} mferr]} {
            _bail registry_mark_found $mferr
        }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
            _bail remaining_by_rep2 $rbr2
        } else {
            set rbr2keys [dict keys $rbr2]
            if {[llength $rbr2keys] != 1 || [lindex $rbr2keys 0] ne "DynamicBonds"} {
                _bail rbr2_key "exp=exact key {DynamicBonds} got=$rbr2keys"
            }
            if {[catch {dict get $rbr2 DynamicBonds} got] || $got != 2} {
                _bail rbr2_dynbonds "exp=2 got=$got"
            }
        }
    }
}

# ---- 7. CLEANUP/RESTORE: registry 0, game molid DEAD, restored original
#         intact (numatoms 424, numreps == pre-start -- no leak) with rep-0
#         style reading back `DynamicBonds` EXACTLY (the pre-styled scene
#         rep survived the snapshot -> backup::apply round-trip). Runs even
#         if earlier assertions failed (only a thrown start_game error skips
#         it -- then there is no round to clean). ----
if {[llength $gs] > 0} {
    if {[catch {::biochemeleon::game::cleanup $gs} restored_molid]} {
        _bail cleanup $restored_molid
    } else {
        set ch2 [::biochemeleon::registry::count_hiders]
        if {$ch2 != 0} { _bail reg_after_cleanup "exp=0 got=$ch2" }
        if {![catch {molinfo $gm get numatoms} alive]} {
            _bail game_molid_alive "molinfo on the deleted game molid succeeded (numatoms=$alive)"
        }
        if {[catch {molinfo $restored_molid get numatoms} rn]} {
            _bail restored_atoms $rn
        } elseif {$rn != 424} {
            _bail restored_atoms "exp=424 got=$rn"
        }
        if {[catch {molinfo $restored_molid get numreps} rr]} {
            _bail restored_numreps $rr
        } elseif {$rr != $pre_reps} {
            _bail restored_numreps "exp=$pre_reps got=$rr"
        }
        set rstyle ""; set rsel2 ""; set rcol2 ""; set rmat2 ""
        if {[catch {foreach {rstyle rsel2 rcol2 rmat2} [molinfo $restored_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} rb2]} {
            _bail restored_style_rb $rb2
        } elseif {$rstyle ne "DynamicBonds"} {
            _bail restored_style "exp=DynamicBonds got=$rstyle (pre-styled scene rep must survive the restore round-trip)"
        }
    }
}

# ---- 8. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
