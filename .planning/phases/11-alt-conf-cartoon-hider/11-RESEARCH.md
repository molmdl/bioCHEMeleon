# Phase 11: Alt-conf Cartoon/Ribbon Hider (v1 Follow-up) — Research

**Researched:** 2026-08-15
**Synthesized from:** Aspect A (`11-RESEARCH-rendering.md`, 676 lines) + Aspect B (`11-RESEARCH-scoring-lifecycle.md`, 714 lines)
**Domain:** PyMOL 2.5.0 altLoc/alternate-conformation handling, cartoon+ribbon trace rendering, backbone-only segment construction, coordinate perturbation, atom-identification selectors, backup/restore/cleanup/persistence lifecycle
**Confidence:** HIGH for the central mechanism (runtime-verified via recovered 05-06 spike, 10/10 headless PASS). MEDIUM for multi-hider GUI integration (05-08 reverted — GUI human-verify never completed), backbone-only variant (spike tested whole-segment), and `.pse` `alt`-field survival (reasoned, not smoke-verified).

**Reconciled decisions (cross-researcher):**
- **Perturbation magnitude:** Aspect A recommended 1.0–2.0 Å (1.5 Å default); Aspect B recommended 1.0–1.5 Å. **Reconciled: 1.0–1.5 Å recommended (1.5 Å default); 2.0 Å is the spike-verified rendering-tolerance ceiling** for uniform displacement (the 05-06 spike displaced ALL atoms by 2.0 Å and rendered fine). For middle-only displacement (endpoints fixed), 1.5 Å is safer for the connected-bulge visual.
- **Perturbation scope:** Aspect A's code example displaced ONLY `name CA` of middle residues; Aspect B's Pitfall B-8 (mechanically correct) displaces ALL middle-residue atoms by the SAME offset (rigid translation) to preserve backbone geometry. **Reconciled: displace ALL middle-residue atoms (B's approach) — this is the spike-verified pattern** (the 05-06 spike used `alter_state(1, "obj and segi GAME", "x=x+2.0")` without `name CA`, displacing all GAME atoms). A's CA-only variant is untested and would distort the tube per B-8.
- **Cleanup path:** Both aspects independently concluded `backup.restore` (delete+create two-step, canonical since Phase 6, `game.py:274-305`) handles residual alt-conf state — **NO cleanup change needed for Phase 11.** `mutation.cleanup_hiders` (sentinel remove) stays a primitive, NOT wired into `game.cleanup`.
- **Registry extension:** Both converged on a minimal extension (NO multi-id index, NO sentinel migration). Aspect B's 3-field + 1-method shape is the recommendation; Aspect A's construction half depends on it (the shared-id collision is the registry's problem to solve at pick time, not at construction time).

---

## 1. Executive Summary

Phase 11 replaces the Phase 5 terminal-extension cartoon hider (which renders DISCONNECTED on 1ubq) with a connected, blended visual built from **PyMOL alternate conformations (altLoc)**. The central mechanism — recovered from the reverted 05-06 spike (commit `a6fd26a` / git-history `1f22014`) and runtime-verified 10/10 headless — is a 4-call sequence: copy a ≥3-residue mid-chain **backbone** segment to a temp (`cmd.create`), tag it `alt='B'; segi='GAME'; ss='L'` (`cmd.alter`), append it back as true alt-conf pairs (`cmd.create(obj, tmp)` — the `alt='B'` makes the identity differ from the `alt=''` originals so it appends, not merges), and delete the temp. The cartoon/ribbon trace draws a SECOND connected path through the alt-conf CAs (classified as `polymer`, `cmd.py:363`), blending at the endpoints (which coincide with the real trace) and bulging in the middle (which is displaced). This satisfies **user requirement 1** (backbone-only via the `backbone` selector, `cmd.py:364`) and **user requirement 2** (endpoints fixed, middle moved via `cmd.alter_state` on all middle-residue atoms, `editing.py:1535`) and **success criteria 1 & 2** (connected cartoon + ribbon renders).

The 05-08 attempt (commits `6d51d12`, `d146370`, `335fe3c`) then hit FOUR cascading GUI-only bugs that each passed headless verification but failed in the GUI — and was REVERTED. All four are now diagnosed with headless-verified fixes: (1) **id collision** (alt-conf atoms SHARE ids with originals — `cmd.alter("id=...")` is a silent NO-OP) → pick ALL cartoon+ribbon segments DISJOINT in one `pick_segments` call; (2) **iterate_state corruption** after an alt-conf insert → pre-capture all needed coords BEFORE any `cmd.create` mutation; (3) **auto-zoom** (GUI `auto_zoom=1` zooms into the segment) → `zoom=0` on EVERY `cmd.create`; (4) **retroactive coord corruption** on the 2nd merge into state 1 → source the temp from the CLEAN backup + 2nd+ alt-conf as a NEW state (`target_state=-1`) + `all_states=on` for visibility. These fixes satisfy **success criterion 3** (multiple mid-chain hiders per chain), but the GUI human-verify was NEVER completed — this is the highest Open Risk.

The scoring problem is the load-bearing discovery for this phase: because alt-conf atoms share ids with their originals, and `cmd.identify("pk1", mode=1)` returns only `(model, id)` — NO `alt` (querying.py:1282-1283) — the registry CANNOT distinguish a clicked alt='B' hider from the alt='' original by id alone. The 05-08 approach accepted "clicking the original tube also scores" as a latent limitation. **Phase 11 user requirement 3 demands solving this.** The solution (Aspect B): modify `PickWizard.do_pick` to read `(model, ID, alt, resv)` from `pk1` via ONE `cmd.iterate` (editing.py:1490) before `cmd.unpick()`, pass `(aid, alt, resv)` to `on_pick`, extend `HiderRecord` with `is_altconf` + `endpoint_resvs (rv1, rv2)` + `alt_tag` (default 'B'), and gate scoring on `alt == rec.alt_tag AND rv1 < resv < rv2` (strict middle). A NEW pure `get_altconf_by_resv(object, resv)` method handles non-anchor middle-atom clicks via a dual lookup. This satisfies **user requirement 3** (any middle atom scores; endpoints and real trace don't) and **success criterion 4** (mixed-rep game — all reps tracked, all clickable). The `.bcm` sidecar carries the 3 new fields as OPTIONAL v1 additions (NO version bump); `reconstruct_from_sentinels` defaults them, `reconcile_with_bcm` restores them.

---

## 2. The Central Hypothesis — VERIFIED

**Hypothesis:** Replicating a copied protein segment as PyMOL alternate conformations (altLoc) makes the cartoon/ribbon renderer draw a SECOND, CONNECTED trace through the copied backbone — replacing the disconnected terminal extension from Phase 5.

**VERIFIED (HIGH) — 05-06 spike (commit `a6fd26a`, recovered from git-history `1f22014`), 10/10 headless ALL PASSED on 1ubq:**

| Check | Result | Diag Value |
|-------|--------|------------|
| Cartoon renders alt-conf GAME CAs (default settings) | PASS | `game_cartoon_ca = 3` |
| Ribbon renders alt-conf GAME CAs | PASS | `game_ribbon_ca = 3` |
| Alt-conf GAME atoms in `polymer` | PASS | `game_polymer = 25` (all 25 alt-conf atoms are polymer — cartoon trace includes them) |
| `all_states` required for cartoon? | NO | `game_cartoon_ca_all = 3` with `all_states=off` (single hider) |
| `alter_state` displacement (x=x+2.0) | PASS | `dx=2.0000` — coords shifted exactly 2 Å |
| Cleanup by `segi GAME` restores count | PASS | `after_count=660, orig_count=660` |
| Sentinel: `fetch_all_hider_ids` returns 1 atom | PASS | `fetch_ids = [('1ubq', 227)]` |

**The WORKING mechanism (spike discovery):** `cmd.create(tmp, seg, 1, 1)` → `cmd.alter(tmp, "alt='B'; segi='GAME'", space={})` → `cmd.create(obj, tmp)` → `cmd.delete(tmp)`. The `alt='B'` tag makes the temp atoms' identity DIFFER from the `alt=''` originals (alt is part of the identity key), so `cmd.create(obj, tmp)` APPENDS them as TRUE alt-conf pairs (same chain/resv/name=CA, but alt='B').

**Two alternatives DISPROVED by the spike:**
1. **`cmd.create(obj, seg, 1, 1)` (same-object create) — NO-OP.** `cmd.create` MERGES by identity (segi, chain, resi, name) when the target name equals the source object. A subset selection overwrites itself → 0 new ids (creating.py:960 — the "create states in an existing object" path deduplicates by identity).
2. **`cmd.fuse(tmp, obj, mode=3)` — RENAMES atoms.** Mode 3 ("don't move and don't create a bond, just combine into single object", editing.py:937-987) renames atoms to avoid collisions (CA→C02/C03, N→N01, O→O04). The 25 fused atoms have NO `name CA`, so the cartoon trace cannot render them. NOT alt-conf pairs (different names).

**Does the cartoon trace require a contiguous N-C-CA backbone?** NO — it follows consecutive C-alpha atoms along `polymer` atoms (preset.py:395 `show_as('cartoon', 'polymer & ...')`; mutagenesis.py:570 `count_atoms("(%s & name CA & rep cartoon)" % src_sele) > 0`). A backbone-only copy (N, CA, C, O — no sidechain) WILL render because the CA trace is intact.

**Does `cmd.show('cartoon', selection)` on alt-conf atoms render? Ribbon?** YES for both — spike confirmed `game_cartoon_ca = 3` AND `game_ribbon_ca = 3`. The 05-09 rep-forwarding fix (commit `2d487af`, IN HEAD) parameterized `cmd.show(rep, ...)` — use `cmd.show(rep, "%s and segi GAME" % obj)` so the requested rep is shown, not hardcoded.

**Does the cartoon require `ss` flags?** The cartoon REP renders regardless of `ss` (which controls the cartoon TYPE — helix ribbon vs sheet arrow vs loop tube). The alt-conf copies INHERIT `ss` from the source segment via `cmd.create`. **Recommendation: set `ss='L'` (loop) on the alt-conf copies** via `cmd.alter` for a consistent smooth-tube visual (mirrors the 05-05 fix; avoids a sheet-arrow shape that looks "disconnected"). Optional — the cartoon renders either way.

---

## 3. Construction Approach

### 3a. Backbone-only via `backbone` selector (USER REQUIREMENT 1)

**User requirement 1 (verbatim):** "Only generate the BACKBONE of the copied residues, to be simple."

**Use the `backbone` selector (cmd.py:364 — N, CA, C, O) in the source `cmd.create`:**

```python
segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
    backup_name, chain, start_resi, end_resi)
cmd.create(tmp, segment_sele, 1, 1, zoom=0)   # source_state=1, zoom=0 (Bug 3 fix)
```

**Why this wins (HIGH confidence for the mechanism, MEDIUM for the backbone-only variant):** The 05-06 spike VERIFIED the exact mechanism with the WHOLE segment (not backbone-only) — 10/10 headless PASS. The `backbone` selector is a standard C-side selector. Adding it to the source selection copies only backbone atoms. The alt-conf copies inherit the polymer classification (they're copies of polymer backbone atoms), so the cartoon trace includes them. **MEDIUM — backbone-only needs runtime verify** (the spike tested whole-segment; Open Risk 1). **Fallback:** whole-segment copy + `cmd.remove("obj and segi GAME and sidechain")` after alter (Open Risk 1 mitigation). Verify the atom set at runtime: `cmd.iterate(tmp, "stored.append(name)", space={'stored': []})` — assert only N/CA/C/O present.

### 3b. The 4-call construction sequence (full, with Bug 4 fixes)

**The construction (replaces `mutation.insert_cartoon_hider`'s terminal-extension branch; sources from the CLEAN backup for multi-hider safety):**

```python
# 1. Copy BACKBONE ONLY from CLEAN backup to temp (Bug 4 Part A; user req 1; cmd.py:364)
tmp = cmd.get_unused_name("_bchm_alt")                       # querying.py:74
segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
    backup_name, chain, start_resi, end_resi)
cmd.create(tmp, segment_sele, 1, 1, zoom=0)                  # creating.py:960

# 2. Set alt-conf + sentinel + ss on TEMP (editing.py:1424; hygienic space={})
#    NO leakage: originals in obj are never in the alter's selection (B Pitfall B-4)
cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'", space={})

# 3. Append alt-conf atoms to target (creating.py:960; target_state for Bug 4 Part B; zoom=0 for Bug 3)
target_state = 0 if is_first_altconf else -1                  # 1st → state 1; 2nd+ → new state
cmd.create(object, tmp, target_state=target_state, zoom=0)

# 4. Clean up temp
cmd.delete(tmp)                                              # commanding.py:496

# 5. Defensive sort (editing.py:1457; preserves id, reassigns index)
cmd.sort(object)
```

### 3c. Multi-hider per chain (SUCCESS CRITERION 3) — the 05-08 hazards + fixes

The 05-08 attempt hit 4 cascading GUI-only bug classes when inserting multiple alt-conf hiders in the SAME round. Headless smoke (44/44, then 49/49) passed because it tested reps ONE-AT-A-TIME with cleanup between — the collisions only manifest when multiple hiders register in the same round (the real GUI flow). **Phase 11 MUST address all 4 from the start.**

#### Bug 1: id collision (KeyError "hider already registered")
**Root cause (commit `6d51d12`):** Alt-conf CAs SHARE ids with the originals (`cmd.create` preserves source ids; `cmd.alter("id=...")` is a silent NO-OP — the C engine rejects id changes). Two hiders picking the same segment → same shared id → 2nd `register()` raises KeyError.
**Fix:** Pick ALL cartoon+ribbon segments in ONE `pick_segments(cartoon+ribbon total)` call so the segments are DISJOINT (distinct middle CAs → distinct shared ids). **Hard constraint on the generator (Aspect B's `pick_segments` scope):** `pick_segments` MUST produce DISJOINT resv ranges — because `get_altconf_by_resv` assumes disjoint ranges (B Open Risk 6 / dependency).

#### Bug 2: iterate_state corruption (ValueError "neighbor_id not found in state 1")
**Root cause (commit `6d51d12`):** `cmd.create(obj, tmp)` with alt-conf atoms CORRUPTS `cmd.iterate_state(1, "id X")` for non-segment atoms. After one cartoon insert, only the segment's own CAs are readable via `iterate_state`; every other CA returns nothing (the atom still EXISTS: `cmd.iterate` + `cmd.count_atoms` find it, but `iterate_state` cannot retrieve its coords).
**Fix:** `_on_start` pre-captures each neighbor CA's `(x,y,z,elem,color)` via `iterate_state` while the state is CLEAN (before any insertion) and passes the tuple through the payload. `insert_line_stick_hider` uses the pre-captured coord and skips `iterate_state` when supplied. **Pre-capture ALL needed coords (neighbor CAs for line/stick + segment CAs for displacement direction) BEFORE any `cmd.create` mutation. Do NOT read coords via `iterate_state` after an alt-conf insert.**

#### Bug 3: auto-zoom (GUI-only, headless smoke missed it)
**Root cause (commit `d146370`):** GUI `auto_zoom=1` caused `cmd.create` to zoom the camera 4x into the 3-residue segment, pushing other hiders off-screen. Headless PyMOL defaults `auto_zoom=-1` (off) — headless smoke is STRUCTURALLY BLIND to this.
**Fix:** `zoom=0` on ALL `cmd.create` calls that create/recreate objects (creating.py:960 — `zoom=-1` default; pass `zoom=0` explicitly). Apply to: `cmd.create(tmp, seg, 1, 1, zoom=0)`, `cmd.create(object, tmp, zoom=0)`, `backup.snapshot` (`cmd.create(BACKUP_PREFIX, target_obj, zoom=0)`), `backup.restore` (`cmd.create(target_obj, backup_name, zoom=0)`).

#### Bug 4: retroactive coord corruption (THE MULTI-HIDER KILLER)
**Root cause (TWO-PART, commit `335fe3c`):**
- **Part A (temp-create):** `cmd.create(tmp, seg)` sourcing FROM an alt-conf-laden object (after the 1st insert) produces a temp with NO state-1 coords (invisible hider).
- **Part B (RETROACTIVE CORRUPTION):** `cmd.create(obj, tmp)` merging the 2nd alt-conf INTO state 1 (which holds the 1st) CORRUPTS the 1st alt-conf's coords — collapse to 1x1x1 "no coords" box; un-readable AND un-writable. ONLY `target_state=-1` (new state) avoids the corruption.

**Fix (headless-verified for 1znf 5-rep + 1ubq 4-cartoon, GUI human-verify PENDING — Open Risk 3):**
1. **Source segments from the CLEAN backup** (`backup.snapshot` from `game.start` BEFORE any mutation). `insert_altconf_cartoon_hider` receives a `backup_name` param; sources `cmd.create(tmp, "%s and ... and backbone" % backup_name, 1, 1, zoom=0)`.
2. **1st alt-conf → state 1 (`target_state=0`); 2nd+ alt-conf → new state (`target_state=-1`).**
3. **Set `all_states=on` (object-scoped) when 2+ cartoon/ribbon hiders** so the player sees all states. Reset to `off` on cleanup.
4. **`alter_state` displacement runs per-state** — each hider's middle atoms are displaced in their OWN state.

### 3d. Residue-number collision analysis
Alt-conf atoms SHARE `(chain, resi, name)` with the originals — that's the POINT of alt-conf (alternate conformations of the same atom). This is VALID in PyMOL and PDB format. The cartoon renderer handles it: original CA (alt='') and alt-conf CA (alt='B') are at the same `(chain, resi, name='CA')` but different `alt` — alternate positions, drawn as parallel paths. **No residue-number collision issue.**

---

## 4. Geometry — Faked Connectivity (USER REQUIREMENT 2)

**User requirement 2 (verbatim):** "≥3 residues: keep the two ends' positions, slightly move the middle residue(s)."

### 4a. The rendering path (CONNECTED bulge)
The cartoon draws a tube through consecutive CAs (preset.py:395; mutagenesis.py:570). With endpoints fixed and middle displaced, the path is: real_CA → alt_CA_1 (= real_CA_1 coords, coincides → BLEND) → alt_CA_2 (displaced → DISTINGUISHABLE) → alt_CA_3 (= real_CA_3 coords, coincides → BLEND) → real_CA. The alt-conf tube and real tube share the same CA at the endpoints → they look like one tube (blend); in the middle, the alt-conf tube bulges away → distinguishable. This IS the "connected, blended visual."

### 4b. Reconciled perturbation magnitude
**Recommended: 1.0–1.5 Å, default 1.5 Å; 2.0 Å is the spike-verified rendering-tolerance ceiling.**
- CA-CA distance: normally ~3.8 Å. A 1.5 Å perpendicular displacement on the middle makes CA-CA distances `sqrt(3.8² + 1.5²) ≈ 4.09 Å` — well within cartoon trace tolerance (PyMOL draws tubes between CAs regardless of distance; 4 Å is normal).
- The 05-06 spike used 2.0 Å uniform displacement and rendered fine. 1.5 Å middle-only is more conservative for the connected-bulge visual.
- The GUI human-verify (Open Risk 2) fine-tunes the magnitude — if the trace forks (not blends), reduce to 0.5–1.0 Å; if the middle is not distinguishable, increase to 2.0 Å (the ceiling).

### 4c. Reconciled perturbation scope — ALL middle-residue atoms (rigid translation)
**Displace ALL atoms of the MIDDLE residues (N, CA, C, O) by the SAME offset — a rigid translation** (Aspect B's Pitfall B-8; reconciled OVER Aspect A's CA-only code example). Displacing ONLY CA would leave N/C/O at original coords → broken backbone geometry → distorted tube. The 05-06 spike displaced ALL GAME atoms (the alter_state selection was `"obj and segi GAME"` without `name CA`) — so the all-atoms approach IS the spike-verified pattern. A's `name CA`-only selection was an untested variant; reject it per B-8.

### 4d. Direction: one random unit vector per hider (rigid)
A fixed-axis offset (`x=x+1.5`) is simplest and spike-verified, but introduces axis bias. **Recommendation: one random unit vector per hider** (from `generators.py`, seeded), scaled to 1.5 Å, applied to ALL middle atoms of that hider. This keeps the middle rigid (same offset for all middle atoms of one hider) AND avoids axis bias. Inject via `space={'dx': dx, 'dy': dy, 'dz': dz}`.

### 4e. The `alter_state` displacement (per-hider state)
Use `cmd.alter_state(state, selection, expression, space={...})` (editing.py:1535-1575). **State is 1-indexed** in the Python API (internally `int(state) - 1`, editing.py:1571). Expression syntax: `x = x + dx` (assignment, NOT `x += dx` — docstring uses `x=x+5`; `+=` not verified in the per-atom evaluator). Multi-axis in one call: `"x=x+dx; y=y+dy; z=z+dz"` (semicolon-joined).

**Selection — two robust approaches:**
1. **By `resi` range (simpler, works for numeric resis like 1ubq/1znf):**
   ```python
   middle_sele = "%s and segi GAME and alt B and resi %d-%d" % (
       object, start_resi + 1, end_resi - 1)   # strict middle; ALL atoms
   cmd.alter_state(hider_state, middle_sele,
                   "x=x+dx; y=y+dy; z=z+dz",
                   space={'dx': dx, 'dy': dy, 'dz': dz})
   ```
2. **By `id` list (robust for any resi encoding including insertion codes):** Collect middle atom ids via `cmd.iterate("obj and segi GAME", "stored.append((ID, resv))", space={...})` + Python filter `rv1 < resv < rv2`, then `cmd.alter_state(state, "obj and segi GAME and id a+b+c", "x=x+dx...", space={...})`. The `and segi GAME` restricts to the alt-conf copies (originals have segi A → excluded), so `id` (shared with originals) is unambiguous within the `segi GAME` intersection.

**Recommendation:** use the `resi`-range approach for the Phase 11 demos (numeric resis); use the `id`-list approach as the robust fallback for insertion-coded resis. **`resv` as a SELECTOR keyword is LOW confidence** (the standard is `resi`; not verified) — Open Risk 6. The `id`-list approach sidesteps this.

### 4f. Endpoints: do NOT offset (exact coincidence is the BLEND mechanism)
Cartoon/ribbon render as TUBES (not surfaces). Two tubes at the same position (real and alt-conf endpoints) share the same CA → overlapping tubes. Since they're the same color (blended via `cmd.alter color=...`), the overlap looks like one tube. **z-fighting is NOT an issue for cartoon tubes** — it's a surface-rendering artifact. The 05-06 spike showed no z-fighting. **Do NOT offset endpoints by an epsilon** — that would break the blend.

---

## 5. Scoring — Click Any Middle Atom (USER REQUIREMENT 3 — THE CENTRAL SCORING SOLUTION)

**User requirement 3 (verbatim):** "Scoring click should be of ANY atom clicked on the MIDDLE residues so the player isn't confused clicking a 'game'-labelled residue and getting missed."

### 5a. The shared-id problem (the load-bearing fact)
**Runtime-verified (05-06 spike §12.2 caveat 2 + 05-08 Bug 1 commit `6d51d12`):** Alt-conf atoms created via `cmd.create(obj, tmp)` SHARE atom `id`s with their originals. Root cause: `cmd.create` preserves source ids (Phase 3 Q2b); the temp was a copy of the originals; appended alt-conf atoms keep the originals' ids. Example: 1ubq segment A:2-4 → alt-conf CAs `[10,19,27]` == originals `[10,19,27]`.

**Consequence:** `PickWizard.do_pick` (wizard.py:43-54) reads the picked atom via `cmd.identify("pk1", mode=1)` → `[(model, id)]` (querying.py:1282-1283 — mode=1 returns `(object_name, id)` tuples, NO `alt`, NO `resv`). When the player clicks the displaced alt='B' middle CA, `identify` returns `(obj, shared_id)`. When the player clicks the alt='' ORIGINAL middle CA (the real trace), `identify` ALSO returns `(obj, shared_id)`. **The registry, keyed by `(object, id)`, cannot distinguish the two clicks.** The 05-08 approach accepted "clicking the original tube also scores" as a latent limitation. **Phase 11 req 3 explicitly rejects this.**

`cmd.alter("id=...")` is a SILENT NO-OP (id is immutable — the C engine rejects id changes; the symbol table has `ID` without `*` but the C engine rejects). `cmd.create` preserves source ids on append EVEN with a different chain. Only `cmd.pseudoatom` mints a new id, but a pseudoatom can't render in cartoon. **A truly-unique polymer-CA id is IMPOSSIBLE.**

### 5b. Three mechanisms — only ONE works under the shared-id constraint
1. **Register all middle-residue atom ids (brief's option 1) — FAILS.** Registering `(obj, middle_N_id)` means clicking the ORIGINAL middle N (alt='', real trace) → `identify` returns `middle_N_id` → registry hit → score. **False positive on the real trace.** Reject.
2. **A second sentinel/marker on middle atoms only (brief's option 2) — REDUNDANT.** A distinct `b` value (b=-888) would break `fetch_all_hider_ids` (`segi GAME and b < 0` would return ALL middle atoms + anchor → multiple records per hider → counts wrong). A `q` value works but is NOT recoverable from the sentinel after `.pse` reload → the .bcm must store the split anyway. AND the pick path still cannot tell alt='' from alt='B' by id alone — it MUST read `alt`. Reduces to "mechanism 3 + a redundant marker." Reject as redundant.
3. **Derive middle-ness at pick time from `alt` + `resv` vs the hider's endpoint resv range (RECOMMENDED).** Minimal, no sentinel migration, no multi-id index, robust to shared ids, round-trips via .bcm.

### 5c. The recommended mechanism
1. **`PickWizard.do_pick` reads `(model, ID, alt, resv)` from `pk1`** via ONE `cmd.iterate` (editing.py:1490) BEFORE `cmd.unpick()`. `pk1` is a one-atom named selection (the C layer sets it on click) → `iterate` returns exactly one row. Pass `(aid, alt, resv)` to `controller.on_pick`.
2. **`on_pick(aid, alt='', resv=None)` does a DUAL lookup + alt/resv gate:**
   ```python
   rec = self.registry.get(self.target_obj, aid)                  # anchor-id hit
   if rec is None and resv is not None:
       rec = self.registry.get_altconf_by_resv(self.target_obj, resv)  # non-anchor middle
   if rec is None:
       self._on_log("Miss!"); return
   if rec.is_altconf:
       if alt != rec.alt_tag or not (rec.endpoint_resvs[0] < resv < rec.endpoint_resvs[1]):
           self._on_log("Miss!"); return       # real trace (alt='') or endpoint (resv=rv1/rv2)
   self._mark_found(rec.id, rec)              # rec.id (anchor) NOT picked_id (B Pitfall B-6)
   ```
3. **`HiderRegistry.get_altconf_by_resv(object, resv)`** (NEW, pure): returns the first alt-conf record with `endpoint_resvs[0] < resv < endpoint_resvs[1]` (strict middle), or `None`. Correct because alt-conf hiders have DISJOINT resv ranges (`pick_segments` contract — hard dependency on the generator).

### 5d. Why this satisfies ALL THREE branches of req 3

| Click target | `alt` | `resv` | `registry.get(id)` | `get_altconf_by_resv` | `alt==tag?` | `rv1<resv<rv2?` | SCORE? |
|---|---|---|---|---|---|---|---|
| alt='B' middle CA/N/C/O (displaced hider, anchor residue) | 'B' | middle_rv | **hit** (anchor id) | — | YES | YES | **YES** ✓ |
| alt='B' middle atom (displaced hider, NON-anchor middle residue) | 'B' | middle_rv | None (id not registered) | **hit** (resv in range) | YES | YES | **YES** ✓ |
| alt='B' endpoint CA (hider endpoint, coincides with real trace) | 'B' | rv1 or rv2 | None | None (not strictly between) | — | — | **NO** ✓ |
| alt='' real middle CA (the real trace, NOT the hider) | '' | middle_rv | hit (anchor id shared) OR None | hit (resv in range) | **NO** (''≠'B') | — | **NO** ✓ |
| alt='' real endpoint CA | '' | rv1/rv2 | None | None | — | — | **NO** ✓ |
| sphere/line/stick pseudoatom (unique id, alt='') | '' | 9001 | **hit** (unique id) | — | `is_altconf=False` → skip check | — | **YES** ✓ |

**The anchor-id registration + the resv-range fallback together cover "click ANY atom on the MIDDLE residues"** (anchor residue atoms via id; non-anchor middle residue atoms via resv). The `alt == rec.alt_tag` check rejects the real trace (alt=''). The `rv1 < resv < rv2` strict check rejects endpoints. **All three branches of req 3 satisfied.**

### 5e. `alt_tag` choice + collision risk
Default `alt_tag='B'` (spike-verified on 1ubq/1znf, which have no pre-existing alt-confs). Store `alt_tag` in the registry record so `on_pick` checks `alt == rec.alt_tag` (not hardcoded 'B'). If a future structure has real `alt='B'` atoms, the `segi GAME` sentinel + `resv`-in-range check still disambiguate (real alt='B' has segi A; `get_altconf_by_resv` only matches registered ranges). Forward-compatible with zero added complexity. If needed, choose `alt='G'` (GAME) and the record carries it.

---

## 6. Registry Extension (MINIMAL — preserves ALL Phase 3/8 invariants)

**Confidence:** HIGH. Three new fields on `HiderRecord` + ONE new method on `HiderRegistry`. No multi-id index. No sentinel migration. `id`-keying intact.

### 6a. `HiderRecord` extension
```python
class HiderRecord(object):
    __slots__ = ('id', 'object', 'rep', 'status', 'pos',
                 'is_altconf',        # NEW: bool, default False (sphere/line/stick)
                 'endpoint_resvs',    # NEW: (rv1, rv2) tuple or None (alt-conf middle range)
                 'alt_tag')           # NEW: str, default '' (non-altconf) or 'B' (alt-conf)
    def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''):
        ...
        self.is_altconf = is_altconf
        self.endpoint_resvs = endpoint_resvs   # None or (int, int)
        self.alt_tag = alt_tag                 # '' for non-altconf; 'B' default for altconf
```

### 6b. `HiderRegistry` changes
- `register(object, id, rep, ..., is_altconf=False, endpoint_resvs=None, alt_tag='')` — passes new fields to `HiderRecord`. **Backward compatible (defaults).**
- `get(object, id)` — **UNCHANGED.** Still keyed by `(object, id)` (the anchor id for alt-conf).
- **NEW `get_altconf_by_resv(object, resv)`** — pure, no cmd. Returns the first alt-conf record with `endpoint_resvs is not None and endpoint_resvs[0] < resv < endpoint_resvs[1]`, or `None`. O(N) over records (N = hider count, small).
- `counts_by_rep` — **UNCHANGED.** One record per hider. A cartoon hider (with ~12 middle atoms) is ONE record → `counts_by_rep['cartoon'] += 1`, NOT +12. The middle-atom scoring is a pick-time derivation (`get_altconf_by_resv`), invisible to counts.
- `mark_found(object, id)` — **UNCHANGED** (sets status on the record at `(object, id)`). The CALLER passes `rec.id` (anchor), NOT `picked_id` (B Pitfall B-6 fix — one-line change in `game.py:on_pick`: `self._mark_found(picked_id)` → `self._mark_found(rec.id, rec)`).
- `remove(object, id)` — **UNCHANGED** (removes by anchor id).
- `to_dict` — add `is_altconf`, `endpoint_resvs` (as a list or None), `alt_tag` to each hider dict. Omit fields when default (keeps v1 sidecar compact for sphere/line/stick).
- `from_dict` — read with defaults (`is_altconf=False, endpoint_resvs=None, alt_tag=''` for non-altconf; `alt_tag='B'` if `is_altconf=True` and `alt_tag` absent). Tolerant of v1 sidecars without these fields (backward compat).
- `reconstruct_from_sentinels` — sets `is_altconf=False, endpoint_resvs=None, alt_tag=''` for every rebuilt record (the sentinel `segi GAME + b=-999` carries NO middle/endpoint/alt info — same limitation as `rep=None` per Phase 8 Open Risk 6). The .bcm reconciles (§8).
- `reconcile_with_bcm` — restore `is_altconf`, `endpoint_resvs`, `alt_tag` from the matching .bcm entry (alongside `rep`, `status`). Same merge shape as existing `rep`+`status` restore (registry.py:288-346). Validate `endpoint_resvs` is a 2-int tuple or None; `alt_tag` is a single char or ''; `is_altconf` is bool. On malformed .bcm entry → leave defaults (degraded but playable).

### 6c. Why NOT a multi-id index
A secondary `_id_index: {(object, any_clickable_id) → record}` would support "register all middle ids, look up any." But: (1) shared ids break it — clicking the original middle N (alt='') → `_id_index` hit → score (false positive); the index cannot mark "only alt='B' copy scorable" → STILL need the `alt` check. (2) `reconstruct` needs .bcm anyway — `fetch_all_hider_ids` (b=-999 on ONE anchor) returns one id per hider; rebuilding a multi-id index needs b=-999 on ALL middle atoms → multiple records per hider → counts wrong. (3) More state, more sync. **The resv-range + alt approach is strictly less state, degrades gracefully, and is robust to shared ids. Recommend it over the multi-id index.**

---

## 7. Cleanup & Backup/Restore (AGREEMENT — NO cleanup change needed)

**Confidence:** HIGH (both aspects independently converged; 05-06 spike caveat 3 + Phase 6 canonical path).

### 7a. `segi GAME` cleanup removes ONLY the copies (originals have segi A)
`mutation.cleanup_hiders` (mutation.py:131-159) does `cmd.remove(f"{object} and segi GAME")` (editing.py:800 — removes atoms FROM the object). The alt-conf copies carry `segi='GAME'`; the original real atoms carry `segi='A'` (or their original segi). The `and segi GAME` intersection restricts removal to the copies. **Even though endpoint copies COINCIDE in coordinates with the real atoms**, they are DISTINCT atom records (different `alt` — 'B' vs '' — and different `segi` — GAME vs A), so `remove("segi GAME")` deletes the copies and leaves the originals. 05-06 spike check 10: `after_count=660, orig_count=660` — cleanup restored the count exactly.

### 7b. BUT cleanup_hiders (sentinel remove) is INSUFFICIENT for repeated rounds — backup.restore is canonical (already in place)
**05-06 spike §12.2 caveat 3 (runtime-verified):** After `cmd.remove('segi GAME')`, residual alt-conf state interferes with re-insertion. After a create+alter+create flow, if the alt-conf atoms are removed by `cmd.remove('segi GAME')` and then a SECOND create+alter+create is attempted on the same object, the `segi GAME` iterate finds 0 CAs even though `count_atoms` shows new atoms. The alt-conf "slots"/records left behind confuse the next `cmd.create(obj, tmp)`.

**Resolution (already shipped in Phase 6):** `GameController.cleanup` (game.py:274-305) does NOT call `mutation.cleanup_hiders` — it calls `backup.restore(self.target_obj, self._backup_name)` (delete+create two-step, backup.py:54-64). The backup was snapshotted in `start()` BEFORE any mutation, so it has NO alt-conf atoms. `delete(target) + create(target, backup)` returns the object to its pre-game state — no residual alt-conf state. **The current cleanup path already handles this. Phase 11 does NOT need to change cleanup.** `GameController.abort_on_error` (game.py:307-320) also uses `backup.restore` — same, handles alt-conf.

**Hard rule (document):** alt-conf hiders REQUIRE `backup.restore` (delete+create two-step) for repeated rounds — NOT `mutation.cleanup_hiders` (sentinel remove). Keep `cleanup_hiders` available as a primitive (smoke tests, edge cases) but do NOT wire it into `GameController.cleanup`. This is the current state — no change needed for Phase 11.

### 7c. Snapshot-before-insert invariant (load-bearing)
`GameController.start` (game.py:48-69): `self._backup_name = backup.snapshot(self.target_obj)` runs BEFORE the `for (payload, rep) in hider_specs: mutation.insert_hider_for_rep(...)` loop. So the backup is a pristine pre-hider snapshot — NO alt-conf atoms, NO displaced coords, NO hint colors. This invariant is the entire safety net (PyMOL Open Source has NO undo — editor.py:25-36 no-op stub). **Phase 11 MUST preserve this: snapshot before ANY alt-conf construction.** Since `insert_altconf_cartoon_hider` is called inside the existing `insert_hider_for_rep` dispatch within the `start` loop, the snapshot already precedes it. No change needed.

### 7d. 05-08 Bug 4 dependency: source the temp from the CLEAN backup
`cmd.create(tmp, seg, 1, 1)` sourcing FROM an alt-conf-laden object (after the 1st insert) produces a temp with NO state-1 coords (invisible hider, 05-08 Bug 4 Part A). **`insert_altconf_cartoon_hider` MUST receive the `backup_name` parameter** and source the segment from `backup_name`, NOT from `obj` (which may already have alt-conf atoms from a prior hider in the same round). `insert_hider_for_rep` passes `backup_name` through; `game.start` passes `self._backup_name`. **Hard dependency on the construction signature.**

### 7e. altLoc-leakage prevention (the exact alter scoping)
The `alt='B'` tag is set on the TEMP object, NOT on `obj` directly. The 05-06 spike sequence: `cmd.create(tmp, seg)` → `cmd.alter(tmp, "alt='B'; segi='GAME'")` → `cmd.create(obj, tmp)`. The `alter` selection is `tmp`, NOT `obj and name N and resi X`. A too-broad `alter("obj and resi X", "alt='B'")` would hit the ORIGINAL residue X (alt='') too — LEAKING the alt tag onto real atoms. The temp-first approach eliminates this.

**Post-create alter scoping rule:** if ANY alter must run on `obj` after `cmd.create(obj, tmp)` (e.g., the b=-999 anchor set), restrict to `segi GAME` (only the copies carry it): `cmd.alter("%s and segi GAME and name CA and resi %d" % (obj, anchor_rv), "b=-999.0", space={})`. The `and segi GAME` prevents hitting the original CA (segi A) that shares the resi. **NEVER use `id <id>` alone** — it matches BOTH alt versions (shared id; 05-06 §12.2 caveat 2). Use `segi GAME and resi <rv>` for the anchor b=-999 set.

### 7f. `verify_intact` passes after restore
`backup.verify_intact` (backup.py:69-85) compares atom count + `(resn, resi, name, chain, segi)` multiset between target and backup. After `backup.restore` (delete+create from the pre-game backup), the target is an atom-for-atom copy of the backup → counts match + multisets match (the backup has no segi GAME atoms). **Passes.** The alt-conf atoms (added after the snapshot) are gone. (`verify_intact` does NOT compare coords — Phase 3 finding: `iterate` doesn't expose x/y/z; count + identity suffices because `create` copies coords bit-for-bit. The alt-conf displacement is irrelevant to `verify_intact` since the backup has no alt-conf atoms at all.)

---

## 8. .bcm Persistence Round-trip (NO version bump)

**Confidence:** MEDIUM (extension shape reasoned from persistence.py + registry.py; backward-compat reasoned, not runtime-verified).

### 8a. Current .bcm shape (Phase 8, persistence.py)
`build_bcm_dict` (persistence.py:45-110) produces `{'magic', 'version': 1, 'kind', 'target_object', 'started', 'timer_elapsed', 'reveal_count', 'hint_count', 'found_color', 'found_color_rgb', 'registry': controller.registry.to_dict(), 'setup'}`. `registry.to_dict()` (registry.py:227-237) = `{'version': 1, 'hiders': [record.to_dict() ...]}`. Each hider dict: `{id, object, rep, status, pos?}`. `parse_bcm_dict` (persistence.py:113-145) refuses `version > BCM_VERSION (1)`. `apply_bcm_dict` (persistence.py:150-192) calls `registry.reconcile_with_bcm(bcm_hiders)`.

### 8b. Proposed extension (backward-compatible v1 — NO version bump)
**Add `is_altconf`, `endpoint_resvs`, `alt_tag` to each hider dict as OPTIONAL fields.** Keep `version: 1` (parse_bcm_dict still accepts v1). `to_dict` omits them when default (sphere/line/stick → compact v1 shape unchanged). `from_dict`/`reconcile_with_bcm` read them with defaults. **No parse_bcm_dict change needed** (it validates magic+version only, not per-hider fields).

**Why no version bump:** ADDITIVE and optional. A v1 sidecar from Phase 8 code has no new fields → `from_dict`/`reconcile` treat every hider as non-altconf → works for sphere/line/stick exactly as today. A v1 sidecar from Phase 11 code includes the fields for alt-conf hiders → `reconcile` restores them. A future Phase 11 sidecar loaded by Phase 8 code → Phase 8's `from_dict` ignores unknown fields → alt-conf hiders load as `is_altconf=False` → score by anchor id only (non-anchor middle clicks miss) → degraded but playable. **Lowest-risk migration.**

**Extended hider dict (alt-conf):**
```json
{
  "id": 227, "object": "1ubq", "rep": "cartoon", "status": "hidden",
  "is_altconf": true,
  "endpoint_resvs": [10, 12],
  "alt_tag": "B"
}
```
Non-altconf hiders omit the fields (or set `is_altconf: false`).

### 8c. `import_state` re-establishes the middle/endpoint split
`GameController.import_state` (game.py:237-272):
1. `reconstruct_registry()` → `reconstruct_from_sentinels` rebuilds records from `fetch_all_hider_ids` (one record per anchor CA, `rep=None`, `status='hidden'`, AND `is_altconf=False, endpoint_resvs=None, alt_tag=''`).
2. `persistence.apply_bcm_dict(self, bcm_dict)` → `reconcile_with_bcm(bcm_hiders)` restores `rep`+`status` AND the new `is_altconf`+`endpoint_resvs`+`alt_tag` by matching `(object, id)`.
3. Defensive found-color re-apply (game.py:265-268).
4. `backup.snapshot(self.target_obj)` (fresh post-import backup).

**After reconcile, alt-conf records have `is_altconf=True, endpoint_resvs=(rv1, rv2), alt_tag='B'` → `on_pick`'s `get_altconf_by_resv` works → non-anchor middle clicks score post-reload.** The middle/endpoint structure is NOT recoverable from sentinels — the .bcm is the ONLY source. This mirrors Phase 8 Open Risk 6 (rep not recoverable from sentinels; .bcm reconciles). A missing/corrupt .bcm → alt-conf hiders load as `is_altconf=False` → only the anchor CA scores (the `alt` check is skipped because `is_altconf=False`) → game is winnable but the "click any middle atom" UX is lost. Degraded but playable — same graceful-degradation philosophy as Phase 8.

### 8d. Does `alt` survive `.pse` reload? (MEDIUM — load-bearing, needs smoke verification — Open Risk 2)
The Phase 3 smoke confirmed `segi` + `b` + `id` survive `.pse` (PITFALLS.md). `alt` is an atom property in the same `ObjectMolecule` atom record (same serialization path via `_cmd.get_session`/`set_session`, exporting.py:424 / importing.py:143). By the same mechanism, `alt='B'` should survive. **MEDIUM confidence** (reasoned, not explicitly smoke-verified for `alt`). The Phase 11 smoke MUST assert `alt` survives. **If `alt` does NOT survive reload, the `alt == rec.alt_tag` check fails post-reload** → alt-conf hiders unclickable after reload. **Mitigation:** the .bcm-stored `endpoint_resvs` + `is_altconf` still let `get_altconf_by_resv` find the record by resv; `on_pick` could score on `is_altconf=True AND resv-in-range` ALONE (drop the `alt` check) — but then clicking the real-trace middle CA (alt='' if alt lost) would score (the 05-08 latent limitation returns). The `alt` check is the clean disambiguator; losing it forces the resv-only fallback. **`alt` survival is load-bearing for clean req-3 satisfaction post-reload. Verify in smoke.** If it fails: re-apply `alt=rec.alt_tag` on `obj and segi GAME` via `cmd.alter` after `reconcile_with_bcm` (runtime re-tag from the .bcm-stored `alt_tag`).

---

## 9. Mixed-Rep Game (SUCCESS CRITERION 4)

**Confidence:** HIGH (dispatch + counting reasoned from existing mutation.py + registry.py).

### 9a. Alt-conf slots into `insert_hider_for_rep` without breaking sphere/line/stick
`mutation.insert_hider_for_rep` (mutation.py:483-538) dispatches per rep: `spheres` → `insert_hider` + show spheres; `lines`/`sticks` → `insert_line_stick_hider`; `cartoon`/`ribbon` → `insert_cartoon_hider` (terminal-extension, Phase 5). **Phase 11 REPLACES the `cartoon`/`ribbon` branch body** with a call to the new `insert_altconf_cartoon_hider`. The dispatcher signature + return (the anchor CA's stable id) is unchanged — `game.start`'s loop does `aid = mutation.insert_hider_for_rep(...); self.registry.register(object=self.target_obj, id=aid, rep=rep)` and now ALSO passes `is_altconf=(rep in ('cartoon','ribbon')), endpoint_resvs=(rv1,rv2) if is_altconf else None, alt_tag='B' if is_altconf else ''`. **The `spheres`/`lines`/`sticks` branches are UNTOUCHED** — they still produce single-id, `is_altconf=False` records.

### 9b. `counts_by_rep` counts hiders (records), NOT atoms — correct for mixed rep
`counts_by_rep` (registry.py:190-210) iterates `self._records.values()` — ONE record per hider. A cartoon hider (with 3 middle residues × ~4 backbone atoms = ~12 middle atoms) is ONE record → `counts_by_rep['cartoon'] += 1`, NOT +12. A ribbon hider is ONE record. Sphere/line/stick are ONE record each. **Mixed-rep counts are correct with NO change to `counts_by_rep`.** The middle-atom scoring is a pick-time derivation (`get_altconf_by_resv`), invisible to counts.

### 9c. `on_pick` scores correctly per rep (dual lookup + alt/resv gate)
For a mixed-rep game, `on_pick(aid, alt, resv)`:
- **Sphere click:** `aid` = unique pseudoatom id → `registry.get` hit → `rec.is_altconf=False` → skip alt/resv check → score.
- **Line/stick click:** `aid` = unique bonded-pseudoatom id → `registry.get` hit → `is_altconf=False` → score.
- **Cartoon middle CA click (alt='B', resv=middle):** `aid` = shared anchor id → `registry.get` hit (the cartoon record) → `is_altconf=True` → `alt=='B'` AND `rv1<resv<rv2` → score.
- **Cartoon endpoint CA click (alt='B', resv=rv1):** `registry.get` None (endpoint id not registered) → `get_altconf_by_resv` None (rv1 not strictly between) → miss.
- **Cartoon real-trace CA click (alt='', resv=middle):** `registry.get` hit (shared id) → `is_altconf=True` → `alt!='B'` → miss. OR `registry.get` None → `get_altconf_by_resv` hit → `is_altconf=True` → `alt!='B'` → miss.
- **Ribbon:** same as cartoon (the record's `rep` is 'ribbon'; the scoring logic is rep-agnostic — it keys on `is_altconf`, not `rep`).

**All four reps score correctly in a mixed game.** Success criterion 4 satisfied: all tracked in the registry, all clickable via the dual lookup, counts per-rep correct.

### 9d. `_mark_found` uses `rec.id` (anchor) + branches on `is_altconf` for coloring
`game.py:on_pick` currently calls `self._mark_found(picked_id)`. For alt-conf non-anchor middle clicks, `picked_id` ≠ the record's anchor id → `mark_found(obj, picked_id)` would KeyError (registry.py:212-223). **Change `on_pick` to `self._mark_found(rec.id, rec)`.** For sphere/line/stick, `rec.id == picked_id` (unique id) → unchanged. For alt-conf, `rec.id` = anchor id → mark_found sets the record found.

**Coloring fix (B Pitfall B-7):** The shared-id means `cmd.color("obj and id 227", "green")` colors BOTH the alt='' original AND the alt='B' copy → a real atom turns green (confusing). **For `is_altconf` records, `_mark_found` colors `"obj and segi GAME and resi <rv1+1>-<rv2-1>"`** (the middle residues, all alt-conf copies — the whole displaced bump turns green, clearer feedback). For non-altconf, color by id (unchanged). Small `_mark_found` branch on `rec.is_altconf`.

---

## 10. Headless Smoke + GUI Diagnostic

### 10a. Headless smoke path (pure `pymol.cmd.*`, NO Qt — WSL-runnable)
The smoke exercises the FULL alt-conf lifecycle headlessly. It does NOT use `PickWizard` (Qt-free) — it calls `controller.on_pick(aid, alt, resv)` directly with simulated pick values. The wizard modification (iterate pk1 for alt/resv) is Qt-free too, but testing `on_pick` directly is simpler + deterministic. Run via:
```bash
bash wsl2win_cp.sh
mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/phase11_smoke.py tmp/bioCHEMeleon/smoke/
cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase11_smoke.py" 2>&1 | tail -50
```

**Headless-verifiable (pure `pymol.cmd.*`, no Qt):**
- Atom counts (orig, +25, restored) — `cmd.count_atoms`.
- Sentinel hits (1 anchor b<0, 25 GAME atoms) — `cmd.count_atoms("... and segi GAME and b < 0")`.
- Polymer membership — `cmd.count_atoms("... and segi GAME and polymer")`.
- Rep shown — `cmd.count_atoms("... and segi GAME and rep cartoon") > 0` (mutagenesis.py:570 pattern).
- `on_pick` return values (score/no-score) — call `controller.on_pick(aid, alt, resv)` directly, assert `rec.status`.
- `verify_intact` after restore — `backup.verify_intact`.
- `.pse` round-trip: `segi GAME` + `b < 0` + `alt` survival + id stability — `cmd.save` + `cmd.delete` + `cmd.load` + `cmd.iterate`.
- `reconstruct_from_sentinels` + `reconcile_with_bcm` round-trip — build a .bcm dict, apply, assert `is_altconf`/`endpoint_resvs`/`alt_tag` restored.
- `get_altconf_by_resv` correctness — call directly, assert returns the right record / None.

### 10b. GUI-only (human-verify, NOT headless) — the 05-08 methodology failure
- The cartoon/ribbon tube renders CONNECTED (not disconnected) — human eye.
- The displaced middle bump is visible + clickable — human eye.
- The endpoint residues visually coincide with the real trace (no visible seam) — human eye.
- The found-color (green) shows on the displaced bump (not on the real trace) — human eye.
- Mixed-rep visual coexistence (sphere + line/stick + cartoon + ribbon all visible) — human eye.
- **No auto-zoom** (the GUI `auto_zoom=1` does NOT push other hiders off-screen) — human eye.
- **Multi-state display** (all 2+ cartoon/ribbon hiders visible when `all_states=on`) — human eye.
- **No retroactive coord corruption** (hider 1 still visible/displaced after hider 2 is inserted) — human eye.

### 10c. MANDATORY GUI-runnable diagnostic (Open Risk 4 — the 05-08 methodology failure)
Headless PyMOL (`-cq`) defaults `auto_zoom=-1` (off); GUI defaults `auto_zoom=1`. Any `cmd.create`/`cmd.zoom` verification MUST run in the GUI (a Windows PyMOL diagnostic script the user runs, NOT headless-only smoke). **The 05-08 attempt failed because 4 fix cycles each passed headless (44/44, 49/49) but failed in the GUI.** The Phase 11 plan MUST include a GUI-runnable diagnostic script (pure `pymol.cmd.*`, no Qt) that the user runs via `cmd.exe /c C:\src\run-conda-pymol.bat` WITHOUT `-cq` (or with the GUI) to verify auto-zoom, multi-state display, and coord corruption. **The headless smoke is necessary but NOT sufficient** — this is the single most important methodological lesson from 05-08.

---

## Standard Stack

No new libraries. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer. No `pip install` (opencode.json denies `pip*`/`apt*`/`conda*`).

### Core cmd APIs (all verified against `tmp/pymol-src/modules/pymol/`)

| API | Signature | Purpose | Source |
|-----|-----------|---------|--------|
| `cmd.create` | `create(name, selection, source_state=0, target_state=0, discrete=0, zoom=-1, ...)` | Copy atoms to new/existing object; `target_state=-1` appends new state (creating.py:1000); `zoom=0` prevents auto-zoom (Bug 3); same-object create is NO-OP (merge by identity); preserves source ids (Phase 3 Q2b) | creating.py:960-1036 |
| `cmd.alter` | `alter(selection, expression, space={})` | Set `alt='B'`, `segi='GAME'`, `b=-999`, `ss='L'`, `color=...` on atoms; multi-field `;`-joined (editor.py:354); `alt` writable (editing.py:1446); hygienic `space={}` (NEVER `space=None`); `cmd.alter("id=...")` is silent NO-OP | editing.py:1424-1473 |
| `cmd.alter_state` | `alter_state(state, selection, expression, space={})` | Displace middle-residue coords (`x=x+dx; y=y+dy; z=z+dz`); runs per-state for multi-hider; symbol table exposes `x, y, z` (state-dependent, writable); line 1566 `_iterate_prepare_args` for hygienic space; line 1571 `_cmd.alter_state`; state 1-indexed | editing.py:1535-1575 |
| `cmd.iterate` | `iterate(selection, expression, space={})` | Read `ID`, `alt`, `resv`, `color`, `chain`, `name` on atoms (NO `x/y/z` — state-dependent); use `segi GAME` selector; reads `(model, ID, alt, resv)` from `pk1` for scoring | editing.py:1490+ |
| `cmd.iterate_state` | `iterate_state(state, selection, expression, space={})` | Read x/y/z coords; the ONLY coord reader (iterate doesn't expose x/y/z); CORRUPTED after alt-conf insert (Bug 2) — pre-capture BEFORE any insert | editing.py:1578+ |
| `cmd.identify` | `identify(selection, mode=0)` / `mode=1` | mode=0 → `[id]`; mode=1 → `[(model, id)]` (NO `alt`, NO `resv` — querying.py:1282-1283); use `segi GAME` selector (NOT id-diff for alt-conf — Pitfall 3) | querying.py:1269-1300 |
| `cmd.count_atoms` | `count_atoms(selection)` | Verify rendering: `count_atoms("obj and segi GAME and rep cartoon") > 0` (mutagenesis.py:570 pattern); sentinel/polymer checks | querying.py:1412-1434 |
| `cmd.show` | `show(rep, selection)` | Show the requested rep on alt-conf atoms; `rep` parameterized (05-09 fix, commit `2d487af`) | viewing.py:491-526 |
| `cmd.remove` | `remove(selection)` | `remove("obj and segi GAME")` (primitive; NOT the post-game cleanup — Pitfall 8/B-3); removes atoms FROM object | editing.py:800 |
| `cmd.delete` | `delete(name)` | Delete temp object; idempotent; first half of `backup.restore` | commanding.py:496 |
| `cmd.sort` | `sort(object)` | Defensive after `alter` of segi/alt (editing.py:1457 warning); preserves id, reassigns index — safe for id-keyed registry | editing.py:1457 |
| `cmd.set` | `set(name, value, object)` | `all_states=on` (object-scoped) for multi-state (2+ alt-conf hiders); reset to `off` on cleanup; C-side setting | importing.py:1578 |
| `cmd.get_unused_name` | `get_unused_name(prefix)` | For temp object names (`_bchm_alt`) | querying.py:74 |
| `cmd.fuse` | `fuse(sel1, sel2, mode=0, ...)` | **DISPROVED for alt-conf** — mode 3 RENAMES atoms (CA→C02, loses `name CA`); do NOT use | editing.py:937-987 |
| `cmd.save` / `cmd.load` | — | `.pse` round-trip for `alt` survival smoke (Open Risk 2) | exporting.py:424 / importing.py:143 |
| `cmd.refresh_wizard` | — | Clear `pk1` pick state after `do_pick` | wizard.py |

### Selectors (verified in cmd.py:356-365)

| Selector | Purpose | Source |
|----------|---------|--------|
| `backbone` | N, CA, C, O atoms (backbone-only copy per user req 1) | cmd.py:364 |
| `sidechain` | NOT a backbone atom (fallback: copy-whole + `remove sidechain`) | cmd.py:364 |
| `alt B` | Alt-conf atoms (alt='B'); use for selective middle displacement | cmd.py:357 |
| `segi GAME` | Sentinel segment (cleanup + read); works on alt-conf atoms | cmd.py:357 |
| `b < 0` | Sentinel b-factor (read path); works on alt-conf atoms; **NOT `b -999`** (malformed) | AGENTS.md |
| `polymer` | Polymer atoms (cartoon trace membership, connectivity-based); alt-conf atoms ARE polymer | cmd.py:363 |
| `rep cartoon` / `rep ribbon` | Atoms with rep enabled (visibility check) | cmd.py:360 |
| `name CA` | C-alpha atoms (cartoon representative) | cmd.py:357 |
| `resi A-B` | Residue range (numeric; for middle selection); `resi` is the string resi | cmd.py:357 |
| `id a+b+c` | Atom id list (for id-based middle selection; shared between alt versions — scope with `and segi GAME`) | cmd.py:357 |

---

## Architecture Patterns

### Module placement (strict dependency direction, AGENTS.md)

```
setup_state.py (PURE, UNCHANGED) ── GAME_REPS, DEMO_MANIFEST
      ↑
generators.py (PURE, NEW) ── pick_segments, generate_middle_displacement
      │   pick_segments(cas_by_chain, count, segment_size=3) -> [(chain, rv1, rv2), ...]
      │       DISJOINT segments (Bug 1 fix; pick ALL cartoon+ribbon in ONE call)
      │       Hard contract: ranges MUST be non-overlapping (get_altconf_by_resv depends on it)
      │   generate_middle_displacement(n, seed, magnitude=1.5) -> [[dx,dy,dz], ...]
      │       One random unit vector per hider (rigid translation); seeded
      ↑
registry.py (PURE, EXTENDED) ── HiderRecord (+ is_altconf/endpoint_resvs/alt_tag)
      │   HiderRegistry (+ get_altconf_by_resv; to_dict/from_dict/reconcile_with_bcm extended)
      │   id-keying intact; NO multi-id index; DI for any cmd interaction
      ↑
mutation.py (cmd, EXTENDED) ── insert_altconf_cartoon_hider (construction); insert_hider_for_rep dispatch
      │   cleanup_hiders stays as a PRIMITIVE (NOT wired into game.cleanup)
      ↑
backup.py (cmd, UNCHANGED) ── snapshot/restore/discard/verify_intact (already handles alt-conf)
      ↑
persistence.py (PURE, EXTENDED) ── build_bcm_dict/apply_bcm_dict (optional fields; NO version bump)
      ↑
game.py (cmd, EXTENDED) ── on_pick(aid, alt='', resv=None) + _mark_found(rec.id, rec)
      │   start(all_states toggle for 2+ alt-conf) + cleanup (UNCHANGED — backup.restore)
      ↑
wizard.py (cmd, EXTENDED) ── do_pick iterates pk1 for (model, ID, alt, resv); passes to on_pick
      ↑
__init__.py (Qt + cmd, EXTENDED) ── _on_start pre-captures coords BEFORE any insert
```

### Proposed function signatures

```python
# generators.py (PURE, NEW)
def pick_segments(cas_by_chain, count, segment_size=3):
    """Mid-chain segment picker. Returns [(chain, start_resi, end_resi), ...].
    DISJOINT segments (Bug 1 fix). Hard contract: ranges non-overlapping."""
    ...

def generate_middle_displacement(n, seed, magnitude=1.5):
    """Pure RNG. Returns [[dx, dy, dz], ...] — one random unit vector per hider × magnitude.
    Same offset for all middle atoms of one hider (rigid translation)."""
    ...

# mutation.py (cmd, EXTENDED)
def insert_altconf_cartoon_hider(object, chain, start_resi, end_resi, handle,
                                  backup_name, rep='cartoon', displacement=1.5,
                                  is_first_altconf=True, segi='GAME', b=-999.0,
                                  n_color=0):
    """Alt-conf backbone-only segment replication hider (cartoon/ribbon).
    Sources from CLEAN backup (Bug 4 Part A). 1st → state 1; 2nd+ → new state (target_state=-1, Bug 4 Part B).
    zoom=0 on ALL cmd.create (Bug 3). Displaces ALL middle-residue atoms (rigid translation, user req 2).
    Returns the clickable middle anchor CA's stable id (shared with original — Bug 1)."""
    ...

def insert_hider_for_rep(object, rep, payload, handle, backup_name=None):
    """Dispatcher: cartoon/ribbon → insert_altconf_cartoon_hider (passes backup_name);
    spheres → insert_hider; lines/sticks → insert_line_stick_hider (unpacks pre-captured coord, Bug 2)."""
    ...

# registry.py (PURE, EXTENDED)
class HiderRecord:
    __slots__ = ('id', 'object', 'rep', 'status', 'pos',
                 'is_altconf', 'endpoint_resvs', 'alt_tag')
    def __init__(self, id, object, rep, status='hidden', pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''): ...

class HiderRegistry:
    def register(self, object, id, rep, status='hidden', pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''): ...
    def get_altconf_by_resv(self, object, resv):
        """Return the alt-conf record with rv1 < resv < rv2 (strict middle), or None. Pure.
        Correct because alt-conf hiders have DISJOINT resv ranges (pick_segments contract)."""
    # to_dict/from_dict/reconcile_with_bcm extended for the 3 new fields (optional, default)

# game.py (cmd, EXTENDED)
def on_pick(self, picked_id, alt='', resv=None):
    """Dual lookup (id then resv) + alt/resv gate for alt-conf. Backward-compatible signature."""
    rec = self.registry.get(self.target_obj, picked_id)
    if rec is None and resv is not None:
        rec = self.registry.get_altconf_by_resv(self.target_obj, resv)
    if rec is None:
        self._on_log("Miss!"); return
    if rec.is_altconf and (alt != rec.alt_tag or not
                           (rec.endpoint_resvs[0] < resv < rec.endpoint_resvs[1])):
        self._on_log("Miss!"); return
    self._mark_found(rec.id, rec)   # rec.id (anchor) NOT picked_id

def _mark_found(self, hider_id, rec=None):
    """If rec.is_altconf: color 'obj and segi GAME and resi <middle-range>' (the displaced bump).
    Else: color 'obj and id <hider_id>' (unchanged, sphere/line/stick)."""
    self.registry.mark_found(self.target_obj, hider_id)
    if rec is not None and rec.is_altconf and rec.endpoint_resvs:
        rv1, rv2 = rec.endpoint_resvs
        cmd.color(self._found_color, "%s and segi GAME and resi %d-%d" % (self.target_obj, rv1+1, rv2-1))
    else:
        cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))

# wizard.py (cmd, EXTENDED)
def do_pick(self, bondFlag):
    props = []
    cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={'stored': props})
    cmd.unpick()
    if not props: return
    model, aid, alt, resv = props[0]
    if model != self.target_object: return   # non-target -> miss
    self.controller.on_pick(aid, alt=alt, resv=resv)
    cmd.refresh_wizard()
```

### Anti-patterns to avoid
- **Registering all middle atom ids as separate records** → counts_by_rep inflates + shared-id false positives. Use ONE record per hider (anchor id) + `get_altconf_by_resv`.
- **Using `mutation.cleanup_hiders` (sentinel remove) as the post-game cleanup for alt-conf** → 05-06 caveat 3: residual alt-conf state breaks the next round. Use `backup.restore` (already canonical).
- **`cmd.alter("obj and resi X", "alt='B'")`** → leaks alt onto the original residue X. ALWAYS alter the TEMP (before create) or scope with `and segi GAME` (after create).
- **`cmd.alter("obj and id <shared_id>", "b=-999")`** → hits BOTH alt='' and alt='B' (shared id). Use `obj and segi GAME and resi <rv>` for the anchor set.
- **`on_pick` calling `_mark_found(picked_id)` for alt-conf** → KeyError if picked_id is a non-anchor middle id. Use `_mark_found(rec.id, rec)`.
- **Coloring a found alt-conf hider by shared id** → colors the real-trace original too. Use `segi GAME and resi <middle-range>`.
- **Displacing only CA (not all middle-residue atoms)** → broken backbone geometry, distorted tube. Displace ALL middle atoms (rigid translation).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atom duplication within same object | Manual pseudoatom loop with per-atom coord copy | `cmd.create(tmp, "...and backbone", 1, 1, zoom=0)` + `alter alt='B'` + `cmd.create(obj, tmp, zoom=0)` | `cmd.create` preserves polymer classification + bonds; pseudoatoms can't render in cartoon (spike DISPROVED); 05-06 spike verified |
| Backbone-only copy | Copy whole + `cmd.remove("sidechain")` | `cmd.create(tmp, "...and backbone", 1, 1, zoom=0)` | One-step; `backbone` selector (cmd.py:364) is C-side, stable |
| Coordinate displacement | Manual `cmd.set_dihedral` / bond rotations / `cmd.translate` | `cmd.alter_state(state, sele, "x=x+dx; y=y+dy; z=z+dz", space={})` | `alter_state` is the verified per-atom-coordinate write API (editing.py:1535; spike verified dx=2.0); `translate` is object-matrix-oriented |
| Alt-conf tag management | Manual occupancy calculation | `cmd.alter(sele, "alt='B'", space={})` | Default occupancy works; no occupancy management needed (05-06 spike) |
| Multi-state visibility | Manual per-state rep show | `cmd.set('all_states', 'on', object)` | Object-scoped C-side setting; 05-08 Bug 4 fix verified |
| Segment selection | Guessing mid-chain by resi=middle | `pick_segments(cas_by_chain, count)` (pure, in generators.py) | Avoids terminals; DISJOINT for Bug 1; pure/WSL-testable |
| Auto-zoom prevention | Post-hoc `cmd.zoom(target_obj)` | `zoom=0` on every `cmd.create` call | Prevents at source (Bug 3); `cmd.zoom` after is a nicety, not correctness |
| Distinguishing clicked alt-conf from real (shared id) | Custom `cmd.identify` + heuristics | `cmd.iterate("pk1", "...alt, resv...", space={})` | `pk1` is a one-atom selection; `iterate` returns the picked atom's `alt`; `identify` drops `alt` (querying.py:1282) |
| Middle-residue selection | Python loop over all atoms filtering resv | `cmd.iterate("obj and segi GAME", "...resv...", space={})` + filter, OR `resi rv1+1-rv2-1` selector | C-side selection + iterate is fast; id-based filter robust for insertion-coded resi |
| Post-game cleanup for alt-conf | `cmd.remove("segi GAME")` (sentinel remove) | `backup.restore` (delete+create two-step, backup.py:54) | 05-06 caveat 3: sentinel remove leaves residual alt-conf state that breaks re-insertion; restore is canonical Phase 6+ |
| Registry multi-id scoring | Secondary `_id_index` dict + sync on register/remove | `get_altconf_by_resv` (resv-range lookup) + `alt` check at pick time | Shared ids break the index (false positives); resv-range is stateless + degrades gracefully |

**Key insight:** The alt-conf mechanism is a 4-call sequence (`create` + `alter` + `create` + `delete`). Do NOT hand-roll the duplication — `cmd.create` with `alt` set is the ONLY mechanism that produces renderable alt-conf polymer atoms. Pseudoatoms and `fuse` were disproved by the 05-06 spike. The shared-id problem means NO id-based mechanism can distinguish hider from real — the disambiguation MUST come from a non-id atom property read at pick time (`alt` via `iterate` on `pk1`).

---

## Common Pitfalls

### Pitfall 1: `cmd.create(obj, seg, 1, 1)` same-object is a NO-OP (merge by identity)
**What goes wrong:** Duplicating atoms within the same object via `cmd.create(obj, seg, 1, 1)` produces 0 new ids — `cmd.create` MERGES by identity (segi, chain, resi, name) when the target name equals the source.
**How to avoid:** Use the 3-step: `create(tmp, seg)` + `alter(tmp, "alt='B'")` + `create(obj, tmp)`. The `alt='B'` makes the identity DIFFERENT, so `create(obj, tmp)` APPENDS.
**Warning signs:** `new_ids = set(cmd.identify(obj, mode=0)) - ids_before` is empty after `cmd.create(obj, seg, 1, 1)`.
**Source:** 05-06 spike (commit `a6fd26a`), creating.py:960.

### Pitfall 2: `cmd.fuse(tmp, obj, mode=3)` RENAMES atoms (no `name CA`)
**What goes wrong:** `cmd.fuse` mode 3 (combine only) RENAMES atoms to avoid collisions — CA→C02, N→N01, O→O04. The cartoon trace can't find `name CA`.
**How to avoid:** Do NOT use `cmd.fuse` for alt-conf. Use `cmd.create(obj, tmp)` with `alt='B'` set on the temp.
**Source:** 05-06 spike, editing.py:937-987.

### Pitfall 3: `cmd.identify` id-diff does NOT find alt-conf atoms
**What goes wrong:** The id-diff approach (`ids_before = identify(obj); create; new = identify(obj) - ids_before`) returns empty — `cmd.identify` doesn't return alt-conf duplicates.
**How to avoid:** Use `segi GAME` selectors: `cmd.iterate("obj and segi GAME", ...)` and `cmd.identify("obj and segi GAME", mode=0)` both see alt-conf atoms.
**Source:** 05-06 spike caveat 1.

### Pitfall 4: `id <id>` selector matches BOTH alt versions / Setting b=-999 by shared id
**What goes wrong:** `cmd.alter("obj and id 227", "b=-999.0")` sets b=-999 on BOTH the original (alt='', segi A) AND the alt-conf (alt='B', segi GAME) — they share id 227. The original becomes a fetch-sentinel too → `fetch_all_hider_ids` returns 2 atoms → 2 registry records per hider → counts wrong.
**How to avoid:** Use `obj and segi GAME and name CA and resi <rv>` to select ONLY the alt-conf CA (the original has `segi='A'`, excluded). NEVER use `id <id>` alone for the anchor b=-999 set.
**Source:** 05-06 spike caveat 2; 05-08 Bug 1 (commit `6d51d12`).

### Pitfall 5: Auto-zoom in GUI (headless smoke is blind)
**What goes wrong:** Headless smoke passes (`auto_zoom=-1` off), but the GUI `auto_zoom=1` zooms into the first hider's segment, pushing other hiders off-screen.
**How to avoid:** `zoom=0` on EVERY `cmd.create` call. Include a GUI-runnable diagnostic (Windows PyMOL script) in the plan — headless smoke alone is INSUFFICIENT for `cmd.create`-heavy code.
**Source:** 05-08 Bug 3 (commit `d146370`).

### Pitfall 6: Retroactive coord corruption on 2nd alt-conf merge (multi-hider killer)
**What goes wrong:** `cmd.create(obj, tmp)` merging the 2nd alt-conf into state 1 (which holds the 1st) CORRUPTS the 1st alt-conf's coords — collapse to 1x1x1 "no coords" box; un-readable AND un-writable.
**How to avoid:** Source from clean backup (Bug 4 Part A) + 2nd+ alt-conf as new state (`target_state=-1`, Bug 4 Part B) + `all_states=on` for visibility.
**Source:** 05-08 Bug 4 (commit `335fe3c`).

### Pitfall 7: `iterate_state` corruption after alt-conf insert
**What goes wrong:** After one `cmd.create(obj, tmp)` alt-conf insert, `cmd.iterate_state(1, "id X")` for non-segment atoms returns missing. A line/stick hider inserted after a cartoon hider raises ValueError.
**How to avoid:** Pre-capture ALL needed coords (neighbor CAs for line/stick, segment CAs for displacement direction) BEFORE any `cmd.create` mutation. Pass pre-captured coords through the payload.
**Source:** 05-08 Bug 2 (commit `6d51d12`).

### Pitfall 8: Sentinel cleanup leaves residual alt-conf state (breaks New Game)
**What goes wrong:** `cmd.remove("segi GAME")` restores the count but leaves residual alt-conf state that breaks subsequent alt-conf insertions.
**How to avoid:** Use `backup.restore` (delete+create two-step) for cleanup between rounds. The current `game.py.cleanup` (Phase 6) ALREADY uses `backup.restore` — COMPATIBLE, no change needed. Keep `mutation.cleanup_hiders` as a primitive only.
**Source:** 05-06 spike caveat 3.

### Pitfall 9: `cmd.alter("id=...")` is a silent NO-OP
**What goes wrong:** `cmd.alter("obj and segi GAME and name CA", "id=999")` silently does nothing — `id` is immutable in the C engine (the symbol table has `ID` without `*` but the C engine rejects changes).
**How to avoid:** Do NOT try to mint unique ids for alt-conf atoms. Use the shared id + sentinel (`segi GAME and b < 0`) to distinguish. The registry collision is solved at pick time via `alt`/`resv` (not at construction).
**Source:** 05-08 Bug 1 (commit `6d51d12`).

### Pitfall 10: Assuming alt-conf atoms get NEW unique ids (they DON'T)
**What goes wrong:** The registry registers the alt-conf CA's id expecting it to be unique; clicking the original real CA (which shares the id) also scores a find.
**How to avoid:** Read `alt` from the picked atom (`cmd.iterate("pk1", "...alt...")`); score only if `alt == rec.alt_tag`. NEVER assume an alt-conf atom's id is unique.
**Warning signs:** Clicking the real trace scores a find; the game is trivially winnable by clicking real atoms.
**Source:** 05-06 spike §12.2 caveat 2 + 05-08 Bug 1 (commit `6d51d12`).

### Pitfall 11: `cmd.identify("pk1", mode=1)` returns `(model, id)` — NO `alt`
**What goes wrong:** The wizard passes only `id` to `on_pick`; `on_pick` cannot tell alt='' (real) from alt='B' (hider).
**How to avoid:** Use `cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={...})` BEFORE `cmd.unpick()` to read the picked atom's `alt` + `resv`. Pass all four to `on_pick`.
**Source:** querying.py:1282-1283.

### Pitfall 12: altLoc leakage via too-broad `alter` selection
**What goes wrong:** `cmd.alter("obj and resi X", "alt='B'")` sets `alt='B'` on the ORIGINAL residue X (alt='') too — the real trace becomes an alt-conf.
**How to avoid:** Set `alt` on the TEMP object BEFORE `create(obj, tmp)`. After create, scope any alter with `and segi GAME` (only copies carry it).
**Warning signs:** Real atoms gain `alt='B'`; `cmd.iterate("obj and alt B and not segi GAME")` returns non-zero.
**Source:** 05-06 spike §12.3.

### Pitfall 13: `on_pick` calling `_mark_found(picked_id)` for a non-anchor middle click
**What goes wrong:** `mark_found(obj, non_anchor_id)` raises KeyError (the non-anchor id isn't a registry key) → crash on a valid middle click.
**How to avoid:** `on_pick` calls `self._mark_found(rec.id, rec)` (the RECORD's anchor id), NOT `_mark_found(picked_id)`.
**Warning signs:** Crash (KeyError) when clicking a non-anchor middle atom.
**Source:** registry.py:212-223.

### Pitfall 14: Coloring a found alt-conf hider by shared id (colors the real trace too)
**What goes wrong:** `cmd.color('green', "obj and id 227")` colors both the alt='' original AND the alt='B' copy → a real atom turns green → confusing.
**How to avoid:** For `is_altconf` records, color by `"obj and segi GAME and resi <rv1+1>-<rv2-1>"` (the displaced middle bump), NOT by id. Branch `_mark_found` on `rec.is_altconf`.
**Source:** shared-id (Pitfall 10).

### Pitfall 15: Displacing only the CA (not all middle-residue atoms)
**What goes wrong:** The cartoon tube through the middle residue distorts (N/C/O left at original coords, CA displaced) → broken backbone geometry → distorted tube.
**How to avoid:** Displace ALL atoms of the middle residues (N, CA, C, O) by the SAME offset (rigid translation). Selection: `segi GAME and alt B and resi <middle-range>` (all atoms) or `segi GAME and id <all-middle-ids>`. **This is the spike-verified pattern** (the 05-06 spike used `segi GAME` without `name CA`).
**Warning signs:** The displaced bump looks jagged/distorted, not a smooth tube offset.
**Source:** 05-06 spike §12.3; reconciled over Aspect A's CA-only code example.

### Pitfall 16: `alter_state` on the wrong state (multi-hider)
**What goes wrong:** Displacing hider 2's middle atoms in state 1 (where hider 1 lives) corrupts hider 1's coords (05-08 Bug 4).
**How to avoid:** Each hider's atoms live in their OWN state (1st: state 1; 2nd+: `target_state=-1` new state). `alter_state(state=<hider's state>, ...)` uses the correct state. The registry record stores the state (or it's tracked in `insert_altconf_cartoon_hider`).
**Source:** 05-08 Bug 4 (commit `335fe3c`).

---

## Code Examples

### Example 1: `insert_altconf_cartoon_hider` — full construction (4-call + Bug 4 fixes + ALL-atoms displacement)
```python
# Source: creating.py:960 (create), editing.py:1424 (alter), editing.py:1535 (alter_state),
#         viewing.py:491 (show), editing.py:1457 (sort), querying.py:1269 (identify), querying.py:74 (get_unused_name)
# 05-06 spike (commit a6fd26a) — runtime-verified 10/10 headless
# 05-08 Bug fixes (commits 6d51d12, d146370, 335fe3c) — headless-verified, GUI human-verify PENDING

def insert_altconf_cartoon_hider(object, chain, start_resi, end_resi, handle,
                                  backup_name, rep='cartoon', displacement=1.5,
                                  is_first_altconf=True, segi='GAME', b=-999.0,
                                  n_color=0, dx=1.5, dy=0.0, dz=0.0):
    """Alt-conf backbone-only segment replication hider (cartoon/ribbon).
    Returns the clickable middle anchor CA's stable id (shared with original — Bug 1)."""
    # 0. Derive target_state from is_first_altconf (Bug 4 Part B fix)
    target_state = 0 if is_first_altconf else -1   # 1st → state 1; 2nd+ → new state
    hider_state = 1 if is_first_altconf else cmd.count_states(object)

    # 1. Copy BACKBONE ONLY from CLEAN backup to temp (Bug 4 Part A; user req 1; cmd.py:364;
    #    zoom=0 CRITICAL — Bug 3 fix)
    tmp = cmd.get_unused_name("_bchm_alt")          # querying.py:74
    segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
        backup_name, chain, start_resi, end_resi)
    cmd.create(tmp, segment_sele, 1, 1, zoom=0)     # creating.py:960

    # 2. Set alt-conf + sentinel + ss on TEMP (editing.py:1424; hygienic space={}; NO leakage — Pitfall 12)
    cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'", space={})

    # 3. Append alt-conf atoms to target (creating.py:960; target_state for Bug 4 Part B; zoom=0 for Bug 3)
    cmd.create(object, tmp, target_state=target_state, zoom=0)

    # 4. Clean up temp
    cmd.delete(tmp)                                # commanding.py:496

    # 5. Displace ALL MIDDLE-residue atoms (rigid translation; user req 2; editing.py:1535)
    #    Endpoints (start_resi, end_resi) stay at original coords (blend);
    #    middle (start_resi+1 .. end_resi-1) displaced (distinguishable).
    #    ALL atoms (N, CA, C, O) — NOT just CA (Pitfall 15).
    middle_sele = "%s and segi GAME and alt B and resi %d-%d" % (
        object, start_resi + 1, end_resi - 1)       # all middle atoms (no `name CA`)
    cmd.alter_state(hider_state, middle_sele,
                    "x=x+dx; y=y+dy; z=z+dz",
                    space={'dx': dx, 'dy': dy, 'dz': dz})  # editing.py:1535

    # 6. Set b=-999 on ONE anchor middle CA (segi GAME + name CA + resi, NOT id — Pitfall 4)
    middle_cas = []
    cmd.iterate("%s and segi GAME and alt B and name CA and resi %d-%d" % (
        object, start_resi + 1, end_resi - 1),
        "stored.append((ID, resv))", space={'stored': middle_cas})
    anchor = middle_cas[len(middle_cas) // 2]        # middle of the middle (anchor)
    clickable_id = anchor[0]
    clickable_resv = anchor[1]
    cmd.alter("%s and segi GAME and name CA and resi %d" % (object, clickable_resv),
              "b=-999.0", space={})

    # 7. Defensive sort (editing.py:1457; preserves id)
    cmd.sort(object)

    # 8. Show the REQUESTED rep (viewing.py:491; 05-09 rep forwarding, commit 2d487af)
    cmd.show(rep, "%s and segi GAME and alt B" % object)

    return clickable_id, (start_resi, end_resi)    # id + endpoint_resvs for registry
```

### Example 2: Pre-capture coords BEFORE any insert (Bug 2 defense, in `_on_start`)
```python
# Source: 05-08 Bug 2 fix (commit 6d51d12); editing.py:1578 (iterate_state)
# Pre-capture neighbor CA coords for line/stick + segment CA coords for displacement
# while the state is CLEAN (before any cmd.create mutation).

# Neighbor CAs for line/stick (pre-capture (x,y,z,elem,color) per CA id)
neighbor_coord_map = {}
cmd.iterate_state(1, "%s and name CA and not segi GAME" % target_obj,
                  "stored[ID] = (x, y, z, elem, color)",
                  space={'stored': neighbor_coord_map})
# ... pass pre-captured coords through hider_specs ...
```

### Example 3: Displace middle atoms — id-based selection (robust for any resi encoding)
```python
# Source: editing.py:1535 (alter_state); editing.py:1490 (iterate)
# Collect middle atom ids (robust for insertion-coded resis):
middle_ids = []
cmd.iterate("%s and segi GAME" % obj, "stored.append((ID, resv))",
            space={'stored': middle_ids})
middle_ids = [i for (i, rv) in middle_ids if rv1 < rv < rv2]   # strict middle
# Displace all middle atoms by the SAME offset (rigid translation):
id_sele = "id " + "+".join(str(i) for i in middle_ids)        # "id a+b+c"
cmd.alter_state(hider_state, "%s and segi GAME and %s" % (obj, id_sele),
                "x=x+dx; y=y+dy; z=z+dz",
                space={'dx': dx, 'dy': dy, 'dz': dz})          # editing.py:1535
```

### Example 4: Wizard `do_pick` — read (model, ID, alt, resv) from pk1
```python
# Source: editing.py:1490 (iterate); querying.py:1282 (identify mode=1, for contrast)
def do_pick(self, bondFlag):
    props = []
    cmd.iterate("pk1", "stored.append((model, ID, alt, resv))",
                space={'stored': props})   # one row: the picked atom
    cmd.unpick()                           # clear pk1 (wizard.py:46)
    if not props:
        return
    model, aid, alt, resv = props[0]
    if model != self.target_object:         # non-target -> miss (wizard.py:50)
        return
    self.controller.on_pick(aid, alt=alt, resv=resv)
    cmd.refresh_wizard()
```

### Example 5: `on_pick` — dual lookup + alt/resv gate
```python
# Source: game.py:97 (on_pick); registry.py:157 (get); NEW get_altconf_by_resv
def on_pick(self, picked_id, alt='', resv=None):
    rec = self.registry.get(self.target_obj, picked_id)            # anchor-id hit
    if rec is None and resv is not None:
        rec = self.registry.get_altconf_by_resv(self.target_obj, resv)  # resv-range hit
    if rec is None:
        self._on_log("Miss!"); return
    if rec.is_altconf:
        if alt != rec.alt_tag or not (rec.endpoint_resvs[0] < resv < rec.endpoint_resvs[1]):
            self._on_log("Miss!"); return       # real trace (alt='') or endpoint (resv=rv1/rv2)
    self._mark_found(rec.id, rec)              # rec.id (anchor) NOT picked_id (Pitfall 13)
    remaining = self._remaining()
    self._on_log("Found one! %d remaining" % remaining)
    self._on_remaining_changed(remaining)
    if remaining == 0:
        self.win()
```

### Example 6: `get_altconf_by_resv` (pure, new registry method)
```python
# Source: registry.py:180 (by_rep pattern); pure, no cmd
def get_altconf_by_resv(self, object, resv):
    """Return the alt-conf record with rv1 < resv < rv2 (strict middle), or None.
    Correct because alt-conf hiders have DISJOINT resv ranges (pick_segments contract)."""
    for r in self._records.values():
        if (r.object == object and r.is_altconf and r.endpoint_resvs is not None
                and r.endpoint_resvs[0] < resv < r.endpoint_resvs[1]):
            return r
    return None
```

### Example 7: `_mark_found` with `is_altconf` branch (color the displaced bump, not the real trace)
```python
# Source: game.py:123 (_mark_found); Pitfall 14 (don't color by shared id)
def _mark_found(self, hider_id, rec=None):
    self.registry.mark_found(self.target_obj, hider_id)
    if rec is not None and rec.is_altconf and rec.endpoint_resvs:
        rv1, rv2 = rec.endpoint_resvs
        cmd.color(self._found_color, "%s and segi GAME and resi %d-%d" % (
            self.target_obj, rv1+1, rv2-1))    # the displaced middle bump
    else:
        cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))
```

### Example 8: Cleanup via `backup.restore` (canonical, NOT sentinel remove)
```python
# Source: game.py:274 (cleanup); backup.py:54 (restore); 05-06 caveat 3
# GameController.cleanup (UNCHANGED — already calls backup.restore):
ok = backup.restore(self.target_obj, self._backup_name)   # delete + create two-step
backup.discard(self._backup_name)
# Do NOT call mutation.cleanup_hiders for alt-conf (residual state breaks next round)
```

### Example 9: Multi-state `all_states` toggle (Bug 4 visibility, in `game.py.start`)
```python
# Source: 05-08 Bug 4 fix (commit 335fe3c); all_states is C-side setting (importing.py:1578)
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

### Example 10: Visibility check (cartoon + ribbon on alt-conf atoms)
```python
# Source: mutagenesis.py:570; cmd.py:360 'rep' selector; 05-06 spike checks
# After insert_altconf_cartoon_hider + cmd.show(rep, "obj and segi GAME and alt B"):
assert cmd.count_atoms("%s and segi GAME and alt B and name CA and rep cartoon" % obj) > 0
assert cmd.count_atoms("%s and segi GAME and alt B and polymer" % obj) > 0   # polymer membership
# For ribbon:
assert cmd.count_atoms("%s and segi GAME and alt B and name CA and rep ribbon" % obj) > 0
# Regression guard (05-09): ribbon on GAME but NOT on the rest of the polymer
assert cmd.count_atoms("%s and segi GAME and alt B and rep ribbon" % obj) > 0
assert cmd.count_atoms("%s and polymer and not segi GAME and rep ribbon" % obj) == 0
```

### Example 11: .bcm sidecar extension (to_dict / from_dict / reconcile)
```python
# Source: registry.py:103 (to_dict); registry.py:239 (from_dict); registry.py:288 (reconcile)
# to_dict (HiderRecord):
d = {'id': self.id, 'object': self.object, 'rep': self.rep, 'status': self.status}
if self.pos is not None: d['pos'] = list(self.pos)
if self.is_altconf:
    d['is_altconf'] = True
    d['endpoint_resvs'] = list(self.endpoint_resvs)   # [rv1, rv2]
    d['alt_tag'] = self.alt_tag
return d
# from_dict (HiderRegistry):
reg.register(h['object'], h['id'], h['rep'], h.get('status', 'hidden'), h.get('pos'),
             is_altconf=h.get('is_altconf', False),
             endpoint_resvs=tuple(h['endpoint_resvs']) if 'endpoint_resvs' in h else None,
             alt_tag=h.get('alt_tag', 'B' if h.get('is_altconf') else ''))
# reconcile_with_bcm: restore the 3 fields alongside rep/status (same merge shape)
```

### Example 12: `.pse` `alt` survival smoke (Open Risk 2)
```python
# Source: exporting.py:424 / importing.py:143; Phase 3 smoke pattern
# After insert + register, save, delete, load, assert alt survives:
cmd.save("/tmp/phase11_test.pse")
cmd.delete(obj)
cmd.load("/tmp/phase11_test.pse", obj)
alts = []
cmd.iterate("%s and segi GAME" % obj, "stored.append(alt)", space={'stored': alts})
assert all(a == 'B' for a in alts), "alt='B' did NOT survive .pse reload — Open Risk 2"
```

---

## Open Risks / Needs-Runtime-Verify

Consolidated from both aspects, ordered by priority. Each risk lists: what's unverified, the smoke/human-verify check, and the fallback.

### Risk 1 [MEDIUM-HIGH] — Multi-hider GUI integration (05-08 reverted — methodology failure)
**What's unverified:** The 05-08 Bug 4 fix (source from backup + 2nd+ as new state + `all_states=on`) was headless-verified for 1znf 5-rep + 1ubq 4-cartoon (49/49 smoke), but the GUI human-verify was NEVER completed — 05-08 was reverted because 4 fix cycles each passed headless but failed in the GUI. This is the highest Open Risk: the entire 05-08 revert was due to GUI-only failures that headless smoke cannot catch.
**Check:** GUI-runnable diagnostic (Risk 4) — verify (a) all 2+ hiders are visible, (b) all are clickable, (c) no "no coordinates" zoom warning, (d) cleanup restores the original.
**Fallback:** If multi-hider GUI fails, cap at 1 alt-conf hider per chain (regression to 05-08 latent state) and document the limitation. The single-hider path is spike-verified (10/10 headless).

### Risk 2 [MEDIUM] — Backbone-only alt-conf renders in cartoon (user req 1 variant)
**What's unverified:** The 05-06 spike copied the WHOLE segment (25 atoms including sidechain). Phase 11 uses the `backbone` selector (N, CA, C, O only) per user req 1. The cartoon trace only needs CAs, so backbone-only SHOULD render — but the spike didn't test it.
**Check:** Headless smoke MUST assert `count_atoms("obj and segi GAME and alt B and name CA and rep cartoon") > 0` for a backbone-only copy. Also verify the atom set: `cmd.iterate(tmp, "stored.append(name)", space={'stored': []})` — assert only N/CA/C/O present.
**Fallback:** If 0, fall back to whole-segment copy (without the `backbone` selector) + `cmd.remove("obj and segi GAME and sidechain")` after alter.

### Risk 3 [MEDIUM] — `.pse` `alt` field survival (load-bearing for clean req-3 post-reload)
**What's unverified:** `alt='B'` survival through `.pse` reload is reasoned from the same serialization path as `segi`/`b`/`id` (Phase 3 smoke confirmed those survive), but NOT explicitly smoke-verified for `alt`. If `alt` is lost on reload, the `alt == rec.alt_tag` check fails post-reload → alt-conf hiders unclickable after reload.
**Check:** Headless smoke MUST assert `alt` survives `.pse` round-trip (save → delete → load → iterate `alt` on a segi GAME atom → assert 'B'). See Code Example 12.
**Fallback:** If `alt` is lost, re-apply `alt=rec.alt_tag` on `obj and segi GAME` via `cmd.alter` after `reconcile_with_bcm` (runtime re-tag from the .bcm-stored `alt_tag`). OR drop the `alt` check and score on `is_altconf=True AND resv-in-range` alone (real-trace middle clicks would score — the 05-08 latent limitation returns).

### Risk 4 [MEDIUM-HIGH] — GUI-runnable verification methodology (MANDATORY)
**What's unverified:** Headless PyMOL (`-cq`) defaults `auto_zoom=-1` (off); GUI defaults `auto_zoom=1`. Headless smoke is STRUCTURALLY BLIND to `auto_zoom`, multi-state display, and retroactive coord corruption. The 05-08 attempt failed because 4 fix cycles each passed headless (44/44, 49/49) but failed in the GUI.
**Check:** The Phase 11 plan MUST include a GUI-runnable diagnostic script (pure `pymol.cmd.*`, no Qt) that the user runs via `cmd.exe /c C:\src\run-conda-pymol.bat` WITHOUT `-cq` (or with the GUI) to verify auto-zoom, multi-state display, and coord corruption. The headless smoke is necessary but NOT sufficient.
**Fallback:** No fallback — this is a methodology requirement. Without the GUI diagnostic, the multi-hider path (Risk 1) cannot be validated.

### Risk 5 [MEDIUM] — Multi-state `all_states` visibility after `.pse` reload
**What's unverified:** The 05-08 Bug 4 fix appends 2nd+ hiders as new states + sets `all_states=on`. After `.pse` reload, does `all_states` survive? (It's an object setting — should survive via `set_session`.) Does `reconstruct_from_sentinels` find all hiders across states? (`cmd.iterate` over `segi GAME` is atom-level, not state-specific → should find all.)
**Check:** Headless smoke for a 2-cartoon-hider game: save → load → assert both hiders' sentinels found + both `endpoint_resvs` restored via .bcm.
**Fallback:** If `all_states` doesn't survive, re-apply `cmd.set("all_states", "on", obj)` in `import_state` when 2+ alt-conf records are reconciled.

### Risk 6 [MEDIUM] — Selective middle-only displacement renders as a connected bulge (not a fork)
**What's unverified:** The 05-06 spike displaced ALL atoms uniformly by 2.0 Å. Phase 11 displaces ONLY the middle atoms, leaving endpoints at original coords. The cartoon trace goes: real_CA → alt_CA (coincides) → displaced_middle → alt_CA (coincides) → real_CA. This SHOULD render as a connected tube with a bulge. But if the endpoint-to-displaced-middle CA-CA distance is too long (>5 Å), the tube might look like a straight line (disconnected).
**Check:** GUI human-verify MUST confirm the visual is a connected bulge, not a fork.
**Fallback:** If it forks, reduce displacement to 0.5–1.0 Å. If the middle is not distinguishable, increase to 2.0 Å (the spike-verified ceiling).

### Risk 7 [MEDIUM] — `_mark_found` color-by-resi-range for alt-conf (insertion-coded resis)
**What's unverified:** Coloring `"obj and segi GAME and resi <rv1+1>-<rv2-1>"` colors the middle alt-conf atoms green. If `resi` has insertion codes, the range selector may not match — use the id-based selection (`segi GAME and id <middle-ids>`).
**Check:** GUI human-verify the color shows on the displaced bump (not the real trace). For insertion-coded resis, headless-verify the id-based selection matches.
**Fallback:** Use `segi GAME and id <middle-ids>` (id-list, derived at found-time via `cmd.iterate` + filter) instead of the `resi` range.

### Risk 8 [MEDIUM] — `get_altconf_by_resv` ambiguity if segments overlap (hard dependency on generator)
**What's unverified:** `get_altconf_by_resv` returns the FIRST matching record. If two alt-conf hiders' `endpoint_resvs` ranges overlap (e.g., [10,12] and [11,13]), a click on resv 11.5 is ambiguous.
**Check:** Assert at register time that alt-conf `endpoint_resvs` are pairwise disjoint (defensive).
**Fallback:** Hard dependency on `pick_segments` (generators.py) guaranteeing disjoint resv ranges (advances by `segment_size` on a match). If a future generator allows overlap, `get_altconf_by_resv` must return a list. **Document as a contract.**

### Risk 9 [MEDIUM] — `cmd.create` state args for sourcing from clean backup
**What's unverified:** The 05-06 spike used `create(tmp, seg, 1, 1)` (source_state=1, target_state=1). The 05-08 commit `6e9b7dd` found a `cmd.create` state-args bug (fixed). The exact state-args combo needs re-verification for sourcing from the clean backup (single-state after `collapse_to_single_state`).
**Check:** Headless smoke verify `cmd.create(tmp, "backup and ... and backbone", 1, 1, zoom=0)` produces a temp WITH state-1 coords (single-state backup sourcing).
**Fallback:** If state-args fail, use `cmd.create(tmp, "backup and ... and backbone", zoom=0)` (default states) — verify the temp has the segment atoms.

### Risk 10 [LOW] — `backbone` selector exact atom set
**What's unverified:** The `backbone` selector (cmd.py:364) is C-side. The conventional protein backbone is N, CA, C, O. For non-standard residues or modified backbones, the set might differ.
**Check:** `cmd.iterate(tmp, "stored.append(name)", space={'stored': []})` after `cmd.create(tmp, "...and backbone")` — assert only N/CA/C/O present.
**Fallback:** If O is missing (some selectors exclude carbonyl O), the cartoon trace might still render (primarily needs CAs). If sidechain atoms leak in, add `cmd.remove(tmp, "sidechain")`.

### Risk 11 [LOW] — `all_states=on` interaction with line/stick/sphere hiders
**What's unverified:** Setting `all_states=on` (object-scoped) for multi-hider cartoon/ribbon makes ALL states visible. If line/stick/sphere hiders are in state 1 and cartoon/ribbon hider 2+ are in new states, does clicking still work for state-1 hiders when all_states is on?
**Check:** GUI human-verify (or headless + `cmd.pick` if available) that state-1 line/stick/sphere hiders remain clickable with `all_states=on`.
**Fallback:** Low risk — `all_states` just makes all states visible; clicking still hits the atom in the current state. The 05-08 fix verified this headlessly (1znf 5-rep succeeded).

### Risk 12 [LOW] — `alt='B'` collision with pre-existing real alt-confs
**What's unverified:** If the target structure already has `alt='B'` atoms (real alternate conformers), the hider copies' `alt='B'` is identical to real `alt='B'` by the `alt` field. The `segi GAME` sentinel + `resv`-range still disambiguate (real alt='B' has segi A; `get_altconf_by_resv` only matches registered ranges).
**Check:** Low risk for the demo set (1ubq, 1znf have no alt-confs per 05-06 spike). If a future demo has alt-confs, choose `alt='G'` (stored in `rec.alt_tag`).
**Fallback:** Use `alt='G'` (GAME) instead of `alt='B'`; the registry record carries the chosen `alt_tag`.

### Risk 13 [LOW] — `resv` as a SELECTOR keyword (NOT verified)
**What's unverified:** `resv` IS exposed as an iterate/alter symbol (editing.py:1446) and as a completion keyword (completing.py:25), but NOT verified as a SELECTOR keyword (the standard is `resi`, the string). The id-based middle-atom selection sidesteps this.
**Check:** If a `resv`-range selector is desired for brevity (`resv 11-13`), verify in smoke.
**Fallback:** Use `resi`-range selector (`resi 11-13`) for numeric resis (1ubq, 1znf) — works for the Phase 11 demos. Use the id-based selection for insertion-coded resis.

### Risk 14 [LOW] — `on_pick` signature change backward-compat
**What's unverified:** `on_pick(self, picked_id, alt='', resv=None)` — existing tests call `on_pick(aid)` → `alt=''`, `resv=None` → for `is_altconf=False` records, the alt/resv check is skipped → score. Backward compatible.
**Check:** Audit `tests/test_game_controller.py` for alt-conf test cases (new tests must pass `alt='B'` + a middle `resv` to score).
**Fallback:** No fallback — backward compatible by design. New alt-conf tests are additive.

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 source, directly read at `tmp/pymol-src/modules/pymol/`)
- `editing.py:1424-1473` — `alter(selection, expression, space={})`: symbol table (1444-1449) `name, resn, resi, resv, chain, segi, elem, alt, q, b, ...` (`alt` read-write, no `*`; `ID` read-only); line 1472 calls `_cmd.alter`; `cmd.alter("id=...")` is silent NO-OP (id immutable in C engine).
- `editing.py:1535-1575` — `alter_state(state, selection, expression, space={})`: changes coords (x/y/z); line 1566 `_iterate_prepare_args` for hygienic space; line 1571 `_cmd.alter_state`; state 1-indexed (`int(state) - 1`).
- `editing.py:1578+` — `iterate_state(state, selection, expression, space={})`: reads x/y/z; the ONLY coord reader; CORRUPTED after alt-conf insert (Bug 2).
- `editing.py:1490+` — `iterate(selection, expression, space={})`: reads `ID, alt, resv, color, chain, name` (NO x/y/z); reads `(model, ID, alt, resv)` from `pk1` for scoring.
- `editing.py:40` — atom identify string includes `alt`: `f'...{self.name}`{self.alt}{tail}>'`.
- `editing.py:937-987` — `fuse(selection1, selection2, mode=0, ...)`: mode 3 = "don't move and don't create a bond, just combine" — RENAMES atoms (05-06 spike DISPROVED for alt-conf).
- `editing.py:1457` — "sort after modifying names/chains" warning; `cmd.sort` preserves id.
- `editing.py:800` — `remove(selection)`: removes atoms FROM object.
- `editor.py:354` — multi-field `;`-joined expression idiom for `alter`.
- `creating.py:960-1036` — `create(name, selection, source_state=0, target_state=0, discrete=0, zoom=-1, ...)`: `target_state=-1` appends new state (creating.py:1000-1001); `zoom=0` prevents auto-zoom (Bug 3); same-object create is NO-OP (merge by identity, 05-06 spike); preserves source ids (Phase 3 Q2b).
- `viewing.py:491-526` — `show(rep, selection)`: turns on rep flag; newly-created atoms do NOT inherit shown reps (must `cmd.show` explicitly).
- `querying.py:1269-1300` — `identify(selection, mode=0)`: mode=0 → [id]; mode=1 → `[(model, id)]` (querying.py:1282-1283, NO `alt`, NO `resv`); use `segi GAME` selector (NOT id-diff for alt-conf — Pitfall 3).
- `querying.py:1412-1434` — `count_atoms(selection)`: use `rep cartoon` selector for visibility check.
- `querying.py:74` — `get_unused_name(prefix)`: for temp object names.
- `commanding.py:496` — `delete(name)`: idempotent; for temp cleanup + first half of `backup.restore`.
- `cmd.py:356-365` — selector keyword list: `'alt '` (357), `'backbone'` (364), `'sidechain'` (364), `'polymer'` (363), `'rep '` (360), `'segi '`, `'b '`, `'id '`, `'name CA'`, `'resi '`.
- `preset.py:395` — `show_as('cartoon', 'polymer & ...')`: cartoon shown for `polymer` selection (connectivity-based).
- `wizard/mutagenesis.py:570` — `cartoon = (cmd.count_atoms("(%s & name CA & rep cartoon)" % src_sele) > 0)`: canonical cartoon-visibility check.
- `wizard/mutagenesis.py:474` — the canonical blend pattern (`alter` on copied atoms).
- `importing.py:1578` — `_self.set('all_states', 1, object)`: all_states is object-scoped setting.
- `exporting.py:424` / `importing.py:143` — `.pse` serialization path (Phase 3 smoke confirmed `segi`+`b`+`id` survive; `alt` reasoned to survive by same path — Open Risk 3).

### Secondary (HIGH confidence — 05-06 spike, recovered from git history)
- 05-06 spike (commit `a6fd26a`): `smoke/altconf_spike.py` (314 lines, pure `pymol.cmd.*`, NO Qt) — 10/10 headless ALL PASSED. Recovered from git-history commit `1f22014` (section 12 of 05-RESEARCH.md, removed from current 823-line version). Key findings: WORKING mechanism (create+alter+create+delete), 3 DISPROVED approaches (same-object create NO-OP, fuse mode 3 renames, pseudoatom can't render), 3 critical caveats (identify excludes alt-conf, id matches both alts, residual state breaks re-insertion), sentinel compatibility, `alter_state` displacement verified (dx=2.0).

### Tertiary (MEDIUM confidence — 05-08 bug fixes, headless-verified, GUI human-verify PENDING)
- 05-08 Bug 1 (commit `6d51d12`): alt-conf CAs SHARE ids with originals; `cmd.alter("id=...")` is silent NO-OP; fix = DISJOINT segments.
- 05-08 Bug 2 (commit `6d51d12`): `cmd.create(obj, tmp)` corrupts `iterate_state(1, "id X")` for non-segment atoms; fix = pre-capture coords before insert.
- 05-08 Bug 3 (commit `d146370`): GUI `auto_zoom=1` zooms into segment; fix = `zoom=0` on all `cmd.create`.
- 05-08 Bug 4 (commit `335fe3c`): 2nd alt-conf merge into state 1 corrupts 1st coords; fix = source from clean backup + 2nd+ as new state (`target_state=-1`) + `all_states=on`.
- 05-08 plan (commit `8cd76a3`, on `backup/05-08-attempts` branch): full implementation plan with `insert_cartoon_hider` alt-conf version, `pick_segments`, `_on_start` updates.
- 05-09 rep-forwarding fix (commit `2d487af`, IN HEAD): `cmd.show(rep, ...)` parameterized — prerequisite for ribbon.

### Existing repo code (referenced for extension points)
- `registry.py:56-284` — `HiderRecord` + `HiderRegistry` (Phase 3/8; extended by Phase 11).
- `mutation.py:483-538` — `insert_hider_for_rep` dispatcher (Phase 5; cartoon/ribbon branch replaced).
- `mutation.py:124-159` — `fetch_all_hider_ids` (segi GAME and b < 0) + `cleanup_hiders` (primitive, NOT post-game cleanup).
- `backup.py:54-85` — `restore` (delete+create two-step) + `verify_intact` (count + identity multiset).
- `game.py:48-69` — `start` (snapshot-before-insert invariant).
- `game.py:97-113` — `on_pick` (extended: dual lookup + alt/resv gate).
- `game.py:123` — `_mark_found` (extended: is_altconf branch).
- `game.py:237-272` — `import_state` (reconstruct + reconcile).
- `game.py:274-320` — `cleanup` + `abort_on_error` (both use `backup.restore` — UNCHANGED).
- `persistence.py:45-192` — `build_bcm_dict` / `parse_bcm_dict` / `apply_bcm_dict` (extended, NO version bump).
- `wizard.py:43-54` — `PickWizard.do_pick` (extended: iterate pk1 for alt/resv).

---

## Metadata

**Confidence breakdown:**
- Central mechanism (alt-conf construction → connected cartoon/ribbon): **HIGH** — 05-06 spike 10/10 headless ALL PASSED (recovered from git history).
- Backbone-only variant (user req 1): **HIGH** for the mechanism, **MEDIUM** for the backbone-only variant (spike tested whole-segment; `backbone` selector is standard but not spike-tested) — Open Risk 2.
- Coordinate perturbation (user req 2): **HIGH** for `alter_state` displacement (spike verified dx=2.0); **MEDIUM** for the selective middle-only displacement visual (spike displaced ALL atoms; middle-only is a variant — needs GUI human-verify) — Open Risk 6.
- Scoring (user req 3): **HIGH** — shared-id problem runtime-verified by 05-08 Bug 1; recommended mechanism (dual lookup + alt/resv gate) follows from source semantics + wizard.py structure. `alt` survival through `.pse` is **MEDIUM** (Open Risk 3, load-bearing for clean req-3 post-reload).
- Registry extension: **HIGH** — minimal, pure-layer-preserving, id-keying intact.
- Cleanup & backup/restore: **HIGH** — both aspects independently converged; `backup.restore` (Phase 6) already handles residual alt-conf state — NO change needed.
- .bcm persistence: **MEDIUM** — extension shape reasoned, backward-compat reasoned, not runtime-verified (Open Risk 3 + 5).
- Multi-hider GUI integration (success criterion 3): **MEDIUM** — 05-08 fixes headless-verified but GUI human-verify NEVER completed (05-08 reverted) — Open Risks 1 + 4 (the methodology failure).
- Mixed-rep game (success criterion 4): **HIGH** — dispatch + counting + dual-lookup reasoned from existing code.

**Research date:** 2026-08-15
**Valid until:** 2026-09-14 (30 days — the 05-08 GUI human-verify Open Risks should be resolved by the Phase 11 GUI diagnostic before they expire)
**Synthesizer:** GSD research synthesizer (merged Aspect A + Aspect B)
