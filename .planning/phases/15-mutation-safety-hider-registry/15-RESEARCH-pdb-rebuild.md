# Phase 15: Mutation Safety & Hider Registry — PDB-rebuild Research (mutation.tcl)

**Researched:** 2026-08-30
**Domain:** VMD 1.9.3 tcl — PDB-rebuild engine (`vmd/lib/mutation.tcl`, the mol bridge)
**Confidence:** HIGH (every API claim verified by a headless VMD probe in this session)
**Focus:** `vmd/lib/mutation.tcl` ONLY. Researchers B/C own `backup.tcl` (viewpoint+reps) and `registry.tcl`+`game.tcl`. This doc is the actionable input the planner turns into mutation.tcl PLAN.md tasks.

## Summary

The PDB-rebuild mechanism is **PROVEN end-to-end by headless probe** (this session, `tmp/probe15a/probe.tcl` + `probe2.tcl`, both reached `BCHM_SMOKE_RESULT ...DONE=1`). The flow is: `atomselect $m "all" writepdb` the originals → read the file, strip the trailing `END` → append hand-written hider `ATOM` records with **strict 78-column PDB format** (`resname=GAM`, `beta=-999.0`, `segid=GAME`, `chain=G`, `resseq=9001`, `element=C`) → write `END` → `mol delete $orig` + `mol new <combined.pdb>`. The result is ONE molecule holding original + hider atoms together (probe: 555 + 5 = 560 atoms, `resname GAM and beta < 0` selects exactly 5, indices 555–559). Sentinels are then SET IN-PLACE via `atomselect` (`$sel set beta -999; $sel set segid GAME; $sel set user <id>`) so they are robust against any PDB-column quirk.

**Primary recommendation:** Build `mutation.tcl` as a standalone mol bridge with 5 procs (`make_placeholder_hiders`, `write_combined_pdb`, `tag_sentinels`, `fetch_hider_indices`, `mutate`) — it owns the **forward** mutate-reload only (write combined PDB → `mol delete` original → `mol new` combined → tag sentinels). The **restore/cleanup** reload (`mol delete` game + `mol new` original + re-apply reps + restore viewpoint) is `backup.tcl`'s `restore` proc (researchers B & C agree — atomic restore, no backup→mutation coupling; reconciled below). Use the **writepdb-then-splice** approach (NOT hand-write-all — `atomselect get` lacks `icode` and risks dropping fields). Format hider beta as **`%6.1f` → `-999.0`** (6 cols, fits, no overflow — proven to let `segid=GAME` survive in the PDB columns) AND set sentinels in-place after load (belt-and-suspenders, per spec).

## API Findings (every claim verified by probe — cite probe output line)

All probes staged at `tmp/probe15a/` (Windows-visible; `cp -r vmd tmp/probe15a/`), run via `bash -ic 'cd tmp/probe15a && vmd -dispdev text -e probe.tcl -eofexit < /dev/null'`. VMD 1.9.3, Tcl 8.5.6. Probe logs: `tmp/probe15a/probe.log` (P1–P8), `tmp/probe15a/probe2b.log` (format refinement).

### A1. `atomselect $m "all" writepdb <path>` — round-trips atoms exactly, preserves beta/segid/occupancy, NOT `user`
- **Citation:** `vmd-ref/scripts/save_state.tcl:39-46` (header states beta/user/segid NOT restored by `save_state`); writepdb is a different, fuller writer.
- **Probe (P1, probe.log:66-95):** writepdb wrote 78-char ATOM lines. After setting atom0 `beta=-42.50 / segid=ORIG / occupancy=0.75 / user=12345`, the written PDB round-tripped:
  - `roundtrip_numatoms=555 orig=555 eq=1` (exact atom count)
  - `roundtrip_beta_survives=-42.5` ✓, `roundtrip_segid_survives=ORIG` ✓, `survive_occ= 0.75` ✓
  - `roundtrip_user_survives=0.0` ✗ — **`user` is LOST on writepdb** (so the per-hider `user` id is an in-session-only field; never rely on it surviving a PDB round-trip. The `.bcm` sidecar reconciles it post-load — Phase 20.)
- **Column layout VMD writes (probe.log:68):** `record=ATOM  serial=    1 name= N1  altloc=  resname=BRU chain=A resseq=   1 x=   6.841 y=  13.739 z=  44.059 occ=  0.75 beta=-42.50 segid=ORIG elem= N` — 0-indexed string ranges: record 0–5, serial 6–10, **name 12–15**, altloc 16, **resname 17–19**, chain 21, resseq 22–25, x 30–37, y 38–45, z 46–53, occ 54–59, **beta 60–65**, segid 72–75, **elem 76–77**. (Matches `mergestructs.tcl:871` `string range $line 72 75` for segid.)
- **Trailer (probe.log:72-76):** writepdb emits **0 `TER` records and 1 `END`** for 1k8p, plus a leading `CRYST1` line. → Splice = read file, drop the `END` line, append hider records, write `END`. No TER handling needed.

### A2. Combined PDB via writepdb-then-splice → loads as ONE molecule (HIGHEST-RISK unknown, DE-RISKED)
- **Probe (P3, probe.log:695-708):** writepdb 1k8p (555) → strip END → append 5 hider `ATOM` records (resname GAM, beta -999.00 [%6.2f at the time], segid GAME) → END → `mol new`:
  - `combined_molid=2 numatoms=560 want=560 eq=1` — **originals + hiders are ONE molecule** ✓ (the core invariant; player cannot isolate hiders by toggling molecule visibility)
  - `sentinel_resname_GAM_count=5` — `resname GAM` parses from PDB cols 18–20 ✓
  - `sentinel_combined_count=5` — canonical selector `resname GAM and beta < 0` = 5 ✓
  - `sentinel_indices=555 556 557 558 559` — hider `index` values (stable within molid lifetime; registry keys on these)
  - `orig_atom0_name=N1`, `orig_last_real_name=O` — original atoms intact ✓
- **Overmatch warning (probe.log:699):** `sentinel_beta_lt0_count=6 (want 5)` — because atom0 still carried `beta=-42.50` from the P1 experiment. **Lesson: `beta < 0` ALONE over-matches any negative-beta atom; ALWAYS pair with `resname GAM`** (the canonical `resname GAM and beta < 0`). This is exactly why the spec mandates the combined selector.

### A3. `mol delete` + `mol new` → NEW monotonic molid; reps do NOT survive
- **Citation:** `vmd-ref/scripts/save_state.tcl:144-269` (save_state re-`mol new`s from path + re-applies reps because reload resets them); `vmd-ref/plugins/clonerep1.3/clonerep.tcl:92-96` (delrep 0 loop to clear).
- **Probe (P7, probe.log:810-813):** `mol delete $game_mol; set restored [mol new $pdb]` → `restored_molid=5 (monotonic_new=1)`, `restored_numatoms=555 orig=555 eq=1`, `leftover_hider_count=0` — **cleanup restores the original exactly, no hider residue remains** ✓
- **Researcher B's probe (tmp/probe15b/probe.log:264-265):** `m6b_numreps=1 (expect 1 -- reps do NOT survive)`, `m6b_rep0={Lines all Name Opaque}` — reload resets to 1 default Lines rep. → **backup.tcl MUST save+restore reps** (not mutation.tcl's job).

### A4. `molinfo $m get filename` → exact loadable path (for cleanup reload)
- **Probe (researcher B, tmp/probe15b/probe.log:193-217):** `filename_eq_passed=1`, `reload_numatoms=2597 eq=1`. → cleanup can `mol new [molinfo $orig get filename]`. **Capture the filename BEFORE `mol delete`** (it's gone after). The stored path is already Windows-format (forward slashes) because `to_vmd_path` ran at load time.

### A5. Sentinel tagging IN-PLACE via atomselect — sticks; rescues misaligned PDB columns
- **Probe (P6, probe.log:777-781):** after `atomselect $mc "resname GAM"; $sel set beta -999; $sel set segid GAME` (+ per-atom `user` 0..4):
  - `after_inplace_tag_count=5`, `chk_indices=555 556 557 558 559`, `chk_beta=-999.0`, `chk_segid=GAME GAME GAME GAME GAME`, `chk_user=0.0 1.0 2.0 3.0 4.0` — **all sentinels stick in-place** ✓
- **Column-misalignment pitfall PROVEN (P5, probe.log:760-770):** a deliberately shifted hider record (resname "GAM" placed 1 col left) → `bad_molid numatoms=556` (atom still LOADS, not dropped) BUT `bad_sentinel_GAM_count=0` (resname silently read as "AM"), `bad_atom_actual_resname=AM`. **No error — the sentinel is silently lost.** Then `atomselect "beta < 0" set resname GAM` → `fixed_resname={GAM GAM} fixed_segid={GAME GAME}` — **in-place `set` rescues the misaligned record** ✓ (the over-match to 2 was a probe artifact from atom0's stale beta; in a clean run it'd be 1).
- **Conclusion:** PDB columns are unreliable for the sentinel; **always set resname/beta/segid in-place via atomselect after load** (the spec's design, now empirically justified).

### A6. Bounding box / center for placeholder hider coords (Phase 16 does real placement)
- **Probe (P8, probe.log:816-819):** `molinfo $m get center` → `{5.122735 21.042933 35.328976}` — a **NESTED** 1-element list whose element is the 3-coord string. **`molinfo $m get {center x}` FAILS** (`molinfo: cannot find molinfo attribute 'x'`). `measure minmax` returned all-zeros (unreliable in this call form — do NOT use). The CA-select min/max loop (probe.log, P3) worked but builds a Tcl list (avoid on large mols per AGENTS.md perf).
- **Recommendation:** for Phase 15 placeholders, use the center: `lassign [lindex [molinfo $m get center] 0] cx cy cz` (one molinfo call, no list build), then place each hider at `center + tiny jitter`. Placement QUALITY is Phase 16; Phase 15 only needs hiders SOMEWHERE in the bounding region to prove the mechanism.

### A7. Hider record format — `%6.1f` beta is the CLEAN choice (proven)
- **Probe (probe2b.log:53-73):** with `format "...%6.1f..." -999.0 ...`:
  - `rec6_1 len=78` (fits, NO overflow), `resname=GAM beta=-999.0 segid=GAME elem= C`
  - `numatoms=556 eq=1`, `resname_GAM=1`, `GAM_and_beta_lt0=1`, **`segid_from_pdb=GAME`** (survives in PDB cols!), `beta_from_pdb=-999.0`
- **Contrast (`%6.2f`, probe.tcl P3):** `-999.00` is 7 chars → overflows the 6-col beta field by 1, shifting segid so VMD reads `segid=GAM` (not GAME) from the PDB. `resname GAM` + `beta<0` still worked (resname is before beta; VMD reads beta cols 61–66 = "-999.0" < 0), but segid-in-PDB was corrupted. In-place set fixed it. → **Use `%6.1f` (clean, 78 chars, segid GAME survives in PDB too) AND set in-place** (defense-in-depth).

## Recommended Approach — `vmd/lib/mutation.tcl`

### Module shape (mirrors `demos.tcl`: mol bridge, sources setup_state, `script_dir` captured at source time)
```tcl
# vmd/lib/mutation.tcl — MOL BRIDGE: PDB-rebuild + sentinel + cleanup.
# Sources setup_state.tcl (same lib/ dir) for the mol-bridge source-time pattern.
# Tcl 8.5 (no lmap/try; brace all expr; catch; foreach+lappend).
source [file join [file dirname [info script]] setup_state.tcl]

namespace eval ::biochemeleon::mutation {
    # Sentinel constants (mol-domain; registry.tcl stays pure with only HIDER_STATUS_HIDDEN).
    variable HID_RESNAME  "GAM"     ;# 3 chars — fits PDB resname cols 18-20 (4-char "GAME" silently dropped)
    variable HID_BETA    -999       ;# value; SELECTOR is "beta < 0" (never exact `beta -999`)
    variable HID_SEGID   "GAME"    ;# 4 chars — fits PDB segid cols 73-76
    variable HID_CHAIN   "G"       ;# hider chain (disjoint from real chains)
    variable HID_RESSEQ  9001      ;# hider residue number (disjoint from real resids)
    variable HID_ELEMENT "C"       ;# placeholder element (Phase 16 sets real blend element)
    variable HID_OCC     1.00
    variable script_dir [file dirname [info script]]  ;# frozen at source time (proc bodies can't use [info script] under `vmd -e`)
    namespace export make_placeholder_hiders write_combined_pdb tag_sentinels \
                     fetch_hider_indices mutate
}
```
:::note
**No `cleanup` proc in mutation.tcl.** The restore/cleanup reload is `backup.tcl::restore` (researchers B & C). mutation.tcl owns the **forward** mutate-reload only. This keeps backup self-contained for restore (mol delete + mol new + reps + viewpoint in one atomic proc) and avoids backup→mutation coupling. See "clean split" below.
:::

### Proc signatures (prescriptive — the planner turns these into tasks)

**1. `make_placeholder_hiders {molid count}` → list of hider records (PROVES the mechanism; Phase 16 does real sphere placement)**
- Returns a list of `{name x y z}` records. Names `G01`..`GNN` (2-digit zero-padded; `hider_count_cap`=50 so ≤ `G50`). Coords = molecule center + small deterministic jitter (e.g. `center + 0.5*i` on each axis) so they aren't all coincident.
- Center: `lassign [lindex [molinfo $molid get center] 0] cx cy cz` (A6 — nested-list pitfall). Wrap `molinfo` in `catch` (bad molid → empty center → return `{0 0 0}`).
- This proc reads coords ONLY; it does NOT write or load anything. Pure data prep.
```tcl
proc ::biochemeleon::mutation::make_placeholder_hiders {molid count} {
    variable HID_CHAIN
    if {[catch {molinfo $molid get center} c]} { lassign {0 0 0} cx cy cz } else { lassign [lindex $c 0] cx cy cz }
    set recs [list]
    for {set i 0} {$i < $count} {incr i} {
        set nm [format "G%02d" [expr {$i + 1}]]
        set x [expr {$cx + 0.5 * $i}]
        set y [expr {$cy + 0.3 * $i}]
        set z [expr {$cz + 0.2 * $i}]
        lappend recs [list $nm $x $y $z]
    }
    return $recs
}
```

**2. `write_combined_pdb {molid hider_records out_path}` → writes the combined PDB (writepdb-then-splice)**
- Step 1: `set all [atomselect $molid "all"]; $all writepdb $out_path; $all delete` (writes originals + CRYST1 + END; preserves beta/segid/occ — A1).
- Step 2: read `$out_path`, drop lines where `[string trim $l] eq "END"` or `$l eq ""`; keep the rest (CRYST1 + ATOM records; no TER for 1k8p — A1).
- Step 3: append one hider `ATOM` record per hider_record via `_hider_record` (strict 78-col format, A7); serial = `orig_n + 1 + i`.
- Step 4: write `END`; close.
- `out_path` MUST be Windows-visible (caller converts via `::biochemeleon::demos::to_vmd_path`; e.g. `[pwd]`-relative in the smoke, or `$env(TEMP)/...` in game.tcl). Re-`writepdb` to the SAME path is fine (overwrite; no `rm` needed).
```tcl
proc ::biochemeleon::mutation::_hider_record {serial name x y z} {
    variable HID_RESNAME HID_CHAIN HID_RESSEQ HID_OCC HID_SEGID HID_ELEMENT
    # 78-char ATOM record. %6.1f beta -> "-999.0" (6 cols, NO overflow; segid GAME survives).
    return [format "ATOM  %5d %4s%1s%-3s %1s%4d%1s   %8.3f%8.3f%8.3f%6.2f%6.1f      %-4s%2s" \
        $serial $name " " $HID_RESNAME $HID_CHAIN $HID_RESSEQ " " $x $y $z $HID_OCC $HID_BETA $HID_SEGID $HID_ELEMENT]
}
proc ::biochemeleon::mutation::write_combined_pdb {molid hider_records out_path} {
    set all [atomselect $molid "all"]
    $all writepdb $out_path
    set orig_n [$all num]
    $all delete
    set fh [open $out_path r]; set lines [split [read $fh] \n]; close $fh
    set fh [open $out_path w]
    foreach l $lines { if {[string trim $l] eq "END" || $l eq ""} continue; puts $fh $l }
    set serial [expr {$orig_n + 1}]
    foreach r $hider_records {
        foreach {nm x y z} $r { break }
        puts $fh [_hider_record $serial $nm $x $y $z]
        incr serial
    }
    puts $fh "END"
    close $fh
    return $orig_n
}
```

**3. `tag_sentinels {molid}` → set resname/beta/segid/user in-place; return hider `index` list**
- Selects `resname $HID_RESNAME` (parsed from PDB cols 18–20, always reliable — A2/A5), then `$sel set beta -999; $sel set segid GAME`, and per-atom `user` = ordinal (in-session hider id; lost on writepdb — A1 — but the `.bcm` reconciles). Returns `[$sel get index]`. **Always `$sel delete`.**
```tcl
proc ::biochemeleon::mutation::tag_sentinels {molid} {
    variable HID_RESNAME HID_BETA HID_SEGID
    set sel [atomselect $molid "resname $HID_RESNAME"]
    $sel set beta  $HID_BETA
    $sel set segid $HID_SEGID
    set idxs [$sel get index]
    set u 0
    foreach i $idxs { set one [atomselect $molid "index $i"]; $one set user $u; $one delete; incr u }
    set idxs [$sel get index]  ;# re-read after the per-atom loop (defensive)
    $sel delete
    return $idxs
}
```

**4. `fetch_hider_indices {molid}` → the DI fn injected into `registry::reconstruct_from_sentinels`**
- Canonical selector `resname GAM and beta < 0` (NEVER `beta < 0` alone — A2 over-match). Returns `[$sel get index]`. `game.tcl` injects `list ::biochemeleon::mutation::fetch_hider_indices $new_molid` as the `fetch_hider_ids` command prefix (matches the existing `registry.tcl:34` `foreach idx [{*}$fetch_hider_ids]` DI shape).
```tcl
proc ::biochemeleon::mutation::fetch_hider_indices {molid} {
    variable HID_RESNAME
    set sel [atomselect $molid "resname $HID_RESNAME and beta < 0"]
    set idxs [$sel get index]
    $sel delete
    return $idxs
}
```

**5. `mutate {molid hider_records out_path}` → forward rebuild; returns new game molid**
- Writes the combined PDB, `mol delete $molid`, `mol new <combined> type pdb waitfor all`, tags sentinels in-place, returns the new molid. **Does NOT save/restore reps/viewpoint** (backup.tcl's job — game.tcl calls `backup::snapshot` BEFORE `mutate` and `backup::restore` AFTER).
```tcl
proc ::biochemeleon::mutation::mutate {molid hider_records out_path} {
    write_combined_pdb $molid $hider_records $out_path
    mol delete $molid
    set new_m [mol new $out_path type pdb waitfor all]
    tag_sentinels $new_m
    return $new_m
}
```

**No `cleanup` proc in mutation.tcl** — the restore/cleanup reload (`mol delete` game + `mol new` original + re-apply reps + restore viewpoint) is `backup.tcl::restore` (researcher B). mutation.tcl owns the forward mutate-reload only. See the clean split below.

### The clean split between mutation.tcl, backup.tcl, and game.tcl (RECONCILED with researchers B & C)
- **`mutation.tcl` OWNS the forward mutate-reload** — the only component that calls `writepdb`, builds the combined PDB, and does the forward `mol delete`-original + `mol new`-combined. Procs: `make_placeholder_hiders`, `write_combined_pdb`, `tag_sentinels`, `fetch_hider_indices`, `mutate`. It NEVER touches reps, viewpoint, `mol addrep`, or `molinfo ... matrix`, and NEVER does the restore-reload.
- **`backup.tcl` OWNS the restore-reload (cleanup) + scene state** — the only component that does the restore `mol delete`-game + `mol new`-original, re-applies reps, and restores viewpoint. It reads/writes viewpoint matrices (`molinfo $m get {rotate_matrix center_matrix scale_matrix global_matrix}`, per `save_state.tcl:52-60`) and the rep list (clonerep form: `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` + `mol delrep 0` loop + `mol addrep`/`mol mod*`, per `clonerep.tcl:103,127` / `save_state.tcl:80-137`) and captures `molinfo $m get filename`. Procs: `snapshot {molid}` (returns `{filename viewpoint reps}`), `restore {snapshot}` (does `mol delete` + `mol new` + reps + viewpoint → returns new molid). Researcher B's `restore` is the FULL cleanup (atomic — no window where the new molid has no reps).
- **`game.tcl` orchestrates** (researcher C), owns the `game_state` dict, owns **no** `mol delete`/`mol new` directly:
  - start: `set snap [backup::snapshot $m]; set hiders [mutation::make_placeholder_hiders $m $count]; set new_m [mutation::mutate $m $hiders $out_path]; backup::restore_reps_viewpoint $new_m $snap; ::biochemeleon::registry::reconstruct_from_sentinels <DI fn $new_m>` (restore reps/viewpoint on the game molid after mutate — see B's doc for whether `restore` is split vs a `restore_reps_viewpoint` helper that takes a pre-existing molid)
  - cleanup/restart: `set new_m [backup::restore $snap]; ::biochemeleon::registry::reset` (restore = mol delete game + mol new original + reps + viewpoint)
- **Rationale for backup owning the restore-reload (not mutation):** atomic restore (reps/viewpoint applied to the SAME new molid in one proc — no inter-module handoff of a bare new molid); backup self-contained for restore; no backup→mutation coupling. This matches researchers B & C. mutation.tcl and backup.tcl do NOT import each other.

### Exact PDB hider record (the line the planner needs — copy verbatim)
78-char `ATOM` record, 0-indexed columns: record 0–5=`ATOM  `, serial 6–10, blank 11, name 12–15, altLoc 16, resname 17–19=`GAM`, blank 20, chain 21=`G`, resSeq 22–25=`9001`, iCode 26, blank 27–29, x 30–37, y 38–45, z 46–53, occ 54–59, beta 60–65=`-999.0` (**`%6.1f`**), blank 66–71, segid 72–75=`GAME`, element 76–77=` C`.
```
ATOM    556  G01 GAM G9001       5.123  21.043  35.329  1.00-999.0      GAME C
```
Tcl builder (proven, probe2b.log:53):
```tcl
format "ATOM  %5d %4s%1s%-3s %1s%4d%1s   %8.3f%8.3f%8.3f%6.2f%6.1f      %-4s%2s" \
    $serial $name " " "GAM" "G" 9001 " " $x $y $z 1.00 -999.0 "GAME" "C"
```

## Pitfalls (each with probe proof)

### Pitfall 1: `beta=-999.00` (`%6.2f`) OVERFLOWS the 6-column beta field
**What:** `-999.00` is 7 chars; PDB beta is cols 61–66 (6 wide). `%6.2f` emits 7 chars, overflowing into col 67 and shifting segid/element right by 1.
**Probe proof (probe.log:703):** with `%6.2f`, VMD read `segid=GAM` (not GAME) from the PDB. `resname GAM` + `beta<0` still worked (resname is before beta; VMD reads beta cols 61–66 = "-999.0" < 0), but segid-in-PDB was corrupted. In-place `$sel set segid GAME` fixed it (P6: `chk_segid=GAME`).
**Avoid:** format beta as **`%6.1f` → `-999.0`** (6 chars, fits — proven probe2b.log:72 `segid_from_pdb=GAME`). AND set segid in-place regardless (defense-in-depth).
**Warning signs:** `resname GAM` count is right but `segid GAME` count is 0 after `mol new` (before in-place set).

### Pitfall 2: PDB column misalignment SILENTLY loses the sentinel (NO error)
**What:** if `resname GAM` is written 1 column off, VMD loads the atom (count includes it) but reads resname as e.g. "AM" — the hider is invisible to the sentinel selector, with no error.
**Probe proof (probe.log:760-765):** shifted record → `numatoms=556` (loaded) but `bad_sentinel_GAM_count=0`, `bad_atom_actual_resname=AM`.
**Avoid:** **always set resname/beta/segid IN-PLACE via atomselect after load** (P5/P6 proven). Use the canonical selector `resname GAM and beta < 0` (not `beta < 0` alone — over-matches any negative-beta real atom, probe.log:699).
**Warning signs:** `molinfo numatoms` is right but `atomselect "resname GAM" num` < expected.

### Pitfall 3: `atomselect` objects LEAK; a dangling selection on a deleted molecule returns STALE data SILENTLY
**Citation:** `vmd-ref/scripts/atomselect.tcl` (atomselect is a command object); AGENTS.md (ramaplot pattern `ramaplot.tcl:220,267`).
**Avoid:** **`$sel delete` after EVERY use**, especially before any `mol delete`/reload. **Never cache a selection across `mol delete`/`mol new`** — the molid changes; the old selection silently returns stale data. `mutate` and `cleanup` create fresh selections on the NEW molid only.
**Warning signs:** selection `num`/`get` returns data from a molecule you already deleted.

### Pitfall 4: `molid` CHANGES on every `mol delete`+`mol new`; `index` is stable only within a molid's lifetime
**Probe proof (probe.log:810, B:264):** `restored_molid=5 (monotonic_new=1)`. Molids are monotonic, never reused.
**Avoid:** `mutate`/`cleanup` RETURN the new molid; the caller (game.tcl) updates its molid handle. The registry keys on atom `index` (stable within a molid's lifetime) and **rebuilds from sentinels after every reload** via `fetch_hider_indices` (DI into `registry::reconstruct_from_sentinels`). Never persist `index` across a rebuild.

### Pitfall 5: `molinfo $m get center` is a NESTED list `{{x y z}}`; `molinfo $m get {center x}` does NOT exist
**Probe proof (probe.log:816-818):** `molinfo_center={5.122735 21.042933 35.328976} (llength=1)`; `molinfo_center_x_ERR=molinfo: cannot find molinfo attribute 'x'`. `measure minmax` returned all-zeros (unreliable here).
**Avoid:** `lassign [lindex [molinfo $m get center] 0] cx cy cz` — extract the inner 3-list, then split. Do NOT index `[lindex ... 0]`/`[lindex ... 1]`/`[lindex ... 2]` directly on the outer list (you'll get the whole string / empty / empty — probe2.tcl first attempt failed exactly this way: `expected floating-point number but got "5.122735 21.042933 35.328976"`).

### Pitfall 6: `atomselect get` has NO `icode` attribute (hand-write-all aborted)
**Probe proof (probe.log:712):** `cannot find attribute 'icode': in atomsel: get` — the `get {serial name altloc resname chain resid icode occupancy beta segid element x y z}` aborted, `rows` never set, the hand-written combined PDB got 0 original records (only 5 hiders).
**Avoid:** **use writepdb-then-splice** (VMD's own writer handles every field correctly — A1). If you ever hand-write originals, drop `icode` from the `get` list (insertion codes are rare; 1k8p has none) — but you don't need to, because writepdb-then-splice only hand-writes the HIDER records (which we fully control).

### Pitfall 7: `user` field does NOT survive `writepdb` (PDB round-trip loses it)
**Probe proof (probe.log:95):** set `user=12345`, writepdb, reload → `roundtrip_user_survives=0.0`. (beta/segid/occ DID survive — A1.)
**Avoid:** treat `user` as an IN-SESSION hider id only (set in-place after load, never read from a PDB). The `.bcm` sidecar (Phase 20) reconciles `user`/rep/status post-load. For Phase 15, `user` is optional; the registry keys on `index`, not `user`.

### Pitfall 8: serial overflow on >99999 atoms (NOT a Phase 15 issue, but document)
**What:** PDB serial is cols 7–11 (5 wide) → max 99999. Demos are ≤3779 atoms (4wb3) + ≤50 hiders → safe. Large membrane (100k+) overflows; VMD is lenient (parses past the column) but it's a known PDB-format limit.
**Avoid:** Phase 15 (demos) is safe. Phase 9 (large demos) must handle it (e.g. wrap serial, or VMD tolerates overflow). Out of scope here.

### Pitfall 9: temp PDB path MUST be Windows-visible; `rm` is denied in WSL
**Avoid:** write the combined PDB to a `C:/`-style path (convert via `::biochemeleon::demos::to_vmd_path`; `/mnt/c/...` is NOT readable by Windows VMD). Do NOT use bash `rm` to clean temp files (denied by `opencode.json`); use tcl `file delete` (run inside VMD) or just overwrite the same path on each `mutate`. For the smoke, use a `[pwd]`-relative path (staging root is already under `/mnt/c`).

## Code Examples (verified patterns)

### The full mutate→verify→cleanup cycle (the smoke core, probe-proven)
```tcl
# Source the lib (smoke runs under `vmd -e`; [info script] is EMPTY in -e'd scripts,
# so source by [pwd]-relative path -- the lib's own [info script] works because it
# was `source`d, not `-e`d. Phase 13+ verified pattern.)
source [file join [pwd] vmd lib setup_state.tcl]
source [file join [pwd] vmd lib registry.tcl]
source [file join [pwd] vmd lib mutation.tcl]

set pdb [::biochemeleon::demos::to_vmd_path "[pwd]/vmd/data/demos/1k8p.pdb"]
set outpdb [::biochemeleon::demos::to_vmd_path "[pwd]/tmpout/combined.pdb"]
file mkdir "[pwd]/tmpout"

set m0 [mol new $pdb type pdb waitfor all]              ;# 555 atoms
set orig_n [molinfo $m0 get numatoms]                    ;# 555
set hiders [::biochemeleon::mutation::make_placeholder_hiders $m0 5]
set m1 [::biochemeleon::mutation::mutate $m0 $hiders $outpdb]   ;# mol delete m0; mol new combined; tag
# asserts:
#   molinfo $m1 get numatoms == orig_n + 5  (560)
#   [atomselect $m1 "resname GAM and beta < 0" num] == 5
#   [atomselect $m1 "index 0" get name] == a real name (N1), unchanged
# registry DI:
::biochemeleon::registry::reconstruct_from_sentinels \
    [list ::biochemeleon::mutation::fetch_hider_indices $m1]
#   ::biochemeleon::registry::is_hider 555 -> 1,  is_hider 0 -> 0
# cleanup (backup.tcl::restore owns the full reload + reps + viewpoint; this is
# the underlying mechanism it wraps):
mol delete $m1
set m2 [mol new $pdb type pdb waitfor all]   ;# = backup::restore's mol delete + mol new
#   molinfo $m2 get numatoms == 555, [atomselect $m2 "resname GAM" num] == 0
```

## Test Strategy — headless smoke for mutation.tcl

**Runner:** `bash -ic 'cd tmp/probe15a && vmd -dispdev text -e phase15_mutation_smoke.tcl -eofexit < /dev/null'` (staging: `mkdir -p tmp/probe15a && cp -r vmd tmp/probe15a/`; copy the smoke script in). **Note:** on this machine VMD takes ~3–4 min per run (slow startup + the `bash -ic` wrapper hangs on `tcsetattr` at exit — the probe COMPLETES and writes the marker before the shell returns; grep the log, don't trust the shell's return timing). Parse result from `BCHM_SMOKE_RESULT` markers (VMD does NOT propagate tcl exit codes — Phase 13 Pitfall 4; never check `$?`).

**Smoke skeleton (turn into `vmd/smoke/phase15_mutation_smoke.tcl`):**
```tcl
# phase15_mutation_smoke.tcl — Phase 15 mutation.tcl gate. Tcl 8.5.
set failures [list]
proc _bail {tag msg} { upvar 1 failures f; lappend f "$tag:$msg" }
source [file join [pwd] vmd lib setup_state.tcl]
source [file join [pwd] vmd lib registry.tcl]
source [file join [pwd] vmd lib mutation.tcl]   ;# Phase 15 NEW
# (backup.tcl + game.tcl are researchers B/C; this smoke tests mutation.tcl ALONE + registry DI)

set pdb [::biochemeleon::demos::to_vmd_path "[pwd]/vmd/data/demos/1k8p.pdb"]
file mkdir "[pwd]/tmpout"
set outpdb [::biochemeleon::demos::to_vmd_path "[pwd]/tmpout/comb15.pdb"]

# ---- 1. mutate: load 1k8p (555) -> 5 placeholder hiders -> combined mol ----
set m0 [mol new $pdb type pdb waitfor all]
set orig_n [molinfo $m0 get numatoms]                       ;# 555
if {$orig_n != 555} { _bail orig_atoms "exp=555 got=$orig_n" }
set hiders [::biochemeleon::mutation::make_placeholder_hiders $m0 5]
if {[llength $hiders] != 5} { _bail hider_count "[llength $hiders]" }
set m1 [::biochemeleon::mutation::mutate $m0 $hiders $outpdb]
# 1a. new molid is monotonic
if {$m1 <= $m0} { _bail new_molid "m1=$m1 <= m0=$m0" }
# 1b. atom count = orig + 5
set n1 [molinfo $m1 get numatoms]
if {$n1 != 555 + 5} { _bail game_atoms "exp=560 got=$n1" }
# 1c. canonical sentinel selector == 5
set sel [atomselect $m1 "resname GAM and beta < 0"]
if {[$sel num] != 5} { _bail sentinel_count "exp=5 got=[$sel num]" }
# 1d. indices are the last 5 (555..559)
set want_idxs [list 555 556 557 558 559]
if {[$sel get index] ne $want_idxs} { _bail sentinel_idx "got=[$sel get index]" }
# 1e. in-place segid/beta stick
if {[$sel get segid] ne "GAME GAME GAME GAME GAME"} { _bail sentinel_segid "got=[$sel get segid]" }
$sel delete
# 1f. original atoms intact (index 0 still the real N1)
set s0 [atomselect $m1 "index 0"]
if {[$s0 get name] ne "N1"} { _bail orig_intact "index0 name=[$s0 get name] want N1" }
$s0 delete

# ---- 2. registry DI: reconstruct_from_sentinels + is_hider ----
::biochemeleon::registry::reconstruct_from_sentinels \
    [list ::biochemeleon::mutation::fetch_hider_indices $m1]
if {![::biochemeleon::registry::is_hider 555]} { _bail reg_555 "not registered" }
if {![::biochemeleon::registry::is_hider 559]} { _bail reg_559 "not registered" }
if {[::biochemeleon::registry::is_hider 0]}   { _bail reg_0 "real atom 0 wrongly registered" }

# ---- 3. cleanup MECHANISM: raw mol delete + mol new original -> no hider residue.
# (In the real game, backup.tcl::restore owns this reload + re-applies reps/viewpoint;
#  this smoke proves the underlying mechanism since it tests mutation.tcl ALONE.)
mol delete $m1
set m2 [mol new $pdb type pdb waitfor all]
if {$m2 <= $m1} { _bail cleanup_molid "m2=$m2 <= m1=$m1" }
if {[molinfo $m2 get numatoms] != 555} { _bail cleanup_atoms "exp=555 got=[molinfo $m2 get numatoms]" }
set left [atomselect $m2 "resname GAM and beta < 0"]
if {[$left num] != 0} { _bail cleanup_leftover "exp=0 got=[$left num]" }
$left delete

# ---- report ----
set nfail [llength $failures]
if {$nfail == 0} { puts "BCHM_SMOKE_RESULT PASS=1 FAIL=none" } \
else { puts "BCHM_SMOKE_RESULT PASS=0 FAIL=[join $failures ,]" }
```
**Asserts success criteria 1, 2, 3 (registry DI) from the phase goal.** Criterion 4 (viewpoint+rep restore) is backup.tcl's smoke (researcher B). Run this smoke from a `/mnt/c` cwd; script + `vmd/` staged to a Windows-visible path first.

## State of the Art

| Old Approach | Current Approach (Phase 15) | Why |
|--------------|------------------------------|-----|
| v1 PyMOL `cmd.pseudoatom(object=existing)` — in-place atom insertion | v2 VMD **PDB-rebuild** — write combined PDB + `mol delete`/`mol new` | VMD has NO in-place atom insertion (`mol new atoms N` makes a SEPARATE molecule; no merge). PDB-rebuild is the ONLY way to get hiders into the same molecule. |
| v1 registry keyed on atom `id` (PyMOL stable global id) | v2 registry keyed on atom `index` (stable within a molid lifetime; molid changes on reload) | VMD has NO global atom `id`; identity = `(molid, index)`. Rebuild registry from sentinels after every reload. |
| v1 sentinel `segi='GAME'` + `b=-999` set via `cmd.alter` in-place (PyMOL) | v2 sentinel `resname=GAM` + `beta=-999` + `segid=GAME` set via `atomselect` in-place after `mol new` | Same concept, VMD verbs. `resname GAM` (3 chars) added because PDB resname is 3 cols (4-char "GAME" silently dropped). In-place set is robust against PDB column bugs (proven). |
| v1 `cmd.remove("segi GAME")` — per-atom cleanup in-place | v2 `mol delete` whole game molecule + `mol new <original.pdb>` | VMD has NO per-atom delete. Cleanup is always whole-molecule reload. |

**Deprecated/outdated for v2:**
- `save_state` for game persistence — does NOT preserve beta/user/segid (`save_state.tcl:39-46`). The combined PDB + `.bcm` sidecar replaces it (Phase 20, NOT this phase).
- `measure minmax` for bounding box — returned all-zeros in probe (unreliable call form). Use `molinfo $m get center` (nested list) instead.

## Open Questions (need a human decision or later phase)

1. **Temp PDB location for the combined file in real (non-smoke) use.** Phase 15's smoke uses `[pwd]`-relative. For game.tcl, options: (a) next to the original PDB (`<orig>.game.pdb` — guarantees Windows-visible but writes to the user's dir), (b) `$env(TEMP)/biochemeleon_game.pdb` (system temp, always writable), (c) a plugin-local cache dir. **Recommendation:** (b) `$env(TEMP)` — clean, always writable, doesn't pollute the user's PDB dir. The planner should confirm with researcher C (game.tcl). mutation.tcl itself is path-agnostic (takes `out_path`).
2. **Who owns `mol delete`/`mol new`? — RESOLVED (reconciled with B & C).** mutation.tcl owns the **forward** mutate-reload (`mutate`: mol delete original + mol new combined + tag sentinels). backup.tcl owns the **restore** reload (`restore`: mol delete game + mol new original + re-apply reps + restore viewpoint — atomic). game.tcl owns **neither** `mol delete`/`mol new` directly. This doc originally proposed a `cleanup` proc in mutation.tcl; it has been REMOVED in favor of backup.tcl's `restore` (cleaner: atomic restore, no backup→mutation coupling, matches B & C). See "The clean split" above.
3. **DI style for `reconstruct_from_sentinels`: proc-prefix (this doc) vs `apply`-lambda (researcher C).** Both work with the existing `registry.tcl:34` `foreach idx [{*}$fetch_hider_ids]` DI shape:
   - **This doc (proc-prefix):** `fetch_hider_indices` lives in mutation.tcl (the mol bridge — natural home for atomselect); game.tcl injects `[list ::biochemeleon::mutation::fetch_hider_indices $new_m]`. Keeps game.tcl a pure orchestrator (no inline atomselect); `fetch_hider_indices` is reusable (the smoke asserts it directly).
   - **Researcher C (apply-lambda):** game.tcl injects `[list apply {{molid} { ...atomselect inline... }} $game_molid]` (C probed this: `BCHM_SMOKE_RESULT PASS=1`). Keeps the atomselect in game.tcl (the composition root, allowed to be mol-coupled); mutation.tcl has no public `fetch_hider_indices`.
   - **Recommendation:** the proc-prefix style (this doc) — atomselect belongs in the mol bridge (mutation.tcl), not the orchestrator; `fetch_hider_indices` is reusable and directly smoke-testable. **The planner should reconcile this with researcher C** (it's a stylistic DI choice; both are functionally correct and probe-verified). Either way, `registry.tcl` stays pure (the `{*}$fetch_hider_ids` expansion is DI-agnostic).
4. **`tclsh` is NOT installed in WSL** — contradicts `vmd/AGENTS.md` ("tclsh is available in WSL"). `which tclsh` → `command not found`; no `/usr/bin/tcl*`. This affects the **pure-layer registry tcltest** (`vmd/tests/test_registry.test`) which AGENTS.md says runs via `tclsh`. **For MY smoke (mutation.tcl), headless VMD works (proven this session).** For the registry pure tests (researcher C), options: run tcltest under headless VMD (`vmd -dispdev text -e test_registry.test`), or flag for a human to install `tcl-dev`. **Recommendation:** flag this discrepancy to the orchestrator; researcher C decides. (Not a mutation.tcl blocker.)
5. **`ATOM` vs `HETATM` record type for hiders.** Probe used `ATOM` (loaded fine). `HETATM` is more PDB-correct for a non-standard residue `GAM`, and the sentinel selector `resname GAM` is record-type-agnostic. **Recommendation:** `ATOM` (proven) is fine; `HETATM` is an equivalent drop-in if the planner prefers PDB-correctness. Low impact.

## Sources

### Primary (HIGH confidence — verified by headless probe this session)
- `tmp/probe15a/probe.log` — P1–P8 (writepdb round-trip, PDB columns, combined-PDB splice, misalignment, in-place tagging, cleanup, bounding box)
- `tmp/probe15a/probe2b.log` — `%6.1f` beta format confirmation (78-char line, segid GAME survives in PDB)
- `tmp/probe15b/probe.log` — researcher B's probe (molinfo filename reload, reps reset on reload) — cross-checked for cleanup proc

### Reference (HIGH confidence — vmd-ref/ source)
- `vmd-ref/scripts/save_state.tcl:39-46` (beta/user/segid NOT restored), `:52-60` (viewpoint matrices), `:80-137` (rep save/restore), `:144-269` (mol new from path)
- `vmd-ref/scripts/atomselect.tcl` (atomselect command object semantics)
- `vmd-ref/plugins/clonerep1.3/clonerep.tcl:92-96` (delrep 0 loop), `:103,127` (rep save/restore form)
- `vmd-ref/plugins/mergestructs1.1/mergestructs.tcl:855-903` (PDB column handling — `string range $line 72 75` = segid), `:805-839` (mol new + atomselect + $sel delete + mol delete lifecycle)
- `vmd/AGENTS.md` (domain rules: no in-place insert, no undo, sentinel GAM/-999/GAME, `beta < 0` selector, atomselect leaks)
- `vmd/lib/demos.tcl` (script_dir capture pattern, `to_vmd_path`, combined-braces molinfo form — reuse these)
- `vmd/lib/registry.tcl` (existing DI shape: `foreach idx [{*}$fetch_hider_ids]` — matches `fetch_hider_indices`)
- `pymol/biochemeleon/mutation.py` (v1 sentinel/registry CONCEPT — pseudoatom mechanism does NOT port; sentinel resname/beta concept ports)
- `pymol/biochemeleon/registry.py:100-160` (v1 HiderRecord schema — concept port; v2 keys on `index` not `(object, id)`)

### Secondary (MEDIUM — prior research, cross-checked)
- `.planning/research/ARCHITECTURE.md:287-345` (Pattern 4 PDB-rebuild, Pattern 5 sentinel — prior probe3 confirmed same-molid invariant; this session's probe confirms with the EXACT Phase 15 sentinel GAM)
- `.planning/research/PITFALLS.md:30-131` (Pitfalls 1-3,7: no in-place insert, no undo/no per-atom delete, no global id, save_state loses atom mods)

## Metadata

**Confidence breakdown:**
- Standard stack (writepdb/mol new/atomselect/molinfo): HIGH — every API verified by probe with output cited.
- PDB column format + hider record builder: HIGH — `%6.1f` 78-char format proven (probe2b.log:53-73); column layout confirmed against VMD's own writepdb output (probe.log:68) and mergestructs.tcl:871.
- Combined-PDB mechanism (same-molid invariant): HIGH — 555+5=560 atoms, `resname GAM and beta < 0`=5 proven (probe.log:695-708).
- Sentinel in-place tagging + misalignment mitigation: HIGH — P5/P6 proven.
- Cleanup (restore original exactly): HIGH — P7 proven (new molid, 555 atoms, 0 hider residue).
- Bounding box (`molinfo center`): HIGH (nested-list pitfall documented); `measure minmax`: LOW (returned zeros — do NOT use).
- mutation/backup proc split: MEDIUM — reconciled with researchers B & C (mutation owns forward mutate-reload; backup owns restore-reload/cleanup; game owns neither). Design choice, not probe-verified as a whole; the Phase 15 capstone smoke + game.tcl integration confirm.

**Research date:** 2026-08-30
**Valid until:** 2026-09-29 (30 days — stable VMD 1.9.3 target; no upstream changes)
