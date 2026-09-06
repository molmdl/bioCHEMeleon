# vmd/smoke/phase17_splice_smoke.tcl
# Phase-17.2 (17.2-04) headless smoke: the RESidue-SPLICE mechanism end-to-end
# through the real mutation bridge -- the origin of the 17.2 render-diff
# harness (the four tier smokes 17.2-05..08 COPY this file's helpers:
# _parse_bits / _render_bits / _fetch_atoms_data / _dist).
#
# Proves, on demo 1znf (424 atoms):
#   1. GEOMETRY: make_residue_hiders 2 -> 2 {chain resid atoms} records; real
#      chain (never "G"/blank); resids {9001 9002}; N-first/CA-second atom
#      order; every fake atom exactly ~1.0 A from its anchor counterpart
#      (rigid translation) and fake N-CA distance == anchor N-CA distance.
#   2. WRITER: write_combined_pdb appends the residue records AFTER the simple
#      records with continuing serials; last 10 ATOM lines are 78 cols; beta
#      -999.0 on CA only / "  0.00" elsewhere; segid GAME; element emitted;
#      chain col == the record's chain; ZERO CONECT; exactly one END.
#   3. ROUND: mutate -> 434 atoms; `resname GAM and beta < 0` == 2 (CA-only
#      sentinel); GAM == 10; protein +10; CA structure == T (load-time STRIDE,
#      no ssrecalc anywhere); CA resids {9001 9002}; anchor chains + segid
#      GAME on all fakes; BOTH peptide junctions bonded (fake N has a bonded
#      C, fake C has a bonded N within the C-N bond cutoff).
#   4. BASELINE-ZERO render (harness proof) + POSITIVE control (in-path) +
#      NEGATIVE-A (chain-G fragment homogeneity, Pitfall C8) + NEGATIVE-B
#      (2.0 A over-displacement, Pitfall C1).
#   5. MIXED tagging: 2 bonded simple + 2 residue hiders in ONE mutate ->
#      beta<0 == 4 (2 simple + 2 CA), simple beta -999 preserved, residue
#      N/C/O/CB beta 0, user ordinals {0 1 2 3} over the beta set, segid GAME
#      on all 12 fake atoms.
#   6. RESTORE round-trip: snapshot -> mutate -> game filename ->
#      backup::restore -> 424 atoms (no residue leak).
#
# Tachyon technique (17.1-08 template, 17.2-04 harness origin): `axes location
# off` first; the probe rep is added LAST (highest index -- deleting it never
# renumbers earlier reps) and deleted after each render; every OTHER rep is
# emptied by modselect to a null selection for the render (mol showrep is
# IGNORED in text mode -- probe F6) and restored to "all" after; baseline-zero
# render (selection `index 999999` -> 0 primitives) proves the parser counts
# the real scene. Primitive tokens pinned from the research probes:
# FCylinder (Cartoon/Trace/Tube cylinders), STri (Cartoon sheet triangles),
# TriStrip (NewCartoon mesh), Sphere -- parsed with \m/word-boundary regexes
# so "TriStrip" can never false-match "STri" (the S is mid-word).
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
# silently). NEVER mol showrep (ignored in text mode).

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

# THE reusable 17.2 render helper (17.2-05..08 copy this): add a probe rep
# LAST (highest index), style+select it, EMPTY every earlier rep (showrep is
# ignored in text mode), render Tachyon, restore the earlier reps to "all",
# delete the probe rep (highest index -- never renumbers), return the parsed
# counts. `axes location off` must have been called once before the first
# render.
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

# Fetch a residue's present heavy backbone atoms in N/CA/C/O/CB order as
# {name element x y z} records (the splice::assemble_record shape) -- the
# smoke's rebuild helper for the negative controls.
proc _fetch_atoms_data {m ch rid} {
    set atoms [list]
    foreach nm {N CA C O CB} {
        set s [_pin [atomselect $m "chain $ch and resid $rid and name $nm"]]
        if {[$s num] >= 1} {
            lappend atoms [list $nm \
                [lindex [$s get element] 0] \
                [lindex [$s get x] 0] \
                [lindex [$s get y] 0] \
                [lindex [$s get z] 0]]
        }
        $s delete
    }
    return $atoms
}

# A residue's C atom index (for the next-N spatial query).
proc _res_c_index {m ch rid} {
    set s [_pin [atomselect $m "chain $ch and resid $rid and name C"]]
    set ci [lindex [$s get index] 0]
    $s delete
    return $ci
}

# The next residue's N coords (first N within 1.7 A of the anchor C -- the
# anchor's own N is ~2.4 A away, excluded).
proc _next_n_pt {m c_idx} {
    set s [_pin [atomselect $m "name N and within 1.7 of index $c_idx"]]
    set pt [list \
        [lindex [$s get x] 0] \
        [lindex [$s get y] 0] \
        [lindex [$s get z] 0]]
    $s delete
    return $pt
}

# THE 17.2 harness loader: load a demo COLLAPSED TO A SINGLE FRAME. 1znf
# ships 2 models; VMD lands on the last frame and UNPINNED coordinate reads
# are racy on multi-frame molecules (reads land on whatever frame is current
# -- the frame even drifts; dbg_pin probe). Collapse via a frame-0-pinned
# writepdb round-trip (the SAME pipeline mutate uses downstream) so every
# molecule in the smoke is single-frame and every read/write is deterministic
# frame-0 geometry. The 17.2 tier smokes (05-08) copy this helper.
proc _load_demo_1f {demo_id} {
    set m [::biochemeleon::demos::load_demo $demo_id]
    set tmp [file join [pwd] splice_load_collapse.pdb]
    set all [atomselect $m all]
    $all frame 0
    $all writepdb $tmp
    $all delete
    mol delete $m
    return [mol new $tmp type pdb waitfor all]
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

# REAR-JUNCTION SIGN SAFETY (mirrors make_residue_hiders): the raw
# splice::displacement is perpendicular to the FORWARD peptide bond, but its
# projection on the REAR bond vector (prev C -> anchor N) can stretch that
# junction past the 1.95 A C-N cutoff (half-bonded -> the dangling branch's
# bits do not render). Flip the sign when the rear projection is positive --
# the forward junction is sign-invariant, the rear can only shorten.
proc _rear_safe_d {m ch rid d atoms_data} {
    if {[llength $d] != 3} { return $d }
    set s [_pin [atomselect $m "chain $ch and resid $rid and name N"]]
    set nidx [lindex [$s get index] 0]
    $s delete
    if {$nidx < 0} { return $d }
    set p [_pin [atomselect $m "name C and within 1.7 of index $nidx"]]
    if {[$p num] < 1} { $p delete; return $d }
    set pcx [lindex [$p get x] 0]
    set pcy [lindex [$p get y] 0]
    set pcz [lindex [$p get z] 0]
    $p delete
    set anx -1
    foreach a $atoms_data {
        if {[lindex $a 0] eq "N"} {
            lassign [lrange $a 2 4] anx any anz
        }
    }
    if {$anx eq -1} { return $d }
    lassign $d ddx ddy ddz
    set proj [expr {$ddx * ($anx - $pcx) + $ddy * ($any - $pcy) \
        + $ddz * ($anz - $pcz)}]
    if {$proj > 0} {
        return [list [expr {-1.0 * $ddx}] [expr {-1.0 * $ddy}] [expr {-1.0 * $ddz}]]
    }
    return $d
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
set ggm -1
set ogm -1
set gm2 -1
set m3 -1
set gm3 -1
set rm3 -1
set recs [list]
set n0 -1
set real_protein -1
set outpdb [file join [pwd] splice_combined_probe.pdb]

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

# ---- 1. GEOMETRY: load 1znf, make 2 residue hiders, assert the records. ----
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
    # Retry loop: 1znf is a COMPACT fold -- the greedy 5.0 A anchor
    # separation rejects the 2nd draw often (~half the runs under-generate
    # to 1). The mechanism behavior is correct (under-generation tolerated,
    # vmdcon-warned); the smoke needs 2 records for the multi-hider
    # bookkeeping, so re-draw until 2 (max 6 attempts).
    set recs [list]
    for {set att 0} {$att < 6} {incr att} {
        if {![catch {::biochemeleon::mutation::make_residue_hiders $m0 2} recs]} {
            if {[llength $recs] == 2} { break }
        } else {
            _bail make_residue_hiders $recs
            set recs [list]
            break
        }
    }
}
if {[llength $recs] != 2} {
    _bail rec_count "exp=2 got=[llength $recs]"
} else {
    # Records carry the FAKE resid (9001+k); the ANCHOR residue is derived
    # geometrically: the nearest real CA to the fake CA sits exactly 1.0 A
    # away (rigid translation), every other real CA is >= ~2.8 A out.
    set catab [_ca_table $m0]
    set anchor_list [list]
    set partner_list [list]
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
        # resid from the disjoint block.
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
        # Derive the anchor: nearest real CA to the fake CA.
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
            _bail ${tag}_anchor_dist "nearest real CA (resid $anch_res) at $best, exp 1.0 in [0.95,1.05]"
        }
        # Rigid translation: every fake atom sits ~1.0 A from its anchor
        # counterpart, and the fake N-CA distance == the anchor's (eps 1e-6).
        set fake_n [list]
        set fake_ca [list]
        set anch_n [list]
        set anch_ca [list]
        foreach a $atoms {
            lassign $a nm el x y z
            set s [_pin [atomselect $m0 "chain $anch_ch and resid $anch_res and name $nm"]]
            if {[$s num] < 1} {
                _bail ${tag}_anchor_missing "$nm missing on the anchor residue"
                $s delete
                continue
            }
            set apt [list [lindex [$s get x] 0] [lindex [$s get y] 0] [lindex [$s get z] 0]]
            $s delete
            set dd [_dist [list $x $y $z] $apt]
            if {[catch {expr {double($dd) >= 0.95 && double($dd) <= 1.05}} inband] || !$inband} {
                _bail ${tag}_disp_$nm "exp 1.0 A (0.95..1.05) got=$dd"
            }
            if {$nm eq "N"} {
                set fake_n [list $x $y $z]
                set anch_n $apt
            }
            if {$nm eq "CA"} {
                set fake_ca [list $x $y $z]
                set anch_ca $apt
            }
        }
        lappend anchor_list [list $anch_ch $anch_res]
        lappend partner_list [_junction_partners $m0 $anch_ch $anch_res]
        if {[llength $fake_n] == 3 && [llength $fake_ca] == 3 \
                && [llength $anch_n] == 3 && [llength $anch_ca] == 3} {
            set dfake [_dist $fake_n $fake_ca]
            set danch [_dist $anch_n $anch_ca]
            if {[catch {expr {abs(double($dfake) - double($danch)) < 1.0e-6}} geq] || !$geq} {
                _bail ${tag}_nca_geom "fake N-CA $dfake != anchor N-CA $danch (rigid translation broken)"
            }
        }
        incr k
    }
}

# ---- 2. WRITER: write combined PDB with residue records; assert the file. ----
if {$m0 >= 0 && [llength $recs] == 2} {
    if {[catch {::biochemeleon::mutation::write_combined_pdb $m0 [list] $outpdb $recs} werr]} {
        _bail write_combined_pdb $werr
    } else {
        if {![catch {open $outpdb r} fh]} {
            set dat [split [read $fh] \n]
            close $fh
            set atom_lines [list]
            set nconect 0
            set nend 0
            foreach l $dat {
                if {[string range $l 0 5] eq "ATOM  "} { lappend atom_lines $l }
                if {[string range $l 0 5] eq "CONECT"} { incr nconect }
                if {[string trim $l] eq "END"} { incr nend }
            }
            if {$nconect != 0} { _bail conect_count "exp=0 got=$nconect (Pitfall C7)" }
            if {$nend != 1} { _bail end_count "exp=1 got=$nend" }
            set nfa [llength $atom_lines]
            # Expected fake-line layout DERIVED FROM THE RECORDS (a GLY
            # anchor yields a 4-atom residue; never hardcode 5).
            set exp_atoms [list]
            foreach r $recs {
                foreach a [lindex $r 2] {
                    lappend exp_atoms [list [lindex $r 0] [lindex $r 1] [lindex $a 0]]
                }
            }
            set nfake_exp [llength $exp_atoms]
            set total_exp [expr {424 + $nfake_exp}]
            if {$nfa != $total_exp} {
                _bail atom_lines "exp=$total_exp got=$nfa"
            } else {
                # LAST nfake_exp ATOM lines = the fake records (appended
                # last; a trailing real ATOM record would shift the window).
                set lastf [lrange $atom_lines [expr {$nfa - $nfake_exp}] [expr {$nfa - 1}]]
                set resid_seen [list]
                set gi 0
                foreach l $lastf {
                    lassign [lindex $exp_atoms $gi] ech erid enm
                    incr gi
                    if {[string length $l] != 78} {
                        _bail line_len "exp=78 got=[string length $l]"
                    }
                    set nm [string trim [string range $l 12 15]]
                    if {$nm ne $enm} {
                        _bail file_name "exp=$enm got=$nm"
                    }
                    set beta [string range $l 60 65]
                    if {$nm eq "CA"} {
                        if {$beta ne "-999.0"} {
                            _bail ca_beta "exp=-999.0 got='$beta'"
                        }
                    } else {
                        if {$beta ne "  0.00"} {
                            _bail other_beta "exp='  0.00' got='$beta'"
                        }
                    }
                    if {[string range $l 72 75] ne "GAME"} {
                        _bail segid_col "exp=GAME got=[string range $l 72 75]"
                    }
                    if {[string trim [string range $l 76 77]] eq ""} {
                        _bail element_col "blank element on a fake atom"
                    }
                    set lch [string range $l 21 21]
                    if {$lch ne $ech} {
                        _bail chain_col "exp=$ech got='$lch'"
                    }
                    if {$nm eq "N"} {
                        lappend resid_seen [string trim [string range $l 22 25]]
                    }
                }
                set exp_resids [list]
                foreach r $recs { lappend exp_resids [lindex $r 1] }
                if {$resid_seen ne $exp_resids} {
                    _bail file_resids "exp=$exp_resids got=$resid_seen"
                }
            }
        } else {
            _bail read_outpdb $fh
        }
    }
}

# ---- 3. ROUND: mutate with residue records; assert the tagged molecule. ----
if {$m0 >= 0 && [llength $recs] == 2} {
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
    # CA-only sentinel: exactly ONE index per hider.
    if {[catch {::biochemeleon::mutation::fetch_hider_indices $gm} hidx]} {
        _bail fetch_idx $hidx
        set hidx [list]
    } elseif {[llength $hidx] != 2} {
        _bail fetch_count "exp=2 got=[llength $hidx] ($hidx)"
    }
    set beta_idxs [list]
    if {![catch {atomselect $gm {resname GAM and beta < 0}} s]} {
        set beta_idxs [$s get index]
        set nb [$s num]
        $s delete
        if {$nb != 2} { _bail sentinel_count "exp=2 got=$nb" }
        foreach i $beta_idxs {
            if {![catch {atomselect $gm "index $i"} si]} {
                set nm [lindex [$si get name] 0]
                if {$nm ne "CA"} { _bail sentinel_name_$i "exp=CA got=$nm" }
                $si delete
            } else { _bail sentinel_sel_$i $si }
        }
    } else { _bail sentinel_sel $s }
    # GAM total 10; protein +10.
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set ngam [$s num]
        $s delete
        if {$ngam != $exp_fake} { _bail gam_count "exp=$exp_fake got=$ngam" }
    } else { _bail gam_sel $s }
    if {![catch {atomselect $gm protein} s]} {
        set nprot [$s num]
        $s delete
        if {$nprot != $real_protein + $exp_fake} {
            _bail protein_count "exp=$real_protein+$exp_fake=[expr {$real_protein + $exp_fake}] got=$nprot"
        }
    } else { _bail protein_sel2 $s }
    # Load-time STRIDE assigned a coil/turn value (T turn or C coil) -- BOTH
    # render as the smooth tube (Option A). The exact letter is
    # anchor-dependent (STRIDE reads the displaced phi/psi geometry; the
    # research's resid-5 anchor read T, PRNG-chosen coil-region anchors read
    # C). NO ssrecalc anywhere in the flow -- the value is load-time.
    if {![catch {atomselect $gm {resname GAM and name CA}} s]} {
        set structs [$s get structure]
        set cads [$s get resid]
        $s delete
        foreach st $structs {
            if {$st ne "T" && $st ne "C"} {
                _bail ca_structure "exp T or C (coil/turn tube) got=$st"
            }
        }
        if {$cads ne [list 9001 9002]} {
            _bail ca_resids "exp={9001 9002} got=$cads"
        }
    } else { _bail ca_sel $s }
    # Per fake residue: anchor chain + segid GAME + BOTH junctions bonded.
    if {![catch {atomselect $gm {resname GAM}} s]} {
        set gidx [$s get index]
        set gres [$s get resid]
        set gchn [$s get chain]
        set gseg [$s get segid]
        set gnam [$s get name]
        $s delete
        set nfake [llength $gidx]
        if {$nfake != $exp_fake} { _bail gam_walk "exp=$exp_fake got=$nfake" }
        # Expected chain per resid from the records.
        set exp_chain [dict create]
        foreach r $recs {
            dict set exp_chain [lindex $r 1] [lindex $r 0]
        }
        for {set i 0} {$i < $nfake} {incr i} {
            set ii [lindex $gidx $i]
            set rr [lindex $gres $i]
            if {[lindex $gseg $i] ne "GAME"} {
                _bail fake_segid_$ii "exp=GAME got=[lindex $gseg $i]"
            }
            if {[lindex $gchn $i] ne [dict get $exp_chain $rr]} {
                _bail fake_chain_$ii "exp=[dict get $exp_chain $rr] got=[lindex $gchn $i]"
            }
        }
        # Junction law: for each fake resid, its N has a bonded C (prev
        # residue) and its C has a bonded N (next residue) within the C-N
        # bond cutoff (0.6*(1.70+1.55)=1.95; use 1.9 so ONLY bonded pairs
        # can match -- the load-time distance search bonded everything < 1.95).
        set fi -1
        foreach rr [list 9001 9002] {
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
            # Scoped to the EXACT partner resids (prev C's residue for the
            # fake N, next N's residue for the fake C): a compact fold puts
            # other residues' C/N atoms within 1.9 A of a displaced fake,
            # and the anchor's own C can sit within 1.9 of the fake N (a
            # spurious cross-bond, not a peptide junction).
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
}

# ---- 4. RENDER CONTROLS: baseline-zero + POSITIVE + NEGATIVE-A/B. ----
# 4a. Baseline-zero (harness proof): a null selection renders 0 primitives of
#     every kind -- the parser really counts the scene.
if {$gm >= 0} {
    if {![catch {_render_bits $gm Cartoon {index 999999} [file join [pwd] splice_base.dat]} bbits]} {
        lassign $bbits bs bc bst bstr
        if {$bs != 0 || $bc != 0 || $bst != 0 || $bstr != 0} {
            _bail baseline_zero "exp=0/0/0/0 got=$bs/$bc/$bst/$bstr"
        }
    } else { _bail render_base $bbits }
}
# 4b. POSITIVE control (in-path): the anchor of record 1 = the nearest real CA
#     to the fake CA (exactly 1.0 A away; every other real CA is >= ~2.8 A).
set anch_resid -1
set anch_chain ""
set s1c -2
set s2c -2
set c1c -2
if {$gm >= 0 && [llength $beta_idxs] == 2} {
    set fakeca1 [lindex $beta_idxs 0]
    # NOTE: the `within` reference must be PARENTHESIZED -- VMD's within
    # swallows the trailing expression (`... of index N and not index N`
    # parses as within-of-an-empty-selection -> 0 hits; the diagnostic run
    # proved the anchor CA sits at 1.0004 A).
    if {![catch {atomselect $gm "name CA and (within 2.0 of index $fakeca1) and not index $fakeca1"} asel]} {
        $asel frame 0
        set na [$asel num]
        if {$na != 1} {
            set fcs [_pin [atomselect $gm "index $fakeca1"]]
            set ffx [lindex [$fcs get x] 0]
            set ffy [lindex [$fcs get y] 0]
            set ffz [lindex [$fcs get z] 0]
            $fcs delete
            set mind 1e9
            foreach c $catab {
                lassign $c cr cc cx cy cz
                set dd [_dist [list $ffx $ffy $ffz] [list $cx $cy $cz]]
                if {$dd < $mind} { set mind $dd; set mres $cr }
            }
            _bail anchor_lookup "exp=1 nearest real CA got=$na (fakeca1=$fakeca1 minCA-dist=[format %.4f $mind] at resid $mres -- NOTE catab is from the ORIGINAL frame-0; game mol is the combined PDB)"
        } else {
            set anch_resid [lindex [$asel get resid] 0]
            set anch_chain [lindex [$asel get chain] 0]
        }
        $asel delete
    } else { _bail anchor_sel $asel }
}
if {$gm >= 0 && $anch_resid > 0} {
    set wlo [_wlo $anch_resid]
    set whi [expr {$anch_resid + 2}]
    set winsel "resid $wlo to $whi"
    # Spliced window render (plan-literal selection: real resids only).
    if {![catch {_render_bits $gm Cartoon $winsel [file join [pwd] splice_win.dat]} sw]} {
        lassign $sw s1s s1c s1st s1str
        puts "SPLICE_POS spliced_window={$winsel} nsph=$s1s ncyl=$s1c nstri=$s1st nstrip=$s1str"
    } else { _bail render_spliced_win $sw; set s1c -1 }
    # Fake-inclusive window render (disjoint-resid adaptation evidence).
    if {![catch {_render_bits $gm Cartoon "$winsel or segid GAME" [file join [pwd] splice_win_fake.dat]} sw2]} {
        lassign $sw2 s2s s2c s2st s2str
        puts "SPLICE_POS spliced_window_plus_fake nsph=$s2s ncyl=$s2c nstri=$s2st nstrip=$s2str"
    } else { _bail render_spliced_win_fake $sw2; set s2c -1 }
    # GAME-only bits (the bump renders at all -- contrast with NEGATIVE-A).
    if {![catch {_render_bits $gm Cartoon {segid GAME} [file join [pwd] splice_game.dat]} sg]} {
        lassign $sg s3s s3c s3st s3str
        puts "SPLICE_POS gameonly nsph=$s3s ncyl=$s3c nstri=$s3st nstrip=$s3str"
        if {$s3c < 1} { _bail gameonly_bits "exp>=1 FCylinder got=$s3c" }
    } else { _bail render_gameonly $sg }
    # Unspliced control: the SAME frame-0 collapse pipeline as the splice
    # molecules (_load_demo_1f == the mutate pipeline minus hiders). A raw
    # load_demo renders the demo's LAST frame geometry while every
    # mutate-pipeline molecule is the frame-0 collapse -- different NMR-model
    # geometry gives DIFFERENT STRIDE/cartoon counts (observed 30 vs 24 for
    # the same window), so the control MUST be collapsed identically.
    if {[catch {_load_demo_1f 1znf} mc]} {
        _bail load_control $mc
        set mc -1
    } else {
        if {![catch {_render_bits $mc Cartoon $winsel [file join [pwd] splice_ctrl.dat]} cw]} {
            lassign $cw c1s c1c c1st c1str
            puts "SPLICE_POS control_window nsph=$c1s ncyl=$c1c nstri=$c1st nstrip=$c1str"
        } else { _bail render_ctrl_win $cw; set c1c -1 }
        # The control molecule is spent -- delete it so later renders are
        # never polluted (belt-and-suspenders with _render_bits isolation).
        catch {mol delete $mc}
        set mc -2
    }
    # POSITIVE assertions (in-path). RENDER TRUTH (run-20 lesson): the
    # cartoon window counts are ss-SHIFT-VARIANT -- inserting the fake into
    # a helix run splits the run and the window can CRASH below the control
    # (22 -> 6 observed) with ZERO pathology -- so NO cross-molecule window
    # comparison is asserted. The robust render proof is the 17.1-08 BOND
    # SCENE-DIFF (ss-independent): the scene rep renders A=all vs
    # B=not resname GAM; the cylinder delta == the fake residues' bond count
    # (junction + intra-residue stubs, both-endpoints rule) >= 4 per fake.
    # Together with the junction bonds (step 3) and the fake's own rendered
    # bits (gameonly >= 1) this is the in-path evidence.
    set pi2 [molinfo $gm get numreps]
    mol addrep $gm
    mol modstyle $pi2 $gm Lines
    mol modcolor $pi2 $gm Element
    mol modselect $pi2 $gm {index 999999}
    set da_ok 0
    set db_ok 0
    set daerr ""
    set dberr ""
    if {![catch {render Tachyon [file join [pwd] splice_sceneA.dat]} daerr]} {
        set da_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm {not resname GAM} }
    if {![catch {render Tachyon [file join [pwd] splice_sceneB.dat]} dberr]} {
        set db_ok 1
    }
    for {set i 0} {$i < $pi2} {incr i} { mol modselect $i $gm all }
    catch {mol delrep $pi2 $gm}
    if {$da_ok && $db_ok} {
        lassign [_parse_bits [file join [pwd] splice_sceneA.dat]] as2 ac2 a2st a2sp
        lassign [_parse_bits [file join [pwd] splice_sceneB.dat]] bs2 bc2 b2st b2sp
        set bond_delta [expr {$ac2 - $bc2}]
        set floor [expr {4 * $exp_fake}]
        puts "SPLICE_POS bond_scene_diff A=$ac2 B=$bc2 delta=$bond_delta floor=$floor"
        if {[catch {expr {double($bond_delta) >= double($floor)}} bd] || !$bd} {
            _bail positive_bond_diff "exp delta >= $floor (the fakes' bonds render) got=$bond_delta"
        }
    } else {
        _bail render_scene_diff "$daerr / $dberr"
    }
    if {$s2c > $c1c} {
        puts "SPLICE_POS window_delta bonus: fake-incl $s2c > control $c1c (window-only $s1c vs $c1c)"
    } else {
        puts "SPLICE_POS window_delta NOTE: fake-incl $s2c <= control $c1c (ss-shift variance, not asserted)"
    }
}

# 4c. NEGATIVE-A (chain-G, Pitfall C8): fresh load; rebuild record 1 with
#     chain "G" (same displacement recomputed) -> splice lands (5 GAM atoms)
#     but the GAME-only Cartoon render draws 0 bits (separate fragment, never
#     traced).
if {[catch {_load_demo_1f 1znf} m_g]} {
    _bail load_negA $m_g
    set m_g -1
}
if {$m_g >= 0 && [llength $recs] == 2} {
    lassign [lindex $anchor_list 0] gch grid
    if {![catch {_fetch_atoms_data $m_g $gch $grid} gdata] \
            && [llength $gdata] >= 4} {
        set gci [_res_c_index $m_g $gch $grid]
        set gpt [_next_n_pt $m_g $gci]
        # Anchor C coords from the refetched atoms_data.
        set gcpt [list]
        foreach a $gdata {
            if {[lindex $a 0] eq "C"} {
                set gcpt [list [lindex $a 2] [lindex $a 3] [lindex $a 4]]
            }
        }
        if {[catch {::biochemeleon::splice::displacement $gcpt $gpt} gd]} {
            _bail negA_displacement $gd
        } elseif {![catch {_rear_safe_d $m_g $gch $grid $gd $gdata} gd] \
            && ![catch {::biochemeleon::splice::assemble_record $gdata "G" 9003 $gd} grec]} {
            if {[catch {::biochemeleon::mutation::mutate $m_g [list] [list $grec]} ggm]} {
                _bail negA_mutate $ggm
                set ggm -1
            }
        } else { _bail negA_assemble $grec }
    } else { _bail negA_atoms_data $gdata }
}
if {$ggm >= 0} {
    if {![catch {atomselect $ggm {resname GAM}} s]} {
        set ng [$s num]
        $s delete
        set exp_ng [llength [lindex $grec 2]]
        if {$ng != $exp_ng} { _bail negA_gam_count "exp=$exp_ng got=$ng" }
    } else { _bail negA_gam_sel $s }
    # PITFALL-C8 VERIFICATION OUTCOME (research ASSUMED, this smoke tested):
    # a chain-G splice is NOT a separate fragment. VMD's distance bonds
    # ignore chain ids and fragments are bond-connected, so the mismatched
    # fake BONDS into the chain, RENDERS its bits (6 GAME-only FCyl -- the
    # assumed 0-bit signature is falsified), and even SHIFTS the fragment's
    # STRIDE assignment (its window reads 15 vs the control 18 in run 9 --
    # the SAME shift the chain-A splice causes). The window render is
    # ss-shift-variant and asserted NOWHERE; the robust facts are asserted:
    if {![catch {_render_bits $ggm Cartoon {segid GAME} [file join [pwd] splice_gamerec.dat]} gab]} {
        lassign $gab gas gac gast gastr
        puts "SPLICE_NEGA chainG_gameonly nsph=$gas ncyl=$gac nstri=$gast nstrip=$gastr"
        if {$gac < 1} {
            _bail negative_a_bits "chain-G GAME-only bits vanished (got=$gac; observed 6 in every evidence run)"
        }
    } else { _bail render_negA $gab }
    # ... and the junctions still form across the chain mismatch.
    set gn_idx -1
    set gc_idx -1
    if {![catch {atomselect $ggm {resname GAM}} s]} {
        set ggidx [$s get index]
        set ggnam [$s get name]
        $s delete
        for {set i 0} {$i < [llength $ggidx]} {incr i} {
            if {[lindex $ggnam $i] eq "N"} { set gn_idx [lindex $ggidx $i] }
            if {[lindex $ggnam $i] eq "C"} { set gc_idx [lindex $ggidx $i] }
        }
    } else { _bail negA_junc_sel $s }
    set gbonded 0
    lassign [lindex $partner_list 0] gaprev ganext
    if {$gn_idx >= 0 && $gaprev >= 0} {
        if {![catch {atomselect $ggm "name C and (within 1.9 of index $gn_idx) and resid $gaprev"} js]} {
            if {[$js num] >= 1} { set gbonded 1 }
            $js delete
        } else { _bail negA_junc_sel_n $js }
    }
    if {$gc_idx >= 0 && !$gbonded && $ganext >= 0} {
        if {![catch {atomselect $ggm "name N and (within 1.9 of index $gc_idx) and resid $ganext"} js]} {
            if {[$js num] >= 1} { set gbonded 1 }
            $js delete
        } else { _bail negA_junc_sel_c $js }
    }
    if {!$gbonded} {
        _bail negative_a_junction "chain-G fake bonded to NO chain atom (fragment isolation after all?)"
    }
    # Window render: recorded, never asserted (ss-shift variance).
    if {$anch_resid > 0} {
        set wlo [_wlo $anch_resid]
        set whi [expr {$anch_resid + 2}]
        if {![catch {_render_bits $ggm Cartoon "resid $wlo to $whi" [file join [pwd] splice_gamewin.dat]} gaw]} {
            lassign $gaw gaws gawc gawst gawstr
            puts "SPLICE_NEGA chainG_window ncyl=$gawc control=$c1c (ss-shift variance, not asserted)"
        } else { _bail render_negA_win $gaw }
    }
}

# 4d. NEGATIVE-B (over-displacement, Pitfall C1): fresh load; rebuild record 1
#     with a 2.0 A displacement (each component scaled x2.0) -> the window
#     render DEGRADES below the step-4 control (the half-bonded pathology is
#     headlessly detectable).
if {[catch {_load_demo_1f 1znf} m_o2]} {
    _bail load_negB $m_o2
    set m_o2 -1
}
if {$m_o2 >= 0 && $anch_resid > 0 && [llength $recs] == 2} {
    lassign [lindex $anchor_list 0] och orid
    if {![catch {_fetch_atoms_data $m_o2 $och $orid} odata] \
            && [llength $odata] >= 4} {
        set oci [_res_c_index $m_o2 $och $orid]
        set opt [_next_n_pt $m_o2 $oci]
        set ocpt [list]
        foreach a $odata {
            if {[lindex $a 0] eq "C"} {
                set ocpt [list [lindex $a 2] [lindex $a 3] [lindex $a 4]]
            }
        }
        if {[catch {::biochemeleon::splice::displacement $ocpt $opt} od]} {
            _bail negB_displacement $od
        } elseif {![catch {_rear_safe_d $m_o2 $och $orid $od $odata} od]} {
            lassign $od odx ody odz
            set od2 [list \
                [expr {double($odx) * 2.0}] \
                [expr {double($ody) * 2.0}] \
                [expr {double($odz) * 2.0}]]
            if {![catch {::biochemeleon::splice::assemble_record $odata $och 9004 $od2} orec]} {
                if {[catch {::biochemeleon::mutation::mutate $m_o2 [list] [list $orec]} ogm]} {
                    _bail negB_mutate $ogm
                    set ogm -1
                }
            } else { _bail negB_assemble $orec }
        }
    } else { _bail negB_atoms_data $odata }
}
if {$ogm >= 0 && $anch_resid > 0} {
    # Junction evidence FIRST (the deterministic over-displacement detector):
    # at 2.0 A the junction distances (~2.40 A) exceed the 1.95 A C-N cutoff.
    # The research's window-DROPS-below-control signature is the HALF-BONDED
    # band (~1.44 A, PP14) and is anchor-dependent at 2.0 (this anchor fully
    # detaches) -- so the smoke asserts AT LEAST ONE junction lost, plus the
    # real chain's window untouched (full break) or degraded (half bond).
    set n_idx -1
    set c_idx -1
    if {![catch {atomselect $ogm {resname GAM}} s]} {
        set gidx [$s get index]
        set gnam [$s get name]
        $s delete
        for {set i 0} {$i < [llength $gidx]} {incr i} {
            if {[lindex $gnam $i] eq "N"} { set n_idx [lindex $gidx $i] }
            if {[lindex $gnam $i] eq "C"} { set c_idx [lindex $gidx $i] }
        }
    } else { _bail negB_gam_sel $s }
    set broke 0
    lassign [lindex $partner_list 0] nbprev nbnext
    if {$n_idx >= 0 && $nbprev >= 0} {
        if {![catch {atomselect $ogm "name C and (within 1.9 of index $n_idx) and resid $nbprev"} js]} {
            if {[$js num] < 1} { set broke 1 }
            $js delete
        } else { _bail negB_junc_sel_n $js }
    }
    if {$c_idx >= 0 && $nbnext >= 0} {
        if {![catch {atomselect $ogm "name N and (within 1.9 of index $c_idx) and resid $nbnext"} js]} {
            if {[$js num] < 1} { set broke 1 }
            $js delete
        } else { _bail negB_junc_sel_c $js }
    }
    if {!$broke} {
        _bail negative_b_junction "2.0 A splice kept BOTH junctions bonded (over-displacement undetected)"
    }
    set wlo [_wlo $anch_resid]
    set whi [expr {$anch_resid + 2}]
    if {![catch {_render_bits $ogm Cartoon "resid $wlo to $whi" [file join [pwd] splice_over.dat]} ob]} {
        lassign $ob obs obc obst obstr
        puts "SPLICE_NEGB over2A_window nsph=$obs ncyl=$obc nstri=$obst nstrip=$obstr control=$c1c"
        if {[catch {expr {double($obc) <= double($c1c)}} dec] || !$dec} {
            _bail negative_b "exp over-2A window $obc <= control $c1c (real path improved? half-bonded?)"
        }
    } else { _bail render_negB $ob }
    # GAME-only + fake-inclusive counts for the signature record (lone
    # residue bits render even when detached -- NOT a breakage detector).
    if {![catch {_render_bits $ogm Cartoon {segid GAME} [file join [pwd] splice_over_game.dat]} obg]} {
        lassign $obg obgs obgc obgst obgstr
        puts "SPLICE_NEGB over2A_gameonly ncyl=$obgc"
    } else { _bail render_negB_game $obg }
    if {![catch {_render_bits $ogm Cartoon "resid $wlo to $whi or segid GAME" [file join [pwd] splice_over_fake.dat]} obf]} {
        lassign $obf obfs obfc obfst obgstr2
        puts "SPLICE_NEGB over2A_fake_incl ncyl=$obfc (1.0 A in-path was $s2c)"
    } else { _bail render_negB_fake $obf }
}

# ---- 5. MIXED tagging: 2 bonded simple + 2 residue hiders in ONE mutate. ----
if {[catch {_load_demo_1f 1znf} m2]} {
    _bail load_mixed $m2
    set m2 -1
}
set srecs [list]
set rrecs2 [list]
if {$m2 >= 0} {
    if {[catch {::biochemeleon::mutation::make_bonded_hiders $m2 2} srecs]} {
        _bail make_bonded_hiders $srecs
        set srecs [list]
    }
    if {[catch {::biochemeleon::mutation::make_residue_hiders $m2 2} rrecs2]} {
        _bail make_residue_hiders_mixed $rrecs2
        set rrecs2 [list]
    }
}
if {$m2 >= 0 && [llength $srecs] == 2 && [llength $rrecs2] == 2} {
    if {[catch {::biochemeleon::mutation::mutate $m2 $srecs $rrecs2} gm2]} {
        _bail mutate_mixed $gm2
        set gm2 -1
    }
}
if {$gm2 >= 0} {
    set exp_mixed [expr {424 + [llength $srecs] + [_rec_atom_total $rrecs2]}]
    set n2 [molinfo $gm2 get numatoms]
    if {$n2 != $exp_mixed} { _bail mixed_atoms "exp=$exp_mixed got=$n2" }
    # Derive the expected index layout from the records (mirrors
    # tag_sentinels_mixed: n_simple single atoms, then each residue's atoms
    # in N-first/CA-second record order).
    set exp_beta [list]
    set exp_other [list]
    for {set i 0} {$i < [llength $srecs]} {incr i} {
        lappend exp_beta [expr {424 + $i}]
    }
    set cur [expr {424 + [llength $srecs]}]
    set exp_cas [list]
    foreach r $rrecs2 {
        foreach a [lindex $r 2] {
            if {[lindex $a 0] eq "CA"} {
                lappend exp_beta $cur
                lappend exp_cas $cur
            } else {
                lappend exp_other $cur
            }
            incr cur
        }
    }
    if {![catch {::biochemeleon::mutation::fetch_hider_indices $gm2} midx]} {
        if {$midx ne $exp_beta} {
            _bail mixed_fetch "exp=$exp_beta got=$midx"
        }
    } else { _bail mixed_fetch_sel $midx }
    # Simple atoms keep beta -999 (the rescue path).
    foreach i [lrange $exp_beta 0 1] {
        if {![catch {atomselect $gm2 "index $i"} si]} {
            set b [lindex [$si get beta] 0]
            if {![_feq $b -999.0]} { _bail mixed_simple_beta_$i "exp=-999 got=$b" }
            $si delete
        } else { _bail mixed_simple_sel_$i $si }
    }
    # Residue N/C/O/CB carry beta 0.
    foreach i $exp_other {
        if {![catch {atomselect $gm2 "index $i"} si]} {
            set b [lindex [$si get beta] 0]
            if {[catch {expr {abs(double($b)) < 1.0e-6}} z] || !$z} {
                _bail mixed_other_beta_$i "exp=0 got=$b"
            }
            $si delete
        } else { _bail mixed_other_sel_$i $si }
    }
    # User ordinals over the beta set, file order == 0..k-1 (the count
    # derives from the records -- under-generation tolerated).
    if {![catch {atomselect $gm2 {resname GAM and beta < 0}} si]} {
        set bidx [$si get index]
        set busr [$si get user]
        $si delete
        set exp_ords [list]
        set ou 0
        foreach _b $exp_beta { lappend exp_ords [expr {double($ou)}]; incr ou }
        if {[llength $busr] != [llength $exp_beta]} {
            _bail mixed_user_count "exp=[llength $exp_beta] got=[llength $busr]"
        } else {
            foreach u $busr o $exp_ords {
                if {![_feq $u $o]} { _bail mixed_user "exp=$o got=$u (full=$busr)" }
            }
        }
    } else { _bail mixed_user_sel $si }
    # segid GAME on ALL 12 fake atoms.
    if {![catch {atomselect $gm2 {resname GAM}} si]} {
        set allseg [$si get segid]
        set nall [$si num]
        $si delete
        set exp_mgam [expr {[llength $srecs] + [_rec_atom_total $rrecs2]}]
        if {$nall != $exp_mgam} { _bail mixed_gam_count "exp=$exp_mgam got=$nall" }
        foreach sg $allseg {
            if {$sg ne "GAME"} { _bail mixed_segid "exp=GAME got=$sg" }
        }
    } else { _bail mixed_gam_sel $si }
}

# ---- 6. RESTORE round-trip: snapshot -> mutate -> restore -> 424 atoms. ----
if {[catch {_load_demo_1f 1znf} m3]} {
    _bail load_restore $m3
    set m3 -1
}
if {$m3 >= 0} {
    if {[catch {::biochemeleon::backup::snapshot $m3} snap]} {
        _bail snapshot $snap
        set snap [list]
    }
    if {[catch {::biochemeleon::mutation::make_residue_hiders $m3 1} recs3]} {
        _bail make_residue_hiders_restore $recs3
        set recs3 [list]
    }
    if {[llength $recs3] == 1} {
        if {[catch {::biochemeleon::mutation::mutate $m3 [list] $recs3} gm3]} {
            _bail mutate_restore $gm3
            set gm3 -1
        }
    } else {
        _bail restore_recs "exp=1 got=[llength $recs3]"
    }
}
if {$gm3 >= 0 && [info exists snap] && [llength $snap] > 0} {
    if {[catch {molinfo $gm3 get filename} gfn]} {
        _bail game_filename $gfn
    } else {
        if {![string match "*biochemeleon_game.pdb" $gfn]} {
            _bail game_filename "exp=*biochemeleon_game.pdb got=$gfn"
        }
    }
    if {[catch {::biochemeleon::backup::restore $snap $gm3} rm3]} {
        _bail restore $rm3
        set rm3 -1
    } else {
        if {[catch {molinfo $rm3 get numatoms} rn]} {
            _bail restored_atoms $rn
        } elseif {$rn != 424} {
            _bail restored_atoms "exp=424 got=$rn (residue leak?)"
        }
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
