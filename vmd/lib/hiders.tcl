# vmd/lib/hiders.tcl -- MOL BRIDGE: N-tier hider rendering + found-marking
# visuals (generalized 17.1-04 from the Phase-16 single VDW pair).
#
# Purpose: the VISUAL half of the hider mechanic (HIDER-03/HIDER-06 +
# LOOP-01). VMD colors/styles per-REP, not per-atom (FEATURES.md:77) -- there
# is NO per-atom color or style override -- so a Lines-tier hider must render
# in a Lines rep to blend, a VDW-tier hider in a VDW rep, etc. The design
# (research rep-infra RQ4, probe3-verified end-to-end) is ONE hidden/found rep
# PAIR per ACTIVE tier (2N reps total), with STATIC per-tier selections:
#   hidden tier-t: <tier style> + Element coloring
#                  + {resname GAM and beta < 0 and user2 < 1 and user3 <t>}
#   found  tier-t: <tier style> + ColorID 7 (green)
#                  + {resname GAM and beta < 0 and user2 > 0 and user3 <t>}
#
# TIER CODES: user3 is the per-atom tier channel (probe-verified: settable on
# multi-atom selections with a NUMERIC scalar -- non-numeric errors, P7;
# selectable exact-match `user3 1`; read-back is FLOAT 1.0 -- compare
# numerically only, P10). stamp_tier_codes writes the codes; add_hider_reps
# builds the pairs; the caller (game.tcl 17.1-06) owns the tier-spec table
# (code/style/indices from the dispatch split). Real atoms default user3=0 --
# the sentinel conjunct `resname GAM and beta < 0` is VERBATIM in every
# selection and is NEVER relaxed (P6: `user2 < 1`/`user3 <t>` alone would
# match all real atoms).
#
# ORDERING CONTRACT (enforced by game.tcl 17.1-06): stamp_tier_codes MUST run
# BEFORE add_hider_reps. Rep selections re-evaluate per TIMESTEP only -- a
# static single-frame molecule NEVER re-evaluates a rep's cached selection
# when an atom field changes -- so a rep added before its tier's user3 codes
# were stamped would cache an EMPTY selection forever. Stamp, then add.
#
# NAME-KEYED TRACKING (replaces the Phase-16 hidden_rep/found_rep INDEX
# vars -- see the 17.1-07 note below): rep names are MONOTONIC and never
# reset (P1), and `mol repindex $m $name` resolves a name to its CURRENT
# index (returns -1, no error, for deleted/unknown names -- P2) while
# `mol repname $m $idx` ERRORS on an out-of-range index. add_hider_reps
# captures each rep's name via `mol repname` IMMEDIATELY AFTER its addrep
# (post-apply names are the only live ones -- a pre-apply name is dead, P1)
# and stores it in tier_reps; mark_found_visual resolves names via repindex
# AT USE TIME with a -1/out-of-range guard. Indices are NEVER cached across
# rep mutations (Pitfall 9: delrep renumbers; clonerep.tcl:92-96).
#
#   tier_reps  : tier_code -> {hidden_name found_name hidden_sel found_sel}
#   tier_styles: tier_code -> style string ([join $sargs " "], e.g. "VDW"
#                or "DynamicBonds 1.6")
# Both dicts are RESET at the top of add_hider_reps: they describe the pairs
# of the CURRENT call (one call per round in production). Keeping entries
# from a prior round would poison mark_found_visual's all-pairs re-assert on
# the next round's molecule (the old round's names resolve to -1 there).
#
# 17.1-07 NOTE (known red): this plan REPLACES hidden_rep/found_rep.
# vmd/smoke/phase16_smoke.tcl (~212-213) and vmd/tests/pick_verify.tcl read
# those namespace vars, and vmd/smoke/phase16_hiders_smoke.tcl asserts the
# pre-17.1 selection strings (no user3 conjunct) -- all three go red until
# 17.1-07 updates them. NO compat shims are provided (the new dict contract
# is the only contract).
#
# STYLE VALIDATION IS READ-BACK, NEVER catch (viability P-1): `mol modstyle`
# with a bad style NEVER raises -- it prints an ERROR) to the VMD console and
# silently no-ops (or falls back). add_hider_reps therefore reads every rep
# back via the COMBINED-BRACES molinfo form (the single-field form FAILS --
# Pitfall 3) and string-compares style + selection; any mismatch is a hard
# error. Callers pass style args from rep_tiers::style_args (validated
# GAME_REPS spellings); this module sources NOTHING (standalone, like
# backup.tcl) and does NOT source rep_tiers.
#
# NEVER HIDE A REP: UG node140 -- "Hidden reps cannot be picked and do not
# show any graphics." Pickability is per-REP; hiding either hider rep would
# make its hiders unclickable. NO showrep call exists in this module and
# neither rep is EVER hidden during play. Found hiders stay visible (green)
# -> still pickable -> double-count prevention is the CALLER's registry-
# status guard (registry::mark_found is idempotent).
#
# NEVER WRITE BETA: the sentinel selector "resname GAM and beta < 0" must
# keep matching ALL hiders (registry reconstruct + cleanup both depend on
# it). Found flags live ONLY in user2 ("user" is taken -- tag_sentinels
# stores ordinals there; user3 carries tier codes); beta stays -999 forever.
#
# MANDATORY modselect RE-ASSERT: after EVERY user2 write, mark_found_visual
# re-issues modselect for ALL tracked pairs with the UNCHANGED literal
# strings stored in tier_reps (timestep-based re-eval only; a static
# molecule never re-evaluates on an atom-field change -- probe F17). The
# strings are stored at add time precisely so they are literally unchanged
# at re-assert time. Re-asserting ALL pairs (vs only the picked hider's
# tier) avoids a tier lookup here and keeps the unchanged-string contract
# trivial; <= 2N modselects at the 50-hider cap is idempotent and ~free.
#
# Tcl 8.5 ONLY (no 8.6 control-flow idioms; brace all expr; one `variable`
# per line -- the multi-name form is a name-VALUE pair, not a link, 14-04).
# Sentinel selector strings are built verbatim. Every atomselect is $sel
# delete'd.

namespace eval ::biochemeleon::hiders {
    namespace export add_hider_reps stamp_tier_codes mark_found_visual
    # Name-keyed pair tracking: tier_code -> {hidden_name found_name
    # hidden_sel found_sel}. Reset (not merged) by every add_hider_reps call
    # -- see header.
    variable tier_reps [dict create]
    # Style strings this module last applied: tier_code -> style string.
    variable tier_styles [dict create]
}

# add_hider_reps {molid {tier_specs {{1 VDW}}}} -> tier_reps dict.
#
# Adds ONE hidden/found rep pair per tier in tier_specs (ordered) to the game
# molid and records name-keyed tracking. tier_specs is a list of
# `{code styleArg1 styleArg2 ...}` entries, e.g.:
#   {{1 VDW}}                      -- Phase-16-compatible single VDW pair
#   {{1 VDW} {2 Lines}}            -- 2 tiers, 4 reps
#   {{2 DynamicBonds 1.6}}         -- args pass straight through to modstyle
# code is a 1-based int (the user3 tier code); the style args are the
# modstyle arg list (caller supplies validated GAME_REPS spellings via
# rep_tiers::style_args). Call AFTER backup::apply (hider reps land LAST:
# base..base+2N-1, base = numreps after apply -- deterministic per round)
# and AFTER stamp_tier_codes (ORDERING CONTRACT -- see header).
#
# Every rep is VALIDATED by read-back string-compare (style == joined args,
# selection == the exact built string, index in range) -- a bad style never
# raises from modstyle, so read-back is the only reliable gate (P-1).
# Returns the tier_reps dict. NO showrep calls anywhere -- both reps of every
# pair stay SHOWN (UG node140: a hidden rep cannot be picked).
proc ::biochemeleon::hiders::add_hider_reps {molid {tier_specs {{1 VDW}}}} {
    variable tier_reps
    variable tier_styles
    # Reset per call: these dicts describe THIS call's pairs only (stale
    # entries from a prior round would resolve to -1 on the new molecule and
    # break mark_found_visual's all-pairs re-assert).
    set tier_reps [dict create]
    set tier_styles [dict create]
    # Base index = numreps AFTER backup::apply (deterministic per round).
    set base [molinfo $molid get numreps]
    set k 0
    foreach spec $tier_specs {
        set code [lindex $spec 0]
        set sargs [lrange $spec 1 end]
        if {![string is integer -strict $code] || $code < 1} {
            error "hiders::add_hider_reps: tier code '$code' is not a 1-based integer (spec: $spec)"
        }
        if {[llength $sargs] == 0} {
            error "hiders::add_hider_reps: tier spec '$spec' carries no style args"
        }
        # The style STRING the read-back must echo (DynamicBonds echoes its
        # explicit cutoff: "DynamicBonds 1.6" -- compare against the join).
        set stylestr [join $sargs " "]
        # Hidden rep: hiders of this tier whose user2 flag is still < 1
        # (unfound). Element coloring auto-tracks the hider element (C ->
        # cyan, matches real carbons under default Name coloring).
        mol addrep $molid
        set hidx [expr {$base + $k}]
        set hname [mol repname $molid $hidx]
        mol modstyle $hidx $molid {*}$sargs
        mol modcolor $hidx $molid Element
        set hsel "resname GAM and beta < 0 and user2 < 1 and user3 $code"
        mol modselect $hidx $molid $hsel
        # Found rep: hiders of this tier whose user2 flag is > 0 (marked
        # found). ColorID 7 = green (4th arg to modcolor; read-back
        # "ColorID 7").
        mol addrep $molid
        set fidx [expr {$base + $k + 1}]
        set fname [mol repname $molid $fidx]
        mol modstyle $fidx $molid {*}$sargs
        mol modcolor $fidx $molid ColorID 7
        set fsel "resname GAM and beta < 0 and user2 > 0 and user3 $code"
        mol modselect $fidx $molid $fsel
        # VALIDATE both reps (P-1: read-back string-compare -- catch NEVER
        # fires on a bad style; molinfo get on an out-of-range index errors,
        # so range is checked against numreps BEFORE the read).
        set nreps [molinfo $molid get numreps]
        if {$hidx >= $nreps || $fidx >= $nreps} {
            error "hiders::add_hider_reps: rep index out of range after addrep (hidx=$hidx fidx=$fidx numreps=$nreps)"
        }
        foreach {rname ridx rexp_sel} [list hidden $hidx $hsel found $fidx $fsel] {
            set rstyle ""; set rsel ""; set rcol ""; set rmat ""
            foreach {rstyle rsel rcol rmat} [molinfo $molid get "{rep $ridx} {selection $ridx} {color $ridx} {material $ridx}"] { break }
            if {$rstyle ne $stylestr || $rsel ne $rexp_sel} {
                error "hiders::add_hider_reps: style/selection read-back mismatch on $rname-pair rep $ridx (tier $code): exp style='$stylestr' sel='$rexp_sel' got style='$rstyle' sel='$rsel'"
            }
        }
        # Record name-keyed tracking (the literal selection strings are
        # stored here so the re-assert re-issues them UNCHANGED).
        dict set tier_reps $code [list $hname $fname $hsel $fsel]
        dict set tier_styles $code $stylestr
        set k [expr {$k + 2}]
    }
    return $tier_reps
}

# stamp_tier_codes {molid tier_of} -> {}.
#
# Writes the per-atom tier codes: tier_of is a dict tier_code -> index list
# (the dispatch split from game.tcl 17.1-06). For each code, one batched
# multi-atom atomselect + a NUMERIC scalar set (VMD broadcasts the scalar
# over the selection, probe2; non-numeric data errors -- P7 -- hence the
# integer guard below). Codes are 1-based ints; real atoms keep 0.
#
# MUST run BEFORE add_hider_reps (ORDERING CONTRACT): a static single-frame
# molecule never re-evaluates cached rep selections on an atom-field change,
# so reps added before stamping would cache empty selections. Read-back is
# FLOAT (1.0) -- callers compare numerically only (P10).
proc ::biochemeleon::hiders::stamp_tier_codes {molid tier_of} {
    dict for {code idxs} $tier_of {
        if {![string is integer -strict $code] || $code < 1} {
            error "hiders::stamp_tier_codes: tier code '$code' is not a 1-based integer -- user3 stamps must be numeric (P7)"
        }
        set sel [atomselect $molid "index $idxs"]
        $sel set user3 $code
        $sel delete
    }
    return
}

# mark_found_visual {molid idx} -> {}.
#
# Visual half of a found event: set user2=1 on the picked index, then
# re-issue modselect for ALL tracked pairs with the UNCHANGED literal
# selection strings stored in tier_reps (the mandatory re-evaluation
# re-assert -- see header). The atom migrates its tier's hidden rep -> found
# rep (green). Errors with a clear message if no hider reps were added (or
# a tracked rep is gone for THIS molid -- repindex -1 / out of range; rep
# indices renumber on delrep, P2/Pitfall 9, hence the per-use resolution).
proc ::biochemeleon::hiders::mark_found_visual {molid idx} {
    variable tier_reps
    # Guard: pairs must have been added, and the molecule must still have
    # reps to re-assert.
    set nreps [molinfo $molid get numreps]
    if {[dict size $tier_reps] == 0 || $nreps <= 0} {
        error "hiders::mark_found_visual: hider reps not added -- call add_hider_reps first (numreps=$nreps)"
    }
    # 1. Flag the atom. user2 values are FLOATS (read-back 1.0/0.0) -- always
    #    compare numerically, never string-eq to "1" (Pitfall 7).
    set sel [atomselect $molid "index $idx"]
    $sel set user2 1
    $sel delete
    # 2. MANDATORY re-evaluation re-assert (Pitfall 3): re-issue EVERY pair's
    #    modselect with the STORED literal strings -- a static molecule never
    #    re-evaluates cached rep selections on atom-field change
    #    (timestep-based re-eval only). Names resolve via repindex at USE
    #    time (never cached indices); -1 or out-of-range = the round's reps
    #    were mutated behind our back -> hard error.
    dict for {code pair} $tier_reps {
        lassign $pair hname fname hsel fsel
        set hidx [mol repindex $molid $hname]
        if {$hidx < 0 || $hidx >= $nreps} {
            error "hiders::mark_found_visual: hider rep '$hname' is gone (repindex $hidx)"
        }
        mol modselect $hidx $molid $hsel
        set fidx [mol repindex $molid $fname]
        if {$fidx < 0 || $fidx >= $nreps} {
            error "hiders::mark_found_visual: hider rep '$fname' is gone (repindex $fidx)"
        }
        mol modselect $fidx $molid $fsel
    }
    return
}
