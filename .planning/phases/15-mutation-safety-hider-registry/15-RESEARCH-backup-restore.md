# Phase 15: backup.tcl (viewpoint + rep save/restore on a NEW molid) — Research

**Researched:** 2026-08-30
**Domain:** VMD 1.9.3 tcl — `molinfo` viewpoint matrices + rep save/restore across `mol delete`/`mol new` (viewmaster-style round-trip)
**Confidence:** HIGH (every API claim verified by a headless VMD probe + cited to `vmd-ref/` file:line)
**Focus:** `vmd/lib/backup.tcl` — the mol bridge that snapshots viewpoint + rep list before mutation and restores them on a NEW molid after `mol delete` + `mol new <original>`. This is the v2 wrinkle: **molid changes on reload and reps/viewpoint do NOT survive** (`mol delete`+`mol new` resets to 1 default Lines rep + identity viewpoint).

## Summary

`backup.tcl` is a small mol bridge with two public procs: `snapshot {molid}` returns a dict `{molid filename viewpoint reps}`, and `restore {snapshot}` performs the full cleanup cycle — `mol delete $molid` + `mol new $filename` + clear-then-addrep the saved reps + `molinfo set` the saved viewpoint — and returns the NEW molid. The viewpoint is a 4-element list of 4×4 nested matrices obtained via `molinfo $m get {rotate_matrix center_matrix scale_matrix global_matrix}` (viewmaster form) and restored verbatim with the positional `molinfo $m set {rotate_matrix center_matrix scale_matrix global_matrix} $vp` (round-trip is EXACT: maxdiff 0.0 over 64 elements, str-eq 1). Reps are saved with the combined-braces form already used in `demos.tcl::get_active_reps` — `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` — capturing the 4 fields `{style selection color material}` where color and material are NAMES (`"Name"`, `"Opaque"`), not indices; `{rep $i}` returns the bare style name (`"Lines"`, `"VDW"`, `"Cartoon"`) with NO style parameters. Restore uses the clonerep clear pattern (`mol delrep 0` loop to 0) then `mol addrep` + `mol modstyle/modselect/modcolor/modmaterial` per rep (isolated form B; form A — set defaults then `mol addrep` — is the canonical clonerep alternative, both verified 0-mismatch).

**Primary recommendation:** `backup.tcl` owns the FULL restore cycle (`mol delete` + `mol new` + re-apply reps + restore viewpoint → returns new molid), keeping `game.tcl` a thin orchestrator (`snapshot` on start, `restore` on cleanup/restart) and leaving `mutation.tcl` focused on the FORWARD high-risk PDB-rebuild. Save ALL reps (not just `GAME_REPS`) — success criterion #2 says "same reps". Keep the scope minimal: viewpoint + rep list + original PDB path; do NOT snapshot atom fields (reloading the original PDB restores them — confirmed: `mol new [molinfo $m get filename]` reloads the same atom count).

## API findings (every claim cited + probed)

### Viewpoint: the 4 molinfo matrix fields
**Source:** `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:219` (save) and `:234` (restore); `vmd-ref/scripts/save_state.tcl:57-58` (save) and `:70-71` (restore).

viewmaster saves/restores all 4 transformation matrices in one combined `molinfo` get/set:
```tcl
# viewmaster.tcl:219 (save)
lappend moldata [list views [molinfo $mol get {rotate_matrix center_matrix scale_matrix global_matrix}]]
# viewmaster.tcl:234 (restore)
views { molinfo $molid set {rotate_matrix center_matrix scale_matrix global_matrix} $val }
```
`save_state.tcl:57-58` uses a DIFFERENT field order (`center_matrix` first):
```tcl
set viewpoints($mol) [molinfo $mol get {center_matrix rotate_matrix scale_matrix global_matrix}]
# save_state.tcl:70-71
molinfo $mol set {center_matrix rotate_matrix scale_matrix global_matrix} $viewpoints($mol)
```
**The order is POSITIONAL — the set list MUST match the get list order.** Both orders work; viewmaster's (`rotate center scale global`) is the canonical plugin form and is what this research verified.

**Probe result (PROBE1, 1xdn.pdb, molid 0):** each single-field `molinfo $m get <field>` returns `llength=1` — a ONE-element list whose sole element is a nested 4×4 matrix (a list of 4 row-sublists of 4 floats). The COMBINED get returns `llength=4` — a 4-element list of 4×4 matrices (NOT a flat 64-element list):
```
center_matrix: llength=1
  val={{1 0 0 -39.5457} {0 1 0 -26.6581} {0 0 1 -16.3063} {0 0 0 1}}
rotate_matrix: llength=1
  val={{1 0 0 0} {0 1 0 0} {0 0 1 0} {0 0 0 1}}
scale_matrix: llength=1
  val={{0.0263061 0 0 0} {0 0.0263061 0 0} {0 0 0.0263061 0} {0 0 0 1}}
global_matrix: llength=1
  val={{1 0 0 0} {0 1 0 0} {0 0 1 0} {0 0 0 1}}
COMBINED_A(rotate,center,scale,global) llength=4
COMBINED_B(center,rotate,scale,global) llength=4
combA==combB(aseq): 0          ;# order matters (positional)
combA llength_64? 0             ;# NOT flat — nested 4x4 matrices
```
**Implication:** store the combined 4-element nested list verbatim in the snapshot; pass it verbatim to `molinfo set`. Do NOT flatten/reformat — the positional set expects the identical nested structure.

### Viewpoint round-trip on a NEW molid (the v2 wrinkle)
**Source:** `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:228-241` (`restore_molecules` iterates `molinfo list` and sets the saved views per molid).

**Probe result (PROBE2, fixed nested-list flattener, 1xdn.pdb):** mutate viewpoint (`rotate x by 30; rotate y by 45; scale to 0.8; translate by 0.5 0.5 0.5`), snapshot, `mol delete` + `mol new` original, restore, compare:
```
VIEW_snapshot_len=4 (expect 4)
VIEW_m_old=0 m_new=1 monotonic=1                              ;# molid monotonic, new > old
VIEW_fresh_differs_from_snapshot=1 (maxdiff=0.7736939 over 64 elems)   ;# fresh mol viewpoint != snapshot -> backup necessary
VIEW_restored_maxdiff=0.0 over 64 elems                        ;# EXACT round-trip
VIEW_restored_within_1e-4=1                                   ;# within tolerance
VIEW_restored_str_eq=1                                         ;# byte-identical string rep too
```
**Verified commands (copy these exactly):**
```tcl
# SAVE (viewmaster order)
set vp [molinfo $m get {rotate_matrix center_matrix scale_matrix global_matrix}]
# ... mol delete $m; set m2 [mol new $pdb type pdb] ...
# RESTORE (positional, SAME order)
molinfo $m2 set {rotate_matrix center_matrix scale_matrix global_matrix} $vp
```
The round-trip is EXACT (maxdiff 0.0); the `1e-4` tolerance is a safe bound for the smoke assert. The float-tolerance compare needs a recursive flattener because the structure is nested 4×4 matrices, NOT a flat 64-list (a naive `abs($x-$y)` over the top-level list errors with `can't use non-numeric string as operand of "-"` — confirmed in the first probe run).

### Rep save: the combined-braces molinfo form (color/material are NAMES)
**Source:** `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:252`; `vmd-ref/plugins/clonerep1.3/clonerep.tcl:103`; `vmd-ref/scripts/save_state.tcl:85`; **already used in v2** `vmd/lib/demos.tcl:94`.

The canonical rep-save form (single combined-braces `molinfo get` — single-field `molinfo get {rep $i}` FAILS, per v2 `demos.tcl` Pitfall 3):
```tcl
foreach {r s c m} [molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
```
**Probe result (PROBE3, 1xdn.pdb, 3 reps = Lines + VDW + Cartoon):**
```
rep0 combined=Lines all Name Opaque
rep1 combined=VDW {name CA} Name Opaque
rep2 combined=Cartoon protein Name Transparent
rep0 color=Name (is_name=1) material=Opaque    ;# {color $i} = NAME string, NOT an index
rep2 color=Name material=Transparent            ;# {material $i} = NAME string
rep0 style_raw=Lines                            ;# {rep $i} = bare style NAME, NO params
rep1 style_raw=VDW
rep2 style_raw=Cartoon
```
Per-rep extra params (all DEFAULTS for reps created via `mol addrep` with default settings — `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:257-264` saves these, but they are irrelevant for Phase 15):
```
showrep=1 selupdate=0 colupdate=0 smoothrep=0 scaleminmax=0.000000 0.000000 drawframes=now
```
**Findings:**
- `{color $i}` returns a color-method NAME (`"Name"`, `"Structure"`, `"Type"`, …), NOT an integer index. `string is integer -strict` = 0. Pass it straight to `mol modcolor`/`mol color`.
- `{material $i}` returns a material NAME (`"Opaque"`, `"Transparent"`, …). Pass it straight to `mol modmaterial`/`mol material`.
- `{rep $i}` returns the BARE style name (`"Lines"`, `"VDW"`, `"Cartoon"`) with NO style parameters (line thickness, sphere scale, bond radius). The 4 fields `{style selection color material}` are SUFFICIENT to reproduce a rep set up with default params (the Phase 15 case — the Setup tab creates reps with default params), but NOT a rep whose style params were hand-tuned in the GUI (see Open Questions).
- `selection` is the raw selection text (e.g. `"all"`, `"name CA"`, `"protein"`) — a single braced token when it contains spaces.

### Rep restore on a FRESH molecule (clear-then-add)
**Source (clear pattern):** `vmd-ref/plugins/clonerep1.3/clonerep.tcl:94-96` — the CORRECT clear (capture count once, always `delrep 0`):
```tcl
set numreps [molinfo $toid get numreps]
for {set i 0} {$i < $numreps} {incr i} {
    mol delrep 0 $toid     ;# always index 0 -- remaining reps renumber (clonerep.tcl:92 "note they will always be renumbered")
}
```
**DO NOT USE `save_state.tcl:121-123`** — it has an off-by-one bug (`for {set i 0} {$i < [molinfo $mol get numreps]} {incr i} { mol delrep $i $mol }` re-evaluates `numreps` each iteration while it shrinks → deletes only ~half the reps, stops early). clonerep's captured-count `delrep 0` loop is correct.

**Source (restore form A — set defaults then addrep):** `vmd-ref/plugins/clonerep1.3/clonerep.tcl:123-127` and `vmd-ref/scripts/save_state.tcl:128-133`:
```tcl
mol representation $rep
mol color $col
mol selection $sel
mol material $mat
mol addrep $toid
```
**Source (restore form B — add then mod):** `mol addrep` then `mol modstyle/modselect/modcolor/modmaterial` (per `viewmaster.tcl:300-319` mod* calls):
```tcl
mol addrep $m
mol modstyle $idx $m $style
mol modselect $idx $m $sel
mol modcolor $idx $m $color
mol modmaterial $idx $m $material
```

**Probe result (PROBE4, saved 3 reps, fresh reload, both forms):**
```
saved_reps={Lines all Name Opaque} {VDW {name CA} Name Opaque} {Cartoon protein Name Transparent}
fresh m3=2 numreps=1 (expect 1 Lines)          ;# fresh mol new has 1 default Lines rep
after_clear numreps=0 (expect 0)               ;# clonerep delrep-0 loop clears to 0
after_restore_A numreps=3 (expect 3)           ;# form A: 3 reps added
formA_mismatches=0                             ;# form A: all 3 reps {style,sel,color,material} match saved
formB_mismatches=0                             ;# form B: all 3 reps match saved
```
**Both forms give 0 mismatches.** Form A is the canonical clonerep/save_state pattern but mutates the GLOBAL "current default" rep/color/selection/material (a benign side effect — see Open Questions). Form B is ISOLATED (no global-default mutation; `mol addrep` adds a default rep then the `mod*` calls override it). This research recommends **form B** for isolation (the transient default is immediately overridden so it never leaks); form A is the verified canonical alternative.

### molinfo filename: reload the original by path
**Source:** `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:720` (`set files [lindex [molinfo $id get filename] 0]`) — viewmaster saves filename to reload molecules.

**Probe result (PROBE5, 1xdn.pdb loaded with a C:/ forward-slash path):**
```
filename_raw=C:/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/tmp/probe15b/vmd/data/demos/1xdn.pdb
filename_type=pdb
filename_eq_passed=1                            ;# molinfo filename == EXACT string passed to mol new
reload_numatoms=2597 orig_numatoms=2597 eq=1    ;# mol new [molinfo $m get filename] reloads same atom count
```
**Finding:** `molinfo $m get filename` returns the EXACT path string passed to `mol new` (for bundled demos, a `C:/...` forward-slash path after `demos::to_vmd_path`). `mol new [molinfo $m get filename] type pdb` reloads with the identical atom count. The snapshot stores this string; restore does `mol new $filename type pdb`. (Note: viewmaster wraps `filename` in `[lindex ... 0]` because `molinfo get filename` can return a LIST for multi-file molecules; for Phase 15's single-PDB bundled demos it is a single string. See Open Questions for the multi-file edge case.)

### mol delete + mol new: NEW molid, reps do NOT survive (backup is necessary)
**Source:** `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:132-169` (`update_molecules` traces `vmd_initialize_structure` precisely because mols disappear/appear and per-mol state must be rebuilt — confirming reps/viewpoint do not survive).

**Probe result (PROBE6, 1xdn.pdb):**
```
m6=6 numreps_with3=3 (expect 3)               ;# added VDW + Cartoon to the default Lines = 3 reps
m6b=7 new_molid=1 (monotonic)                  ;# after mol delete + mol new: new molid 7 > 6 (monotonic, never reused)
m6b_numreps=1 (expect 1 -- reps do NOT survive) ;# fresh mol new resets to 1 default rep
m6b_rep0={Lines all Name Opaque}               ;# the default rep on a fresh mol new
```
**Finding:** `mol delete` + `mol new` gives a strictly-higher molid (monotonic, never reused) and the rep list RESETS to 1 default `Lines all Name Opaque` rep. The viewpoint also resets to the load-default (PROBE2: `fresh_differs_from_snapshot=1`). This is WHY backup is mandatory — nothing survives the reload.

### Scope confirmation: do NOT snapshot atom fields
**Source:** `vmd/AGENTS.md:84` ("`save_state` does NOT persist `beta`/`user`/`segid` … It reloads original files by path"). The original PDB file already carries the original `beta`/`user`/`segid`/coords; reloading it restores them automatically. PROBE5 confirmed `mol new [molinfo $m get filename]` reloads the same atom count (2597), and since the file is the untouched original, all atom fields are restored by the reload itself. **backup.tcl scope = viewpoint + rep list + original PDB path. No `atomselect`, no atom-field snapshot.**

## Recommended approach — `vmd/lib/backup.tcl`

### Module shape
- Namespace `::biochemeleon::backup` (filename parity with v1 `backup.py`; matches `demos`/`registry` naming).
- mol bridge: uses `mol`/`molinfo` only; NO `tk`/`toplevel` (headless-verifiable). NO `atomselect` (no atom-field snapshot).
- Tcl 8.5: `catch` for errors, `foreach`+`lappend` for list builds, brace all `expr`, `lassign`/`dict` available, NO `lmap`/`try`/`finally`.
- Sourced by the entry `vmd/biochemeleon.tcl` (Phase 15 adds the `source` line). `[info script]` is fine here because backup.tcl is `source`d (not `-e`d) — same as `demos.tcl` (Phase 14 lesson).
- Reuse `demos::to_vmd_path` only if a path needs conversion — but `molinfo get filename` already returns a VMD-readable `C:/` path for bundled demos, so `restore` can pass it straight to `mol new` WITHOUT re-converting (re-converting a `C:/` path is a no-op anyway). Keep backup.tcl standalone (do NOT `source demos.tcl` — it would reverse the dependency direction; `demos` is a sibling mol bridge, not a dependency of `backup`).

### Public procs (exact signatures + verified command strings)

```tcl
namespace eval ::biochemeleon::backup {
    namespace export snapshot restore
}

# snapshot {molid} -> dict {molid <int> filename <path> viewpoint <4-matrix list> reps <list of {style sel color material}>}
# Saves ALL reps on the molecule (NOT just GAME_REPS) -- success criterion #2 "same reps".
# Wraps in catch: a bad molid returns an error (caller -- game.tcl -- aborts the game).
proc ::biochemeleon::backup::snapshot {molid} {
    set filename [molinfo $molid get filename]
    set viewpoint [molinfo $molid get {rotate_matrix center_matrix scale_matrix global_matrix}]
    set reps [list]
    set n [molinfo $molid get numreps]
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel color material} \
            [molinfo $molid get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        lappend reps [list $style $sel $color $material]
    }
    return [dict create molid $molid filename $filename viewpoint $viewpoint reps $reps]
}

# restore {snapshot} -> new_molid (int)
# The FULL cleanup cycle: mol delete $molid + mol new $filename + clear-then-addrep + restore viewpoint.
# Returns the NEW molid (monotonic, > old) so game.tcl can track it / re-generate on restart.
proc ::biochemeleon::backup::restore {snapshot} {
    set molid    [dict get $snapshot molid]
    set filename [dict get $snapshot filename]
    set viewpoint [dict get $snapshot viewpoint]
    set reps     [dict get $snapshot reps]
    # 1. delete the (possibly mutated) molecule + reload the ORIGINAL PDB -> NEW molid
    mol delete $molid
    set new_molid [mol new $filename type pdb]
    # 2. clear the fresh mol's default Lines rep (clonerep.tcl:94-96 -- captured count, always delrep 0)
    set n [molinfo $new_molid get numreps]
    for {set i 0} {$i < $n} {incr i} { mol delrep 0 $new_molid }
    # 3. re-apply each saved rep -- form B (isolated: addrep then mod*)
    set idx 0
    foreach rep $reps {
        foreach {style sel color material} $rep { break }
        mol addrep $new_molid
        mol modstyle $idx $new_molid $style
        mol modselect $idx $new_molid $sel
        mol modcolor $idx $new_molid $color
        mol modmaterial $idx $new_molid $material
        incr idx
    }
    # 4. restore viewpoint (positional, SAME field order as the get)
    molinfo $new_molid set {rotate_matrix center_matrix scale_matrix global_matrix} $viewpoint
    return $new_molid
}
```

### Responsibility split (backup.tcl vs mutation.tcl vs game.tcl) — RECOMMENDED

**RECOMMENDED: `backup.tcl` owns the full restore cycle.** `restore` does `mol delete` + `mol new` + re-apply reps + restore viewpoint and returns the new molid. `game.tcl` is a thin orchestrator: `snapshot` on start, `restore` on cleanup/restart. `mutation.tcl` focuses on the FORWARD high-risk PDB-rebuild (rebuild PDB with hiders + `mol new <combined>` + set sentinels) and does NOT own the cleanup reload.

**Justification:**
1. The knowledge "reps and viewpoint do NOT survive `mol delete`+`mol new`; you must clear-then-addrep and `molinfo set`" is VMD-specific and belongs in ONE mol bridge, not split across `mutation.tcl` + `backup.tcl` + `game.tcl`.
2. `backup.tcl` is the natural home for the save/restore SYMMETRY — `snapshot` saves everything, `restore` reloads everything (single responsibility).
3. `game.tcl` stays minimal — no VMD-reload mechanics leak into the orchestrator (it just calls `snapshot`/`restore` and wires `registry`).
4. `mutation.tcl` keeps the hardest, highest-risk job (forward PDB-rebuild) isolated; its "cleanup" in the AGENTS.md module description is the inverse reload, which `backup::restore` implements. The smoke test is a clean one-liner: `set new [backup::restore [backup::snapshot $m]]`.

**ALTERNATIVE (if researcher A/C prefer `mutation.tcl` to own the cleanup reload per the literal AGENTS.md "mutation.tcl: ... + cleanup" description):** expose `backup.tcl::restore_reps {new_molid reps}` + `backup.tcl::restore_viewpoint {new_molid viewpoint}` (state-only helpers, public), and have `mutation.tcl::cleanup` do `mol delete $molid + mol new $filename -> new_molid`, then `game.tcl` calls `backup::restore_reps $new_molid $reps` + `backup::restore_viewpoint $new_molid $viewpoint`. This matches the literal module descriptions but SPLITS the VMD-reload knowledge across `mutation.tcl` (the delete+new) and `backup.tcl` (the state re-apply). Both work; the split is a COORDINATION POINT with researchers A (mutation.tcl) and C (game.tcl) — the planner should confirm which proc owns `mol delete`+`mol new` so the signatures align.

### Internal helpers (optional — only if the alternative split is chosen)
```tcl
proc ::biochemeleon::backup::restore_reps {molid reps} {
    set n [molinfo $molid get numreps]
    for {set i 0} {$i < $n} {incr i} { mol delrep 0 $molid }
    set idx 0
    foreach rep $reps {
        foreach {style sel color material} $rep { break }
        mol addrep $molid
        mol modstyle $idx $molid $style
        mol modselect $idx $molid $sel
        mol modcolor $idx $molid $color
        mol modmaterial $idx $molid $material
        incr idx
    }
}
proc ::biochemeleon::backup::restore_viewpoint {molid viewpoint} {
    molinfo $molid set {rotate_matrix center_matrix scale_matrix global_matrix} $viewpoint
}
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Viewpoint save/restore | Manual matrix math / per-element get | `molinfo $m get {rotate_matrix center_matrix scale_matrix global_matrix}` + positional `molinfo $m set ...` | viewmaster.tcl:219,234 — VMD's own mechanism; EXACT round-trip (probe: maxdiff 0.0) |
| Rep save | Per-field `molinfo get {rep $i}` (one field at a time) | Combined-braces `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` | demos.tcl:94 + clonerep.tcl:103 + viewmaster.tcl:252 — single-field form FAILS (v2 Pitfall 3) |
| Rep clear | `mol delrep $i` in an ascending loop / `save_state.tcl:121-123` form | `set n [numreps]; for {i 0} {$i<$n} {incr i} { mol delrep 0 $m }` | clonerep.tcl:94-96 — captured count + always index 0 (renumbering-safe); save_state's ascending-`$i` form has an off-by-one bug |
| Reload original | Re-derive the PDB path / store a copy | `molinfo $m get filename` + `mol new $filename type pdb` | viewmaster.tcl:720 — VMD records the load path; reload reproduces atom count exactly (probe: 2597==2597) |
| Float-tolerance compare | `expr {$a == $b}` on nested matrices | Recursive flatten + `expr {abs($x-$y) < 1e-4}` per element | Tcl 8.5: nested-list `abs($a-$b)` errors "can't use non-numeric string" (probe-confirmed); must flatten first |

## Common Pitfalls

### Pitfall 1: molid changes on reload — reps/viewpoint do NOT survive
**What goes wrong:** caller caches the old molid or assumes reps/viewpoint persist across `mol delete`+`mol new`.
**Why:** VMD molids are monotonic, never reused; a fresh `mol new` gets a strictly-higher molid and resets to 1 default Lines rep + load-default viewpoint (PROBE6: `m6b=7`, `numreps=1`, `{Lines all Name Opaque}`).
**How to avoid:** `backup::restore` returns the NEW molid; the caller MUST use the returned molid, never the snapshot's `molid`. Reps and viewpoint are ALWAYS re-applied from the snapshot after reload.
**Warning signs:** "no such molecule" errors using the old molid; reps count = 1 after a reload that should have N; viewpoint snaps back to default.

### Pitfall 2: viewpoint combined get is NESTED, not flat — naive compare errors
**What goes wrong:** `expr {abs($vp_a - $vp_b)}` on the combined 4-element list errors: `can't use non-numeric string as operand of "-"`.
**Why:** each of the 4 elements is itself a 4×4 nested matrix (a list of 4 row-lists), not a float (PROBE1: `llength=4`, NOT 64).
**How to avoid:** recursively flatten both viewpoint structures to a flat 64-float list, THEN compare element-wise with `expr {abs($x-$y) < 1e-4}` (see Test Strategy for the verified flattener). Or use string equality `expr {$vp eq $vp_restored}` (probe-confirmed: str_eq=1 when round-trip is exact) — but float-tolerance is safer against formatting drift.
**Warning signs:** the `abs($a-$b)` error above; a "PASS" that didn't actually compare numbers.

### Pitfall 3: `molinfo get` field ORDER is positional — get/set MUST match
**What goes wrong:** `molinfo $m set {center_matrix rotate_matrix ...} $vp` where `$vp` was got in `{rotate_matrix center_matrix ...}` order — silently swaps center/rotate (wrong viewpoint).
**Why:** the combined get/set is positional; viewmaster uses `rotate center scale global`, save_state uses `center rotate scale global` — both work ONLY if get and set match (PROBE1: `combA==combB(aseq): 0`).
**How to avoid:** use ONE order everywhere in backup.tcl. RECOMMEND viewmaster's `{rotate_matrix center_matrix scale_matrix global_matrix}` (canonical plugin, verified exact round-trip). Never mix.
**Warning signs:** restored viewpoint is rotated/translated wrong despite "matching" element counts.

### Pitfall 4: rep clear with ascending index deletes only ~half (save_state bug)
**What goes wrong:** `for {set i 0} {$i < [molinfo $mol get numreps]} {incr i} { mol delrep $i $mol }` leaves reps behind.
**Why:** `numreps` shrinks each iteration but `$i` grows — the loop stops at ~half. `mol delrep` renumbers the remaining reps (clonerep.tcl:92 "note they will always be renumbered").
**How to avoid:** capture the count ONCE, always delete index 0: `set n [molinfo $m get numreps]; for {set i 0} {$i < $n} {incr i} { mol delrep 0 $m }` (clonerep.tcl:94-96).
**Warning signs:** after "clear", `numreps` is nonzero; restored reps appended AFTER leftover defaults → numreps > saved count.

### Pitfall 5: form A restore mutates the GLOBAL "current default" rep/color/selection/material
**What goes wrong:** `mol representation $r; mol color $c; mol selection $s; mol material $m; mol addrep` (clonerep form A) leaves the global default at the LAST rep's values; a later bare `mol addrep` (by game.tcl or the Setup tab) silently uses those values.
**Why:** `mol representation/color/selection/material` (no `mod*`) set the global "current default" used by the next `mol addrep` (clonerep.tcl:123-127, save_state.tcl:128-133).
**How to avoid:** use **form B** (`mol addrep` then `mol modstyle/modselect/modcolor/modmaterial`) — isolated, no global-default mutation. Form A is verified-correct (PROBE4: `formA_mismatches=0`) and canonical, but form B is safer for an orchestrator that may add reps later.
**Warning signs:** a later `mol addrep` unexpectedly creates a Cartoon/Transparent rep instead of the default Lines/Opaque.

### Pitfall 6: atomselect leaks (NOT applicable to backup.tcl, but documented for the boundary)
**What goes wrong:** a cached `atomselect` on a deleted molid returns STALE data silently (no error).
**Why:** `atomselect` objects are not invalidated when their molid is deleted (vmd/AGENTS.md:105).
**How to avoid:** backup.tcl uses NO `atomselect` (scope = viewpoint + reps + path only; reloading the original PDB restores atom fields). If a future phase adds atom-field snapshot, NEVER cache a selection across `mol delete`/reload — always `$sel delete` and re-create on the new molid.
**Warning signs:** (future) stale beta/segid values after a reload.

### Pitfall 7: `{rep $i}` returns the style NAME only, NOT style parameters
**What goes wrong:** a rep with a hand-tuned line thickness / sphere scale / bond radius restores with default params after `mol delete`+`mol new`.
**Why:** `molinfo $m get "{rep $i}"` returns the bare style name (`"Lines"`, `"VDW"`, `"Cartoon"`) — NO params (PROBE3: `rep0 style_raw=Lines`). The 4-field save `{style selection color material}` does not capture style params.
**How to avoid:** for Phase 15 this is FINE — the original's reps are set up by the Setup tab with default params, so 4 fields reproduce them exactly. Do NOT hand-tune rep params before a game. If a future phase needs exact param restore, port viewmaster's full per-rep save (`showperiodic`, `scaleminmax`, `smoothrep`, `drawframes`, `selupdate`, `colupdate`, `showrep`, clipplanes — viewmaster.tcl:257-264, clonerep.tcl:104-120) — out of scope for Phase 15.
**Warning signs:** a GUI-tuned rep looks different after cleanup (not a Phase 15 risk).

### Pitfall 8: `mol color Secondary` is NOT a valid color method (probe finding)
**What goes wrong:** `mol color Secondary` errors: `Incorrect atom color method command 'Secondary'` (the rep falls back to `Name`).
**Why:** the secondary-structure color method is `Structure`, not `Secondary`; and `Cartoon` rep triggers Stride which fails for nucleic-only structures (1k8p) — cosmetic noise, the rep still loads.
**How to avoid:** use `mol color Structure` (not `Secondary`) if secondary-structure coloring is wanted. For the backup.tcl SMOKE test, use a PROTEIN demo (1xdn, 2597 atoms) so Cartoon/Structure render cleanly without Stride errors. 1k8p (nucleic) also round-trips correctly but emits Stride warnings.
**Warning signs:** `ERROR) Incorrect atom color method command 'Secondary'`; Stride errors in the smoke log (cosmetic — rep still added, round-trip still matches).

## Code Examples (verified — copy from probes)

### Save + restore round-trip (the full backup.tcl core, from PROBE2 + PROBE4)
```tcl
# Source: probe2.tcl + probe4.tcl (this research, 2026-08-30); viewmaster.tcl:219,234; clonerep.tcl:94-96

# --- SAVE ---
set filename [molinfo $m get filename]
set viewpoint [molinfo $m get {rotate_matrix center_matrix scale_matrix global_matrix}]
set reps [list]
set n [molinfo $m get numreps]
for {set i 0} {$i < $n} {incr i} {
    foreach {style sel color material} \
        [molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
    lappend reps [list $style $sel $color $material]
}

# --- RELOAD + RESTORE ---
mol delete $m
set m2 [mol new $filename type pdb]                       ;# NEW molid (monotonic)
set n [molinfo $m2 get numreps]
for {set i 0} {$i < $n} {incr i} { mol delrep 0 $m2 }       ;# clonerep clear (captured count, index 0)
set idx 0
foreach rep $reps {
    foreach {style sel color material} $rep { break }
    mol addrep $m2                                         ;# form B: add then mod (isolated)
    mol modstyle $idx $m2 $style
    mol modselect $idx $m2 $sel
    mol modcolor $idx $m2 $color
    mol modmaterial $idx $m2 $material
    incr idx
}
molinfo $m2 set {rotate_matrix center_matrix scale_matrix global_matrix} $viewpoint   ;# positional, same order as get
```

### Float-tolerance viewpoint compare (recursive flatten — verified in probe2.tcl)
```tcl
# Source: probe2.tcl (this research) — the naive abs($a-$b) ERRORS on nested matrices; must flatten.
proc _flat {lst outvar} {
    upvar 1 $outvar out
    foreach x $lst {
        if {[llength $x] > 1} { _flat $x out } else { lappend out $x }
    }
}
proc _vp_maxdiff {a b} {
    set fa [list]; set fb [list]
    _flat $a fa; _flat $b fb
    set maxd 0.0
    foreach x $fa y $fb {
        if {[catch {expr {abs($x - $y)}} d]} continue   ;# skip non-numeric (none expected)
        if {$d > $maxd} { set maxd $d }
    }
    return $maxd
}
# assert: [expr {[_vp_maxdiff $vp_saved $vp_restored] < 1e-4}]  -> probe gave 0.0 (exact)
```

## State of the Art

| Old Approach (v1 PyMOL) | Current Approach (v2 VMD) | Impact |
|--------------------------|---------------------------|--------|
| `backup.py`: `cmd.create('_bchm_backup', target)` deep-copy to a backup OBJECT; restore = `cmd.delete(target) + cmd.create(target, backup)` (v1 `backup.py:39-64`) | No backup object — VMD cannot copy a molecule to a "private" name cheaply; backup = record the ORIGINAL PDB path + viewpoint + reps; restore = `mol delete + mol new <original>` + re-apply reps + viewpoint | v2 backup is stateless (a dict), not an object; the "original" is the on-disk PDB, always clean |
| v1 `cmd.create` copies the view WITH the object (viewpoint implicitly preserved) | VMD reps/viewpoint do NOT survive `mol delete`+`mol new` (PROBE6: resets to 1 Lines + default view) | v2 MUST explicitly save+restore viewpoint (viewmaster pattern) — v1 did not |
| v1 `verify_intact`: count + atomic-tuple multiset (v1 `backup.py:69-85`) | v2 reload-original restores atom fields automatically (PROBE5: same atom count) | v2 cleanup-integrity = "atom count after reload == atom count before" + "reps match saved" + "viewpoint within 1e-4" — no atomic-tuple iterate needed |

**Deprecated/outdated:**
- `save_state.tcl:121-123` rep-clear loop (ascending `delrep $i`) — off-by-one bug; use `clonerep.tcl:94-96` (captured count, `delrep 0`).
- Single-field `molinfo get {rep $i}` — FAILS; use the combined-braces form (v2 `demos.tcl:94` Pitfall 3).

## Open Questions

1. **backup.tcl vs mutation.tcl responsibility split (COORDINATION POINT with researchers A & C).**
   - What we know: AGENTS.md lists `mutation.tcl: "... + cleanup"` and `backup.tcl: "snapshot ...; restore"`. The cleanup reload (`mol delete` + `mol new original`) could live in either.
   - Recommendation: `backup.tcl::restore` owns the FULL cycle (recommended above) — simplest for game.tcl, keeps VMD-reload knowledge in one mol bridge.
   - Alternative: `mutation.tcl::cleanup` owns `mol delete`+`mol new`, `backup.tcl` exposes `restore_reps`/`restore_viewpoint` state-only helpers.
   - **Decision needed:** the planner should confirm with researchers A (mutation.tcl) and C (game.tcl) which proc owns `mol delete`+`mol new` so the signatures align. This research's `restore {snapshot} -> new_molid` is the primary; the alternative's `restore_reps`/`restore_viewpoint` helpers are provided above.

2. **Should backup save reps beyond `{style, selection, color, material}`?**
   - What we know: viewmaster/clonerep save 12+ per-rep fields (`showperiodic`, `numperiodic`, `showrep`, `selupdate`, `colupdate`, `scaleminmax`, `smoothrep`, `drawframes`, clipplanes) for a FULL clone. PROBE3 showed all these are DEFAULTS for reps created via the Setup tab.
   - Recommendation: NO — save only the 4 fields. Phase 15's original reps are Setup-tab-created with default params; the 4 fields reproduce them exactly (PROBE4: 0 mismatches). Style PARAMETERS (line thickness, sphere scale) are NOT in `{rep $i}` anyway (Pitfall 7). Saving the extra fields would expand scope without Phase 15 benefit. Document this as a known limitation: a hand-tuned rep's style params are not restored (acceptable — Setup tab uses defaults).

3. **Multi-file molecules (`molinfo get filename` returns a list).**
   - What we know: viewmaster wraps `filename` in `[lindex ... 0]` (viewmaster.tcl:720) because `molinfo get filename` can return a LIST for molecules loaded from multiple files (trajectories, multi-PDB). For Phase 15's single-PDB bundled demos it is a single string (PROBE5: `filename_eq_passed=1`).
   - Recommendation: handle the single-string case now (Phase 15 only loads bundled single-PDB demos). If a future phase adds multi-file/fetched demos, wrap with `[lindex $filename 0]` and `mol addfile` for the rest. Flag for that phase; do NOT build it now.

4. **Should `restore` re-validate that the reloaded atom count matches the pre-mutation count?**
   - What we know: success criterion #2 says "same atom count". PROBE5 confirmed `mol new [molinfo get filename]` reproduces the atom count. The reload is the ORIGINAL (untouched) PDB, so atom count is guaranteed equal to the pre-game count (mutation never wrote to the original — it writes a COMBINED temp PDB, loaded as a SEPARATE molecule).
   - Recommendation: the smoke test asserts atom count before == after; `restore` itself does NOT need an internal assert (the original file is immutable). If defense-in-depth is wanted, `restore` can compare `[molinfo $new_molid get numatoms]` to a saved count — but that adds a field to the snapshot. Keep minimal; let the smoke test assert.

## Test Strategy — headless smoke for `backup.tcl`

A standalone headless smoke (NOT tcltest — backup.tcl is mol-coupled, verified by `vmd -dispdev text`, per `vmd/AGENTS.md:75`). Stage `mkdir -p tmp/<stage> && cp -r vmd tmp/<stage>/`, write `vmd/smoke/phase15_backup_smoke.tcl`, run `bash -ic 'cd tmp/<stage> && vmd -dispdev text -e vmd/smoke/phase15_backup_smoke.tcl -eofexit < /dev/null' > smoke.log 2>&1` and parse the `BCHM_SMOKE_RESULT PASS=1|0` marker (VMD does NOT propagate tcl exit codes — Phase 13 Pitfall 4). Use `[pwd]` to locate `vmd/lib/backup.tcl` (NOT `[info script]` — empty under `vmd -e`), then `source` it (backup.tcl's own `[info script]` then works because it's `source`d, per Phase 14 pattern).

**Use 1xdn.pdb (protein, 2597 atoms) for the smoke** so Cartoon + Structure render cleanly (1k8p is nucleic → Stride warnings, cosmetic but noisy — Pitfall 8). The task hint said 1k8p; 1xdn is the clean choice and also a bundled demo.

**Smoke skeleton (the planner turns this directly into the smoke task):**
```tcl
# vmd/smoke/phase15_backup_smoke.tcl
set failures [list]
proc _bail {tag msg} { upvar 1 failures f; lappend f "$tag:$msg" }

# Source backup.tcl via [pwd] (VMD cwd = staging root; [info script] empty under -e).
set bk [file join [pwd] vmd lib backup.tcl]
if {![file exists $bk]} { lappend failures "backup_not_found:$bk"
} elseif {[catch {source $bk} err]} { lappend failures "backup_source_error:$err" }

# Path helpers (mirror demos::to_vmd_path; do NOT source demos.tcl -- reverses dependency)
proc _to_vmd {p} { if {[regexp {^/mnt/([a-zA-Z])/(.*)$} $p -> d r]} { return "[string toupper $d]:/$r" }; return $p }
set pdb [_to_vmd "[pwd]/vmd/data/demos/1xdn.pdb"]

# Recursive flatten + numeric maxdiff (Pitfall 2 -- nested 4x4 matrices, NOT flat)
proc _flat {lst outvar} { upvar 1 $outvar out; foreach x $lst { if {[llength $x] > 1} { _flat $x out } else { lappend out $x } } }
proc _vp_maxdiff {a b} {
    set fa [list]; set fb [list]; _flat $a fa; _flat $b fb
    set maxd 0.0
    foreach x $fa y $fb { if {[catch {expr {abs($x - $y)}} d]} continue; if {$d > $maxd} { set maxd $d } }
    return $maxd
}

# 1. Load original, set up 3 reps (Lines + VDW + Cartoon), mutate viewpoint.
set m [mol new $pdb type pdb]
mol representation VDW;  mol selection "name CA"; mol color Name;  mol material Opaque;   mol addrep $m
mol representation Cartoon; mol selection "protein"; mol color Structure; mol material Transparent; mol addrep $m
rotate x by 30; rotate y by 45; scale to 0.8; translate by 0.5 0.5 0.5
set atoms_before [molinfo $m get numatoms]
set numreps_before [molinfo $m get numreps]   ;# expect 3 (default Lines + VDW + Cartoon)

# 2. Snapshot.
if {[catch {::biochemeleon::backup::snapshot $m} snap]} { _bail snapshot $snap }
# Snapshot shape asserts.
if {![dict exists $snap molid]}    { _bail snap_shape molid }
if {![dict exists $snap filename]} { _bail snap_shape filename }
if {![dict exists $snap viewpoint]} { _bail snap_shape viewpoint }
if {![dict exists $snap reps]}     { _bail snap_shape reps }
if {[llength [dict get $snap reps]] != $numreps_before} { _bail snap_reps_count "[llength [dict get $snap reps]] (want $numreps_before)" }

# 3. Restore (full cycle: mol delete + mol new + re-apply reps + viewpoint).
if {[catch {::biochemeleon::backup::restore $snap} new_m]} { _bail restore $new_m }

# 4. Assert: NEW molid is monotonic-higher (Pitfall 1).
if {$new_m <= $m} { _bail new_molid_monotonic "old=$m new=$new_m" }

# 5. Assert: atom count restored exactly (success criterion #2).
set atoms_after [molinfo $new_m get numatoms]
if {$atoms_after != $atoms_before} { _bail atoms_count "exp=$atoms_before got=$atoms_after" }

# 6. Assert: numreps restored exactly (success criterion #2 "same reps").
set numreps_after [molinfo $new_m get numreps]
if {$numreps_after != $numreps_before} { _bail numreps "exp=$numreps_before got=$numreps_after" }

# 7. Assert: each rep {style,selection,color,material} matches saved (rep-index order).
set saved_reps [dict get $snap reps]
for {set i 0} {$i < $numreps_after} {incr i} {
    foreach {r s c m3} [molinfo $new_m get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
    set want [lindex $saved_reps $i]
    if {$r ne [lindex $want 0] || $s ne [lindex $want 1] || $c ne [lindex $want 2] || $m3 ne [lindex $want 3]} {
        _bail rep_mismatch "i=$i got={$r $s $c $m3} want=$want"
    }
}

# 8. Assert: viewpoint matches within 1e-4 (success criterion #4, viewmaster round-trip).
set vp_saved    [dict get $snap viewpoint]
set vp_restored [molinfo $new_m get {rotate_matrix center_matrix scale_matrix global_matrix}]
set md [_vp_maxdiff $vp_saved $vp_restored]
if {$md >= 1e-4} { _bail viewpoint_maxdiff $md }

# 9. Assert: bad-molid snapshot raises (caller can abort the game).
if {![catch {::biochemeleon::backup::snapshot 999} bad]} { _bail snapshot_bad_molid "exp=error got=ok:$bad" }

# ---- Report (VMD does NOT propagate tcl exit codes -- parse this marker). ----
if {[llength $failures] == 0} {
    puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none"
} else {
    puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]"
}
```
**Expected (from probes):** PASS=1 — new_molid > old, atoms 2597==2597, numreps 3==3, each rep matches, viewpoint maxdiff 0.0 (< 1e-4), bad-molid errors. This single smoke covers success criteria #2 (same atom count + same reps) and #4 (viewpoint + rep list saved before mutation, restored on new molid).

## Sources

### Primary (HIGH confidence)
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:219,234` — viewpoint save/restore (`{rotate_matrix center_matrix scale_matrix global_matrix}`); `:252` — rep save combined-braces form; `:272-336` — rep restore (clear tail + addrep + mod*); `:132-169` — `update_molecules` (mols disappear/appear, state rebuilt); `:720` — `molinfo get filename` for reload.
- `vmd-ref/plugins/clonerep1.3/clonerep.tcl:92-96` — rep clear pattern (captured count, always `delrep 0`); `:103` — rep save combined-braces; `:123-127` — restore form A (set defaults then `addrep`).
- `vmd-ref/scripts/save_state.tcl:52-60,66-74` — viewpoint save/restore (alt field order); `:80-108` — rep save (12+ fields); `:116-137` — rep restore (form A); `:121-123` — the BUGGY ascending-`delrep` clear (DO NOT USE).
- `vmd/lib/demos.tcl:94` — the combined-braces rep form ALREADY used in v2 (`get_active_reps`); `:36-41` — `to_vmd_path` pattern; `:26` — `script_dir` capture in `namespace eval` (Phase 14 lesson).
- `vmd/AGENTS.md:80-106` — VMD domain rules (no undo, no global atom id, molid monotonic, reps stable names, rep command-based management, atomselect leaks, never cache selection across reload).
- Headless probes (this research, 2026-08-30, 1xdn.pdb + 1k8p.pdb, VMD 1.9.3 Win32, Tcl 8.5.6):
  - `tmp/probe15b/probe.tcl` → `probe_out.log` (PROBE1/3/4/5/6)
  - `tmp/probe15b/probe2.tcl` → `probe2_out.log` (PROBE2 — viewpoint round-trip, fixed flattener)

### Secondary (MEDIUM confidence)
- `pymol/biochemeleon/backup.py:39-85` — v1 snapshot/restore/discard/verify_intact concept (cmd.delete + cmd.create from a backup object). v2 differs (no backup object — reload original PDB), but the snapshot-before-mutation / restore-on-cleanup LIFECYCLE ports. Read for the round-trip test idea only (DIFFERENT API).

### Tertiary (LOW confidence)
- None. All claims probed or cited to `vmd-ref/`.

## Metadata

**Confidence breakdown:**
- Viewpoint save/restore: HIGH — viewmaster.tcl:219,234 cited + probe2 verified exact round-trip (maxdiff 0.0, str_eq 1) on a NEW molid.
- Rep save/restore: HIGH — clonerep.tcl:94-96,103,123-127 + demos.tcl:94 cited + probe4 verified 0-mismatch round-trip (both form A and form B) on a fresh molecule.
- molinfo filename reload: HIGH — viewmaster.tcl:720 cited + probe5 verified same atom count (2597==2597).
- molid monotonic + reps/viewpoint don't survive: HIGH — AGENTS.md:82 + probe6 verified (new molid 7 > 6, numreps resets to 1).
- Responsibility split recommendation: MEDIUM — based on AGENTS.md module descriptions + v1 backup.py lifecycle analogy; the split is a coordination point with researchers A/C (Open Question 1).

**Research date:** 2026-08-30
**Valid until:** 2026-09-29 (30 days — VMD 1.9.3 is a fixed 2016 release; API stable; no drift expected)
