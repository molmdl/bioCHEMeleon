# vmd/smoke/phase17_newcartoon_smoke.tcl
# Phase-17.2 (17.2-06) headless smoke: the NewCartoon tier end-to-end -- the
# mesh-rendering residue-splice consumer. Tier adaptation of the 17.2-04
# harness (vmd/smoke/phase17_splice_smoke.tcl: _bail/_feq/_pin/_dist/
# _parse_bits/_render_bits/_load_demo_1f/_ca_table/_wlo/_rec_atom_total are
# copied verbatim; only the tier style and the primitive expectation change).
#
# Proves, on demo 1znf (424 atoms), driven DIRECTLY through the real
# mutation+hiders bridges (dispatch is 17.2-09, not this smoke):
#   1. SPLICE: make_residue_hiders 3 (chained accumulation: need/occupied/
#      resid_start -- the lib's multi-call pattern for compact folds) ->
#      mutate -> 424+fake atoms; CA-only sentinel (exactly ONE beta<0 index
#      per hider, names CA, resids {9001 9002 9003}); GAM == derived fake
#      total; protein +fake; segid GAME on all fake atoms; BOTH peptide
#      junctions bonded per fake (scoped to the exact partner resids).
#   2. Fake CA `structure` letter: Option-A turn-tube. The plan pins "== T";
#      the settled 17.2-04 discovery is that the letter is ANCHOR-DEPENDENT
#      (STRIDE reads the displaced phi/psi: resid-5 anchors read T,
#      PRNG-chosen coil-region anchors read C) -- so this smoke asserts the
#      Option-A PROPERTY (T or C -- both render the smooth coil/turn tube;
#      FAIL on H/G/E/B/blank), prints the letters, and zero ssrecalc is
#      called anywhere (load-time STRIDE only).
#   3. HIDER REPS: stamp_tier_codes (code 1 = the 3 CA indices) ->
#      add_hider_reps {{1 NewCartoon}} -- the BARE style (0 args valid;
#      read-back `NewCartoon` EXACTLY, never a hand-typed variant) ->
#      numreps == pre_start + 2; read-back style/selection/color
#      string-compares (hidden Element + user2 < 1, found ColorID 7 +
#      user2 > 0; both user3 1 conjunct).
#   4. RENDERS (probe rep LAST; baseline-zero FIRST):
#      a. baseline-zero (harness proof): null selection -> 0 primitives.
#      b. GAME-only exclusive (`segid GAME`, NewCartoon, Element):
#         TriStrip >= 1 (the ribbon mesh covers the fake residue -- research
#         measured 14/residue) AND FCylinder == 0 (a T/C fake draws NO helix
#         cylinders; NewCartoon emits mesh only). No salmon (1.0 0.6 0.6)
#         in any parsed Color.
#      c. Window path-inclusion: anchor resid a via the settled recipe
#         (nearest real CA, 1.0 A band); probe `resid <a-2> to <a+2>` on the
#         spliced molecule vs a fresh single-frame control. PLAN CONFLICT
#         RESOLUTION (17.2-04 run-20 lesson, STRIDE-shift variance observed
#         22->6 with zero pathology): window counts are PRINTS/EVIDENCE ONLY
#         -- the asserted positive control is the BOND SCENE-DIFF (A=all vs
#         B=not resname GAM, Lines probe): FCylinder delta >= 4 per fake
#         atom (the fakes' junction + intra-residue bonds render). The
#         NewCartoon B-spline caveat (mesh need not pass exactly through
#         CA, UG node70) is recorded and non-blocking: path INCLUSION is
#         the assertion, not geometric exactness.
#   5. FOUND-MARKING: mark_found_visual on CA 2 -> user2 > 0; partition
#      re-splits (found 1 / hidden 2, user3 1 conjunct); the mandatory
#      re-evaluation re-assert repairs the harness's render-phase rep
#      clobber (read-back re-proven after).
#   6. RESTORE round-trip: mol delete gm; reload original -> 424 atoms.
#
# PLAN-PIN DERIVATIONS (documented, not hand-waved):
#   - GAM == 15 in the plan assumes 3 non-GLY anchors (5 atoms each); the
#     settled 17.2-04 lesson is that a GLY anchor yields a 4-atom residue --
#     the expected count is DERIVED from the records, never hardcoded.
#   - The window exceedance is printed as evidence (NC_WIN lines); the
#     asserted path-inclusion proof is the scene-diff + GAME-only TriStrip.
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and is
# recorded for a gap-closure plan -- never patched from a tier smoke.
#
# Harness discipline (inherited): sources the lib files in dependency order
# (setup_state, registry, rep_tiers, generators, game_logic, demos, backup,
# mutation, hiders, game; registry EXACTLY ONCE; mutation sources splice.tcl
# itself). -e'd by VMD -> [info script] is EMPTY -> [pwd] (VMD cwd = staging
# root). VMD does NOT propagate tcl exit codes -> parse BCHM_SMOKE_RESULT,
# never $?; VMD -e catches top-level errors and CONTINUES -> every step is
# catch-wrapped + _bail'd; the runner scans the FULL log for ERROR)/bad
# switch. Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is
# $sel delete'd. NEVER mol showrep (ignored in text mode). Token regexes are
# \m word-boundary so TriStrip can never false-match STri.

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (beta/user are FLOATS -- numeric only).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Frame pin for coordinate reads (1znf ships 2 models; the collapse loader
# makes every molecule single-frame -- the pin is belt-and-suspenders).
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

# Per-channel color proximity (eps 0.01 for the salmon check).
proc _cnear {c ref eps} {
    if {[llength $c] != 3 || [llength $ref] != 3} { return 0 }
    foreach a $c b $ref {
        if {[expr {abs(double($a) - double($b))}] > $eps} { return 0 }
    }
    return 1
}

# Parse a Tachyon .dat: \m/word-boundary primitive-token counts over the
# whole file + per-line Color capture (Directional_Light lines carry
# "Color 1 1 1" and are skipped -- not primitives). Returns
# {nsph ncyl nstri nstrip cols}; -1s signal an unreadable file (a missing
# file can never masquerade as an empty scene).
proc _parse_dat {path} {
    if {[catch {open $path r} fh]} {
        return [list -1 -1 -1 -1 [list]]
    }
    set dat [read $fh]
    close $fh
    set nsph [regexp -all -- {\mSphere\y} $dat]
    set ncyl [regexp -all -- {\mFCylinder\y} $dat]
    set nstri [regexp -all -- {\mSTri\y} $dat]
    set nstrip [regexp -all -- {\mTriStrip\y} $dat]
    set cols [list]
    foreach line [split $dat \n] {
        if {[string match "Directional_Light*" $line]} { continue }
        if {[regexp -- {Color\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)} \
                $line -> cr cg cb]} {
            lappend cols [list $cr $cg $cb]
        }
    }
    return [list $nsph $ncyl $nstri $nstrip $cols]
}

# THE reusable 17.2 render helper (tier smokes 05-08 copy this): add a probe
# rep LAST (highest index), style+select it, EMPTY every earlier rep
# (showrep is ignored in text mode), render Tachyon, restore the earlier
# reps to "all", delete the probe rep (highest index -- never renumbers),
# return the parsed counts. `axes location off` must have been called once
# before the first render. NOTE: the restore sets earlier reps to "all" --
# hider-pair reps with real selections are RE-ASSERTED later by
# mark_found_visual (the mandatory re-evaluation), which is exactly the
# plan's step order (renders 3, found-marking 4).
proc _render_bits {m style sel path} {
    # Isolate the scene: VMD renders EVERY DISPLAYED molecule -- any other
    # live molecule's reps would pollute the count.
    set others [list]
    foreach mm [molinfo list] {
        if {$mm != $m} { lappend others $mm }
    }
    foreach mm $others { catch {mol off $mm} }
    set pi [molinfo $m get numreps]
    mol addrep $m
    mol modstyle $pi $m $style
    mol modcolor $pi $m Element
    mol modselect $pi $m $sel
    for {set i 0} {$i < $pi} {incr i} {
        mol modselect $i $m {index 999999}
    }
    set rc [catch {render Tachyon $path} rerr]
    for {set i 0} {$i < $pi} {incr i} {
        mol modselect $i $m all
    }
    catch {mol delrep $pi $m}
    foreach mm $others { catch {mol on $mm} }
    if {$rc} { error "render Tachyon failed: $rerr" }
    return [_parse_dat $path]
}

# THE 17.2 harness loader: load a demo COLLAPSED TO A SINGLE FRAME (1znf
# ships 2 models; unpinned reads are frame-unstable). Collapse via a
# frame-0-pinned writepdb round-trip (the SAME pipeline mutate uses
# downstream) so every molecule in the smoke is single-frame.
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] nc_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
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

# A residue's N atom index.
proc _res_n_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name N"]]
    set ni [lindex [$s get index] 0]
    $s delete
    return $ni
}

# A residue's C atom index.
proc _res_c_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name C"]]
    set ci [lindex [$s get index] 0]
    $s delete
    return $ci
}

# The junction partner resids for an anchor residue: the C bonded to the
# anchor N (prev) and the N bonded to the anchor C (next). Scoping the
# junction checks to THESE resids is the only exact partner test.
proc _junction_partners {m ch rid} {
    set ni [_res_n_index $m $ch $rid]
    set ci [_res_c_index $m $ch $rid]
    set prev_res -1
    set next_res -1
    if {$ni >= 0} {
        set s [_pin [atomselect $m "name C and within 1.7 of index $ni"]]
        set prev_res [lindex [$s get resid] 0]
        $s delete
    }
    if {$ci >= 0} {
        set s [_pin [atomselect $m "name N and within 1.7 of index $ci"]]
        set next_res [lindex [$s get resid] 0]
        $s delete
    }
    return [list $prev_res $next_res]
}

# Window low bound: clamp to 0 (`resid -1 ...` is a VMD selection SYNTAX
# ERROR -- the render then captures the un-emptied scene, garbage counts).
proc _wlo {a} {
    set w [expr {$a - 2}]
    if {$w < 0} { set w 0 }
    return $w
}

# Total fake-atom count across records (a GLY anchor yields a 4-atom
# residue -- NEVER hardcode 5 per residue; the plan's "15" is the 3x5
# non-GLY special case).
proc _rec_atom_total {recs} {
    set t 0
    foreach r $recs { set t [expr {$t + [llength [lindex $r 2]]}] }
    return $t
}

# Defensive init so a failed earlier step never masks as a substitution error.
set m0 -1
set gm -1
set mc -1
set mr -1
set recs [list]
set n0 -1
set real_protein -1
set beta_idxs [list]
set anchor_list [list]
set partner_list [list]
set exp_fake 0
set marked_idx -1
set anch_resid -1
set anch_chain ""
set pre_start -1
set tier_reps [dict create]
set hidx -1
set fidx -1

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

# ---- 1. SPLICE: load 1znf, make 3 residue hiders, mutate. ----
if {[catch {_load_demo_1f 1znf} m0]} {
    _bail load_demo $m0
    set m0 -1
} else {
    set n0 [molinfo $m0 get numatoms]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    if {[catch {atomselect $m0 protein} psel]} {
        _bail protein_sel $psel
    } else {
        set real_protein [$psel num]
        $psel delete
    }
    # Chained accumulation (the lib's multi-call pattern: need + occupied +
    # resid_start) -- compact 1znf rejects far-separated anchors often, and
    # ONE call for 3 under-generates; accumulate batches until 3 records.
    set occ [list]
    set recs [list]
    for {set att 0} {$att < 8 && [llength $recs] < 3} {incr att} {
        set need [expr {3 - [llength $recs]}]
        set start_r [expr {9001 + [llength $recs]}]
        if {[catch {::biochemeleon::mutation::make_residue_hiders \
                $m0 $need $occ $start_r} batch]} {
            _bail make_residue_hiders $batch
            break
        }
        foreach r $batch {
            lappend recs $r
            # Occupancy = the fake CA position (1.0 A from its anchor -- the
            # clearance intent: never re-pick the same/adjacent anchor).
            foreach a [lindex $r 2] {
                if {[lindex $a 0] eq "CA"} {
                    lassign [lrange $a 2 4] fx fy fz
                    lappend occ [list $fx $fy $fz]
                }
            }
        }
    }
}
if {[llength $recs] != 3} {
    _bail rec_count "exp=3 got=[llength $recs]"
} else {
    # Per-record shape + anchor + partner derivation (anchors/partners MUST
    # be derived BEFORE mutate -- mutate DELETES m0).
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
        if {[llength $atoms] < 4} {
            _bail ${tag}_atom_count "exp>=4 got=[llength $atoms]"
            incr k
            continue
        }
        set names [list]
        foreach a $atoms { lappend names [lindex $a 0] }
        if {[lindex $names 0] ne "N" || [lindex $names 1] ne "CA"} {
            _bail ${tag}_order "exp=N-first/CA-second got=$names"
        }
        # Anchor derivation: nearest real CA to the fake CA (settled: exactly
        # ~1.0 A away; every other real CA is >= ~2.8 A out).
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
    # MUTATE (deletes m0, loads the combined PDB).
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
    # CA-only sentinel: exactly ONE beta<0 index per hider (3 total, CA only).
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set beta_idxs [$s get index]
        set nb [$s num]
        set bnm [$s get name]
        set brd [$s get resid]
        $s delete
        if {$nb != 3} { _bail sentinel_count "exp=3 got=$nb" }
        foreach nm $bnm {
            if {$nm ne "CA"} { _bail sentinel_name "exp=CA-only got=$nm" }
        }
        if {$brd ne [list 9001 9002 9003]} {
            _bail sentinel_resids "exp={9001 9002 9003} got=$brd"
        }
        # Fake CA structure letters: Option-A turn-tube PROPERTY (T or C;
        # both render the smooth coil/turn tube). The plan pins "== T" but
        # the settled discovery is anchor-dependence -- print the letters,
        # FAIL only on a non-Option-A letter. NO ssrecalc is called anywhere
        # in this flow (load-time STRIDE only, by construction).
        if {![catch {atomselect $gm {resname GAM and name CA}} cs]} {
            set structs [$cs get structure]
            $cs delete
            puts "NC_STRUCT fake_CA_structure=$structs (Option-A tube: T/C ok, ssrecalc=never)"
            foreach st $structs {
                if {$st ne "T" && $st ne "C"} {
                    _bail ca_structure "exp T or C (Option-A turn/coil tube) got=$st"
                }
            }
        } else { _bail ca_sel $cs }
    } else { _bail sentinel_sel $s }
    # GAM total == DERIVED fake count (plan's 15 = the 3x5 non-GLY case).
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set ngam [$s num]
        set gseg [$s get segid]
        $s delete
        puts "NC_GAM gam_count=$ngam derived_fake_total=$exp_fake (plan literal 15 = 3x5 non-GLY)"
        if {$ngam != $exp_fake} { _bail gam_count "exp=$exp_fake got=$ngam" }
        foreach sg $gseg {
            if {$sg ne "GAME"} { _bail fake_segid "exp=GAME got=$sg" }
        }
    } else { _bail gam_sel $s }
    if {![catch {atomselect $gm protein} s]} {
        set nprot [$s num]
        $s delete
        if {$nprot != $real_protein + $exp_fake} {
            _bail protein_count "exp=$real_protein+$exp_fake=[expr {$real_protein + $exp_fake}] got=$nprot"
        }
    } else { _bail protein_sel2 $s }
    # Junction law per fake resid: its N has a bonded C (prev partner resid)
    # and its C has a bonded N (next partner resid) within the C-N bond
    # cutoff (0.6*(1.70+1.55)=1.95; 1.9 so ONLY bonded pairs can match).
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set gidx [$s get index]
        set gres [$s get resid]
        set gnam [$s get name]
        $s delete
        set fi 0
        foreach rr [list 9001 9002 9003] {
            set n_idx -1
            set c_idx -1
            for {set i 0} {$i < [llength $gidx]} {incr i} {
                if {[lindex $gres $i] != $rr} { continue }
                if {[lindex $gnam $i] eq "N"} { set n_idx [lindex $gidx $i] }
                if {[lindex $gnam $i] eq "C"} { set c_idx [lindex $gidx $i] }
            }
            if {$n_idx < 0 || $c_idx < 0} {
                _bail junction_atoms_$rr "N/C indices not found"
                incr fi
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
            incr fi
        }
    } else { _bail gam_walk_sel $s }
}

# ---- 2. HIDER REPS: stamp code 1 = the 3 CA indices; the BARE NewCartoon. ----
if {$gm >= 0 && [llength $beta_idxs] == 3} {
    set pre_start [molinfo $gm get numreps]
    if {[catch {::biochemeleon::hiders::stamp_tier_codes $gm \
            [dict create 1 $beta_idxs]} terr]} {
        _bail stamp_tier_codes $terr
    }
    if {[catch {::biochemeleon::hiders::add_hider_reps $gm {{1 NewCartoon}}} tier_reps]} {
        _bail add_hider_reps $tier_reps
        set tier_reps [dict create]
    }
    set nreps [molinfo $gm get numreps]
    if {$nreps != $pre_start + 2} {
        _bail rep_count "exp=$pre_start+2 got=$nreps"
    }
    # Read-back (combined-braces single molinfo; Pitfall 2). add_hider_reps
    # validates internally -- this independent read-back is the plan's gate:
    # style == `NewCartoon` EXACTLY (never a hand-typed variant).
    if {[dict size $tier_reps] == 1} {
        lassign [dict get $tier_reps 1] hname fname hsel fsel
        set hidx [mol repindex $gm $hname]
        set fidx [mol repindex $gm $fname]
        foreach {rname ridx rexp_style rexp_col rexp_sel} [list \
            hidden $hidx "NewCartoon" "Element" $hsel \
            found  $fidx "NewCartoon" "ColorID 7" $fsel] {
            if {$ridx < 0 || $ridx >= [molinfo $gm get numreps]} {
                _bail repidx_$rname "$rname repindex=$ridx"
                continue
            }
            set rstyle ""; set rsel ""; set rcol ""; set rmat ""
            foreach {rstyle rsel rcol rmat} [molinfo $gm get \
                "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }
            if {$rstyle ne $rexp_style} {
                _bail rep_style_$rname "exp='$rexp_style' got='$rstyle'"
            }
            if {$rcol ne $rexp_col} {
                _bail rep_color_$rname "exp='$rexp_col' got='$rcol'"
            }
            if {$rsel ne $rexp_sel} {
                _bail rep_sel_$rname "exp='$rexp_sel' got='$rsel'"
            }
        }
    }
}

# ---- 3. RENDERS (probe rep LAST; baseline-zero FIRST). ----
if {$gm >= 0 && [dict size $tier_reps] == 1 && [llength $beta_idxs] == 3} {
    # 3a. Baseline-zero (harness proof): null selection -> 0 of every kind.
    if {![catch {_render_bits $gm NewCartoon {index 999999} \
            [file join [pwd] nc_base.dat]} bbits]} {
        lassign $bbits bs bc bst bstr bcols
        puts "NC_RENDER baseline_zero nsph=$bs ncyl=$bc nstri=$bst nstrip=$bstr"
        if {$bs != 0 || $bc != 0 || $bst != 0 || $bstr != 0} {
            _bail baseline_zero "exp=0/0/0/0 got=$bs/$bc/$bst/$bstr"
        }
    } else { _bail render_base $bbits }
    # 3b. GAME-only exclusive: TriStrip >= 1 (mesh covers the fake residue;
    #     research measured 14/residue) AND FCylinder == 0 (a T/C fake draws
    #     NO helix cylinders; NewCartoon is mesh-only). No salmon.
    set gtri -1
    set gcyl -1
    if {![catch {_render_bits $gm NewCartoon {segid GAME} \
            [file join [pwd] nc_game.dat]} gbits]} {
        lassign $gbits gs gc gst gstr gcols
        set gtri $gstr
        set gcyl $gc
        puts "NC_RENDER gameonly nsph=$gs ncyl=$gc nstri=$gst nstrip=$gstr (exp TriStrip>=1, FCyl==0)"
        if {$gstr < 1} {
            _bail gameonly_tristrip "exp>=1 TriStrip got=$gstr (mesh must cover the fake residue)"
        }
        if {$gc != 0} {
            _bail gameonly_fcyl "exp=0 FCylinder (T/C fake draws no helix cylinders) got=$gc"
        }
        foreach c $gcols {
            if {[_cnear $c {1.0 0.6 0.6} 0.01]} {
                _bail gameonly_salmon "SALMON leak (Name-coloring trap): $c"
            }
        }
    } else { _bail render_gameonly $gbits }
    # 3c. Window path-inclusion: anchor of record 1 via the settled recipe
    #     (nearest real CA at 1.0 A == the anchor we derived on m0). Window
    #     counts are PRINTS/EVIDENCE (STRIDE-shift variance); the asserted
    #     positive control is the bond scene-diff below.
    set wtri -1
    set wtot -1
    set ctritot -1
    lassign [lindex $anchor_list 0] anch_chain anch_resid
    set fakeca1 [lindex $beta_idxs 0]
    if {$anch_resid > 0} {
        # Recipe cross-check on the GAME molecule (parenthesized `within` --
        # VMD swallows trailing expressions).
        if {![catch {atomselect $gm "name CA and (within 2.0 of index $fakeca1) and not index $fakeca1"} asel]} {
            $asel frame 0
            set na [$asel num]
            if {$na != 1} {
                _bail anchor_lookup "exp=1 nearest real CA got=$na (fakeca1=$fakeca1)"
            } else {
                set vres [lindex [$asel get resid] 0]
                set vchn [lindex [$asel get chain] 0]
                if {$vres != $anch_resid || $vchn ne $anch_chain} {
                    _bail anchor_mismatch "exp=$anch_chain:$anch_resid got=$vchn:$vres"
                }
            }
            $asel delete
        } else { _bail anchor_sel $asel }
        set wlo [_wlo $anch_resid]
        set whi [expr {$anch_resid + 2}]
        set winsel "resid $wlo to $whi"
        if {![catch {_render_bits $gm NewCartoon $winsel \
                [file join [pwd] nc_win.dat]} wbits]} {
            lassign $wbits ws wc wst wstr wcols
            set wtri $wstr
            set wtot [expr {$wstr + $wc}]
            puts "NC_WIN spliced_window={$winsel} nsph=$ws ncyl=$wc nstri=$wst nstrip=$wstr total(Tri+FCl)=$wtot"
            foreach c $wcols {
                if {[_cnear $c {1.0 0.6 0.6} 0.01]} {
                    _bail window_salmon "SALMON leak: $c"
                }
            }
        } else { _bail render_spliced_win $wbits }
        # Unspliced control: the SAME single-frame collapse pipeline
        # (_load_demo_1f == the mutate pipeline minus hiders -- a raw
        # load_demo renders the LAST NMR model, different geometry).
        if {[catch {_load_demo_1f 1znf} mc]} {
            _bail load_control $mc
            set mc -1
        } else {
            if {![catch {_render_bits $mc NewCartoon $winsel \
                    [file join [pwd] nc_ctrl.dat]} cw]} {
                lassign $cw cs2 cc cst2 cstr2 ccols
                set ctritot [expr {$cstr2 + $cc}]
                puts "NC_WIN control_window={$winsel} nsph=$cs2 ncyl=$cc nstri=$cst2 nstrip=$cstr2 total(Tri+FCl)=$ctritot"
            } else { _bail render_ctrl_win $cw }
            # The control molecule is spent -- delete it so later renders are
            # never polluted (belt-and-suspenders with _render_bits isolation).
            catch {mol delete $mc}
            set mc -2
        }
        if {$wtot > $ctritot} {
            puts "NC_WIN delta: spliced $wtot > control $ctritot (fake IN the traced path -- evidence)"
        } else {
            puts "NC_WIN delta: spliced $wtot <= control $ctritot (STRIDE-shift variance -- not asserted; scene-diff is the proof)"
        }
    }
    # 3d. BOND SCENE-DIFF (the asserted positive control; 17.1-08 technique,
    #     ss-independent): probe rep = Lines; A = everything vs B = not
    #     resname GAM; the FCylinder delta == the fakes' rendered bond count
    #     (junction + intra-residue stubs, both-endpoints rule) >= 4 per
    #     fake atom. Hider reps are emptied during the renders (harness
    #     restore-to-all clobber) and RE-ASSERTED by mark_found_visual in
    #     step 4 -- the plan's step order makes the repair exact.
    set exp_fake_n [llength $beta_idxs]
    set floor [expr {4 * $exp_fake}]
    set pi2 [molinfo $gm get numreps]
    mol addrep $gm
    mol modstyle $pi2 $gm Lines
    mol modcolor $pi2 $gm Element
    mol modselect $pi2 $gm {index 999999}
    set da_ok 0
    set db_ok 0
    set daerr ""
    set dberr ""
    if {![catch {render Tachyon [file join [pwd] nc_sceneA.dat]} daerr]} {
        set da_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm {not resname GAM} }
    if {![catch {render Tachyon [file join [pwd] nc_sceneB.dat]} dberr]} {
        set db_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm all }
    catch {mol delrep $pi2 $gm}
    if {$da_ok && $db_ok} {
        lassign [_parse_dat [file join [pwd] nc_sceneA.dat]] as2 ac2 a2st a2sp acols
        lassign [_parse_dat [file join [pwd] nc_sceneB.dat]] bs2 bc2 b2st b2sp bcols
        set bond_delta [expr {$ac2 - $bc2}]
        puts "NC_SCENE_DIFF A=$ac2 B=$bc2 delta=$bond_delta floor=$floor"
        if {[catch {expr {double($bond_delta) >= double($floor)}} bd] || !$bd} {
            _bail positive_bond_diff "exp delta >= $floor (the fakes' bonds render) got=$bond_delta"
        }
        foreach c $acols {
            if {[_cnear $c {1.0 0.6 0.6} 0.01]} {
                _bail scene_salmon "SALMON leak: $c"
            }
        }
    } else {
        _bail render_scene_diff "$daerr / $dberr"
    }
}

# ---- 4. FOUND-MARKING: mark CA 2; partition re-splits; re-assert repair. ----
if {$gm >= 0 && [dict size $tier_reps] == 1 && [llength $beta_idxs] == 3} {
    set marked_idx [lindex $beta_idxs 1]
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm $marked_idx} merr]} {
        _bail mark_found_visual $merr
    } else {
        # user2 flag on the marked index (FLOAT read-back -- numeric only).
        if {![catch {atomselect $gm "index $marked_idx"} si]} {
            set u2 [lindex [$si get user2] 0]
            $si delete
            if {[catch {expr {double($u2) > 0.0}} uok] || !$uok} {
                _bail found_user2 "exp>0 got=$u2"
            }
        } else { _bail found_sel $si }
        # Partition: found 1 / hidden 2 (user3 1 conjunct).
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 > 0 and user3 1}} fs]} {
            set nf [$fs num]
            $fs delete
            if {$nf != 1} { _bail found_partition "exp=1 found got=$nf" }
        } else { _bail found_part_sel $fs }
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} hs]} {
            set nh [$hs num]
            $hs delete
            if {$nh != 2} { _bail hidden_partition "exp=2 hidden got=$nh" }
        } else { _bail hidden_part_sel $hs }
        # The mandatory re-assert repaired the harness's render-phase
        # clobber: both reps read back their literal selections + styles.
        lassign [dict get $tier_reps 1] hname fname hsel fsel
        set hidx2 [mol repindex $gm $hname]
        set fidx2 [mol repindex $gm $fname]
        foreach {rname ridx rexp_sel} [list hidden $hidx2 $hsel found $fidx2 $fsel] {
            set rstyle ""; set rsel ""; set rcol ""; set rmat ""
            foreach {rstyle rsel rcol rmat} [molinfo $gm get \
                "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }
            if {$rstyle ne "NewCartoon"} {
                _bail repaired_style_$rname "exp='NewCartoon' got='$rstyle'"
            }
            if {$rsel ne $rexp_sel} {
                _bail repaired_sel_$rname "exp='$rexp_sel' got='$rsel'"
            }
        }
    }
}

# ---- 5. RESTORE round-trip: mol delete gm; reload original -> 424 atoms. ----
if {$gm >= 0} {
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
        catch {mol delete $mr}
        set mr -2
    }
}

# ---- 6. Report. VMD does NOT propagate exit codes -- use a marker line. ----
set nfail [llength $failures]
if {$nfail == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
exit
