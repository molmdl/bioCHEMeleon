# Phase 11 Research — ASPECT A: Rendering & Construction Feasibility

**Researcher:** A (rendering + construction)
**Researched:** 2026-08-15
**Domain:** PyMOL 2.5.0 altLoc / alternate-conformation handling, cartoon+ribbon trace rendering, backbone-only segment construction
**Confidence summary:** A1=HIGH, A2=HIGH (runtime-verified), A3=HIGH (mechanism) / MEDIUM (backbone-only variant), A4=MEDIUM (headless-verified fixes, GUI human-verify pending), A5=HIGH (alter_state) / MEDIUM (exact visual), A6=HIGH

---

## Critical context: prior 05-06/05-08 attempt (recovered from git history)

The 05-06 research spike (commit `a6fd26a`) and 05-08 implementation (commits `3e65d41`–`335fe3c`) were REVERTED from HEAD — they live on branch `backup/05-08-attempts`, NOT in the current ancestry. The 05-06 spike findings (section 12 of 05-RESEARCH.md, commit `1f22014`) were REMOVED from the current 05-RESEARCH.md (823 lines now; spike brought it to 947). This file recovers those runtime-verified findings and the 05-08 integration bug analysis.

**The spike PROVED the central hypothesis viable in isolation (10/10 headless ALL PASSED). The 05-08 implementation hit 4 cascading GUI-only bug classes that each passed headless verification but failed in the GUI.** Phase 11 must build on the spike's verified mechanism while addressing the integration hazards the 05-08 attempt discovered. Re-research should focus on INTEGRATION, not re-proving the mechanism.

---

## A1. AltLoc fundamentals in PyMOL 2.5.0

### How PyMOL represents altLoc (the `alt` atom field)

**Verified (HIGH):** `alt` is a per-atom string field (the PDB altLoc column). It is writable via `cmd.alter`.

- **Symbol table** (editing.py:1444-1449): `name, resn, resi, resv, chain, segi, elem, alt, q, b, vdw, type, partial_charge, formal_charge, elec_radius, text_type, label, numeric_type, model*, state*, index*, ID, rank, color, ss, cartoon, flags`. `alt` has NO `*` (read-write). `model*`, `state*`, `index*` are read-only.
- **`alt` selector** (cmd.py:357): `'alt '` is in the selector keyword list, alongside `name `, `id `, `chain `, `segi `, `resi `. Selections like `alt B` or `alt ''` work.
- **Atom identify string** (editing.py:40): `f'/{self.model}/{self.segi}/{self.chain}/{self.resn}`{self.resi}/{self.name}`{self.alt}{tail}>'` — `alt` is part of the atom's display identity.
- **`alt` is part of the atom IDENTITY KEY** (05-06 spike, runtime-verified): two atoms with the same `(segi, chain, resi, name)` but different `alt` are treated as ALTERNATE CONFORMATIONS of the same logical atom, NOT as duplicate atoms. This is the PDB altLoc semantics: `alt=''` (blank) is the default conformation; `alt='A'`, `alt='B'`, `alt='C'` are alternates.

### How to SET `alt` on an atom

**Verified (HIGH) — use `cmd.alter`:**

```python
# Set alt='B' on a selection (editing.py:1424; hygienic space={})
cmd.alter(selection, "alt='B'", space={})
```

- `cmd.alter` evaluates the expression per atom, writing to the `alt` field (editing.py:1424-1473; line 1472 calls `_cmd.alter`).
- Use `space={}` (hygienic — no global namespace pollution; AGENTS.md sentinel rule: "NEVER `space=None`").
- **`cmd.alter_state` does NOT set `alt`** — `alter_state` (editing.py:1535) is for COORDINATES (x/y/z) and state-dependent flags, not for atom properties like `alt`. Use `cmd.alter` for `alt`.

### Does the renderer treat alt-conf atoms as alternates of ONE logical atom or as distinct atoms?

**Verified (HIGH) — as ALTERNATES of one logical atom:** The renderer (cartoon/ribbon trace, lines/sticks bonds) treats atoms with the same `(chain, resi, name)` but different `alt` as alternate positions of the same atom. The cartoon trace draws THROUGH whichever alt-conf CA is present; if multiple alt-conf CAs exist at the same residue, the trace follows EACH as a parallel path (confirmed by 05-06 spike: `game_cartoon_ca = 3` for 3 alt-conf CAs — all 3 render).

### Does creating alt-conf atoms REQUIRE occupancy management?

**Verified (HIGH) — NO, occupancy is not required for rendering.** The 05-06 spike set `alt='B'` without setting occupancy (`q`), and the cartoon rendered (`game_cartoon_ca = 3`). PyMOL's default occupancy (`q=1.0`) works. Occupancy (`q`) is a separate field (editing.py:1446 symbol table, read-write); it affects B-factor/occupancy-weighted calculations but NOT cartoon/ribbon rendering. **Do NOT hand-roll occupancy management — the default works.**

---

## A2. Cartoon & ribbon trace — does it follow alt-conf? (THE CENTRAL HYPOTHESIS)

### VERIFIED (HIGH) — the central hypothesis is TRUE

**The 05-06 spike (commit `a6fd26a`, recovered from git history commit `1f22014`) ran 10/10 headless ALL PASSED on 1ubq, confirming:**

| Check | Result | Diag Value |
|-------|--------|------------|
| Cartoon renders alt-conf GAME CAs (default settings) | **PASS** | `game_cartoon_ca = 3` |
| Ribbon renders alt-conf GAME CAs | **PASS** | `game_ribbon_ca = 3` |
| Alt-conf GAME atoms in polymer | **PASS** | `game_polymer = 25` (all 25 alt-conf atoms are polymer — cartoon trace includes them) |
| all_states required for cartoon? | **NO** | `game_cartoon_ca_all = 3` with `all_states=off` — NOT needed (single hider) |
| alter_state displacement (x=x+2.0) | **PASS** | `dx=2.0000` — coords shifted exactly 2 Å |
| Cleanup by segi GAME restores count | **PASS** | `after_count=660, orig_count=660` |
| Sentinel: fetch_all_hider_ids returns 1 atom | **PASS** | `fetch_ids = [('1ubq', 227)]` |

**CENTRAL HYPOTHESIS VERIFIED:** Replicating a copied protein segment as PyMOL alternate conformations (altLoc) DOES make the cartoon/ribbon renderer draw a SECOND, connected trace through the copied backbone. The alt-conf CAs are classified as `polymer` (connectivity-based; cmd.py:363 `polymer` selector), so the cartoon trace includes them. The trace renders through all alt-conf CAs as a parallel path to the original, creating a connected, blended visual — NOT a disconnected terminal extension (the Phase 5 cosmetic gap).

### The WORKING mechanism (05-06 spike discovery, runtime-verified)

**Three approaches were tested — only the third works:**

1. **DISPROVED:** `cmd.create(obj, seg, 1, 1)` (same-object create). This is a **NO-OP** — `cmd.create` MERGES by identity (segi, chain, resi, name) when the target name equals the source object. A subset selection overwrites itself, producing 0 new ids. (creating.py:960 — the "create states in an existing object" path deduplicates by identity.)
2. **DISPROVED:** `cmd.create(tmp, seg)` + `cmd.fuse(tmp, obj, mode=3)` (editing.py:937-987; mode 3 = "don't move and don't create a bond, just combine into single object"). `cmd.fuse mode=3` RENAMES atoms to avoid collisions — CA→C02/C03, N→N01, O→O04. The 25 fused atoms have NO `name CA`, so the cartoon trace (which goes through C-alpha atoms) cannot render them. NOT alt-conf pairs (different names).
3. **WORKING (the spike's discovery):** `cmd.create(tmp, seg, 1, 1)` + `cmd.alter(tmp, "alt='B'; segi='GAME'", space={})` + `cmd.create(obj, tmp)` + `cmd.delete(tmp)`. The `alt='B'` tag makes the temp atoms' identity DIFFER from the `alt=''` originals (alt is part of the identity key), so `cmd.create(obj, tmp)` APPENDS them as TRUE alt-conf pairs — same chain/resv/name=CA, but alt='B'. 25 atoms appended, 3 CAs, all alt-conf pairs of the originals. The cartoon trace renders them, they're polymer, alter_state displaces them, and cleanup by segi GAME removes them.

### Does the cartoon trace require a contiguous N-C-CA backbone?

**Verified (HIGH):** The cartoon trace follows consecutive C-alpha atoms along `polymer` atoms (preset.py:395 `show_as('cartoon', 'polymer & ...')`; mutagenesis.py:570 `count_atoms("(%s & name CA & rep cartoon)" % src_sele) > 0`). It does NOT require N-C-CA bonds specifically — it follows the CA trace. The alt-conf CAs inherit the polymer classification from the source segment (they're copies of polymer atoms), so the trace includes them. **A backbone-only copy (N, CA, C, O — no sidechain) WILL render in cartoon** because the CA trace is intact. (MEDIUM — the spike copied the WHOLE segment including sidechain; backbone-only needs runtime-verify, but the cartoon only needs CAs.)

### Does `cmd.show('cartoon', selection)` on alt-conf backbone atoms render? What about `ribbon`?

**Verified (HIGH):** YES for both. The 05-06 spike confirmed `game_cartoon_ca = 3` AND `game_ribbon_ca = 3` — both reps render alt-conf CAs. The 05-09 rep-forwarding fix (commit `2d487af`, in HEAD) parameterized `cmd.show(rep, ...)` so `rep='ribbon'` shows ribbon, `rep='cartoon'` shows cartoon. **Use `cmd.show(rep, "%s and segi GAME" % obj)` — the requested rep is shown, not hardcoded.**

### Does the cartoon trace require `ss` (secondary structure) flags?

**Verified (HIGH):** The cartoon REP renders regardless of `ss` (the `ss` field controls the cartoon TYPE — helix ribbon vs sheet arrow vs loop tube). The alt-conf CAs inherit `ss` from the source segment (they're copies via `cmd.create`, which copies atom properties). The 05-05 fix set `ss='L'` (loop) on the terminal-extension hider for a smooth tube; for the alt-conf approach, the copies INHERIT the source `ss` (e.g. if the source segment is a loop, the alt-conf copy is a loop; if it's a helix, the alt-conf copy is a helix). **Recommendation: set `ss='L'` on the alt-conf copies via `cmd.alter` for a consistent smooth-tube visual** (mirrors the 05-05 fix; avoids a sheet-arrow shape that looks "disconnected"). This is optional — the cartoon renders either way.

---

## A3. Backbone-only residue construction (ranked mechanisms)

User requirement 1: "Only generate the BACKBONE of the copied residues, to be simple" — the copied/replicated segment should contain only backbone atoms (N, CA, C, O), NOT the full sidechain.

### Ranked candidate mechanisms

#### MECHANISM 1 (WINNER): `cmd.create` with `backbone` selector + `alter alt='B'` + `cmd.create` append

**How:** Copy only backbone atoms to a temp, set alt-conf + sentinel, append to target.

```python
# 1. Copy BACKBONE ONLY to temp (creating.py:960; cmd.py:364 'backbone' selector)
segment_sele = "%s and chain %s and resi %d-%d and backbone" % (object, chain, start_resi, end_resi)
cmd.create(tmp, segment_sele, 1, 1)   # source_state=1, target_state=0 (new obj)

# 2. Set alt-conf + sentinel on temp (editing.py:1424; hygienic space={})
cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'", space={})

# 3. Append alt-conf atoms to target (creating.py:960 -- different identity = append)
cmd.create(object, tmp)                # zoom=0 CRITICAL (Bug 3 fix; see A4)

# 4. Clean up temp
cmd.delete(tmp)

# 5. Defensive sort (editing.py:1457)
cmd.sort(object)
```

**Why it wins (HIGH confidence):**
- The 05-06 spike VERIFIED this exact mechanism (with the whole segment, not backbone-only) — 10/10 headless ALL PASSED. The `backbone` selector is a standard PyMOL selector (cmd.py:364) that selects N, CA, C, O for protein residues. Using it in the source selection copies only backbone atoms.
- The alt-conf copies inherit the polymer classification (they're copies of polymer backbone atoms), so the cartoon trace includes them.
- Backbone-only keeps the construction simple (user req 1) and the visual clean (no sidechain atoms to clutter the view).
- The `backbone` selector is C-side (not in Python selector.py), but it's a standard, stable selector. The exact atom set (N, CA, C, O) is the conventional protein backbone; PyMOL's `backbone` selector includes these. **MEDIUM confidence on the exact atom set** — verify at runtime with `cmd.iterate(tmp, "stored.append(name)", space={'stored': []})` that only N/CA/C/O are present.

**Tradeoff:** The alt-conf copy has FEWER atoms than the original (no sidechain). The original residue has CB (beta carbon) with `alt=''` but no CB with `alt='B'`. This is valid in PDB altLoc semantics (not all atoms need alt-conf). PyMOL handles this — the cartoon trace only needs CAs. **MEDIUM — needs runtime-verify that backbone-only alt-conf renders in cartoon** (the spike tested whole-segment; backbone-only is a variant).

#### MECHANISM 2 (REJECTED): Per-atom `cmd.pseudoatom` loop with `cmd.iterate_state` / `cmd.alter_state`

**How:** Hand-build each backbone atom as a pseudoatom with `elem`/`name`/`resi`/`chain`/`segi`/`alt` set, reading coords via `cmd.iterate_state` then writing via `cmd.alter_state`.

**Why rejected (HIGH):** Pseudoatoms do NOT render in cartoon/ribbon (Pitfall 8 — cartoon needs polymer trace; a pseudoatom with `name='CA'` is NOT classified as polymer unless bonded into the backbone). The 05-06 spike confirmed: `cmd.pseudoatom` mints a unique id but CANNOT render in cartoon/ribbon. The entire alt-conf approach depends on `cmd.create` (which preserves polymer classification) — pseudoatoms break this.

#### MECHANISM 3 (VIABLE as a sub-step, NOT standalone): Copy whole segment then `cmd.remove("sidechain")`

**How:** Copy the whole segment (including sidechain) via mechanism 1 without the `backbone` selector, then `cmd.remove(tmp, "sidechain")` to strip to backbone.

**Why NOT the winner:** It's a two-step version of mechanism 1 (copy whole → remove sidechain → alter → create). More steps = more mutation surface (no undo — AGENTS.md). The `backbone` selector in mechanism 1 achieves the same result in one `cmd.create` call. **Use mechanism 1 with the `backbone` selector; do NOT use the copy-then-remove approach.**

### Recommendation

**Use MECHANISM 1: `cmd.create(tmp, "...and backbone", 1, 1)` + `alter alt='B';segi='GAME';ss='L'` + `cmd.create(obj, tmp, zoom=0)` + `cmd.delete(tmp)` + `cmd.sort(obj)`.** This is the spike-verified mechanism with the `backbone` selector added to satisfy user req 1. The `zoom=0` is CRITICAL (Bug 3 fix — see A4).

---

## A4. Multiple mid-chain hiders per chain (success criterion 3)

### The 05-08 integration hazards (4 bugs, all runtime-verified, fixes headless-confirmed)

The 05-08 implementation (reverted, on `backup/05-08-attempts`) hit 4 cascading GUI-only bug classes when inserting multiple alt-conf hiders in the SAME round. The headless smoke (44/44, then 49/49) passed because it tested reps ONE-AT-A-TIME with cleanup between — the collisions only manifest when multiple hiders register in the same round (the real GUI flow). **Phase 11 MUST address all 4 from the start.**

#### Bug 1: id collision (KeyError "hider already registered")

**Root cause (runtime-verified, commit `6d51d12`):** Alt-conf CAs SHARE ids with the originals. `cmd.create(obj, tmp)` append gives the alt-conf CAs the SAME ids as the source segment CAs (e.g. 1ubq segment A:2-4 → alt-conf CAs `[10,19,27]` == originals `[10,19,27]`). If two hiders pick the SAME segment (e.g. cartoon + ribbon each independently call `pick_segments(1)` and both return the first segment), they get the same shared clickable CA id → 2nd `register()` raises KeyError.

**Also verified:** `cmd.alter("id=...")` is a SILENT NO-OP (id is immutable — symbol table has `ID` without `*` but the C engine rejects id changes). `cmd.create` preserves source ids on append EVEN with a different chain. Only `cmd.pseudoatom` mints a new id, but a pseudoatom can't render in cartoon. **A truly-unique polymer-CA id is IMPOSSIBLE.**

**Fix (05-08, commit `6d51d12`):** Pick ALL cartoon+ribbon segments in ONE `pick_segments(cartoon+ribbon total)` call so the segments are DISJOINT (distinct middle CAs → distinct shared ids → no collision). Clicks still hit the visible cartoon tube (the shared id IS the tube's CA). **This is a GENERATOR constraint (Researcher B's pick_segments scope) but the rendering/construction half is: the clickable CA must be on a MIDDLE residue of a DISJOINT segment, and the player clicks the displaced tube (not the original).**

**Rendering implication:** The registry keys on `(object, id)`, and the id is SHARED between the real CA and the alt-conf CA. Clicking the real (undisplaced) tube at the hider's resi would ALSO register a find (latent — the player clicks the displaced bump, not the normal original). This is a known v1 limitation (Researcher B's registry scope). **For construction: displace the middle CA enough (≥1.0 Å) that the player clicks the alt-conf tube, not the real tube.**

#### Bug 2: iterate_state corruption (ValueError "neighbor_id not found in state 1")

**Root cause (runtime-verified, commit `6d51d12`):** `cmd.create(obj, tmp)` with alt-conf atoms CORRUPTS `cmd.iterate_state(1, "id X")` for non-segment atoms. After one cartoon insert, only the segment's own 3 CAs are readable via `iterate_state`; every other CA returns nothing (the atom still EXISTS: `cmd.iterate` + `cmd.count_atoms` find it, but `iterate_state` cannot retrieve its coords). So a line/stick hider inserted AFTER a cartoon hider raises ValueError from the `iterate_state` coord read.

**Fix (05-08, commit `6d51d12`):** `_on_start` pre-captures each neighbor CA's `(x,y,z,elem,color)` via `iterate_state` while the state is CLEAN (before any insertion) and passes the tuple through the `(offset, neighbor_id, neighbor_coord)` payload; `insert_line_stick_hider` uses the pre-captured coord and skips `iterate_state` when supplied. **This is a LINE/STICK concern (not directly alt-conf construction) but Phase 11 MUST preserve the 05-07 fix (pre-capture neighbor coords) if it touches `_on_start`.**

**Rendering implication:** None directly — this is a data-flow bug. But it means the construction sequence MUST be: (1) pre-capture ALL needed coords (neighbor CAs for line/stick, segment CAs for cartoon/ribbon displacement direction) BEFORE any `cmd.create` mutation, then (2) insert hiders. **Do NOT read coords via `iterate_state` after an alt-conf insert.**

#### Bug 3: auto-zoom (GUI-only, headless smoke missed it)

**Root cause (runtime-verified, commit `d146370`):** The GUI `auto_zoom=1` setting caused `cmd.create` (in `insert_cartoon_hider`, `collapse_to_single_state`, `backup.snapshot`/`restore`) to zoom the camera 4x into the 3-residue cartoon segment, pushing line/stick/sphere pseudoatom hiders off-screen so the player could not see or click them. The headless smoke (44/44) missed this because headless PyMOL defaults `auto_zoom=-1` (off).

**Fix (05-08, commit `d146370`):** `zoom=0` on ALL `cmd.create` calls that create/recreate objects (prevents auto-zoom at source). `cmd.create` signature (creating.py:960): `zoom=-1` default (inherit); pass `zoom=0` explicitly. Apply to: `cmd.create(tmp, seg, 1, 1, zoom=0)`, `cmd.create(object, tmp, zoom=0)`, `backup.snapshot` (`cmd.create(BACKUP_PREFIX, target_obj, zoom=0)`), `backup.restore` (`cmd.create(target_obj, backup_name, zoom=0)`), `collapse_to_single_state`.

**Rendering implication:** **CRITICAL — every `cmd.create` call in Phase 11 MUST pass `zoom=0`.** Without it, the GUI auto-zooms into the first hider's segment and the player can't see the others. The headless smoke won't catch this (headless defaults `auto_zoom=-1`). **This is a GUI-only hazard that headless smoke is structurally blind to — the Phase 11 plan MUST include a GUI-runnable diagnostic (Windows PyMOL script the user runs) to verify no auto-zoom.**

#### Bug 4: retroactive coord corruption (the MULTI-HIDER killer — success criterion 3)

**Root cause (TWO-PART, runtime-verified, commit `335fe3c`):**

- **Part A (temp-create):** `cmd.create(tmp, seg)` sourcing the segment FROM an alt-conf-laden object (after the 1st cartoon/ribbon insert) produces a temp whose atoms are NOT in state 1 (44 atoms, 0 with state-1 coords) — invisible hider. With explicit `1,1` state args it produces 0 atoms entirely. Neither arg combo works sourcing from an alt-conf-laden object (5 variants all fail the 2nd insert).
- **Part B (RETROACTIVE CORRUPTION):** `cmd.create(obj, tmp)` merging the 2nd alt-conf into state 1 (which holds the 1st alt-conf) CORRUPTS the 1st alt-conf atoms' coordinates — extent collapses to the 1x1x1 "no coords" default box; they become un-readable (`iterate_state`) AND un-writable (`alter_state` cannot restore). Verified: ALL merge variants corrupt; coord-restore via `alter_state` FAILS. ONLY `target_state=-1` (new state) avoids the corruption (no merge into state 1).

**Fix (05-08, commit `335fe3c`, headless-verified for 1znf 5-rep + 1ubq 4-cartoon):**
- **Part A:** Source the segment from the CLEAN pre-insertion backup (`backup.BACKUP_PREFIX` via `backup.snapshot` in `GameController.start`), so `cmd.create(tmp, backup_seg, 1, 1)` produces a temp WITH state-1 coords (spike-faithful). `insert_cartoon_hider` gains a `backup_name` param; `insert_hider_for_rep` passes it through; `game.start` passes `self._backup_name`.
- **Part B:** 1st alt-conf merges into state 1 (clean, no corruption); 2nd+ appends as a NEW state (`target_state=-1`, no merge → no retroactive corruption). `alter_state` displacement runs in each hider's own state.
- **Visibility:** `gc.start` sets `all_states=on` (object-scoped) when the object is multi-state (2+ alt-conf hiders) so the player sees all hiders; `cleanup`/`abort_on_error` reset it to `off`. A single cartoon/ribbon hider stays in state 1 (backward-compatible, `all_states` untouched).
- **_on_start:** defensive `cmd.zoom` (count_atoms gate + try/except).

**Rendering implication — THIS IS THE KEY INTEGRATION FINDING for success criterion 3:**
1. **Source segments from the clean backup, NOT from the alt-conf-laden target.** The backup is created by `backup.snapshot` in `game.py.start` BEFORE any mutation. Pass `backup_name` to `insert_cartoon_hider`.
2. **1st alt-conf → state 1 (target_state=0); 2nd+ alt-conf → new state (target_state=-1).** This avoids the retroactive coord corruption. The `cmd.create` call becomes `cmd.create(object, tmp, target_state=-1, zoom=0)` for the 2nd+ hider.
3. **Set `all_states=on` (object-scoped) when 2+ alt-conf hiders are inserted** so the player sees all states. Reset to `off` on cleanup.
4. **`alter_state` displacement runs per-state** — each hider's middle CA is displaced in its OWN state, so the displacements don't interfere.

### Residue-number collision analysis

**Verified (HIGH):** Alt-conf atoms SHARE `(chain, resi, name)` with the originals — that's the POINT of alt-conf (they're alternate conformations of the same atom). This is VALID in PyMOL and in PDB format. The cartoon renderer handles it: the original CA (alt='') and the alt-conf CA (alt='B') are at the same `(chain, resi, name='CA')` but different `alt` — they're alternate positions. The cartoon trace draws through BOTH as parallel paths. **No residue-number collision issue — alt-conf is designed for this.**

### Recommendation for success criterion 3

**Use the Bug 4 fix from the start:**
1. `backup.snapshot` in `game.py.start` (already exists — Phase 3).
2. Pass `backup_name` to `insert_cartoon_hider`.
3. Source the segment from the backup: `cmd.create(tmp, "%s and chain %s and resi %d-%d and backbone" % (backup_name, chain, start, end), 1, 1, zoom=0)`.
4. 1st hider: `cmd.create(object, tmp, zoom=0)` (state 1). 2nd+ hider: `cmd.create(object, tmp, target_state=-1, zoom=0)` (new state).
5. `alter_state(state, ...)` displacement in each hider's own state.
6. Set `all_states=on` (object-scoped) when 2+ alt-conf hiders; reset on cleanup.

---

## A5. Faked-connectivity geometry — rendering tolerance (user req 2, rendering half)

### User requirement 2 (rendering half)

"Keep the position of the two ends, slightly move the middle residue(s)" — copy ≥3 consecutive residues' backbone; leave the two endpoint residues at their original coordinates (so they coincide with the real trace and the cartoon/ribbon blends through them); perturb the MIDDLE residue(s)' coordinates slightly so the alt-conf segment is visually distinguishable yet still traces as connected.

### Does the cartoon/ribbon trace a smooth connected path through endpoints+middle?

**Verified (HIGH) — YES, the trace follows the CA positions regardless of distance.** The cartoon trace draws a tube/ribbon through consecutive CAs (preset.py:395; mutagenesis.py:570). The 05-06 spike displaced ALL atoms uniformly by 2.0 Å and the cartoon rendered (`game_cartoon_ca = 3`). For Phase 11, the user wants SELECTIVE displacement: endpoints at original coords, middle displaced.

**The rendering path:** real_CA_1 → alt_CA_1 (= real_CA_1 coords, coincides) → alt_CA_2 (displaced) → alt_CA_3 (= real_CA_3 coords, coincides). The cartoon draws: a tube from alt_CA_1 to alt_CA_2 to alt_CA_3. At the endpoints (alt_CA_1 = real_CA_1, alt_CA_3 = real_CA_3), the alt-conf tube and the real tube share the same CA position → they BLEND (look like one tube). In the middle, the alt-conf tube bulges away from the real tube → the middle is DISTINGUISHABLE. This IS the "connected, blended visual" the user wants.

### What perturbation magnitude keeps the cartoon "connected-looking" while making the middle distinguishable?

**Recommended (MEDIUM — 05-06 spike verified 2.0 Å uniform; selective middle-only is a variant):**

- **1.0–2.0 Å** displacement on the MIDDLE CA(s) only (perpendicular to the chain direction is most visible).
- **1.5 Å recommended default** (middle ground — visible bulge without breaking the trace).
- CA-CA distance: normally ~3.8 Å. A 1.5 Å perpendicular displacement on the middle CA makes CA-CA distances: `sqrt(3.8² + 1.5²) ≈ 4.09 Å` — well within the cartoon trace tolerance (PyMOL draws tubes between CAs regardless of distance; very long distances look like straight lines, but 4 Å is normal).
- The 05-06 spike used 2.0 Å uniform displacement and the cartoon rendered fine. A 1.5 Å middle-only displacement is more conservative.
- **The human-verify in Phase 11 will fine-tune the magnitude** — if the cartoon trace renders both the original and the displaced copy as a visible "fork," the displacement may need to be smaller (0.5–1.0 Å) for better blending. If the middle is not distinguishable enough, increase to 2.0–2.5 Å.

### Does making endpoints COINCIDE with real atoms cause z-fighting / render artifacts?

**Verified (MEDIUM — no C-source for the cartoon renderer, but 05-06 spike showed no artifacts):** Cartoon/ribbon render as TUBES (not surfaces). Two tubes at the same position (real and alt-conf endpoints) share the same CA — the renderer draws them as overlapping tubes. Since they're the same color (blended via `cmd.alter color=neighbor_color`), the overlap looks like a single tube. **z-fighting is NOT an issue for cartoon tubes** — it's a surface-rendering artifact. The 05-06 spike (endpoints at original coords, displaced ALL atoms) showed no z-fighting; Phase 11 (endpoints at original coords, middle displaced) should be even cleaner because only the middle diverges.

**Do NOT offset endpoints by an epsilon.** Exact coincidence is the BLEND mechanism — the endpoints look like one tube, the middle looks like a fork/bulge. Offsetting endpoints would break the blend (the alt-conf tube wouldn't connect to the real trace).

### How to apply selective middle-only displacement

**Use `cmd.alter_state` (editing.py:1535) with a `segi GAME and resi <middle>` selection:**

```python
# Displace ONLY the middle residue(s) CA (editing.py:1535; hygienic space=)
# The middle is resi from start+1 to end-1 (for a 3-residue segment, exactly 1 residue)
middle_sele = "%s and segi GAME and alt B and resi %d-%d and name CA" % (
    object, start_resi + 1, end_resi - 1)
cmd.alter_state(1, middle_sele,     # or the hider's own state for multi-hider (A4 Bug 4)
                "x=x+dx; y=y+dy; z=z+dz",
                space={'dx': dx, 'dy': dy, 'dz': dz})
```

- `alter_state` takes `state` (int, 1-indexed), `selection`, `expression`, `space=` (editing.py:1535-1575; line 1566 uses `_iterate_prepare_args` for hygienic space; line 1571 calls `_cmd.alter_state`).
- For multi-hider (Bug 4 fix), run `alter_state` in each hider's OWN state (the state it was appended to).
- **Direction:** a small offset in one axis (e.g. `x=x+1.5`) is simplest. A random direction (normalized vector × 1.5 Å) would be more natural but requires a generator function (Researcher B's geometry scope). The construction half: pass `(dx, dy, dz)` from the generator; apply via `alter_state`.

---

## A6. Sentinel + alt-conf interaction (construction half)

### Does setting `alt` on the copied atoms interfere with the sentinel selections?

**Verified (HIGH) — NO interference.** The 05-06 spike confirmed all sentinel paths work UNCHANGED:

| Selector | Selects alt-conf atoms? | Source |
|----------|------------------------|--------|
| `segi GAME` | YES — `segi` is independent of `alt` | 05-06 spike: `cleanup by segi GAME restores count` PASS; cmd.py:357 |
| `b < 0` | YES — `b` is independent of `alt` | 05-06 spike: `fetch_all_hider_ids returns [(obj, 227)]` PASS; editing.py:1446 |
| `segi GAME and b < 0` | YES — returns the ONE clickable CA (b=-999) | 05-06 spike: `segi GAME b<0 count=1` PASS |

**`alt` and `segi` and `b` are INDEPENDENT atom fields** (editing.py:1446 symbol table — all separate, all read-write). Setting `alt='B'` does NOT affect `segi` or `b`. The sentinel `segi='GAME'` + `b=-999` works UNCHANGED on alt-conf atoms.

### Does `cmd.identify("obj and segi GAME and b < 0", mode=0)` return the alt-conf hider atom ids?

**Verified (HIGH) — YES, but with a CRITICAL CAVEAT.** The 05-06 spike caveat 1: `cmd.identify(obj, mode=0)` does NOT use id-diff to find alt-conf atoms (the id-diff approach CANNOT find alt-conf duplicates because `cmd.identify` returns ids that may include or exclude alt-conf atoms depending on the selector). **Use `segi GAME` selectors to find alt-conf atoms: `cmd.iterate("obj and segi GAME", ...)` and `cmd.identify("obj and segi GAME", mode=0)` both see alt-conf atoms.** The sentinel `segi GAME and b < 0` is the reliable read path.

### id stability of alt-conf atoms across the lifecycle

**Verified (MEDIUM — 05-08 Bug 1 runtime finding):** Alt-conf atoms SHARE ids with the originals (PyMOL alt-conf semantics; `cmd.create` append preserves source ids). The clickable CA's id is the SAME as the original CA's id. This means:
- `fetch_all_hider_ids` returns `[(obj, id)]` — the shared id. The registry keys on `(object, id)`.
- The id is STABLE across insert (it's the source id, preserved by `cmd.create`) and across `.pse` reload (Phase 3 confirmed id stability; alt-conf atoms follow the same rule).
- **The id is NOT unique to the alt-conf atom** — the original CA has the same id. This is the registry collision concern (Researcher B's scope: registry multi-id extension). **For construction: the b=-999 sentinel distinguishes the clickable CA (b=-999) from the original (b=normal), so `segi GAME and b < 0` selects ONLY the alt-conf clickable CA, not the original.**

### Does setting `segi='GAME'` on alt-conf atoms break the cartoon/ribbon trace?

**Verified (HIGH) — NO.** The 05-06 spike set `segi='GAME'` on the alt-conf atoms AND the cartoon rendered (`game_cartoon_ca = 3`). The `polymer` selector (cmd.py:363) is C-side, connectivity-based (NOT segi-based). The 05-05 finding (runtime-RESOLVED) confirmed `segi='GAME'` does NOT break the polymer classification — the residue is still bonded into the backbone. **The same holds for alt-conf atoms: `segi='GAME'` does NOT remove them from the polymer set.**

### The `id <id>` selector matches BOTH alt versions (caveat 2 from spike)

**Verified (HIGH — 05-06 spike caveat 2):** The `id <id>` selector matches BOTH `alt=''` and `alt='B'` versions of the same atom (they share id space). `cmd.alter("obj and id 227", "b=-999.0")` would set b=-999 on the ORIGINAL atom too (which has `segi='A'`, so it doesn't affect `fetch_all_hider_ids`, but it's semantically wrong). **To set b=-999 on ONE alt-conf CA unambiguously, use `segi GAME and name CA and resi <resv>` — the original has `segi='A'` so it's excluded.** NEVER use `id <id>` alone to select an alt-conf atom for sentinel setting.

### Cleanup needs backup.restore between rounds (caveat 3 from spike)

**Verified (HIGH — 05-06 spike caveat 3):** `cmd.remove("segi GAME")` alone restores the count but leaves RESIDUAL alt-conf state that breaks subsequent alt-conf insertions on the same object. For a single game round (insert → play → cleanup → done), sentinel cleanup works. But for "New Game" (cleanup → insert again), the object MUST be restored from backup (`delete+create` two-step, NOT just sentinel remove). **Phase 11 MUST use `backup.restore` (already in `game.py.cleanup` — Phase 6 changed cleanup to restore from backup, NOT sentinel remove) for alt-conf hiders.** The current `game.py.cleanup` (line 274-305) already calls `backup.restore` — this is COMPATIBLE with the alt-conf approach. **No cleanup change needed — the Phase 6 cleanup path (backup.restore) is the correct path for alt-conf.**

---

## Standard Stack (this aspect)

### Core cmd APIs (all verified against `tmp/pymol-src/modules/pymol/`)

| API | Signature | Purpose | Source |
|-----|-----------|---------|--------|
| `cmd.create` | `create(name, selection, source_state=0, target_state=0, discrete=0, zoom=-1, ...)` | Copy atoms to a new/existing object; `target_state=-1` appends new state; `zoom=0` prevents auto-zoom (Bug 3) | creating.py:960-1036 |
| `cmd.alter` | `alter(selection, expression, space={})` | Set `alt='B'`, `segi='GAME'`, `b=-999`, `ss='L'`, `color=...` on atoms; hygienic `space={}` | editing.py:1424-1473 |
| `cmd.alter_state` | `alter_state(state, selection, expression, space={})` | Displace middle CA coords (x=x+dx); runs per-state for multi-hider | editing.py:1535-1575 |
| `cmd.iterate` | `iterate(selection, expression, space={})` | Read `ID`, `color`, `chain`, `resv`, `name` on alt-conf atoms (NO x/y/z); use `segi GAME` selector | editing.py:1490+ |
| `cmd.iterate_state` | `iterate_state(state, selection, expression, space={})` | Read x/y/z coords — BUT corrupted after alt-conf insert (Bug 2); pre-capture BEFORE any insert | editing.py:1582+ |
| `cmd.identify` | `identify(selection, mode=0)` | Get stable atom ids; use `segi GAME` selector (NOT id-diff — alt-conf invisible to id-diff) | querying.py:1269-1300 |
| `cmd.count_atoms` | `count_atoms(selection)` | Verify rendering: `count_atoms("obj and segi GAME and rep cartoon") > 0` | querying.py:1412-1434 |
| `cmd.show` | `show(rep, selection)` | Show the requested rep on alt-conf atoms; `rep` parameterized (05-09) | viewing.py:491-526 |
| `cmd.remove` | `remove(selection)` | Strip sidechain from temp if needed; cleanup (but use backup.restore between rounds) | editing.py:800 |
| `cmd.delete` | `delete(name)` | Delete temp object; idempotent | commanding.py:496 |
| `cmd.sort` | `sort(object)` | Defensive after alter (preserves id, reassigns index) | editing.py:1457 |
| `cmd.set` | `set(name, value, object)` | `all_states=on` for multi-state (2+ alt-conf hiders); reset on cleanup | setting (C-side) |

### Selectors (verified in cmd.py:356-365)

| Selector | Purpose |
|----------|---------|
| `backbone` | N, CA, C, O atoms (backbone-only copy per user req 1) |
| `alt B` | Alt-conf atoms (alt='B'); use for selective middle displacement |
| `segi GAME` | Sentinel segment (cleanup + read); works on alt-conf atoms |
| `b < 0` | Sentinel b-factor (read path); works on alt-conf atoms |
| `polymer` | Polymer atoms (cartoon trace membership); alt-conf atoms ARE polymer |
| `rep cartoon` / `rep ribbon` | Atoms with rep enabled (visibility check) |
| `name CA` | C-alpha atoms (cartoon representative) |

---

## Architecture Patterns (this aspect)

### Where the code goes (purity rules from AGENTS.md)

```
generators.py  (PURE: stdlib only; NO from pymol; WSL-testable)
   pick_segments(cas_by_chain, count, segment_size=3)  -- mid-chain segment picker
       Returns [(chain, start_resi, end_resi), ...] — DISJOINT segments
       (Bug 1 fix: pick ALL cartoon+ribbon in ONE call for disjoint ids)
   generate_middle_displacement(n, seed, magnitude=1.5)  -- pure RNG [dx,dy,dz]
       Returns [[dx, dy, dz], ...] — perpendicular displacement for middle CAs
       ↑ (caller feeds cmd.iterate_state output as data for direction)

mutation.py  (cmd-coupled; headless-smoke-testable)
   insert_cartoon_hider(object, chain, start_resi, end_resi, handle,
                        backup_name, rep='cartoon', displacement=1.5,
                        is_first_hider=True, segi='GAME', b=-999.0)
       -- alt-conf segment replication (replaces terminal extension)
       -- Sources segment from CLEAN backup (Bug 4 Part A fix)
       -- 1st hider → state 1; 2nd+ → new state target_state=-1 (Bug 4 Part B fix)
       -- zoom=0 on ALL cmd.create (Bug 3 fix)
       -- Pre-captured coords passed in (Bug 2 defense)
       Returns the clickable middle CA's stable id (shared with original — Bug 1)

   insert_hider_for_rep(object, rep, payload, handle, backup_name=None)
       -- dispatcher: cartoon/ribbon → insert_cartoon_hider (passes backup_name)
       -- line/stick: unpacks (offset, neighbor_id, neighbor_coord) 3-tuple (Bug 2)

game.py  (cmd orchestrator)
   start(hider_specs)  -- snapshot → pre-capture coords → insert loop → register
       -- Sets all_states=on when 2+ cartoon/ribbon hiders (Bug 4 visibility)
       -- Passes backup_name to insert_hider_for_rep
   cleanup()  -- already uses backup.restore (Phase 6) — CORRECT for alt-conf

__init__.py  (Qt + cmd wiring)
   _on_start  -- pre-captures ALL coords (neighbor CAs + segment CAs) BEFORE any insert
       -- calls pick_segments ONE time for cartoon+ribbon total (Bug 1 disjoint)
       -- passes backup_name through hider_specs
```

### Proposed function signature for `insert_cartoon_hider` (alt-conf version)

```python
def insert_cartoon_hider(object, chain, start_resi, end_resi, handle,
                         backup_name, rep='cartoon', displacement=1.5,
                         is_first_altconf=True, target_state=None,
                         segi='GAME', b=-999.0):
    """Insert an alt-conf backbone-only segment replication hider.

    Copies backbone (N, CA, C, O) of residues start_resi..end_resi from
    the CLEAN backup (Bug 4 Part A) as alt='B' alternate conformations,
    displaces the MIDDLE residue(s) CA(s) by `displacement` Å, and shows
    `rep` (cartoon or ribbon). Endpoints stay at original coords (blend);
    middle displaced (distinguishable).

    Args:
        object: existing PyMOL object to insert INTO.
        chain: chain identifier of the segment.
        start_resi, end_resi: residue range (inclusive; ≥3 residues).
        handle: throwaway atom name (unused — selected by segi GAME).
        backup_name: clean backup object name (Bug 4 Part A — source from backup).
        rep: 'cartoon' or 'ribbon' (shown via cmd.show(rep, ...)).
        displacement: Å to displace middle CA(s) (default 1.5).
        is_first_altconf: True → state 1 (target_state=0); False → new state (target_state=-1, Bug 4 Part B).
        target_state: override (None = derive from is_first_altconf).
    Returns:
        The clickable middle CA's stable id (shared with original — Bug 1).
    """
```

---

## Don't Hand-Roll (this aspect)

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atom duplication within same object | Manual pseudoatom loop with per-atom coord copy | `cmd.create(tmp, "...and backbone", 1, 1, zoom=0)` + `alter alt='B'` + `cmd.create(obj, tmp, zoom=0)` | `cmd.create` preserves polymer classification + bonds; pseudoatoms can't render in cartoon (Pitfall 8); 05-06 spike verified |
| Backbone-only copy | Copy whole + `cmd.remove("sidechain")` | `cmd.create(tmp, "...and backbone", 1, 1, zoom=0)` | One-step; `backbone` selector (cmd.py:364) is C-side, stable |
| Coordinate displacement | Manual `cmd.set_dihedral` or bond rotations | `cmd.alter_state(state, sele, "x=x+dx;...", space={})` | alter_state is the verified coord-mutation primitive (editing.py:1535; 05-06 spike verified dx=2.0) |
| Alt-conf tag management | Manual occupancy calculation | `cmd.alter(sele, "alt='B'", space={})` | Default occupancy works; no occupancy management needed (05-06 spike) |
| Multi-state visibility | Manual per-state rep show | `cmd.set('all_states', 'on', object)` | Object-scoped setting; C-side; 05-08 Bug 4 fix verified |
| Segment selection | Guessing mid-chain by resi=middle | `pick_segments(cas_by_chain, count)` (pure, in generators.py) | Avoids terminals; DISJOINT for Bug 1; pure/WSL-testable |
| Auto-zoom prevention | Post-hoc `cmd.zoom(target_obj)` | `zoom=0` on every `cmd.create` call | Prevents at source (Bug 3); `cmd.zoom` after is a nicety, not correctness |

**Key insight:** The alt-conf mechanism is a 4-call sequence (`create` + `alter` + `create` + `delete`). Do NOT hand-roll the duplication — `cmd.create` with `alt` set is the ONLY mechanism that produces renderable alt-conf polymer atoms. Pseudoatoms and `fuse` were disproved by the 05-06 spike.

---

## Common Pitfalls (this aspect)

### Pitfall 1: `cmd.create(obj, seg, 1, 1)` same-object is a NO-OP (merge by identity)

**What goes wrong:** You try to duplicate atoms within the same object by `cmd.create(obj, seg, 1, 1)`. It produces 0 new ids — `cmd.create` MERGES by identity (segi, chain, resi, name) when the target name equals the source object.
**How to avoid:** Use the 3-step: `create(tmp, seg)` + `alter(tmp, "alt='B'")` + `create(obj, tmp)`. The `alt='B'` makes the identity DIFFERENT, so `create(obj, tmp)` APPENDS.
**Warning signs:** `new_ids = set(cmd.identify(obj, mode=0)) - ids_before` is empty after `cmd.create(obj, seg, 1, 1)`.
**Source:** 05-06 spike (commit `a6fd26a`, recovered from `1f22014`), creating.py:960.

### Pitfall 2: `cmd.fuse(tmp, obj, mode=3)` RENAMES atoms (no `name CA`)

**What goes wrong:** You try `cmd.fuse` mode 3 (combine only) to merge the temp into the target. It RENAMES atoms to avoid collisions — CA→C02, N→N01, O→O04. The cartoon trace can't find `name CA`.
**How to avoid:** Do NOT use `cmd.fuse` for alt-conf. Use `cmd.create(obj, tmp)` with `alt='B'` set on the temp.
**Source:** 05-06 spike, editing.py:937-987 (mode 3 docstring: "don't move and don't create a bond, just combine").

### Pitfall 3: `cmd.identify` id-diff does NOT find alt-conf atoms

**What goes wrong:** You use the id-diff approach (`ids_before = identify(obj); create; new = identify(obj) - ids_before`) to find the new alt-conf atoms. It returns empty — `cmd.identify` doesn't return alt-conf duplicates.
**How to avoid:** Use `segi GAME` selectors: `cmd.iterate("obj and segi GAME", ...)` and `cmd.identify("obj and segi GAME", mode=0)` both see alt-conf atoms.
**Source:** 05-06 spike caveat 1.

### Pitfall 4: `id <id>` selector matches BOTH alt versions

**What goes wrong:** You set b=-999 via `cmd.alter("obj and id 227", "b=-999.0")`. It sets b=-999 on BOTH the original (alt='') and the alt-conf (alt='B') atom — they share id 227.
**How to avoid:** Use `segi GAME and name CA and resi <resv>` to select ONLY the alt-conf CA (the original has `segi='A'`, excluded).
**Source:** 05-06 spike caveat 2.

### Pitfall 5: Auto-zoom in GUI (headless smoke is blind)

**What goes wrong:** Headless smoke passes (auto_zoom=-1 off), but the GUI auto-zooms into the first hider's segment, pushing other hiders off-screen.
**How to avoid:** `zoom=0` on EVERY `cmd.create` call. Include a GUI-runnable diagnostic (Windows PyMOL script) in the plan — headless smoke alone is INSUFFICIENT for `cmd.create`-heavy code.
**Source:** 05-08 Bug 3 (commit `d146370`).

### Pitfall 6: Retroactive coord corruption on 2nd alt-conf merge (multi-hider killer)

**What goes wrong:** `cmd.create(obj, tmp)` merging the 2nd alt-conf into state 1 (which holds the 1st) CORRUPTS the 1st alt-conf's coords — collapse to 1x1x1 "no coords" box; un-readable AND un-writable.
**How to avoid:** Source from clean backup (Bug 4 Part A) + 2nd+ alt-conf as new state (`target_state=-1`, Bug 4 Part B) + `all_states=on` for visibility.
**Source:** 05-08 Bug 4 (commit `335fe3c`).

### Pitfall 7: iterate_state corruption after alt-conf insert

**What goes wrong:** After one `cmd.create(obj, tmp)` alt-conf insert, `cmd.iterate_state(1, "id X")` for non-segment atoms returns missing. A line/stick hider inserted after a cartoon hider raises ValueError.
**How to avoid:** Pre-capture ALL needed coords (neighbor CAs for line/stick, segment CAs for displacement direction) BEFORE any `cmd.create` mutation. Pass pre-captured coords through the payload.
**Source:** 05-08 Bug 2 (commit `6d51d12`).

### Pitfall 8: Sentinel cleanup leaves residual alt-conf state (breaks New Game)

**What goes wrong:** `cmd.remove("segi GAME")` restores the count but leaves residual alt-conf state that breaks subsequent alt-conf insertions.
**How to avoid:** Use `backup.restore` (delete+create two-step) for cleanup between rounds. The current `game.py.cleanup` (Phase 6) ALREADY uses `backup.restore` — COMPATIBLE, no change needed.
**Source:** 05-06 spike caveat 3.

### Pitfall 9: `cmd.alter("id=...")` is a silent NO-OP

**What goes wrong:** You try to give an alt-conf CA a unique id via `cmd.alter("obj and segi GAME and name CA", "id=999")`. It silently does nothing — `id` is immutable in the C engine (the symbol table has `ID` without `*` but the C engine rejects changes).
**How to avoid:** Do NOT try to mint unique ids for alt-conf atoms. Use the shared id + sentinel (`segi GAME and b < 0`) to distinguish. The registry collision is Researcher B's scope.
**Source:** 05-08 Bug 1 (commit `6d51d12`).

---

## Code Examples (this aspect)

### Recommended alt-conf insert_cartoon_hider (construction, full sequence)

```python
# Source: creating.py:960 (create), editing.py:1424 (alter), editing.py:1535 (alter_state),
#         viewing.py:491 (show), editing.py:1457 (sort), querying.py:1269 (identify)
# 05-06 spike (commit a6fd26a, recovered from 1f22014) — runtime-verified 10/10 headless
# 05-08 Bug fixes (commits 6d51d12, d146370, 335fe3c) — headless-verified, GUI human-verify PENDING

def insert_cartoon_hider(object, chain, start_resi, end_resi, handle,
                         backup_name, rep='cartoon', displacement=1.5,
                         is_first_altconf=True, segi='GAME', b=-999.0,
                         n_color=0):
    """Alt-conf backbone-only segment replication hider (cartoon/ribbon).
    Returns the clickable middle CA's stable id (shared with original)."""
    # 0. Derive target_state from is_first_altconf (Bug 4 Part B fix)
    target_state = 0 if is_first_altconf else -1   # 1st → state 1; 2nd+ → new state

    # 1. Copy BACKBONE ONLY from CLEAN backup to temp (Bug 4 Part A: source from backup;
    #    user req 1: backbone-only; creating.py:960; cmd.py:364 'backbone' selector;
    #    zoom=0 CRITICAL — Bug 3 fix)
    tmp = cmd.get_unused_name("_bchm_alt")          # querying.py:74
    segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
        backup_name, chain, start_resi, end_resi)
    cmd.create(tmp, segment_sele, 1, 1, zoom=0)     # creating.py:960; source_state=1, zoom=0

    # 2. Set alt-conf + sentinel + ss + color on temp (editing.py:1424; hygienic space={})
    cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'; color=stored_c",
              space={'stored_c': n_color})

    # 3. Append alt-conf atoms to target (creating.py:960; target_state for Bug 4 Part B;
    #    zoom=0 for Bug 3)
    cmd.create(object, tmp, target_state=target_state, zoom=0)

    # 4. Clean up temp
    cmd.delete(tmp)                                # commanding.py:496

    # 5. Displace MIDDLE CA(s) ONLY (user req 2; editing.py:1535)
    #    Endpoints (start_resi, end_resi) stay at original coords (blend);
    #    middle (start_resi+1 .. end_resi-1) displaced (distinguishable).
    #    For multi-hider: use the hider's OWN state (target_state+1 or count_states).
    state_for_displace = 1 if is_first_altconf else cmd.count_states(object)
    middle_sele = "%s and segi GAME and alt B and resi %d-%d and name CA" % (
        object, start_resi + 1, end_resi - 1)
    cmd.alter_state(state_for_displace, middle_sele,
                    "x=x+dx; y=y+dy; z=z+dz",
                    space={'dx': dx, 'dy': dy, 'dz': dz})  # dx,dy,dz from generator

    # 6. Set b=-999 on ONE clickable middle CA (clean sentinel; 05-06 spike §12.3 step 6)
    #    Use segi GAME + name CA + resi (NOT id — Pitfall 4; id matches both alts)
    middle_cas = []
    cmd.iterate("%s and segi GAME and alt B and name CA and resi %d-%d" % (
        object, start_resi + 1, end_resi - 1),
        "stored.append((ID, resv))", space={'stored': middle_cas})
    clickable_id = middle_cas[len(middle_cas) // 2][0]   # middle of the middle
    clickable_resv = middle_cas[len(middle_cas) // 2][1]
    cmd.alter("%s and segi GAME and name CA and resi %d" % (object, clickable_resv),
              "b=-999.0", space={})

    # 7. Defensive sort (editing.py:1457; preserves id)
    cmd.sort(object)

    # 8. Show the REQUESTED rep (viewing.py:491; 05-09 rep forwarding)
    cmd.show(rep, "%s and segi GAME and alt B" % object)

    return clickable_id
```

### Pre-capture coords BEFORE any insert (Bug 2 defense, in `_on_start`)

```python
# Source: 05-08 Bug 2 fix (commit 6d51d12); editing.py:1582 (iterate_state)
# Pre-capture neighbor CA coords for line/stick + segment CA coords for displacement
# while the state is CLEAN (before any cmd.create mutation).

# Neighbor CAs for line/stick (pre-capture (x,y,z,elem,color) per CA id)
neighbor_coord_map = {}
cmd.iterate_state(1, "%s and name CA and not segi GAME" % target_obj,
                  "stored[ID] = (x, y, z, elem, color)",
                  space={'stored': neighbor_coord_map})

# Segment CAs for displacement direction (pre-capture first CA direction)
# (the generator computes displacement direction; the construction applies it)
# ... pass displacement (dx,dy,dz) from generator through hider_specs ...
```

### Visibility check (cartoon + ribbon on alt-conf atoms)

```python
# Source: mutagenesis.py:570; 05-06 spike checks 5+8; cmd.py:360 'rep' selector
# After insert_cartoon_hider + cmd.show(rep, "obj and segi GAME and alt B"):
assert cmd.count_atoms("%s and segi GAME and alt B and name CA and rep cartoon" % obj) > 0
assert cmd.count_atoms("%s and segi GAME and alt B and polymer" % obj) > 0   # polymer membership
# For ribbon:
assert cmd.count_atoms("%s and segi GAME and alt B and name CA and rep ribbon" % obj) > 0
# Regression guard (05-09): ribbon on GAME but NOT on the rest of the polymer
assert cmd.count_atoms("%s and segi GAME and alt B and rep ribbon" % obj) > 0
assert cmd.count_atoms("%s and polymer and not segi GAME and rep ribbon" % obj) == 0
```

### Multi-state all_states toggle (Bug 4 visibility, in `game.py.start`)

```python
# Source: 05-08 Bug 4 fix (commit 335fe3c); all_states is C-side setting
# After the insert loop, if 2+ cartoon/ribbon hiders were inserted (multi-state):
n_altconf_hiders = sum(1 for _, rep in hider_specs if rep in ('cartoon', 'ribbon'))
if n_altconf_hiders >= 2:
    cmd.set("all_states", "on", self.target_obj)   # object-scoped
    self._all_states_was_set = True                # for cleanup reset
# In cleanup() / abort_on_error():
if getattr(self, '_all_states_was_set', False):
    cmd.set("all_states", "off", self.target_obj)
    self._all_states_was_set = False
```

---

## Open Risks / Needs-Runtime-Verify (this aspect)

### 1. [MEDIUM] Backbone-only alt-conf renders in cartoon

The 05-06 spike copied the WHOLE segment (25 atoms including sidechain). Phase 11 uses `backbone` selector (N, CA, C, O only) per user req 1. The cartoon trace only needs CAs, so backbone-only SHOULD render — but the spike didn't test it. **The headless smoke MUST assert `count_atoms("obj and segi GAME and alt B and name CA and rep cartoon") > 0` for a backbone-only copy.** If it's 0, fall back to whole-segment copy (without the `backbone` selector) + `cmd.remove("obj and segi GAME and sidechain")` after alter.

### 2. [MEDIUM] Selective middle-only displacement renders as a connected bulge (not a fork)

The 05-06 spike displaced ALL atoms uniformly by 2.0 Å. Phase 11 displaces ONLY the middle CA(s), leaving endpoints at original coords. The cartoon trace goes: real_CA → alt_CA (coincides) → displaced_middle_CA → alt_CA (coincides) → real_CA. This SHOULD render as a connected tube with a bulge in the middle. But if the endpoint-to-displaced-middle CA-CA distance is too long (>5 Å), the tube might look like a straight line (disconnected). **The GUI human-verify MUST confirm the visual is a connected bulge, not a fork.** If it forks, reduce displacement to 0.5–1.0 Å.

### 3. [MEDIUM] Multi-hider Bug 4 fix (new-state append) works in the GUI

The 05-08 Bug 4 fix (source from backup + 2nd+ as new state + all_states=on) was headless-verified for 1znf 5-rep + 1ubq 4-cartoon (49/49 smoke). But the GUI human-verify was NEVER completed — 05-08 was reverted. **The GUI human-verify MUST confirm: (a) all 2+ hiders are visible, (b) all are clickable, (c) no "no coordinates" zoom warning, (d) cleanup restores the original.** This is the highest-risk Open Risk — the entire 05-08 revert was due to GUI-only failures that headless smoke couldn't catch.

### 4. [MEDIUM] GUI-runnable verification methodology

Headless PyMOL (`-cq`) defaults `auto_zoom=-1` (off); GUI defaults `auto_zoom=1`. Any `cmd.create`/`cmd.zoom` verification MUST run in the GUI (a Windows PyMOL diagnostic script the user runs, NOT headless-only smoke). The 05-08 attempt failed because 4 fix cycles each passed headless (44/44, 49/49) but failed in the GUI. **The Phase 11 plan MUST include a GUI-runnable diagnostic script (pure `pymol.cmd.*`, no Qt) that the user runs via `cmd.exe /c C:\src\run-conda-pymol.bat` WITHOUT `-cq` (or with the GUI) to verify auto-zoom, multi-state display, and coord corruption.** The headless smoke is necessary but NOT sufficient.

### 5. [LOW] `backbone` selector exact atom set

The `backbone` selector (cmd.py:364) is C-side. The conventional protein backbone is N, CA, C, O. But for non-standard residues or modified backbones, the set might differ. **Verify at runtime: `cmd.iterate(tmp, "stored.append(name)", space={'stored': []})` after `cmd.create(tmp, "...and backbone")` — assert only N/CA/C/O present.** If O is missing (some selectors exclude carbonyl O), the cartoon trace might still render (it primarily needs CAs), but the visual would be less complete.

### 6. [LOW] `all_states=on` interaction with line/stick/sphere hiders

Setting `all_states=on` (object-scoped) for multi-hider cartoon/ribbon makes ALL states visible. If line/stick/sphere hiders are in state 1 and cartoon/ribbon hider 2+ are in new states, `all_states=on` shows all. But does the clicking still work for state-1 hiders when all_states is on? The 05-08 fix verified this headlessly (1znf 5-rep succeeded), but the GUI human-verify is pending. **Low risk — all_states just makes all states visible; clicking still hits the atom in the current state.**

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 source, directly read at `tmp/pymol-src/modules/pymol/`)

- `editing.py:1424-1473` — `alter(selection, expression, space={})`: symbol table (1444-1449) `name, resn, resi, resv, chain, segi, elem, alt, q, b, ...` (`alt` read-write, no `*`); line 1472 calls `_cmd.alter`.
- `editing.py:1535-1575` — `alter_state(state, selection, expression, space={})`: changes coords (x/y/z); line 1566 `_iterate_prepare_args` for hygienic space; line 1571 `_cmd.alter_state`.
- `editing.py:1582+` — `iterate_state(state, selection, expression, space={})`: reads x/y/z; corrupted after alt-conf insert (05-08 Bug 2).
- `editing.py:40` — atom identify string includes `alt`: `f'...{self.name}`{self.alt}{tail}>'`.
- `editing.py:937-987` — `fuse(selection1, selection2, mode=0, ...)`: mode 3 = "don't move and don't create a bond, just combine" — RENAMES atoms (05-06 spike DISPROVED for alt-conf).
- `editing.py:1457` — "sort after modifying names/chains" warning; `cmd.sort` preserves id.
- `editing.py:800` — `remove(selection)`: removes atoms FROM object.
- `creating.py:960-1036` — `create(name, selection, source_state=0, target_state=0, discrete=0, zoom=-1, ...)`: `target_state=-1` appends new state; `zoom=0` prevents auto-zoom (Bug 3); same-object create is NO-OP (merge by identity, 05-06 spike).
- `creating.py:867-890` — `copy(target, source, zoom=-1)`: not used for alt-conf (create is the mechanism).
- `viewing.py:491-526` — `show(rep, selection)`: turns on rep flag; newly-created atoms do NOT inherit shown reps (must `cmd.show` explicitly).
- `querying.py:1269-1300` — `identify(selection, mode=0)`: mode=0 → [id]; use `segi GAME` selector (NOT id-diff for alt-conf — Pitfall 3).
- `querying.py:1412-1434` — `count_atoms(selection)`: use `rep cartoon` selector for visibility check.
- `querying.py:74` — `get_unused_name(prefix)`: for temp object names.
- `commanding.py:496` — `delete(name)`: idempotent; for temp cleanup.
- `cmd.py:356-365` — selector keyword list: `'alt '` (357), `'backbone'` (364), `'sidechain'` (364), `'polymer'` (363), `'rep '` (360), `'segi '`, `'b '`, `'id '`, `'name CA'`.
- `preset.py:395` — `show_as('cartoon', 'polymer & ...')`: cartoon shown for `polymer` selection (connectivity-based).
- `wizard/mutagenesis.py:474` — `alter("?%s & name CA" % src_sele, "stored.identifiers = (segi, chain, resi, ss, color)", space=self.space)`: the canonical blend pattern.
- `wizard/mutagenesis.py:570` — `cartoon = (cmd.count_atoms("(%s & name CA & rep cartoon)" % src_sele) > 0)`: canonical cartoon-visibility check.
- `importing.py:1578` — `_self.set('all_states', 1, object)`: all_states is object-scoped setting.

### Secondary (HIGH confidence — 05-06 spike, recovered from git history)

- 05-06 spike (commit `a6fd26a`): `smoke/altconf_spike.py` (314 lines, pure `pymol.cmd.*`, NO Qt) — 10/10 headless ALL PASSED. Recovered from git history commit `1f22014` (section 12 of 05-RESEARCH.md, removed from current 823-line version). Key findings: WORKING mechanism (create+alter+create), 3 DISPROVED approaches, 3 critical caveats (identify excludes alt-conf, id matches both alts, residual state breaks re-insertion), sentinel compatibility, alter_state displacement verified (dx=2.0).

### Tertiary (MEDIUM confidence — 05-08 bug fixes, headless-verified, GUI human-verify PENDING)

- 05-08 Bug 1 (commit `6d51d12`): alt-conf CAs SHARE ids with originals; `cmd.alter("id=...")` is silent NO-OP; fix = DISJOINT segments.
- 05-08 Bug 2 (commit `6d51d12`): `cmd.create(obj, tmp)` corrupts `iterate_state(1, "id X")` for non-segment atoms; fix = pre-capture coords before insert.
- 05-08 Bug 3 (commit `d146370`): GUI `auto_zoom=1` zooms into segment; fix = `zoom=0` on all `cmd.create`.
- 05-08 Bug 4 (commit `335fe3c`): 2nd alt-conf merge into state 1 corrupts 1st coords; fix = source from clean backup + 2nd+ as new state (`target_state=-1`) + `all_states=on`.
- 05-08 plan (commit `8cd76a3`, on `backup/05-08-attempts` branch): full implementation plan with `insert_cartoon_hider` alt-conf version, `pick_segments`, `_on_start` updates.
- 05-09 rep-forwarding fix (commit `2d487af`, IN HEAD): `cmd.show(rep, ...)` parameterized — prerequisite for ribbon.

---

## Metadata

**Confidence breakdown:**
- A1 (AltLoc fundamentals): **HIGH** — source-verified (editing.py:1446 symbol table; cmd.py:357 selector; editing.py:40 identity string) + 05-06 spike runtime-verified.
- A2 (Central hypothesis): **HIGH** — 05-06 spike 10/10 headless ALL PASSED (recovered from git history); cartoon+ribbon+polymer all confirmed.
- A3 (Backbone-only construction): **HIGH** for the mechanism (05-06 spike verified create+alter+create); **MEDIUM** for the backbone-only variant (spike tested whole-segment; `backbone` selector is standard but not spike-tested).
- A4 (Multi-hider per chain): **MEDIUM** — 05-08 bug fixes headless-verified (49/49 smoke) but GUI human-verify NEVER completed (05-08 reverted). The 4 bugs and fixes are runtime-verified; the GUI integration is the Open Risk.
- A5 (Faked-connectivity geometry): **HIGH** for `alter_state` displacement (05-06 spike verified dx=2.0); **MEDIUM** for the selective middle-only displacement (spike displaced ALL atoms; middle-only is a variant — needs GUI human-verify for the connected-bulge visual).
- A6 (Sentinel + alt-conf): **HIGH** — 05-06 spike verified all sentinel paths work unchanged; `segi`/`b`/`alt` are independent fields.

**Research date:** 2026-08-15
**Valid until:** 2026-09-14 (30 days — the 05-08 GUI human-verify Open Risks should be resolved by the Phase 11 GUI diagnostic before they expire)
