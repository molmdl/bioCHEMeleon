# Phase 5: Line/Stick & Cartoon Generators — Research

**Researched:** 2026-08-08
**Domain:** PyMOL 2.5.0 polymer-trace rendering (cartoon/ribbon), bond rendering (lines/sticks), `cmd.attach_amino_acid` / `cmd.fuse` / `cmd.bond` mutation APIs, hider coloring & blend-vs-sentinel tradeoff
**Confidence:** HIGH for line/stick + cartoon "extend-at-terminal" path (verified against `editor.py`, `editing.py`, `viewing.py`, `mutagenesis.py`, `preset.py`, `cmd.py` at `tmp/pymol-src/modules/pymol/`); MEDIUM for cartoon Cα-color-follows-atom and segi-doesn't-break-trace (runtime-verify in smoke); LOW for the loop-replica alt-position variant (deferred — not needed for MVP).

---

## 1. Executive Summary

Phase 5 extends the proven Phase 3/4 insert-and-register mechanism (`mutation.insert_hider` + `GameController.start(hider_specs)`) to three new representations. The **single most consequential finding** is that the three reps have *fundamentally different rendering requirements*, so they need three different insertion primitives — there is no one-size-fits-all `pseudoatom`:

| Rep | Renders what | Insertion primitive | Verified source |
|-----|--------------|---------------------|-----------------|
| **lines / sticks** | **Bonds** between atoms (a lone atom is invisible) | `cmd.pseudoatom` + `cmd.bond(hider, neighbor)` | editing.py:694-735 ("atoms must both be within the same object"); PITFALLS.md Minor: "lines and sticks render bonds" |
| **cartoon / ribbon** | **Polymer trace** over consecutive N-C-Cα backbone with `ss` flags (a lone pseudoatom is invisible — Pitfall 8) | `cmd.attach_amino_acid(terminus_N_or_C, 'gly', ss=4)` (fuses a real residue with backbone geometry via `cmd.fuse(...,2)`) | editor.py:85-270; preset.py:395 (`show_as('cartoon','polymer & ...')`) |
| **spheres** (Phase 4) | Any atom with a vdw radius | `cmd.pseudoatom` (Phase 4, unchanged) | — |

**Primary recommendation:** Implement **two new cmd-coupled insert functions** in `mutation.py` — `insert_line_stick_hider(object, neighbor_id, ...)` (pseudoatom + `cmd.bond`) and `insert_cartoon_hider(object, terminus_id, ...)` (`attach_amino_acid` + sentinel-alter) — dispatched per-rep from a new `mutation.insert_hider_for_rep(...)` wrapper, so `GameController.start` stays a thin `(pos-or-anchor, rep)` loop. Keep `generators.py` PURE for the *geometry/selection* decisions (neighbor sampling offsets, terminal-residue picking from an atom list) and let `mutation.py` own the cmd-coupled insertion. **For cartoon, implement ONLY the "extend at a terminal" option (HIDER-05 option 1) for MVP**; the "replicate a segment as an alternate position" loop-replica option is meaningfully harder (separate `fab` object + `fuse` + altloc management) and is deferred to a stretch goal / Phase 6.

**Highest-risk item:** the `cmd.attach_amino_acid` → `cmd.fuse(...,2)` → sentinel-`alter` → `cmd.show('cartoon', ...)` chain has **four sequential cmd mutations with no undo** (Pitfall 10). `backup.snapshot` MUST precede the first call (Phase 3 `game.py.start` already does this). The smoke test MUST verify (a) the new residue is detected as `polymer` after `alter segi='GAME'`, (b) `cmd.count_atoms("obj and segi GAME and rep cartoon") > 0` after `cmd.show`, and (c) the structure is intact after `cleanup_hiders` (sentinel remove) — because altering `segi` on a polymer residue *might* break the trace (MEDIUM — runtime-verify).

**User's key question (hider color):** ANSWERED in §4 — **keep the `segi='GAME'` + `b=-999` sentinel UNCHANGED** (so Phase 3 cleanup `segi GAME` and read path `segi GAME and b < 0` work untouched) AND **explicitly copy a neighbor's `color` (and plausible `elem`/`ss`/`chain`) onto the hider via `cmd.alter`** so the *default* rendering blends. This is the exact pattern PyMOL's own mutagenesis wizard uses (`mutagenesis.py:474`: `stored.identifiers = (segi, chain, resi, ss, color)`). The known tradeoff: a user-initiated `spectrum b` will still reveal the b=-999 hiders (Pitfall 3) — document as a known limitation, do NOT change the sentinel value (that would break the Phase-3 `b < 0` read path and force a cleanup-selector migration).

**Build approach:** pure-geometry/selection helpers in `generators.py` (WSL-testable) → cmd-coupled `insert_line_stick_hider` / `insert_cartoon_hider` in `mutation.py` (headless-smoke-testable) → `GameController.start` dispatches per-rep → `__init__.py._on_start` builds mixed-rep `hider_specs` from `state["per_rep"]` (success criterion 3).

---

## 2. Line/Stick Hider Generation (HIDER-03) — Q1-Q4

### Q1: How do `lines`/`sticks` render? Do lone atoms render?

**Verified (HIGH):** `lines` and `sticks` are **bond-based** representations — they draw the *bonds* between atoms, not the atoms themselves. A lone pseudoatom (no bonds) is **invisible** in `lines`/`sticks`.

- PITFALLS.md Minor Pitfalls (line 511): *"`lines` and `sticks` render bonds. A hider atom with no bonds is invisible in `lines`/`sticks`. Use `cmd.bond(hider, neighbor)` to give it a bond, or show it as `spheres`."*
- `cmd.show('lines', selection)` / `cmd.show('sticks', selection)` turn on the rep flag for the atoms in the selection, but the rep only *draws* where bonds exist. `_showhide` (viewing.py:477-489) sets per-atom rep-mask flags via `_cmd.showhide`; the C renderer draws lines/sticks over the object's bond list.

**Implication:** a sphere-style `cmd.pseudoatom` placed in space will NOT render in lines/sticks. The hider MUST have a bond to a real neighbor.

### Q2: To BLEND, should the hider be (a) lone pseudoatom, (b) bonded pseudoatom, or (c) alternate position?

**Verified (HIGH) — option (b): a `cmd.pseudoatom` bonded to a real neighbor via `cmd.bond`.**

HIDER-03 says "mimic connected atoms or alternate positions." Option (b) "mimic connected atoms" is the simpler, proven path. `cmd.bond` API (editing.py:694-735):

```python
# tmp/pymol-src/modules/pymol/editing.py:694
def bond(atom1="pk1", atom2="pk2", order=1, *, quiet=1, symop="", _self=cmd):
    '''
    "bond" creates a new bond between two selections, each of which
    should contain one atom.
    ...
    NOTES
    The atoms must both be within the same object.
    '''
```

- **`atom1`, `atom2`:** single-atom selections (e.g., `"%s and id %d" % (obj, hider_id)` and `"%s and id %d" % (obj, neighbor_id)`).
- **`order`:** bond order (1=single, 2=double). Use 1 for a single bond.
- **"The atoms must both be within the same object"** (line 717) — SATISFIED: our pseudoatom is inserted INTO the existing object (`cmd.pseudoatom(object=existing)` per Phase 3 sentinel design), and the real neighbor is in that same object.

Option (c) "alternate position" (altloc) is meaningfully harder: it requires setting the `alt` field and managing altloc occupancy, and PyMOL's altloc rendering for bonds is fiddly. **Not recommended for MVP** — option (b) fully satisfies HIDER-03 ("mimic connected atoms").

### Q3: Where to place a line/stick hider? Hardest to spot but clickable?

**Recommendation (MEDIUM — no source rule, design choice):** Place the pseudoatom **near a real atom with a small random offset** (so the bond is short and the hider sits among real bonds), then `cmd.bond` it to that neighbor. Specifically:

1. Sample a real neighbor atom id from the object (via `cmd.iterate` — see §4 Q13).
2. Read its coords via `cmd.iterate_state` (Phase 3 finding: `cmd.iterate` does NOT expose x/y/z; use `cmd.iterate_state`).
3. Place the pseudoatom at `neighbor_pos + small_random_offset` (e.g., 0.5-1.0 Å, so the bond is visible but short — blends with nearby real bonds).
4. `cmd.bond(hider, neighbor)`.

This keeps the hider *clickable* (it's a real atom in the object, registered by id) and *hard to spot* (a single extra short bond among thousands). The offset is a pure-geometry decision → `generators.py` (see §5 Q18).

### Q4: Does `cmd.bond` require same object? Work after `cmd.pseudoatom(object=existing)`? Bond order param?

**Verified (HIGH):**
- **Same object: YES** — editing.py:717 docstring: *"The atoms must both be within the same object."* Our design satisfies this (pseudoatom INTO existing object, neighbor in same object).
- **After `cmd.pseudoatom(object=existing)`: YES** — `cmd.pseudoatom(object=existing)` adds the atom to the existing object (creating.py:1082; PITFALLS.md Pitfall 2). The new atom is then bondable to any other atom in that object.
- **Bond order param: `order=1`** (single bond, default). Use 1 for line/stick hiders. (2=double, 3=triple.)

```python
# Verified pattern (editing.py:694-735):
cmd.bond("%s and id %d" % (obj, hider_id),     # atom1
        "%s and id %d" % (obj, neighbor_id),    # atom2
        order=1)
```

**Caveat:** `cmd.bond` does NOT return the new bond's id or any handle — it returns a status code (`r`). The hider is tracked by its atom `id` (already captured via `cmd.identify` in `insert_hider`); the bond is implicit (cleanup by `segi GAME` removes the atom AND its bonds automatically — `cmd.remove` deletes incident bonds).

---

## 3. Cartoon/Ribbon Hider Generation (HIDER-05) — Q5-Q11 — THE DEEP DIVE

### Q5: Confirm Pitfall 8 — cartoon/ribbon are polymer-trace reps; a lone Cα pseudoatom is NOT enough

**Verified (HIGH):**
- **Pitfall 8 confirmed:** cartoon and ribbon are **polymer-trace** representations connecting consecutive Cα atoms (and N/C for ribbon) along `polymer` atoms. A lone pseudoatom — even with `elem='C'`, `name='CA'`, `hetatm=0` — is NOT part of the polymer trace unless fused into the chain with real N-C-Cα backbone geometry and consecutive `resi`.
- `preset.py:395`: `_self.show_as('cartoon', 'polymer & %' + s)` — cartoon is shown for the **`polymer`** selection. The `polymer` selector (cmd.py:363) is C-side, based on backbone connectivity/typing, NOT on `name='CA'` alone.
- `mutagenesis.py:570`: `cartoon = (cmd.count_atoms("(%s & name CA & rep cartoon)"%src_sele)>0)` — the canonical "is cartoon shown?" check uses `name CA & rep cartoon` (Cα atoms with the cartoon rep flag).

**Implication:** a `cmd.pseudoatom(name='CA', elem='C', hetatm=0)` placed near a residue will NOT render in cartoon — it's not bonded into the backbone, so the C engine doesn't classify it as polymer. **You MUST use `cmd.attach_amino_acid` (or `cmd.fuse`) to add real backbone geometry.**

### Q6: `cmd.attach_amino_acid` — full signature, what it does, does the new residue join the polymer trace?

**Verified (HIGH) — editor.py:85-270:**

```python
# tmp/pymol-src/modules/pymol/editor.py:85
def attach_amino_acid(selection, amino_acid, center=0, animate=-1,
                      object="", hydro=-1, ss=-1, _self=cmd):
    '''
    ARGUMENTS
    selection = str: named selection of single N or C atom
    amino_acid = str: fragment name to load from fragment library
    center = bool: center on new terminus (pk1)
    animate = int: animate centering
    object = str: name of new object (if selection is none)
    hydro = int (-1/0/1): keep hydrogens
    ss = int: Secondary structure 1=alpha helix, 2=antiparallel beta,
             3=parallel beta, 4=flat
    '''
```

**What it does (editor.py:103-268):**
1. **Validates the connection point:** `_self.select(tmp_connect,"(%s) & elem N,C"%selection)` (line 125) — the `selection` must contain exactly ONE atom that is N or C (a terminus N or carbonyl C). If not: `"Error: invalid connection point: must be one atom, name N or C."` (line 126).
2. **Loads a fragment:** `_self.fragment(amino_acid, tmp_editor, origin=0)` (line 153) — creates a temp object `_tmp_editor0` with the amino acid's real backbone geometry (N, Cα, C, O, side chain).
3. **Sets the residue number:** reads the neighbor's `resv` via `cmd.iterate` (line 156/208), sets the new residue's `resi` to `resv-1` (N-terminus extension, backward) or `resv+1` (C-terminus extension, forward) via `cmd.alter` (line 158/210).
4. **Fuses:** `_self.fuse("(%s and name C)"%(tmp_editor), tmp_connect, 2)` (line 160, backward) or `_self.fuse("(%s and name N)"%tmp_editor, tmp_connect, 2)` (line 212, forward) — **`mode=2`** (not documented in the `fuse` docstring, but used internally — see Q7).
5. **Sets dihedrals** (phi/psi) based on `ss` (lines 176-252) — so the new residue has physically reasonable backbone angles.
6. **Cleans up temp objects:** `_self.delete(tmp_wild)` (line 268) where `tmp_wild = "_tmp_editor*"` (editor.py:14).

**Does the new residue join the polymer trace so cartoon renders it?** **YES (HIGH).** The fused residue has real N-C-Cα atoms, real backbone bonds to the neighbor, and consecutive `resi` — it IS part of the polymer chain by connectivity. The C-engine `polymer` selector will classify it as polymer, and `cmd.show('cartoon', 'obj and segi GAME')` will render it.

**`ss` param for a blending hider:** use `ss=4` (flat / loop) or `ss=-1` (use the `secondary_structure` setting, default 0 = no dihedral → loop). A loop extension is the least visually conspicuous (no helix ribbon or sheet arrow — just a tube), so it blends best as an "extra loop turn." Avoid `ss=1/2/3` (helix/beta) — those draw attention.

**Amino acid choice:** `'gly'` (glycine) — smallest side chain (just N-Cα-C-O, no Cβ). Glycine is the least visually conspicuous residue and has the fewest atoms to register. The full 1-letter → fragment code map is at editor.py:272-295 (`_aa_codes`).

### Q7: `cmd.fuse(mobile, target, mode)` — full signature, modes, can it fuse a pre-built peptide?

**Verified (HIGH) — editing.py:937-987:**

```python
# tmp/pymol-src/modules/pymol/editing.py:937
def fuse(selection1="(pk1)", selection2="(pk2)",
         mode=0, recolor=1, move=1, _self=cmd):
    '''
    "fuse" joins two objects into one by forming a bond.  A copy of
    the object containing the first atom is moved so as to form an
    approximately resonable bond with the second, and that copy is
    then merged with the first object.
    ARGUMENTS
    selection1 = str: single atom selection (will be copied to object 2)
    selection2 = str: single atom selection
    mode = int: {default: 0}
      3: don't move and don't create a bond, just combine into single object
    recolor = bool: recolor C atoms to match target {default: 1}
    move = bool: {default: 1}
    NOTES
    Each selection must include a single atom in each object.
    '''
```

- **`mode=0`** (default): move + create bond.
- **`mode=3`:** combine into single object, no move, no bond.
- **`mode=1`** and **`mode=2`:** NOT documented in the docstring, but `attach_amino_acid` uses **`mode=2`** (editor.py:160, 212) and `attach_fragment` uses **`mode=1`** (editor.py:66). These modes differ in bond geometry / which atom is the anchor. **For Phase 5, do NOT call `cmd.fuse` directly — use `cmd.attach_amino_acid` which calls it internally with the correct mode.**
- **`recolor=1`** (default): recolor C atoms to match the target — this is GOOD for blending (the fused residue's carbons get the target's color automatically). See §4 for the full coloring strategy.

**Can it fuse a pre-built peptide (the loop-replica option)?** YES — `cmd.fuse(frag_atom, target_atom, mode)` merges the fragment's object into the target object. This is the mechanism for HIDER-05 option 2 (loop replica). But it requires: (a) building the peptide as a separate object (`cmd.fab`), (b) picking a single anchor atom in the fragment and a single target atom, (c) fusing. **Significantly more complex than option 1** — see Q9.

### Q8: "Extend at a terminal" (HIDER-05 option 1) — how to pick a terminal, attach, sentinel, register?

**Verified (HIGH) — full procedure:**

**Step 1: Pick a terminal N or C atom.** PyMOL has NO built-in "terminus" selector keyword (cmd.py:350-369 selector list — no `termi`/`terminus`). The robust approach: `cmd.iterate` the polymer Cα atoms to find the chain endpoints:

```python
# Find the C-terminus C atom (highest resi) of the longest chain
cas = []
cmd.iterate("%s and polymer and name CA" % obj,
            "stored.append((chain, int(resi), ID))", space={'stored': cas})
# Group by chain, pick the chain with the most residues, take max resi
# Then select that chain's terminal C atom:
# C-terminus: "%s and chain %s and resi %d and name C" % (obj, chain, max_resi)
# N-terminus: "%s and chain %s and resi %d and name N" % (obj, chain, min_resi)
```

**Step 2: Call `cmd.attach_amino_acid`** with that single-atom selection:
```python
terminus_sele = "%s and chain %s and resi %d and name C" % (obj, chain, max_resi)
cmd.attach_amino_acid(terminus_sele, 'gly', ss=4, hydro=0)
```
- `ss=4` (flat/loop) → the new residue renders as a loop extension (least conspicuous).
- `hydro=0` → no hydrogens (fewer atoms, cleaner).
- The new residue is fused INTO `obj` with real backbone geometry + consecutive resi.

**Step 3: Apply the GAME sentinel** to the new residue via `cmd.alter`:
```python
# The new residue's resi is max_resi + 1 (C-term) or min_resi - 1 (N-term)
new_resi = max_resi + 1  # or min_resi - 1
new_sele = "%s and chain %s and resi %d" % (obj, chain, new_resi)
cmd.alter(new_sele, "segi='GAME'; b=-999.0", space={})
cmd.sort(obj)  # defensive (editing.py:1457) — sort after altering segi
```

**Step 4: Register the new residue's atom id(s).** The fused atoms get NEW stable ids (fuse adds atoms; existing target atoms keep their ids — see Q22). Fetch the new Cα id (the cartoon-representative atom) via `cmd.identify`:
```python
ids = cmd.identify("%s and name CA and segi GAME and resi %d" % (obj, new_resi), mode=0)
# Register ids[0] (the Cα) as the hider — the player clicks the Cα to find it.
```

**Step 5: Show the cartoon rep** (CRITICAL — see Q11 + the "newly-fused atoms don't inherit reps" finding below):
```python
cmd.show('cartoon', "%s and segi GAME" % obj)
```

### Q9: "Replicate a segment (loop) as alternate position" (HIDER-05 option 2) — harder? MVP?

**Verified (MEDIUM) — meaningfully harder; DEFER for MVP.**

The loop-replica option would: (a) build a short peptide as a SEPARATE object via `cmd.fab` (editor.py:387-423: `fab(input, name, mode='peptide', resi=1, chain='', segi='', ss=0)` — builds a peptide from a 1-letter sequence into a new object), (b) translate it to the target location, (c) `cmd.fuse` it into the existing object (mode 1 or 3), (d) manage altlocs (`alt` field) so the replica is an "alternate position."

**Why it's harder than option 1:**
- `cmd.fab` creates a SEPARATE object (editor.py:351 `_self.fragment(...)` + editor.py:355 `_self.create(name, tmp_obj+" or ?"+name, 1, 1, zoom=0)`). To merge it into the target, you must `cmd.fuse` a single anchor atom — but the fragment has no bond to the target until fused, and the fused residue's geometry may not align with the target's backbone.
- "Alternate position" implies altloc management (`alt='A'/'B'`), which is a distinct concept from "extra residue" — altlocs share the same resi and are mutually exclusive. This is fiddly and not what a cartoon *extension* needs.
- `attach_amino_acid` already gives you a clean "extra loop turn at the terminus" with real backbone geometry — that IS a loop replica, just at the terminus rather than mid-chain.

**MVP recommendation:** **Implement option 1 (extend at terminal) ONLY.** It satisfies HIDER-05 ("extend at a terminal, OR replicate a segment as an alternate position") — the spec is an OR, not an AND. Option 2 is a stretch goal / Phase 6 polish. Document option 2 as "deferred — not needed for success criteria" in the plan.

### Q10: Ribbon vs cartoon — different requirements? Can one hider satisfy both?

**Verified (HIGH):** Ribbon and cartoon are BOTH polymer-trace reps over the same N-C-Cα backbone. Ribbon draws a flat ribbon; cartoon draws tubes (loop), ribbons (helix), and arrows (sheet) based on `ss`. **One attached residue satisfies BOTH reps** — the same polymer segment renders in both `cartoon` and `ribbon` when those reps are shown.

- `preset.py:395` uses `show_as('cartoon', 'polymer & ...')`; the same selection works for `show_as('ribbon', ...)`.
- The `HiderRecord.rep` field stores ONE rep (`'cartoon'` OR `'ribbon'`), but the underlying atom is visible in BOTH reps if both are shown. **For the registry, pick `'cartoon'` as the canonical rep** (cartoon is the more common/default rep) and let the player find the same Cα if `ribbon` is the shown rep. If the user's scene shows `ribbon` (not `cartoon`), the hider generated as `'cartoon'` will still render in `ribbon` (same atoms) — but the registry says `'cartoon'`. This is a known minor mismatch; document it. (Alternative: generate the hider with `rep` = whichever of cartoon/ribbon is currently shown — `cmd.count_atoms("obj and rep cartoon") > 0` vs `... rep ribbon`.)

### Q11: How to verify a cartoon hider renders? `cmd.count('cartoon', ...)`?

**Verified (HIGH) — the success-criteria pseudocode is WRONG syntax; use `cmd.count_atoms`:**

There is **NO `cmd.count(rep, selection)` function** in PyMOL 2.5.0. The querying module (querying.py) has `count_atoms` (line 1412), `count_states` (703), `count_frames` (759), `count_discrete` (1436) — none take a rep argument. The Phase 5 success criteria `cmd.count('cartoon', 'obj and segi GAME') > 0` is **imprecise pseudocode**.

**The correct, verified check** uses the `rep` SELECTOR (cmd.py:360: `'rep '` is in the selector keyword list) inside `cmd.count_atoms`:
```python
cmd.count_atoms("obj and segi GAME and rep cartoon") > 0
```
- **`rep` selector:** cmd.py:360 lists `'rep '` among selector keywords (alongside `b`, `color`, `ss`, `elem`). It selects atoms that have the named representation ENABLED (shown).
- **Canonical precedent:** `mutagenesis.py:570`: `cartoon = (cmd.count_atoms("(%s & name CA & rep cartoon)"%src_sele)>0)` — PyMOL's own wizard checks cartoon-visibility this way. Also `mutagenesis.py:571`: `sticks = (cmd.count_atoms("(%s & name CA & rep sticks)"%src_sele)>0)`.
- **Phase 4 smoke already uses this pattern:** `smoke/phase4_smoke.py:43`: `cmd.count_atoms("%s and rep spheres and segi GAME" % obj) == 3` — confirms `rep <name>` selector works at the PyMOL 2.5.0 runtime tier.

**CRITICAL implementation detail — newly-fused atoms do NOT inherit shown reps:** PyMOL representations are per-atom flags set by `_cmd.showhide` (viewing.py:487). Atoms added via `cmd.pseudoatom`/`cmd.fuse`/`attach_amino_acid` start with NO reps shown. The mutagenesis wizard RE-SHOWS reps after replacing a residue (mutagenesis.py:660-667):
```python
cmd.hide("("+obj_name+")")
cmd.show(self.rep,obj_name)
cmd.show('lines',obj_name)
if cartoon: cmd.show("cartoon",obj_name)
if sticks:  cmd.show("sticks",obj_name)
```
**Implication for Phase 5:** after `attach_amino_acid` + sentinel-alter, you MUST explicitly call `cmd.show('cartoon', "%s and segi GAME" % obj)` (and/or `cmd.show('ribbon', ...)`) to make the new residue render. Without this, `count_atoms("... and rep cartoon and segi GAME")` returns 0 and the hider is invisible. **Same for line/stick:** `cmd.show('lines'/'sticks', "%s and segi GAME" % obj)` after `cmd.bond`.

**Better visibility check than `count_atoms`?** `count_atoms("... and rep cartoon")` is the canonical, headless-runnable check (mutagenesis.py:570). The only "better" check is a human visually confirming the cartoon tube blends — that's a human-verify checkpoint (§6 Q21), not a smoke assertion.

---

## 4. Hider Coloring Strategy (USER'S KEY QUESTION) — Q12-Q17

### Q12: CPK by element? What color does a pseudoatom get?

**Verified (HIGH):**
- PyMOL colors atoms by element (CPK default): C=green (carbon), O=red, N=blue, S=yellow, H=white. The default color is the `atomic` color scheme, applied when an atom has no explicit color.
- A pseudoatom with `elem='PS'` (Phase 4 default) gets the pseudo-element color (a gray/green "PS" color). This makes it visually DISTINCT from real atoms (C/N/O) — fine for spheres (the challenge is the 3D search), but **bad for line/stick/cartoon blending**.
- A pseudoatom with `elem='C'` gets carbon's color (green). Setting `elem` to match the local context (C for Cα, N for backbone N, O for carbonyl O) makes CPK auto-blend.

**Implication:** Phase 5 hiders in line/stick/cartoon MUST set plausible `elem` (not `PS`) so the default CPK coloring matches neighbors. Phase 4's `elem='PS'` was acceptable for spheres only.

### Q13: How to sample a neighbor's color — `cmd.iterate` exposes `color`?

**Verified (HIGH):** `cmd.iterate` exposes the atom's color index as **lowercase `color`** (an int). The `alter`/`iterate` symbol table (editing.py:1444-1449):
```
name, resn, resi, resv, chain, segi, elem, alt, q, b, vdw, type,
partial_charge, formal_charge, elec_radius, text_type, label, 
numeric_type, model*, state*, index*, ID, rank, color, ss,
cartoon, flags
```
- **`color`** is lowercase, read-WRITE (no `*` — the `*` marks read-only: `model*`, `state*`, `index*`).
- **`ID`** is UPPERCASE (Phase 3 finding confirmed — the stable integral id).
- **`ss`**, **`elem`**, **`segi`**, **`chain`**, **`resn`**, **`resi`** are lowercase, read-write.
- **`cartoon`** is lowercase (per-atom cartoon-type override).

**Canonical read pattern (mutagenesis.py:474):**
```python
cmd.alter("?%s & name CA" % src_sele,
          "stored.identifiers = (segi, chain, resi, ss, color)",
          space=self.space)
# stored.identifiers = (segi_str, chain_str, resi_str, ss_str, color_int)
```
(Yes, `alter` can also READ — it evaluates the expression per atom, so `stored.identifiers = (segi, chain, ...)` captures values. `iterate` is the read-only equivalent; both work for sampling.)

**Phase 4 smoke already reads color:** `smoke/phase4_smoke.py:56`: `cmd.iterate("%s and id %d" % (obj, first_id), "stored.append(color)", space={'stored': orig_cols})` — confirmed at the runtime tier.

### Q14: How to apply a color — `cmd.color` with int index? Or `cmd.alter`?

**Verified (HIGH) — both work; `cmd.alter` is the most reliable for an int index:**

- **`cmd.color(color, selection)`** (viewing.py:1858-1899): `color = string: color name or number`. It calls `_interpret_color` (internal.py:563) which resolves names via `color_sc.interpret`. For an INT, `is_string(new_color)` is False, so it falls through and `_cmd.color(_self._COb, str(color), ...)` passes the int-as-string to the C side, which resolves it as a color index. **The appearance wizard uses this:** `appearance.py:189` `color = self.color_dict[self.current_color][1]` (the int index), then `cmmd = mode+'("%s","%s")'%(color,sele)` → `cmd.do(cmmd)` (passes the int stringified). So `cmd.color(int_index, sele)` works, but is slightly indirect.

- **`cmd.alter(selection, "color = %d" % idx, space={})`** — directly writes the color index to the atom's `color` field. `color` is read-write (symbol table, no `*`). This is the **most reliable, direct path** and mirrors the mutagenesis read pattern (`mutagenesis.py:474` reads `color` into a tuple; the inverse write is `alter(..., "color = ...")`).

**Recommendation:** use `cmd.alter` to set the color (and `segi`/`b`/`ss`/`chain` together in one call — hygienic, single mutation):
```python
# Copy neighbor's (chain, ss, color) but override segi='GAME', b=-999
nbr = []
cmd.iterate("%s and id %d and name CA" % (obj, neighbor_id),
            "stored.append((chain, ss, color))", space={'stored': nbr})
chain, ss, color = nbr[0]
# Inject values via space= (hygienic — no global namespace pollution, RESEARCH §Q3)
cmd.alter("%s and id %d" % (obj, hider_id),
          "segi='GAME'; b=-999.0; color=stored_c; ss=stored_ss; chain=stored_chain",
          space={'stored_c': color, 'stored_ss': ss, 'stored_chain': chain})
```
(For cartoon, apply to the new residue's Cα; the cartoon tube color follows the Cα — see Q16.)

### Q15: b=-999 sentinel vs `spectrum b` recoloring — which option is safest?

**The user's explicit question. Analysis of the three options:**

| Option | Sentinels | `spectrum b` reveals hiders? | Phase 3 cleanup `segi GAME` works? | Phase 3 read `segi GAME and b < 0` works? | Default render blends? |
|--------|----------|------------------------------|-----------------------------------|------------------------------------------|-----------------------|
| (a) keep `b=-999` only | yes | YES (Pitfall 3 — hider colored at spectrum extreme) | yes | yes | NO (unless elem/color set) |
| (b) set `b` = neighbor's `b`, rely on `segi='GAME'` alone | partial | no | yes | **NO** (`b < 0` matches nothing) — breaks `fetch_all_hider_ids` | yes if elem/color set |
| (c) **keep `b=-999`, ALSO `cmd.color`/alter to neighbor color** | yes | YES (still — b=-999 is at the extreme) | yes | yes | **YES** (explicit color matches neighbor) |

**RECOMMENDATION: Option (c) — keep the sentinel UNCHANGED, add explicit color blending.**

**Rationale:**
- **Option (c) preserves Phase 3 invariants with ZERO migration:** `mutation.cleanup_hiders` uses `segi GAME` alone (mutation.py:145) — unaffected. `mutation.fetch_all_hider_ids` uses `segi GAME and b < 0` (mutation.py:113) — unaffected. `backup.verify_intact` uses `(resn, resi, name, chain, segi)` — unaffected. No existing test or code path changes.
- **Option (c) fixes the DEFAULT rendering:** by copying the neighbor's `color` (and plausible `elem`/`ss`), the hider looks like a real atom in default CPK/line/stick/cartoon rendering. The user sees a blended hider.
- **The `spectrum b` tradeoff is ACCEPTABLE and UNAVOIDABLE:** ANY b-factor sentinel (b=-999 or otherwise) will be revealed by `spectrum b, rainbow, obj` because spectrum colors by b value. The only way to hide from `spectrum b` is to set `b` to a neighbor's value (option b) — but that breaks the `b < 0` read path, forcing a migration of `fetch_all_hider_ids` to `segi GAME` alone (doable but touches Phase 3 code + tests). Since `spectrum b` is a *user-initiated* recolor (not the default state), and the game's challenge is visual search (not "type `spectrum b` to win"), **document `spectrum b` as a known limitation / "debug cheat" and keep the sentinel intact.**
- **Pitfall 3's warning stands:** "A `b`-factor matching neighbors so `spectrum b` doesn't recolor hiders differently" is the *ideal*, but it conflicts with the sentinel read path. Phase 5 prioritizes NOT breaking Phase 3 over defeating the `spectrum b` debug cheat.

**Action:** in `insert_line_stick_hider` / `insert_cartoon_hider`, after the pseudoatom/attach, run a single `cmd.alter` that sets `segi='GAME'; b=-999.0; color=<neighbor_color>; ss=<neighbor_ss>; chain=<neighbor_chain>` (and `elem` set at pseudoatom-creation time). Do NOT change `mutation.cleanup_hiders` or `mutation.fetch_all_hider_ids`.

### Q16: Does the cartoon segment color follow the Cα atom's color?

**Verified (MEDIUM — needs runtime smoke confirmation):** By default, the cartoon tube color follows the Cα atom's color of each residue. The `cartoon_color` setting can override (e.g., `set cartoon_color, gray` forces all cartoon to one color), but by default (`cartoon_color = -1` / "by atom"), the cartoon segment takes the Cα's color.

- `mutagenesis.py:474` copies `color` (among `(segi, chain, resi, ss, color)`) from the source Cα to the fragment Cα — strong evidence that the Cα color drives the cartoon/rep appearance.
- `cmd.color('cartoon'?)` — there is no separate "cartoon color"; `cmd.color(c, "obj and name CA")` colors the Cα, and the cartoon follows.

**Implication for blending:** color the inserted residue's Cα to match a neighbor Cα's color → the cartoon tube segment for the new residue matches the neighbor's tube color → blends. **Runtime-verify in the smoke test:** after attach + alter color, `cmd.iterate("obj and segi GAME and name CA", "stored.append(color)")` should return the neighbor's color index, and a human-verify checkpoint confirms the cartoon tube blends visually.

### Q17: Set `elem` to plausible, OR `cmd.color`, OR both?

**Recommendation (HIGH): BOTH — set plausible `elem` AND explicit `color`.**

- **`elem` (set at `cmd.pseudoatom`/fragment time):** makes CPK auto-blend (C=green, N=blue, O=red) AND makes `spectrum elem`-style recoloring consistent AND gives the right vdw radius for sphere fallback. For cartoon, the fragment from `attach_amino_acid` already has correct `elem` (C for Cα/C, N for N, O for O) — no extra work. For line/stick, set `elem` on the pseudoatom to match the neighbor's elem (sample via `cmd.iterate` reading `elem`).
- **`color` (via `cmd.alter`):** makes the DEFAULT rendering match the neighbor exactly (handles cases where the user recolored by chain, by ss, custom — `elem` alone wouldn't follow a custom per-chain color). This is the belt-and-suspenders blend.
- **Tradeoff:** two properties to set instead of one. But both are cheap (one `alter` call) and the redundancy is robust: if the user does `color byelem`, `elem` wins; if the user does `color chain`, `color` matches; if the user does nothing, both agree (CPK).

**Do NOT rely on `elem` alone** — if the user recolored by chain (e.g., `color skyblue, chain A`), the hider's `elem='C'` would NOT follow that custom color, and the hider would stand out. Setting `color` explicitly to the neighbor's color index follows custom recoloring too.

---

## 5. Architecture: Pure vs Cmd-Coupled Split — Q18-Q20

### Q18: How much of Phase 5 can stay PURE in `generators.py` vs needs a new cmd-coupled module?

**Recommendation (HIGH) — preserve the Phase 4 pure/cmd split:**

```
generators.py  (PURE: stdlib only; NO from pymol; WSL-testable)
   generate_sphere_positions(extent, n, seed)              # Phase 4
   generate_line_stick_offsets(neighbor_count, seed)       # NEW Phase 5 — pure RNG offsets
   pick_terminal_residue(cas_by_chain)                     # NEW Phase 5 — pure selection from a list
        ↑ (caller feeds cmd.iterate output as data)
mutation.py  (cmd-coupled; headless-smoke-testable)
   insert_hider(object, pos, rep, handle, ...)             # Phase 3/4 sphere path (unchanged)
   insert_line_stick_hider(object, pos, neighbor_id, ...)   # NEW Phase 5
   insert_cartoon_hider(object, terminus_sele, ...)         # NEW Phase 5
   insert_hider_for_rep(object, rep, spec, handle, ...)     # NEW Phase 5 dispatcher
game.py  (cmd orchestrator)
   GameController.start(hider_specs)                        # unchanged signature
__init__.py  (Qt + cmd wiring)
   _on_start builds mixed-rep hider_specs                    # extended
```

**What stays PURE (`generators.py`):**
- **`generate_line_stick_offsets(n, seed)`** — returns `n` small `[dx,dy,dz]` offset vectors (e.g., uniform in [-1.0, 1.0] Å). Pure RNG, no pymol. Unit-testable in WSL.
- **`pick_terminal_residue(cas_by_chain)`** — takes a dict `{chain: [(resi, id), ...]}` (produced by the caller's `cmd.iterate`) and returns `(chain, terminal_resi, terminal_ca_id, is_c_terminus)`. Pure data logic (find the chain with the most residues; pick min or max resi). Unit-testable in WSL.

**What's cmd-coupled (`mutation.py`):**
- **`insert_line_stick_hider(object, offset, neighbor_id, handle, ...)`** — calls `cmd.iterate_state` to get the neighbor's coords, `cmd.pseudoatom` at `coord+offset`, `cmd.bond`, sentinel-alter, `cmd.identify`, return id. (The `cmd.bond` + `cmd.iterate_state` are inherently cmd-coupled.)
- **`insert_cartoon_hider(object, terminus_sele, handle, ...)`** — calls `cmd.attach_amino_acid`, sentinel-alter, `cmd.identify`, `cmd.show('cartoon', ...)`, return the Cα id. (The `attach_amino_acid` is inherently cmd-coupled.)
- **`insert_hider_for_rep(object, rep, spec, handle, ...)`** — dispatches: `rep=='spheres'` → `insert_hider`; `rep in ('lines','sticks')` → `insert_line_stick_hider`; `rep in ('cartoon','ribbon')` → `insert_cartoon_hider`. This lets `GameController.start` stay a thin loop.

**Why this split:** the PURE layer (geometry/selection over data) is WSL-unit-testable (mirrors `registry.py`/`setup_state.py`/Phase 4 `generators.py`). The cmd layer (actual `cmd.bond`/`attach_amino_acid`/`cmd.show`) can only run in the Windows headless smoke (AGENTS.md). This preserves the Phase 3/4 purity convention (AGENTS.md: "setup_state.py PURE ← generators.py PURE ← registry.py PURE; demos.py/backup.py/mutation.py cmd-coupled").

### Q19: Extend `mutation.insert_hider` or add new functions?

**Recommendation (HIGH): ADD new functions; keep `insert_hider` for spheres.**

- `insert_hider(object, pos, rep, handle, ...)` is the Phase 3/4 sphere primitive: `cmd.pseudoatom` at `pos` + sentinel + `cmd.identify`. It takes `rep` but ignores it for placement (Phase 3 design — rep is for the registry, not placement).
- **Do NOT overload `insert_hider` to handle bond+attach** — the signatures diverge: sphere needs `pos`, line/stick needs `neighbor_id`, cartoon needs `terminus_sele`. Forcing one signature with optional kwargs is brittle.
- **Add `insert_line_stick_hider` and `insert_cartoon_hider`** with clear, rep-specific signatures. Add `insert_hider_for_rep(rep, ...)` as the dispatcher so `GameController.start`'s loop body becomes:
  ```python
  for i, spec in enumerate(hider_specs):
      handle = "H%03d" % i
      aid = mutation.insert_hider_for_rep(self.target_obj, spec.rep, spec, handle)
      self.registry.register(object=self.target_obj, id=aid, rep=spec.rep)
  ```
- The `hider_specs` shape changes from `[(pos, rep)]` (Phase 4) to a small structured spec per rep. **Recommendation:** keep `hider_specs` as `[(payload, rep)]` where `payload` is `pos` (spheres), `(offset, neighbor_id)` (line/stick), or `terminus_sele` (cartoon) — a 2-tuple preserves the existing `for pos, rep in hider_specs` unpacking if you rename `pos`→`payload`. OR introduce a tiny `HiderSpec` namedtuple (`HiderSpec(rep, payload)`). The planner decides; the dispatcher handles the variant.

### Q20: How does `__init__.py._on_start` change for mixed-rep specs (success criterion 3)?

**Verified (HIGH) — current `_on_start` (Phase 4, `__init__.py:76-129`) builds sphere-only specs; Phase 5 extends it to read `state["per_rep"]` and dispatch per rep.**

**Current flow (Phase 4):**
```python
extent = cmd.get_extent(target_obj)
positions = generators.generate_sphere_positions(extent, count)
hider_specs = [(pos, "spheres") for pos in positions]
```

**Phase 5 flow (mixed reps):**
```python
state = self.setup_tab.collect_state()
per_rep = state.get("per_rep", {})  # {rep: count} — already in collect_state (Phase 2)
hider_specs = []
# Pre-fetch the data the pure generators need (cmd-coupled, here in _on_start):
extent = cmd.get_extent(target_obj)
# For line/stick: sample neighbor atom ids + coords
neighbor_pool = []  # [(id, x, y, z, elem, color, chain, ss), ...]
cmd.iterate_state(1, "%s and not segi GAME" % target_obj,
                  "stored.append((ID, x, y, z, elem, color, chain, ss))",
                  space={'stored': neighbor_pool})  # iterate_state exposes x,y,z
# For cartoon: find terminal Cα per chain
cas_by_chain = {}
cmd.iterate("%s and polymer and name CA" % target_obj,
            "stored.append((chain, int(resi), ID))", space={'stored': cas_list})
# (group cas_list into cas_by_chain in pure code)

for rep, count in per_rep.items():
    if rep == 'spheres':
        positions = generators.generate_sphere_positions(extent, count)
        hider_specs += [(p, 'spheres') for p in positions]
    elif rep in ('lines', 'sticks'):
        offsets = generators.generate_line_stick_offsets(count, seed)
        # pick `count` random neighbors from neighbor_pool (pure)
        for off, nbr in zip(offsets, chosen_neighbors):
            hider_specs.append(((off, nbr['id']), rep))
    elif rep in ('cartoon', 'ribbon'):
        terminus = generators.pick_terminal_residue(cas_by_chain)
        # one cartoon hider per terminus (attaching many to one terminus chains)
        hider_specs.append((terminus_sele, rep))  # or count termini if count > 1
# Then: GameController.start(hider_specs) — unchanged
```

**Key points:**
- `collect_state()` already returns `per_rep` (gui_setup.py — verified Phase 4 research Q19). Phase 5 consumes it.
- The `cmd.iterate`/`cmd.iterate_state` calls (to fetch the neighbor pool and Cα list) live in `_on_start` (cmd-coupled) — they feed DATA to the pure generators. This keeps `generators.py` pure.
- **Cartoon count caveat:** you can attach at most ONE residue per terminus per call (attaching many to the same terminus chains them — the 2nd attaches to the 1st's new terminus, which works but shifts the chain). For `count > 1` cartoon hiders, attach sequentially to the same growing terminus (each `attach_amino_acid` extends the new terminus). This is fine but means the `hider_specs` for cartoon is a list of terminus selections that must be processed in order. The dispatcher handles this.
- If `per_rep` is empty (random mode) and `lock_scene` is False, Phase 5 should still default to spheres (Phase 4 behavior) OR distribute across active reps — this is a product decision. The setup_state `randomize_state` already distributes `per_rep` across reps (setup_state.py:196-205); Phase 5 just needs to honor it.

---

## 6. Verification & Safety — Q21-Q24

### Q21: Can Phase 5 cartoon hiders be verified headlessly? What should the smoke assert?

**Verified (HIGH): YES — cartoon hiders are headless-verifiable for RENDERING (not visual blend).** The Phase 3/4 headless smoke pattern (`smoke/phase3_smoke.py`, `smoke/phase4_smoke.py`) runs pure `pymol.cmd.*` via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq` from WSL (AGENTS.md Environment). `cmd.attach_amino_acid`, `cmd.bond`, `cmd.show`, `cmd.count_atoms` are all pure-cmd (no Qt) → headless-runnable.

**Smoke test assertions (recommended):**
```python
# After insert_cartoon_hider + cmd.show('cartoon', 'obj and segi GAME'):
check("cartoon: GAME atoms in polymer",
      cmd.count_atoms("%s and segi GAME and polymer" % obj) > 0)  # new residue is polymer
check("cartoon: GAME Cα in rep cartoon",
      cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj) > 0)  # mutagenesis.py:570 pattern
check("cartoon: residue has N-C-Cα backbone",
      cmd.count_atoms("%s and segi GAME and (name N or name CA or name C)" % obj) >= 3)
check("cartoon: sentinel set (segi=GAME, b=-999)",
      # iterate and assert segi/b on the new atoms
      ...)
check("cartoon: color matches neighbor (blend)",
      # iterate neighbor Cα color and hider Cα color, assert equal
      ...)
# After insert_line_stick_hider + cmd.show('sticks', 'obj and segi GAME'):
check("stick: GAME atoms in rep sticks",
      cmd.count_atoms("%s and segi GAME and rep sticks" % obj) > 0)
check("stick: hider bonded to neighbor",
      # cmd.count_atoms("neighbor and bound_to hider") or similar
      ...)
# Cleanup safety (criterion 4):
check("cleanup: count back to orig",
      cmd.count_atoms(obj) == orig_count)  # sentinel remove restores original
check("cleanup: structure intact",
      gc.cleanup() is True)
```

**Human-verify checkpoint (Qt GUI — NOT headless):** a human in a real Windows PyMOL session loads a demo (e.g., 1ubq), starts a game with mixed reps (sphere + line/stick + cartoon), and visually confirms:
1. Sphere hiders are visible as spheres among real atoms.
2. Line/stick hiders are visible as extra bonds that blend with real bonds.
3. Cartoon hiders are visible as extra cartoon tube segments that blend with the existing cartoon.
4. The player can click each hider (in each rep) and the game registers the find.
5. After cleanup, the structure looks identical to pre-game (no extra residues/bonds).

This is the success-criteria-3 verification (mixed reps, all tracked). The smoke proves the mechanism; the human proves the blend.

### Q22: Backup safety — does `attach_amino_acid`/`cmd.fuse` change existing atom ids (break the registry)?

**Verified (HIGH): NO — `attach_amino_acid`/`cmd.fuse` only ADD new atoms with new ids; existing target atoms keep their ids.**

- `cmd.fuse` (editing.py:937-987) merges a COPY of the source object into the target. The docstring: *"A copy of the object containing the first atom is moved ... and that copy is then merged with the first object."* The target's existing atoms are not renumbered — the fused fragment's atoms are APPENDED with new ids.
- `cmd.pseudoatom` (Phase 3) adds one atom with a new id (Phase 3 smoke Q4: existing ids stable across insert — `orig_ids.issubset(new_ids) and len(new_ids - orig_ids) == 3`).
- `cmd.bond` (editing.py:694) only adds a bond record; it does NOT change atom ids.
- `backup.snapshot` (Phase 3, `cmd.create('_bchm_backup', target)`) captures the pre-mutation state. `backup.restore` (`cmd.delete(target)` + `cmd.create(target, backup)`) restores atom-for-atom. Phase 3 smoke confirmed `verify_intact` after cleanup returns True.
- **The registry is safe:** the registry keys on (object, id) of the NEW hider atoms (captured via `cmd.identify` after each insert/attach). Existing atoms' ids are unchanged, so any pre-existing registry entries (there are none at start — `start()` builds a fresh registry) are unaffected. After cleanup (`cmd.remove` by `segi GAME`), the hider atoms (and their incident bonds) are removed; original atoms remain with original ids.

**Conclusion:** the Phase 3 backup/restore mechanism needs NO changes for Phase 5. `game.py.start` already does `backup.snapshot` before the insert loop; `cleanup`/`abort_on_error` already restore. The cartoon `attach_amino_acid` is just a different insert primitive — it's wrapped in the same snapshot→mutate→register→cleanup envelope.

### Q23: Does `cmd.sort` interact badly with `attach_amino_acid`? Call sort after attach?

**Verified (HIGH): `cmd.sort` is SAFE after attach+alter; call it defensively (editing.py:1457).**

- `attach_amino_acid` does NOT call `cmd.sort` internally (editor.py:85-270 — no `sort` call). It does call `cmd.alter` (resi) and `cmd.fuse`, which change canonical ordering.
- `cmd.alter` of `segi`/`chain`/`resi` on the new residue: editing.py:1457 warns: *"You should always issue a 'sort' command on an object after modifying any property which might affect canonical atom ordering (names, chains, etc.). Failure to do so will confound subsequent 'create' and 'byres' operations."*
- `cmd.sort` reassigns `index` but **preserves `id`** (Phase 3 smoke confirmed: sort is safe for the id-keyed registry — PITFALLS.md Pitfall 4 / AGENTS.md "sort reassigns index but preserves id — safe for the id-keyed registry").
- **Recommendation:** in `insert_cartoon_hider`, call `cmd.sort(obj)` AFTER the sentinel `cmd.alter` (mirrors the existing `insert_hider` pattern at mutation.py:76). This is defensive and matches the Phase 3 idiom. No adverse interaction with `attach_amino_acid` (attach is already done; sort just re-canonicalizes).

### Q24: Does altering `segi='GAME'` on a polymer residue break the cartoon trace?

**Verified (MEDIUM — needs runtime smoke confirmation): NO, it should NOT break the trace, but VERIFY.**

- `segi` is the segment identifier (a label). The `polymer` selector (cmd.py:363) is C-side, based on **backbone bond connectivity** (N-C-Cα bonds) and atom typing, NOT on `segi` continuity. Changing `segi` on a residue does not remove it from the polymer set — the residue is still bonded into the backbone.
- Cartoon traces the polymer by connectivity (consecutive Cα along bonded residues), not by segment label. `preset.py:395` shows cartoon for `polymer & ...` — the `polymer` selection is connectivity-based.
- **BUT:** `segi` is used by some operations (`bysegi`, segment-based selections). Altering `segi` on a mid-chain residue could affect `bysegi` grouping (it would split the chain into two segments for `bysegi` purposes). For our use (terminal extension + segi='GAME'), the new residue is at the terminus — it's the last residue in the chain, so `bysegi` would put it in a separate segment, which is fine (we WANT it separate for cleanup).
- **The risk:** if altering `segi` somehow makes the C engine re-classify the residue as non-polymer, the cartoon wouldn't render it. **This is the MEDIUM-confidence item.** The smoke test MUST assert `cmd.count_atoms("obj and segi GAME and polymer") > 0` after attach + alter segi — if this is 0, the trace broke and we need a different sentinel strategy (e.g., keep `segi` = neighbor's segi, use `b=-999` + `resn='HIDER'` as the sentinel instead — but that changes the cleanup selector).

**Mitigation if segi breaks the trace (fallback):** use `resn='HIDER'` + `b=-999` as the sentinel (cleanup by `resn HIDER and b < 0`) and keep `segi` = neighbor's segi for the polymer trace. This is a Phase 5 contingency — the smoke test determines which sentinel is safe for cartoon. **Primary plan: `segi='GAME'` (matches Phase 3); fallback: `resn='HIDER'` + `b=-999` if smoke fails.**

---

## 7. Open Risks (need a runtime spike or human decision before/during planning)

1. **[MEDIUM] Does altering `segi='GAME'` on an attached polymer residue break the `polymer` selector / cartoon trace?** Smoke must assert `count_atoms("obj and segi GAME and polymer") > 0` after attach+alter. If 0, fall back to `resn='HIDER'` + `b=-999` sentinel (cleanup selector migration). This is the single most consequential runtime unknown — it determines whether the Phase 3 sentinel survives cartoon or needs a Phase 5 variant.

2. **[MEDIUM] Does `cmd.attach_amino_acid` work with a NAMED selection (not `pk1`)?** editor.py:109-110 has a legacy `pk1` special-case (`"calling functions should pass '?pk1'"`), but the general path (line 125 `_self.select(tmp_connect,"(%s) & elem N,C"%selection)`) accepts any selection. The smoke must call `attach_amino_acid` with a named `"%s and chain X and resi Y and name C" % obj` selection and confirm it fuses (no `pk1` needed). If it requires `pk1`, we'd need `cmd.edit(terminus_sele)` to set pk1 first.

3. **[MEDIUM] Cartoon Cα-color-follows-atom (Q16).** Strong evidence (mutagenesis.py:474 copies `color`) but not C-verified. The smoke must assert the hider Cα color == neighbor Cα color after `cmd.alter`, and the human-verify must confirm the cartoon tube segment blends visually. If `cartoon_color` setting is non-default, the explicit color may not show — document.

4. **[MEDIUM] `cmd.color(int_index, selection)` with a raw int.** The appearance wizard stringifies the int (appearance.py:189-192 via `cmd.do`). For direct API `cmd.color(7, sele)`, `_interpret_color` passes `str(color)` to C (viewing.py:1898). **Safer path: use `cmd.alter(sele, "color = %d" % idx, space={})`** (Q14) — avoids the int-vs-string ambiguity. Plan should mandate `cmd.alter` for color, not `cmd.color(int)`.

5. **[LOW] Multiple cartoon hiders on one chain (count > 1).** Attaching N residues to the same terminus chains them (each attach extends the new terminus). This works but the `hider_specs` for cartoon must be processed in order, and each new residue's `resi` is the previous + 1. The dispatcher must handle this. For MVP, consider capping cartoon hiders to 1 per chain, or 1 total (simplest), and document the cap.

6. **[LOW] `cmd.iterate_state` for neighbor coords (line/stick placement).** Phase 3 found `cmd.iterate` does NOT expose x/y/z. `cmd.iterate_state(state, sele, "stored.append((x,y,z))")` does (state-dependent coords). Verify the state arg (1 = first state). The smoke must confirm `cmd.iterate_state(1, sele, "stored.append([x,y,z])", space={...})` returns coords.

7. **[LOW] `fab` / loop-replica option 2 deferred.** If the user wants the loop-replica variant later, it requires `cmd.fab` (builds a separate object) + `cmd.fuse` + altloc management. Not needed for MVP (option 1 satisfies HIDER-05). Document as a Phase 6 stretch goal.

8. **[LOW] Ribbon vs cartoon `rep` field mismatch.** One attached residue renders in BOTH `cartoon` and `ribbon` reps. If the user's scene shows `ribbon` (not `cartoon`), a hider generated as `rep='cartoon'` still renders in `ribbon` — but the registry says `'cartoon'`. Minor mismatch; the player still finds the same Cα. Option: generate the hider with `rep` = whichever of cartoon/ribbon is currently shown (`count_atoms("obj and rep cartoon") > 0`). The planner decides whether to add this nuance or accept the mismatch.

---

## 8. Resolved Research Flags (Q-numbered, with verified answers + file:line citations)

| Q | Question | Answer | Confidence | Source |
|---|----------|--------|-----------|--------|
| Q1 | Do lines/sticks render lone atoms? | NO — render BONDS only | HIGH | PITFALLS.md Minor (line 511) |
| Q2 | Blend via bonded pseudoatom? | YES — `cmd.bond` (same-object) | HIGH | editing.py:694-735 (line 717: "same object") |
| Q3 | Where to place line/stick hider? | Near real atom + small offset, then bond | MEDIUM | Design choice (no source rule) |
| Q4 | `cmd.bond` same-object? order param? | YES same-object; `order=1` single | HIGH | editing.py:694, 717, 711 |
| Q5 | Pitfall 8 — cartoon needs polymer trace? | YES — lone Cα pseudoatom invisible | HIGH | preset.py:395; Pitfall 8; mutagenesis.py:570 |
| Q6 | `attach_amino_acid` signature + polymer join? | `attach_amino_acid(sele, aa, ss=-1)`; joins polymer via fuse mode 2 | HIGH | editor.py:85-270 (lines 153, 160, 212) |
| Q7 | `cmd.fuse` modes? | 0=move+bond, 3=combine only, 1/2 internal | HIGH | editing.py:937-987 (line 958) |
| Q8 | Extend-at-terminal procedure? | iterate terminal N/C → attach_amino_acid → alter sentinel → identify → show | HIGH | editor.py:85-270; cmd.py:360 (`rep`) |
| Q9 | Loop-replica (option 2) harder? MVP? | YES harder (fab+fuse+altloc); DEFER | MEDIUM | editor.py:387-423 (`fab`); design analysis |
| Q10 | Ribbon vs cartoon requirements? | Same (polymer trace); one hider satisfies both | HIGH | preset.py:395; same backbone |
| Q11 | Verify cartoon renders? `cmd.count('cartoon',...)`? | NO `cmd.count`; use `count_atoms("... and rep cartoon")` | HIGH | querying.py:1412; cmd.py:360; mutagenesis.py:570; phase4_smoke.py:43 |
| Q12 | CPK by element? pseudoatom color? | C=green, N=blue, O=red; `elem='PS'` distinct; `elem='C'` blends | HIGH | PyMOL CPK default; PITFALLS Pitfall 3 |
| Q13 | `cmd.iterate` exposes `color`? | YES lowercase `color` (int index); `ID` uppercase | HIGH | editing.py:1444-1449; mutagenesis.py:474; phase4_smoke.py:56 |
| Q14 | Apply color via `cmd.color` or `cmd.alter`? | Both work; `cmd.alter("color = %d")` most reliable | HIGH | viewing.py:1858; internal.py:563; editing.py:1446; appearance.py:189 |
| Q15 | b=-999 sentinel vs spectrum b? | Option (c): keep b=-999 + explicit color; spectrum b is accepted limitation | HIGH | PITFALLS Pitfall 3; mutation.py:113,145 (read/cleanup paths) |
| Q16 | Cartoon color follows Cα? | YES by default (MEDIUM — runtime verify) | MEDIUM | mutagenesis.py:474; `cartoon_color` setting |
| Q17 | elem OR color OR both? | BOTH — elem for CPK/spectrum-elem, color for custom recolor | HIGH | Design analysis; PITFALLS Pitfall 3 |
| Q18 | Pure vs cmd-coupled split? | generators.py pure (offsets, terminal-pick); mutation.py cmd (bond, attach) | HIGH | AGENTS.md purity convention; Phase 4 pattern |
| Q19 | Extend insert_hider or add functions? | ADD `insert_line_stick_hider`, `insert_cartoon_hider`, `insert_hider_for_rep` | HIGH | Signature divergence; Phase 3 `insert_hider` unchanged |
| Q20 | `_on_start` mixed-rep flow? | Read `per_rep`; iterate neighbor pool + Cα list; dispatch per rep | HIGH | __init__.py:76-129; setup_state.py per_rep; gui_setup collect_state |
| Q21 | Cartoon headless-verifiable? | YES for rendering (count_atoms+rep); NO for visual blend (human) | HIGH | phase4_smoke.py:43; mutagenesis.py:570 |
| Q22 | attach/fuse break existing ids? | NO — only adds new atoms with new ids | HIGH | editing.py:937-987; Phase 3 smoke Q4 |
| Q23 | `cmd.sort` after attach? | YES defensive (editing.py:1457); preserves id | HIGH | editing.py:1457; mutation.py:76; Phase 3 smoke |
| Q24 | Alter segi breaks cartoon trace? | NO expected (polymer is connectivity-based); VERIFY in smoke | MEDIUM | cmd.py:363 (`polymer`); preset.py:395; fallback: resn='HIDER' |

---

## 9. Standard Stack (PyMOL 2.5.0 APIs used by Phase 5)

### Core cmd APIs (all verified against `tmp/pymol-src/modules/pymol/`)

| API | Signature | Purpose | Source |
|-----|-----------|---------|--------|
| `cmd.pseudoatom` | `pseudoatom(object, pos, name, segi, b, hetatm, elem, resn, chain, resi)` | Insert a single atom INTO existing object (sphere + line/stick hiders) | creating.py:1082 (Phase 3) |
| `cmd.bond` | `bond(atom1, atom2, order=1)` | Create a bond between two same-object atoms (line/stick hider) | editing.py:694-735 |
| `cmd.attach_amino_acid` | `attach_amino_acid(selection, amino_acid, ss=-1, hydro=-1, ...)` | Fuse a real residue at a terminus N/C (cartoon hider) | editor.py:85-270 |
| `cmd.fuse` | `fuse(selection1, selection2, mode=0, recolor=1, move=1)` | Merge two objects by a bond (internal to attach_amino_acid) | editing.py:937-987 |
| `cmd.fragment` | `fragment(name, object, origin=1)` | Load amino-acid fragment from library (internal to attach) | creating.py:929-958 |
| `cmd.fab` | `fab(input, name, mode='peptide', ss=0, ...)` | Build a peptide (DEFERRED — loop-replica option 2) | editor.py:387-423 |
| `cmd.alter` | `alter(selection, expression, space={})` | Mutate atom props (segi, b, color, ss, chain); space= hygienic | editing.py:1424-1473 |
| `cmd.iterate` | `iterate(selection, expression, space={})` | Read atom props (ID, color, chain, ss, elem); NO x/y/z | editing.py:1490+; symbol table editing.py:1444-1449 |
| `cmd.iterate_state` | `iterate_state(state, selection, expression, space={})` | Read atom coords (x, y, z) — needed for line/stick placement | (state-dependent; Phase 3 finding) |
| `cmd.identify` | `identify(selection, mode=0)` | Get stable atom ids (mode=0 → [id]; mode=1 → [(model,id)]) | querying.py:1269-1300 (Phase 3) |
| `cmd.count_atoms` | `count_atoms(selection)` | Count atoms in a selection; use `rep <name>` selector for rep counts | querying.py:1412-1434; cmd.py:360 (`rep`) |
| `cmd.show` | `show(representation, selection)` | Turn ON a rep flag for atoms (CRITICAL after attach/pseudoatom) | viewing.py:491-526 |
| `cmd.color` | `cmd.color(name_or_index, selection)` | Color atoms (prefer `cmd.alter` for int index) | viewing.py:1858-1899 |
| `cmd.sort` | `sort(object)` | Re-canonicalize after alter of segi/chain (preserves id) | editing.py:1457 (Phase 3) |
| `cmd.get_extent` | `get_extent(selection)` | Bounding box `[[min],[max]]` (sphere gen) | querying.py:1371-1392 (Phase 4) |
| `cmd.get_unused_name` | `get_unused_name(prefix)` | Unique temp name (for transient selections) | querying.py:74 |

### Selectors (verified in cmd.py:350-369 selector keyword list)

| Selector | Purpose |
|----------|---------|
| `polymer` | Polymer atoms (C-side, connectivity-based) — cartoon/ribbon trace |
| `rep <name>` | Atoms with rep `<name>` enabled (e.g., `rep cartoon`) — visibility check |
| `name CA` / `name N` / `name C` | Backbone atoms |
| `segi GAME` | Sentinel segment (cleanup/read) |
| `b < 0` | Sentinel b-factor (read path; NEVER `b -999`) |
| `id <N>` | Stable atom id (registry key; lowercase in selections) |
| `bound_to` / `neighbor` / `nbr.` | Bonded-atom selections (line/stick bond verification) |

### Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cartoon residue insertion | Manual N-C-Cα pseudoatom placement | `cmd.attach_amino_acid(sele, 'gly', ss=4)` | Real backbone geometry + dihedrals + polymer-trace join; manual pseudoatoms don't render in cartoon (Pitfall 8) |
| Bond creation | Manual bond records | `cmd.bond(atom1, atom2, order=1)` | C-side bond bookkeeping; manual edits corrupt the bond list |
| Color sampling | `cmd.get_model` + Python loop | `cmd.iterate(sele, "stored.append(color)", space={})` | Streams (no full copy); Pitfall 12 (get_model OOM on large objs) |
| Terminal residue detection | Guess by resi=1 | `cmd.iterate` polymer Cα + pure `pick_terminal_residue` | Robust to non-1-starting resi, insertion codes, multi-chain |
| Rep visibility check | Custom render query | `cmd.count_atoms("... and rep <name>")` | Canonical (mutagenesis.py:570); headless-runnable |

---

## 10. Code Examples (verified patterns from PyMOL source)

### Line/Stick hider insertion (mutation.py — new function)

```python
# Source: editing.py:694 (bond), creating.py:1082 (pseudoatom), editing.py:1424 (alter)
# Verified same-object bond requirement (editing.py:717)
def insert_line_stick_hider(object, offset, neighbor_id, handle,
                             segi='GAME', b=-999.0, bond_order=1):
    """Insert a bonded pseudoatom near neighbor_id (line/stick hider).
    Returns the new atom's stable id."""
    # 1. Read neighbor coords + props (iterate_state for x,y,z; iterate for elem/color)
    nbr = []
    cmd.iterate_state(1, "%s and id %d" % (object, neighbor_id),
                      "stored.append((x, y, z, elem, color))",
                      space={'stored': nbr})
    nx, ny, nz, n_elem, n_color = nbr[0]
    # 2. Insert pseudoatom at neighbor + offset, plausible elem (neighbor's elem)
    pos = [nx + offset[0], ny + offset[1], nz + offset[2]]
    cmd.pseudoatom(object=object, pos=pos, name=handle,
                   segi=segi, b=b, hetatm=0, elem=n_elem,  # plausible elem
                   resn='HIDER', chain='H', resi='9001')    # NOTE: chain/resn may need blending (Q17)
    # 3. Sentinel alter (segi, b, color=neighbor color) — single hygienic call
    cmd.alter("%s and name %s" % (object, handle),
              "segi='GAME'; b=-999.0; color=stored_c",
              space={'stored_c': n_color})
    cmd.sort(object)  # defensive (editing.py:1457)
    # 4. Bond to neighbor (same object — editing.py:717 satisfied)
    hider_ids = cmd.identify("%s and name %s and segi GAME" % (object, handle), mode=0)
    hider_id = hider_ids[0]
    cmd.bond("%s and id %d" % (object, hider_id),
             "%s and id %d" % (object, neighbor_id),
             order=bond_order)
    return hider_id
```

### Cartoon hider insertion (mutation.py — new function)

```python
# Source: editor.py:85 (attach_amino_acid), editor.py:160/212 (fuse mode 2),
#         editing.py:1424 (alter), viewing.py:491 (show), querying.py:1269 (identify)
def insert_cartoon_hider(object, terminus_sele, handle,
                         aa='gly', ss=4, hydro=0, segi='GAME', b=-999.0):
    """Attach a residue at a terminus (cartoon/ribbon hider).
    terminus_sele: single N or C atom selection (e.g., 'obj and chain A and resi 76 and name C').
    Returns the new residue's Cα stable id."""
    # 1. Read neighbor (terminus) props for blending (chain, ss, color)
    nbr = []
    cmd.iterate(terminus_sele + " and name CA",  # Cα of the terminal residue
                "stored.append((chain, ss, color))", space={'stored': nbr})
    # (for a C-terminus 'name C' sele, the neighbor Cα is in the same residue)
    n_chain, n_ss, n_color = nbr[0]
    # 2. Attach the residue (fuses with real backbone geometry, mode=2 internally)
    cmd.attach_amino_acid(terminus_sele, aa, ss=ss, hydro=hydro)
    # 3. The new residue's resi is terminal_resi +/- 1 (attach sets it internally).
    #    Find the new residue by the resi shift: select the new max-resi (C-term) residue.
    #    (The caller knows the terminus resi; new_resi = term_resi + 1 for C-term extension.)
    #    Apply sentinel + blend on the new residue's atoms:
    new_resi = ...  # caller supplies (term_resi + 1 for C-term, term_resi - 1 for N-term)
    new_sele = "%s and chain %s and resi %d" % (object, n_chain, new_resi)
    cmd.alter(new_sele,
              "segi='GAME'; b=-999.0; color=stored_c; ss=stored_ss",
              space={'stored_c': n_color, 'stored_ss': n_ss})
    cmd.sort(object)  # defensive (editing.py:1457)
    # 4. Show the cartoon rep on the new residue (CRITICAL — fused atoms start with no reps)
    cmd.show('cartoon', "%s and segi GAME" % object)
    # 5. Fetch the new Cα stable id (the cartoon-representative atom; the player clicks this)
    ids = cmd.identify("%s and name CA and segi GAME and resi %d" % (object, new_resi),
                       mode=0)
    assert len(ids) == 1, "expected 1 new cartoon Cα, got %r" % (ids,)
    return ids[0]
```

### Coloring / blend pattern (the mutagenesis wizard precedent — mutagenesis.py:474)

```python
# Source: mutagenesis.py:474 (read), editing.py:1444-1449 (color is read-write)
# Read neighbor (segi, chain, resi, ss, color) — then write blended props to hider
cmd.alter("%s and id %d and name CA" % (obj, neighbor_id),
          "stored.identifiers = (segi, chain, resi, ss, color)",
          space={'stored': stored})
n_segi, n_chain, n_resi, n_ss, n_color = stored['identifiers'][0]
# Write to hider: copy (chain, ss, color) for blend, OVERRIDE segi='GAME' + b=-999 for sentinel
cmd.alter("%s and id %d" % (obj, hider_id),
          "chain=stored_chain; ss=stored_ss; color=stored_c; segi='GAME'; b=-999.0",
          space={'stored_chain': n_chain, 'stored_ss': n_ss, 'stored_c': n_color})
```

### Cartoon visibility check (the mutagenesis precedent — mutagenesis.py:570)

```python
# Source: mutagenesis.py:570, phase4_smoke.py:43, cmd.py:360 (rep selector)
# After cmd.show('cartoon', 'obj and segi GAME'):
assert cmd.count_atoms("%s and segi GAME and name CA and rep cartoon" % obj) > 0
# Polymer membership (Q24 runtime verify):
assert cmd.count_atoms("%s and segi GAME and polymer" % obj) > 0
```

---

## 11. State of the Art (PyMOL 2.5.0 — current target)

| Capability | Status in PyMOL 2.5.0 | Impact on Phase 5 |
|-----------|----------------------|--------------------|
| `cmd.attach_amino_acid` | Stable, uses `cmd.fuse(mode=2)` internally | Cartoon hider mechanism — proven (mutagenesis wizard uses it) |
| `cmd.get_representations()` | DOES NOT EXIST in 2.5.0 (AGENTS.md) | Use `cmd.count_atoms("... and rep <name>")` instead (mutagenesis.py:570 pattern) |
| `cmd.count(rep, sele)` | DOES NOT EXIST (only `count_atoms`) | Use `count_atoms("... and rep <name>")` — success-criteria pseudocode is imprecise |
| `cmd.undo` / `undocontext` | NO-OP stub in open-source (editor.py:25-36) | `backup.snapshot` is the only recovery — Phase 3 already does this |
| `cmd.iterate` x/y/z | NOT exposed (state-dependent) | Use `cmd.iterate_state(state, ...)` for coords (line/stick placement) |
| `cmd.fab` | Stable (builds peptide as separate object) | DEFERRED for MVP (loop-replica option 2) |
| `polymer` selector | C-side, connectivity-based | Cartoon trace membership; `segi` alteration should NOT remove (Q24 — verify) |

---

## Sources

### Primary (HIGH confidence — PyMOL 2.5.0 source, directly read at `tmp/pymol-src/modules/pymol/`)

- `editor.py:85-270` — `attach_amino_acid(selection, amino_acid, ss=-1, hydro=-1, ...)`: validates single N/C atom (line 125), `_self.fragment(amino_acid, tmp_editor, origin=0)` (153), `_self.fuse("(%s and name C)"%(tmp_editor), tmp_connect, 2)` (160 backward / 212 forward), sets resi ± 1 (156/208), sets dihedrals by ss (176-252), cleans temp `_tmp_editor*` (268). `ss`: 1=helix, 2=antipara-beta, 3=para-beta, 4=flat (101).
- `editor.py:272-295` — `_aa_codes` 1-letter → fragment name map ('A'='ala', ..., 'G'='gly').
- `editor.py:387-423` — `fab(input, name, mode='peptide', ss=0)`: builds a peptide from 1-letter seq into a new object (uses `attach_amino_acid` internally). Deferred for MVP.
- `editor.py:13-21` — temp names `_tmp_editor0`, `_tmp_editor_con`, `_tmp_editor_dom`, `tmp_wild="_tmp_editor*"`.
- `editor.py:25-36` — `undocontext` is a NO-OP stub (no undo in open-source).
- `editing.py:694-735` — `bond(atom1, atom2, order=1)`: "atoms must both be within the same object" (717).
- `editing.py:937-987` — `fuse(selection1, selection2, mode=0, recolor=1, move=1)`: mode 0=move+bond, mode 3=combine only; "each selection must include a single atom in each object" (966); `recolor=1` recolors C atoms to match target (960).
- `editing.py:1424-1473` — `alter(selection, expression, space={})`: symbol table (1444-1449) `name, resn, resi, resv, chain, segi, elem, alt, q, b, vdw, type, partial_charge, formal_charge, elec_radius, text_type, label, numeric_type, model*, state*, index*, ID, rank, color, ss, cartoon, flags` (`*` = read-only). "sort after modifying names/chains" warning (1457).
- `editing.py:1490+` — `iterate(selection, expression, space=None)`: same symbols; `space=None` pollutes global `pymol.__dict__` (use `space={}`).
- `creating.py:929-958` — `fragment(name, object, origin=1)`: loads from fragment library (amino acids) via `load_model` into a new object.
- `creating.py:960-988` — `create(name, selection, source_state, target_state, discrete, ...)`.
- `viewing.py:491-526` — `show(representation, selection)`: turns on rep flag.
- `viewing.py:568-602` — `hide(representation, selection)`.
- `viewing.py:477-489` — `_showhide(rep, selection, value)`: calls `_cmd.showhide` (per-atom rep-mask flags).
- `viewing.py:1858-1899` — `color(color, selection)`: "color = string: color name or number"; calls `_interpret_color` then `_cmd.color(... str(color) ...)`.
- `internal.py:563-573` — `_interpret_color`: resolves names via `color_sc.interpret`; for non-string, returns `color` as-is (passed to C as string).
- `querying.py:74` — `get_unused_name(prefix)`.
- `querying.py:843-849` — `get_color_indices(all=0)`: returns color list.
- `querying.py:851-854` — `get_color_index(color)`: name → index.
- `querying.py:1269-1300` — `identify(selection, mode=0)`: mode=0 → [id], mode=1 → [(model,id)].
- `querying.py:1302-1330` — `index(selection)`: returns [(model,index)]; docstring warns "use integral atom identifiers instead of indices".
- `querying.py:1412-1434` — `count_atoms(selection)`: the canonical atom counter (NO `cmd.count(rep,sele)` exists).
- `cmd.py:350-369` — selector keyword list: includes `rep` (360), `polymer` (363), `b`, `color`, `ss`, `elem`, `id`, `name`, `chain`, `segi`, `resn`, `resi`.
- `preset.py:395` — `_self.show_as('cartoon', 'polymer & %' + s)`: cartoon shown for `polymer` selection.
- `wizard/mutagenesis.py:474` — `cmd.alter("?%s & name CA" % src_sele, "stored.identifiers = (segi, chain, resi, ss, color)", space=self.space)`: the canonical "blend a fragment by copying neighbor props" pattern — reads `(segi, chain, resi, ss, color)`.
- `wizard/mutagenesis.py:475` — `cmd.alter("?%s" % frag_name, "(segi, chain, resi, ss) = stored.identifiers[:4]", space=self.space)`: writes the blended props (note: uses `[:4]`, omits color here, but `color` is writable per symbol table).
- `wizard/mutagenesis.py:570` — `cartoon = (cmd.count_atoms("(%s & name CA & rep cartoon)"%src_sele)>0)`: the canonical cartoon-visibility check (`rep cartoon` selector + `count_atoms`).
- `wizard/mutagenesis.py:571` — `sticks = (cmd.count_atoms("(%s & name CA & rep sticks)"%src_sele)>0)`.
- `wizard/mutagenesis.py:660-667` — after residue replacement: `cmd.hide(...); cmd.show(self.rep,obj); cmd.show('lines',obj); if cartoon: cmd.show("cartoon",obj); if sticks: cmd.show("sticks",obj)` — **proves newly-fused atoms do NOT inherit shown reps; you must `cmd.show` explicitly.**
- `wizard/mutagenesis.py:631` — `cmd.bond(tmp_sele1, tmp_sele2)`: bonds single atoms (precedent for line/stick hider bonding).
- `wizard/appearance.py:145,189-192` — `color = int(color)` then `cmmd = mode+'("%s","%s")'%(color,sele)` → `cmd.do(cmmd)`: color index passed as stringified int.

### Secondary (HIGH confidence — project research, Phase 3/4 verified)

- `.planning/research/PITFALLS.md` — Pitfall 3 (pseudoatom defaults visible; `spectrum b` recoloring), Pitfall 8 (cartoon needs polymer trace; `pseudoatom + cmd.bond` for line/stick), Pitfall 9 (cleanup over-match), Pitfall 10 (no undo), Minor Pitfalls (lines/sticks render bonds).
- `.planning/research/ARCHITECTURE.md` — Pattern 6 (backup → mutate → cleanup/restore), HiderGenerator strategy-per-rep design.
- `.planning/phases/03-.../03-15-SUMMARY.md` — Phase 3 runtime-verified: `ID` uppercase in iterate, `b < 0` selector (never `b -999`), `cmd.iterate` no x/y/z (use `iterate_state`), id stable across insert/.pse, `space={}` hygienic, sentinel `segi='GAME'`+`b=-999` survives .pse.
- `.planning/phases/04-.../04-RESEARCH.md` — Phase 4 patterns: pure `generators.py` + cmd-coupled wiring; `GameController.start(hider_specs)` proven; `cmd.count_atoms("... and rep spheres and segi GAME")` works (phase4_smoke.py:43).
- `biochemeleon/generators.py` — Phase 4 pure `generate_sphere_positions(extent, n, seed)` (the purity pattern to extend).
- `biochemeleon/mutation.py` — Phase 3 `insert_hider` (sphere), `fetch_all_hider_ids` (`segi GAME and b < 0`), `cleanup_hiders` (`segi GAME` alone).
- `biochemeleon/game.py` — `GameController.start(hider_specs)` (snapshot → insert loop → register), `cleanup`, `abort_on_error`.
- `biochemeleon/__init__.py:76-129` — Phase 4 `_on_start` (resolve target → `cmd.get_extent` → `generate_sphere_positions` → `hider_specs` → `GameController.start` → `cmd.show('spheres', ...)` → countdown).
- `biochemeleon/setup_state.py` — `GAME_REPS=['lines','sticks','spheres','cartoon','ribbon']`, `DEFAULTS["per_rep"]`, `randomize_state` distributes `per_rep` across reps (196-205).
- `smoke/phase3_smoke.py`, `smoke/phase4_smoke.py` — headless smoke pattern (`cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`); `cmd.count_atoms("... and rep <name> ...")` confirmed at runtime (phase4_smoke.py:43).

### Tertiary (LOW/MEDIUM confidence — needs runtime smoke confirmation)

- Cartoon Cα-color follows atom color by default (Q16) — strong precedent (mutagenesis.py:474 copies `color`) but `cartoon_color` setting can override; MEDIUM until smoke + human-verify.
- `alter segi='GAME'` does not break `polymer` selector / cartoon trace (Q24) — connectivity-based `polymer` should be unaffected; MEDIUM until smoke asserts `count_atoms("obj and segi GAME and polymer") > 0`.
- `cmd.attach_amino_acid` works with a named selection (not `pk1`) (Open Risk 2) — general path accepts any sele (editor.py:125) but legacy `pk1` special-case exists; MEDIUM until smoke.

---

## Metadata

**Confidence breakdown:**
- Line/stick generation: **HIGH** — `cmd.bond` same-object requirement, lines/sticks render bonds, blend via bonded pseudoatom all verified (editing.py:694, PITFALLS Minor).
- Cartoon "extend-at-terminal": **HIGH** — `attach_amino_acid` signature, fuse mode 2, polymer join, rep-show requirement all verified (editor.py:85-270, mutagenesis.py:660-667, preset.py:395).
- Cartoon loop-replica (option 2): **LOW** — deferred; `fab`+`fuse`+altloc is complex and not needed for MVP.
- Hider coloring: **HIGH** for the read/write APIs (`color` lowercase, `alter` writable, mutagenesis precedent); **MEDIUM** for cartoon-color-follows-Cα and segi-doesn't-break-trace (runtime-verify).
- Architecture (pure/cmd split): **HIGH** — follows the proven Phase 3/4 convention (AGENTS.md).
- Verification & safety: **HIGH** — backup/restore unchanged, fuse only adds atoms, sort preserves id; **MEDIUM** for segi-vs-polymer (smoke-gated).

**Research date:** 2026-08-08
**Valid until:** 2026-09-07 (30 days — stable PyMOL 2.5.0 API; the runtime-verify items in §7 Open Risks should be resolved by the Phase 5 smoke test before they expire)
