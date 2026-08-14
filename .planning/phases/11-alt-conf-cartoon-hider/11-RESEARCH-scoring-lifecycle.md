# Phase 11 Research — ASPECT B: Geometry Perturbation, Scoring & Lifecycle Safety

**Researcher:** B (geometry + scoring + lifecycle)
**Researched:** 2026-08-15
**Domain:** PyMOL 2.5.0 alt-conf coordinate mutation, atom-identification under shared-id alt-conf semantics, registry multi-id scoring, backup/restore/cleanup/.bcm-persistence lifecycle
**Confidence summary:** B1 HIGH (alter_state verified by 05-06 spike + source), B2 HIGH (shared-id problem runtime-verified by 05-08 Bug 1; recommended mechanism follows from source semantics), B3 HIGH (minimal registry extension, pure-layer-preserving), B4 HIGH (segi GAME cleanup confirmed by spike; backup.restore already canonical via Phase 6), B5 HIGH (snapshot-before-insert invariant), B6 MEDIUM (sidecar extension shape; backward-compat reasoned, not runtime-verified), B7 HIGH (dispatch + counting reasoned from existing code), B8 HIGH (smoke path identified, mirrors phase3/5/7/8 smokes).

---

## Summary

Phase 11 replaces the Phase 5 terminal-extension cartoon hider (which renders DISCONNECTED on 1ubq) with "replicate a ≥3-residue mid-chain segment as an alt-conf alternate position, keeping endpoints fixed and displacing the middle residue(s)." The 05-06 spike (`smoke/altconf_spike.py`, commit `a6fd26a`, 10/10 PASS headless) already proved the CONSTRUCTION approach viable: `cmd.create(tmp, seg, 1, 1)` + `cmd.alter(tmp, "alt='B'; segi='GAME'")` + `cmd.create(obj, tmp)` appends true alt-conf pairs that render in cartoon/ribbon, are polymer, and cleanup by `segi GAME`. The 05-08 attempt then hit FOUR bugs (commits `6d51d12`, `d146370`, `335fe3c`): id collision (alt-conf CAs SHARE ids with originals), iterate_state corruption after an alt-conf insert, auto-zoom off-screen, and retroactive coord corruption on the 2nd merge. 05-08 was REVERTED (no SUMMARY). Phase 11 is the clean re-attempt with the user's NEW requirements: (req 2) keep endpoints fixed, move middle; (req 3) click ANY atom on the MIDDLE residues scores, endpoints + real trace do NOT.

The CENTRAL discovery for my aspect (B2): **alt-conf atoms created via `cmd.create(obj, tmp)` SHARE atom `id`s with their originals** (runtime-verified 05-06 spike §12.2 caveat 2 + 05-08 Bug 1 commit `6d51d12`: "alt-conf CAs get the SAME ids as the source segment CAs (e.g. 1ubq segment A:2-4 → alt-conf CAs [10,19,27] == originals [10,19,27])"). This is because `cmd.create` preserves source ids (Phase 3 Q2b resolved) and the temp is a copy of the originals. The wizard's `cmd.identify("pk1", mode=1)` returns `(model, id)` — it does NOT return `alt` (querying.py:1282-1283). So the registry CANNOT distinguish a clicked alt='B' hider atom from the alt='' original that shares its id. The 05-08 approach accepted this as a "latent v1 limitation" (clicking the original tube also scored). **The user's Phase 11 req 3 demands solving it** — clicking the real trace (alt='') or the endpoint alt='B' atoms must NOT score; only middle alt='B' atoms score.

**Primary recommendation (B2):** Modify `PickWizard.do_pick` to read the picked atom's `(model, ID, alt, resv)` from `pk1` via ONE `cmd.iterate` (before `cmd.unpick()`) and pass `(aid, alt, resv)` to `on_pick`. Extend `HiderRecord` with `is_altconf` (bool) + `endpoint_resvs` `(rv1, rv2)` + `alt_tag` (the alt value used, default `'B'`). `on_pick` scores iff: the record is found (by id OR by `get_altconf_by_resv`), AND `alt == rec.alt_tag` (hider, not real), AND `rec.rv1 < resv < rec.rv2` (strictly middle, not endpoint). This satisfies all three branches of req 3 with NO sentinel migration and NO multi-id registry index. The `b=-999` fetch sentinel stays on ONE anchor CA per hider (one record per hider → counts correct); the middle/endpoint split is metadata carried by the registry record + .bcm sidecar, NOT by the sentinel.

---

## B1. Coordinate perturbation — endpoints fixed, middle moved

**Confidence:** HIGH (05-06 spike check 9 verified `alter_state` displacement at runtime; source signature confirmed)

### The exact coordinate-mutation API: `cmd.alter_state`

**Use `cmd.alter_state(state, selection, expression, ...)` (editing.py:1535).** NOT `cmd.translate` (editing.py:1610 — that operates on object TTT matrices or selection-wide transforms, not per-atom-coordinate expressions with selection scoping), NOT `cmd.set_object_ttt` (object-level display matrix, not atom coords), NOT per-atom pseudoatom rebuild.

**Signature** (editing.py:1535-1537):
```python
def alter_state(state, selection, expression, quiet=1, space=None, atomic=1, _self=cmd):
```

**Docstring** (editing.py:1538-1565): `"alter_state" changes atom coordinates and flags over a particular state and selection using the Python evaluator with a temporary namespace for each atomic coordinate.` Example: `alter_state 1, all, x=x+5`. The symbol table is the same as `alter` (editing.py:1444-1449): `x, y, z` are exposed (state-dependent, writable in `alter_state`), plus `name, resn, resi, resv, chain, segi, elem, alt, q, b, ...` and read-only `model*, state*, index*, ID, rank`.

**Expression syntax:** `x = x + dx` (assignment, NOT `x += dx` — the spike used `x=x+2.0` and it worked; `+=` is not verified in the per-atom evaluator namespace and the docstring example uses `x=x+5`). Multi-axis in one call: `"x=x+dx; y=y+dy; z=z+dz"` (semicolon-joined, same idiom as `alter` sentinel — editor.py:354). State is 1-indexed in the Python API; internally `int(state) - 1` (editing.py:1571, 1575).

**Reading middle coords** uses `cmd.iterate_state` (editing.py:1578) — same symbol table, read-only. `cmd.iterate` (editing.py:1490) does NOT expose `x/y/z` (Phase 3 finding, confirmed by 05-08 Bug 2: `iterate_state` is the only coord reader). The pure offset (dx, dy, dz) is computed in Python (generators.py) and injected via `space=`, so reading the middle coords is only needed if we want the offset to be along a structural axis (e.g., Cα-Cα vector or CA-normal); a fixed-axis offset needs NO coord read.

**05-06 spike verification** (commit `1f22014` §12.1 row 9): `cmd.alter_state(1, "obj and segi GAME", "x=x+2.0", space={})` displaced atom 0 from `(36.731, 30.570, 12.645)` to `(38.731, 30.570, 12.645)` — dx=2.0000 verified. So `alter_state` on `segi GAME` works for the copied atoms.

### Safe perturbation magnitude

**Recommendation: 1.0-1.5 Å, fixed-axis (e.g., `x=x+1.2`), applied to ALL atoms of the MIDDLE residues (not just CA, not all GAME atoms).**

Rationale:
- The 05-06 spike §12.4 recommended 1.0-2.0 Å. The lower end (1.0-1.5) keeps the cartoon/ribbon trace visually connected (the tube bridges a ~1.5 Å displacement smoothly; rendering tolerance is Researcher A's scope — I provide the COORDINATE mechanics + a candidate range; A confirms the visual).
- **Apply to ALL atoms of the middle residues (N, CA, C, O, H) by the SAME offset** — a rigid translation of the middle residues. This preserves the middle residues' internal backbone geometry (N-C-CA-C bond angles unchanged) so the cartoon tube through the middle stays well-formed. Displacing ONLY CA would break the backbone geometry (N/C/O left behind) and distort the tube.
- **Do NOT displace the endpoints** — they stay at original coords (coinciding with the real trace), per user req 2 ("keep the position of the two ends"). The cartoon trace then goes: endpoint (original) → middle (displaced ~1.2 Å) → endpoint (original), producing a visible "bump" in the middle that is the hider.
- **Fixed-axis vs random direction:** fixed-axis (`x=x+1.2`) is simplest and spike-verified. A random direction (normalized vector × 1.2 Å) is more natural (no systematic bias) but requires a generator function (pure, in `generators.py`) + the offset must be the SAME for all middle atoms of one hider (so the middle moves as a rigid unit — if each atom got a random independent offset, the backbone would shred). Recommendation: **one random unit vector per hider** (from `generators.py`, seeded), scaled to 1.2 Å, applied to all middle atoms of that hider. This keeps the middle rigid AND avoids axis bias. The offset is injected via `space={'dx': dx, 'dy': dy, 'dz': dz}`.

### "Middle residues" selection expression

For a ≥3-residue segment with endpoint residue-sequence-values `rv1 < rv2`, the middle residues are all residues with `rv1 < resv < rv2` (strictly between). For a 3-residue segment `[10, 11, 12]`: middle = `{11}` (1 residue). For a 5-residue segment `[10, 11, 12, 13, 14]`: middle = `{11, 12, 13}` (3 residues). The endpoints (rv1, rv2) are NOT displaced and NOT scorable.

**Selection construction** — the displacement target is the alt-conf copies (segi GAME) of the middle residues, NOT the originals (segi A). Two robust approaches:

1. **By `id` (most robust, works for any resi including insertion-coded):** after `cmd.create(obj, tmp)`, collect the middle atoms' ids by iterating `obj and segi GAME` and filtering `rv1 < resv < rv2` in Python, then `cmd.alter_state(state, "obj and segi GAME and id <a>+<b>+...", "x=x+dx; y=y+dy; z=z+dz", space={...})`. The `and segi GAME` restricts to the alt-conf copies (originals have segi A → excluded), so `id` (shared with originals) is unambiguous within the `segi GAME` intersection. This mirrors the `insert_cartoon_hider` id-diff pattern (mutation.py:412-415).

2. **By `resi` range (simpler, works for numeric resis):** `cmd.alter_state(state, "%s and segi GAME and resi %d-%d" % (obj, rv1+1, rv2-1), "x=x+dx...", space={...})`. The `resi` selector accepts ranges (`resi 11-13`). This is correct for structures with simple numeric resis (1ubq, 1znf). For insertion-coded resis (rare in the demo set), fall back to approach 1. **Recommendation: use approach 1 (id-based) as the primary; it is robust for all resi encodings and reuses the verified id-selection idiom.**

**`resv` selector note:** `resv` IS exposed as an iterate/alter symbol (editing.py:1446) and as a completion keyword (completing.py:25), but I did NOT verify `resv` as a SELECTOR keyword (the standard selector is `resi`, the string). The `id`-based approach sidesteps this uncertainty. Mark `resv`-as-selector LOW confidence; do not rely on it.

### The state argument (multi-hider dependency on Researcher A)

The 05-08 Bug 4 finding (commit `335fe3c`): `cmd.create(obj, tmp)` merging a 2nd+ alt-conf into state 1 (which already holds the 1st alt-conf) CORRUPTS the 1st alt-conf's coords retroactively. The 05-08 fix: 1st alt-conf merges into state 1 (clean); 2nd+ appends as a NEW state (`target_state=-1`, creating.py:1000-1001). So each hider's atoms live in their OWN state, and `alter_state` displacement runs in each hider's own state. **The `state` argument to `alter_state` depends on Researcher A's construction (which state this hider was appended to).** `insert_altconf_cartoon_hider` must receive + use the correct state. For a single-hider game, state=1. For multi-hider, state = the hider's assigned state (1, 2, 3, ...). The registry record should store the state too (see B3) so `on_pick`-time queries (if any) and post-reload use the right state.

---

## B2. Marking middle residues for scoring (THE CENTRAL SCORING QUESTION)

**Confidence:** HIGH (shared-id problem runtime-verified by 05-08 Bug 1; recommended mechanism follows from source semantics + wizard.py structure)

### The shared-id problem (the load-bearing fact)

**Runtime-verified (05-06 spike §12.2 caveat 2 + 05-08 Bug 1 commit `6d51d12`):** alt-conf atoms created via `cmd.create(obj, tmp)` (where `tmp` is a copy of real segment atoms) **SHARE atom `id`s with their originals.** Quote from `6d51d12`: "alt-conf CAs SHARE ids with the originals (PyMOL alt-conf semantics) — the appended alt-conf CAs get the SAME ids as the source segment CAs (e.g. 1ubq segment A:2-4 → alt-conf CAs [10,19,27] == originals [10,19,27])." Root cause: `cmd.create` preserves source ids (Phase 3 Q2b resolved: "cmd.create copies preserve atom ids"); the temp was a copy of the originals; so the appended atoms keep the originals' ids.

**Consequence for the pick path:** `PickWizard.do_pick` (wizard.py:43-54) reads the picked atom via `cmd.identify("pk1", mode=1)` → `[(model, id)]` (querying.py:1282-1283 — mode=1 returns `(object_name, id)` tuples, NOT alt, NOT resv). When the player clicks the displaced alt='B' middle CA, `identify` returns `(obj, shared_id)`. When the player clicks the alt='' ORIGINAL middle CA (the real trace, not the hider), `identify` ALSO returns `(obj, shared_id)`. **The registry, keyed by `(object, id)`, cannot distinguish the two clicks.** The 05-08 approach registered the shared anchor id and accepted that "clicking the ORIGINAL tube at the hider's resi also registers a find" as a "Known v1 limitation" (commit `6d51d12`). **Phase 11 req 3 explicitly rejects this** — clicking the real trace or an endpoint must NOT score.

### Three mechanisms — ranked, with the shared-id constraint applied

#### Mechanism 1: Register all middle-residue atom ids (the brief's option 1)
**VERDICT: FAILS due to shared ids.** Registering `(obj, middle_N_id)` for every middle atom: when the player clicks the ORIGINAL middle N (alt='', real trace), `identify` returns `middle_N_id` → registry hit → score. **False positive on the real trace.** The registry cannot mark "only the alt='B' copy of this id is scorable" because the id is identical. Reject.

#### Mechanism 2: A second sentinel/marker on middle atoms only (the brief's option 2)
**VERDICT: WORKS but requires a marker the pick path can read AND that survives .pse reload; pick path still needs `alt` to disambiguate shared id.** Options for the marker: (a) a distinct `b` value (b=-888 middle, b=0 endpoint, b=-999 anchor) — but `fetch_all_hider_ids` uses `segi GAME and b < 0` (AGENTS.md), which would return ALL middle atoms (b=-888) + anchor (b=-999) → multiple records per hider on reconstruct → breaks "one hider = one count." Migrating the fetch selector to `b < -500` (anchor only) is a sentinel migration (risk + touches `mutation.py`/AGENTS.md). (b) a distinct `q` (occupancy) value (q=-1 middle, q=0 endpoint) — `q` is writable (editing.py:1446) and NOT in the fetch selector → no sentinel migration. But `q` is NOT recoverable from the `segi GAME + b=-999` sentinel after .pse reload → the .bcm sidecar must store the middle/endpoint split anyway. AND the pick path still cannot tell alt='' (real) from alt='B' (hider) by id alone — it MUST read `alt` from `pk1`. So mechanism 2 reduces to "mechanism 3 + a redundant atom marker." The marker adds an atom-field write + a .bcm field but does not remove the need for the `alt` read. **Reject as redundant; mechanism 3 alone suffices.**

#### Mechanism 3 (RECOMMENDED): Derive middle-ness at pick time from `alt` + `resv` vs the hider's endpoint resv range
**VERDICT: RECOMMENDED. Minimal, no sentinel migration, no multi-id index, robust to shared ids, round-trips via .bcm.**

**The mechanism:**
1. **`PickWizard.do_pick` reads `(model, ID, alt, resv)` from `pk1`** via ONE `cmd.iterate` BEFORE `cmd.unpick()` (wizard.py:45-46 currently does `identify` then `unpick`; swap to iterate-then-unpick). `pk1` is a named selection containing exactly the ONE picked atom (the C layer sets it on click), so `iterate` returns exactly one row — the picked atom's `alt` ('' for real, 'B' for hider) and `resv` (the residue's int sequence value). Pass `(aid, alt, resv)` to `controller.on_pick`.
2. **`on_pick(aid, alt='', resv=None)` does a DUAL lookup + alt/resv check:**
   ```python
   rec = self.registry.get(self.target_obj, aid)                  # anchor-id hit (sphere/line/stick OR alt-conf anchor)
   if rec is None and resv is not None:
       rec = self.registry.get_altconf_by_resv(self.target_obj, resv)  # alt-conf non-anchor middle atom
   if rec is None:
       self._on_log("Miss!"); return
   if rec.is_altconf:
       # Alt-conf: only score if clicked the hider's alt-tag AND a MIDDLE residue (strictly between endpoints)
       if alt != rec.alt_tag or not (rec.endpoint_resvs[0] < resv < rec.endpoint_resvs[1]):
           self._on_log("Miss!"); return
   # score (sphere/line/stick always pass here; alt-conf passes only for middle alt='B')
   self._mark_found(aid)
   ...
   ```
3. **`HiderRegistry.get_altconf_by_resv(object, resv)`** (NEW method): returns the alt-conf record whose `endpoint_resvs[0] < resv < endpoint_resvs[1]` (strict middle), or `None`. Correct because alt-conf hiders have DISJOINT resv ranges (Researcher A's `pick_segments` guarantees non-overlapping segments — generators.py `pick_segments` advances by `segment_size` on a match), so the resv lookup is unambiguous. (If two alt-conf hiders ever overlapped, this would be ambiguous — A's disjoint-segment contract prevents that. Document as a dependency.)

**Why this satisfies ALL three branches of req 3:**

| Click target | `alt` | `resv` | `registry.get(id)` | `get_altconf_by_resv` | `alt==tag?` | `rv1<resv<rv2?` | SCORE? |
|---|---|---|---|---|---|---|---|
| alt='B' middle CA/N/C/O (displaced hider, anchor residue) | 'B' | middle_rv | **hit** (anchor id registered) | — | YES | YES | **YES** ✓ |
| alt='B' middle atom (displaced hider, NON-anchor middle residue) | 'B' | middle_rv | None (id not registered) | **hit** (resv in range) | YES | YES | **YES** ✓ |
| alt='B' endpoint CA (hider endpoint, coincides with real trace) | 'B' | rv1 or rv2 | None (endpoint id not registered) | None (rv not strictly between) | — | — | **NO** ✓ |
| alt='' real middle CA (the real trace, NOT the hider) | '' | middle_rv | hit (anchor id shared) OR None | hit (resv in range) | **NO** (''≠'B') | — | **NO** ✓ |
| alt='' real endpoint CA | '' | rv1/rv2 | None | None | — | — | **NO** ✓ |
| sphere/line/stick pseudoatom (unique id, alt='') | '' | 9001 | **hit** (unique id) | — | rec.is_altconf=False → skip check | — | **YES** ✓ |

The anchor-id registration + the resv-range fallback together cover "click ANY atom on the MIDDLE residues" (anchor residue atoms via id; non-anchor middle residue atoms via resv). The `alt == rec.alt_tag` check rejects the real trace (alt=''). The `rv1 < resv < rv2` strict check rejects endpoints. **All three branches of req 3 satisfied.**

### Why `pk1` iterate returns the picked atom's `alt` unambiguously

`pk1` is a named selection set by the C layer to the SINGLE picked atom (SceneMouse.cpp; the wizard's `do_pick`/`do_select` path operates on `pk1`). `cmd.iterate("pk1", ...)` evaluates the expression per atom in the selection — for a one-atom selection, exactly one row. So `alt` is the picked atom's alt ('' or 'B'), not a multiset. `cmd.identify("pk1", mode=1)` (the current path) returns `(model, id)` and loses `alt`; `cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={...})` preserves it. **HIGH confidence** — `identify` already works on `pk1` (wizard.py:45), and `iterate` uses the same selection mechanism (editing.py:1490, selector.process).

### The `alt_tag` choice + collision risk

The 05-06 spike used `alt='B'` (verified on 1ubq/1znf, which have no pre-existing alt-confs). If the target structure ALREADY has `alt='B'` atoms (real alternate conformers), setting the hider copies to `alt='B'` would make them indistinguishable from real alt='B' atoms via the `alt` field alone — BUT the `segi GAME` sentinel + the `resv`-in-range check still disambiguate (real alt='B' atoms have segi A, not GAME; and `get_altconf_by_resv` only matches registered hider ranges). However, the `cmd.alter(tmp, "alt='B'; segi='GAME'")` sets alt on the TEMP (not obj), so real alt='B' atoms in obj are untouched. The collision risk is low. **Recommendation: default `alt_tag='B'` (spike-verified); store `alt_tag` in the registry record so `on_pick` checks `alt == rec.alt_tag` (not hardcoded 'B'); if a future structure has real alt='B' + the `segi GAME` intersection is somehow ambiguous, the insert can choose `alt='G'` (GAME) and the record carries it.** This is forward-compatible with zero added complexity. The .bcm stores `alt_tag` (default 'B' for v1 sidecars).

---

## B3. Registry extension — one hider, many scorable ids (MINIMAL)

**Confidence:** HIGH (extension reasoned from current registry.py; pure-layer + id-keying preserved)

### Current shape (registry.py:56-284)

`HiderRecord(id, object, rep, status, pos)`, `__slots__=('id','object','rep','status','pos')`, keyed by `(object, id)` in `HiderRegistry._records` (OrderedDict). One id per record. `register/get/all/remove/by_rep/counts_by_rep/mark_found/to_dict/from_dict/reconstruct_from_sentinels/reconcile_with_bcm`. `reconstruct_from_sentinels` sets `rep=None` (sentinel carries no rep); `reconcile_with_bcm` restores `rep`+`status` from .bcm. `fetch_all_hider_ids` (mutation.py:124) iterates `segi GAME and b < 0` → one `(model, id)` per sentinel atom → one record per hider (b=-999 on ONE anchor CA).

### Proposed minimal extension (preserves ALL Phase 3/8 invariants)

**Add THREE fields to `HiderRecord` + ONE method to `HiderRegistry`. No multi-id index. No sentinel migration. `id`-keying intact.**

```python
class HiderRecord(object):
    __slots__ = ('id', 'object', 'rep', 'status', 'pos',
                 'is_altconf',        # NEW: bool, default False (sphere/line/stick)
                 'endpoint_resvs',    # NEW: (rv1, rv2) tuple or None (alt-conf middle range)
                 'alt_tag')           # NEW: str, default 'B' (the alt value on hider copies)
                                    #   ('' for non-altconf; rec.alt_tag checked by on_pick)
    def __init__(self, id, object, rep, status=HIDER_STATUS_HIDDEN, pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''):
        ...
        self.is_altconf = is_altconf
        self.endpoint_resvs = endpoint_resvs   # None or (int, int)
        self.alt_tag = alt_tag                 # '' for non-altconf; 'B' default for altconf
```

**`HiderRegistry` changes:**
- `register(object, id, rep, ..., is_altconf=False, endpoint_resvs=None, alt_tag='')` — passes new fields to `HiderRecord`. Backward compatible (defaults).
- `get(object, id)` — **UNCHANGED.** Still keyed by `(object, id)` (the anchor id for alt-conf). This is the primary lookup (anchor-id hits).
- **NEW `get_altconf_by_resv(object, resv)`** — returns the first alt-conf record with `endpoint_resvs is not None and endpoint_resvs[0] < resv < endpoint_resvs[1]` (strict middle), or `None`. Used by `on_pick` for non-anchor middle-atom clicks. Pure (iterates `self._records.values()`). O(N) over records — fine (N = hider count, small).
- `counts_by_rep` — **UNCHANGED.** Iterates `self._records.values()` (one record per hider). One alt-conf hider = one count, NOT N counts for N middle atoms. (The middle atoms are NOT separate records; they're derived at pick time via `get_altconf_by_resv`.)
- `mark_found(object, id)` — **UNCHANGED.** Sets status on the record at `(object, id)`. For alt-conf, the caller passes the anchor id (or the clicked id — but `on_pick` calls `_mark_found(aid)` where `aid` is the clicked id; for a non-anchor middle click, `aid` is NOT the anchor id → `mark_found(obj, non_anchor_id)` would KeyError!). **FIX:** `on_pick` must call `_mark_found(rec.id)` (the RECORD's anchor id), NOT `_mark_found(aid)` (the clicked id). This is a one-line change in `game.py:on_pick` (currently `self._mark_found(picked_id)` → change to `self._mark_found(rec.id)`). For sphere/line/stick, `rec.id == picked_id` (unique id) → unchanged. For alt-conf non-anchor middle, `rec.id` = anchor id (the record's key) → mark_found sets the record found. Correct.
- `remove(object, id)` — **UNCHANGED** (removes by anchor id; alt-conf records are keyed by anchor id).
- `to_dict` — add `is_altconf`, `endpoint_resvs` (as a list or None), `alt_tag` to each hider dict. Omit fields when default (keeps v1 sidecar compact for sphere/line/stick).
- `from_dict` — read `is_altconf` (default False), `endpoint_resvs` (default None, normalize list→tuple), `alt_tag` (default '' for non-altconf, 'B' if `is_altconf` and absent). Tolerant of v1 sidecars without these fields (backward compat).
- `reconstruct_from_sentinels` — sets `is_altconf=False, endpoint_resvs=None, alt_tag=''` for every rebuilt record (the sentinel `segi GAME + b=-999` carries NO middle/endpoint/alt info — same limitation as `rep=None` per Phase 3 Open Risk 6). The .bcm reconciles (B6).
- `reconcile_with_bcm` — restore `is_altconf`, `endpoint_resvs`, `alt_tag` from the matching .bcm entry (alongside `rep`, `status`). Same merge shape as existing `rep`+`status` restore (registry.py:288-346). Validate `endpoint_resvs` is a 2-int tuple or None; `alt_tag` is a single char or ''; `is_altconf` is bool. On malformed .bcm entry → leave defaults (degraded but playable, same as `bad_rep` handling).

### Why NOT a multi-id index (`clickable_ids: [...]`)

The brief framed B3 as "one hider → a SET of scorable ids." A `_id_index: {(object, any_clickable_id) → record}` would support "register all middle ids, look up any." But:
1. **Shared ids break it:** the middle alt='B' atom's id == the original alt='' atom's id. Registering `(obj, middle_N_id)` means clicking the ORIGINAL middle N (alt='') → `_id_index` hit → score. False positive. The index cannot mark "only alt='B' copy scorable." So the index alone doesn't solve req 3 — you STILL need the `alt` check at pick time.
2. **Reconstruct needs .bcm anyway:** `fetch_all_hider_ids` (b=-999 on ONE anchor) returns one id per hider. To rebuild a multi-id index, fetch would need ALL middle ids → b=-999 on all middle atoms → multiple records per hider → counts wrong. Or the .bcm stores `clickable_ids` and the index is rebuilt from .bcm (not sentinels) → but then a missing .bcm loses all middle ids → on_pick misses non-anchor clicks. The resv-range approach degrades gracefully (missing .bcm → `get_altconf_by_resv` returns None → non-anchor middle clicks miss, but the anchor CA still scores via `get(id)` → game still winnable by clicking the anchor CA).
3. **More state, more sync:** a secondary index must stay in sync with `_records` on register/remove/mark_found. The resv-range approach has NO secondary state — the range is on the record, looked up by iteration.

**The resv-range + alt approach is strictly less state, degrades gracefully, and is robust to shared ids. Recommend it over the multi-id index.**

### `id`-keying preserved (Phase 3 invariant)

The registry primary key stays `(object, anchor_id)` where `anchor_id` is the alt-conf anchor CA's id (shared with the original, but disambiguated at pick time by `alt`). The registry NEVER keys on `index` (Pitfall 4, querying.py:1315). `get_altconf_by_resv` keys on `resv` (a lookup, not a registry key — resv ranges are disjoint per A's `pick_segments` contract, so the lookup is a function, not a 1:1 map). No `index` anywhere. Invariant intact.

---

## B4. Cleanup — `segi GAME` removes alt-conf cleanly; altLoc-leakage prevention; verify_intact passes

**Confidence:** HIGH (05-06 spike checks 10-11 + 05-08 Bug 4 fix confirmed; backup.restore already canonical via Phase 6)

### `segi GAME` cleanup removes ONLY the copies (originals have segi A)

`mutation.cleanup_hiders` (mutation.py:131-159) does `cmd.remove(f"{object} and segi GAME")` (editing.py:800 — removes atoms FROM the object, not the object). The alt-conf copies carry `segi='GAME'`; the original real atoms carry `segi='A'` (or their original segi). The `and segi GAME` intersection restricts removal to the copies. **Even though endpoint copies COINCIDE in coordinates with the real atoms**, they are DISTINCT atom records (different `alt` — 'B' vs '' — and different `segi` — GAME vs A), so `remove("segi GAME")` deletes the copies and leaves the originals. 05-06 spike check 10: `after_count=660, orig_count=660` — cleanup restored the count exactly. HIGH confidence.

### BUT cleanup_hiders (sentinel remove) is INSUFFICIENT for repeated rounds — backup.restore is canonical (already in place)

**05-06 spike §12.2 caveat 3 (runtime-verified):** "Residual alt-conf state after `cmd.remove('segi GAME')` interferes with re-insertion. After a create+alter+create flow, if the alt-conf atoms are removed by `cmd.remove('segi GAME')` and then a SECOND create+alter+create is attempted on the same object, the `segi GAME` iterate finds 0 CAs (even though `count_atoms` shows 25 new atoms)." The alt-conf "slots" or records left behind confuse the next `cmd.create(obj, tmp)`.

**Resolution (already shipped in Phase 6):** `GameController.cleanup` (game.py:274-305) does NOT call `mutation.cleanup_hiders` — it calls `backup.restore(self.target_obj, self._backup_name)` (delete+create two-step, backup.py:54-64). The backup was snapshotted in `start()` BEFORE any mutation, so it has NO alt-conf atoms. `delete(target) + create(target, backup)` returns the object to its pre-game state — no residual alt-conf state. **The current cleanup path already handles this.** Phase 11 does NOT need to change cleanup. CONFIRM: the snapshot-before-insert invariant (B5) must hold for the alt-conf path too (it does — `game.start` snapshots first, then the insert loop).

**For the abort path:** `GameController.abort_on_error` (game.py:307-320) also uses `backup.restore`. Same — handles alt-conf.

**Recommendation: do NOT use `mutation.cleanup_hiders` (sentinel remove) as the post-game cleanup when alt-conf hiders are present. Use `backup.restore` (already the Phase 6+ canonical path). Keep `mutation.cleanup_hiders` available as a primitive (smoke tests, edge cases) but do NOT wire it into `GameController.cleanup`.** This is the current state — no change needed for Phase 11, but DOCUMENT it as a hard rule (alt-conf requires backup.restore, not sentinel-remove, for repeated rounds).

### altLoc-leakage prevention (the exact alter scoping)

The `alt='B'` tag is set on the TEMP object, NOT on `obj` directly. The 05-06 spike sequence (§12.3):
```python
cmd.create(tmp, segment_sele, 1, 1)          # 1. copy segment to temp (tmp has only the copies)
cmd.alter(tmp, "alt='B'; segi='GAME'", space={})  # 2. set alt+segi on TEMP (originals in obj untouched)
cmd.create(obj, tmp)                          # 3. append the tagged copies to obj
cmd.delete(tmp)                               # 4. clean up temp
```
**The `alter` selection is `tmp` (the temp object), NOT `obj and name N and resi X`.** A too-broad `alter("obj and resi X", "alt='B'")` would hit the ORIGINAL residue X (alt='') too — LEAKING the alt tag onto real atoms. The temp-first approach eliminates this: the originals are never in the alter's selection. HIGH confidence.

**Post-create alter scoping rule:** if ANY alter must run on `obj` after `cmd.create(obj, tmp)` (e.g., the b=-999 anchor set), restrict to `segi GAME` (which only the copies carry): `cmd.alter("%s and segi GAME and name CA and resi %d" % (obj, anchor_rv), "b=-999.0", space={})`. The `and segi GAME` prevents hitting the original CA (segi A) that shares the resi. The 05-06 spike §12.2 caveat 2 confirms: `cmd.alter("obj and id 227", "b=-999.0")` would hit BOTH alt='' and alt='B' (shared id) — **use `segi GAME and resi <rv>` (NOT `id <id>`) for the anchor b=-999 set.** This is the exact scoping rule.

### verify_intact passes after restore

`backup.verify_intact` (backup.py:69-85) compares atom count + `(resn, resi, name, chain, segi)` multiset between target and backup. After `backup.restore` (delete+create from the pre-game backup), the target is an atom-for-atom copy of the backup → counts match + multisets match (the backup has no segi GAME atoms). **Passes.** The alt-conf atoms (added after the snapshot) are gone. HIGH confidence. (Note: `verify_intact` does NOT compare coords — Phase 3 finding: `iterate` doesn't expose x/y/z; count + identity suffices because `create` copies coords bit-for-bit. The alt-conf displacement is irrelevant to `verify_intact` since the backup has no alt-conf atoms at all.)

---

## B5. Backup.restore interaction (Phase 7 dependency)

**Confidence:** HIGH (snapshot-before-insert invariant already in `game.start`; restore = delete+create two-step, backup.py:54-64)

### The snapshot-before-insert invariant (load-bearing for alt-conf)

`GameController.start` (game.py:48-69): `self._backup_name = backup.snapshot(self.target_obj)` runs BEFORE the `for (payload, rep) in hider_specs: mutation.insert_hider_for_rep(...)` loop. So the backup is a pristine pre-hider snapshot — NO alt-conf atoms, NO displaced coords, NO hint colors. This invariant is the entire safety net (PyMOL Open Source has NO undo — editor.py:25-36 no-op stub). **Phase 11 MUST preserve this: snapshot before ANY alt-conf construction.** Since `insert_altconf_cartoon_hider` is called inside the existing `insert_hider_for_rep` dispatch within the `start` loop, the snapshot already precedes it. No change needed.

### Restore returns to pre-hider state (alt-conf atoms gone)

`backup.restore` (backup.py:54-64) = `cmd.delete(target_obj)` + `cmd.create(target_obj, backup_name)`. The backup has no alt-conf atoms (snapshot was pre-insert). After restore, the target is a fresh copy of the backup → zero alt-conf atoms, zero GAME segi atoms, all original atoms at original coords. **The 05-08 Bug 4 retroactive-coord-corruption problem (commit `335fe3c`) is NOT triggered by restore** — restore doesn't merge into an alt-conf-laden state; it DELETES the target first, then creates fresh from a clean backup. HIGH confidence. This is exactly why Phase 3 §Q2 mandated delete+create (not single-call create) for restore — it sidesteps all merge semantics.

### 05-08 Bug 4 dependency on Researcher A: source the temp from the CLEAN backup

The 05-08 Bug 4 fix (commit `335fe3c`) found that `cmd.create(tmp, seg, 1, 1)` sourcing the segment FROM an alt-conf-laden object (after the 1st cartoon/ribbon insert) produces a temp whose atoms have NO state-1 coords (invisible hider). The fix: **source the segment from the clean pre-insertion backup** (`backup.snapshot` from `GameController.start`), so `cmd.create(tmp, backup_seg, 1, 1)` produces a temp WITH state-1 coords. **This means `insert_altconf_cartoon_hider` must receive the `backup_name` parameter** and source the segment from `backup_name`, NOT from `obj` (which may already have alt-conf atoms from a prior hider in the same round). `insert_hider_for_rep` passes `backup_name` through; `game.start` passes `self._backup_name`. This is a construction detail (Researcher A's scope) but the LIFECYCLE constraint is: **the backup must exist before ANY alt-conf insert, and the insert must source from the backup.** I flag this as a hard dependency on A's construction signature (`insert_altconf_cartoon_hider(object, backup_name, chain, rv1, rv2, ...)`).

### altLoc fidelity edge case (does not arise in the happy path)

The backup (pre-insert) has no alt-conf atoms, so `create(target, backup)` doesn't need to preserve altLoc — there are no alt-conf atoms to preserve. The invariant "snapshot before insert" guarantees this. If a BUG ever snapshotted AFTER an insert (backup contaminated with alt-conf atoms), `create` preserves source ids (Phase 3 Q2b) AND alt (alt is an atom property, same serialization path as segi/b — Phase 3 smoke confirmed segi+b+id survive `create`; alt is a sibling field in the same atom record). So even the bug case would round-trip alt. But the happy path never exercises this. Mark MEDIUM (reasoned, not runtime-verified for alt specifically).

---

## B6. .bcm sidecar round-trip for multi-id/middle-structure

**Confidence:** MEDIUM (extension shape reasoned from persistence.py + registry.py; backward-compat reasoned, not runtime-verified)

### Current .bcm shape (Phase 8, persistence.py)

`build_bcm_dict` (persistence.py:45-110) produces `{'magic', 'version': 1, 'kind', 'target_object', 'started', 'timer_elapsed', 'reveal_count', 'hint_count', 'found_color', 'found_color_rgb', 'registry': controller.registry.to_dict(), 'setup'}`. `registry.to_dict()` (registry.py:227-237) = `{'version': 1, 'hiders': [record.to_dict() ...]}`. Each hider dict: `{id, object, rep, status, pos?}`. `parse_bcm_dict` (persistence.py:113-145) refuses `version > BCM_VERSION (1)`. `apply_bcm_dict` (persistence.py:150-192) sets controller fields + calls `registry.reconcile_with_bcm(bcm_hiders)`. `reconcile_with_bcm` (registry.py:288-346) restores `rep`+`status`+`pos` by matching `(object, id)`.

### Proposed extension (backward-compatible v1 — NO version bump)

**Add `is_altconf`, `endpoint_resvs`, `alt_tag` to each hider dict as OPTIONAL fields.** Keep `version: 1` (parse_bcm_dict still accepts v1). `to_dict` omits them when default (sphere/line/stick hiders → compact v1 shape unchanged). `from_dict`/`reconcile_with_bcm` read them with defaults (`is_altconf=False, endpoint_resvs=None, alt_tag=''` for non-altconf; `alt_tag='B'` if `is_altconf=True` and `alt_tag` absent).

**Why no version bump:** the new fields are ADDITIVE and optional. A v1 sidecar produced by the current (Phase 8) code has no `is_altconf`/`endpoint_resvs`/`alt_tag` → `from_dict`/`reconcile` treat every hider as non-altconf (`is_altconf=False`) → the registry works for sphere/line/stick exactly as today. A v1 sidecar produced by Phase 11 code includes the fields for alt-conf hiders → `reconcile` restores them. A future Phase 11 sidecar loaded by Phase 8 code → Phase 8's `from_dict` ignores unknown fields (it reads only `id/object/rep/status/pos`) → alt-conf hiders load as `is_altconf=False` → they score by anchor id only (non-anchor middle clicks miss) → degraded but playable. **No parse_bcm_dict change needed** (it validates magic+version only, not per-hider fields). **Recommendation: keep `BCM_VERSION = 1`; add the fields as optional.** This is the lowest-risk migration.

**Extended hider dict (alt-conf):**
```json
{
  "id": 227, "object": "1ubq", "rep": "cartoon", "status": "hidden",
  "is_altconf": true,
  "endpoint_resvs": [10, 12],
  "alt_tag": "B"
}
```
Non-altconf hiders omit `is_altconf`/`endpoint_resvs`/`alt_tag` (or set `is_altconf: false`).

### import_state re-establishes the middle/endpoint split

`GameController.import_state` (game.py:237-272) sequence:
1. `reconstruct_registry()` → `reconstruct_from_sentinels` (registry.py:261-284) rebuilds records from `fetch_all_hider_ids` (one record per anchor CA, `rep=None`, `status='hidden'`, AND now `is_altconf=False, endpoint_resvs=None, alt_tag=''`).
2. `persistence.apply_bcm_dict(self, bcm_dict)` → `reconcile_with_bcm(bcm_hiders)` restores `rep`+`status` AND the new `is_altconf`+`endpoint_resvs`+`alt_tag` by matching `(object, id)`.
3. Defensive found-color re-apply (game.py:265-268).
4. `backup.snapshot(self.target_obj)` (fresh post-import backup).

**After reconcile, the alt-conf records have `is_altconf=True, endpoint_resvs=(rv1, rv2), alt_tag='B'` → `on_pick`'s `get_altconf_by_resv` works → non-anchor middle clicks score post-reload.** The middle/endpoint structure is NOT recoverable from sentinels (the `segi GAME + b=-999` sentinel carries no resv range) — the .bcm is the ONLY source. **This mirrors Phase 8 Open Risk 6 (rep not recoverable from sentinels; .bcm reconciles).** A missing/corrupt .bcm → alt-conf hiders load as `is_altconf=False` → only the anchor CA scores (clickable via the shared id; the `alt` check is skipped because `is_altconf=False`) → game is winnable but the "click any middle atom" UX is lost. Degraded but playable — same graceful-degradation philosophy as Phase 8.

### Does `alt` survive .pse reload? (MEDIUM — needs smoke verification)

The Phase 3 smoke confirmed `segi` + `b` + `id` survive `.pse` (PITFALLS.md "PSE — .pse round-trip id/sentinel stability: RESOLVED"). `alt` is an atom property in the same `ObjectMolecule` atom record (same serialization path via `_cmd.get_session`/`set_session`, exporting.py:424 / importing.py:143). By the same mechanism, `alt='B'` should survive. **MEDIUM confidence** (reasoned from the same serialization path, not explicitly smoke-verified for `alt`). The Phase 11 smoke MUST assert `alt` survives (B8). If `alt` does NOT survive reload, the `alt == rec.alt_tag` check fails post-reload → alt-conf hiders unclickable after reload → the .bcm-only fallback (`is_altconf=True` but `alt` lost) would need a different scoring path. **Mitigation if alt is lost:** the .bcm-stored `endpoint_resvs` + `is_altconf` still let `get_altconf_by_resv` find the record by resv; `on_pick` could score on `is_altconf=True AND resv-in-range` ALONE (drop the `alt` check) — but then clicking the real-trace middle CA (alt='' if alt lost, OR alt='B' if alt survived) would score. The `alt` check is the clean disambiguator; losing it forces the resv-only check (real-trace middle clicks would score — the 05-08 latent limitation returns). **So `alt` survival is load-bearing for the clean req-3 satisfaction post-reload. Verify in smoke.**

---

## B7. Mixed-rep game — registry + on_pick across reps (success criterion 4)

**Confidence:** HIGH (dispatch + counting reasoned from existing mutation.py + registry.py)

### Alt-conf slots into `insert_hider_for_rep` without breaking sphere/line/stick

`mutation.insert_hider_for_rep` (mutation.py:483-538) dispatches per rep: `spheres` → `insert_hider` + show spheres; `lines`/`sticks` → `insert_line_stick_hider`; `cartoon`/`ribbon` → `insert_cartoon_hider` (terminal-extension, Phase 5). **Phase 11 replaces the `cartoon`/`ribbon` branch body** with a call to the new `insert_altconf_cartoon_hider` (construction = Researcher A). The dispatcher signature + return (the anchor CA's stable id) is unchanged — `game.start`'s loop (game.py:64-67) does `aid = mutation.insert_hider_for_rep(...); self.registry.register(object=self.target_obj, id=aid, rep=rep)` and now ALSO passes `is_altconf=(rep in ('cartoon','ribbon')), endpoint_resvs=(rv1,rv2) if is_altconf else None, alt_tag='B' if is_altconf else ''`. **The `spheres`/`lines`/`sticks` branches are UNTOUCHED** — they still produce single-id, `is_altconf=False` records. So a mixed-rep game (sphere + line/stick + cartoon + ribbon) registers: sphere records (is_altconf=False, unique id), line/stick records (is_altconf=False, unique id), cartoon records (is_altconf=True, shared anchor id, endpoint_resvs), ribbon records (is_altconf=True, shared anchor id, endpoint_resvs). All coexist in the registry.

### `counts_by_rep` counts hiders (records), NOT atoms — correct for mixed rep

`counts_by_rep` (registry.py:190-210) iterates `self._records.values()` — ONE record per hider. A cartoon hider (with 3 middle residues × ~4 backbone atoms = ~12 middle atoms) is ONE record → `counts_by_rep['cartoon'] += 1`, NOT +12. A ribbon hider is ONE record → `counts_by_rep['ribbon'] += 1`. Sphere/line/stick are ONE record each. **Mixed-rep counts are correct with NO change to `counts_by_rep`.** The middle-atom scoring is a pick-time derivation (`get_altconf_by_resv`), invisible to counts.

### `on_pick` scores correctly per rep (dual lookup + alt/resv gate)

For a mixed-rep game, `on_pick(aid, alt, resv)`:
- Sphere click: `aid` = unique pseudoatom id → `registry.get` hit → `rec.is_altconf=False` → skip alt/resv check → score.
- Line/stick click: `aid` = unique bonded-pseudoatom id → `registry.get` hit → `is_altconf=False` → score.
- Cartoon middle CA click (alt='B', resv=middle): `aid` = shared anchor id → `registry.get` hit (the cartoon record) → `is_altconf=True` → `alt=='B'` AND `rv1<resv<rv2` → score.
- Cartoon endpoint CA click (alt='B', resv=rv1): `registry.get` None (endpoint id not registered) → `get_altconf_by_resv` None (rv1 not strictly between) → miss.
- Cartoon real-trace CA click (alt='', resv=middle): `registry.get` hit (shared id) → `is_altconf=True` → `alt!='B'` → miss. OR `registry.get` None → `get_altconf_by_resv` hit → `is_altconf=True` → `alt!='B'` → miss.
- Ribbon: same as cartoon (the record's `rep` is 'ribbon'; the scoring logic is rep-agnostic — it keys on `is_altconf`, not `rep`).

**All four reps score correctly in a mixed game.** Success criterion 4 (lifecycle half) satisfied: all tracked in the registry, all clickable via the dual lookup, counts per-rep correct.

### `_mark_found` uses `rec.id` (anchor), not the clicked id (B3 fix)

`game.py:on_pick` (game.py:113) currently calls `self._mark_found(picked_id)`. For alt-conf non-anchor middle clicks, `picked_id` ≠ the record's anchor id → `mark_found(obj, picked_id)` would KeyError (registry.py:212-223 — `self._records[(object, int(id))]` raises KeyError on absent key). **Change `on_pick` to `self._mark_found(rec.id)`** — for sphere/line/stick, `rec.id == picked_id` (unique id, no change); for alt-conf, `rec.id` = anchor id (the record's key) → mark_found sets the record found. The `cmd.color(self._found_color, "obj and id %s" % (hider_id))` in `_mark_found` (game.py:123) then colors the ANCHOR atom — for alt-conf, the anchor CA (shared id) gets colored. **BUT the shared-id means `cmd.color("obj and id 227", "green")` colors BOTH the alt='' original AND the alt='B' copy** (same id). The original would turn green too — confusing (a real atom turns green). **FIX:** `_mark_found` for alt-conf should color by `segi GAME and resi <anchor_rv>` (restricts to the alt-conf copy), NOT by shared id. OR color ALL middle alt-conf atoms (`segi GAME and resi <rv1+1>-<rv2-1>`) so the whole displaced bump turns green (clearer feedback). I recommend: for `is_altconf` records, `_mark_found` colors `"obj and segi GAME and resi <rv1+1>-<rv2-1>"` (the middle residues, all alt-conf copies) — the whole visible bump turns green. For non-altconf, color by id (unchanged). This is a small `_mark_found` branch on `rec.is_altconf`. Document it.

---

## B8. Headless-smoke-verifiable path

**Confidence:** HIGH (mirrors smoke/phase3_smoke.py, phase5_smoke.py, phase7_smoke.py, phase8_smoke.py — all run headlessly via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`)

### The smoke script (`smoke/phase11_smoke.py`, pure `pymol.cmd.*`, NO Qt)

The smoke exercises the FULL alt-conf lifecycle headlessly. It does NOT use `PickWizard` (Qt-free) — it calls `controller.on_pick(aid, alt, resv)` directly with simulated pick values. The wizard modification (iterate pk1 for alt/resv) is Qt-free too, but testing `on_pick` directly is simpler + deterministic.

**Smoke outline (exact assertions):**
```python
# Setup
cmd.fetch("1ubq", async_=0)
obj = "1ubq"
mutation.collapse_to_single_state(obj)   # 05-05: multi-state breaks verify_intact
orig_count = cmd.count_atoms(obj)

# --- Lifecycle: snapshot -> construct alt-conf -> register -> score -> cleanup ---
import biochemeleon.backup as backup, biochemeleon.mutation as mutation
from biochemeleon import registry as regmod
from biochemeleon.game import GameController

controller = GameController(obj)
# 1. Snapshot (MUST precede insert — no undo)
bname = backup.snapshot(obj)
# 2. Construct alt-conf segment (mid-chain 3-residue, e.g. resv 23-25 on chain A)
#    (Researcher A's insert_altconf_cartoon_hider; here we call it via the dispatcher)
payload = (bname, 'A', 23, 25)   # (backup_name, chain, rv1, rv2) — A's signature
aid = mutation.insert_hider_for_rep(obj, 'cartoon', payload, 'H000')
# 3. Register with alt-conf metadata
controller.registry.register(obj, aid, 'cartoon',
                              is_altconf=True, endpoint_resvs=(23, 25), alt_tag='B')
# 4. Assertions: structure + sentinel + polymer + rep
check("alt-conf: count += 25 (3 residues backbone)", cmd.count_atoms(obj) == orig_count + 25)
check("alt-conf: 1 anchor CA with b<0 (fetch sentinel)", cmd.count_atoms("%s and segi GAME and b < 0" % obj) == 1)
check("alt-conf: 25 GAME atoms (cleanup target)", cmd.count_atoms("%s and segi GAME" % obj) == 25)
check("alt-conf: GAME atoms in polymer", cmd.count_atoms("%s and segi GAME and polymer" % obj) == 25)
check("alt-conf: cartoon rep shown on GAME", cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) > 0)
# 5. Read the anchor + middle atom ids for the score simulation
game_ids = []
cmd.iterate("%s and segi GAME" % obj, "stored.append((ID, alt, resv))", space={'stored': game_ids})
anchor_id = aid
middle_ids = [(i, a, r) for (i, a, r) in game_ids if 23 < r < 25]   # middle (resv 24)
endpoint_ids = [(i, a, r) for (i, a, r) in game_ids if r == 23 or r == 25]
# 6. Simulate on_pick on a MIDDLE alt='B' atom -> SCORE
controller.on_pick(middle_ids[0][0], alt='B', resv=middle_ids[0][2])
check("score: middle alt='B' atom -> found", controller.registry.get(obj, anchor_id).status == 'found')
# 7. Reset status; simulate on_pick on an ENDPOINT alt='B' atom -> NO SCORE
controller.registry.mark_found(obj, anchor_id) if False else None  # reset
controller.registry._records[(obj, anchor_id)].status = 'hidden'   # reset for test
controller.on_pick(endpoint_ids[0][0], alt='B', resv=endpoint_ids[0][2])
check("score: endpoint alt='B' atom -> NO find", controller.registry.get(obj, anchor_id).status == 'hidden')
# 8. Simulate on_pick on a REAL (alt='') middle atom -> NO SCORE
#    Find a real atom with the same resv as a middle residue (alt='')
real_middle = []
cmd.iterate("%s and name CA and resv 24 and not segi GAME" % obj, "stored.append((ID, alt, resv))", space={'stored': real_middle})
if real_middle:
    controller.on_pick(real_middle[0][0], alt='', resv=real_middle[0][2])
    check("score: real (alt='') middle atom -> NO find", controller.registry.get(obj, anchor_id).status == 'hidden')
# 9. Cleanup via backup.restore (NOT sentinel remove — 05-06 caveat 3)
ok = controller.cleanup()   # calls backup.restore
check("cleanup: restore returns True", ok)
check("cleanup: count back to orig", cmd.count_atoms(obj) == orig_count)
check("cleanup: verify_intact", backup.verify_intact(obj, bname))
# 10. .pse round-trip + alt survival (MEDIUM flag — B6)
cmd.save("/tmp/phase11_test.pse")
# (register + insert again, save, delete, load, reconstruct, reconcile, check alt)
```

### Headless-verifiable vs GUI-only split

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

**GUI-only (human-verify, NOT headless):**
- The cartoon/ribbon tube renders CONNECTED (not disconnected) — human eye (Researcher A's rendering scope).
- The displaced middle bump is visible + clickable — human eye.
- The endpoint residues visually coincide with the real trace (no visible seam) — human eye.
- The found-color (green) shows on the displaced bump (not on the real trace) — human eye.
- Mixed-rep visual coexistence (sphere + line/stick + cartoon + ribbon all visible) — human eye.

---

## Standard Stack (this aspect)

No new libraries. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer.

| API | Source location | Purpose | Why standard |
|-----|-----------------|---------|--------------|
| `cmd.alter_state` | editing.py:1535 | Displace middle-residue coords (x=x+dx) | The ONLY per-atom-coordinate write API with selection scoping; 05-06 spike verified |
| `cmd.iterate_state` | editing.py:1578 | Read middle/anchor coords (x/y/z) | The ONLY coord read API (iterate doesn't expose x/y/z — Phase 3 finding) |
| `cmd.iterate` | editing.py:1490 | Read (ID, alt, resv) from pk1 / segi GAME | Read-only per-atom eval; `alt`+`resv`+`ID` in symbol table (editing.py:1446) |
| `cmd.create` | creating.py:960 | Copy segment to temp; append alt-conf to obj | `target_state=-1` appends new state (creating.py:1000); preserves source ids (Phase 3 Q2b) |
| `cmd.alter` | editing.py:1424 | Set `alt='B'; segi='GAME'` on temp; `b=-999` on anchor | Multi-field `;`-joined (editor.py:354); `alt` writable (editing.py:1446) |
| `cmd.remove` | editing.py:800 | `remove("obj and segi GAME")` (primitive; NOT the post-game cleanup) | Removes atoms FROM object by selection |
| `cmd.delete` + `cmd.create` | commanding.py:496 + creating.py:960 | `backup.restore` two-step (canonical cleanup) | Phase 3 §Q2; avoids merge ambiguity; 05-06 caveat 3 requires this for repeated rounds |
| `cmd.identify` | querying.py:1269 | `mode=1` → `[(model, id)]` from pk1 (current wizard path) | Returns id (shared for alt-conf — that's WHY we add iterate for alt) |
| `cmd.count_atoms` | querying.py:1412 | Smoke assertions (sentinel, polymer, rep) | `rep <name>` + `polymer` + `segi GAME` selectors |
| `cmd.sort` | (C-dispatched) | After `alter` of segi/alt | editing.py:1457 warning; defensive |

**Installation:** None. No `pip install`. (opencode.json denies `pip*`/`apt*`/`conda*`.)

---

## Architecture Patterns (this aspect)

### Module placement (strict dependency direction, AGENTS.md)

```
setup_state.py (PURE) ── GAME_REPS
      ↑
registry.py (PURE) ── HiderRecord (+ is_altconf/endpoint_resvs/alt_tag) + HiderRegistry
      │                (+ get_altconf_by_resv; to_dict/from_dict/reconcile extended)
      ↑
mutation.py (cmd) ── insert_altconf_cartoon_hider (construction = A; lifecycle calls here)
      │              (cleanup_hiders stays as a PRIMITIVE; NOT wired into game.cleanup)
backup.py (cmd) ── snapshot/restore/discard/verify_intact (UNCHANGED — already handles alt-conf)
      ↑
persistence.py (PURE) ── build_bcm_dict/apply_bcm_dict (extended to_dict/from_dict; NO version bump)
      ↑
game.py (cmd, orchestrator) ── on_pick(aid, alt='', resv=None) + _mark_found(rec.id, is_altconf branch)
wizard.py (cmd) ── do_pick iterates pk1 for (model, ID, alt, resv); passes to on_pick
generators.py (PURE) ── pick_segments (A's scope) + offset vector generator (one unit vector per hider)
```

### Proposed function signatures (this aspect)

```python
# registry.py (PURE — extended)
class HiderRecord:
    __slots__ = ('id', 'object', 'rep', 'status', 'pos',
                 'is_altconf', 'endpoint_resvs', 'alt_tag')
    def __init__(self, id, object, rep, status='hidden', pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''): ...

class HiderRegistry:
    def register(self, object, id, rep, status='hidden', pos=None,
                 is_altconf=False, endpoint_resvs=None, alt_tag=''): ...
    def get_altconf_by_resv(self, object, resv):
        """Return the alt-conf record with rv1 < resv < rv2 (strict middle), or None. Pure."""
    # to_dict/from_dict/reconcile_with_bcm extended for the 3 new fields (optional, default)

# game.py (orchestrator — extended)
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
    self._mark_found(rec.id, rec)   # pass rec so _mark_found can branch on is_altconf

def _mark_found(self, hider_id, rec=None):
    """If rec.is_altconf: color 'obj and segi GAME and resi <middle-range>' (the displaced bump).
    Else: color 'obj and id <hider_id>' (unchanged, sphere/line/stick)."""
    self.registry.mark_found(self.target_obj, hider_id)
    if rec is not None and rec.is_altconf and rec.endpoint_resvs:
        rv1, rv2 = rec.endpoint_resvs
        cmd.color(self._found_color, "%s and segi GAME and resi %d-%d" % (self.target_obj, rv1+1, rv2-1))
    else:
        cmd.color(self._found_color, "%s and id %s" % (self.target_obj, hider_id))

# wizard.py (cmd — extended do_pick)
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

- **Registering all middle atom ids as separate records** → counts_by_rep inflates (N atoms = N counts) + shared-id false positives. Use ONE record per hider (anchor id) + `get_altconf_by_resv` for non-anchor middle clicks.
- **Using `mutation.cleanup_hiders` (sentinel remove) as the post-game cleanup for alt-conf** → 05-06 caveat 3: residual alt-conf state breaks the next round's insert. Use `backup.restore` (already canonical).
- **`cmd.alter("obj and resi X", "alt='B'")`** → leaks alt onto the original residue X. ALWAYS alter the TEMP (before create) or scope with `and segi GAME` (after create).
- **`cmd.alter("obj and id <shared_id>", "b=-999")`** → hits BOTH alt='' and alt='B' (shared id). Use `obj and segi GAME and resi <rv>` for the anchor set.
- **`on_pick` calling `_mark_found(picked_id)` for alt-conf** → KeyError if picked_id is a non-anchor middle id. Use `_mark_found(rec.id)` (the anchor id).
- **Coloring a found alt-conf hider by shared id** → colors the real-trace original too. Use `segi GAME and resi <middle-range>`.

---

## Don't Hand-Roll (this aspect)

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Coordinate displacement | Manual per-atom `cmd.set_atom_coord` loop or `cmd.translate` | `cmd.alter_state(state, sele, "x=x+dx; y=y+dy; z=z+dz", space={...})` (editing.py:1535) | Per-atom-coordinate expression evaluator with selection scoping; spike-verified; `translate` is object-matrix-oriented |
| Distinguishing clicked alt-conf from real (shared id) | A custom "alt lookup" via `cmd.identify` + heuristics | `cmd.iterate("pk1", "...alt...", space={})` reads the picked atom's `alt` directly (editing.py:1490) | `pk1` is a one-atom selection; `iterate` returns exactly the picked atom's `alt`; `identify` drops `alt` |
| Middle-residue selection | A Python loop over all atoms filtering resv | `cmd.iterate("obj and segi GAME", "...resv...", space={})` + Python filter, OR `resi rv1+1-rv2-1` selector | C-side selection + iterate is fast (Pitfall 12); the id-based filter is robust for insertion-coded resi |
| Post-game cleanup for alt-conf | `cmd.remove("segi GAME")` (sentinel remove) | `backup.restore` (delete+create two-step, backup.py:54) | 05-06 caveat 3: sentinel remove leaves residual alt-conf state that breaks re-insertion; restore is the canonical Phase 6+ path |
| Registry multi-id scoring | A secondary `_id_index` dict + sync on register/remove | `get_altconf_by_resv` (resv-range lookup) + `alt` check at pick time | Shared ids break the index (false positives); resv-range is stateless + degrades gracefully |

**Key insight:** the shared-id problem (alt-conf atoms share ids with originals) means NO id-based mechanism can distinguish hider from real. The disambiguation MUST come from a non-id atom property read at pick time (`alt` via `iterate` on `pk1`). Do not hand-roll an id-based disambiguator; use the `alt` field.

---

## Common Pitfalls (this aspect)

### Pitfall B-1: Assuming alt-conf atoms get NEW unique ids (they DON'T)
**What goes wrong:** The registry registers the alt-conf CA's id expecting it to be unique; clicking the original real CA (which shares the id) also scores a find.
**Why:** `cmd.create` preserves source ids (Phase 3 Q2b); the temp was a copy of the originals; appended alt-conf atoms keep the originals' ids. Runtime-verified 05-06 spike §12.2 caveat 2 + 05-08 Bug 1 (`6d51d12`): "alt-conf CAs get the SAME ids as the source segment CAs."
**How to avoid:** Read `alt` from the picked atom (`cmd.iterate("pk1", "...alt...")`); score only if `alt == rec.alt_tag`. NEVER assume an alt-conf atom's id is unique.
**Warning signs:** Clicking the real trace scores a find; counts_by_rep is correct but the game is trivially winnable by clicking real atoms.

### Pitfall B-2: `cmd.identify("pk1", mode=1)` returns `(model, id)` — NO `alt`
**What goes wrong:** The wizard passes only `id` to `on_pick`; `on_pick` cannot tell alt='' (real) from alt='B' (hider).
**Why:** `cmd.identify` mode=1 returns `(object_name, id)` tuples (querying.py:1282-1283) — no `alt`, no `resv`. The 05-08 wizard used `identify` and accepted the shared-id ambiguity as a "latent limitation."
**How to avoid:** Use `cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={...})` BEFORE `cmd.unpick()` to read the picked atom's `alt` + `resv`. Pass all four to `on_pick`.
**Warning signs:** The wizard passes only `id`; alt-conf hiders unclickable-distinguishable from real trace.

### Pitfall B-3: Using `mutation.cleanup_hiders` (sentinel remove) for alt-conf post-game cleanup
**What goes wrong:** After `cmd.remove("segi GAME")`, the count is restored BUT the next `cmd.create(obj, tmp)` (New Game) fails — `segi GAME` iterate finds 0 CAs even though count shows new atoms.
**Why:** 05-06 spike §12.2 caveat 3 (runtime-verified): residual alt-conf "slots"/records left by `remove("segi GAME")` confuse the next `create(obj, tmp)`.
**How to avoid:** `GameController.cleanup` uses `backup.restore` (delete+create two-step) — already canonical since Phase 6 (game.py:274-305). Do NOT wire `cleanup_hiders` into `game.cleanup`. Keep `cleanup_hiders` as a smoke/primitive only.
**Warning signs:** New Game after an alt-conf round fails to insert / shows 0 hiders.

### Pitfall B-4: altLoc leakage via too-broad `alter` selection
**What goes wrong:** `cmd.alter("obj and resi X", "alt='B'")` sets `alt='B'` on the ORIGINAL residue X (alt='') too — the real trace becomes an alt-conf.
**Why:** `resi X` matches both the original (alt='') and the copy (alt='B') after `create(obj, tmp)`.
**How to avoid:** Set `alt` on the TEMP object BEFORE `create(obj, tmp)` (`cmd.alter(tmp, "alt='B'; segi='GAME'")`). After create, scope any alter with `and segi GAME` (only copies carry it): `cmd.alter("obj and segi GAME and name CA and resi <rv>", "b=-999")`.
**Warning signs:** Real atoms gain `alt='B'`; `cmd.iterate("obj and alt B and not segi GAME")` returns non-zero.

### Pitfall B-5: Setting `b=-999` by shared `id` (hits both alt='' and alt='B')
**What goes wrong:** `cmd.alter("obj and id 227", "b=-999")` sets b=-999 on BOTH the original CA (alt='', segi A) AND the alt-conf CA (alt='B', segi GAME) — the original becomes a fetch-sentinel too → `fetch_all_hider_ids` returns 2 atoms → 2 registry records per hider → counts wrong.
**Why:** `id <id>` matches both alt versions (shared id; 05-06 §12.2 caveat 2).
**How to avoid:** Set b=-999 with `and segi GAME and resi <anchor_rv>` (NOT `and id <id>`). The `segi GAME` restricts to the copy.
**Warning signs:** `fetch_all_hider_ids` returns >1 atom per hider; counts_by_rep inflated.

### Pitfall B-6: `on_pick` calling `_mark_found(picked_id)` for a non-anchor middle click
**What goes wrong:** `mark_found(obj, non_anchor_id)` raises KeyError (the non-anchor id isn't a registry key) → crash on a valid middle click.
**Why:** The registry keys by the anchor id; non-anchor middle atoms are scored via `get_altconf_by_resv` (which returns the record), but `mark_found` takes an id.
**How to avoid:** `on_pick` calls `self._mark_found(rec.id, rec)` (the RECORD's anchor id), NOT `_mark_found(picked_id)`.
**Warning signs:** Crash (KeyError) when clicking a non-anchor middle atom (e.g., the N of a middle residue, or the CA of a 5-residue segment's non-anchor middle residue).

### Pitfall B-7: Coloring a found alt-conf hider by shared id (colors the real trace too)
**What goes wrong:** `cmd.color('green', "obj and id 227")` colors both the alt='' original AND the alt='B' copy → a real atom turns green → confusing.
**Why:** Shared id (B-1).
**How to avoid:** For `is_altconf` records, color by `"obj and segi GAME and resi <rv1+1>-<rv2-1>"` (the displaced middle bump), NOT by id. Branch `_mark_found` on `rec.is_altconf`.
**Warning signs:** A real-trace residue turns green when a cartoon hider is found.

### Pitfall B-8: Displacing only the CA (not all middle-residue atoms)
**What goes wrong:** The cartoon tube through the middle residue distorts (N/C/O left at original coords, CA displaced) → broken backbone geometry → the tube renders weirdly.
**Why:** The cartoon trace follows CA but the backbone N-C-Cα-C geometry must stay coherent for a clean tube.
**How to avoid:** Displace ALL atoms of the middle residues (N, CA, C, O, H) by the SAME offset (rigid translation). Selection: `segi GAME and resi <middle-range>` (all atoms) or `segi GAME and id <all-middle-ids>`.
**Warning signs:** The displaced bump looks jagged/distorted, not a smooth tube offset.

### Pitfall B-9: `alter_state` on the wrong state (multi-hider)
**What goes wrong:** Displacing hider 2's middle atoms in state 1 (where hider 1 lives) corrupts hider 1's coords (05-08 Bug 4, `335fe3c`).
**Why:** `cmd.create(obj, tmp)` merging a 2nd+ alt-conf into state 1 corrupts the existing alt-conf coords retroactively.
**How to avoid:** Each hider's atoms live in their OWN state (1st: state 1; 2nd+: `target_state=-1` new state). `alter_state(state=<hider's state>, ...)` uses the correct state. The registry record stores the state (or it's tracked in `insert_altconf_cartoon_hider`).
**Warning signs:** Hider 1 disappears/distorts after hider 2 is inserted.

---

## Code Examples (this aspect)

### B1: Displace middle-residue atoms (alter_state, id-based selection)
```python
# Source: editing.py:1535 (alter_state); 05-06 spike §12.3 step 7
# Collect middle atom ids (robust for any resi encoding):
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

### B2: Wizard do_pick — read (model, ID, alt, resv) from pk1
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

### B2/B3: on_pick — dual lookup + alt/resv gate
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
    self._mark_found(rec.id, rec)              # rec.id (anchor) NOT picked_id
    remaining = self._remaining()
    self._on_log("Found one! %d remaining" % remaining)
    self._on_remaining_changed(remaining)
    if remaining == 0:
        self.win()
```

### B3: get_altconf_by_resv (pure, new registry method)
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

### B4: Construction — alt-conf create+alter+create (sourced from clean backup)
```python
# Source: 05-06 spike §12.3; creating.py:960; editing.py:1424; 05-08 Bug 4 fix (335fe3c)
segment_sele = "%s and chain %s and resi %d-%d" % (backup_name, chain, rv1, rv2)
tmp = cmd.get_unused_name('_bchm_alt')          # avoid collisions
cmd.create(tmp, segment_sele, 1, 1)             # copy from CLEAN backup (Bug 4 fix)
cmd.alter(tmp, "alt='B'; segi='GAME'", space={})  # set alt+sentinel on TEMP (no leakage)
cmd.create(obj, tmp, target_state=target_state) # append; target_state=1 (1st) or -1 (new state, 2nd+)
cmd.delete(tmp)
cmd.sort(obj)                                    # defensive (editing.py:1457)
# Set b=-999 on ONE anchor CA (segi GAME + resi, NOT id — shared id):
cmd.alter("%s and segi GAME and name CA and resi %d" % (obj, rv1),
          "b=-999.0", space={})
# Displace middle (B1 example above)
# Show rep:
cmd.show(rep, "%s and segi GAME" % obj)          # viewing.py:491
```

### B4: Cleanup via backup.restore (canonical, NOT sentinel remove)
```python
# Source: game.py:274 (cleanup); backup.py:54 (restore); 05-06 caveat 3
# GameController.cleanup (UNCHANGED — already calls backup.restore):
ok = backup.restore(self.target_obj, self._backup_name)   # delete + create two-step
backup.discard(self._backup_name)
# Do NOT call mutation.cleanup_hiders for alt-conf (residual state breaks next round)
```

### B6: .bcm sidecar extension (to_dict / from_dict / reconcile)
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

---

## Open Risks / Needs-Runtime-Verify (this aspect)

1. **`alt` field survival through `.pse` reload (MEDIUM — B6).** Reasoned from the same serialization path as `segi`/`b`/`id` (exporting.py:424 / importing.py:143 — Phase 3 smoke confirmed segi+b+id survive), but NOT explicitly smoke-verified for `alt`. **Load-bearing for clean req-3 satisfaction post-reload** (the `alt == rec.alt_tag` check needs `alt` to survive). If `alt` is lost on reload, the fallback is `is_altconf=True AND resv-in-range` alone (real-trace middle clicks would score — the 05-08 latent limitation returns). **Mitigation: the Phase 11 smoke MUST assert `alt` survives `.pse` round-trip** (save → delete → load → iterate `alt` on a segi GAME atom → assert 'B'). If it fails, document the fallback + add a runtime `alt` re-apply on import (re-set `alt=rec.alt_tag` on `obj and segi GAME` via `cmd.alter` after `reconcile_with_bcm`).

2. **`resv` as a SELECTOR keyword (LOW — B1).** I did NOT verify `resv` works as a selector (the standard is `resi`). The id-based middle-atom selection (iterate + filter + `id a+b+c`) sidesteps this. If a `resv`-range selector is desired for brevity (`resv 11-13`), verify in smoke. The `resi`-range selector (`resi 11-13`) works for numeric resis (mutation.py uses `resi %d`); use it as the simpler alternative for numeric-resi structures.

3. **Multi-state + `all_states` for multi-hider visibility (MEDIUM — B1/B5, dependency on A).** The 05-08 Bug 4 fix appends 2nd+ hiders as new states + sets `all_states=on` so all hiders are visible. After `.pse` reload, does `all_states` survive? (It's an object setting — should survive via `set_session`.) Does `reconstruct_from_sentinels` find all hiders across states? (`cmd.iterate` over `segi GAME` is atom-level, not state-specific → should find all.) **Verify in smoke** for a 2-cartoon-hider game: save → load → assert both hiders' sentinels found + both `endpoint_resvs` restored via .bcm.

4. **`alt='B'` collision with pre-existing real alt-confs (LOW — B2).** If the target structure already has `alt='B'` atoms (real alternate conformers), the hider copies' `alt='B'` is identical to real `alt='B'` by the `alt` field. The `segi GAME` sentinel + `resv`-range still disambiguate (real alt='B' has segi A; `get_altconf_by_resv` only matches registered ranges). BUT `cmd.alter("obj and segi GAME and ...", ...)` is safe (segi-restricted). Low risk for the demo set (1ubq, 1znf have no alt-confs per 05-06 spike). If a future demo has alt-confs, choose `alt='G'` (stored in `rec.alt_tag`). Document.

5. **`_mark_found` color-by-resi-range for alt-conf (MEDIUM — B7).** Coloring `"obj and segi GAME and resi <rv1+1>-<rv2-1>"` colors the middle alt-conf atoms green. If `resi` has insertion codes, the range selector may not match — use the id-based selection (`segi GAME and id <middle-ids>`). The middle-ids list is derivable at found-time via `cmd.iterate("obj and segi GAME", "...resv...")` + filter, but that's a per-found-hider iterate (cheap, N is small). Verify the color shows on the displaced bump (GUI-only).

6. **`get_altconf_by_resv` ambiguity if segments overlap (MEDIUM — B3, dependency on A).** `get_altconf_by_resv` returns the FIRST matching record. If two alt-conf hiders' `endpoint_resvs` ranges overlap (e.g., [10,12] and [11,13]), a click on resv 11.5 is ambiguous. Researcher A's `pick_segments` (generators.py) produces NON-overlapping segments (advances by `segment_size` on a match). **Hard dependency: A's generator MUST guarantee disjoint resv ranges.** If a future generator allows overlap, `get_altconf_by_resv` must return a list (or the ranges must be stored disjoint + asserted at register time). Document as a contract.

7. **`on_pick` signature change backward-compat (LOW — B2).** `on_pick(self, picked_id, alt='', resv=None)` — existing tests call `on_pick(aid)` → `alt=''`, `resv=None` → for `is_altconf=False` records, the alt/resv check is skipped → score. Backward compatible. But tests that construct alt-conf records MUST pass `alt='B'` + a middle `resv` to score. Audit `tests/test_game_controller.py` for alt-conf test cases (new tests).

8. **`cmd.create(tmp, segment_sele, 1, 1)` state args (MEDIUM — B4, dependency on A).** The 05-06 spike used `create(tmp, seg, 1, 1)` (source_state=1, target_state=1). The 05-08 commit `6e9b7dd` found a `cmd.create` state-args bug (fixed). Verify the exact state-args combo works for sourcing from the clean backup (single-state after `collapse_to_single_state`). The spike verified `1, 1` on a single-state 1ubq. Re-verify in the Phase 11 smoke (single-state backup sourcing).
