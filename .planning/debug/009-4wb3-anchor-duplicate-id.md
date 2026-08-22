---
status: resolved
trigger: "mixed protein-nucleic structure (4wb3 — nucleosome) fails when inserting a cartoon segment hider with AssertionError: expected 1 anchor id, got [256, 257]"
created: 2026-08-22T14:00:00Z
updated: 2026-08-22T15:30:00Z
resolved_by: quick-009 (commit 4f7ed72)
---

## Current Focus

hypothesis: 4wb3 has alt-conf CA atoms (ASN 710 alt A/B, GLU 734 alt A/B on chain A). The `backbone` selector in the segment copy matches BOTH alt-conf CAs. After retagging `alt=''`, both become duplicate atoms at the same (chain, resi, name, alt) -> anchor selector `name CA or name P` matches 2 -> AssertionError.
test: headless diagnostic script that loads 4wb3, builds cas_by_chain, calls pick_segments, simulates the copy+retag, and checks the anchor selector match count
expecting: if H1 is correct, (a) cas_by_chain may or may not have duplicates (depends on whether iterate matches all alt-confs), but (b) the segment copy WILL include both alt-conf CAs, and (c) after retag the anchor matches 2
next_action: write and run diag_4wb3_anchor.py headlessly

## Symptoms

expected: inserting a cartoon segment hider on 4wb3 should succeed (1 anchor id)
actual: AssertionError: expected 1 anchor id, got [256, 257] at mutation.py:689
errors: "expected 1 anchor id, got [256, 257]"
reproduction: load 4wb3, start game with cartoon hider(s) -> insert_cartoon_segment_hider -> assertion
started: after merging quick-005 (even segment spreading)

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-22T14:15
  checked: 4wb3 PDB chain composition
  found: 5 chains: A,B,C (protein, ATOM records, 68-69 res each), D,E (nucleic aptamer, HETATM records, non-standard L-nucleotide names 0A/0G/0DA etc.)
  implication: nucleic chains are HETATM with non-standard names; may or may not be classified as `polymer` by PyMOL

- timestamp: 2026-08-22T14:20
  checked: alt-conf in 4wb3 PDB
  found: 34 alt-conf atoms (17 altloc A + 17 altloc B), ALL on chain A, at 2 residues: ASN 710 (CA serials 256,257) and GLU 734 (CA serials 459,460)
  implication: atoms 256,257 from the assertion are the two alt-conf CA atoms of ASN 710 on chain A

- timestamp: 2026-08-22T14:25
  checked: mutation.py:641-644 retagging
  found: `cmd.alter(tmp, "chain='H'; segi='%s'; alt=''; ss='L'; resi=resv+%d" % (segi, CARTOON_RESI_OFFSET), space={})` — sets alt='' which clears alt-conf, merging both alt-conf CAs into duplicate atoms
  implication: if the segment copy includes both alt-conf CAs, retagging makes them duplicates -> anchor selector matches 2

- timestamp: 2026-08-22T14:45
  checked: headless diagnostic (diag_4wb3_anchor.py) — cas_by_chain composition
  found: chain A has 70 entries (68 unique resv + 2 duplicates at 710 and 734); chains D,E ARE classified as polymer (35 entries each, 39 P atoms each); 1xdn and 1gzm have ZERO alt-conf atoms
  implication: cas_by_chain duplicates inflate chain A to longest (70 > 69 > 68), causing it to be picked first by pick_segments; 1xdn/1gzm work because they have no alt-conf

- timestamp: 2026-08-22T14:50
  checked: headless diagnostic — segment copy + retag simulation
  found: Segment chain A resi 709-711 (middle=710): copy has 16 atoms (8 from 710 alt A + 8 from 710 alt B); after retag alt='', anchor selector matches 2 CA atoms -> identify returns [256, 257] -> ASSERTION WOULD FAIL. Same for segment 733-735 (middle=734): identify returns [459, 460] -> FAIL.
  implication: CONFIRMED — the backbone selector copies ALL alt-conf variants, and alt='' retagging merges them into duplicates

- timestamp: 2026-08-22T14:55
  checked: which hider counts trigger the bug (new even-spreading vs old adjacent)
  found: NEW even-spreading triggers at count=6 (first: start_resi=709, middle=710); OLD adjacent triggers at count=11. 1xdn/1gzm have 0 alt-conf atoms -> never trigger.
  implication: Pre-existing bug (alt='' retagging always merged alt-conf). Quick-005 lowered the trigger threshold from 11 to 6, making it more likely. NOT caused by quick-005, but EXPOSED by it.

## Resolution

root_cause: CONFIRMED. The `backbone` selector in the segment copy (mutation.py:632-634) matches ALL alt-conf variants of backbone atoms. 4wb3 has alt-conf at ASN 710 (CA IDs 256,257, altloc A/B) and GLU 734 (CA IDs 459,460) on chain A. When a segment's middle residue is an alt-conf residue, the copy contains 2 CA atoms at that residue. The retagging `alt=''` (mutation.py:641-644) merges both alt-conf CAs into duplicate atoms at the same (chain=H, resi=new_mid, name=CA, alt='', segi=GAME). The anchor selector `name CA or name P` (mutation.py:681-682) then matches 2 atoms -> AssertionError: expected 1, got [256, 257].

Additionally, `cas_by_chain` (__init__.py:409-414) is built from `polymer and (name CA or name P)` which matches BOTH alt-conf CAs, giving chain A 70 entries (68 unique + 2 duplicates). This inflates chain A's length, making it the longest chain (picked first by pick_segments), and compresses segment ranges (a 3-residue window may span only 2 unique residues).

fix: APPLIED (quick-009, commit 4f7ed72). Two-part fix:
1. __init__.py:412-414 — deduplicate cas_by_chain by (chain, resv) to prevent
   compressed segments (keep first entry per residue = alt-A; drop alt-B dup).
2. mutation.py:634 — after cmd.create(tmp,...), deduplicate alt-conf variants
   by removing duplicate (chain, resv, name) atoms, keeping the first.
verification: headless smoke pymol/smoke/diag_4wb3_altconf_fix.py — 32/32
checks pass. The DIRECT alt-conf segment inserts (chain A 709-711 mid=710,
733-735 mid=734; the exact path that pre-fix raised AssertionError) now
return 1 anchor each (ids 256, 459), no AssertionError. 6 pick_segments(count=6)
inserts also succeed; cleanup restores 3779 atoms exactly. phase5_smoke
(protein-only 1ubq) 41/41 pass — no regression (Fix 2 dedup is a no-op when
no alt-conf atoms present).
files_changed:
- pymol/biochemeleon/__init__.py (Fix 1: cas_by_chain dedup)
- pymol/biochemeleon/mutation.py (Fix 2: segment-copy alt-conf dedup)
- pymol/smoke/diag_4wb3_altconf_fix.py (verification smoke, 32/32 pass)
- pymol/smoke/diag_4wb3_anchor.py (bug-reproducer diagnostic, retained)
side_effect: Fix 1 dedup drops chain A from 70 -> 68 entries, so chain C (69)
becomes longest and pick_segments(count=6) lands all 6 segments on chain C
(no alt-conf) — Fix 1 alone shifts picks away from the alt-conf chain. Fix 2
is the essential defense for structures whose LONGEST chain has alt-conf
(directly verified by the chain-A alt-conf segment inserts).
