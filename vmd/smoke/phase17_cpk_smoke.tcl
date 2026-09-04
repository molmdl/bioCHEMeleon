# vmd/smoke/phase17_cpk_smoke.tcl
# Phase-17.1 (17.1-11) headless smoke: the CPK tier END-TO-END through the
# real 17.1-06 dispatch -- the PRE-STYLED-SCENE variant of the 17.1-08
# Tachyon template (points_smoke structure + the 17.1-10 pre-styled-scene
# pattern; 17.1-10's own file lives in a sibling wave worktree, so the
# pattern is applied from THIS plan's pinned mechanics).
#
# CPK = VDW spheres at the 0.25x CPK default scale + bond cylinders
# (UG node62, probe-measured; "if the radii ... are too small, they will
# not be drawn" -- the scale-ratio check is the guard for that warning).
#
# Proves, on demo 1k8p (555 atoms; a DNA demo WITH 22 P atoms -- unlike
# 1znf the tan element color can genuinely appear) with the scene
# PRE-STYLED to CPK before the round
#   mol modstyle 0 $m CPK ; game::start_game $molid 3 [dict create CPK 3] 0:
#   1. PRE-STYLE: rep-0 style reads back "CPK" BEFORE start_game (P-1
#      read-back rule -- a bad style never raises), and the GAME molecule's
#      rep 0 is CPK too (backup::apply snapshot fidelity).
#   2. ROUND: 558-atom game molecule; hider indices {555 556 557} (file
#      order == record order); user3 == 1.0 numeric on all three (float
#      read-back, P10); registry count_hiders 3; remaining_by_rep ==
#      {CPK 3}; a real atom keeps user3 == 0.0 (P6).
#   3. MIMICRY + BOND LAW: per hider -- element in {C N O S P}; radius ==
#      the element's VDW radius (eps 1e-6; CPK scaling is a RENDER
#      property -- the atom record carries the full VDW radius); name in
#      the real atom-name set; numbonds >= 1 (CPK uses the bond list).
#   4. REP READ-BACK via tier_reps + mol repindex (COMBINED-BRACES molinfo
#      form): numreps == pre_start + 2; hidden/found style == "CPK"
#      EXACTLY; color Element / ColorID 7; selections
#      "resname GAM and beta < 0 and user2 < 1 and user3 1" / the user2 > 0
#      variant. Read-back string-compare, NEVER catch (a bad style only
#      prints console ERROR) and no-ops -- viability P-1).
#   5. TACHYON RENDERS (headless pixel-proxy; probe rep added LAST and
#      deleted LAST; all OTHER reps emptied via modselect to a null
#      selection because `mol showrep off` is IGNORED in text mode -- probe
#      F6; `axes location off` first):
#      a. Baseline-zero: probe selection "index 999999" -> 0 Sphere + 0
#         FCylinder (harness proof: a missing file parses -1 and bails).
#      b. Hider-rep exclusive (selection "resname GAM and beta < 0", style
#         CPK, color Element): exactly 3 spheres, 0 FCylinder (hiders bond
#         only to REAL atoms -- the both-endpoints rule drops those
#         cylinders when real atoms are not selected; this is the UG node62
#         "not drawn" guard at the primitive level), every parsed Color
#         within eps 0.01 of an element color (tan {0.5 0.5 0.2} LIVE on
#         1k8p -- 22 P atoms; see the constants note),
#         NO salmon (1.0 0.6 0.6 -- the GAM-name Name-coloring trap). No
#         dot-radius bound here: CPK hider spheres are ~0.25x VDW Rad
#         (~0.024 for C), ABOVE the 0.02 Points-dot bound -- the scale is
#         checked by (c).
#      c. SCALE RATIO (the one per-tier render fact worth pinning): same
#         probe selection, re-style VDW -> render -> mean sphere Rad;
#         re-style CPK -> render -> mean sphere Rad;
#         mean(CPK Rad) / mean(VDW Rad) in [0.20, 0.30]
#         (probe K: an element-C atom exports Rad 0.094504 under VDW at res
#         8.0/scale 1.0 defaults; CPK hider Rad ~ 0.25x that). Both probe
#         renders must parse exactly 3 spheres / 0 FCylinders so the means
#         are pure (FCylinder Rad lines would pollute a naive mean).
#      d. Scene-diff (scene rep = the PRE-STYLED CPK rep 0, selection all):
#         render A "all" vs render B "not resname GAM" -> (A.sph - B.sph)
#         == 3 (the hider spheres drawn by the scene CPK rep) AND
#         (A.cyl - B.cyl) >= 3 (hider stub cylinders via the both-endpoints
#         rule). Delete the probe rep after renders (highest index -- no
#         renumbering).
#      .dat format pinned per 17.1-08 (copy-ready evidence): one "Sphere "/
#      "FCylinder" header line per primitive, "   Rad <f> " after
#      Center/Base/Apex, per-primitive color on the "Phong Plastic ... Color
#      R G B TexFunc 0" line; the two "Directional_Light ... Color 1 1 1"
#      header lines carry a Color token and are FILTERED; multi-attribute
#      atomselect get returns NESTED per-atom tuples -- per-field
#      single-attribute gets only.
#   6. FOUND-MARKING: mark 557 (mark_found_visual + registry::mark_found --
#      the on_pick sequence) -> user2(557) > 0; the user2 > 0 / user3 1
#      partition num == 1; the user2 < 1 variant num == 2; remaining_by_rep
#      CPK == 2. The mark's mandatory modselect re-assert also RESTORES the
#      pair selections the render phase emptied (unchanged-string contract,
#      hiders.tcl).
#   7. CLEANUP RESTORE (style-faithful): game::cleanup $gs -> registry 0;
#      game molid DEAD; restored original intact (555 atoms) with numreps
#      == pre_start AND rep-0 style reads back "CPK" (the pre-styled scene
#      survives the round through snapshot/restore).
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and is
# recorded for a gap-closure plan -- never patched from a tier smoke
# (wave-disjointness).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself -- same order as phase17_points_smoke): setup_state,
# registry, rep_tiers, generators, game_logic, demos, backup, mutation,
# hiders, game. registry is sourced EXACTLY ONCE (re-sourcing WIPEs
# _records).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root). VMD does NOT propagate tcl exit codes (Pitfall
# 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD -e catches
# top-level errors and CONTINUES (false-PASS risk) -> every step is
# catch-wrapped + _bail'd, and the runner scans the FULL log for ERROR) /
# bad switch lines (the regexp -- false-PASS lesson).
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

# Mean of a numeric list (-1 on empty/non-numeric -- never masks as 0).
proc _mean {vals} {
    if {[llength $vals] == 0} { return -1 }
    set s 0.0
    foreach v $vals {
        if {[catch {expr {double($v)}} d]} { return -1 }
        set s [expr {$s + $d}]
    }
    return [expr {$s / double([llength $vals])}]
}

# Parse a Tachyon .dat: line-based primitive counting (research probe_e
# pattern) + per-primitive Rad/Color extraction. Directional_Light lines
# carry "Color 1 1 1" and are skipped (not primitives -- see header).
# NOTE: FCylinder primitives ALSO carry a Rad line (cylinder radius), so a
# mixed scene's rads list is NOT all-sphere -- callers must check the cyl
# count first (the scale-ratio step does). Returns {nsph ncyl rads colors};
# nsph/ncyl == -1 signals an unreadable file (so a missing file can never
# masquerade as an empty scene).
proc _parse_dat {path} {
    set nsph -1
    set ncyl -1
    set rads [list]
    set cols [list]
    if {[catch {open $path r} fh]} {
        return [list $nsph $ncyl $rads $cols]
    }
    set nsph 0
    set ncyl 0
    set dat [read $fh]
    close $fh
    foreach line [split $dat \n] {
        if {[string match "Sphere*" $line]} { incr nsph; continue }
        if {[string match "FCylinder*" $line]} { incr ncyl; continue }
        if {[string match "Directional_Light*" $line]} { continue }
        if {[regexp -- {Rad\s+(-?[0-9.eE+-]+)} $line -> r]} {
            lappend rads $r
        }
        if {[regexp -- {Color\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)} $line -> cr cg cb]} {
            lappend cols [list $cr $cg $cb]
        }
    }
    return [list $nsph $ncyl $rads $cols]
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
# P = 1.80 DISCOVERED this plan (17.1-11 run 2): the 17.1-08 pin said 1.55,
# but that value was INERT on P-free 1znf and never render-validated. A
# P-anchored hider on 1k8p read back 1.7999999523162842 -- matching the REAL
# P atoms (probe: element P radius == 1.80; N re-confirmed 1.55; S 1.80 was
# validated on 1znf in 17.1-08). VMD 1.9.3's element table uses Bondi vdW
# for P (1.80), NOT the covalent-ish 1.55.
set vdw_rad [dict create C 1.70 N 1.55 O 1.52 S 1.80 P 1.80]
# Element-method resolved RGBs (eps 0.01). C cyan / N blue / O red / S yellow
# probe-pinned byte-exact in the 17.1-08 renders. P tan DISCOVERED this plan
# (17.1-11 run 2): color Element P -> tan (probe `color Element P`), and the
# RENDERED RGB on a P-anchored hider was {0.5 0.5 0.2} byte-exact -- the old
# {0.5 0.5 0.31} pin was OCHRE's RGB, mis-pinned from colordefs.dat while
# inert on 1znf (no P atoms). 1k8p has 22 P atoms (~1 run in 9 draws a
# P-anchored hider), so the tan entry is LIVE here.
set elem_colors [list \
    {0.25 0.75 0.75} \
    {0.0 0.0 1.0} \
    {1.0 0.0 0.0} \
    {1.0 1.0 0.0} \
    {0.5 0.5 0.2}]
# SALMON (1.0 0.6 0.6) = Name-coloring leak on GAM-named atoms. Must NEVER
# appear in a hider render (hiders are anchor-named + reps use Element).
set salmon {1.0 0.6 0.6}
# CPK scale-ratio window (plan-pinned): mean CPK hider Rad over mean VDW Rad
# for the SAME atoms in [0.20, 0.30] (probe-measured 0.25x; UG node62's
# "too-small radii are not drawn" guard).
set ratio_lo 0.20
set ratio_hi 0.30

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

# ---- 1. PRE-STYLE + ROUND: load 1k8p (555 atoms), pre-style the scene rep
#         to CPK BEFORE start_game (the 17.1-10 pattern -- the snapshot then
#         carries a CPK scene through apply AND restore), capture the
#         real-atom reference sets, start an EXPLICIT CPK-only round. ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
    # Pre-style rep 0 to CPK + read-back validation (P-1: a bad style never
    # raises -- a silent no-op here would void the whole pre-styled-scene
    # premise, so it is asserted BEFORE the round starts).
    if {[catch {mol modstyle 0 $orig_molid CPK} pserr]} {
        _bail prestyle $pserr
    } else {
        set ps0 ""
        if {[catch {foreach {ps0 psl0 pc0 pm0} [molinfo $orig_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} psrb]} {
            _bail prestyle_readback $psrb
        } elseif {$ps0 ne "CPK"} {
            _bail prestyle_readback "exp=CPK got=$ps0"
        }
    }
    # Real-atom reference sets, collected ONCE pre-start (555 atoms -- a bulk
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
    if {[catch {::biochemeleon::game::start_game $orig_molid 3 [dict create CPK 3] 0} gs]} {
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
    # 2a: 555 + 3 = 558 atoms on the combined molecule.
    set n1 [molinfo $gm get numatoms]
    if {$n1 != 558} { _bail game_atoms "exp=558 got=$n1" }
    # 2b: hider indices == {555 556 557} (file order == record order; the
    #     single tier owns the whole list).
    if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hider_idxs]} {
        _bail fetch_idx $hider_idxs
        set hider_idxs [list]
    } elseif {$hider_idxs ne {555 556 557}} {
        _bail hider_idx "got=$hider_idxs"
    }
    # 2c: user3 == 1.0 numeric on all three (float read-back, P10); the tier
    #     table is DERIVED (tiers_from_per_rep over the stashed per_rep) and
    #     pinned to the single-tier code 1.
    if {[catch {dict get $gs per_rep} pr]} {
        _bail gs_per_rep $pr
    } elseif {[catch {::biochemeleon::rep_tiers::tiers_from_per_rep $pr} tiers]} {
        _bail tiers_from_per_rep $tiers
        set tiers [list]
    } elseif {[llength $tiers] != 1} {
        _bail tier_table "exp=1 tier got=$tiers"
    } else {
        lassign [lindex $tiers 0] tcode tstyle tcnt
        if {$tcode != 1 || $tstyle ne "CPK" || $tcnt != 3} {
            _bail tier1 "got=[lindex $tiers 0] (single CPK tier, code 1)"
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
    # 2d: the PRE-STYLED scene survived apply -- the game molecule's rep 0
    #     reads back CPK (snapshot fidelity for the pre-styled-scene pattern).
    set gstyle0 ""
    if {[catch {foreach {gstyle0 gsel0 gcol0 gmat0} [molinfo $gm get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} grb]} {
        _bail game_scene_style_readback $grb
    } elseif {$gstyle0 ne "CPK"} {
        _bail game_scene_style "exp=CPK got=$gstyle0 (pre-style did not survive backup::apply)"
    }
    # 2e: registry count + per-tier remaining (fresh round -- all hidden).
    set ch [::biochemeleon::registry::count_hiders]
    if {$ch != 3} { _bail reg_count "exp=3 got=$ch" }
    if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
        _bail remaining_by_rep $rbr
    } else {
        if {[dict size $rbr] != 1} {
            _bail rbr_size "exp=1 got=$rbr"
        }
        if {[catch {dict get $rbr CPK} got] || $got != 3} {
            _bail rbr_cpk "exp=3 got=$got"
        }
    }
}

# ---- 3. MIMICRY + BOND LAW per hider (requires the hider indices + the
#         real-atom reference sets). CPK scaling is a RENDER property -- the
#         atom record still carries the full element VDW radius. ----
if {$gm >= 0 && [llength $hider_idxs] == 3 && [llength $real_names] > 0} {
    foreach idx $hider_idxs {
        if {[catch {atomselect $gm "index $idx"} s]} {
            _bail mimic_sel_$idx $s
            continue
        }
        # PER-FIELD single-attribute gets (multi-attribute get returns NESTED
        # per-atom tuples even on single-atom selections -- 17.1-08 gotcha).
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
        # Bond law: every hider numbonds >= 1 (CPK draws bond cylinders from
        # the bond list; extra bonds to H/N neighbors are normal and
        # blend-positive -- viability sec 3).
        if {![string is integer -strict $nb] || $nb < 1} {
            _bail bond_$idx "numbonds=$nb (expect >= 1)"
        }
    }
}

# ---- 4. REP READ-BACK via tier_reps + repindex (COMBINED-BRACES form; the
#         exact literal selections per the 17.1-08 contract; style == "CPK"
#         EXACTLY). Must run BEFORE the render phase empties the pair
#         selections. ----
if {$gm >= 0} {
    set nreps [molinfo $gm get numreps]
    if {$nreps != $pre_reps + 2} {
        _bail rep_count "exp=[expr {$pre_reps + 2}] got=$nreps"
    }
    if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
        _bail tier_reps_missing 1
    } else {
        lassign [dict get $::biochemeleon::hiders::tier_reps 1] hname fname hsel fsel
        foreach {rname rrep rexp_sel} [list \
                hidden $hname {resname GAM and beta < 0 and user2 < 1 and user3 1} \
                found  $fname {resname GAM and beta < 0 and user2 > 0 and user3 1}] {
            if {[catch {mol repindex $gm $rrep} ridx] || $ridx < 0} {
                _bail ${rname}_repindex "name=$rrep repindex=$ridx"
                continue
            }
            set st ""; set sl ""; set cl ""; set mt ""
            if {[catch {foreach {st sl cl mt} [molinfo $gm get "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }} rb]} {
                _bail ${rname}_readback $rb
                continue
            }
            if {$st ne "CPK"} {
                _bail ${rname}_style "exp=CPK got=$st"
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
        mol modstyle $probe_idx $gm CPK
        mol modcolor $probe_idx $gm Element
        mol modselect $probe_idx $gm {index 999999}
        # P-1: validate the probe rep by read-back (a bad style never raises).
        set pst ""; set psl ""; set pcl ""
        if {[catch {foreach {pst psl pcl pmt} [molinfo $gm get "{rep $probe_idx} {selection $probe_idx} {color $probe_idx} {material $probe_idx}"] { break }} prb]} {
            _bail probe_readback $prb
        } elseif {$pst ne "CPK"} {
            _bail probe_style "exp=CPK got=$pst"
        }
        # Empty ALL other reps (scene + hidden + found) so every render is
        # attributable to the probe rep alone. The pair selections are stored
        # literals -- mark_found_visual re-asserts (restores) them in step 6.
        for {set i 0} {$i < $probe_idx} {incr i} {
            mol modselect $i $gm {index 999999}
        }

        # (a) Baseline-zero: 0 primitives -- the harness proof (a missing
        #     file parses as -1 and bails; a real empty scene parses 0/0).
        if {[catch {render Tachyon [file join [pwd] cpk_base.dat]} rerr]} {
            _bail render_base $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_base.dat]] bs bc brd bcl
            if {$bs != 0 || $bc != 0} {
                _bail baseline_zero "exp=0/0 primitives got=$bs/$bc"
            }
        }

        # (b) Hider-rep exclusive CPK: exactly 3 spheres, 0 FCylinder (both-
        #     endpoints rule drops the hider-real bond cylinders), element
        #     colors only (tan LIVE-eligible on 1k8p), no salmon. The UG
        #     node62 "too-small radii are not drawn" guard: 3 parsed spheres
        #     prove the 0.25x-scale radii ARE drawn.
        mol modselect $probe_idx $gm {resname GAM and beta < 0}
        if {[catch {render Tachyon [file join [pwd] cpk_hiders.dat]} rerr]} {
            _bail render_hiders $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_hiders.dat]] hsph hcyl hrds hcls
            if {$hsph != 3} { _bail hider_spheres "exp=3 got=$hsph" }
            if {$hcyl != 0} { _bail hider_fcyl "exp=0 got=$hcyl (hider bonds end on unselected real atoms -- both-endpoints rule)" }
            if {[llength $hcls] != $hsph} {
                _bail hider_color_count "exp=$hsph colors got=[llength $hcls]"
            }
            foreach c $hcls {
                set ok 0
                foreach ref $elem_colors {
                    if {[_cnear $c $ref 0.01]} { set ok 1; break }
                }
                if {!$ok} { _bail hider_color "$c not within 0.01 of an element color" }
                if {[_cnear $c $salmon 0.01]} {
                    _bail hider_salmon "SALMON leak (Name-coloring trap): $c"
                }
            }
        }

        # (c) SCALE RATIO (probe selection unchanged: resname GAM and beta < 0):
        #     VDW render -> mean sphere Rad; CPK render -> mean sphere Rad;
        #     ratio in [0.20, 0.30]. Both renders must parse exactly 3 spheres
        #     / 0 cyls so the means are pure sphere radii (an FCylinder Rad
        #     line would pollute a naive mean).
        set mean_vdw -1
        set mean_cpk -1
        mol modstyle $probe_idx $gm VDW
        if {[catch {render Tachyon [file join [pwd] cpk_vdw.dat]} rerr]} {
            _bail render_vdw $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_vdw.dat]] vs vc vrds vcls
            if {$vs != 3 || $vc != 0} {
                _bail vdw_render "exp=3 sph / 0 cyl got=$vs/$vc"
            } else {
                set mean_vdw [_mean $vrds]
            }
        }
        mol modstyle $probe_idx $gm CPK
        if {[catch {render Tachyon [file join [pwd] cpk_cpk.dat]} rerr]} {
            _bail render_cpk $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_cpk.dat]] cs cc crds ccls
            if {$cs != 3 || $cc != 0} {
                _bail cpk_render "exp=3 sph / 0 cyl got=$cs/$cc"
            } else {
                set mean_cpk [_mean $crds]
            }
        }
        set ratio -1.0
        if {$mean_vdw > 0 && $mean_cpk > 0} {
            set ratio [expr {double($mean_cpk) / double($mean_vdw)}]
        }
        if {[catch {expr {($ratio < $ratio_lo) || ($ratio > $ratio_hi)}} bad] || $bad} {
            _bail scale_ratio "exp mean(CPK)/mean(VDW) in \[$ratio_lo,$ratio_hi\] got=$ratio (cpk=$mean_cpk vdw=$mean_vdw; probe K: VDW C Rad 0.094504, CPK ~0.25x)"
        }

        # (d) Scene-diff: probe emptied; the SCENE rep (index 0, the
        #     PRE-STYLED CPK rep, selection all) renders A = all vs
        #     B = not resname GAM. The hider spheres are drawn by the scene
        #     CPK rep: A has exactly 3 more spheres than B; the hider stubs
        #     are drawn by the scene rep too (both-endpoints rule): A loses
        #     >= 3 cylinders in B.
        mol modselect $probe_idx $gm {index 999999}
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm all
        }
        set rA_ok 0
        set rB_ok 0
        if {[catch {render Tachyon [file join [pwd] cpk_sceneA.dat]} rerr]} {
            _bail render_sceneA $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_sceneA.dat]] asph acyl ards acls
            set rA_ok 1
        }
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm {not resname GAM}
        }
        if {[catch {render Tachyon [file join [pwd] cpk_sceneB.dat]} rerr]} {
            _bail render_sceneB $rerr
        } else {
            lassign [_parse_dat [file join [pwd] cpk_sceneB.dat]] bsph bcyl brds2 bcls2
            set rB_ok 1
        }
        if {$rA_ok && $rB_ok} {
            set dsph [expr {$asph - $bsph}]
            if {$dsph != 3} {
                _bail scene_hider_sph "exp=A.sph - B.sph == 3 got=$dsph (A=$asph B=$bsph; hider spheres drawn by the pre-styled CPK scene rep)"
            }
            set dcyl [expr {$acyl - $bcyl}]
            if {$dcyl < 3} {
                _bail scene_stub_cyl "exp=A.cyl - B.cyl >= 3 got=$dcyl (A=$acyl B=$bcyl; hider stubs via both-endpoints rule)"
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

# ---- 6. FOUND-MARKING (the on_pick find sequence, single tier): flag 557,
#         then the partition re-splits ONLY the CPK tier. ----
if {$gm >= 0 && [llength $hider_idxs] == 3} {
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 557} merr]} {
        _bail mark_found_visual $merr
    } else {
        if {![catch {atomselect $gm "index 557"} s]} {
            set u2 [lindex [$s get user2] 0]
            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                _bail found_user2 "exp=user2 > 0 got=$u2"
            }
            $s delete
        } else { _bail found_sel $s }
        foreach {selstr expn tag} [list \
                {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 cpk_found \
                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 cpk_hidden] {
            if {![catch {atomselect $gm $selstr} s]} {
                if {[$s num] != $expn} {
                    _bail $tag "exp=$expn got=[$s num]"
                }
                $s delete
            } else { _bail ${tag}_sel $s }
        }
        if {[catch {::biochemeleon::registry::mark_found 557} mferr]} {
            _bail registry_mark_found $mferr
        }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
            _bail remaining_by_rep2 $rbr2
        } else {
            if {[catch {dict get $rbr2 CPK} got] || $got != 2} {
                _bail rbr2_cpk "exp=2 got=$got"
            }
        }
    }
}

# ---- 7. CLEANUP/RESTORE (style-faithful): registry 0, game molid DEAD,
#         restored original intact (555 atoms, numreps == pre-start, rep-0
#         style reads back CPK -- the pre-styled scene survives the round).
#         Runs even if earlier assertions failed (only a thrown start_game
#         error skips it -- then there is no round to clean). ----
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
        } elseif {$rn != 555} {
            _bail restored_atoms "exp=555 got=$rn"
        }
        if {[catch {molinfo $restored_molid get numreps} rr]} {
            _bail restored_numreps $rr
        } elseif {$rr != $pre_reps} {
            _bail restored_numreps "exp=$pre_reps got=$rr"
        }
        # Style-faithful restore: the pre-styled CPK scene rep reads back
        # CPK on the restored molecule.
        set rstyle0 ""
        if {[catch {foreach {rstyle0 rsel0 rcol0 rmat0} [molinfo $restored_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} rrb]} {
            _bail restored_style_readback $rrb
        } elseif {$rstyle0 ne "CPK"} {
            _bail restored_style "exp=CPK got=$rstyle0 (pre-style lost in restore)"
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
