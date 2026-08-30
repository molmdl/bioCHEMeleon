# Phase 16: MVP Core Loop (Sphere) — Research (sphere generation + found-marking)

**Researched:** 2026-08-30
**Domain:** VMD 1.9.3 sphere-hider placement (`measure minmax`), VDW rep rendering/blending, found-marking without breaking pickability or the sentinel contract, found-state storage
**Confidence:** HIGH (all API claims probe-verified headlessly against the real VMD 1.9.3 Windows install on the bundled 1k8p demo, using the real Phase-15 pipeline via `game::start_game`; UG quotes from the version-matched local UG text + ks.uiuc.edu node140)

**Probe scripts + full outputs:** `tmp/biochemeleon-vmd/probe16_place.tcl`, `probe16b.tcl`, `probe16c.tcl`, `probe16_found.tcl` (gitignored staging; re-run recipe at bottom).

---

## 1. Executive Summary

Phase 16 turns the Phase-15 placeholder pipeline into the playable sphere loop. **Placement** ports v1's proven strategy 1:1: uniform-random points inside the molecule's bounding box, obtained headlessly via `measure minmax [atomselect $m all]` (probe-verified return format: a 2-element list of two 3-float lists). The pure sampler (`sphere_positions {minmax n {seed {}}}`) lives in a new pure `vmd/lib/generators.tcl` (the tcl port of v1's `generators.py`, tcltest-able); `mutation::make_placeholder_hiders` swaps its placeholder jitter body for `measure minmax` + the sampler, keeping its `{molid count}` signature and `{name x y z}` record shape frozen (per 15-05).

**Rendering + blending come almost free in VMD:** hider atoms already carry element C (PDB cols 77-78, phase-15) → VMD assigns them **radius 1.7, identical to real carbons** (probe F6/F7). One hidden-rep (`VDW` style + `Element` coloring → cyan, matching real carbons under default Name coloring) plus one found-rep (`VDW` + `ColorID 7` green) give the whole visual layer with two reps. Setup state has **no** color/difficulty blending params (verified: 11 DEFAULTS keys, none color-related) → fixed sensible defaults, nothing to wire, matching v1's zero-param MVP.

**Found-marking (the subtle one) is solved with a per-atom `user2` flag + a two-rep split.** VMD has NO per-atom color override (v1's `cmd.color` has no analog — colors are per-rep coloring methods). Instead: mark found = set `user2 1` on the atom (batched list-set) + re-issue `mol modselect` on both hider reps (REQUIRED: per UG node140, rep selections re-evaluate per *timestep* — a static molecule never re-evaluates on atom-field change). The UG node140 caveat "**Hidden reps cannot be picked and do not show any graphics**" is per-REP, not per-atom: we never hide the hider reps, found hiders stay visible (green) → remain pickable → the caller-side registry status check (v1's "Already found!" pattern) is what prevents double-counts; `registry::mark_found` is an idempotent overwrite (probe F19), so the guard MUST be in the caller. Registry `status` stays the single source of truth (LOOP-02); the game_state dict shape stays frozen.

**Primary recommendation:** swap `make_placeholder_hiders`' body (uniform-bbox via `measure minmax` + pure sampler), add a small mol-bridge `vmd/lib/hiders.tcl` (add_hider_reps / mark_found_visual), extend pure `registry.tcl` with `status_of`/`count_remaining`/`remaining_by_rep` + optional rep field, and add `game::on_pick` composing registry + visual marking — everything else (start_game order, DI line, game_state shape) unchanged.

---

## 2. Standard Stack

No new libraries — Tcl 8.5.6 stdlib + VMD built-in commands only (dependency rule: zero external deps).

### Core (VMD commands used this phase — all probe-verified)

| Command | Verified syntax | Purpose | Evidence |
|---------|----------------|---------|----------|
| `measure minmax $sel` | returns `{{xmin ymin zmin} {xmax ymax zmax}}` | bounding box for placement | probe16_place P2; UG: "Returns two vectors, the first containing the minimum x, y, and z coordinates of all atoms in selection, and the second containing the corresponding maxima" |
| `measure center $sel` | returns FLAT `{x y z}` (len 3) | optional (bbox math needs minmax, not center) | probe16_place P4 |
| `mol addrep $m` | (molid) | add rep (inherits current defaults until mod*ed) | probe16c C2 (numreps 1→2) |
| `mol modstyle <rep> <molid> VDW [res scale]` | **(rep, molid, style)** order; VDW takes exactly 2 params (resolution, sphere-scale) | hider spheres | probe16c C3; probe16_place P8-P12 (wrong order errors) |
| `mol modcolor <rep> <molid> Element` | per-rep coloring method | hidden hiders = carbon color | probe16c C6 |
| `mol modcolor <rep> <molid> ColorID <id>` | id is a 4th arg; read-back `color` = `"ColorID 7"` | found hiders = green | probe16c C5 |
| `mol modselect <rep> <molid> <seltext>` | re-issues/forces rep selection re-eval | found-flag repaint | probe16_found F17 |
| `atomselect ... set user2 <list>` | batched list form works; values are FLOATS (0.0/1.0) | per-atom found flag | probe16_found F9/F14 |
| `atomselect $m "resname GAM and beta < 0 and user2 > 0"` | `user2` IS a selection keyword; `>`, `<`, `==`, `not (...)` all parse | found/unfound selectors | probe16_found F8 |
| `mol showrep $m <rep>` | **(molid, rep)** order (OPPOSITE of mod*!); read-back `'1'`/`'0'` | verify reps shown | probe16_place P18-P20; viewmaster.tcl:259 |
| `mol repname $m <rep>` | read-only getter → `rep2`, `rep3` | stable rep names | probe16_found F13 |
| `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` | COMBINED-braces form ONLY | headless rep verification | probe16c C2-C8; backup.tcl:35-36 |

### Pure-layer (tcltest-able, no VMD)

| Module | New surface | Notes |
|--------|-------------|-------|
| `vmd/lib/generators.tcl` (NEW, pure) | `sphere_positions {minmax n {seed {}}}` → list of `{x y z}` | direct port of v1 `generators.py::generate_sphere_positions`; stdlib `rand()`/`srand` only |
| `vmd/lib/registry.tcl` (extend, pure) | `status_of {idx}`, `count_remaining {}`, `remaining_by_rep {}`; optional `rep` arg on `reconstruct_from_sentinels` | all `dict` ops over `_records` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `user2` flag + rep split | `mol showrep off` per hider | showrep hides a WHOLE rep → kills pickability of everything in it (UG node140). Cannot hide one atom. REJECTED for found-marking (fine for the Phase-19 found-hider *dropdown*, which toggles the whole found-rep) |
| `user2` flag | occupancy flag (`occ 1.00`→`0.0`) or name rename (G01→F01) | occupancy/name survive PDB round-trips but entangle game state with structure fields and confuse .bcm reconciliation; user2 is a dedicated free per-atom channel (user is taken — tag_sentinels stores ordinals there) |
| `Element` coloring for hidden rep | `ColorID 10` (cyan) | Element auto-tracks the hider element (C→cyan) with zero params; ColorID hard-codes the id. Either works; Element is self-maintaining |
| CPK style | VDW style | VDW is the GAME_REPS name for the sphere tier (setup rows say "VDW"); VDW takes 2 params vs CPK's 3 with a DIFFERENT order (probe C3/C4) — less to get wrong |
| Two reps (hidden/found) | one rep + `mol modcolor` on find | modcolor is per-rep (all GAM atoms recolor) — no per-atom color in VMD. Two reps is the standard VMD technique (FEATURES.md:77 hint pattern) |

---

## 3. Placement Algorithm Spec (HIDER-03)

**v1 strategy (what actually shipped, 04-01-SUMMARY):** uniform random `[x,y,z]` within the bounding box; no min-distance constraint, no overlap avoidance, no surface-snapping; seed param for deterministic tests; "anywhere in the bounding region" read literally. v1 explicitly deferred near-atom placement to Phase 5+. **Port this as-is** — do not invent surface-projection or Poisson-disk for MVP.

### 3.1 Bounding box (headless-verified)

```tcl
# measure minmax returns EXACTLY this shape (probe16_place P2):
#   {{xmin ymin zmin} {xmax ymax zmax}}   -- 2 elements, each a 3-float list
set all [atomselect $molid "all"]
set mm [measure minmax $all]
$all delete
lassign $mm lo hi
lassign $lo xmin ymin zmin
lassign $hi xmax ymax zmax
# 1k8p: x [-8.88..17.649] y [2.63..40.396] z [19.202..48.236]
```

Full float precision (not rounded); works on any selection (subset candidates possible later, not MVP). Cost is C-level — safe on 100k+ atom demos.

### 3.2 Pure sampler (new `vmd/lib/generators.tcl`)

```tcl
# vmd/lib/generators.tcl -- PURE: stdlib rand() only. Port of v1 generators.py.
namespace eval ::biochemeleon::generators {
    namespace export sphere_positions
}
# sphere_positions {minmax n {seed {}}} -> list of {x y z} triples,
# uniform-random inside the box. seed -> deterministic (expr {srand($seed)},
# the setup_state::randomize_per_rep convention). rand() is the GLOBAL PRNG
# (Pitfall 4 in setup_state) -- do NOT reseed per call in production.
proc ::biochemeleon::generators::sphere_positions {minmax n {seed {}}} {
    if {$seed ne ""} { expr {srand($seed)} }
    lassign $minmax lo hi
    lassign $lo xmin ymin zmin
    lassign $hi xmax ymax zmax
    set pts [list]
    for {set i 0} {$i < $n} {incr i} {
        lappend pts [list \
            [expr {$xmin + rand() * ($xmax - $xmin)}] \
            [expr {$ymin + rand() * ($ymax - $ymin)}] \
            [expr {$zmin + rand() * ($zmax - $zmin)}]]
    }
    return $pts
}
```

tcltest suite (port of v1's 8 tests): count == n; every coordinate within [min,max]; seed determinism; different seeds differ; n=0 → empty; n=1; degenerate box (min==max → all points equal, no crash).

### 3.3 Swap point in mutation.tcl (signature + record shape frozen)

`make_placeholder_hiders {molid count}` keeps everything about its contract (returns `{name x y z}` records, names `G01..GNN` zero-padded, wrap in catch for bad molid). Only the coordinate math changes:

```tcl
proc ::biochemeleon::mutation::make_placeholder_hiders {molid count} {
    set all [atomselect $molid "all"]
    set mm [measure minmax $all]
    $all delete
    set pts [::biochemeleon::generators::sphere_positions $mm $count]
    set recs [list]
    set i 0
    foreach p $pts {
        incr i
        lassign $p x y z
        lappend recs [list [format "G%02d" $i] $x $y $z]
    }
    return $recs
}
```

Dependency direction stays legal: `mutation.tcl` (mol bridge) already sources pure `setup_state.tcl`; it sources pure `generators.tcl` the same way. Keep the existing `[catch {molinfo ...}]`-style defensiveness only if you keep any molinfo call — `measure minmax` on a bad molid raises naturally, which game.tcl already propagates (15-05 behavior: caller aborts the game).

### 3.4 Where spheres sit relative to the molecule

Uniform-in-bbox means some spheres land inside the atom cloud (hard to spot — good) and some in empty space (findable — the game needs SOME findability). v1 shipped exactly this and passed its SCs; the challenge for the sphere tier is the 3D volume search, not visual camouflage (04-RESEARCH.md §C Q13 rationale). Do NOT clamp/inset the box or avoid real atoms — v1 didn't, and overlapping a real atom is harmless (a sphere at a carbon position looks like a slightly fat carbon).

---

## 4. Rendering Spec (hider reps)

Two reps are added to the **game molid** AFTER `backup::apply` (which clears all reps and re-applies the user's). Base index = `numreps` after apply (deterministic per round since apply always ends with exactly the snapshot's reps). Probe-verified end-to-end (probe16_found F10-F13).

```tcl
# rH = hidden hiders, rF = found hiders; base = [molinfo $gm get numreps] after apply
mol addrep $gm
mol modstyle  $rH $gm VDW            ;# defaults res 8.0 scale 1.0 (read-back "VDW")
mol modcolor  $rH $gm Element        ;# elem C -> cyan (matches real carbons)
mol modselect $rH $gm "resname GAM and beta < 0 and user2 < 1"

mol addrep $gm
mol modstyle  $rF $gm VDW
mol modcolor  $rF $gm ColorID 7      ;# 7 = green (colorinfo colors index; v1 also used green)
mol modselect $rF $gm "resname GAM and beta < 0 and user2 > 0"
```

**Read-back verification (headless):** `molinfo $gm get "{rep $rH} {selection $rH} {color $rH} {material $rH}"` → probe F11: `style='VDW' sel='resname GAM and beta < 0 and user2 < 1' color='Element'`; F12: `color='ColorID 7'`. Note `{color $i}` returns the id too ("ColorID 7").

**Style parameters:** `VDW <resolution> <sphere_scale>` — exactly 2 params, that order (probe C3: "VDW 8.0 1.0" round-trips positionally; a 3rd param ERRORS: "Incorrect atom representation command 'VDW 8.0 1.0 0.3'"). Bare `VDW` = defaults. CPK (comparison tier) is `CPK <sphere_scale> <bond_radius> <resolution>` — DIFFERENT param order, 3 params (probe C4). MVP: bare `VDW`.

**Blending profile (all defaults, zero new params):**

| Property | Hider sphere | Real carbon | Match |
|----------|-------------|-------------|-------|
| radius | 1.70 (element C parsed from PDB cols 77-78) | 1.70 (probe F6 vs F7: C5' = 1.7000000476837158) | ✅ exact |
| color | Element → cyan (id 10) | Name → cyan (VMD default name table) | ✅ under default coloring |
| material | Opaque (rep default) | Opaque | ✅ |
| style | VDW sphere | user's rep (often Lines/VDW) | differs if user reps aren't VDW — v1-parity limitation, acceptable |

**Coloring caveat:** if the user's reps color by Structure/ResType/etc., cyan spheres won't match their surroundings. v1 had the same class of limitation (elem-PS gray spheres that "may be TOO easy to spot" — accepted for MVP). Setup state provides NO color/blending knobs (verified: `setup_state::DEFAULTS` = 11 keys — format/target_mode/selected_object/pdb_code/demo_id/hider_count/lock_scene/per_rep/difficulty_easy/lock_source/pdb_pool; setup_tab.tcl has no color widgets) → there is nothing to wire; ship fixed defaults.

**Sphere count/cap (RQ6):** `hider_count_cap` = `atoms/50` clamped to [1,50] → **max 50 VDW spheres ever**. No performance concern at that count (v1 had no cap lessons either; uniform sampling is O(n)). Per-rep distribution: setup's `per_rep` exists in the validated state, but Phase 16 is the sphere tier only → **total-only distribution, every hider rep field = "VDW"**. The GUI per-rep rows and `randomize_per_rep` stay untouched (they feed Phase 17+ multi-tier generators; honoring non-VDW per_rep counts is impossible until those tiers exist).

---

## 5. Found-Marking Spec (THE subtle one — resolved)

### 5.1 Why v1's mechanism cannot port

v1: `cmd.color('green', f"{obj} and id {aid}")` — PyMOL per-atom color override. **VMD has no per-atom color**; coloring methods apply per-REP (FEATURES.md:77 states this explicitly; confirmed by the command set — `mol modcolor` takes a rep number, and atomselect has no settable `color` field). The VMD-native equivalent of "recolor one atom" is the **flag + dedicated rep** technique (same pattern FEATURES.md prescribes for hints).

### 5.2 The mechanism (probe-verified end-to-end through `game::start_game`)

1. **Flag:** `$sel set user2 1` on the found atom's index (batched list form works: `$sel set user2 {0 0 0}` — probe F9). `user` is taken (tag_sentinels stores ordinals there); `user2` is a free per-atom channel, defaults 0.0 after every reload.
2. **Repaint:** re-issue `mol modselect` on BOTH hider reps with their unchanged selection strings (probe F17 OK). **This re-assert is REQUIRED, not insurance:** per UG node140, `mol selupdate` controls re-evaluation "each time the molecule's *timestep* changes" — a static single-frame molecule never re-evaluates a rep's cached selection when atom fields change. Re-issuing modselect re-parses the selection, forcing re-evaluation; it is idempotent and costs microseconds at ≤50 hiders.
3. **Registry:** `registry::mark_found $idx` (already exported; probe F18).
4. **Guard (caller-side, in game.tcl on_pick):** check `registry::status_of $idx` BEFORE marking — unregistered → miss (log, no-op); already `found` → "Already found!" (log, no-op); `hidden` → mark. **The guard must live in the caller because `mark_found` is a silent idempotent overwrite** (probe F19: re-marking the same idx leaves count at 3, no dup, no error). This is a 1:1 port of v1 game.py on_pick's three-way branch.

**Sentinel integrity:** the sentinel selector `resname GAM and beta < 0` is untouched — we never write beta (never use beta for found flags; beta<0 must keep matching ALL hiders for reconstruct/cleanup). `user2` is not written by `writepdb` (Pitfall 7 class) → found flags are session-only and reset naturally on the mutate reload each round; cross-session found-state is the Phase-20 `.bcm` sidecar's job.

### 5.3 The UG node140 caveat, resolved

> "showrep molecule_number rep_number [on | off]: Get/set whether the given rep is shown or hidden. **Hidden reps cannot be picked and do not show any graphics.**" (UG node140, verified verbatim against the version-matched local UG text + ks.uiuc.edu)

Meaning: pickability is a **per-REP** property — an atom is pickable iff it is visible in at least one shown rep. It is NOT per-atom (there is no per-atom hide). Consequences:

- `mol showrep $m $rF off` would make ALL found hiders unclickable at once — never do this in the find loop. (It IS the right tool for the Phase-19 "hide found hiders" dropdown, which intentionally toggles the whole found-rep.)
- Our design never hides either hider rep during play. Found hiders remain visible (green sphere) → **still pickable** → the caller guard above is what stops double-counts. v1 made the identical choice (found hiders stayed clickable; on_pick answered "Already found!") — port as-is.
- Remaining unfound hiders live in rH (shown) → pickable. Real atoms are visible in the user's reps → pickable → miss no-op (LOOP-01 "clicking a non-hider does nothing harmful").

### 5.4 Where the pick index comes from

`vmd_pick_atom` holds the picked atom's **`index`** — the UG's own callback example does `atomselect $vmd_pick_mol "same residue as index $vmd_pick_atom"`. That is the SAME 0-based index the registry keys on → the pick→registry lookup is a direct dict key hit, no serial/index conversion. (Whether the callback fires via `::vmd_pick_atom_callbacks`, a `trace variable`, or label-poll is the PickBridge GUI human-verify checkpoint — ROADMAP flags Phase 16 ⚠️ for exactly this; all three fallbacks per STACK.md read the same index.)

### 5.5 Module shape (dependency-direction-legal)

```
vmd/lib/generators.tcl   (PURE: sphere_positions; tcltest)
vmd/lib/hiders.tcl       (MOL BRIDGE, NEW: add_hider_reps {molid} -> nothing;
                          mark_found_visual {molid idx} -> set user2 + re-assert
                          both modselects; tracks rH/rF in namespace vars set by
                          add_hider_reps -- game_state shape stays FROZEN)
vmd/lib/game.tcl         (extend: on_pick {game_state idx}; start_game gains
                          ONE step between apply and registry-reconstruct:
                          hiders::add_hider_reps $game_molid)
```

`hiders.tcl` sources nothing (like backup.tcl); game.tcl stays the only composition root. Rep-index recovery without touching game_state: rH/rF are always the last two reps (`numreps-2`, `numreps-1`) — recompute defensively in mark_found_visual (or keep the namespace vars; either is fine at ≤50 hiders, planner's pick).

---

## 6. Found-State Model (LOOP-02, SC3, GAME-03)

**Single source of truth: the registry record's `status` field** — same as v1 (04-03: registry-as-single-source-of-truth). The game_state dict `{game_molid hider_count snapshot}` stays FROZEN (15-05 contract); it never carries found-state.

Record shape today: `dict create rep "" status hidden|found` keyed by atom index (registry.tcl:35). Phase 16 changes, all pure + tcltest-able:

```tcl
# registry.tcl additions (pure):
proc ::biochemeleon::registry::status_of {idx} {
    variable _records
    if {![dict exists $_records $idx]} { return "" }
    return [dict get [dict get $_records $idx] status]
}
proc ::biochemeleon::registry::count_remaining {} {
    variable _records
    set n 0
    dict for {k rec} $_records {
        if {[dict get $rec status] eq $::biochemeleon::registry::HIDER_STATUS_HIDDEN} { incr n }
    }
    return $n
}
proc ::biochemeleon::registry::remaining_by_rep {} {
    variable _records
    set out [dict create]
    dict for {k rec} $_records {
        if {[dict get $rec status] eq $::biochemeleon::registry::HIDER_STATUS_HIDDEN} {
            set r [dict get $rec rep]
            if {![dict exists $out $r]} { dict set out $r 0 }
            dict incr out $r      ;# dict incr probe-verified under tcl 8.5.6 (probe16_dictincr)
        }
    }
    return $out
}
# reconstruct_from_sentinels: optional rep arg, default "" (backward compatible
# with every existing smoke call):
proc ::biochemeleon::registry::reconstruct_from_sentinels {fetch_hider_ids {rep ""}} {
    ... dict set _records $idx [dict create rep $rep status $HIDER_STATUS_HIDDEN] ...
}
# game.tcl passes "VDW" (the sphere tier's GAME_REPS name) -> per-rep remaining
# is derivable forever; MVP displays it as {VDW N} which equals the total.
```

**Remaining-count flow (SC3):** `on_pick` → `mark_found` → `count_remaining` → GUI label callback (v1 `on_remaining_changed` pattern). Win: `count_remaining == 0` → stop timer → win message (GAME-03). Easy-mode per-rep remaining (SC3 mentions it): `remaining_by_rep` gives `{VDW N}`; with total-only sphere distribution per-rep == total, so the Game tab can show either from the same data — planner decides whether the per-rep label ships now or with Phase 17 multi-tier.

**tcltest coverage (pure layer, no VMD):** reconstruct with rep arg → records carry rep "VDW"; status_of on unregistered → ""; mark_found → status_of "found"; count_remaining decrements; remaining_by_rep grouping; double-mark idempotence; reset → 0.

**Timer/countdown (GAME-01/02, v1 parity):** countdown = `after 1000` callback chain (the tcl analog of v1's `QTimer.singleShot` chain — NEVER `vwait`, AGENTS.md Tcl gotcha); elapsed = `clock seconds` delta computed on each tick (v1's drift-free `time.time()` pattern).

**Start button (BTN-07):** setup_tab actions group gains Start. Target resolution mirrors v1 `_on_start`: mode=loaded → `current_molid`; mode=demo → `demos::load_demo`; mode=fetch → **`demos::fetch_pdb {code}` already exists** (demos.tcl:106). Then `game::start_game $molid $hider_count` (clamped via `validate_state $state $atom_count` first, the setup_tab do_save precedent) → switch to Game tab → countdown.

---

## 7. v1 Port Notes (what shipped, what changes)

| v1 (Phase 4 + 04.1 + 07) | Shipped behavior | v2 Phase 16 disposition |
|--------------------------|------------------|------------------------|
| `generators.py::generate_sphere_positions(extent, n, seed)` — uniform random in bbox, stdlib random, 8 unit tests (04-01) | proven | **Ports 1:1** → `generators.tcl::sphere_positions` (`rand()`/`srand`), same test list |
| PickWizard `do_pick` → `cmd.identify("pk1", mode=1)` → `controller.on_pick(aid)` (04-02) | stable-id chain | Mechanism differs (no wizard API): PickBridge + `vmd_pick_atom` = atom **index** directly (UG example); same contract `on_pick(idx)` |
| `GameController.on_pick`: registry lookup → miss/found/already-found → mark_found + recolor + callbacks + win check (04-03) | three-way guard | **Ports 1:1 logically**; the recolor call becomes `hiders::mark_found_visual` (user2 + modselect re-assert) |
| `cmd.show('spheres', ...)` + elem-PS gray pseudoatom spheres — NOT blended (04-RESEARCH Q15/Q18; "may be TOO easy to spot" accepted) | visible, unblended | v2 ships BETTER blending for free: element C → radius 1.7 == carbon, Element coloring == carbon color. Deliberate minimal delta, zero new params |
| Found = per-atom `cmd.color('green', ...)` (04-03) | per-atom recolor | **CANNOT port** (no per-atom color in VMD) → user2 flag + found-rep `ColorID 7` (green, same hue as v1) |
| `_remaining()` = count of hidden records | total only | `registry::count_remaining` (same definition); easy-mode per-rep via `remaining_by_rep` (v1 shipped that in 04.1 — here it's free data; display decision is the planner's) |
| Game tab: QTextEdit log + QLabel timer + QLabel remaining + 3-2-1 `QTimer.singleShot` countdown + modal win `QMessageBox` (04-04) | UI | → `vmd/gui/game_tab.tcl`: text widget log, labels, `after`-chain countdown, `tk_messageBox` win; Game tab is NEW (dialog.tcl currently has Setup only) |
| Start wiring in `__init__._on_start`: resolve target → get_extent → generate → start → switch tab → countdown (04-05) | wiring | → setup_tab BTN-07 + `game::start_game`; `demos::fetch_pdb` already exists for mode=fetch |
| Headless smoke simulated the pick by injecting pk1 (04-06) | pick sim | v2 headless CAN'T fire real picks (vmd_pick_atom absent in text mode, STACK.md:227) → smoke tests on_pick by CALLING `game::on_pick $gs $idx` directly with a known hider index; real picks = human-verify (ROADMAP ⚠️) |
| Found-hider management dropdown hide/show/recolor (Phase 7 v1) | later | Phase 19 here (ROADMAP) — `mol showrep` on the found-rep is the hide/show switch; NOT Phase 16 scope |

---

## 8. Common Pitfalls (all probe-verified unless noted)

### Pitfall 1: `mol mod*` argument order is (rep, molid, X) — showrep is (molid, rep)
**What goes wrong:** `mol modstyle VDW $m 1` → `ERROR) Unknown atom representation command '1'` (probe16_place P8-P12); `mol modcolor ColorID $m 1 7` → `Incorrect atom color method command '1 7'`. **Why:** UG node140 signatures are `modstyle rep_number molecule_number rep_style` / `modcolor rep_number molecule_number coloring_method`, but `showrep molecule_number rep_number` — the mol/rep order FLIPS between the two command families. **Avoid:** always `mol modstyle $rep $m ...`, `mol showrep $m $rep` (backup.tcl:79-82 and viewmaster.tcl are the canonical examples). **Warning sign:** "Unknown atom representation command '<number>'".

### Pitfall 2: single-field `molinfo $m get {rep $i}` FAILS
**What goes wrong:** `molinfo: cannot find molinfo attribute '1'` (probe16b — 10× failures; probe16_place P9+ silently lost their read-backs). **Why:** documented v2 pitfall (backup.tcl:35-36, "demos.tcl Pitfall 3") — the braces form `{rep 1}` list-parses into attributes "rep" and "1". **Avoid:** the COMBINED-braces form only: `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"`, then destructure with `foreach ... break`.

### Pitfall 3: rep selections do NOT re-evaluate on atom-field changes
**What goes wrong:** set user2 → rep keeps its cached selection → found sphere never turns green. **Why:** UG node140 `selupdate` re-evaluates "each time the molecule's *timestep* changes" — static molecules have none. **Avoid:** ALWAYS re-issue `mol modselect` (same string) on both hider reps after any user2 write (probe F17 OK). **Confidence:** mechanism MEDIUM-HIGH (UG-implied; auto-re-eval is unobservable headlessly — the human-verify checkpoint confirms the green flip), the re-assert itself HIGH (probe-verified, idempotent, ~free).

### Pitfall 4: `measure center` is flat; `molinfo get center` is nested
**What goes wrong:** `lassign [molinfo $m get center] x y z` binds x={x y z}, y/z empty (the nested form is `{{x y z}}`, len 1 — mutation.tcl:41-49 already documents this). `measure center` returns a FLAT 3-list (probe P4: len 3). **Avoid:** don't mix them; placement needs `measure minmax` anyway, not center.

### Pitfall 5: `mark_found` silently overwrites — the caller must guard
**What goes wrong:** clicking a found hider again re-marks it; with a naive count-then-win flow nothing breaks, but any "already found" UX or stat depends on the caller checking `status_of` first (v1's three-way on_pick). **Avoid:** status check BEFORE mark_found, always (probe F19).

### Pitfall 6: VDW style takes exactly 2 params; CPK takes 3 in a DIFFERENT order
**What goes wrong:** `VDW 8.0 1.0 0.3` → `ERROR) Incorrect atom representation command` (probe C3); assuming CPK's order for VDW (or vice versa) silently transposes resolution/scale. **Avoid:** `VDW <resolution> <sphere_scale>`; `CPK <sphere_scale> <bond_radius> <resolution>` (probe C3/C4 round-trips). MVP: bare `VDW`.

### Pitfall 7: user2 values are floats
**What goes wrong:** string-comparing `[lindex [$sel get user2] 0] eq "1"` fails (value is `1.0`). **Avoid:** numeric compare (`> 0`) in tcl too; in selection strings the numeric forms all parse (probe F8: `user2 > 0`, `user2 < 1`, `user2 == 0`, `not (user2 > 0)` — all OK).

### Pitfall 8: never use beta for found flags
**What goes wrong:** any beta write risks the sentinel selector `resname GAM and beta < 0` (reconstruct + cleanup both depend on it matching ALL hiders). **Avoid:** found flags live ONLY in user2; beta stays -999 forever.

### Pitfall 9: rep indices renumber on delrep — hider reps must be (re)added LAST, every round
**What goes wrong:** caching "rep 1 is the found-rep" across a `mol delrep` or a restart → wrong rep modified. **Why:** probe16c C10 — after `mol delrep 0`, old rep1 became rep0 (backup.tcl's delrep-0 loop exists because of this). **Avoid:** add hider reps after backup::apply in start_game (deterministic: base..base+1); restart goes through start_game → automatic re-add; verify by repinfo read-back, not by remembered index.

### Pitfall 10: `after`-based countdown, never `vwait`
Tcl gotcha (AGENTS.md): `vwait` on a var you set in the same proc = infinite loop; the countdown is an `after 1000` callback chain (v1 `QTimer.singleShot` analog). Also `expr` braced everywhere.

---

## 9. Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bounding box | manual min/max loops over `$sel get {x y z}` | `measure minmax` | C-level, exact format probe-verified, safe on 100k+ atoms (AGENTS perf rule: never build huge Tcl lists) |
| Sphere rendering | `graphics` command spheres / custom draw lists | VDW rep on the GAM selection | reps are pickable + rep-managed + restore-safe; `graphics` objects are not pickable and not part of backup/restore |
| Per-atom state channel | new sidecar files / parallel arrays keyed by index | `user2` atom field | VMD-native, batched set, selection-keyword-queryable (probe F8), survives within a session, auto-resets on reload (desired semantics) |
| "Recolor one atom" | hacks stacking 50 one-atom reps | flag + 2-rep split | rep explosion breaks repname tracking/restore; 2 reps total is the FEATURES.md-blessed technique |
| Random uniform points | home-rolled RNG in tcl | `rand()`/`srand()` + v1's formula | v1-proven distribution; global PRNG matches setup_state `_randint` convention (one PRNG stream per process) |
| Pure-test harness | ad-hoc assert scripts | `tcltest` (vmd/tests/*.test pattern) | established convention (test_registry.test, test_setup_state.test) |

---

## 10. State of the Art (v1 → v2 deltas that matter this phase)

| Old (v1 PyMOL) | Current (v2 VMD) | Impact |
|----------------|------------------|--------|
| per-atom recolor `cmd.color` | per-rep coloring methods only | found-marking = flag + rep split (§5) |
| `cmd.get_extent` | `measure minmax` (same shape, 2×3-vector list) | placement formula identical |
| pseudoatom elem-PS gray hider | PDB ATOM record elem C → radius 1.7, Element-colored | MVP blending is strictly better, zero params |
| Wizard `do_pick` + `pk1` | `vmd_pick_atom` (= index) via callbacks/trace/label-poll; pick & rotate mutually exclusive | pick contract human-verify (ROADMAP ⚠️ SC5 needs a Rotate/Pick toggle, `mouse mode pick 0` vs `r`) |
| QTimer countdown/timer | `after` chain + `clock seconds` delta | same UX, event-loop-safe |
| found hiders stay clickable, guard = registry status | identical (green sphere keeps pickability; UG node140 caveat avoided by never hiding reps) | 1:1 port |

**Deprecated/outdated (don't carry over):** v1's `cmd.index`-style identity (fragile) — v2 keys on `index` via sentinels (Phase 15); v1's per-rep PyMOL GUI state — v2 reps are command-managed; `mol showrep`-based found-hiding — rejected for the find loop (§5.3).

---

## 11. Open Questions

1. **Does VMD ever auto-re-evaluate rep selections on atom-field change?**
   - What we know: UG says selupdate is timestep-based; static molecules shouldn't re-eval. Headless cannot observe rep rendering.
   - Recommendation: treat `mol modselect` re-assert as MANDATORY (probe F17; cost ~nil). Human-verify confirms the green flip; if VMD DOES auto-update, the re-assert is a harmless no-op.
2. **Exact PickBridge callback contract in a real GUI session** (does `::vmd_pick_atom_callbacks` receive (molid index) args, or only globals populate?). ROADMAP flags Phase 16 ⚠️ for a GUI human-verify checkpoint; design defensively (trace + callback-list + `label list Atoms` poll per STACK.md).
3. **Visual blending quality in a real session** (cyan VDW spheres vs the user's actual reps/materials) — human-verify checkpoint; headless verified all the objective preconditions (radius 1.7, Element→cyan id, Opaque, shown, pickable).
4. **Per-rep remaining LABEL in Phase 16 vs Phase 17** — SC3 says "(total + per-rep in easy mode)"; with total-only sphere distribution per-rep == total. `remaining_by_rep` is delivered pure either way; planner decides display scope.

---

## 12. Sources

### Primary (HIGH confidence — probe-verified against the real VMD 1.9.3 install)
- `tmp/biochemeleon-vmd/probe16_place.tcl` output — measure minmax/center formats; colorinfo order (blue=0 … green=7 … cyan=10 …); wrong-order mod* errors; showrep read-back 1/0.
- `tmp/biochemeleon-vmd/probe16c.tcl` output — addrep; VDW `res scale` (2 params, 3rd errors); CPK `scale bondrad res`; ColorID id round-trip "ColorID 7"; Element/Name read-backs; modselect read-back; delrep renumbering.
- `tmp/biochemeleon-vmd/probe16_found.tcl` output — full pipeline: start_game on 1k8p (555→558 atoms, indices 555-557, elem C, radius 1.7 == real C5'); user2 keyword parses (4 forms); batched set; hider reps round-trip (F11/F12 read-backs); mark-found flow (F14-F17); registry mark/reset (F18-F20); cleanup with extra reps (F22/F23).
- `vmd/lib/{mutation,game,registry,backup,setup_state}.tcl`, `vmd/gui/setup_tab.tcl` (read in full — frozen contracts: start_game signature/DI/game_state shape; registry record shape; make_placeholder_hiders swap point; no Start button yet; no color params).
- VMD 1.9.3 User's Guide (version-matched local text `tmp/biochemeleon-vmd/ug_text.txt` + https://www.ks.uiuc.edu/Research/vmd/current/ug/node140.html, fetched 2026-08-30): mol command — showrep caveat verbatim; selupdate timestep semantics; mod*/showrep signatures; `measure minmax`/`center` definitions; pick-callback example (`vmd_pick_atom` = index).

### Secondary (MEDIUM-HIGH — project-verified prior research)
- `.planning/research/FEATURES.md` (:63 minmax verified; :77 "VMD colors by rep-method, not per-atom" + rep technique; :150 VDW hider row) — all re-probe-confirmed this session.
- `.planning/research/STACK.md` (:176 node140 caveat; :227 headless can/cannot list; :262 molinfo rep keywords).
- `.planning/phases/04-mvp-core-loop-sphere/04-RESEARCH.md` + `04-01/02/03/05/06-SUMMARY.md` — v1 sphere strategy, on_pick logic, human-verify scope.
- `.planning/phases/15-mutation-safety-hider-registry/15-05-SUMMARY.md` — frozen Phase-16 contracts + re-run recipe.

### Tertiary (LOW — flagged for human-verify)
- Rep auto-re-eval behavior on atom-field change (unobservable headless; re-assert mandated regardless).
- Real pick-event contract + visual blending (GUI-only).

---

## 13. Re-run recipe

```bash
mkdir -p tmp/biochemeleon-vmd && cp -r vmd tmp/biochemeleon-vmd/ && cp pymol/biochemeleon/data/demos/1k8p.pdb tmp/biochemeleon-vmd/
# probes live in tmp/biochemeleon-vmd/probe16*.tcl (gitignored)
timeout 300 bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e probe16_found.tcl -eofexit < /dev/null' 2>&1 | grep -E "^F[0-9]+|PROBE|ERROR"
```

## Metadata

**Confidence breakdown:**
- Placement: HIGH — probe-verified minmax format + UG definition + 1:1 v1 port of a shipped strategy
- Rendering: HIGH — every mol call + read-back probe-verified; blending preconditions (radius/color/material) probe-verified; final look = human-verify
- Found-marking: HIGH mechanism (probe-verified end-to-end through start_game; node140 caveat verbatim) / MEDIUM the auto-re-eval nuance (mitigated by mandatory re-assert)
- Found-state: HIGH — pure dict layer, tcltest-able, frozen game_state respected

**Research date:** 2026-08-30
**Valid until:** ~2026-09-29 (VMD 1.9.3 is frozen; Phase-15 contracts frozen by 15-05)
