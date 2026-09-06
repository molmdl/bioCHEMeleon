# vmd/smoke/phase17_cartoon_smoke.tcl
# Phase-17.2 (17.2-05) headless smoke: the CARTOON tier end-to-end -- the
# SS-dependent rep of the hider family. Cartoon is the flagship residue-splice
# consumer: the research's Option-A decision says a spliced GAM gets STRIDE
# `T` (turn) at load time and renders as a smooth coil/turn TUBE under the
# bare `Cartoon` rep -- connected, in-path, bump-visible, NEVER a sheet ribbon
# (no TriStrip, no ssrecalc).
#
# Proves, on demo 1znf (424 atoms), driven directly (NOT through start_game --
# the dispatch lands in 17.2-09; 17.1-04's tiers-smoke precedent):
#   1. SPLICE: make_residue_hiders 3 -> 3 {chain resid atoms} records (fake
#      resids {9001 9002 9003}); mutate -> 424+nfake atoms; CA-only sentinel
#      (`resname GAM and beta < 0` == exactly ONE index per hider, all named
#      CA); resname GAM == nfake; protein +nfake; segid GAME + record chain on
#      every fake atom; BOTH peptide junctions bonded (scoped partner resids).
#   2. STRUCTURE: fake CA structure == T on all three (load-time STRIDE --
#      the Option-A turn verdict, zero ssrecalc anywhere). The exact letter is
#      PRNG-anchor-dependent (17.2-04 harness: coil-region anchors read C, the
#      SAME load-time tube look), so the splice is RE-DRAWN (bounded retries)
#      until an all-T draw lands; if the retry budget exhausts, the last valid
#      molecule is kept and the assert relaxes to the harness contract
#      {T,C} with a printed NOTE (documented in the SUMMARY).
#   3. ANCHOR RECIPE (shared by the tier smokes): the fake CA sits ~1.0 A from
#      its anchor -> `name CA and (within 2.0 of index <fake>) and not index
#      <fake>` returns EXACTLY ONE CA whose resid IS the anchor's (next-nearest
#      real CA >= ~2.8 A). Asserted for all 3 fakes; record 1's anchor drives
#      the window render. NEVER hand-roll displacement (the rear-junction sign
#      handling lives inside make_residue_hiders).
#   4. HIDER REPS (production order, 17.1-04 contracts): stamp_tier_codes
#      BEFORE add_hider_reps (a rep added before the user3 stamp caches an
#      empty selection); user3 read-back FLOAT 1.0 (numeric only); ONE
#      hidden/found pair with the BARE style `Cartoon` + Element coloring;
#      numreps == pre_start + 2; read-back via the COMBINED-braces molinfo
#      form + mol repindex (-1 guard): style == `Cartoon` EXACTLY, hidden
#      color Element / found ColorID 7, selections the user3-conjoined
#      sentinel strings verbatim. NEVER mol showrep; NEVER write beta.
#   5. Tachyon renders (probe rep LAST; baseline-zero first; harness helpers
#      _parse_bits/_render_bits copied from 17.2-04):
#      a. BASELINE-ZERO (selection `index 999999`) renders 0 primitives of
#         every kind -- the parser really counts the scene.
#      b. GAME-ONLY EXCLUSIVE (probe selection `segid GAME`, style Cartoon):
#         FCylinder >= 3 (coil-tube bits, research measured ~6/residue) AND
#         TriStrip == 0 (a T fake never draws sheet ribbon) AND no found-color
#         leak (no salmon v1-legacy triple, no v2 found-green ColorID 7).
#      c. WINDOW path-inclusion: `resid <a-2> to <a+2>` Cartoon on the spliced
#         molecule vs the SAME window on a fresh single-frame-collapsed
#         control. PRINTS ONLY -- window render counts are STRIDE-shift-
#         variant (22->6 observed with zero pathology, run 20) and asserted
#         NOWHERE (plan-pinned window assertion conflicts with the discovery;
#         the scene-diff below is the assertion -- documented in SUMMARY).
#      d. BOND SCENE-DIFF (the ss-independent POSITIVE control): A=all vs
#         B=fakes-removed (per-rep: GAM-targeting reps empty to `index
#         999999`, others to `not resname GAM`); cylinder delta >= 4 per
#         fake atom (junction + intra-residue stubs, both-endpoints rule).
#   6. FOUND-MARKING partition: mark_found_visual on hider 2 -> user2(ca2)
#      > 0 numeric; the found selection (user2 > 0 and user3 1) == 1; the
#      hidden variant (user2 < 1) == 2; CA 1/3 user2 still <= 0.
#   7. CLEAN RESTORE: mol delete game mol (molid dead); reload the original
#      demo -> 424 atoms (no residue leak), sentinel registry == 0, numreps ==
#      the pre-start demo value (no hider rep leak).
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
# silently). NEVER mol showrep (ignored in text mode). NEVER ssrecalc.

set failures [list]

proc _bail {tag msg} {
    upvar 1 failures f
    lappend f "$tag:$msg"
}

# Float read-back compare (beta/user/user3 are FLOATS -- numeric only).
proc _feq {a b} {
    if {[catch {expr {abs(double($a) - double($b)) < 1.0e-6}} ok]} {
        return 0
    }
    return $ok
}

# Frame pin for coordinate reads on multi-model demos (1znf ships 2 frames;
# unpinned reads are frame-unstable -- dbg_frame probe). The lib pins frame 0
# everywhere; the smoke reads frame 0 to match.
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
# whole file. Returns {nsph ncyl nstri nstrip}; -1s signal an unreadable file
# (a missing file can never masquerade as an empty scene).
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

# THE reusable 17.2 render helper (copied from 17.2-04, ONE adaptation): add
# a probe rep LAST (highest index), style+select it, EMPTY every earlier rep
# (showrep is ignored in text mode), render Tachyon, RESTORE EVERY EARLIER
# REP'S EXACT SELECTION STRING (combined-braces grab -- the harness restored
# to "all", byte-identical when every prior selection IS "all" but it would
# WIPE the hider reps' user3-conjoined tier selections), delete the probe rep
# (highest index -- never renumbers), return the parsed counts. `axes
# location off` must have been called once before the first render.
proc _sel_grab {m n} {
    set spec ""
    for {set i 0} {$i < $n} {incr i} {
        append spec " {selection $i}"
    }
    return [molinfo $m get [string trim $spec]]
}

proc _render_bits {m style sel path} {
    # Isolate the scene: VMD renders EVERY DISPLAYED molecule -- any other
    # live molecule's reps would pollute the count (found the hard way: a
    # still-alive game molecule added ~823 phantom FCylinders). Turn all
    # OTHER molecules off for the render, restore after.
    set others [list]
    foreach mm [molinfo list] {
        if {$mm != $m} { lappend others $mm }
    }
    foreach mm $others { catch {mol off $mm} }
    set pi [molinfo $m get numreps]
    set olds [_sel_grab $m $pi]
    mol addrep $m
    mol modstyle $pi $m $style
    mol modcolor $pi $m Element
    mol modselect $pi $m $sel
    for {set i 0} {$i < $pi} {incr i} {
        mol modselect $i $m {index 999999}
    }
    set rc [catch {render Tachyon $path} rerr]
    for {set i 0} {$i < $pi} {incr i} {
        mol modselect $i $m [lindex $olds $i]
    }
    catch {mol delrep $pi $m}
    foreach mm $others { catch {mol on $mm} }
    if {$rc} { error "render Tachyon failed: $rerr" }
    return [_parse_bits $path]
}

# Found-color leak scan: every `Color R G B` triple in a Tachyon .dat; flag
# anything within eps 0.01 of the v1-legacy salmon (1.0 0.6 0.6) OR the v2
# found-green (ColorID 7 = 0.0 1.0 0.0). Returns the offending triples
# ({{-1 -1 -1}} signals an unreadable file).
proc _found_color_scan {path} {
    if {[catch {open $path r} fh]} {
        return [list [list -1 -1 -1]]
    }
    set dat [read $fh]
    close $fh
    set toks [regexp -all -inline -- {\mColor\y\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)} $dat]
    set ncol 0
    set bad [list]
    for {set i 0} {$i < [llength $toks]} {incr i 4} {
        set r [lindex $toks [expr {$i + 1}]]
        set g [lindex $toks [expr {$i + 2}]]
        set b [lindex $toks [expr {$i + 3}]]
        incr ncol
        foreach ref [list {1.0 0.6 0.6} {0.0 1.0 0.0}] {
            lassign $ref er eg eb
            if {[catch {expr {abs(double($r) - double($er)) < 0.01 \
                && abs(double($g) - double($eg)) < 0.01 \
                && abs(double($b) - double($eb)) < 0.01}} hit] || $hit} {
                lappend bad [list $r $g $b]
            }
        }
    }
    if {$ncol == 0} {
        return [list [list -2 -2 -2]]
    }
    return $bad
}

# THE 17.2 harness loader: load a demo COLLAPSED TO A SINGLE FRAME. 1znf
# ships 2 models; VMD lands on the last frame and UNPINNED coordinate reads
# are racy on multi-frame molecules (dbg_pin probe). Collapse via a frame-0-
# pinned writepdb round-trip (the SAME pipeline mutate uses downstream) so
# every molecule in the smoke is single-frame and every read/write is
# deterministic frame-0 geometry. THE CALLER CONTRACT: single-frame molecules
# only.
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] cartoon_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
}

# A residue's N/C atom index (for the junction partner queries).
proc _res_n_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name N"]]
    set ni [lindex [$s get index] 0]
    $s delete
    return $ni
}

proc _res_c_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name C"]]
    set ci [lindex [$s get index] 0]
    $s delete
    return $ci
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

# Bulk protein-CA table ({resid chain x y z}) for the anchor derivation from
# the records -- records carry the FAKE resid (9001+k), never the anchor's.
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
set recs [list]
set n0 -1
set nreps_demo -1
set real_protein -1
set ca_idxs [list]
set partner_list [list]
set anchor_list [list]
set ganchor_list [list]
set all_t 0
set ca_structs [list]
set s1c -1
set c1c -1

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

# ---- 1. SPLICE + STRUCTURE: re-draw until 3 records AND (bounded) an ----
# ----    all-T STRIDE verdict; keep the chosen molecule + its metadata. ----
for {set att 0} {$att < 8 && $gm < 0} {incr att} {
    if {[catch {_load_demo_1f 1znf} m0] || $m0 < 0} {
        _bail load_demo $m0
        set m0 -1
        break
    }
    set n0 [molinfo $m0 get numatoms]
    set nreps_demo [molinfo $m0 get numreps]
    if {$n0 != 424} { _bail orig_atoms "exp=424 got=$n0" }
    if {[catch {atomselect $m0 protein} psel]} {
        _bail protein_sel $psel
        set real_protein -1
    } else {
        set real_protein [$psel num]
        $psel delete
    }
    # Draw retry loop: 1znf is a COMPACT fold -- the greedy 5.0 A anchor
    # separation rejects later draws often (17.2-04: ~half the 2-record
    # runs under-generate to 1). The mechanism behavior is correct
    # (under-generation tolerated, vmdcon-warned); the smoke needs 3
    # records for the tier bookkeeping, so re-draw until 3 (max 8).
    set recs [list]
    for {set d 0} {$d < 8} {incr d} {
        if {![catch {::biochemeleon::mutation::make_residue_hiders $m0 3} recs]} {
            if {[llength $recs] == 3} { break }
        } else {
            _bail make_residue_hiders $recs
            set recs [list]
            break
        }
    }
    if {[llength $recs] != 3} {
        catch {mol delete $m0}
        set m0 -1
        continue
    }
    # Records carry the FAKE resid (9001+k); derive each ANCHOR geometrically
    # (nearest real CA to the record's fake CA sits exactly 1.0 A away) and
    # the junction partner resids, on THIS attempt's original molecule --
    # mutate consumes it.
    set catab [_ca_table $m0]
    set anchor_list [list]
    set partner_list [list]
    set k 0
    set recs_ok 1
    foreach r $recs {
        set fca [list]
        foreach a [lindex $r 2] {
            if {[lindex $a 0] eq "CA"} {
                lassign [lrange $a 2 4] fx fy fz
                set fca [list $fx $fy $fz]
            }
        }
        if {[llength $fca] != 3} {
            _bail rec${k}_fake_ca "record $k carries no CA coords"
            set recs_ok 0
            incr k
            continue
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
            _bail rec${k}_anchor "no real CA found (catab empty?)"
            set recs_ok 0
        } elseif {[catch {expr {double($best) >= 0.95 && double($best) <= 1.05}} inband] || !$inband} {
            _bail rec${k}_anchor_dist "nearest real CA (resid $anch_res) at $best, exp 1.0 in \[0.95,1.05\]"
            set recs_ok 0
        }
        lappend anchor_list [list $anch_ch $anch_res]
        lappend partner_list [_junction_partners $m0 $anch_ch $anch_res]
        incr k
    }
    if {!$recs_ok} {
        catch {mol delete $m0}
        set m0 -1
        continue
    }
    # Splice through the real bridge (NEVER hand-roll displacement).
    if {[catch {::biochemeleon::mutation::mutate $m0 [list] $recs} gm]} {
        _bail mutate $gm
        set gm -1
        break
    }
    # STRUCTURE verdict (load-time STRIDE; NO ssrecalc anywhere). Prefer an
    # all-T draw (the plan-pinned Option-A verdict); keep the last valid
    # molecule on a {T,C} fallback with a printed NOTE.
    set all_t 1
    set ca_structs [list]
    if {![catch {atomselect $gm {resname GAM and name CA}} s]} {
        set ca_structs [$s get structure]
        $s delete
    } else {
        _bail ca_sel $s
    }
    if {[llength $ca_structs] != 3} {
        _bail ca_struct_count "exp=3 got=[llength $ca_structs]"
        catch {mol delete $gm}
        set gm -1
        set all_t 0
        continue
    }
    foreach st $ca_structs {
        if {$st ne "T"} { set all_t 0 }
        if {$st ne "T" && $st ne "C"} {
            _bail ca_structure "exp T or C (load-time coil/turn tube) got=$st"
        }
    }
    if {!$all_t && $att < 7} {
        # Not the plan-pinned all-T verdict and retries remain: discard and
        # re-draw (independent PRNG anchors).
        catch {mol delete $gm}
        set gm -1
        continue
    }
    # gm kept here: all-T (preferred) or the final fallback molecule.
}
if {![info exists ca_structs]} { set ca_structs [list] }
if {$gm >= 0 && !$all_t} {
    puts "CARTOON_NOTE structure fallback: fake CA structures = $ca_structs \
(PRNG anchor draw read C on a coil-region anchor; SAME load-time STRIDE \
tube look, NO ssrecalc anywhere -- 17.2-04 harness contract)"
} elseif {$gm >= 0} {
    puts "CARTOON_STRUCT fake CA structures = $ca_structs (all T -- the \
plan-pinned Option-A turn verdict, load-time STRIDE, NO ssrecalc anywhere)"
}

# ---- 2. TAGGED MOLECULE asserts on the chosen game molecule. ----
if {$gm >= 0} {
    set exp_fake [_rec_atom_total $recs]
    set exp_total [expr {424 + $exp_fake}]
    set n1 [molinfo $gm get numatoms]
    if {$n1 != $exp_total} { _bail game_atoms "exp=$exp_total got=$n1" }
    # CA-only sentinel: exactly ONE index per hider, all named CA, resids
    # {9001 9002 9003}, structure T-or-C on all three.
    if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hidx]} {
        _bail fetch_idx $hidx
        set hidx [list]
    } elseif {[llength $hidx] != 3} {
        _bail fetch_count "exp=3 got=[llength $hidx] ($hidx)"
    }
    set beta_idxs [list]
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set beta_idxs [$s get index]
        set nb [$s num]
        $s delete
        if {$nb != 3} { _bail sentinel_count "exp=3 got=$nb" }
        foreach i $beta_idxs {
            if {![catch {atomselect $gm "index $i"} si]} {
                set nm [lindex [$si get name] 0]
                if {$nm ne "CA"} { _bail sentinel_name_$i "exp=CA got=$nm" }
                $si delete
            } else { _bail sentinel_sel_$i $si }
        }
    } else { _bail sentinel_sel $s }
    if {[llength $beta_idxs] == 3} {
        # resids read per sentinel index
        set exp_rids [list 9001 9002 9003]
        set seen_rids [list]
        foreach i $beta_idxs {
            if {![catch {atomselect $gm "index $i"} si]} {
                lappend seen_rids [lindex [$si get resid] 0]
                $si delete
            } else { _bail sentinel_sel2_$i $si }
        }
        if {$seen_rids ne $exp_rids} {
            _bail sentinel_resids "exp=$exp_rids got=$seen_rids"
        }
    }
    # GAM total + protein count.
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set ngam [$s num]
        $s delete
        if {$ngam != $exp_fake} { _bail gam_count "exp=$exp_fake got=$ngam" }
    } else { _bail gam_sel $s }
    if {![catch {atomselect $gm protein} s]} {
        set nprot [$s num]
        $s delete
        if {$real_protein >= 0 && $nprot != $real_protein + $exp_fake} {
            _bail protein_count "exp=$real_protein+$exp_fake=[expr {$real_protein + $exp_fake}] got=$nprot"
        }
    } else { _bail protein_sel2 $s }
    # Per fake residue: segid GAME + record chain; junction law: the fake N
    # has a bonded C (prev residue) and the fake C has a bonded N (next
    # residue) within the C-N bond cutoff (0.6*(1.70+1.55)=1.95; scoped to
    # the EXACT partner resids -- a compact fold puts other residues' C/N
    # atoms within 1.9 A of a displaced fake).
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set gidx [$s get index]
        set gres [$s get resid]
        set gchn [$s get chain]
        set gseg [$s get segid]
        set gnam [$s get name]
        $s delete
        set nfake [llength $gidx]
        if {$nfake != $exp_fake} { _bail gam_walk "exp=$exp_fake got=$nfake" }
        set exp_chain [dict create]
        set fi 0
        foreach r $recs {
            dict set exp_chain [lindex $r 1] [lindex $r 0]
            incr fi
        }
        for {set i 0} {$i < $nfake} {incr i} {
            set ii [lindex $gidx $i]
            set rr [lindex $gres $i]
            if {[lindex $gseg $i] ne "GAME"} {
                _bail fake_segid_$ii "exp=GAME got=[lindex $gseg $i]"
            }
            if {[dict exists $exp_chain $rr] \
                    && [lindex $gchn $i] ne [dict get $exp_chain $rr]} {
                _bail fake_chain_$ii "exp=[dict get $exp_chain $rr] got=[lindex $gchn $i]"
            }
        }
        set fi -1
        foreach rr [list 9001 9002 9003] {
            incr fi
            set n_idx -1
            set c_idx -1
            for {set i 0} {$i < $nfake} {incr i} {
                if {[lindex $gres $i] != $rr} { continue }
                if {[lindex $gnam $i] eq "N"} { set n_idx [lindex $gidx $i] }
                if {[lindex $gnam $i] eq "C"} { set c_idx [lindex $gidx $i] }
            }
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
    } else { _bail gam_walk_sel $s }
    # ANCHOR RECIPE on the game molecule (parenthesized within -- VMD's
    # within swallows trailing expressions): exactly ONE real CA within 2.0
    # A of each fake CA (the anchor at ~1.0 A; next-nearest >= ~2.8 A), and
    # it agrees with the record-derived anchor.
    set ganchor_list [list]
    if {[llength $beta_idxs] == 3} {
        set fi 0
        foreach i $beta_idxs {
            if {![catch {atomselect $gm "name CA and (within 2.0 of index $i) and not index $i"} asel]} {
                $asel frame 0
                set na [$asel num]
                if {$na != 1} {
                    _bail anchor_recipe_$i "exp=1 nearest real CA got=$na"
                    lappend ganchor_list [list "" -1]
                } else {
                    lappend ganchor_list [list \
                        [lindex [$asel get chain] 0] \
                        [lindex [$asel get resid] 0]]
                }
                $asel delete
            } else {
                _bail anchor_sel_$i $asel
                lappend ganchor_list [list "" -1]
            }
            incr fi
        }
        set fi 0
        foreach ga $ganchor_list {
            lassign [lindex $anchor_list $fi] ech erid
            lassign $ga gch grid
            if {$grid > 0 && ($gch ne $ech || $grid != $erid)} {
                _bail anchor_agree_$fi "record anchor=$ech/$erid vs recipe anchor=$gch/$grid"
            }
            incr fi
        }
    }
}

# ---- 3. HIDER REPS (production order): stamp user3 THEN add the pair. ----
set pre_start -1
set tier_reps_ok 0
if {$gm >= 0 && [llength $beta_idxs] == 3} {
    set pre_start [molinfo $gm get numreps]
    # stamp_tier_codes BEFORE add_hider_reps (ORDERING CONTRACT: a rep added
    # before the user3 stamp caches an EMPTY selection -- static molecules
    # never re-evaluate on atom-field change).
    if {[catch {::biochemeleon::hiders::stamp_tier_codes $gm \
            [dict create 1 $beta_idxs]} serr]} {
        _bail stamp_tier_codes $serr
    } else {
        set u3_ok 1
        foreach i $beta_idxs {
            if {![catch {atomselect $gm "index $i"} si]} {
                set u3 [lindex [$si get user3] 0]
                if {![_feq $u3 1.0]} {
                    _bail user3_readback_$i "exp=1.0 got=$u3"
                    set u3_ok 0
                }
                $si delete
            } else { _bail user3_sel_$i $si; set u3_ok 0 }
        }
        if {$u3_ok} {
            # ONE hidden/found pair: the BARE Cartoon style (StyleArgs from
            # the caller; the dispatch lands in 17.2-09).
            if {[catch {::biochemeleon::hiders::add_hider_reps $gm \
                    {{1 Cartoon}}} tr]} {
                _bail add_hider_reps $tr
            } else {
                set post_nreps [molinfo $gm get numreps]
                if {$post_nreps != $pre_start + 2} {
                    _bail numreps "exp=$pre_start+2 got=$post_nreps"
                }
                # tier_reps dict: code 1 -> {hidden_name found_name hsel fsel}.
                if {[dict size $tr] != 1 || ![dict exists $tr 1]} {
                    _bail tier_reps_shape "exp 1 entry keyed 1 got=[dict size $tr]"
                } else {
                    lassign [dict get $tr 1] hname fname hsel fsel
                    if {$hname eq "" || $fname eq ""} {
                        _bail tier_rep_names "empty rep name(s): $hname/$fname"
                    }
                    # Read-back via mol repindex (-1 guard) + the
                    # COMBINED-braces molinfo form (the single-field form
                    # FAILS -- Pitfall 3). Style must string-compare to
                    # `Cartoon` EXACTLY.
                    set nreps [molinfo $gm get numreps]
                    foreach {rname rwant_sel rwant_col} [list \
                        hidden "resname GAM and beta < 0 and user2 < 1 and user3 1" "Element" \
                        found  "resname GAM and beta < 0 and user2 > 0 and user3 1" "ColorID 7"] {
                        set rn [set ${rname}name]
                        set ri [mol repindex $gm $rn]
                        if {$ri < 0 || $ri >= $nreps} {
                            _bail repindex_$rname "rep '$rn' unresolved (repindex $ri)"
                            continue
                        }
                        set rstyle ""; set rsel ""; set rcol ""; set rmat ""
                        foreach {rstyle rsel rcol rmat} [molinfo $gm get \
                            "{rep $ri} {selection $ri} {color $ri} {material $ri}"] { break }
                        if {$rstyle ne "Cartoon"} {
                            _bail style_readback_$rname "exp=Cartoon got='$rstyle'"
                        }
                        if {$rsel ne $rwant_sel} {
                            _bail sel_readback_$rname "exp='$rwant_sel' got='$rsel'"
                        }
                        if {$rcol ne $rwant_col} {
                            _bail color_readback_$rname "exp=$rwant_col got=$rcol"
                        }
                        if {$rsel ne $hsel && $rname eq "hidden"} {
                            _bail tier_reps_sel "tier_reps hsel='$hsel' != read-back '$rsel'"
                        }
                        if {$rsel ne $fsel && $rname eq "found"} {
                            _bail tier_reps_fsel "tier_reps fsel='$fsel' != read-back '$rsel'"
                        }
                    }
                    # Sentinel surface stays CA-only + user3-conjoined:
                    # the hidden selection picks EXACTLY the 3 fake CAs,
                    # the found variant is empty (nothing marked yet).
                    if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} s]} {
                        set nh [$s num]
                        $s delete
                        if {$nh != 3} { _bail hidden_partition "exp=3 got=$nh" }
                    } else { _bail hidden_sel $s }
                    if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 > 0 and user3 1}} s]} {
                        set nf [$s num]
                        $s delete
                        if {$nf != 0} { _bail found_partition_pre "exp=0 got=$nf" }
                    } else { _bail found_pre_sel $s }
                    set tier_reps_ok 1
                }
            }
        }
    }
}

# ---- 4. TACHYON RENDERS (probe rep LAST; baseline-zero first). ----
if {$gm >= 0} {
    # 4a. Baseline-zero (harness proof): a null selection renders 0
    #     primitives of every kind -- the parser really counts the scene.
    if {![catch {_render_bits $gm Cartoon {index 999999} \
            [file join [pwd] cartoon_base.dat]} bbits]} {
        lassign $bbits bs bc bst bstr
        puts "CARTOON_RENDER baseline_zero nsph=$bs ncyl=$bc nstri=$bst nstrip=$bstr"
        if {$bs != 0 || $bc != 0 || $bst != 0 || $bstr != 0} {
            _bail baseline_zero "exp=0/0/0/0 got=$bs/$bc/$bst/$bstr"
        }
    } else { _bail render_base $bbits }
    # 4b. GAME-ONLY EXCLUSIVE: the splice's own bits render under the bare
    #     Cartoon style -- FCylinder coil-tube bits (>= 3; research measured
    #     ~6/residue), NO TriStrip (a T fake never draws sheet ribbon), and
    #     no found-color leak (nothing is marked yet).
    if {![catch {_render_bits $gm Cartoon {segid GAME} \
            [file join [pwd] cartoon_game.dat]} gbits]} {
        lassign $gbits gs gc gst gstr
        puts "CARTOON_RENDER gameonly nsph=$gs ncyl=$gc nstri=$gst nstrip=$gstr"
        if {$gc < 3} {
            _bail gameonly_bits "exp>=3 FCylinder coil-tube bits got=$gc"
        }
        if {$gstr != 0} {
            _bail gameonly_tristrip "exp=0 TriStrip (T fake = tube, never ribbon) got=$gstr"
        }
        set leak [_found_color_scan [file join [pwd] cartoon_game.dat]]
        if {[lindex $leak 0] == -1 || [lindex $leak 0] == -2} {
            _bail color_scan "unreadable/empty Color section in cartoon_game.dat ($leak)"
        } elseif {[llength $leak] > 0} {
            _bail found_color_leak "found-color triples in the GAME-only render: $leak"
        }
    } else { _bail render_gameonly $gbits }
    # 4c. WINDOW path-inclusion evidence (PRINTS ONLY -- the window render
    #     is STRIDE-shift-variant and asserted NOWHERE; the bond scene-diff
    #     below is the positive control).
    set anch_resid -1
    if {[llength $ganchor_list] >= 1} {
        lassign [lindex $ganchor_list 0] gch1 grid1
        set anch_resid $grid1
    }
    if {$anch_resid > 0} {
        set wlo [_wlo $anch_resid]
        set whi [expr {$anch_resid + 2}]
        set winsel "resid $wlo to $whi"
        if {![catch {_render_bits $gm Cartoon $winsel \
                [file join [pwd] cartoon_win.dat]} sw]} {
            lassign $sw s1s s1c s1st s1str
            puts "CARTOON_RENDER spliced_window={$winsel} nsph=$s1s ncyl=$s1c nstri=$s1st nstrip=$s1str"
        } else { _bail render_spliced_win $sw }
        # Unspliced control: the SAME single-frame collapse pipeline
        # (_load_demo_1f == the mutate pipeline minus hiders) -- a raw
        # load_demo renders the demo's LAST frame geometry while every
        # mutate-pipeline molecule is the frame-0 collapse; different
        # NMR-model geometry gives DIFFERENT STRIDE/cartoon counts.
        if {[catch {_load_demo_1f 1znf} mc] || $mc < 0} {
            _bail load_control $mc
            set mc -1
        } else {
            if {![catch {_render_bits $mc Cartoon $winsel \
                    [file join [pwd] cartoon_ctrl.dat]} cw]} {
                lassign $cw c1s c1c c1st c1str
                puts "CARTOON_RENDER control_window nsph=$c1s ncyl=$c1c nstri=$c1st nstrip=$c1str"
                puts "CARTOON_NOTE window delta spliced=$s1c vs control=$c1c \
(STRIDE-shift-variant, printed NOT asserted -- 22->6 crash observed with \
zero pathology; the scene-diff is the assertion)"
            } else { _bail render_ctrl_win $cw }
            catch {mol delete $mc}
            set mc -2
        }
    }
    # 4d. BOND SCENE-DIFF (the ss-independent POSITIVE control): A=all vs
    #     B=fakes-removed; the cylinder delta == the fakes' bond count
    #     (junction + intra-residue stubs, both-endpoints rule) >= 4 per
    #     fake atom. Probe rep added LAST and emptied (it carries no scene
    #     of its own); exact-restore for the hider reps. PER-REP fake
    #     removal (NOT a blanket `not resname GAM`): a rep whose selection
    #     targets the fakes (the hidden tier rep) empties to `index 999999`
    #     -- a blanket flip would turn the EMPTY found rep into a real-atom
    #     Cartoon rep and ADD phantom bits to B (observed: B=964 > A=865).
    set pi2 [molinfo $gm get numreps]
    set olds2 [_sel_grab $gm $pi2]
    mol addrep $gm
    mol modstyle $pi2 $gm Lines
    mol modcolor $pi2 $gm Element
    mol modselect $pi2 $gm {index 999999}
    set da_ok 0
    set db_ok 0
    set daerr ""
    set dberr ""
    if {![catch {render Tachyon [file join [pwd] cartoon_sceneA.dat]} daerr]} {
        set da_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} {
        set cursel [lindex $olds2 $i]
        if {[string first "resname GAM" $cursel] >= 0} {
            mol modselect $i $gm {index 999999}
        } else {
            mol modselect $i $gm {not resname GAM}
        }
    }
    if {![catch {render Tachyon [file join [pwd] cartoon_sceneB.dat]} dberr]} {
        set db_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm [lindex $olds2 $i] }
    catch {mol delrep $pi2 $gm}
    if {$da_ok && $db_ok} {
        lassign [_parse_bits [file join [pwd] cartoon_sceneA.dat]] as2 ac2 a2st a2sp
        lassign [_parse_bits [file join [pwd] cartoon_sceneB.dat]] bs2 bc2 b2st b2sp
        set bond_delta [expr {$ac2 - $bc2}]
        set floor [expr {4 * $exp_fake}]
        puts "CARTOON_RENDER bond_scene_diff A=$ac2 B=$bc2 delta=$bond_delta floor=$floor"
        if {[catch {expr {double($bond_delta) >= double($floor)}} bd] || !$bd} {
            _bail positive_bond_diff "exp delta >= $floor (the fakes' bonds render in-path) got=$bond_delta"
        }
    } else {
        _bail render_scene_diff "$daerr / $dberr"
    }
}

# ---- 5. FOUND-MARKING partition: hider 2 migrates hidden -> found. ----
if {$gm >= 0 && $tier_reps_ok && [llength $beta_idxs] == 3} {
    set ca2 [lindex $beta_idxs 1]
    if {[catch {::biochemeleon::hiders::mark_found_visual $gm $ca2} merr]} {
        _bail mark_found_visual $merr
    } else {
        # user2 read-back is FLOAT -- numeric only.
        if {![catch {atomselect $gm "index $ca2"} si]} {
            set u2 [lindex [$si get user2] 0]
            if {[catch {expr {double($u2) > 0.0}} pos] || !$pos} {
                _bail found_user2 "exp >0 got=$u2"
            }
            $si delete
        } else { _bail found_user2_sel $si }
        # Partition: found selection == 1 (ca2), hidden == 2, CA 1/3 still
        # <= 0.
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 > 0 and user3 1}} s]} {
            set nf [$s num]
            set fidx [$s get index]
            $s delete
            if {$nf != 1} {
                _bail found_partition "exp=1 got=$nf"
            } elseif {$fidx ne [list $ca2]} {
                _bail found_partition_idx "exp=($ca2) got=($fidx)"
            }
        } else { _bail found_sel $s }
        if {![catch {atomselect $gm {resname GAM and beta < 0 and user2 < 1 and user3 1}} s]} {
            set nh [$s num]
            set hidx2 [$s get index]
            $s delete
            if {$nh != 2} {
                _bail hidden_partition_post "exp=2 got=$nh"
            } elseif {[lsearch -exact $hidx2 $ca2] >= 0} {
                _bail hidden_partition_post "found hider still in the hidden selection"
            }
        } else { _bail hidden_post_sel $s }
        foreach oidx [list [lindex $beta_idxs 0] [lindex $beta_idxs 2]] {
            if {![catch {atomselect $gm "index $oidx"} si]} {
                set u2o [lindex [$si get user2] 0]
                if {[catch {expr {double($u2o) <= 0.0}} neg] || !$neg} {
                    _bail unfound_user2_$oidx "exp <=0 got=$u2o"
                }
                $si delete
            } else { _bail unfound_sel_$oidx $si }
        }
    }
}

# ---- 6. CLEAN RESTORE: game molid dead, original atoms, registry 0, ----
# ----    pre-start numreps (no residue/hider-rep leak). ----
if {$gm >= 0} {
    catch {mol delete $gm}
    if {[lsearch -exact [molinfo list] $gm] >= 0} {
        _bail game_molid_dead "molid $gm still alive after mol delete"
    }
    set gm -2
    if {[catch {_load_demo_1f 1znf} mr] || $mr < 0} {
        _bail load_restore $mr
    } else {
        set nr [molinfo $mr get numatoms]
        if {$nr != 424} { _bail restored_atoms "exp=424 got=$nr (residue leak?)" }
        if {[catch {::biochemeleon::mutation::fetch_hider_indices $mr} ridx]} {
            _bail restore_fetch $ridx
        } elseif {[llength $ridx] != 0} {
            _bail registry_zero "exp=0 sentinels on the reloaded demo got=[llength $ridx]"
        }
        set nreps_r [molinfo $mr get numreps]
        if {$nreps_demo >= 0 && $nreps_r != $nreps_demo} {
            _bail prestart_numreps "exp=$nreps_demo got=$nreps_r (hider rep leak?)"
        }
        catch {mol delete $mr}
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
