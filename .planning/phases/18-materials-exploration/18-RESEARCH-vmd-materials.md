# Phase 18: Materials Exploration — VMD 1.9.3 Material System Research

**Researched:** 2026-09-14 (headless probes against the real Windows VMD 1.9.3 binary)
**Domain:** VMD 1.9.3 tcl material system as a hider-blending dimension (MATERIAL-01, MATERIAL-02)
**Confidence:** HIGH on API/semantics (all claims probe-verified this session unless tagged [ref]/[v1]); LOW on visual quality + transmode + pick-through (GUI-checkpoint items by nature)

**Tag legend:** [probe] = executed headlessly this session (`tmp/probe18a..18c`, log excerpts in appendix); [ref] = VMD 1.9.3 reference source in `vmd-ref/` (save_state.tcl / viewmaster.tcl / materials.dat); [v1] = PyMOL v1 analogue. Unverified claims are in Open Questions, not stated as facts.

---

## Summary

The VMD 1.9.3 material system is fully probe-verified: 23 stock materials, 9 settings per material in a FIXED order, per-rep assignment via `mol modmaterial` that never leaks across reps/molecules, and a custom-material workflow (`material add <name> copy <base>` → `material change <prop> <name> <value>`) that is deterministic and restorable in-session. Materials are **per-rep named references to SHARED named objects**: `mol modmaterial` is safe and isolated, but `material change <stockname> ...` mutates every rep on every molecule that references that name — the phase's custom GameBlend material exists precisely to avoid that blast radius.

Materials are headlessly provable BEYOND molinfo read-back: Tachyon `.dat` exports embed per-primitive `Opacity <v>` / `Phong Plastic <specular>` tokens, so a phase smoke can assert material assignment with the repo's established scene-diff discipline (hiders-only render shows `Opacity 0.85`; Opaque baseline shows `Opacity 1`). Lighting is scriptable (`light 0..3 on/off/status`, `display depthcue ...`) and light state is even Tachyon-provable (Directional_Light line count), but `save_state` does NOT persist light on/off — keep lighting OUT of Phase 18's managed state.

The gameplay value remains a hypothesis (per FEATURES.md LOW-confidence rating) — this research makes it TESTABLE: a difficulty ladder of materials ordered by opacity, a curated set with per-material hiding rationale, and three explicit GUI-checkpoint questions (visual distinctness, transparency depth-sorting, and — critical — whether transparent reps still receive atom picks).

**Primary recommendation:** Build hider material blending exclusively on a custom `GameBlend` material (`material add GameBlend copy Opaque` + opacity/specular changes, NEVER mutate stock names) plus a curated stock set {GameBlend, Translucent, Glass2, EdgyGlass, Glass3} with {Glass1, Ghost} gated behind hard difficulty pending the pick-through GUI check. Prove assignment headlessly via molinfo read-back + Tachyon `Opacity` token counts; defer look/feel to the GUI checkpoint.

---

## Verified API Reference

All commands verified against VMD 1.9.3 (WIN32, Nov 30 2016, Tcl 8.5.6), fresh headless session, 2026-09-14.

### `material` subcommands (exact 1.9.3 usage text, captured by probe A [probe])

```
material list
material settings <name>
material add [<newname>] [copy <copyfrom>]
material rename <oldname> <newname>
material change [ambient|specular|diffuse|shininess|mirror|opacity|outline|outlinewidth|transmode] <name> <value>
```

Note the usage text omits `delete` and `default` — both exist but are undocumented (below). The property list in the usage text is the AUTHORITATIVE valid-property set: ambient, specular, diffuse, shininess, mirror, opacity, outline, outlinewidth, transmode.

| Command | Verified behavior | Tag |
|---|---|---|
| `material list` | Returns 23 names: Opaque Transparent BrushedMetal Diffuse Ghost Glass1 Glass2 Glass3 Glossy HardPlastic MetallicPastel Steel Translucent Edgy EdgyShiny EdgyGlass Goodsell AOShiny AOChalky AOEdgy BlownGlass GlassBubble RTChrome. Custom materials are APPENDED at the end. | [probe] |
| `material settings <name>` | Returns a 9-value list in FIXED order **ambient, specular, diffuse, shininess, mirror, opacity, outline, outlinewidth, transmode** (order probe-verified by setting each property to a distinctive value and observing which index moves — B13; corroborated by [ref] save_state.tcl:389 `lassign [material settings $mat] amb spec dif shin mirr opac outl outlw transmode` and [ref] viewmaster.tcl:826). On unknown name: errors `material settings: material 'zzznomat' has not been defined`. | [probe]+[ref] |
| `material change <prop> <name> <value>` | Sets one property on the NAMED material — **global, shared, immediate** (see Pitfalls). Prop comes FIRST, then name, then value. | [probe] |
| `material add <newname> copy <base>` | Creates a new material as a VALUE-COPY of `<base>`'s current settings. Returns the new name (capturable: `set nm [material add Foo copy Opaque]` → nm=Foo). | [probe] |
| `material add <newname>` (1-arg) | Copies the CURRENT live settings of the session default material (Opaque by default) — probe B4 created a material whose settings matched the then-current (mutated) Opaque, not Transparent. | [probe] |
| `material add` (0-arg) | Auto-names `Material<N>` (probe A created "Material23" in a fresh session). Avoid in game code — always pass a name. | [probe] |
| `material rename <old> <new>` | Works; name slot moves with the material (position in `material list` preserved). Reps referencing the old name follow the rename (not probed directly — see Open Questions; viewmaster/save_state never rename materials in use). | [probe] |
| `material delete <name>` | Works on CUSTOM materials (name leaves the list). On stock: `material delete Opaque` → error `Unable to delete material: Opaque` — stock materials are protected from deletion but NOT from modification ([ref] save_state.tcl:375 comment: "materials 0 and 1 cannot be deleted, but they can be modified"). | [probe] |
| `material default <int>` | EXISTS but takes an INTEGER, not a name: `material default Glass1` → `expected integer but got "Glass1"`. Semantics unverified — see Open Questions. **Not needed by the phase; avoid.** | [probe] |
| `material duplicate` | No-arg call errors with an empty message; NOT in the usage text. Treat as nonexistent — use `material add <new> copy <base>`. | [probe] |

### `mol` material forms

| Command | Verified behavior | Tag |
|---|---|---|
| `mol modmaterial <rep> <molid> <name>` | THE per-rep assignment. Strictly per-rep, per-molecule (C2: `mol modmaterial 0 $mA Ghost` left mol B's rep 0 Opaque). Works on ALL 10 GAME_REP tiers incl. multi-word style `DynamicBonds 1.6` (probe E read-back matrix). With an INVALID name: **silent no-op** — no error, rep keeps its previous material (C4). | [probe] |
| `mol material <name>` (ONE arg) | Sets the default material used by SUBSEQUENT `mol addrep` calls — SESSION-GLOBAL, not per-molecule (C5: set Glass1, then addrep on two different mols → both new reps got Glass1). With 2 args (`mol material 0 Glass1`): `ERROR) Invalid material specified: 0 Glass1` + `Using default: Opaque` (B2). **Restore with `mol material Opaque` after use** or later addreps inherit the override. This is the form [ref] save_state.tcl:208 emits before re-adding reps. | [probe]+[ref] |
| `molinfo $m get "{material $i}"` | Per-rep material NAME read-back. **Inner braces REQUIRED**: `{material 0}` unbraced (or quoted without inner braces) errors `molinfo: cannot find molinfo attribute '0'`. Works combined: `molinfo $m get "{color 0} {material 0}"` → `{ColorID 4} Glass3`; the viewmaster form `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` returns the flat 4-token list (C1 formF: `Lines all Name Opaque`). Bare `molinfo $m get material` (no index) returns rep 0's material (D2: followed a modmaterial on rep 0). Out-of-range rep index errors `<attr> <i> out of range`. | [probe] |

### Reading material VALUES (as opposed to names)

`molinfo` returns only the NAME. The VALUES live in the shared named object: `material settings <name>`. Full per-rep visual state = `molinfo get "{material $i}"` → `material settings <that name>`.

### Lighting / depth cue (Q6)

| Command | Verified behavior | Tag |
|---|---|---|
| `light num` | → 4 (lights 0–3). | [probe] |
| `light <0-3> status` | Returns e.g. `on unhighlight` / `off unhighlight`. Defaults in a fresh text session: 0=on, 1=on, 2=off, 3=off. | [probe] |
| `light <n> on/off` | Works for 0–3. **`light 5 on` does NOT error** — out-of-range light numbers are silently accepted (silent trap #3; validate indices 0–3 in game code). | [probe] |
| `light <n> rot <axis> <deg>` / `light <n> pos [{x y z}\|default]` | Listed in usage text; not exercised (rotation/position not needed by Phase 18). | [probe] (usage text only) |
| `display depthcue on/off`, `display get depthcue` | Scriptable toggle + query; fresh text session reads `off`. | [probe] |
| `display get cuestart/cueend/cuedensity/cuemode` | 0.5 / 10.0 / 0.32 / Exp2 in a fresh session; settable per [ref] save_state.tcl:433-446 pattern. | [probe]+[ref] |
| `display get shadows / ambientocclusion / projection` | off / off / Perspective (ray-trace params; [ref] save_state.tcl:449-466). | [probe]+[ref] |

**Tachyon-provability of scene state [probe]:** light 0 off → the `.dat` loses one `Directional_Light` line (2 → 1). Depthcue on/off and material transmode 0→1 produced NO token change in the `.dat` (Trans_VMD/Fog_VMD shader-mode lines are static) — those two are NOT headlessly provable.

### Persistence (relevant to later phases; Phase 18 needs in-session restore only)

- `save_state <file.vmd>` embeds a `vmdrestoremymaterials` proc: for EVERY material in `material list` it emits `material add $mat` (if missing) + all NINE `material change <prop> <mat> <value>` lines ([probe] saved.vmd lines 6-30; [ref] save_state.tcl:371-402). Custom materials persist across save/load.
- `save_state` persists `display depthcue/cuestart/cueend/cuedensity/cuemode` ([probe] saved.vmd:331-334; [ref] save_state.tcl:433-446) but does **NOT persist `light <n> on/off`** ([ref] save_state.tcl has no light section; [probe] saved.vmd contains no `light` lines).
- Stock materials RESET on every `vmd` launch: probe C ran in a session AFTER probe B had mutated Opaque's opacity to 0.42, and read pristine 1.0 — cross-session evidence [probe]. Only in-session restore matters for the game.

---

## Material inventory table

All values [probe] (B11 dump; session-fresh values) in settings order `amb spec dif shin mirr opac outl outlw transmode`. Opaque row cross-checks against [ref] vmd-ref/scripts/materials.dat (`Opaque 0.00 0.65 0.50 0.53 0.00 1.00` — note materials.dat column order is amb,dif,spec; settings order is amb,spec,dif). **Correction to prior research:** FEATURES.md:112 lists "Translucent (0.30)" — actual Translucent opacity is **0.80**; 0.30 is *Transparent*'s opacity. Also FEATURES.md/ARCHITECTURE.md say "23/24 materials" in different places — the count is **23** [probe].

| Material | amb | spec | dif | shin | mirr | opac | outl | outlw | transmode | Hiding rationale (visual claims → GUI checkpoint) | In curated set? |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **GameBlend** (custom) | 0 | 0.65 | 0.65 | 0.534 | 0 | **0.85** | 0 | 0 | 0 | Near-Opaque but subtly more translucent + shinier than real atoms; the "spot the sheen" difficulty rung. Recipe below. | **YES** (centerpiece, MATERIAL-01) |
| Opaque (baseline) | 0 | 0.5 | 0.65 | 0.534 | 0 | 1.0 | 0 | 0 | 0 | The real atoms' default; every hider material is judged against this. | (baseline, not a hider material) |
| **Translucent** | 0 | 0.6 | 0.7 | 0.3 | 0 | **0.80** | 0 | 0 | 0 | Mildest stock transparency; waxy soft look, clearly "off" next to Opaque. Medium rung. | **YES** |
| **Glass2** | 0.52 | 0.22 | 0.76 | 0.59 | 0 | **0.68** | 0 | 0 | 0 | Noticeably glassy yet solid enough to stay findable; high ambient keeps it visible in shadowed areas. Medium rung. | **YES** |
| **EdgyGlass** | 0 | 0.5 | 0.66 | 0.75 | 0 | **0.62** | 0.62 | 0.94 | 0 | Glass WITH outlines — the edge artifact is itself the pedagogy ("notice the rim"); opacity 0.62 but outline makes it easier than Glass3. | **YES** (6th; outline-artifact pedagogy) |
| **Glass3** | 0.15 | 0.75 | 0.25 | 0.8 | 0 | **0.50** | 0 | 0 | 0 | Clearly translucent, high specular sparkle. Hard rung. | **YES** |
| Glass1 | 0 | 0.65 | 0.5 | 0.53 | 0 | **0.15** | 0 | 0 | 0 | Very faint; plausibly click-through (see Open Questions) → hard-difficulty gate only. | GATED (hard) |
| Ghost | 0 | 1.0 | 0.0 | 0.23 | 0 | **0.10** | 0 | 0 | 0 | Pure specular ghost, no diffuse body — nearly invisible. Expert gate; same pick-through caveat. | GATED (expert) or exclude |
| Transparent | 0 | 0.5 | 0.65 | 0.534 | 0 | 0.30 | 0 | 0 | 0 | Same shading as Opaque at 0.30 — "Opaque but see-through"; redundant with Glass set, adds no new artifact type. | no |
| BlownGlass | 0.04 | 1.0 | 0.34 | 1.0 | 0 | 0.10 | 0 | 0 | **1** | Shiny, near-invisible, and the only stock non-zero transmode — transmode's visual effect is unverified → exclude until GUI-checked. | no |
| GlassBubble | 0.25 | 1.0 | 0.34 | 1.0 | 0 | **0.04** | 0 | 0 | 1 | Essentially invisible (0.04). Dead-on-arrival for hiders. | no (DOA) |
| Edgy | 0 | 0 | 0.66 | 0.75 | 0 | 1.0 | 0.62 | 0.94 | 0 | Opaque + outline — a look-variant, no translucency axis. Future "confuser" material. | no (future) |
| EdgyShiny | 0 | 0.96 | 0.66 | 0.75 | 0 | 1.0 | 0.76 | 0.94 | 0 | Same, shiny variant. | no (future) |
| Goodsell | 0.52 | 0 | 1.0 | 0 | 0 | 1.0 | **4.0** | 0.9 | 0 | Opaque with THICK outlines (outlinewidth 4.0) — pops out of the scene; better as a decoy/reveal style than a hider. | no |
| BrushedMetal / Diffuse / Glossy / HardPlastic / MetallicPastel / Steel | — | — | — | — | — | 1.0 | — | — | 0 | Opaque shading variants (matte/metal look). No blending dimension; possible future distractors. | no |
| AOShiny / AOChalky / AOEdgy | 0 | 0.2/0/0.2 | 0.85/0.85/0.9 | 0.53 | 0 | 1.0 | (AOEdgy: 0.62/0.93) | | 0 | Ambient-occlusion look — visually near-identical to plain materials when AO/shadows are OFF (the default). Dead-on-arrival under default display settings. | no (DOA under defaults) |
| RTChrome | 0 | 0.5 | 0.65 | 0.53 | **0.70** | 1.0 | 0 | 0 | 0 | Mirror 0.7 — shine mostly materializes in Tachyon ray-trace renders, not the default OpenGL preview. Display-dependent → exclude. | no |

**Difficulty ladder implied by the curated set (opacity ascending):** GameBlend 0.85 → Translucent 0.80 → Glass2 0.68 → EdgyGlass 0.62 (outline-boosted) → Glass3 0.50 → [gate] Glass1 0.15 → [gate] Ghost 0.10.

---

## Global side effects & pitfalls

### Pitfall 1: `material change` blast radius (THE key semantics)
**What goes wrong:** Materials are SHARED named objects. `material change opacity Opaque 0.42` instantly re-renders every rep on every molecule referencing "Opaque" (B3: settings mutate; every default rep on both probe molecules references Opaque). A phase bug that "tunes" a STOCK material permanently alters the user's whole scene — and since reps persist, the damage survives until VMD restart.
**Why it happens:** `mol modmaterial` stores a NAME reference, not a value copy; the name resolves to one shared settings object.
**How to avoid:** The game NEVER calls `material change` on a stock name. Workflow: `material add GameBlend copy Opaque` (value-copy, B4) → tune only GameBlend → assign via `mol modmaterial`. Restore = write the 9 saved values back to GameBlend only (C7 round-trip verified eq=1), or `material delete GameBlend` + re-add.
**Warning signs:** A user rep that "looks wrong" after Start; material settings that differ between sessions.

### Pitfall 2: silent acceptance of garbage (three traps)
**What goes wrong:** [probe B9] (a) `material change opacity <name> zzz` sets opacity to **0.0** (string parsed as 0 — silent); (b) values outside [0,1] are stored UNCLAMPED (1.5 and −0.3 both accepted; opacity −0.3 renders as... whatever OpenGL does — unverified, don't rely on it); (c) `material change <unknown-prop> <name> <value>` is a SILENT no-op. Also `mol modmaterial <rep> <mol> <badname>` is a silent no-op (rep keeps previous material, C4); `light 5 on` doesn't error (D1 implied).
**How to avoid:** Game code validates: property names from the fixed 9-list, opacity ∈ [0,1] (clamp in Tcl), material names checked against `material list` before modmaterial. Never trust VMD to reject bad input.
**Warning signs:** Smokes asserting on error behavior that doesn't exist (false-pass in reverse: code that "works" because VMD swallowed garbage).

### Pitfall 3: `mol material <name>` is session-global
**What goes wrong:** After `mol material Glass1`, EVERY subsequent `mol addrep` (on ANY molecule — including the user's own) inherits Glass1 until reset (C5).
**How to avoid:** If used to style hider reps at creation, always follow with `mol material Opaque`. Or skip it entirely and use `mol addrep` + `mol modmaterial` (the repo's established clonerep pattern: set representation/selection/color, addrep, then modmaterial/modselect).

### Pitfall 4: molinfo read-back syntax
**What goes wrong:** `molinfo $m get {material 0}` and `molinfo $m get "material 0"` both ERROR (`cannot find molinfo attribute '0'`); only the inner-brace form `molinfo $m get "{material 0}"` works (C1). Out-of-range rep errors `<attr> <i> out of range` — and when that call sits inside a `puts [molinfo ...]` command substitution, the error escapes the surrounding `catch` blocks (probe D's missing-output lesson).
**How to avoid:** Always brace-group each keyword: `"{material $i}"` / the viewmaster 4-keyword form. Guard read-backs, not just writes. Smoke convention: scan full output for `ERROR)` AND `bad switch` AND `out of range`.

### Pitfall 5: transparency depth-sorting (GUI-checkpoint class)
**What goes wrong (expected):** Translucent geometry with `display projection Perspective` and multiple Glass/Translucent reps can z-sort incorrectly in the OpenGL renderer (draw-order artifacts); dense Glass scenes may shimmer. This is THE "material/lighting artifact" the pedagogy hypothesis wants players to notice — but it also can make hiders unfindable or ugly.
**How to avoid:** Phase 18 must not promise visual quality headlessly; the GUI checkpoint owns: (1) does each curated material look distinct from Opaque, (2) are depth-sorting artifacts pedagogically interesting or game-breaking, (3) does depth cue / lighting state change the look.
**Also probe-verified relevant:** transmode has NO effect on Tachyon export (D5) and its OpenGL meaning is undocumented in accessible sources → treat transmode as a constant 0 for GameBlend until GUI-checked.

### Pitfall 6: Stride errors pollute Cartoon-family smoke logs
**What goes wrong:** Any headless session that renders/creates Cartoon/NewCartoon reps triggers VMD's internal Stride secondary-structure program, which fails in text mode: `ERROR) Unable to find Stride output file` / `ERROR) Call to Stride program failed` (probe E: 3 ERRORs, none material-related). A smoke that greps for bare `ERROR)` false-fails.
**How to avoid:** Phase 18 smokes must classify Stride ERRORs as known-noise (the 17.2 suite already does this — follow its convention) and keep the zero-tolerance scan for OTHER ERROR classes.

### Restore / rollback strategy (Q7)
Deterministic in-session reset of the custom material:
```tcl
# capture (9 values, fixed order amb spec dif shin mirr opac outl outlw transmode)
set saved [material settings GameBlend]
lassign $saved amb spec dif shin mirr opac outl outlw transmode
# ... round uses GameBlend, may tune it ...
# restore (save_state.tcl:390-398 pattern [ref])
material change ambient      GameBlend $amb
material change specular     GameBlend $spec
material change diffuse      GameBlend $dif
material change shininess    GameBlend $shin
material change mirror       GameBlend $mirr
material change opacity      GameBlend $opac
material change outline      GameBlend $outl
material change outlinewidth GameBlend $outlw
material change transmode    GameBlend $transmode
# verify: [expr {$saved eq [material settings GameBlend]}] == 1  (C7: ROUNDTRIP-EQ 1)
```
`material delete GameBlend` + re-add also works for customs (B5). VMD restart resets stock materials to factory values (cross-session evidence) — but the game can't rely on a restart mid-session, so the restore block above (or re-running `material add GameBlend copy Opaque` + recipe) is the cleanup path. Reps referencing a deleted material: behavior UNVERIFIED (see Open Questions) — prefer re-add-over-delete when reps still reference the name.

---

## Headless test strategy for materials

### Layer 1 — molinfo read-back (always available)
- Per-rep NAME: `molinfo $m get "{material $i}"` (inner braces!) — assert hider reps carry `GameBlend`/stock names; assert non-hider reps still carry their original material.
- Per-material VALUES: `material settings GameBlend` — assert the 9-tuple matches the recipe (this also catches the silent-garbage traps).
- Isolation: after `mol modmaterial` on hider reps, assert scene reps' material names unchanged.
- Tier matrix: one rep per GAME_REP tier, modmaterial + read-back each (probe E is the template; DynamicBonds needs `mol modstyle $i $m DynamicBonds 1.6`).

### Layer 2 — Tachyon token proof (stronger; fits the repo's scene-diff discipline)
VMD's `render Tachyon out.dat` embeds material state per primitive ([probe], C8/D5):

- Opaque rep → `  Ambient 0 Diffuse 0.65 Specular 0 Opacity 1` + `  Phong Plastic 0.5 Phong_size 40 Color 1 1 0 TexFunc 0`
- Glass1 rep → same line shape with `Diffuse 0.5 ... Opacity 0.15` + `Phong Plastic 0.65 Phong_size 38.9045`

**Token mapping [probe]:** `Opacity <v>` = VMD opacity (verbatim shortest form: `Opacity 1`, `Opacity 0.15`, `Opacity 0.8`, `Opacity 0.85`); `Phong Plastic <v>` = VMD **specular** (0.5 → `Phong Plastic 0.5`, 0.65 → `Phong Plastic 0.65`); `Diffuse <v>` = VMD diffuse; `Ambient <v>` = VMD ambient; `Phong_size` ≈ scaled shininess (40 for 0.534, 38.9045 for 0.53 — computed, do NOT pin exactly); `Specular` token stays 0 in these exports; material NAMES do NOT appear anywhere in the `.dat`.

**Assertable in a smoke:**
```tcl
# hiders-only selection rendered with GameBlend(opacity 0.85, specular 0.65):
#   grep -c "Opacity 0.85" out.dat   >= hider atom count   (token count ~1.7-2x atom count [probe])
#   grep -c "Phong Plastic 0.65" out.dat > 0
# Opaque baseline of the same scene:
#   grep -c "Opacity 1 " ...         tokens present, no 0.85 tokens
# both-endpoints rule (repo convention): scene-diff A(hiders-in) minus B(hiders-out) isolates hider tokens
```
- Token counts are scene-scale/primitive-count dependent (like 17.1-10's radius finding) — pin PRESENCE + DISTINCT-VALUE coexistence (e.g. `Opacity 0.85` appears in hider render, absent in baseline), not absolute counts.
- Different materials coexisting in ONE scene produce distinct Opacity tokens side by side (C8: one scene held 0.1 / 0.15 / 0.68 / 0.8 / 1.0 simultaneously) — a per-hider-material-variation smoke is feasible.
- Light on/off is provable via `Directional_Light` line count (D5: 2 → 1) — available if a later phase wants lighting smokes.
- NOT provable in `.dat`: transmode changes, depthcue changes (D5 — zero token delta).

### Layer 3 — GUI checkpoint (must-verify list for the human session)
1. **Pick-through (CRITICAL, gates the hard materials):** with a hider rep shown but Glass1/Ghost (opacity ≤ 0.15), does clicking the hider hit the hider's atom or pass through to the real atom behind? (The known "hidden reps cannot be picked" rule is for `mol showrep off`, NOT transparent-but-shown — untested.) If pick-through happens, Glass1/Ghost are unfindable → drop from the set or re-gate.
2. Visual distinctness of each curated material vs Opaque at game scale (Lines/VDW/Cartoon tiers).
3. Depth-sorting/draw-order artifacts with multiple translucent reps — pedagogically valuable or game-breaking?
4. transmode 0 vs 1 visual difference (BlownGlass/GlassBubble ship 1) — resolves whether transmode is worth exposing.
5. Whether lighting toggles (`light 1/2 on`) make material artifacts more/less noticeable — for the pedagogy documentation.

---

## Recommended curated material set + GameBlend recipe

### Setup-tab vocabulary (MATERIAL-02)
- Toggle: "use material blending" (off by default — reps-only remains the default game, per v1 parity).
- Material picker: curated list (below) + difficulty mapping; orthogonal to the existing 10-rep tier system (hider rep choice × material choice are independent axes; the material multiplies the rep's blend, it does not replace it).
- The pedagogical-value claim goes in the help text AS A HYPOTHESIS ("materials can leave subtle light/edge artifacts — spotting them is a real structural-biology skill"), per the requirement's framing, not as a validated fact.

### Curated set (default, in difficulty order)

| # | Material | Difficulty | Rationale one-liner |
|---|---|---|---|
| 1 | GameBlend (0.85 / spec 0.65) | Easy-Medium | The subtle custom rung: slightly see-through, slightly too shiny — findable by sheen, not by silhouette. |
| 2 | Translucent | Medium | Mildest stock glass; waxy and clearly "off" next to Opaque. |
| 3 | Glass2 | Medium-Hard | Clearly glassy but body keeps it findable. |
| 4 | EdgyGlass | Medium (outline-boosted) | Glass with faint rims — teaches edge/outline artifacts. |
| 5 | Glass3 | Hard | Half-transparent with sparkle. |
| 6 | Glass1 | Hard (gated on pick-through check) | Faint; include only if the GUI session proves picks still land. |
| 7 | Ghost | Expert (gated, may cut) | Pure highlight; near-invisible. |

Dropped from the requirement's implicit candidates with reasons: Transparent (redundant with Glass set), BlownGlass/GlassBubble (transmode 1 unverified + near-invisible), AO* (indistinguishable under default display settings), RTChrome (ray-trace-only shine), Goodsell/Edgy/EdgyShiny/opaque look-variants (no blending axis — candidate future "decoy" materials).

### GameBlend recipe (MATERIAL-01)
```tcl
# idempotent create (never touch stock names)
if {[lsearch -exact [material list] GameBlend] == -1} {
    material add GameBlend copy Opaque          ;# value-copy of stock Opaque [probe B4]
}
material change opacity  GameBlend 0.85          ;# subtle see-through (hypothesis values from FEATURES.md:110)
material change specular GameBlend 0.65          ;# slightly shinier than Opaque's 0.5 -> "too shiny" tell
# assign to hider reps only:
mol modmaterial <hider_rep_idx> $molid GameBlend
```
Reasoning: opacity 0.85 keeps the hider ~85% opaque (visible body, pick-through risk minimal pending GUI check) while specular 0.65 vs Opaque's 0.5 adds a highlight-only tell that works even when the opacity difference is imperceptible — two independent low-signal artifacts, matching the FEATURES.md M-confidence design and the game's "subtle deviation" mechanic. transmode stays 0 (Tachyon-invisible anyway, unverified visually).

### Lighting/depth-cue scope recommendation (Q6)
Keep lighting/depthcue OUT of Phase 18's managed state and OUT of backup.tcl: they are display-level globals, `save_state` itself doesn't persist light on/off (only depthcue), the game doesn't need to mutate them for MATERIAL-01/02, and snapshotting them now would couple Phase 18 to a Phase 19+ concern. If the GUI checkpoint shows lighting is essential to the pedagogy, add a read-only "lighting tips" help line (e.g. `light 1 on`) rather than game-managed lighting. Revisit only if a future phase adds lighting presets.

---

## v1 parity note (Q9)

v1 (PyMOL) had NO material dimension — the rep system was the only blend axis (ARCHITECTURE.md:596: "Materials as blend dimension | (none — v1 rep-only)"; v1 shipped reps + difficulty only) [v1 by prior planning docs; no materials API in PyMOL v1 workflow]. Consequences for Phase 18:
- The "use material blending" toggle and the material picker are NEW setup-tab vocabulary — there is no v1 widget to port; design them fresh, matching the existing setup-tab idiom (checkbutton + radiobutton/combobox as in `gui/setup_tab.tcl`).
- v1's `difficulty_easy` toggle (per-rep remaining display) exists in v2's setup_state already; Phase 18 must decide whether material choice maps onto difficulty_easy or is an independent picker (recommendation: independent picker with its own difficulty ladder; do NOT silently couple to difficulty_easy — different semantic).
- Do not copy v1's rep-centric assumptions like "one rep per hider tier implies one visual style" — a material can now VARY within a single rep tier (per-hider materials would require one rep per material variant; FEATURES.md:111 caps variants at 3-5 to avoid list clutter — keep the cap).

---

## Open questions for planning (unverifiable headlessly → GUI checkpoint or later probe)

1. **Pick-through on transparent reps** (blocks Glass1/Ghost inclusion): does a click on a shown-but-transparent hider hit the hider? GUI checkpoint item #1; until answered, gate opacity ≤ 0.15 materials behind hard difficulty or exclude.
2. **transmode visual semantics**: not in the accessible UG text (PDF not text-extractable with available WSL tools — 317 streams, 0 keyword hits), no Tachyon signature, only BlownGlass/GlassBubble ship 1. GUI check; Phase 18 pins transmode=0.
3. **Rename of an IN-USE material**: does `material rename` update existing reps' references? (Probed rename only on an unused material.) Avoid renaming materials that reps reference; if the phase ever renames, re-probe first.
4. **Rep referencing a DELETED material**: behavior of a rep whose material was deleted (render fallback? error?) — unprobed. Prefer `material add` (idempotent recreate) over delete in game cleanup while reps exist.
5. **`material default <int>` semantics**: takes an integer, undocumented, unused by save_state/viewmaster — treated as nonexistent for the phase.
6. **Visual distinctness / depth-sorting / lighting interplay**: the entire Layer-3 list above; the pedagogy hypothesis itself stays a hypothesis until gameplay validation (per ROADMAP SC and FEATURES.md LOW-confidence rating).
7. **`light <n> status` exact parse**: returns "on unhighlight" — the second token (highlight state) is display-highlight for picking feedback, unrelated to lighting; parse only the first token (best current reading — verify in GUI if ever parsed programmatically).

---

## Sources

### Primary (HIGH — probe-verified this session)
- Probe A `tmp/probe18a/probe.tcl` (+ out in `tmp/probe18a/probe18a_out.txt`): material list (23), usage text, settings dump, silent traps, stock-delete refusal.
- Probe B `tmp/probe18b/probe.tcl` (+ `tmp/probe18b/out.txt`): blast radius (B3), add/copy forms (B4), rename/delete (B5), default-int error (B6), silent garbage (B9), 23-material settings dump (B11), settings order (B13), transmode range (B14).
- Probe C `tmp/probe18c/probe.tcl` (+ `tmp/probe18c/out.txt`): molinfo syntax resolution (C1), per-rep isolation (C2), color+material coexist (C3), bad-name no-op (C4), `mol material` global semantics (C5), fresh-mol default (C6), GameBlend restore round-trip eq=1 (C7), 5× Tachyon renders + token decode (C8), light/depthcue surface (C9), save_state materials block (C10).
- Probe D `tmp/probe18a/probe18d.tcl` (+ `tmp/probe18a/d_out.txt`): light num/status, bare molinfo material, add return value, transmode/depthcue/light Tachyon deltas (d5_*.dat in tmp/probe18c/).
- Probe E `tmp/probe18a/probe18e.tcl` (+ `tmp/probe18a/e_out.txt`): 10-tier × modmaterial read-back matrix, per-rep material variety, DynamicBonds 1.6 multi-word style, Stride-noise documentation.

### Secondary (HIGH — [ref])
- `vmd-ref/scripts/save_state.tcl:371-402` (material save/restore recipe + settings order), `:208` (`mol material $m` before addreps), `:433-466` (depthcue/AO/display state).
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:252,315-317,724-728,819-835` (rep save/restore incl. material; material settings capture/restore).
- `vmd-ref/scripts/materials.dat` (factory values; column order amb,dif,spec — differs from settings order).

### Tertiary
- `vmd-ref/ug.pdf` — present but NOT text-extractable with available WSL tools (no pdftotext; stream decompression found 0 keywords) — cited only for absence (transmode undocumented).
- `.planning/research/FEATURES.md:104-136` (design hypotheses; one corrected value: Translucent opacity 0.80 not 0.30), `ARCHITECTURE.md:596` (v1 rep-only), `STACK.md:262` (mol/modmaterial forms).

## Metadata

**Confidence breakdown:**
- API surface & semantics: HIGH — every command executed against the real 1.9.3 binary this session; 3 independent sources agree on settings order (probe B13 + save_state.tcl + viewmaster.tcl).
- Inventory values: HIGH — full 23-material dump + materials.dat cross-check.
- Headless test strategy: HIGH — token pattern captured and reproduced across 9 renders.
- Curated set: MEDIUM — opacity ladder + artifact classes are evidence-based, but visual quality/pick-through are unverified by nature.
- Pedagogy value: LOW (unchanged from FEATURES.md) — hypothesis; Phase 18 makes it testable.

**Research date:** 2026-09-14
**Valid until:** binary-pinned (VMD 1.9.3 install is fixed) — re-probe only if the VMD binary changes; GUI-checkpoint items valid until the Phase 18 human session.
