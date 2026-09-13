# Phase 18: Materials Exploration — Codebase-Integration Research

**Researched:** 2026-09-14
**Domain:** VMD 1.9.3 Tcl codebase integration (v2 bioCHEMeleon; phases 13–17.2 built)
**Confidence:** HIGH (every codebase claim below cites file + proc + line, read from the physical repo at `/mnt/c/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon` on 2026-09-14)

**Scope note:** This file covers the INTEGRATION mapping only (game-flow hook points, state schema, GUI wiring, backup fidelity, testing stack, harness, plan decomposition). The VMD material API itself (materials inventory, `material add`/`material change`, Tachyon proof feasibility) is a PARALLEL researcher's deliverable — do not duplicate; integration-side dependencies on that work are flagged in Open Questions.

---

## 1. Hook-point map (file → proc → line → what changes)

### 1.1 `vmd/lib/game.tcl` — `start_game` exact sequence (read in full, 622 lines)

| # | Lines | Step (current) | Phase-18 change? |
|---|-------|----------------|------------------|
| 0 | 147 | Signature `start_game {molid hider_count {per_rep {}} {lock_scene 0}}` | **YES — extend to 5 args**: `{molid hider_count {per_rep {}} {lock_scene 0} {per_mat {}}}` (additive, all existing callers byte-compatible) |
| 0a | 149–191 | 16-13 ACTIVE-GAME GUARD (cleanup + liveness remap) | **NO — byte-frozen** (16-13/16-15/16-16 verified; touch nothing) |
| 1 | 194 | `backup::snapshot $molid` | NO |
| 2 | 199 | `rep_tiers::scene_reps_to_per_rep [dict get $snapshot reps]` (lock-scene detection) | NO |
| 3 | 204–212 | Unimplemented-tier warn loop against CALLER's per_rep keys (`tier_kind ""` → `vmdcon -warn`) | NO — this is the **Warning-class degrade pattern materials must mirror** |
| 4 | 215–216 | `resolve_per_rep` + `effective_total` (P9) | NO |
| 5 | 220 | `tiers_from_per_rep` → `{code style count}` triples | NO |
| 6 | 235–303 | Per-tier placement loop (free/bonded/residue; occ_hiders accumulation) | NO |
| 7 | 311 | ONE `mutation::mutate $molid $records $residue_records` | NO |
| 8 | 314 | `backup::apply $snapshot $game_molid` (scene reps re-applied WITH their material names — see §4) | NO |
| 9 | 323–328 | ONE 1-arg `reconstruct_from_sentinels` (P8, DI command-prefix) | NO |
| 10 | 345–368 | File-layout slicing walk → `tier_of` / `idx_to_rep` / `residue_slices` | NO |
| 11 | 371 | `hiders::stamp_tier_codes $game_molid $tier_of` (BEFORE add_hider_reps — cached-selection contract) | NO |
| 12 | 376–381 | Build `specs` ({code *style_args}) + `hiders::add_hider_reps $game_molid $specs` | **YES — THE SEAM**: after step 12 (hider reps exist at indices base..base+2N-1), apply per-tier materials |
| 13 | 383 | ONE `registry::assign_reps` (P8) | NO |
| 14 | 393–402 | Resid-block zip + `register_resid_block` (skipped for no-residue rounds) | NO |
| 15 | 407–409 | `game_state` = `{game_molid hider_count snapshot per_rep}` (4 keys) → stash in `current_state` → return | **YES — additive 5th key `per_mat`** (mirrors 17.1-06's additive 4th key) |
| — | 452–466 | `restart` (defensive `dict exists` pass-through of per_rep/lock_scene) | **YES — same defensive pattern for `per_mat`** |
| — | 56–146 | Header comment documents the ordering contract | YES — update the header (steps + the 4-key→5-key note at lines 38–43, 145–146) |

### 1.2 WHERE the per-rep `mol modmaterial` application belongs

**Hider reps only.** Scene reps need NO change: `backup::apply` (vmd/lib/backup.tcl:76–84) already re-applies every saved scene rep **with its material name** (`mol modmaterial $idx $molid $material`, backup.tcl:82) — a lock_scene round's scene keeps whatever material the user styled it with, faithfully. The blend dimension comes from hider reps carrying a DIFFERENT material than the scene.

**Seam mechanics (minimal-seam recommendation):**

1. `hiders.tcl::add_hider_reps {molid {tier_specs ...}}` (vmd/lib/hiders.tcl:121) gains an OPTIONAL 3rd arg `{{mat_specs {}}}` — a list of `{code materialName}` pairs, parallel to tier_specs. Inside the existing per-spec loop (lines 132–183), after the found rep's `modselect` (line 163), if a material is given for this code: `mol modmaterial $hidx $molid $mat` + `mol modmaterial $fidx $molid $mat` (BOTH hidden and found reps — the found transition must stay color-only via the existing ColorID 7 green, hiders.tcl:161), then a P-1 read-back validation (the loop at 171–177 ALREADY reads `rmat` into a variable and ignores it — extend the compare to `rmat ne $mat` → hard error).
2. All existing callers stay byte-identical: 2-arg/1-arg calls (`phase16_hiders_smoke`, game.tcl itself pre-18) pass no mat_specs → zero material application → Phase-16/17 behavior unchanged.
3. `game.tcl` step 12 builds `mat_specs` from the new 5th arg `per_mat` + the resolved `$tiers` (see §1.3), and stores a `tier_materials` dict in hiders (parallel to `tier_styles`, hiders.tcl:97–99) for introspection (pv_state dumps, tests).
4. Material RESOLUTION (curation validation, default-fill, active-tier restriction) lives INSIDE `start_game` — the 17.1-14 locked decision ("lock/randomize derivation lives INSIDE start_game so console + GUI + restart share one semantics", STATE.md line 151) applied to materials. The GUI passes a RAW per_mat; start_game is the single derivation choke point.

**Recommended `per_mat` resolution rule (inside start_game, one new helper in materials.tcl):**
- `per_mat == {}` (empty dict) → feature OFF for this round → NO modmaterial calls at all (byte-identical to 17.2 behavior; covers every existing caller).
- `per_mat != {}` → for each ACTIVE tier (in `$tiers`): material = `per_mat[style]` if present and a known `GAME_MATERIALS` name, else the `DEFAULT_MATERIAL` constant. Unknown names dropped with `vmdcon -warn` (Warning-class, mirroring game.tcl:208–212 / 288–291 — never an `ERROR)` line, never a hard abort).
- The "use material blending" toggle never reaches start_game as a separate flag: `on_start` (dialog.tcl) passes `per_mat {}` when the toggle is off (see §3.5). One argument, no flag drift.

**Data the application step needs (all already in scope at line 376):** `$tiers` ({code style count}, from line 220), the 5th arg `per_mat`, and the curated list `::biochemeleon::setup_state::GAME_MATERIALS` (new, §2.1). Molid is `$game_molid`.

### 1.3 `vmd/lib/rep_tiers.tcl` — NO changes

`IMPLEMENTED_TIERS` (line 60), `TIER_KINDS` (66–76), `style_args` (106–113), `scene_reps_to_per_rep` (121–137), `filter_per_rep_to_scene` (142–152), `resolve_per_rep` (166–221), `tiers_from_per_rep` (228–240), `effective_total` (245–254) are all tier-only. Materials ride ALONGSIDE tiers, not inside them. Lock-scene detection reads styles only (line 126) — a material-blended scene derives its tiers exactly as today. **Do not widen this seam.**

### 1.4 Callers of `start_game` (the 4→5-arg surface)

| Caller | File:lines | Change |
|--------|-----------|--------|
| `on_start` (GUI) | vmd/gui/dialog.tcl:209–212 | Thread 5th arg `[dict get $state per_mat]` gated by the toggle (§3.5) |
| `restart` | vmd/lib/game.tcl:452–466 | Defensive `dict exists` pass-through (lines 454–463 precedent) |
| Console/smokes | all capstone/tier/e2e smokes | ZERO changes — 5th arg defaults to `{}` (the verified additive-defaults pattern: every legacy smoke stayed green through 17.1-06's 2→4-arg widening, 17.1-07) |

### 1.5 Why NOT the alternatives

- **Nested per_rep values** `{VDW {count material}}` — REJECTED: breaks `validate_state`'s integer clamp (`cnt <= $remaining`, setup_state.tcl:183–188), `effective_total` (`string is integer`, rep_tiers.tcl:249), `tiers_from_per_rep` (235), `randomize_per_rep` (215), `resolve_per_rep` (174), every legacy smoke's per_rep literal, `per_rep_entry`'s 2-token parse (demos.tcl:163–165), and every rep_verify crafted state. Mass-blast, zero benefit.
- **Materials inside the registry** (17.2-09's "keep game_state 4-key" precedent) — REJECTED here: the registry is the SCORING model; material is VISUAL state owned by hiders (the "visual half" module, hiders.tcl:1–2). A 5th additive game_state key mirrors 17.1-06 exactly and costs one known smoke update (§5.4).
- **`mol modmaterial` called from game.tcl directly** — REJECTED: game.tcl delegates ALL rep manipulation to the mol bridges (header lines 18–21); rep-visual logic belongs in hiders.tcl.

---

## 2. State schema recommendation

### 2.1 Exact DEFAULTS additions (vmd/lib/setup_state.tcl)

Add to `DEFAULTS` (lines 18–29), **appended at the END** (DEFAULTS key order defines validate/load output order — order-stable `eq` discipline, setup_state.tcl:121–125; appending minimizes diff + keeps existing orders):

```tcl
# (inside variable DEFAULTS [dict create ... ] — append after pdb_pool)
        material_blending 0 \
        per_mat          [dict create] ]
```

Add ONE new pure constant next to `GAME_REPS` (line 10):

```tcl
    # Curated material set for Phase 18 blending (stock VMD 1.9.3 names,
    # verified space-free against vmd-ref/scripts/materials.dat). GameBlend
    # is appended only after `material add GameBlend` lands (parallel
    # researcher / plan decision).
    variable GAME_MATERIALS {Translucent Ghost Glass1 Glass2 Glass3 EdgyGlass BlownGlass}
    variable DEFAULT_MATERIAL "Translucent"
```

(Exact membership = planner's discretion within MATERIAL-02's "Glass1/Glass2/Glass3/Translucent + custom GameBlend" (REQUIREMENTS.md:68); the recommended minimal set above keeps every name **space-free** — verified: ALL 21 stock names in `vmd-ref/scripts/materials.dat` are single tokens (`BrushedMetal`, not "Brushed Metal") — which keeps the `.bcm` line format 2-token-safe (§2.4). `Opaque`/`Transparent` are VMD-coded-in reference materials (materials.dat header) and stay OUT of the curated set; `Opaque` is the effective "no blending" default already.)

### 2.2 `validate_state` changes (setup_state.tcl:126–197)

After the per_rep block (line 189), before the lock_source block (line 191):

```tcl
    # material_blending (bool coercion — same _to_bool as lock_scene, line 168)
    if {[dict exists $state material_blending]} {
        dict set result material_blending [_to_bool [dict get $state material_blending]]
    }
    # per_mat: drop non-GAME_REPS keys, drop values not in GAME_MATERIALS,
    # GAME_REPS-order rebuild (order-stable eq; mirrors the per_rep block 172–189).
    set mat_clean [dict create]
    if {[dict exists $state per_mat] && ![catch {dict size [dict get $state per_mat]}]} {
        dict for {rep mat} [dict get $state per_mat] {
            if {[lsearch -exact $GAME_REPS $rep] < 0} { continue }
            if {[lsearch -exact $GAME_MATERIALS $mat] < 0} { continue }
            dict set mat_clean $rep $mat
        }
    }
    dict set result per_mat $mat_clean
```

Key backward-compat property: `validate_state` STARTS from a fresh `$DEFAULTS` copy (line 131) and only overwrites keys present in the input — an old dict / old `.bcm` WITHOUT `material_blending`/`per_mat` silently gets `0` / `{}`. **No version bump, no migration.**

### 2.3 `randomize_state` (setup_state.tcl:234–293)

The return `dict create` (lines 281–292) MUST gain the two new keys (a missing key would change every apply_state/eq round-trip): `material_blending 0` and `per_mat [dict create]`. **Recommendation: do NOT randomize blending** — Randomize stays non-surprising; the new keys exist purely so the returned dict stays validate-shaped. (If the planner prefers carrying the locked state's blend setting, read it from `locked_state` under `lock_source` like target fields at lines 252–259 — acceptable alternative, more code.) `randomize_per_rep` (204–225): untouched.

### 2.4 Save/load (vmd/lib/demos.tcl)

- `save_setup` (116–133): `material_blending` is a scalar → the `else { puts $fh "$k $v" }` branch (line 129) handles it with ZERO changes. `per_mat` needs its own line family mirroring per_rep (122–124): `per_mat_count [dict size $v]` + `per_mat_entry $rep $mat`. All curated names are space-free (§2.1), so `per_rep_entry`'s 2-token parse shape is safe; still, parse DEFENSIVELY: `set rep [lindex $rv 0]; set mat [join [lrange $rv 1 end] " "]` (hardens against any future spaced name).
- `load_setup` (142–181): add `per_mat_count` (no-op) + `per_mat_entry` cases to the `switch` (158–169); init `set per_mat [dict create]` (near line 148); `dict set tmp per_mat $per_mat` (near line 172); **extend the DEFAULTS-order rebuild list at line 176** `{format target_mode selected_object pdb_code demo_id hider_count lock_scene per_rep difficulty_easy lock_source pdb_pool}` → append `material_blending per_mat` IN THE SAME ORDER as the new DEFAULTS. `validate_state` at line 180 then canonicalizes. **BACKWARD COMPAT: an existing .bcm without the new lines loads unchanged** (dict-exists guard in the rebuild loop, line 177, + validate_state's DEFAULTS fill — §2.2).

### 2.5 What must NOT change

- quick-008 semantics (random NON-EMPTY subset, sum ≤ hider_count — setup_state.tcl:207, pinned 14-01/17.1-06): untouched; materials don't participate in counts.
- The 17.1-01 drop-overflow clamp semantics + GAME_REPS-order rebuilds: untouched.
- `hider_count_cap`, `format_remaining`, DEMO_MANIFEST: untouched.
- `rep_tiers.tcl`: untouched (§1.3).

### 2.6 game_state stash shape

4 keys → **5 keys** `{game_molid hider_count snapshot per_rep per_mat}` (game.tcl:407). `restart` gains the defensive read (mirror lines 454–463). Known regression: `phase16_onpick_smoke.tcl` asserts the 4-key gs shape (updated 3→4 keys in 17.1-07 — the identical update class, STATE.md line 51); it needs 4→5. Everything else reads per-key (`dict exists`/`dict get`) and needs nothing.

---

## 3. GUI wiring plan (vmd/gui/setup_tab.tcl + vmd/gui/dialog.tcl)

### 3.1 Widget choices for Tk 8.5.6

- **Per-rep material picker: `menubutton` + `menu`** (the PROVEN in-repo idiom: setup_tab.tcl:137–144 loaded-mol picker, 154–162 demo picker — "the clonerep idiom"). One menubutton per rep row, `-textvariable ::biochemeleon::setup_tab::rep_mat($rep)`, menu built from `GAME_MATERIALS` + a `(default)` entry (empty value = follow DEFAULT_MATERIAL).
- **ttk::combobox: DO NOT plan on it.** Zero occurrences of `combobox` anywhere in `vmd-ref/` (grep-verified 2026-09-14) — no shipped evidence it exists in this Tk 8.5.6 build; Tk loads only in GUI mode (vmd/AGENTS.md) so it CANNOT be probed headlessly. If the planner wants it, it requires a human GUI paste probe (`info commands ttk::combobox`) — the menubutton idiom needs no probe and matches the file's existing style. (Training-data hypothesis: ttk::combobox exists in stock Tk 8.5 — UNVERIFIED here, hence not load-bearing.)
- The **toggle**: `ttk::checkbutton -text "Use material blending"` — same widget class as the existing lock-scene checkbutton (setup_tab.tcl:183–184).

### 3.2 Group placement + new namespace vars

Host in the **Hiders group** (`build_hiders_group`, setup_tab.tcl:174–209) — material blending is a hider property; the group already owns per-rep rows. Concretely:
- Top row (line 178–188): add the `mat_blend` checkbutton after `$top.lock`.
- Per-rep grid (191–207): add a 4th column — the material `menubutton $pr.m$row` (existing columns: checkbutton col 0, spinbox col 1, "random" label col 2).
- New namespace vars (block at 27–46): `variable mat_blend 0` and `variable rep_mat` (array, declared bare like `rep_sel`/`rep_cnt` at lines 39–40 — the probe-verified undefined-`variable`-then-array pattern).

### 3.3 Enable/disable coupling (the grey-out rules)

Picker enabled ⇔ `mat_blend == 1` **AND** `rep_sel($rep) == 1`. Implementation:
- New proc `on_mat_changed {}` (or fold into the existing `on_rep_toggled {rep}`, setup_tab.tcl:443–482): reconfigure each row's menubutton `-state normal|disabled` from the two conditions.
- Follow the established `_loading` discipline EXACTLY: widget enable/disable runs OUTSIDE the guard (the on_rep_toggled precedent: "runs OUTSIDE `_loading` so apply_state's per-rep pass enables checked-rep spinboxes", lines 333–339 + 432–442 comment), while any value-clamping stays guarded (459).
- `apply_state` must drive the pickers: after the per_rep pass (lines 322–339), a per_mat pass (populate `rep_mat($rep)` from the dict; missing → "" = default), then the coupling pass.

### 3.4 Known traps (all repo-verified lessons)

| Trap | Rule | Source |
|------|------|--------|
| `variable a b` = name-VALUE pair, not two links | ONE `variable` per line for the new vars | setup_tab.tcl:252–255, 299–310; STATE.md 14-04 decision |
| `dict get` has NO 3-arg default form | Use `_dget` (setup_tab.tcl:56–59) for the new keys | 14-03 decision |
| Unqualified `tk_version` checks LOCAL scope | `::tk_version` everywhere | biochemeleon.tcl:141–146; 13-02 decision |
| ttk spinbox ABSENT in 8.5.6 | Keep plain `spinbox` (no new spinboxes needed anyway) | setup_tab.tcl:20–21 |
| `grab set` gate greps vmd/gui/ | No grab, ever, on the main panel | vmd/AGENTS.md modeless gate |
| 8.6-idiom gate greps lib/+gui/ (incl. comments) | Reword comments to avoid the literal gated terms | 14-03 decision (STATE.md line 113) |
| Checkbutton `-variable ...array($k)` auto-creates the array | Declare arrays bare (`variable rep_mat`), never `variable rep_mat rep_blend` | 14-04 rep_sel trap (STATE.md line 115) |
| Menubutton `-textvariable` + FQ paths | Bind fully-qualified `::biochemeleon::setup_tab::rep_mat($rep)` | existing rows, lines 194–200 |

### 3.5 collect/apply/on_start threading

- `collect_state` (setup_tab.tcl:251–285): add `material_blending [expr {!!$mat_blend}]` and `per_mat` built from `rep_mat` (only checked reps with non-empty material values, GAME_REPS order — mirror the per_rep build at 266–272).
- `on_start` (dialog.tcl:143–226): step 4 becomes 5-arg (209–212):
  ```tcl
  set pm {}
  if {[dict get $state material_blending]} { set pm [dict get $state per_mat] }
  ... start_game $molid [dict get $state hider_count] [dict get $state per_rep] [dict get $state lock_scene] $pm
  ```
  (Toggle gating at the GUI boundary; start_game's empty-`per_mat`-means-off rule, §1.2, keeps console/smoke callers byte-identical.)
- `do_save`'s diff reporter (setup_tab.tcl:641–657): optionally add `material_blending` to the scalar-diff key list + a per_mat line — small, keeps the save-warning honest.

---

## 4. Backup/restore analysis (vmd/lib/backup.tcl)

### 4.1 What ALREADY round-trips (quoted, verified)

Snapshot (backup.tcl:43–48):

```tcl
    set n [molinfo $molid get numreps]
    for {set i 0} {$i < $n} {incr i} {
        foreach {style sel color material} \
            [molinfo $molid get "{rep $i} {selection $i} {color $i} {material $i}"] { break }
        lappend reps [list $style $sel $color $material]
    }
```

Apply (backup.tcl:76–84):

```tcl
    foreach rep [dict get $snapshot reps] {
        foreach {style sel color material} $rep { break }
        mol addrep $molid
        mol modstyle   $idx $molid $style
        mol modselect  $idx $molid $sel
        mol modcolor   $idx $molid $color
        mol modmaterial $idx $molid $material
```

Header note (backup.tcl:36–38): `{material $i}` returns NAMES ("Name","Opaque"), passed straight to `modmaterial`. **Per-rep material NAMES are already snapshot/apply/restore-faithful** — and `phase15_backup_smoke.tcl:82–94` asserts the saved `{rep sel color material}` 4-tuple read-back (its form-A fixtures at lines 75–76 set `mol material Opaque` / `Transparent`). Hider reps need NO snapshot at all: they are added AFTER `backup::apply` (game.tcl ordering step 9/12) and die with the game molid on cleanup (restore re-applies only the SNAPSHOT's scene reps).

### 4.2 The gap — material SETTINGS, not names

`snapshot` captures the material NAME per rep. It does NOT capture material DEFINITIONS. `material change <name> <param> <val>` (e.g. tuning GameBlend's opacity mid-round) mutates the named material definition **session-globally** — cleanup's restore re-applies the material NAME, not the pre-round definition, so a tuned GameBlend would leak into every rep using that name (including the user's own scene) after cleanup. This is the exact snapshot-fidelity class that 16-15 guarded (`rep-0 style STILL Licorice` asserts — 17.1-10 smoke line 610; STATE.md lines 64, 145).

### 4.3 Recommendation: FORBID mid-round mutation — fixed recipe per round

**Phase 18 design rule: the curated materials are used AS-IS (stock definitions); no `material change` anywhere in the game flow.** If GameBlend ships, it is created ONCE per VMD session (`material add GameBlend` — parallel researcher owns the recipe) and never mutated afterward. Consequences:
- `backup.tcl` stays **byte-untouched** (zero snapshot extension needed).
- No materials-settings snapshot/restore machinery (that would be a new backup sub-proc + restore wiring — real cost, zero Phase-18 requirement).
- The materials smoke adds a cheap fidelity assert: after cleanup, the restored scene rep's material read-back equals the pre-round name (mirrors the 17.1-10 `restored_style` assert, licorice smoke:582–610).
- If tunable GameBlend is ever wanted, THAT phase owns a materials-settings snapshot — registered here as explicitly out of scope.

---

## 5. Testing stack map

### 5.1 Current inventory (17.2-11 gate numbers, STATE.md line 154)

| Layer | Artifacts | Current state |
|-------|-----------|---------------|
| tcltest suites (headless VMD, `BCHM_TEST_RESULT` marker — 13-01 decision) | `vmd/tests/test_{setup_state,registry,generators,rep_tiers,game_logic,splice}.test` | **205/205** (47/37/26/49/15/31) |
| Headless smokes (`BCHM_SMOKE_RESULT PASS=1`; grep `ERROR)` AND `bad switch` = 0; `Exiting normally`) | 31 files in `vmd/smoke/` (15 legacy + 16 phase-17) | 29/31 green; 2 pre-existing draw-dependent reds with recorded recipes (17.2-11) |
| Static gates | 8.6-idiom grep (vmd/AGENTS.md Commands block); grab-set grep; mol-ssrecalc grep | 0 required |
| GUI checkpoints | `vmd/tests/rep_verify.tcl` auto-driver | 17.2-12 PENDING (live user session NOW) |

Runner rules that gate Phase 18 too: suites need the staging-only `suite_driver.tcl` wrapper for full-suite runs (suites lack explicit exit; VMD console hangs past stdin EOF — 17.2-11); **all VMD runs sequential** (mutation.tcl:610–611 writes the shared `$env(TEMP)/biochemeleon_game.pdb`); parse the marker NEVER `$?`; full-log scan, never marker-trust (14-02 LESSON); `regexp -- ` for dash-leading patterns (15-orchestrator false-PASS lesson).

### 5.2 Render-proof machinery Phase 18 inherits (from 17.1-08/10/12 smokes)

- `_parse_dat` line-based Tachyon parser (phase17_licorice_smoke.tcl:124–148) with the missing-file-parses-as-−1 harness guard; Directional_Light filter (139); per-primitive `Rad`/`Color` regexes.
- The **both-endpoints rule** (hiders-only rep = 0 FCylinder for bond tiers; scene-diff `A(all) vs B(not resname GAM)` = +n spheres/stubs — licorice:439–526; dynbonds variant).
- **NEW integration fact:** the per-primitive Tachyon line is `Phong Plastic ... Color R G B TexFunc 0` (17.1-08 pin, STATE.md line 142) — i.e. the .dat embeds the MATERIAL's render-property line per primitive. A material-blend proof therefore likely parses material-property tokens (e.g. opacity/specular values differing between a Glass1 hider rep and an Opaque scene rep) in the SAME `_parse_dat` style. Whether the material NAME or only its resolved properties appear must be pinned by the first-render inspection (the 17.1-08 "plan-prescribed first-render inspection" precedent) — see Open Questions #4.

### 5.3 New artifacts Phase 18 needs

| Artifact | Type | Contents |
|----------|------|----------|
| `vmd/lib/materials.tcl` | mol bridge, sources NOTHING (verified convention: backup.tcl:9 "STANDALONE — sources NOTHING"; hiders.tcl:63–64 "sources NOTHING (standalone, like backup.tcl)") | Curated metadata + pure helpers (`resolve_per_mat`: validate names vs `GAME_MATERIALS`, fill DEFAULT_MATERIAL for active tiers, GAME_REPS-order) + the mol application entry (`apply_tier_materials` or folded into hiders mat_specs — planner's choice, §1.2 recommends hiders-side application) |
| `vmd/tests/test_materials.test` | tcltest suite (marker pattern; source-by-`[pwd]` like test_rep_tiers.tcl:29) | Pure-resolution cases (unknown-name drop, default fill, order stability, empty=off) |
| `vmd/smoke/phase18_materials_smoke.tcl` | headless smoke | The composition seam end-to-end: `start_game` with 5th arg → modmaterial read-back per tier pair (combined-braces `molinfo get "{material $i}"`) → one find → cleanup fidelity (restored scene material name intact, §4.3). TWO rounds covering the two tier classes: simple/bonded (VDW or Licorice on 1znf) + residue (Cartoon on 1znf — the CA-only pair, chain-classifier rules per 17.2-10). Optional Tachyon material-token sub-render (§5.2). |
| Updated `vmd/tests/test_setup_state.test` | regression | New DEFAULTS keys present; validate per_mat cleaning (bad rep key, bad material name, order-stability `eq`); randomize_state returns the new keys; missing-keys backward-compat case |
| Updated `vmd/smoke/phase14_mol_smoke.tcl` | regression | Check 7 save/load round-trip (lines 119–137) gains the new keys (eq=1 must survive) |
| Updated `vmd/smoke/phase16_onpick_smoke.tcl` | regression | gs shape 4→5 keys (17.1-07-precedented update class) |
| Updated `vmd/smoke/phase17_capstone_smoke.tcl` | capstone | One blending round (explicit per_mat) + the blending-off regression round; lock-scene + blending interplay (derived tier gets DEFAULT_MATERIAL) |

### 5.4 Gate checklist for every Phase-18 code plan (verbatim from the 17.x capstones)

1. `tclsh`-less env → suites run under headless VMD; `BCHM_TEST_RESULT` parsed from log.
2. Every smoke: PASS=1 × 3 runs (independent PRNG draws), 0 `ERROR)` AND 0 `bad switch` in the FULL log, `Exiting normally`.
3. 8.6-idiom grep zero; grab-set grep zero; (if splice-adjacent) mol-ssrecalc grep zero.
4. Sequential VMD runs only.
5. Capstone/full-suite gate at the end: all 6 suites + all smokes (17.1-13/17.2-11 pattern; expect the 2 known pre-existing reds with their recorded recipes — do NOT re-diagnose).

---

## 6. GUI checkpoint harness notes (vmd/tests/rep_verify.tcl extension)

Current driver shape (read in full, 637 lines): Tk-guard if-wrap (62–64) → `pv_log` open-append+flush (71–81) → `pv_observe` pick trace with `{args}` signature + find-counting (92–119) → `pv_observe_fallback` resid/name verdicts (129–155) → `pv_game_mol` (162–173) → `pv_state` mega-dump incl. per-tier rep read-backs (183–294) → `pv_round2` lock-scene mirror (303–361) → `pv_round3` cartoon round (375–423) → `pv_cleanup`/`pv_cleanup_check` (432–488) → `pv_report` (495–507) → `pv_instructions` (513–528, LEADS with the p-press quirk) → `pv_autostart` (535–602, sources extension → loads 1k8p → open_dialog → crafted 6-tier state via validate_state → apply_state → on_start → `after 4500 pv_state`).

**pv_round4 extension shape (copy pv_round3's skeleton 1:1):**
1. Fresh 1znf target (`demos::load_demo` — never reuse a mutated molid; pv_round3:379–383 pattern).
2. Crafted state dict WITH the new keys: `material_blending`-driven `per_mat` (e.g. `dict create VDW Glass1 Licorice Translucent Cartoon Glass3`) → `validate_state` → `apply_state` → `on_start` (the same real-GUI-path chain, pv_round3:390–413). NOTE: the driver builds states via `validate_state`+`apply_state`, NOT the form widgets — so the round exercises the state/plumbing path; the WIDGET behavior (toggle + pickers) needs 2–3 manual form interactions OR is accepted as covered by the collect/apply round-trip. Recommend: one manual sub-step "flip the toggle on the form, confirm pickers grey/ungrey" (10 seconds, no paste).
3. `catch {unset ::pv_gs}` BEFORE start (the 17.2-12 stale-stash fix, pv_round3:404–408) → `on_start` → `set ::pv_rounds 4` → `after 4500 pv_state`.
4. `pv_state` gain: the tier dump already reads `mat` (rep_verify.tcl:264 `foreach {sty selx col mat} [molinfo ... {material $r}]`) but never logs it — add `material=$mat` to the hidden line (265) and found line (272). This makes the material read-back AUTO-LOGGED evidence.
5. Session stays ≤3 short pastes (`pv_round4`, `pv_report`, `pv_cleanup`) + the standing rules: instructions lead with the first-click p-press (pv_instructions:515–517 pattern); auto-issue everything else.

**Human-verify question list for the materials round (transparency/lighting artifacts):**
- Are material-blended hiders visually DISTINCT from the opaque scene (the blend dimension working at all)?
- Do Glass/Translucent hiders render with correct transparency (no z-order artifacts against the scene's own geometry)?
- Any lighting/shininess artifacts that make hiders EASIER or harder than intended (the pedagogical hypothesis, MATERIAL-02)?
- Does the found-green transition (ColorID 7) stay visible THROUGH the material?
- Does the blended round still play (finds register) with no new first-click/pick regressions?

**Execution timing constraint:** Phase 18 must NOT edit `rep_verify.tcl` (or anything else) until the 17.2-12 GUI checkpoint closes — the user's live session reads the current file (STATE.md line 14; this research itself respected that — read-only).

---

## 7. Proposed plan decomposition (deliverable for the planner)

Ground rules honored: disjoint `files_modified` within a wave; `parallelization: true` in `.planning/config.json` → worktree protocol for multi-plan waves (root AGENTS.md); `commit_docs: true`; 1–2 tasks per plan; the user accepts 20–50+ plans but the natural seams here produce 13 — merging adjacent same-file plans is acceptable if the planner prefers fewer.

| Plan | Title | files_modified (created ⊕ modified) | Needs | Creates | Wave | Checkpoint? |
|------|-------|--------------------------------------|-------|---------|------|-------------|
| 18-01 | State schema: GAME_MATERIALS + DEFAULTS keys + validate/randomize + suite cases | ⊕ vmd/lib/setup_state.tcl, vmd/tests/test_setup_state.test | Phase 17.2 | material_blending/per_mat keys, GAME_MATERIALS, DEFAULT_MATERIAL; validate per_mat cleaning; randomize returns new keys; suite green | **1** | no |
| 18-02 | materials.tcl lib: curation + resolve_per_mat (pure) + tcltest suite | ⊕ vmd/lib/materials.tcl, vmd/tests/test_materials.test | 18-01 | sources-nothing mol bridge (resolution helpers only this plan); pure cases green | **2** | no |
| 18-03 | hiders.tcl: mat_specs application + tier_materials + read-back | ⊕ vmd/lib/hiders.tcl | — (self-contained) | optional 3rd arg, byte-compatible; P-1 material read-back | **1** | no |
| 18-04 | demos save/load per_mat + backward-compat round-trip | ⊕ vmd/lib/demos.tcl, vmd/smoke/phase14_mol_smoke.tcl | 18-01 | per_mat_entry lines; load rebuild; old-.bcm compat proven | **2** | no |
| 18-05 | setup_tab: blending toggle + per-rep pickers + coupling | ⊕ vmd/gui/setup_tab.tcl | 18-01 | widgets + vars + on_mat_changed; _loading discipline | **2** | no (headless load-gate only) |
| 18-06 | game.tcl 5-arg seam + per_mat resolution + game_state 5th key + restart | ⊕ vmd/lib/game.tcl, vmd/smoke/phase16_onpick_smoke.tcl | 18-02, 18-03 | the §1.2 seam; gs 5 keys; warning-class degrade | **3** | no |
| 18-07 | setup_tab collect/apply + do_save/do_load wiring | ⊕ vmd/gui/setup_tab.tcl | 18-05 | collect/apply emit+read new keys; _dget defaults; save-diff list | **3** | no (headless load-gate only) |
| 18-08 | Entry source line + phase18 materials smoke (both tier classes) | ⊕ vmd/biochemeleon.tcl, vmd/smoke/phase18_materials_smoke.tcl | 18-06 | end-to-end seam proof incl. cleanup material-fidelity + optional Tachyon token probe | **4** | no |
| 18-09 | dialog.tcl on_start 5-arg threading + blend gating | ⊕ vmd/gui/dialog.tcl | 18-06, 18-07 | GUI→engine threading; toggle-off → per_mat {} | **4** | no (headless load-gate only) |
| 18-10 | Capstone extension: blending + lock-scene-blending rounds | ⊕ vmd/smoke/phase17_capstone_smoke.tcl | 18-06 | composition-root regression incl. blending-off round | **5** | no |
| 18-11 | FULL-SUITE green gate (17.1-13/17.2-11 pattern) | (gate run; docs only) | 18-01..10 | all suites + all smokes sequential, markers + false-PASS scans + static gates | **6** | no |
| 18-12 | rep_verify driver: pv_round4 + pv_state material logging | ⊕ vmd/tests/rep_verify.tcl | 18-09; **execution only after 17.2-12 closes** | driver round; headless definition-gate (pv_probe knob) | **6** | no |
| 18-13 | GUI human-verify checkpoint: materials round + form interactions | (session; docs) | 18-12 (and 17.2-12 closed) | verdicts on the §6 question list | **7** | **YES — autonomous:false, LAST** |

Wave-1 parallelizable: **18-01 ∥ 18-03** (disjoint). Wave-2: 18-02 ∥ 18-04 ∥ 18-05 (disjoint; 18-05 is GUI-build — headless-verified via the 14-03 loading-layer pattern only). Wave-3: 18-06 ∥ 18-07 (disjoint). Wave-4: 18-08 ∥ 18-09 (disjoint). Waves 5–7 sequential by nature.

**Execution cautions for the orchestrator:**
- Any two parallel plans that each RUN headless VMD smokes must serialize their smoke-execution steps (shared `$env(TEMP)/biochemeleon_game.pdb`, mutation.tcl:610–611 — the recorded forbids-parallel rule; 17.x parallel waves carried this risk, the rule stands).
- 18-12/18-13 are HARD-GATED on the 17.2-12 checkpoint closing (live user session).

---

## 8. Carried-forward constraints (from .planning/STATE.md decisions, verified 2026-09-14)

1. **17.2-12 checkpoint PENDING** — user is running it NOW; do not touch `tmp/biochemeleon-vmd/`, `vmd/` code, or `vmd/tests/rep_verify.tcl` until it closes (STATE.md lines 12–15).
2. **Warning-class degrade** (the 'Ribbons has no generator yet' pattern, game.tcl:208–212 + capstone round C): any Phase-18 material problem (unknown name, dead molid, modmaterial no-op) must degrade via `vmdcon -warn` + drop — **never an `ERROR)` line, never a hard abort** (17.2-09 supply-0 catch-warn precedent, game.tcl:262–265).
3. **lock-scene quick-008 subset semantics ACCEPTED** (sum ≤ hider_count, never ==; 17.1-14 finding 3) — materials must not touch count semantics.
4. **Phase-19 items, NOT 18**: difficulty calibration (non-sphere tiers too invisible); restored-original-intercepts-picks fix (17.1-14 findings 1–2).
5. **First-click p-press quirk**: every GUI checkpoint instruction list LEADS with "press p ONCE before clicking" (vmd/AGENTS.md FIRST-CLICK QUIRK block; pv_instructions:515–517).
6. **Byte-frozen game.tcl invariants** (header 85–146): 16-13 guard byte-identical; ONE mutate; ONE 1-arg reconstruct (P8); stamp_tier_codes BEFORE add_hider_reps; hider reps land LAST (base..base+2N-1); scene-rep application = backup::apply. Materials slot AFTER add_hider_reps and touch NONE of these.
7. **Tcl 8.5.6 only** — no try/finally/lmap/dict-get-default/`{expand}` abuse (available: dict, lassign, apply, `{*}`); brace every expr; one `variable` per line.
8. **Zero external deps** — everything Phase 18 needs ships with VMD 1.9.3 (`mol modmaterial`, stock materials.dat names — all verified present in `vmd-ref/scripts/materials.dat`).
9. **Comment hygiene** — the 8.6-idiom gate greps COMMENTS too; reword comment text away from gated literals (14-03).
10. **Order-stable dict eq** — every new dict output rebuilt in DEFAULTS/GAME_REPS order (validate_state:121–125 discipline; load_setup rebuild list, demos.tcl:176).
11. **Draw-adaptive assertion discipline** — any randomized-round materials smoke asserts invariants, never literal draws (17.1-06 step-8 / 17.2-10 / 17.2-11 precedents).

---

## 9. Open questions

1. **ttk::combobox availability in Tk 8.5.6** — What we know: zero occurrences in `vmd-ref/`; Tk loads only in GUI mode (cannot probe headlessly); the menubutton+menu idiom is proven in-repo. What's unclear: whether `ttk::combobox` exists in this build. Recommendation: plan the menubutton picker (§3.1); optional 30-second human probe if the planner insists on combobox.
2. **`mol modmaterial` with an INVALID material name** — error, `ERROR)`-print + no-op (the modstyle P-1 class), or silent no-op? Unverified locally. The P-1 read-back compare (§1.2) makes correctness independent of the answer, but the Warning-class requirement (§8.2) wants it probed — a 1-line headless probe in 18-06's smoke (`mol modmaterial 0 $m NoSuchMat` + read-back) settles it.
3. **GameBlend creation & persistence** (parallel researcher's domain, integration contract): who calls `material add GameBlend` (entry? materials.tcl on first use?), does it survive `mol delete`/restart (expect yes — material definitions are session state, not molecule state — UNVERIFIED), and does `material list` work in text mode (expected yes — not a Tk command — UNVERIFIED). Phase 18's curated list can ship WITHOUT GameBlend if this lands late.
4. **Tachyon .dat material tokens** — the 17.1-08 pin documents the per-primitive `Phong Plastic ... Color R G B` line; whether a Glass1/Translucent rep emits a DIFFERENT material-property line (or name token) must be pinned by the first-render inspection in 18-08 (the established first-render-inspection precedent). This decides whether the headless render proof for materials is a token parse (cheap) or needs the parallel researcher's Tachyon findings.
5. **GUI widget coverage depth for the checkpoint** — the rep_verify driver exercises state plumbing (validate→apply), not raw widget clicks. The form interactions (toggle flip, picker menus) are human steps in 18-13 (§6). Acceptable per the 14-04 precedent (widget rendering was human-verified there), but the planner should size 18-13 accordingly.

---

## Sources

### Primary (HIGH confidence — read from the repo, cited by file:line)
- `vmd/lib/game.tcl` (full, 622 lines) — start_game 147–410, cleanup 427–436, restart 452–466, on_pick 573–622, guard 149–191, warn loop 204–212
- `vmd/lib/rep_tiers.tcl` (full, 254 lines) — IMPLEMENTED_TIERS 60, TIER_KINDS 66–76, resolve_per_rep 166–221, tiers_from_per_rep 228–240, effective_total 245–254
- `vmd/lib/setup_state.tcl` (full, 325 lines) — DEFAULTS 18–29, validate_state 126–197, randomize_per_rep 204–225, randomize_state 234–293
- `vmd/lib/demos.tcl` (full, 189 lines) — save_setup 116–133, load_setup 142–181, get_active_reps 89–100
- `vmd/lib/backup.tcl` (full, 114 lines) — snapshot 39–50, apply 70–89, restore 109–114
- `vmd/lib/hiders.tcl` (full, 253 lines) — add_hider_reps 121–185, tier_styles 97–99, stamp_tier_codes 199–209
- `vmd/gui/setup_tab.tcl` (full, 691 lines) — vars 27–46, _dget 56–59, build_hiders_group 174–209, collect_state 251–285, apply_state 297–345, on_rep_toggled 443–482, do_save 618–674
- `vmd/gui/dialog.tcl` (full, 226 lines) — on_start 143–226 (4-arg call 209–212), on_close 92–111
- `vmd/biochemeleon.tcl` (full, 179 lines) — re-source guard 29–32, source order 75–118
- `vmd/tests/rep_verify.tcl` (full, 637 lines) — all pv_* procs
- `vmd/smoke/phase17_capstone_smoke.tcl` (header 1–95), `phase17_licorice_smoke.tcl` (_parse_dat 124–148, restored-style 582–610, marker 618–620), `phase15_backup_smoke.tcl` (material fixtures 75–76, 4-tuple assert 82–94), `phase14_mol_smoke.tcl` (save/load Check 7, 119–137)
- `vmd-ref/scripts/materials.dat` (full, 1521 bytes — all 21 stock names space-free; Opaque/Transparent coded-in)
- `.planning/STATE.md` (full), `.planning/REQUIREMENTS.md` (MATERIAL-01/02, lines 67–68, 137–138), `.planning/ROADMAP.md` (Phase 18, lines 186–200), `.planning/config.json` (parallelization/commit_docs)
- `vmd/AGENTS.md`, root `AGENTS.md` — environment/domain rules
- 17.1/17.2 SUMMARY frontmatter (requires/provides/key-files) — wave-structure precedent

### Parallel-researcher boundary (NOT duplicated here)
- Materials inventory + properties, `material add/change` semantics, GameBlend recipe, Tachyon material-export behavior (Open Questions #3/#4 hold the integration contracts).

## Metadata

**Confidence breakdown:**
- Hook-point map: HIGH — every line cited from full-file reads; game.tcl ordering contract is comment-pinned in-source.
- State schema: HIGH — mechanics verified against validate/randomize/save-load source; one design choice (DEFAULT_MATERIAL value) left to planner.
- GUI wiring: HIGH for structure/traps (all cited); MEDIUM for the picker widget (combobox unverified — menubutton recommended).
- Backup analysis: HIGH — quoted code; gap reasoned from the material-name-vs-definition distinction + 16-15 precedent.
- Testing stack: HIGH — gate numbers from 17.2-11; render-token claim flagged for first-render pinning.
- Plan decomposition: MEDIUM-HIGH — follows the verified 17.x wave/dependency precedent; orchestrator may re-cut.

**Research date:** 2026-09-14
**Valid until:** ~2026-10-14 (stable domain; re-verify only if 17.2-12 close-out changes lib code)
