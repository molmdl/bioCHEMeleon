# vmd/smoke/phase17_trace_smoke.tcl
# Phase-17.2 (17.2-07) headless smoke: the TRACE tier end-to-end through the
# real 17.2-04 splice flow (mutation::make_residue_hiders + mutate + hiders::
# stamp_tier_codes + add_hider_reps, driven DIRECTLY -- the dispatch is
# 17.2-09). Tier adaptation of vmd/smoke/phase17_splice_smoke.tcl (the 17.2
# harness origin): its render-diff helpers (_parse_bits/_render_bits/_pin/
# _dist), its collapse loader (_load_demo_1f), and its log-scan/marker
# discipline are reused verbatim; only the tier style (Trace) and the
# primitive expectation change.
#
# ============================================================================
# THE FAMILY'S SS-INDEPENDENT CONTROL (research sec 5 -- NO sidestep): Trace
# is a SIBLING CONSUMER of the SAME residue splice as Cartoon/NewCartoon/Tube
# (rep_tiers TIER_KINDS "residue"; ONE make_residue_hiders call serves all
# four). Trace never consults `structure` (UG node65): the fake CA's
# load-time STRIDE value is RECORDED below but NO ss assertion is part of the
# render proof -- every render assertion is purely geometric.
# ============================================================================
#
# THE INVERTED RENDER SIGNATURE (the both-endpoints rule -- 17.1-RESEARCH
# viability sec 3 pinned trace_gam = 0): a Trace CA->CA segment is drawn only
# when BOTH endpoint CAs are in the rep selection. A hiders-only render over
# ONE fake residue therefore has ZERO primitives -- the fake CA has no
# CA->CA segment entirely inside the GAME selection (its trace neighbors are
# the real anchor-adjacent CAs; the other fake CAs are >= 5.0 A away, far
# beyond a CA-CA segment). Unlike the Cartoon/Tube >= 1-bit cases, 0 bits is
# here the POSITIVE assertion of the rule:
#   a. GAME-only Trace render == 0 FCylinder AND 0 Sphere (Trace draws no
#      dots) -- the hider is INVISIBLE to a GAME-only viewer of its own tier.
#   b. ... while the fake CA IS in the traced path: the anchor-window render
#      (resid a-2 to a+2, Trace) CHANGES vs the unspliced control -- the
#      trace builder REROUTES through the fake CA (probe6 pinned a spliced
#      window ABOVE its control; the 17.2-07 runs observed the count DELTA
#      in the other direction: 6 vs 8). The hider is IN the path yet draws
#      no GAME-only geometry.
#   c. THE asserted in-path proof: the 17.2-04 BOND SCENE-DIFF (Lines scene
#      rep, A=all vs B=not resname GAM) with the proven floor
#      4 * n_fake_atoms (junction + intra-residue stubs, both-endpoints).
#      Window render counts are PRINTS/EVIDENCE ONLY -- DISCOVERY-BRIEF:
#      window render counts are STRIDE-shift-variant (observed 22->6, zero
#      pathology; 17.2-07 observed 6-vs-8, the same variance class), so the
#      plan-pinned `spliced > control` assert is DEMOTED to prints and the
#      scene-diff + junction-bond law carry the proof (documented in
#      17.2-07-SUMMARY).
#
# Proves, on demo 1znf (424 atoms), 3 residue hiders driven directly:
#   1. SPLICE: make_residue_hiders 3 -> 3 records (real chains, resids
#      {9001 9002 9003}, N-first/CA-second, >= 4 atoms each, fake CA exactly
#      ~1.0 A from its anchor); mutate -> 424 + n_fake atoms;
#      `resname GAM and beta < 0` num == 3 (CA-only sentinel, resids
#      {9001 9002 9003}); resname GAM == n_fake (15 for non-GLY anchors);
#      segid GAME on all fakes; fake CA structure RECORDED (load-time
#      STRIDE, T or C -- NOT part of the render proof); BOTH junctions
#      bonded per fake residue (fake N -> bonded C in prev resid, fake C ->
#      bonded N in next resid).
#   2. HIDER REPS: stamp_tier_codes (code 1 = the 3 fake CA indices) ->
#      add_hider_reps {{1 Trace}} -> numreps == pre_start + 2; read-back
#      style == `Trace` EXACTLY (bare 0-arg tier form), hidden pair Element /
#      found pair ColorID 7, selections `resname GAM and beta < 0 and
#      user2 < 1 and user3 1` (+ the user2 > 0 found variant); a real atom
#      keeps user3 == 0.0 (P6).
#   3. TACHYON RENDERS (probe rep added LAST, deleted after; baseline-zero
#      first; every OTHER rep emptied by modselect -- mol showrep is IGNORED
#      in text mode, probe F6; `axes location off` first; all other
#      molecules turned off for the render):
#      a. baseline-zero: selection `index 999999` -> 0/0/0/0 (harness proof).
#      b. GAME-only exclusive (`segid GAME`, Trace, Element): 0 FCylinder
#         AND 0 Sphere -- the both-endpoints signature (see above).
#      c. anchor-window path-inclusion: `resid <a-2> to <a+2>` Trace on the
#         spliced molecule vs the SAME window on a fresh-original control
#         (loaded through the IDENTICAL frame-0 collapse pipeline) ->
#         counts PRINTED as evidence (STRIDE-shift-variant -- no sign
#         assertion; discovery brief).
#      d. bond scene-diff (Lines scene rep A=all vs B=not resname GAM):
#         delta >= 4 * n_fake (the fakes' bonds render -- in-path proof).
#      e. NO salmon (1.0 0.6 0.6 -- the GAM-name Name-coloring trap) in ANY
#         parsed Color of ANY render.
#   4. FOUND-MARKING: mark_found_visual on fake CA 3 -> user2 > 0; found
#      selection num 1 / hidden selection num 2 (user3 1 conjunct). The
#      mark's mandatory modselect re-assert also RESTORES the pair
#      selections the render phase emptied (unchanged-string contract).
#   5. CLEANUP/RESTORE: mol delete gm; reload the original (same collapse
#      pipeline) -> 424 atoms; marker + exit.
#
# THIS SMOKE EDITS NO LIB FILES: a lib defect surfaces as a FAIL here and is
# recorded for a gap-closure plan -- never patched from a tier smoke
# (wave-disjointness).
#
# Sources the lib files in dependency order (mirrors the entry, NOT the entry
# itself): setup_state, registry, rep_tiers, generators, game_logic, demos,
# backup, mutation, hiders, game. registry is sourced EXACTLY ONCE. mutation
# sources splice.tcl itself (pure layer).
#
# -e'd by VMD -> [info script] is EMPTY (Phase 13 Pitfall 3) -> use [pwd]
# (VMD cwd = staging root). VMD does NOT propagate tcl exit codes (Pitfall 4)
# -> parse the BCHM_SMOKE_RESULT marker, NEVER $?; VMD -e catches top-level
# errors and CONTINUES (false-PASS risk) -> every step is catch-wrapped +
# _bail'd, and the runner scans the FULL log for ERROR) / bad switch lines.
#
# Tcl 8.5 only (no 8.6 idioms; brace all expr). Every atomselect is $sel
# delete'd (a dangling selection on a deleted molecule returns STALE data
# silently). NEVER mol showrep (ignored in text mode). VMD `within` swallows
# trailing expressions -> ALWAYS parenthesize: `(within D of X) and not Y`.

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

# Per-channel color proximity (eps 0.01).
proc _cnear {c ref eps} {
    if {[llength $c] != 3 || [llength $ref] != 3} { return 0 }
    foreach a $c b $ref {
        if {[expr {abs(double($a) - double($b))}] > $eps} { return 0 }
    }
    return 1
}

# Salmon detector: 1 if ANY parsed color is salmon (the Name-coloring leak).
proc _has_salmon {cols salmon} {
    foreach c $cols {
        if {[_cnear $c $salmon 0.01]} { return 1 }
    }
    return 0
}

# Frame pin for coordinate reads on multi-model demos (1znf ships 2 models;
# unpinned reads are frame-unstable). The lib pins frame 0 everywhere; the
# smoke reads frame 0 to match.
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

# Parse a Tachyon .dat: line-based primitive counting (research probe_e
# pattern; one "<Token>" header line per primitive; the two
# "Directional_Light ... Color 1 1 1" header lines are FILTERED -- a naive
# whole-file Color regex counts the lights) + per-primitive Color extraction
# from the "Phong Plastic ... Color R G B TexFunc 0" line. Line-prefix
# matching cannot cross-match STri/TriStrip (disjoint prefixes).
# Returns {nsph ncyl nstri nstrip cols}; -1s signal an unreadable file (a
# missing file can never masquerade as an empty scene).
proc _parse_bits {path} {
    set nsph -1
    set ncyl -1
    set nstri -1
    set nstrip -1
    set cols [list]
    if {[catch {open $path r} fh]} {
        return [list $nsph $ncyl $nstri $nstrip $cols]
    }
    set nsph 0
    set ncyl 0
    set nstri 0
    set nstrip 0
    set dat [read $fh]
    close $fh
    foreach line [split $dat \n] {
        if {[string match "Sphere*" $line]} { incr nsph; continue }
        if {[string match "FCylinder*" $line]} { incr ncyl; continue }
        if {[string match "TriStrip*" $line]} { incr nstrip; continue }
        if {[string match "STri*" $line]} { incr nstri; continue }
        if {[string match "Directional_Light*" $line]} { continue }
        if {[regexp -- {Color\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)\s+(-?[0-9.eE+-]+)} $line -> cr cg cb]} {
            lappend cols [list $cr $cg $cb]
        }
    }
    return [list $nsph $ncyl $nstri $nstrip $cols]
}

# THE reusable 17.2 render helper (copied from phase17_splice_smoke.tcl):
# add a probe rep LAST (highest index), style+select it, EMPTY every earlier
# rep (showrep is ignored in text mode), render Tachyon, restore the earlier
# reps to "all", delete the probe rep (highest index -- never renumbers),
# return the parsed counts {nsph ncyl nstri nstrip cols}. `axes location
# off` must have been called once before the first render. NOTE: the restore
# sets earlier reps to "all" -- pair-rep selections emptied this way are
# re-asserted from the stored literals by mark_found_visual (step 4) and
# directly after the scene-diff (step 3d).
proc _render_bits {m style sel path} {
    # Isolate the scene: VMD renders EVERY DISPLAYED molecule -- any other
    # live molecule's reps would pollute the count (17.2-04: a still-alive
    # game molecule added ~823 phantom FCylinders). Turn all OTHER molecules
    # off for the render, restore after.
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
    return [_parse_bits $path]
}

# THE 17.2 harness loader (copied from phase17_splice_smoke.tcl): load a demo
# COLLAPSED TO A SINGLE FRAME. 1znf ships 2 models; VMD lands on the last
# frame and UNPINNED coordinate reads are racy on multi-frame molecules.
# Collapse via a frame-0-pinned writepdb round-trip (the SAME pipeline mutate
# uses downstream) so every molecule in the smoke is single-frame and every
# read/write is deterministic frame-0 geometry.
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] trace_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

# A residue's C atom index (for the next-N spatial query).
proc _res_c_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name C"]]
    set ci [lindex [$s get index] 0]
    $s delete
    return $ci
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
set m4 -1
set recs [list]
set n0 -1
set real_protein -1
set catab [list]
set anchor_list [list]
set partner_list [list]
set ca_idxs [list]
set exp_fake 0
set anch_resid -1
set anch_chain ""
set pre_reps -1
set winsel ""
set s1c -1
set c1c -1

# SALMON (1.0 0.6 0.6) = Name-coloring leak on GAM-named atoms. Must NEVER
# appear in any render of this smoke (hiders are anchor-named + every rep
# here uses Element coloring).
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

# ---- 1. SPLICE: load 1znf, make 3 residue hiders, assert the records. ----
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
    set catab [_ca_table $m0]
    # Retry loop: 1znf is a COMPACT fold -- the greedy 5.0 A anchor
    # separation rejects draws often (under-generation is tolerated lib
    # behavior, vmdcon-warned); the smoke needs 3 records, so re-draw until 3
    # (max 8 attempts).
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
if {[llength $recs] != 3} {
    _bail rec_count "exp=3 got=[llength $recs]"
} else {
    # Records carry the FAKE resid (9001+k); the ANCHOR residue is derived
    # geometrically: the nearest real CA to the fake CA sits exactly 1.0 A
    # away (rigid translation). NOTE: chain-blank is a real defect (the chain
    # id is fragment identity); chain "G" is NOT checked -- Pitfall C8 was
    # FALSIFIED (VMD distance-bonding ignores chain ids).
    set exp_fake [_rec_atom_total $recs]
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
        foreach bad {H OXT} {
            if {[lsearch -exact $names $bad] >= 0} {
                _bail ${tag}_atom_set "unexpected atom $bad"
            }
        }
        if {[lindex $names 0] ne "N" || [lindex $names 1] ne "CA"} {
            _bail ${tag}_order "exp=N-first/CA-second got=$names"
        }
        # Derive the anchor: nearest real CA to the fake CA (catab is from
        # the ORIGINAL frame-0 collapse; the fake CA coords come from the
        # record -- same frame-0 geometry).
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

# ---- 1b. ROUND: mutate with the residue records; assert the molecule. ----
if {$m0 >= 0 && [llength $recs] == 3} {
    if {[catch {::biochemeleon::mutation::mutate $m0 [list] $recs} gm]} {
        _bail mutate $gm
        set gm -1
    }
}
if {$gm >= 0} {
    set exp_total [expr {424 + $exp_fake}]
    set n1 [molinfo $gm get numatoms]
    # Non-GLY anchors give exp_fake == 15 (plan reference 439); a GLY anchor
    # yields 14 -- the count is DERIVED from the records, never hardcoded.
    puts "TRACE_SPLICE atoms=$n1 expected=$exp_total (plan-ref 439; fakes=$exp_fake)"
    if {$n1 != $exp_total} { _bail game_atoms "exp=$exp_total got=$n1" }
    # CA-only sentinel: exactly ONE index per hider, names CA, resids
    # {9001 9002 9003}, in file order == record order.
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set ca_idxs [$s get index]
        set cads [$s get resid]
        set nb [$s num]
        $s delete
        if {$nb != 3} { _bail sentinel_count "exp=3 got=$nb" }
        if {$cads ne [list 9001 9002 9003]} {
            _bail ca_resids "exp={9001 9002 9003} got=$cads"
        }
        foreach i $ca_idxs {
            if {![catch {atomselect $gm "index $i"} si]} {
                set nm [lindex [$si get name] 0]
                if {$nm ne "CA"} { _bail sentinel_name_$i "exp=CA got=$nm" }
                $si delete
            } else { _bail sentinel_sel_$i $si }
        }
        # Cross-check fetch_hider_indices (the registry-facing key list).
        if {![catch {::biochemeleon::mutation::fetch_hider_indices $gm} hidx]} {
            if {$hidx ne $ca_idxs} {
                _bail fetch_idx "exp=$ca_idxs got=$hidx"
            }
        } else { _bail fetch_idx_sel $hidx }
    } else { _bail sentinel_sel $s }
    # GAM total == the records' fake-atom count (15 for non-GLY); segid GAME
    # on ALL fake atoms; protein grew by the same count.
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set ngam [$s num]
        set gseg [$s get segid]
        $s delete
        puts "TRACE_SPLICE gam_atoms=$ngam (plan-ref 15)"
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
    # SS-INDEPENDENCE RECORD (UG node65): the fake CAs carry the load-time
    # STRIDE value (T turn or C coil on 1znf anchors -- anchor-dependent).
    # RECORDED ONLY: no ss assertion is part of the render proof -- Trace
    # never consults `structure`; every render assertion below is purely
    # geometric.
    if {![catch {atomselect $gm {resname GAM and name CA}} s]} {
        set structs [$s get structure]
        $s delete
        puts "TRACE_SS_INFO fake CA structures=$structs (recorded; load-time STRIDE -- NOT part of the render proof; Trace is SS-independent)"
        foreach st $structs {
            if {$st ne "T" && $st ne "C"} {
                _bail ca_structure "exp T or C (load-time STRIDE) got=$st"
            }
        }
    } else { _bail ca_sel $s }
    # Junction law: for each fake resid, its N has a bonded C (prev residue)
    # and its C has a bonded N (next residue) within the C-N bond cutoff
    # (0.6*(1.70+1.55)=1.95; use 1.9 so ONLY bonded pairs can match).
    # Scoping to the EXACT partner resids (a compact fold puts other
    # residues' C/N within 1.9 A of a displaced fake).
    set fi -1
    foreach rr [list 9001 9002 9003] {
        incr fi
        lassign [lindex $partner_list $fi] prev_res next_res
        set n_idx -1
        set c_idx -1
        if {![catch {atomselect $gm "resname GAM and resid $rr"} s]} {
            set gidx [$s get index]
            set gnam [$s get name]
            $s delete
            foreach ii $gidx nm2 $gnam {
                if {$nm2 eq "N"} { set n_idx $ii }
                if {$nm2 eq "C"} { set c_idx $ii }
            }
        } else { _bail junc_walk_sel_$rr $s }
        if {$n_idx < 0 || $c_idx < 0} {
            _bail junction_atoms_$rr "N/C indices not found"
            continue
        }
        if {$prev_res >= 0} {
            if {![catch {atomselect $gm "name C and (within 1.9 of index $n_idx) and resid $prev_res"} js]} {
                set nj [$js num]
                $js delete
                if {$nj < 1} { _bail junction_n_$rr "fake N has no bonded C in resid $prev_res" }
            } else { _bail junction_sel_n_$rr $js }
        } else {
            _bail junction_partner_prev_$rr "prev partner unresolved"
        }
        if {$next_res >= 0} {
            if {![catch {atomselect $gm "name N and (within 1.9 of index $c_idx) and resid $next_res"} js]} {
                set nj [$js num]
                $js delete
                if {$nj < 1} { _bail junction_c_$rr "fake C has no bonded N in resid $next_res" }
            } else { _bail junction_sel_c_$rr $js }
        } else {
            _bail junction_partner_next_$rr "next partner unresolved"
        }
    }
}

# ---- 2. HIDER REPS: stamp tier codes, add the Trace pair, read-back. ----
# Must run BEFORE the render phase empties the pair selections. ORDERING
# CONTRACT: stamp_tier_codes BEFORE add_hider_reps (a static single-frame
# molecule never re-evaluates cached rep selections on an atom-field change).
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    set pre_reps [molinfo $gm get numreps]
    if {[catch {::biochemeleon::hiders::stamp_tier_codes $gm [dict create 1 $ca_idxs]} serr]} {
        _bail stamp_tier_codes $serr
    }
    if {[catch {::biochemeleon::hiders::add_hider_reps $gm [list [list 1 Trace]]} tr]} {
        _bail add_hider_reps $tr
    }
    set nreps [molinfo $gm get numreps]
    if {$nreps != $pre_reps + 2} {
        _bail rep_count "exp=[expr {$pre_reps + 2}] got=$nreps"
    }
    # P6 guard: a real atom keeps user3 == 0.0 (the sentinel conjunct must
    # keep excluding them -- catches a stamp-broadcast spill).
    if {![catch {atomselect $gm {index 100}} s100]} {
        set u3r [lindex [$s100 get user3] 0]
        if {![_feq $u3r 0.0]} { _bail user3_real "exp=0.0 got=$u3r" }
        $s100 delete
    } else { _bail user3_sel_real $s100 }
    # Read-back via tier_reps + repindex (COMBINED-BRACES molinfo form --
    # the single-field form FAILS, Pitfall 3). String-compare, NEVER catch
    # (a bad style only prints console ERROR and no-ops -- viability P-1).
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
            # The bare 0-arg tier form: read-back == `Trace` EXACTLY.
            if {$st ne "Trace"} {
                _bail ${rname}_style "exp=Trace got=$st"
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

# ---- 3. TACHYON RENDERS (probe rep LAST per _render_bits; baseline-zero
#         first; pair selections re-asserted after the scene-diff). ----
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    # (a) Baseline-zero (harness proof): a null selection renders 0
    #     primitives of every kind -- the parser really counts the scene.
    if {![catch {_render_bits $gm Trace {index 999999} [file join [pwd] trace_base.dat]} bbits]} {
        lassign $bbits bs bc bst bstr bcl
        puts "TRACE_BASE nsph=$bs ncyl=$bc nstri=$bst nstrip=$bstr"
        if {$bs != 0 || $bc != 0 || $bst != 0 || $bstr != 0} {
            _bail baseline_zero "exp=0/0/0/0 got=$bs/$bc/$bst/$bstr"
        }
        if {[_has_salmon $bcl $salmon]} { _bail base_salmon "salmon in baseline render" }
    } else { _bail render_base $bbits }

    # (b) GAME-ONLY EXCLUSIVE -- THE BOTH-ENDPOINTS SIGNATURE (the INVERTED
    #     render expectation: 0 bits is the POSITIVE assertion here). The 3
    #     fake CAs form no CA->CA segment entirely inside the GAME selection
    #     (trace neighbors are real CAs; fake-fake separations >= 5.0 A), and
    #     Trace draws no dots -> 0 FCylinder AND 0 Sphere.
    if {![catch {_render_bits $gm Trace {segid GAME} [file join [pwd] trace_gameonly.dat]} gbits]} {
        lassign $gbits gs gc gst gstr gcl
        puts "TRACE_GAMONLY nsph=$gs ncyl=$gc nstri=$gst nstrip=$gstr (both-endpoints rule: exp 0/0)"
        if {$gc != 0} {
            _bail gameonly_fcyl "exp=0 FCylinder (both-endpoints rule) got=$gc"
        }
        if {$gs != 0} {
            _bail gameonly_sph "exp=0 Sphere (Trace draws no dots) got=$gs"
        }
        if {$gst != 0 || $gstr != 0} {
            _bail gameonly_tri "exp=0 triangles got=$gst/$gstr"
        }
        if {[_has_salmon $gcl $salmon]} { _bail gameonly_salmon "salmon in GAME-only render" }
    } else { _bail render_gameonly $gbits }

    # (c) ANCHOR-WINDOW PATH-INCLUSION: the fake CA IS in the traced path.
    #     Anchor of fake CA 1 = the nearest real CA within 2.0 A (PARENTHESIZED
    #     within -- VMD's within swallows trailing expressions).
    set fakeca1 [lindex $ca_idxs 0]
    if {![catch {atomselect $gm "name CA and (within 2.0 of index $fakeca1) and not index $fakeca1"} asel]} {
        $asel frame 0
        if {[$asel num] != 1} {
            _bail anchor_lookup "exp=1 nearest real CA got=[$asel num] (fakeca1=$fakeca1)"
        } else {
            set anch_resid [lindex [$asel get resid] 0]
            set anch_chain [lindex [$asel get chain] 0]
        }
        $asel delete
    } else { _bail anchor_sel $asel }
    if {$anch_resid > 0} {
        set wlo [_wlo $anch_resid]
        set whi [expr {$anch_resid + 2}]
        set winsel "resid $wlo to $whi"
        # Spliced window render (plan-literal selection: real resids only).
        if {![catch {_render_bits $gm Trace $winsel [file join [pwd] trace_win.dat]} sw]} {
            lassign $sw s1s s1c s1st s1str s1cl
            puts "TRACE_WINDOW spliced {$winsel} anchor=$anch_resid chain=$anch_chain nsph=$s1s ncyl=$s1c nstri=$s1st nstrip=$s1str"
            if {[_has_salmon $s1cl $salmon]} { _bail win_salmon "salmon in spliced window render" }
        } else { _bail render_spliced_win $sw; set s1c -1 }
        # Unspliced control: the SAME frame-0 collapse pipeline as the splice
        # molecules (_load_demo_1f == the mutate pipeline minus hiders), so
        # the only difference is the spliced fakes themselves.
        if {[catch {_load_demo_1f 1znf} mc]} {
            _bail load_control $mc
            set mc -1
        } else {
            if {![catch {_render_bits $mc Trace $winsel [file join [pwd] trace_ctrl.dat]} cw]} {
                lassign $cw c1s c1c c1st c1str c1cl
                puts "TRACE_WINDOW control {$winsel} nsph=$c1s ncyl=$c1c nstri=$c1st nstrip=$c1str"
                if {[_has_salmon $c1cl $salmon]} { _bail ctrl_salmon "salmon in control window render" }
            } else { _bail render_ctrl_win $cw; set c1c -1 }
            # The control molecule is spent -- delete it so later renders are
            # never polluted (belt-and-suspenders with _render_bits isolation).
            catch {mol delete $mc}
            set mc -2
        }
        # PATH-INCLUSION EVIDENCE (prints only -- DISCOVERY-BRIEF OVERRIDES
        # the plan-pinned `spliced > control` assert): window render counts
        # are STRIDE-SHIFT-VARIANT (17.2-04 observed 22->6 with ZERO
        # pathology; this run observed spliced 6 vs control 8 -- the same
        # variance class: the re-segmented CA path changes the window's
        # cylinder count in EITHER direction). The window render DOES change
        # vs the control (the fake CA is in the traced path -- the reroute
        # shows as a count DELTA, not a sign), and the ROBUST asserted
        # positive controls are: the BOND SCENE-DIFF below (floor = the
        # fakes' bond count) + the junction-bond law of step 1. Documented
        # in 17.2-07-SUMMARY.
        if {$s1c >= 0 && $c1c >= 0} {
            if {$s1c != $c1c} {
                puts "TRACE_WINDOW delta spliced=$s1c control=$c1c (reroute evidence: path changed; sign is STRIDE-shift-variant, NOT asserted)"
            } else {
                puts "TRACE_WINDOW NOTE spliced=$s1c == control=$c1c (window blind to this anchor; scene-diff carries the in-path proof)"
            }
        }
    }

    # (d) BOND SCENE-DIFF (17.2-04 proven in-path proof, Lines scene rep):
    #     A = rep-0 Lines over all; B = rep-0 Lines over not resname GAM.
    #     Pair reps are EMPTIED for both (never re-selected to a non-tier
    #     selection); after the diff the pair literals are re-asserted from
    #     tier_reps and rep 0 restored to all.
    set nreps_sd [molinfo $gm get numreps]
    set pairs_ok 1
    for {set i 1} {$i < $nreps_sd} {incr i} {
        if {[catch {mol modselect $i $gm {index 999999}} e1]} { set pairs_ok 0 }
    }
    set da_ok 0
    set db_ok 0
    set daerr ""
    set dberr ""
    if {![catch {render Tachyon [file join [pwd] trace_sceneA.dat]} daerr]} {
        set da_ok 1
    }
    if {[catch {mol modselect 0 $gm {not resname GAM}} e2]} { set pairs_ok 0 }
    if {![catch {render Tachyon [file join [pwd] trace_sceneB.dat]} dberr]} {
        set db_ok 1
    }
    if {[catch {mol modselect 0 $gm all} e3]} { set pairs_ok 0 }
    # Re-assert the pair literals (unchanged-string contract) + null the
    # probe state cleanly: pairs return to their tier selections.
    if {![dict exists $::biochemeleon::hiders::tier_reps 1]} {
        set pairs_ok 0
    } else {
        lassign [dict get $::biochemeleon::hiders::tier_reps 1] hn2 fn2 hs2 fs2
        set hidx2 [mol repindex $gm $hn2]
        set fidx2 [mol repindex $gm $fn2]
        if {$hidx2 >= 0} { catch {mol modselect $hidx2 $gm $hs2} }
        if {$fidx2 >= 0} { catch {mol modselect $fidx2 $gm $fs2} }
    }
    if {$da_ok && $db_ok} {
        lassign [_parse_bits [file join [pwd] trace_sceneA.dat]] a_s a_c a_st a_sp a_cl
        lassign [_parse_bits [file join [pwd] trace_sceneB.dat]] b_s b_c b_st b_sp b_cl
        set bond_delta [expr {$a_c - $b_c}]
        set floor [expr {4 * $exp_fake}]
        puts "TRACE_SCENEDIFF A=$a_c B=$b_c delta=$bond_delta floor=$floor"
        if {[_has_salmon $a_cl $salmon] || [_has_salmon $b_cl $salmon]} {
            _bail scene_salmon "salmon in scene-diff renders"
        }
        if {[catch {expr {double($bond_delta) >= double($floor)}} bd] || !$bd} {
            _bail bond_scene_diff "exp delta >= $floor (the fakes' bonds render) got=$bond_delta"
        }
    } else {
        _bail render_scene_diff "$daerr / $dberr"
    }
}

# ---- 4. FOUND-MARKING (visual half, single tier): flag fake CA 3, then the
#         partition re-splits ONLY the Trace tier. mark_found_visual's
#         mandatory modselect re-assert also RESTORES the pair selections
#         the render phase emptied (unchanged-string contract, hiders.tcl).
if {$gm >= 0 && [llength $ca_idxs] == 3} {
    set ca3 [lindex $ca_idxs 2]
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm $ca3} merr]} {
        _bail mark_found_visual $merr
    } else {
        if {![catch {atomselect $gm "index $ca3"} s]} {
            set u2 [lindex [$s get user2] 0]
            if {[catch {expr {double($u2) > 0}} ok] || !$ok} {
                _bail found_user2 "exp=user2 > 0 got=$u2"
            }
            $s delete
        } else { _bail found_sel $s }
        foreach {selstr expn tag} [list \
                {resname GAM and beta < 0 and user2 > 0 and user3 1} 1 trace_found \
                {resname GAM and beta < 0 and user2 < 1 and user3 1} 2 trace_hidden] {
            if {![catch {atomselect $gm $selstr} s]} {
                if {[$s num] != $expn} {
                    _bail $tag "exp=$expn got=[$s num]"
                }
                $s delete
            } else { _bail ${tag}_sel $s }
        }
    }
}

# ---- 5. CLEANUP/RESTORE: game molecule deleted, original reloaded intact
#         (424 atoms -- no residue leak). ----
if {$gm >= 0} {
    catch {mol delete $gm}
    set gm -2
    if {[catch {_load_demo_1f 1znf} m4]} {
        _bail load_restore $m4
        set m4 -1
    } else {
        set rn [molinfo $m4 get numatoms]
        if {$rn != 424} {
            _bail restored_atoms "exp=424 got=$rn (residue leak?)"
        }
        catch {mol delete $m4}
        set m4 -2
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
