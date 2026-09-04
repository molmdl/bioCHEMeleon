# vmd/smoke/phase17_points_smoke.tcl
# Phase-17.1 (17.1-08) headless smoke: the POINTS tier END-TO-END through the
# real 17.1-06 dispatch -- the first bonded-tier round and the TEMPLATE for
# the 17.1-09..12 bond-family smokes (Lines/Licorice/CPK/DynamicBonds copy
# this file's structure and its Tachyon probe pattern).
#
# Proves (the 17.1-08 must-haves), on demo 1znf (424 atoms) with
#   game::start_game $molid 3 [dict create Points 3] 0:
#   1. ROUND: 427-atom game molecule; hider indices {424 425 426} (file order
#      == record order); user3 == 1.0 numeric on all three (float read-back,
#      P10); registry count_hiders 3; remaining_by_rep == {Points 3}; a real
#      atom keeps user3 == 0.0 (P6: the sentinel conjunct must exclude them).
#   2. MIMICRY: per hider -- element in {C N O S P}; radius == the element's
#      VDW radius (eps 1e-6; read-back is float32, e.g. 1.7000000476 for C --
#      probe-pinned); name in the real atom-name set (collected once
#      pre-start).
#   3. BOND LAW: every hider numbonds >= 1 (extra bonds to H/N neighbors are
#      normal and blend-positive -- viability research sec 3).
#   4. REP READ-BACK via tier_reps + mol repindex (COMBINED-BRACES molinfo
#      form, single-field form FAILS -- Pitfall 3): numreps == pre_start + 2;
#      hidden pair style == "Points" EXACTLY + color "Element" + selection
#      "resname GAM and beta < 0 and user2 < 1 and user3 1"; found pair
#      "ColorID 7" + the user2 > 0 variant. Read-back string-compare, NEVER
#      catch (a bad style only prints console ERROR) and no-ops -- viability
#      P-1).
#   5. TACHYON RENDERS (headless pixel-proxy, viability sec 2/sec 7; probe rep
#      added LAST and deleted LAST -- deleting the highest index never
#      renumbers earlier reps; `axes location off` first; all OTHER reps
#      emptied by modselect to a null selection because `mol showrep off` is
#      IGNORED in text mode -- probe F6):
#      a. Baseline-zero: probe selection "index 999999" -> 0 Sphere + 0
#         FCylinder (harness proof: the parser really counts the scene).
#      b. Hider-rep exclusive: selection "resname GAM and beta < 0" -> exactly
#         3 spheres (Points exports one tiny sphere per atom, Rad 0.002
#         probe-pinned, asserted < 0.02), 0 FCylinder, every parsed Color
#         within eps 0.01 of an element color, NO salmon (1.0 0.6 0.6 -- the
#         GAM-name Name-coloring trap).
#      c. Scene-diff (scene rep = the restored default Lines, selection all):
#         render A "all" vs render B "not resname GAM" -> (A.cyl - B.cyl) >= 3
#         (hider stubs drawn by the SCENE rep via the both-endpoints rule) and
#         (A.sph - B.sph) == 0 (no stray dot geometry either way).
#      .dat format pinned from the research probes + this plan's probe render:
#      one "Sphere "/FCylinder header line per primitive, "   Rad <f> " after
#      Center/Base/Apex, per-primitive color on the "Phong Plastic ... Color R
#      G B TexFunc 0" line. The two "Directional_Light ... Color 1 1 1" header
#      lines carry a Color token and are FILTERED (a naive whole-file Color
#      regex counts the lights -- found by inspecting the first render before
#      pinning, as the plan prescribes).
#   6. FOUND-MARKING: hiders::mark_found_visual $gm 425 -> user2(425) > 0
#      numeric; atomselect user2 > 0 / user3 1 num == 1; the user2 < 1 variant
#      num == 2 (per-tier partition); remaining_by_rep Points == 2. The
#      mark's mandatory modselect re-assert also RESTORES the pair selections
#      that the render phase emptied (unchanged-string contract, hiders.tcl).
#   7. CLEANUP: game::cleanup $gs -> registry 0; game molid DEAD; restored
#      original intact (numatoms 424) with numreps == pre_start (no leak).
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and is
# recorded for a gap-closure plan -- never patched from a tier smoke
# (wave-disjointness).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself -- same order as phase17_dispatch_smoke): setup_state, registry,
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
# carry "Color 1 1 1" and are skipped (not primitives -- see header).
# Returns {nsph ncyl rads colors}; nsph/ncyl == -1 signals an unreadable
# file (so a missing file can never masquerade as an empty scene).
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
set vdw_rad [dict create C 1.70 N 1.55 O 1.52 S 1.80 P 1.55]
# Element-method resolved RGBs (eps 0.01). C cyan / N blue / O red / S yellow
# probe-pinned from the research renders AND this plan's probe render (cyan
# 0.25 0.75 0.75, red 1 0 0 observed byte-exact). P tan is the plan's pinned
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
# Points dot radius bound (probe-pinned Rad 0.002; 17.1-09 pins the same
# < 0.02 dot bound for Lines dots).
set max_dot_rad 0.02

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

# ---- 1. SETUP + ROUND: load 1znf (424 atoms), capture pre-start state and
#         the real-atom reference sets, start an EXPLICIT Points-only round. ----
if {[catch {::biochemeleon::demos::load_demo 1znf} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    set pre_reps [molinfo $orig_molid get numreps]
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
    if {[catch {::biochemeleon::game::start_game $orig_molid 3 [dict create Points 3] 0} gs]} {
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
        if {$tcode != 1 || $tstyle ne "Points" || $tcnt != 3} {
            _bail tier1 "got=[lindex $tiers 0] (single Points tier, code 1)"
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
    set ch [::biochemeleon::registry::count_hiders]
    if {$ch != 3} { _bail reg_count "exp=3 got=$ch" }
    if {[catch {::biochemeleon::registry::remaining_by_rep} rbr]} {
        _bail remaining_by_rep $rbr
    } else {
        if {[dict size $rbr] != 1} {
            _bail rbr_size "exp=1 got=$rbr"
        }
        if {[catch {dict get $rbr Points} got] || $got != 3} {
            _bail rbr_points "exp=3 got=$got"
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
        # chemistry; extra bonds are normal -- viability sec 3).
        if {![string is integer -strict $nb] || $nb < 1} {
            _bail bond_$idx "numbonds=$nb (expect >= 1)"
        }
    }
}

# ---- 4. REP READ-BACK via tier_reps + repindex (COMBINED-BRACES form; the
#         exact literal selections per the 17.1-08 contract). Must run BEFORE
#         the render phase empties the pair selections. ----
if {$gm >= 0} {
    set nreps [molinfo $gm get numreps]
    if {$nreps != $pre_reps + 2} {
        _bail rep_count "exp=[expr {$pre_reps + 2}] got=$nreps"
    }
    if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
        _bail tier_reps_missing 1
    } else {
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
            if {$st ne "Points"} {
                _bail ${rname}_style "exp=Points got=$st"
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
        mol modstyle $probe_idx $gm Points
        mol modcolor $probe_idx $gm Element
        mol modselect $probe_idx $gm {index 999999}
        # P-1: validate the probe rep by read-back (a bad style never raises).
        set pst ""; set psl ""; set pcl ""
        if {[catch {foreach {pst psl pcl pmt} [molinfo $gm get "{rep $probe_idx} {selection $probe_idx} {color $probe_idx} {material $probe_idx}"] { break }} prb]} {
            _bail probe_readback $prb
        } elseif {$pst ne "Points"} {
            _bail probe_style "exp=Points got=$pst"
        }
        # Empty ALL other reps (scene + hidden + found) so every render is
        # attributable to the probe rep alone. The pair selections are stored
        # literals -- mark_found_visual re-asserts (restores) them in step 6.
        for {set i 0} {$i < $probe_idx} {incr i} {
            mol modselect $i $gm {index 999999}
        }

        # (a) Baseline-zero: 0 primitives -- the harness proof (a missing
        #     file parses as -1 and bails; a real empty scene parses 0/0).
        if {[catch {render Tachyon [file join [pwd] pts_base.dat]} rerr]} {
            _bail render_base $rerr
        } else {
            lassign [_parse_dat [file join [pwd] pts_base.dat]] bs bc brd bcl
            if {$bs != 0 || $bc != 0} {
                _bail baseline_zero "exp=0/0 primitives got=$bs/$bc"
            }
        }

        # (b) Hider-rep exclusive: exactly 3 tiny spheres, 0 FCylinder,
        #     element colors only, no salmon.
        mol modselect $probe_idx $gm {resname GAM and beta < 0}
        if {[catch {render Tachyon [file join [pwd] pts_hiders.dat]} rerr]} {
            _bail render_hiders $rerr
        } else {
            lassign [_parse_dat [file join [pwd] pts_hiders.dat]] hs hc hrds hcls
            if {$hs != 3} { _bail hider_spheres "exp=3 got=$hs" }
            if {$hc != 0} { _bail hider_fcyl "exp=0 got=$hc (Points draws no bonds)" }
            foreach r $hrds {
                if {[catch {expr {double($r) < $max_dot_rad}} ok] || !$ok} {
                    _bail hider_dot_rad "rad=$r (expect < $max_dot_rad, probe-pinned 0.002)"
                    break
                }
            }
            if {[llength $hcls] != $hs} {
                _bail hider_color_count "exp=$hs colors got=[llength $hcls]"
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

        # (c) Scene-diff: probe emptied; the SCENE rep(s) (indices
        #     0..pre_reps-1, restored by backup::apply with selection all)
        #     render A = all vs B = not resname GAM. The hider stubs are
        #     drawn by the scene rep (both-endpoints rule): A loses >= 3
        #     cylinders in B; spheres equal (no stray dots either way).
        mol modselect $probe_idx $gm {index 999999}
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm all
        }
        set rA_ok 0
        set rB_ok 0
        if {[catch {render Tachyon [file join [pwd] pts_sceneA.dat]} rerr]} {
            _bail render_sceneA $rerr
        } else {
            lassign [_parse_dat [file join [pwd] pts_sceneA.dat]] asph acyl ards acls
            set rA_ok 1
        }
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm {not resname GAM}
        }
        if {[catch {render Tachyon [file join [pwd] pts_sceneB.dat]} rerr]} {
            _bail render_sceneB $rerr
        } else {
            lassign [_parse_dat [file join [pwd] pts_sceneB.dat]] bsph bcyl brds2 bcls2
            set rB_ok 1
        }
        if {$rA_ok && $rB_ok} {
            set dcyl [expr {$acyl - $bcyl}]
            if {$dcyl < 3} {
                _bail scene_stub_cyl "exp=A.cyl - B.cyl >= 3 got=$dcyl (A=$acyl B=$bcyl; hider stubs via both-endpoints rule)"
            }
            set dsph [expr {$asph - $bsph}]
            if {$dsph != 0} {
                _bail scene_dot_sph "exp=A.sph - B.sph == 0 got=$dsph (A=$asph B=$bsph)"
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

# ---- 6. FOUND-MARKING (the on_pick find sequence, single tier): flag 425,
#         then the partition re-splits ONLY the Points tier. ----
if {$gm >= 0 && [llength $hider_idxs] == 3} {
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 425} merr]} {
        _bail mark_found_visual $merr
    } else {
        if {![catch {atomselect $gm "index 425"} s]} {
            set u2 [lindex [$s get user2] 0]
            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                _bail found_user2 "exp=user2 > 0 got=$u2"
            }
            $s delete
        } else { _bail found_sel $s }
        foreach {selstr expn tag} [list \
                {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 points_found \
                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 points_hidden] {
            if {![catch {atomselect $gm $selstr} s]} {
                if {[$s num] != $expn} {
                    _bail $tag "exp=$expn got=[$s num]"
                }
                $s delete
            } else { _bail ${tag}_sel $s }
        }
        if {[catch {::biochemeleon::registry::mark_found 425} mferr]} {
            _bail registry_mark_found $mferr
        }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
            _bail remaining_by_rep2 $rbr2
        } else {
            if {[catch {dict get $rbr2 Points} got] || $got != 2} {
                _bail rbr2_points "exp=2 got=$got"
            }
        }
    }
}

# ---- 7. CLEANUP/RESTORE: registry 0, game molid DEAD, restored original
#         intact (numatoms 424, numreps == pre-start -- no leak). Runs even
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
