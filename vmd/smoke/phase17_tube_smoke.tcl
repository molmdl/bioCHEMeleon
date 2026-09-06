# vmd/smoke/phase17_tube_smoke.tcl
# Phase-17.2 (17.2-08) headless smoke: the TUBE tier end-to-end -- the
# smooth-spline residue-splice consumer, COMPLETING THE FOUR-REP FAMILY
# (Cartoon/NewCartoon/Trace/Tube) on ONE splice mechanism.
#
# THE FOUR RESIDUE TIERS CONSUME THE IDENTICAL SPLICE: this smoke's
# splice/registry/rep asserts are STRUCTURALLY those of 17.2-05/06/07 -- only
# the style name (`Tube`) and the primitive expectation differ (Tube = pure
# CA spline -> FCylinder segments, NEVER TriStrip/STri; UG node66).
#
# Proves, on demo 1znf (424 atoms, single-frame collapse loader):
#   1. SPLICE: make_residue_hiders 3 -> 3 records (real chain, resids
#      {9001 9002 9003}, N-first/CA-second); mutate -> 424+fake atoms;
#      CA-only sentinel (`resname GAM and beta < 0`) == 3, names CA,
#      resids {9001 9002 9003}; GAM total == the record-derived atom count;
#      segid GAME on all fakes; chain == the anchor's chain; BOTH junctions
#      bonded (scoped partner-resid check, the 17.2-04-proven method);
#      the load-time STRIDE letter on the fake CAs is RECORDED and asserted
#      to the coil/turn family {T, C} (the exact letter is anchor-dependent,
#      17.2-04 discovery; Tube is SS-INDEPENDENT -- UG node66 -- so the
#      smooth CA spline includes the fake CA with NO ss involvement: this is
#      the Option-A "no sidestep needed" evidence for the SS-independent
#      half of the family; the render asserts are purely geometric).
#   2. HIDER REPS (17.1-04 contracts): stamp_tier_codes (code 1 = the 3 CA
#      indices, user3 read-back ~1.0 numeric) BEFORE add_hider_reps {{1
#      Tube}} (ordering contract); numreps == pre + 2; read-back style ==
#      `Tube` EXACTLY, hidden Element / found ColorID 7, selections the
#      exact user3-conjoined literals.
#   3. RENDERS (probe rep LAST via _render_bits; baseline-zero first):
#      a. baseline-zero `index 999999` -> 0 primitives of every kind.
#      b. GAME-only exclusive (segid GAME, Tube, Element): FCylinder >= 3
#         (spline segments over the fake residues -- research measured
#         6/residue; assert >= 3, not exact) AND TriStrip == 0 (Tube draws
#         no mesh); colors parsed -- NO salmon (1.0 0.6 0.6, the GAM-name
#         Name-coloring trap).
#      c. WINDOW PATH-INCLUSION renders (PRINTS/EVIDENCE ONLY -- the
#         17.2-04 STRIDE-variance discovery: cross-molecule window counts
#         are shift-variant, zero pathology; observed 22->6 on Cartoon):
#         spliced bare window `resid <a-2> to <a+2>`, the fake-inclusive
#         variant (`... or segid GAME`), and the same window on a
#         fresh-original control -- printed, never asserted.
#      d. POSITIVE CONTROL = the 17.1-08 BOND SCENE-DIFF (ss-independent,
#         floor-asserted): scene rep renders A = all vs B = not resname
#         GAM; the FCylinder delta == the fakes' bond count >= 4 per fake
#         atom (junction + intra-residue stubs, both-endpoints rule).
#   4. FOUND-MARKING: mark_found_visual on CA 2 -> user2 > 0 numeric;
#      found-selection (`user2 > 0 and user3 1` conjunct) num == 1; hidden
#      variant num == 2; CA 1/3 user2 still <= 0.
#   5. RESTORE: mol delete gm; fresh demo reload -> 424 atoms (no residue
#      leak); marker + exit.
#
# Tachyon technique (17.2-04 harness, copied): `axes location off` first;
# the probe rep is added LAST (highest index) and deleted after each
# render; every OTHER rep is emptied by modselect (mol showrep is IGNORED
# in text mode -- probe F6) and restored to its CAPTURED prior selection --
# NOT a blanket `all`: this molecule carries hider-pair reps whose literal
# selections must survive (the 17.2-04 splice molecule had no pair reps).
# Primitive tokens parsed with \m/word-boundary regexes so "TriStrip" can
# never false-match "STri".
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and
# is recorded for a gap-closure plan -- never patched from a tier smoke
# (wave-disjointness).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the
# entry itself); registry sourced EXACTLY ONCE; mutation sources splice.tcl
# itself (pure layer).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root). VMD does NOT propagate tcl exit codes (Pitfall
# 4) -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD -e catches
# top-level errors and CONTINUES (false-PASS risk) -> every step is
# catch-wrapped + _bail'd, and the runner scans the FULL log for ERROR) /
# bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently). NEVER mol showrep. `within` references are ALWAYS
# parenthesized (VMD's within swallows trailing expressions).

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (beta/user/user2/user3 are FLOATS -- numeric only).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Frame pin for coordinate reads (the lib pins frame 0 everywhere; the
# smoke reads frame 0 to match).
proc _pin {sel} {
    catch {$sel frame 0}
    return $sel
}

# 3-point Euclidean distance.
proc _dist {p q} {
    lassign $p px py pz
    lassign $q qx qy qz
    return [expr {sqrt(($px - $qx) * ($px - $qx) \
        + ($py - $qy) * ($py - $qy) + ($pz - $qz) * ($pz - $qz))}]
}

# Parse a Tachyon .dat: \m/word-boundary primitive-token counts over the
# whole file. Returns {nsph ncyl nstri nstrip}; -1s signal an unreadable
# file (a missing file can never masquerade as an empty scene).
proc _parse_bits {path} {
    if {[catch {open $path r} fh]} {
        return [list -1 -1 -1 -1]
    }
    set dat [read $fh]
    close $fh
    set nsph [regexp -all -- {\mSphere\y} $dat]
    set ncyl [regexp -all -- {\mFCylinder\y} $dat]
    set nstri [regexp -all -- {\mSTri\y} $dat]
    set nstrip [regexp -all -- {\mTriStrip\y} $dat]
    return [list $nsph $ncyl $nstri $nstrip]
}

# Parse the Color R G B triples from a Tachyon .dat (per-primitive colors).
# Directional_Light lines carry "Color 1 1 1" and are skipped (not
# primitives -- the tier-smoke convention). Returns a list of triples.
proc _parse_colors {path} {
    set cols [list]
    if {[catch {open $path r} fh]} {
        return $cols
    }
    set dat [read $fh]
    close $fh
    foreach line [split $dat \n] {
        if {[string match "Directional_Light*" $line]} { continue }
        if {[regexp -- {Color\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)} $line -> cr cg cb]} {
            lappend cols [list $cr $cg $cb]
        }
    }
    return $cols
}

# Per-channel color proximity (eps 0.01 for the salmon-leak check).
proc _cnear {c ref eps} {
    if {[llength $c] != 3 || [llength $ref] != 3} { return 0 }
    foreach a $c b $ref {
        if {[expr {abs(double($a) - double($b))}] > $eps} { return 0 }
    }
    return 1
}

# THE reusable 17.2 render helper (17.2-05..08; capture/restore variant):
# add a probe rep LAST (highest index), style+select it, EMPTY every earlier
# rep (showrep is ignored in text mode), render Tachyon, restore the earlier
# reps to their CAPTURED prior selections (NOT a blanket `all` -- the hider
# pair reps' literal selections must survive), delete the probe rep (highest
# index -- never renumbers), return the parsed counts. `axes location off`
# must have been called once before the first render.
proc _render_bits {m style sel path} {
    # Isolate the scene: VMD renders EVERY DISPLAYED molecule -- any other
    # live molecule's reps would pollute the count (17.2-04: a still-alive
    # game molecule added ~823 phantom FCylinders).
    set others [list]
    foreach mm [molinfo list] {
        if {$mm != $m} { lappend others $mm }
    }
    foreach mm $others { catch {mol off $mm} }
    set pi [molinfo $m get numreps]
    # CAPTURE prior selections for the exact restore.
    set prior [list]
    for {set i 0} {$i < $pi} {incr i} {
        set psl ""
        catch {foreach psl [molinfo $m get "{selection $i}"] { break }}
        lappend prior $psl
    }
    mol addrep $m
    mol modstyle $pi $m $style
    mol modcolor $pi $m Element
    mol modselect $pi $m $sel
    for {set i 0} {$i < $pi} {incr i} {
        mol modselect $i $m {index 999999}
    }
    set rc [catch {render Tachyon $path} rerr]
    for {set i 0} {$i < $pi} {incr i} {
        set psl [lindex $prior $i]
        if {$psl eq ""} {
            catch {mol modselect $i $m all}
        } else {
            catch {mol modselect $i $m $psl}
        }
    }
    catch {mol delrep $pi $m}
    foreach mm $others { catch {mol on $mm} }
    if {$rc} { error "render Tachyon failed: $rerr" }
    return [_parse_bits $path]
}

# THE 17.2 harness loader (17.2-04, copied): load a demo COLLAPSED TO A
# SINGLE FRAME. 1znf ships 2 models; PIN FRAME 0 on every atomselect read;
# the caller contract is single-frame molecules (the frame-0-pinned
# writepdb round-trip is the SAME pipeline mutate uses downstream).
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] tube_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

# A residue's C atom index (for the junction-partner query).
proc _res_c_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name C"]]
    set ci [lindex [$s get index] 0]
    $s delete
    return $ci
}

# The next residue's N coords (first N within 1.7 A of the anchor C -- the
# anchor's own N is ~2.4 A away, excluded).
proc _next_n_pt {m c_idx} {
    set s [_pin [atomselect $m "name N and (within 1.7 of index $c_idx)"]]
    set pt [list \
        [lindex [$s get x] 0] \
        [lindex [$s get y] 0] \
        [lindex [$s get z] 0]]
    $s delete
    return $pt
}

# A residue's N atom index (mirror of _res_c_index).
proc _res_n_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name N"]]
    set ni [lindex [$s get index] 0]
    $s delete
    return $ni
}

# The junction partner resids for an anchor residue: the C bonded to the
# anchor N (prev) and the N bonded to the anchor C (next). Scoping the
# junction checks to THESE resids is the only exact partner test (a compact
# fold puts other residues' C/N atoms within 1.9 A of a displaced fake).
proc _junction_partners {m ch rid} {
    set ni [_res_n_index $m $ch $rid]
    set ci [_res_c_index $m $ch $rid]
    set prev_res -1
    set next_res -1
    if {$ni >= 0} {
        set s [_pin [atomselect $m "name C and (within 1.7 of index $ni)"]]
        set prev_res [lindex [$s get resid] 0]
        $s delete
    }
    if {$ci >= 0} {
        set s [_pin [atomselect $m "name N and (within 1.7 of index $ci)"]]
        set next_res [lindex [$s get resid] 0]
        $s delete
    }
    return [list $prev_res $next_res]
}

# Window low bound: the anchor may sit at resid 1 (N-term + ACE cap), and
# `resid -1 ...` is a VMD selection SYNTAX ERROR (the render then captures
# the un-emptied scene -- garbage counts). Clamp to the demo's min resid 0.
proc _wlo {a} {
    set w [expr {$a - 2}]
    if {$w < 0} { set w 0 }
    return $w
}

# Total fake-atom count across records (a GLY anchor yields a 4-atom
# residue -- NEVER hardcode 5 per residue).
proc _rec_atom_total {recs} {
    set t 0
    foreach r $recs { set t [expr {$t + [llength [lindex $r 2]]}] }
    return $t
}

# Bulk protein-CA table ({resid chain x y z}) for the nearest-anchor
# derivation -- records carry the FAKE resid (9001+k), never the anchor's.
proc _ca_table {m} {
    set s [_pin [atomselect $m {protein and name CA}]]
    set out [list]
    set rs [$s get resid]
    set cs [$s get chain]
    set xs [$s get x]
    set ys [$s get y]
    set zs [$s get z]
    $s delete
    for {set i 0} {$i < [llength $rs]} {incr i} {
        lappend out [list [lindex $rs $i] [lindex $cs $i] \
            [lindex $xs $i] [lindex $ys $i] [lindex $zs $i]]
    }
    return $out
}

# Defensive init so a failed earlier step never masks as a substitution error.
set m0 -1
set gm -1
set mc -1
set mr -1
set recs [list]
set n0 -1
set ca_idxs [list]
set anch_resid -1
set anchor_list [list]
set partner_list [list]
set pre_reps -1
set exp_fake 0

# SALMON (1.0 0.6 0.6) = Name-coloring leak on GAM-named atoms. Must NEVER
# appear in a hider render (hiders are anchor-named + reps use Element).
set salmon {1.0 0.6 0.6}

# ---- 0. Source the lib files in dependency order ([pwd]-relative). ----
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

if {[catch {axes location off} axerr]} {
    _bail axes_off $axerr
}

# ---- 1. SPLICE: load 1znf (424 atoms), make 3 residue hiders, assert the
#         records + derive anchors/junction partners (frame-0 pinned). ----
if {[catch {_load_demo_1f 1znf} m0]} {
    _bail load_demo $m0
    set m0 -1
} else {
    set n0 [molinfo $m0 get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    # Retry loop: 1znf is a COMPACT fold -- the greedy 5.0 A anchor
    # separation can under-generate (17.2-04: ~half the 2-draw runs landed
    # 1). Under-generation is tolerated mechanism behavior (vmdcon-warned);
    # the smoke needs 3 records for the family math, so re-draw until 3
    # (max 8 attempts; each call is a pure re-read -- nothing to undo).
    set recs [list]
    for {set att 0} {$att < 8} {incr att} {
        if {![catch {::biochemeleon::mutation::make_residue_hiders $m0 3} recs]} {
            if {[llength $recs] == 3} { break }
        } else {
            _bail make_residue_hiders $recs
            set recs [list]
            break
        }
    }
}
if {$m0 >= 0 && [llength $recs] != 3} {
    _bail rec_count "exp=3 got=[llength $recs]"
} elseif {$m0 >= 0} {
    # Records carry the FAKE resid (9001+k); the ANCHOR residue is derived
    # geometrically: the nearest real CA to the fake CA sits exactly 1.0 A
    # away (rigid translation; every other real CA is >= ~2.8 A out).
    set catab [_ca_table $m0]
    set k 0
    foreach r $recs {
        set tag "rec$k"
        if {[llength $r] != 3} {
            _bail ${tag}_shape "exp=3 fields got=[llength $r]"
            incr k
            continue
        }
        lassign $r ch rid atoms
        # chain is a real chain (NOT "G", NOT blank).
        if {[string trim $ch] eq ""} {
            _bail ${tag}_chain_blank "chain is blank"
        }
        if {$ch eq "G"} {
            _bail ${tag}_chain_g "chain is G (Pitfall C8 territory)"
        }
        set exp_rid [expr {9001 + $k}]
        if {$rid != $exp_rid} {
            _bail ${tag}_resid "exp=$exp_rid got=$rid"
        }
        # atoms >= 4, N-first/CA-second, subset of {N CA C O CB}.
        if {[llength $atoms] < 4} {
            _bail ${tag}_atom_count "exp>=4 got=[llength $atoms]"
            incr k
            continue
        }
        set names [list]
        foreach a $atoms { lappend names [lindex $a 0] }
        foreach bad {H OXT} {
            if {[lsearch -exact $names $bad] >= 0} {
                _bail ${tag}_atom_set "unexpected atom $bad"
            }
        }
        if {[lindex $names 0] ne "N" || [lindex $names 1] ne "CA"} {
            _bail ${tag}_order "exp=N-first/CA-second got=$names"
        }
        # Derive the anchor: nearest real CA to the fake CA (from the
        # RECORD's frame-0 coords; 1.0 A in [0.95, 1.05]).
        set fca [list]
        foreach a $atoms {
            if {[lindex $a 0] eq "CA"} {
                lassign [lrange $a 2 4] fx fy fz
                set fca [list $fx $fy $fz]
            }
        }
        set anch_res -1
        set anch_ch ""
        set best 1e9
        foreach c $catab {
            lassign $c cr cc cx cy cz
            set dd [_dist $fca [list $cx $cy $cz]]
            if {$dd < $best} {
                set best $dd
                set anch_res $cr
                set anch_ch $cc
            }
        }
        if {$anch_res < 0} {
            _bail ${tag}_anchor "no real CA found (catab empty?)"
            incr k
            continue
        }
        if {[catch {expr {double($best) >= 0.95 && double($best) <= 1.05}} inband] || !$inband} {
            _bail ${tag}_anchor_dist "nearest real CA (resid $anch_res) at $best, exp 1.0 in \[0.95,1.05\]"
        }
        lappend anchor_list [list $anch_ch $anch_res]
        lappend partner_list [_junction_partners $m0 $anch_ch $anch_res]
        incr k
    }
}

# ---- 2. ROUND: mutate with the residue records; assert the tagged mol. ----
if {$m0 >= 0 && [llength $recs] == 3} {
    if {[catch {::biochemeleon::mutation::mutate $m0 [list] $recs} gm]} {
        _bail mutate $gm
        set gm -1
    }
}
if {$gm >= 0} {
    set exp_fake [_rec_atom_total $recs]
    set exp_total [expr {424 + $exp_fake}]
    set n1 [molinfo $gm get numatoms]
    if {$n1 != $exp_total} { _bail game_atoms "exp=$exp_total got=$n1" }
    # CA-only sentinel: exactly ONE index per hider, names CA, resids
    # {9001 9002 9003} (pins the index<->record order for the recipe check).
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set ca_idxs [$s get index]
        set cads [$s get resid]
        set canms [$s get name]
        set nb [$s num]
        $s delete
        if {$nb != 3} { _bail sentinel_count "exp=3 got=$nb" }
        foreach nm $canms {
            if {$nm ne "CA"} { _bail sentinel_name "exp=CA got=$nm" }
        }
        if {$cads ne [list 9001 9002 9003]} {
            _bail ca_resids "exp={9001 9002 9003} got=$cads"
        }
    } else { _bail sentinel_sel $s }
    # GAM total == the record-derived count (a GLY anchor yields 4-atom
    # residues -- 15 only when every anchor carries CB; never hardcode).
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set ngam [$s num]
        $s delete
        if {$ngam != $exp_fake} { _bail gam_count "exp=$exp_fake got=$ngam" }
    } else { _bail gam_sel $s }
    # Load-time STRIDE letter on the fake CAs: RECORDED (printed) and
    # asserted to the coil/turn family {T, C} -- the exact letter is
    # anchor-dependent (17.2-04: STRIDE reads the displaced phi/psi
    # geometry). Tube is SS-INDEPENDENT (UG node66): the smooth CA spline
    # includes the fake CA with NO ss involvement -- both letters render as
    # the identical smooth tube, so the render asserts are purely geometric
    # (the Option-A "no sidestep needed" evidence).
    if {![catch {atomselect $gm {resname GAM and name CA}} s]} {
        set structs [$s get structure]
        $s delete
        set letters [list]
        foreach st $structs {
            lappend letters $st
            if {$st ne "T" && $st ne "C"} {
                _bail ca_structure "exp T or C (load-time STRIDE coil/turn family) got=$st"
            }
        }
        puts "TUBE_INFO fake_ca_structure letters=$letters (load-time STRIDE, recorded; Tube is ss-independent)"
    } else { _bail ca_struct_sel $s }
    # segid GAME on ALL fake atoms; chain == the anchor's chain per record.
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set gidx [$s get index]
        set gres [$s get resid]
        set gchn [$s get chain]
        set gseg [$s get segid]
        $s delete
        if {[llength $gidx] != $exp_fake} { _bail gam_walk "exp=$exp_fake got=[llength $gidx]" }
        set exp_chain [dict create]
        foreach r $recs {
            dict set exp_chain [lindex $r 1] [lindex $r 0]
        }
        for {set i 0} {$i < [llength $gidx]} {incr i} {
            set ii [lindex $gidx $i]
            set rr [lindex $gres $i]
            if {[lindex $gseg $i] ne "GAME"} {
                _bail fake_segid_$ii "exp=GAME got=[lindex $gseg $i]"
            }
            if {[dict exists $exp_chain $rr] && [lindex $gchn $i] ne [dict get $exp_chain $rr]} {
                _bail fake_chain_$ii "exp=[dict get $exp_chain $rr] got=[lindex $gchn $i]"
            }
        }
    } else { _bail gam_walk_sel $s }
    # Junction law (scoped partner check, the 17.2-04-proven method): for
    # each fake resid, its N has a bonded C (prev residue) and its C has a
    # bonded N (next residue) within the C-N bond cutoff (0.6*(1.70+1.55)
    # = 1.95; use 1.9 so ONLY bonded pairs can match). Partner resids come
    # from the pre-mutate derivation; `within` references are PARENTHESIZED.
    set fi -1
    foreach rr [list 9001 9002 9003] {
        incr fi
        set n_idx -1
        set c_idx -1
        if {![catch {atomselect $gm "resname GAM and resid $rr"} s]} {
            set ridx [$s get index]
            set rnam [$s get name]
            $s delete
            for {set i 0} {$i < [llength $ridx]} {incr i} {
                if {[lindex $rnam $i] eq "N"} { set n_idx [lindex $ridx $i] }
                if {[lindex $rnam $i] eq "C"} { set c_idx [lindex $ridx $i] }
            }
        } else { _bail junc_atoms_sel_$rr $s }
        if {$n_idx < 0 || $c_idx < 0} {
            _bail junction_atoms_$rr "N/C indices not found"
            continue
        }
        lassign [lindex $partner_list $fi] prev_res next_res
        if {![catch {atomselect $gm "name C and (within 1.9 of index $n_idx) and resid $prev_res"} js]} {
            set nj [$js num]
            $js delete
            if {$nj < 1} { _bail junction_n_$rr "fake N has no bonded C in resid $prev_res" }
        } else { _bail junction_sel_n_$rr $js }
        if {![catch {atomselect $gm "name N and (within 1.9 of index $c_idx) and resid $next_res"} js]} {
            set nj [$js num]
            $js delete
            if {$nj < 1} { _bail junction_c_$rr "fake C has no bonded N in resid $next_res" }
        } else { _bail junction_sel_c_$rr $js }
    }
    # Anchor recipe (shared by all four tier smokes): on the GAME molecule,
    # the nearest real CA to fake CA 1 (within 2.0, PARENTHESIZED) is
    # exactly 1 -- its resid IS the anchor's; cross-checks the catab-derived
    # anchor of record 1.
    set fakeca1 [lindex $ca_idxs 0]
    if {$fakeca1 ne "" && [llength $anchor_list] == 3} {
        if {![catch {atomselect $gm "name CA and (within 2.0 of index $fakeca1) and not index $fakeca1"} asel]} {
            $asel frame 0
            set na [$asel num]
            if {$na != 1} {
                _bail anchor_lookup "exp=1 nearest real CA got=$na (fakeca1=$fakeca1)"
            } else {
                set anch_resid [lindex [$asel get resid] 0]
                lassign [lindex $anchor_list 0] exp_ch exp_res
                if {$anch_resid != $exp_res} {
                    _bail anchor_recipe "gm-side resid $anch_resid != catab-derived $exp_res"
                }
                puts "TUBE_INFO anchor_resid=$anch_resid (recipe: nearest real CA within 2.0 of fake CA 1)"
            }
            $asel delete
        } else { _bail anchor_sel $asel }
    }
}

# ---- 3. HIDER REPS: stamp_tier_codes BEFORE add_hider_reps (ordering
#         contract); read-back == `Tube` EXACTLY. ----
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    set pre_reps [molinfo $gm get numreps]
    # Stamp: code 1 = the 3 CA indices (user3 read-back ~1.0 numeric, P10).
    if {[catch {::biochemeleon::hiders::stamp_tier_codes $gm [dict create 1 $ca_idxs]} serr]} {
        _bail stamp_tier_codes $serr
    } else {
        if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
            set u3 [$s get user3]
            $s delete
            foreach u $u3 {
                if {![_feq $u 1.0]} { _bail user3_readback "exp=1.0 got=$u" }
            }
        } else { _bail user3_sel $s }
    }
    # Add the pair: bare `Tube` (0 or 2 params valid; the game uses bare).
    if {![catch {::biochemeleon::hiders::add_hider_reps $gm {{1 Tube}}} tr]} {
        set nreps [molinfo $gm get numreps]
        if {$nreps != $pre_reps + 2} {
            _bail rep_count "exp=[expr {$pre_reps + 2}] got=$nreps"
        }
        # Read-back via tier_reps + repindex (COMBINED-BRACES form; the
        # exact literal selections per the 17.1-08 contract).
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
                if {$st ne "Tube"} {
                    _bail ${rname}_style "exp=Tube got=$st"
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
    } else { _bail add_hider_reps $tr }
}

# ---- 4. RENDERS (probe rep LAST via _render_bits; baseline-zero first). ----
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    # 4a. Baseline-zero (harness proof): a null selection renders 0
    #     primitives of every kind -- the parser really counts the scene.
    if {![catch {_render_bits $gm Tube {index 999999} [file join [pwd] tube_base.dat]} bbits]} {
        lassign $bbits bs bc bst bstr
        if {$bs != 0 || $bc != 0 || $bst != 0 || $bstr != 0} {
            _bail baseline_zero "exp=0/0/0/0 got=$bs/$bc/$bst/$bstr"
        }
    } else { _bail render_base $bbits }

    # 4b. GAME-only exclusive (segid GAME, Tube, Element): the smooth CA
    #     spline covers the fake residues -- FCylinder >= 3 (research
    #     measured 6/residue; >= 3, not exact) AND TriStrip == 0 (Tube
    #     draws no mesh). STri is printed (evidence only).
    set game_bits [list -1 -1 -1 -1]
    if {![catch {_render_bits $gm Tube {segid GAME} [file join [pwd] tube_game.dat]} gb]} {
        lassign $gb gs gc gst gstr
        set game_bits $gb
        puts "TUBE_POS gameonly nsph=$gs ncyl=$gc nstri=$gst nstrip=$gstr"
        if {[catch {expr {double($gc) >= 3.0}} gok] || !$gok} {
            _bail gameonly_bits "exp>=3 FCylinder spline segments got=$gc"
        }
        if {$gstr != 0} {
            _bail gameonly_tristrip "exp=0 got=$gstr (Tube draws no mesh)"
        }
    } else { _bail render_gameonly $gb }
    # No salmon in any parsed Color of the GAME-only render (Element
    # coloring only -- the GAM-name Name-coloring trap is (1.0 0.6 0.6)).
    set gcols [_parse_colors [file join [pwd] tube_game.dat]]
    if {[llength $gcols] == 0} {
        _bail gameonly_colors "no Color triples parsed (render unreadable?)"
    } else {
        foreach c $gcols {
            if {[_cnear $c $salmon 0.01]} {
                _bail hider_salmon "SALMON leak (Name-coloring trap): $c"
            }
        }
    }

    # 4c. WINDOW PATH-INCLUSION renders (PRINTS/EVIDENCE ONLY -- the
    #     17.2-04 STRIDE-variance discovery: cross-molecule window counts
    #     are shift-variant with zero pathology, so NOTHING is asserted on
    #     them; the positive control is the bond scene-diff in 4d, and the
    #     GAME-only render in 4b already proves the fake is IN the spline).
    if {$anch_resid > 0} {
        set wlo [_wlo $anch_resid]
        set whi [expr {$anch_resid + 2}]
        set winsel "resid $wlo to $whi"
        # Spliced bare window (plan-literal selection: real resids only).
        if {![catch {_render_bits $gm Tube $winsel [file join [pwd] tube_win.dat]} sw]} {
            lassign $sw s1s s1c s1st s1str
            puts "TUBE_POS spliced_window={$winsel} nsph=$s1s ncyl=$s1c nstri=$s1st nstrip=$s1str"
        } else { _bail render_spliced_win $sw; set s1c -1 }
        # Fake-inclusive window (adds the fake CAs to the traced path).
        if {![catch {_render_bits $gm Tube "$winsel or segid GAME" [file join [pwd] tube_winfake.dat]} sw2]} {
            lassign $sw2 s2s s2c s2st s2str
            puts "TUBE_POS spliced_window_plus_fake nsph=$s2s ncyl=$s2c nstri=$s2st nstrip=$s2str"
        } else { _bail render_spliced_win_fake $sw2; set s2c -1 }
        # Unspliced control: the SAME frame-0 collapse pipeline as the
        # splice molecules (_load_demo_1f == the mutate pipeline minus
        # hiders) so the geometry comparison is like-for-like. Printed,
        # never asserted (STRIDE-variance).
        if {[catch {_load_demo_1f 1znf} mc]} {
            _bail load_control $mc
            set mc -1
        } else {
            if {![catch {_render_bits $mc Tube $winsel [file join [pwd] tube_ctrl.dat]} cw]} {
                lassign $cw c1s c1c c1st c1str
                puts "TUBE_POS control_window nsph=$c1s ncyl=$c1c nstri=$c1st nstrip=$c1str"
            } else { _bail render_ctrl_win $cw; set c1c -1 }
            # The control molecule is spent -- delete it so later renders
            # are never polluted (belt-and-suspenders with _render_bits
            # isolation).
            catch {mol delete $mc}
            set mc -2
        }
        puts "TUBE_POS window_evidence spliced=$s1c fake_incl=$s2c control=$c1c (evidence only -- STRIDE-variance; scene-diff below is the assertion)"
    }

    # 4d. POSITIVE CONTROL = the BOND SCENE-DIFF (ss-independent,
    #     17.1-08/17.2-04 pattern, floor-asserted): the scene reps render
    #     A = all vs B = not resname GAM; the FCylinder delta == the fakes'
    #     bond count (junction + intra-residue stubs, both-endpoints rule)
    #     >= 4 per fake atom. The hider pair reps are NULLED in BOTH renders
    #     (their own bits are proven by 4b; the delta must be attributable
    #     to the scene rep alone) and restored to their stored literals.
    set pi2 [molinfo $gm get numreps]
    mol addrep $gm
    mol modstyle $pi2 $gm Lines
    mol modcolor $pi2 $gm Element
    mol modselect $pi2 $gm {index 999999}
    # Null the hider pair reps (indices pre_reps..pre_reps+1) for A and B.
    if {$pre_reps >= 0} {
        for {set i $pre_reps} {$i < $pi2} {incr i} {
            mol modselect $i $gm {index 999999}
        }
    }
    set da_ok 0
    set db_ok 0
    set daerr ""
    set dberr ""
    if {![catch {render Tachyon [file join [pwd] tube_sceneA.dat]} daerr]} {
        set da_ok 1
    }
    # B selection: SCENE REPS ONLY (0..pre_reps-1) -- the hider pair reps
    # stay NULLED in B (a `not resname GAM` on a Tube pair rep would draw
    # the WHOLE molecule as a spline and inflate B; the splice smoke had no
    # pair reps, so its all-reps loop does not transfer).
    for {set i 0} {$i < $pre_reps && $i < $pi2} {incr i} {
        mol modselect $i $gm {not resname GAM}
    }
    if {![catch {render Tachyon [file join [pwd] tube_sceneB.dat]} dberr]} {
        set db_ok 1
    }
    # Restore: scene reps (0..pre_reps-1) -> all; pair reps -> literals.
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm all }
    if {$pre_reps >= 0 && [dict exists $::biochemeleon::hiders::tier_reps 1]} {
        lassign [dict get $::biochemeleon::hiders::tier_reps 1] hn fn hs2 fs2
        set hidx2 [mol repindex $gm $hn]
        if {$hidx2 >= 0} { catch {mol modselect $hidx2 $gm $hs2} }
        set fidx2 [mol repindex $gm $fn]
        if {$fidx2 >= 0} { catch {mol modselect $fidx2 $gm $fs2} }
    }
    catch {mol delrep $pi2 $gm}
    if {$da_ok && $db_ok} {
        lassign [_parse_bits [file join [pwd] tube_sceneA.dat]] as2 ac2 a2st a2sp
        lassign [_parse_bits [file join [pwd] tube_sceneB.dat]] bs2 bc2 b2st b2sp
        set bond_delta [expr {$ac2 - $bc2}]
        set floor [expr {4 * $exp_fake}]
        puts "TUBE_POS bond_scene_diff A=$ac2 B=$bc2 delta=$bond_delta floor=$floor"
        if {[catch {expr {double($bond_delta) >= double($floor)}} bd] || !$bd} {
            _bail positive_bond_diff "exp delta >= $floor (the fakes' bonds render) got=$bond_delta"
        }
    } else {
        _bail render_scene_diff "$daerr / $dberr"
    }
}

# ---- 5. FOUND-MARKING: mark_found_visual on CA 2; partition asserts. ----
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    # Pre-state: all three user2 flags <= 0.
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set pre_u2 [$s get user2]
        $s delete
        foreach u $pre_u2 {
            if {[catch {expr {double($u) <= 0.0}} z] || !$z} {
                _bail pre_user2 "exp<=0 got=$u"
            }
        }
    } else { _bail pre_user2_sel $s }
    # Mark CA 2 (the SECOND sentinel index -- the middle residue).
    set ca2 [lindex $ca_idxs 1]
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm $ca2} merr]} {
        _bail mark_found_visual $merr
    } else {
        # Post-state: CA 2 > 0; CA 1/3 still <= 0 (numeric -- P7).
        foreach {idx lo hi} [list [lindex $ca_idxs 0] 0 0] { break }
        set u2vals [list]
        if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
            set u2idx [$s get index]
            set u2vals [$s get user2]
            $s delete
        } else { _bail post_user2_sel $s }
        for {set i 0} {$i < [llength $u2idx]} {incr i} {
            set ii [lindex $u2idx $i]
            set uu [lindex $u2vals $i]
            if {$ii == $ca2} {
                if {[catch {expr {double($uu) > 0.0}} z] || !$z} {
                    _bail found_user2_$ii "exp>0 got=$uu"
                }
            } else {
                if {[catch {expr {double($uu) <= 0.0}} z] || !$z} {
                    _bail unfound_user2_$ii "exp<=0 got=$uu"
                }
            }
        }
        # Partition: found-selection (user2 > 0 and user3 1 conjunct)
        # num == 1; hidden variant num == 2.
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 > 0 and user3 1}} s]} {
            set nf [$s num]
            $s delete
            if {$nf != 1} { _bail found_partition "exp=1 got=$nf" }
        } else { _bail found_sel $s }
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} s]} {
            set nh [$s num]
            $s delete
            if {$nh != 2} { _bail hidden_partition "exp=2 got=$nh" }
        } else { _bail hidden_sel $s }
        # The pair reps must still carry their literal selections (the
        # mandatory re-assert inside mark_found_visual re-issued them).
        if {[dict exists $::biochemeleon::hiders::tier_reps 1]} {
            lassign [dict get $::biochemeleon::hiders::tier_reps 1] hn fn hs3 fs3
            set hidx3 [mol repindex $gm $hn]
            if {$hidx3 >= 0} {
                set sl3 ""
                catch {foreach sl3 [molinfo $gm get "{selection $hidx3}"] { break }}
                if {$sl3 ne $hs3} {
                    _bail post_found_hidden_sel "exp=$hs3 got=$sl3"
                }
            } else { _bail post_found_hidden_repindex $hn }
        }
    }
}

# ---- 6. RESTORE: mol delete gm; fresh demo reload -> 424 atoms. ----
catch {mol delete $gm}
set gm -2
if {[catch {_load_demo_1f 1znf} mr]} {
    _bail load_restore $mr
    set mr -1
} else {
    set rn [molinfo $mr get numatoms]
    if {$rn != 424} {
        _bail restored_atoms "exp=424 got=$rn (residue leak?)"
    }
}

# ---- 7. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
