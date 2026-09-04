# vmd/smoke/phase17_licorice_smoke.tcl
# Phase-17.1 (17.1-10) headless smoke: the LICORICE tier END-TO-END through the
# real 17.1-06 dispatch -- including blending into a scene that is ITSELF
# styled Licorice. Structure copied from phase17_points_smoke.tcl (17.1-08,
# the wave template); the NEW pattern introduced here -- PRE-STYLING the scene
# rep before start_game -- is what 17.1-11 (CPK) and 17.1-12 (DynamicBonds)
# reuse.
#
# Proves (the 17.1-10 must-haves), on demo 1k8p (555 atoms -- exercises the
# second bundled demo) with game::start_game $molid 3 [dict create Licorice 3] 0:
#   1. PRE-STYLED SCENE (17.1-10's new pattern): BEFORE start_game the
#      original molecule's default rep (rep 0, selection all) is restyled
#      `mol modstyle 0 $m Licorice` and validated by read-back (P-1: a bad
#      style only prints console ERROR and no-ops). backup::snapshot captures
#      the restyled rep; backup::apply re-applies it on the game molecule, so
#      the scene-diff (5c) measures the actual Licorice blend geometry; and
#      cleanup proves the pre-style survives the whole snapshot->apply->
#      restore round-trip (snapshot fidelity).
#   2. ROUND: 558-atom game molecule; hider indices {555 556 557} (file order
#      == record order); user3 == 1.0 numeric on all three (float read-back,
#      P10); registry count_hiders 3; remaining_by_rep == {Licorice 3}; a real
#      atom keeps user3 == 0.0 (P6: the sentinel conjunct must exclude them).
#   3. MIMICRY + BONDS: per hider -- element in {C N O S P}; radius == the
#      element's VDW radius (eps 1e-6; float32 read-back) AND == the real
#      same-element radius in this molecule; name in the real atom-name set
#      (collected once pre-start); numbonds >= 1 (extra bonds are normal and
#      blend-positive -- viability research sec 3).
#   4. REP READ-BACK via tier_reps + mol repindex (COMBINED-BRACES molinfo
#      form; single-field form FAILS -- Pitfall 3): numreps == pre_start + 2;
#      hidden pair style == "Licorice" EXACTLY (bare form round-trips,
#      params optional -- probe p1) + color "Element" + selection
#      "resname GAM and beta < 0 and user2 < 1 and user3 1"; found pair
#      "ColorID 7" + the user2 > 0 variant. Read-back string-compare, NEVER
#      catch. Must run BEFORE the render phase empties the pair selections.
#   5. TACHYON RENDERS (headless pixel-proxy, viability sec 2/sec 7; probe rep
#      added LAST and deleted LAST -- deleting the highest index never
#      renumbers earlier reps; `axes location off` first; all OTHER reps
#      emptied by modselect to a null selection because `mol showrep off` is
#      IGNORED in text mode -- probe F6):
#      a. Baseline-zero: probe selection "index 999999" -> 0 Sphere + 0
#         FCylinder (harness proof: the parser really counts the scene).
#      b. Hider-rep exclusive: selection "resname GAM and beta < 0", style
#         Licorice, color Element -> exactly 3 spheres (Licorice draws every
#         selected atom as a BOND-RADIUS ball -- probe p6b: hiders-only rep
#         = spheres, no cyl) and 0 FCylinder (the both-endpoints rule: no
#         hider's bond partner is in the selection; hiders sit >= 4 A apart
#         so no GAM-GAM bonds either), every parsed Color within eps 0.01 of
#         an element color, NO salmon (1.0 0.6 0.6 -- the GAM-name
#         Name-coloring trap).
#      c. Scene-diff (scene rep 0 is NOW Licorice via backup::apply,
#         selection all): render A "all" vs render B "not resname GAM" ->
#         (A.sph - B.sph) == 3 (every selected Licorice atom draws a ball, so
#         removing the 3 hiders removes exactly 3 balls) AND
#         (A.cyl - B.cyl) >= 3 (hider stubs drawn by the scene rep via the
#         both-endpoints rule; >= because Tachyon merges same-color
#         collinear half-bonds). Delete the probe rep after the renders.
#      .dat format pinned from the research probes + the 17.1-08 probe render:
#      one "Sphere "/FCylinder header line per primitive, "   Rad <f> " after
#      Center/Base/Apex, per-primitive color on the "Phong Plastic ... Color R
#      G B TexFunc 0" line. The two "Directional_Light ... Color 1 1 1" header
#      lines carry a Color token and are FILTERED (a naive whole-file Color
#      regex counts the lights -- 17.1-08's pinned lesson).
#   6. FOUND-MARKING: hiders::mark_found_visual $gm 556 -> user2(556) > 0
#      numeric; atomselect user2 > 0 / user3 1 num == 1; the user2 < 1 variant
#      num == 2 (per-tier partition); remaining_by_rep Licorice == 2. The
#      mark's mandatory modselect re-assert also RESTORES the pair selections
#      that the render phase emptied (unchanged-string contract, hiders.tcl).
#   7. CLEANUP: game::cleanup $gs -> registry 0; game molid DEAD; restored
#      original intact (numatoms 555) with numreps == pre_start AND rep-0
#      style reading back "Licorice" (snapshot fidelity: the pre-styled scene
#      survives backup::apply + restore byte-faithfully -- lock-scene-adjacent
#      style survival).
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
# probe-pinned from the research renders AND 17.1-08's probe render (cyan
# 0.25 0.75 0.75, red 1 0 0 observed byte-exact). P tan is the pinned
# approximate value from colordefs.dat (Element P -> tan): re-pin from a
# render if 1k8p anchors draw a P hider and the eps-0.01 compare trips.
set elem_colors [list \
    {0.25 0.75 0.75} \
    {0.0 0.0 1.0} \
    {1.0 0.0 0.0} \
    {1.0 1.0 0.0} \
    {0.5 0.5 0.31}]
# SALMON (1.0 0.6 0.6) = Name-coloring leak on GAM-named atoms. Must NEVER
# appear in a hider render (hiders are anchor-named + reps use Element).
set salmon {1.0 0.6 0.6}
# Lines/Points export lone-atom dots as Spheres Rad 0.002 (17.1-08 pin).
# Licorice balls are bond-radius sized (probe p6b) -- strictly larger than
# the dot class. Ball-radius pin 0.0119155 from THIS plan's first hider-rep
# render (all 3 hider balls byte-identical; the 17.1-08 pin-from-first-render
# method) -- asserted exactly (eps 1e-6) on top of the > dot-class bound.
set max_dot_rad 0.002
# Licorice ball-radius pin (0 = unpinned -- only the > dot-class bound is
# asserted).
set lic_ball_rad 0.0119155

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

# ---- 1. SETUP + PRE-STYLE + ROUND: load 1k8p (555 atoms), PRE-STYLE the
#         scene rep (rep 0) to Licorice on the ORIGINAL molecule, capture
#         pre-start state and the real-atom reference sets, start an EXPLICIT
#         Licorice-only round. ----
if {[catch {::biochemeleon::demos::load_demo 1k8p} orig_molid]} {
    _bail load_demo $orig_molid
} else {
    set n0 [molinfo $orig_molid get numatoms]
    if {$n0 != 555} { _bail orig_atoms "exp=555 got=$n0" }
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
    # PRE-STYLE THE SCENE (the 17.1-10 pattern): restyle the original's
    # default rep (rep 0, selection all) to Licorice BEFORE start_game.
    # mol modstyle on rep 0 of a fresh demo is safe (canonical GAME_REPS
    # spelling). backup::snapshot captures it; backup::apply re-applies it on
    # the game molecule; cleanup proves it survives restore.
    if {[catch {mol modstyle 0 $orig_molid Licorice} merr]} {
        _bail prestyle $merr
    }
    # P-1: validate the pre-style by read-back (a bad style only prints
    # console ERROR and no-ops). COMBINED-BRACES form (single-field form
    # FAILS -- Pitfall 3).
    set prst ""; set prsl ""; set prcl ""; set prmt ""
    if {[catch {foreach {prst prsl prcl prmt} [molinfo $orig_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} prb]} {
        _bail prestyle_readback $prb
    } elseif {$prst ne "Licorice"} {
        _bail prestyle "exp=Licorice got=$prst"
    }
    set pre_reps [molinfo $orig_molid get numreps]
    if {[catch {::biochemeleon::game::start_game $orig_molid 3 [dict create Licorice 3] 0} gs]} {
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
        if {$tcode != 1 || $tstyle ne "Licorice" || $tcnt != 3} {
            _bail tier1 "got=[lindex $tiers 0] (single Licorice tier, code 1)"
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
        if {[catch {dict get $rbr Licorice} got] || $got != 3} {
            _bail rbr_licorice "exp=3 got=$got"
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
        # Per-field SINGLE-attribute gets (multi-attribute get returns NESTED
        # per-atom tuples even on single-atom selections -- 17.1-08's
        # probe-pinned gotcha).
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
            if {$st ne "Licorice"} {
                _bail ${rname}_style "exp=Licorice got=$st"
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
        mol modstyle $probe_idx $gm Licorice
        mol modcolor $probe_idx $gm Element
        mol modselect $probe_idx $gm {index 999999}
        # P-1: validate the probe rep by read-back (a bad style never raises).
        set pst ""; set psl ""; set pcl ""
        if {[catch {foreach {pst psl pcl pmt} [molinfo $gm get "{rep $probe_idx} {selection $probe_idx} {color $probe_idx} {material $probe_idx}"] { break }} prb]} {
            _bail probe_readback $prb
        } elseif {$pst ne "Licorice"} {
            _bail probe_style "exp=Licorice got=$pst"
        }
        # Empty ALL other reps (scene + hidden + found) so every render is
        # attributable to the probe rep alone. The pair selections are stored
        # literals -- mark_found_visual re-asserts (restores) them in step 6.
        for {set i 0} {$i < $probe_idx} {incr i} {
            mol modselect $i $gm {index 999999}
        }

        # (a) Baseline-zero: 0 primitives -- the harness proof (a missing
        #     file parses as -1 and bails; a real empty scene parses 0/0).
        if {[catch {render Tachyon [file join [pwd] lic_base.dat]} rerr]} {
            _bail render_base $rerr
        } else {
            lassign [_parse_dat [file join [pwd] lic_base.dat]] bs bc brd bcl
            if {$bs != 0 || $bc != 0} {
                _bail baseline_zero "exp=0/0 primitives got=$bs/$bc"
            }
        }

        # (b) Hider-rep exclusive: exactly 3 bond-radius balls, 0 FCylinder
        #     (both-endpoints rule -- no hider partner is in the selection),
        #     element colors only, no salmon.
        mol modselect $probe_idx $gm {resname GAM and beta < 0}
        if {[catch {render Tachyon [file join [pwd] lic_hiders.dat]} rerr]} {
            _bail render_hiders $rerr
        } else {
            lassign [_parse_dat [file join [pwd] lic_hiders.dat]] hs hc hrds hcls
            if {$hs != 3} { _bail hider_spheres "exp=3 got=$hs" }
            if {$hc != 0} {
                _bail hider_fcyl "exp=0 got=$hc (both-endpoints rule: no cylinder without both endpoints selected)"
            }
            # Bond-radius balls: strictly larger than the Lines/Points dot
            # class (Rad 0.002); when lic_ball_rad is pinned, exactly the pin.
            foreach r $hrds {
                if {[catch {expr {double($r) > $max_dot_rad}} ok] || !$ok} {
                    _bail hider_ball_rad "rad=$r (expect > $max_dot_rad, bond-radius ball not a dot)"
                    break
                }
                if {$lic_ball_rad > 0.0 && ![_feq $r $lic_ball_rad]} {
                    _bail hider_ball_pin "rad=$r exp=$lic_ball_rad"
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
        #     0..pre_reps-1, re-applied by backup::apply WITH the pre-styled
        #     Licorice) render A = all vs B = not resname GAM. Under Licorice
        #     every selected atom draws a ball, so A loses exactly 3 spheres
        #     in B (the hider balls) AND >= 3 cylinders (the hider stubs,
        #     both-endpoints rule; >= for same-color half-bond merging).
        mol modselect $probe_idx $gm {index 999999}
        # The scene rep must read back Licorice ON THE GAME MOLECULE
        # (backup::apply carried the pre-style through the snapshot).
        set sst ""; set ssl ""; set scl ""
        if {[catch {foreach {sst ssl scl smt} [molinfo $gm get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} srb]} {
            _bail scene_style_readback $srb
        } elseif {$sst ne "Licorice"} {
            _bail scene_style "exp=Licorice got=$sst (pre-style must survive backup::apply)"
        }
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm all
        }
        set rA_ok 0
        set rB_ok 0
        if {[catch {render Tachyon [file join [pwd] lic_sceneA.dat]} rerr]} {
            _bail render_sceneA $rerr
        } else {
            lassign [_parse_dat [file join [pwd] lic_sceneA.dat]] asph acyl ards acls
            set rA_ok 1
        }
        for {set i 0} {$i < $pre_reps && $i < $probe_idx} {incr i} {
            mol modselect $i $gm {not resname GAM}
        }
        if {[catch {render Tachyon [file join [pwd] lic_sceneB.dat]} rerr]} {
            _bail render_sceneB $rerr
        } else {
            lassign [_parse_dat [file join [pwd] lic_sceneB.dat]] bsph bcyl brds2 bcls2
            set rB_ok 1
        }
        if {$rA_ok && $rB_ok} {
            set dsph [expr {$asph - $bsph}]
            if {$dsph != 3} {
                _bail scene_hider_balls "exp=A.sph - B.sph == 3 got=$dsph (A=$asph B=$bsph; every selected Licorice atom draws a ball)"
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

# ---- 6. FOUND-MARKING (the on_pick find sequence, single tier): flag 556,
#         then the partition re-splits ONLY the Licorice tier. ----
if {$gm >= 0 && [llength $hider_idxs] == 3} {
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm 556} merr]} {
        _bail mark_found_visual $merr
    } else {
        if {![catch {atomselect $gm "index 556"} s]} {
            set u2 [lindex [$s get user2] 0]
            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                _bail found_user2 "exp=user2 > 0 got=$u2"
            }
            $s delete
        } else { _bail found_sel $s }
        foreach {selstr expn tag} [list \
                {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 licorice_found \
                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 licorice_hidden] {
            if {![catch {atomselect $gm $selstr} s]} {
                if {[$s num] != $expn} {
                    _bail $tag "exp=$expn got=[$s num]"
                }
                $s delete
            } else { _bail ${tag}_sel $s }
        }
        if {[catch {::biochemeleon::registry::mark_found 556} mferr]} {
            _bail registry_mark_found $mferr
        }
        if {[catch {::biochemeleon::registry::remaining_by_rep} rbr2]} {
            _bail remaining_by_rep2 $rbr2
        } else {
            if {[catch {dict get $rbr2 Licorice} got] || $got != 2} {
                _bail rbr2_licorice "exp=2 got=$got"
            }
        }
    }
}

# ---- 7. CLEANUP/RESTORE: registry 0, game molid DEAD, restored original
#         intact (numatoms 555, numreps == pre-start, rep-0 style STILL
#         Licorice -- the pre-styled scene survives the whole round-trip).
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
        # Snapshot fidelity: the PRE-STYLED rep-0 style reads back Licorice on
        # the restored original (style survives snapshot -> apply -> restore).
        set rst ""; set rsl ""; set rcl ""
        if {[catch {foreach {rst rsl rcl rmt} [molinfo $restored_molid get "{rep 0} {selection 0} {color 0} {material 0}"] { break }} rb2]} {
            _bail restored_style_readback $rb2
        } elseif {$rst ne "Licorice"} {
            _bail restored_style "exp=Licorice got=$rst (pre-styled style must survive snapshot->apply->restore)"
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
