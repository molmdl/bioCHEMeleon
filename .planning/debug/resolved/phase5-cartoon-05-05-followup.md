---
status: resolved
trigger: "Debug two Phase 5 cartoon hider issues from 05-05 human-verify: (1) 'Made 5 hiders, only got 1' — user requested 5 cartoon hiders but only 1 generated; (2) 'disconnected arrow cartoon' — 2-residue cartoon hider renders as a disconnected arrow segment"
created: 2026-08-08T22:00:00Z
updated: 2026-08-08T22:35:00Z
---

## Current Focus

hypothesis: (Issue1) pick_terminal_residues caps at one cartoon hider per chain; 1ubq has 1 chain -> max 1 hider even if user requests 5. By design (Open Risk 5). Fix = user warning, not 5 hiders. (Issue2) insert_cartoon_hider step 8 copies neighbor ss ('S' for 1ubq N-term sheet) onto GAME residues via alter, so the 2-residue extension renders as a flat sheet ARROW that visually separates from the main chain tube.
test: (Issue1) unit-test pick_terminal_residues with 1 chain + max_chains=5 -> assert len==1. (Issue2) headless diagnostic: fetch 1ubq, insert cartoon hider, dump ss of N-term residues + CA-CA distances + render PNG (ss=neighbor) vs PNG (ss=L).
expecting: (Issue1) len==1 confirms by-design cap. (Issue2) ss='S' on GAME CAs confirms root cause; ss='L' renders a smoother connected tube.
next_action: write + run Issue1 unit test, then Issue2 headless diagnostic

## Symptoms

expected: (Issue1) User sets cartoon hider count to 5 on 1ubq, clicks Start, expects 5 cartoon hiders. (Issue2) Cartoon hider renders as a CONTINUOUS extension of the chain (blends with the main cartoon), not a disconnected floating arrow.
actual: (Issue1) Only 1 cartoon hider generated (remaining counter shows 1, not 5). (Issue2) The 2-residue cartoon hider at the N-terminus renders as a small "disconnected arrow" that floats separate from the main chain.
errors: none (game starts successfully)
reproduction: GUI — fetch 1ubq, set cartoon count to 5, click Start (Issue1); zoom to N-terminus, observe the cartoon hider (Issue2)
started: discovered during 05-05 human-verify checkpoint (follow-up to two prior resolved sessions: phase5-gui-3-issues, phase5-cartoon-hider-invisible)

## Eliminated

- hypothesis: geometry gap (CA-CA distance too large, creating a visual disconnect)
  evidence: diag_disconnect headless — CA-CA dist resi -1->0 = 3.78A, 0->1 = 3.79A, 1->2 = 3.80A. All normal (~3.8A, standard peptide backbone). No geometry gap.
  timestamp: 2026-08-08T22:10:00Z

- hypothesis: segi=GAME breaks the cartoon polymer trace (hypothesis b)
  evidence: diag_junction headless — 4 variants (ss=S/L x segi=GAME/A) at tight junction zoom all have ~490,500 non-bg pixels (within 0.03% = noise). If segi broke the trace, segi='A' would produce MORE pixels (connected) vs segi=GAME (gap). No difference -> segi does NOT break the cartoon trace. The cartoon IS continuous across the A->GAME boundary.
  timestamp: 2026-08-08T22:15:00Z

- hypothesis: ss='S' creates a literal rendering gap (missing tube between GAME and original)
  evidence: diag_junction — ss='S' and ss='L' have identical pixel counts (490559 vs 490509 = 0.01% noise). If ss='S' had a gap, it would have FEWER pixels. No gap -> the cartoon trace IS continuous regardless of ss. The "disconnected" look is a SHAPE issue (arrow vs tube), not a literal gap.
  timestamp: 2026-08-08T22:15:00Z

## Evidence

- timestamp: 2026-08-08T22:05:00Z
  checked: pick_terminal_residues (pure function, WSL) — 1ubq (1 chain) with max_chains=5
  found: returns len=1, out=[('A', 1, False)]. Multi-chain test: 3 chains + max_chains=5 -> len=3 (capped by available chains); 3 chains + max_chains=2 -> len=2 (capped by max_chains). So effective cap = min(max_chains, num_chains).
  implication: Issue 1 is BY DESIGN (Open Risk 5: attaching many cartoon hiders to one terminus chains them). 1ubq has 1 chain -> max 1 cartoon hider regardless of requested count. Fix = user warning (NOT generating 5 hiders). Warning fires when len(terminals) < count for cartoon branch.

- timestamp: 2026-08-08T22:10:00Z
  checked: diag_disconnect headless — insert cartoon hider on 1ubq, dump ss of N-term residues
  found: ss BEFORE insert: resi 1-5 all ss='S' (1ubq N-term is a beta strand). ss AFTER insert: GAME residues (resi -1, 0) get ss='S' (copied from neighbor via step 8 alter `ss=stored_ss` where stored_ss=n_ss=neighbor's ss). CA-CA distances all ~3.8A (normal, connected).
  implication: Root cause of "disconnected arrow" = the 2 GAME residues inherit ss='S' (sheet) from the neighbor. A 2-residue ss='S' segment renders as a small flat sheet ARROW in cartoon. This small arrow shape looks visually "disconnected" from the main chain tube even though the trace IS continuous. The function's OWN docstring says "ss=4 (flat/loop) gives the least conspicuous extension (no helix ribbon or sheet arrow)" — but step 8 contradicts this by copying the neighbor's ss.

- timestamp: 2026-08-08T22:15:00Z
  checked: diag_junction headless — 4 variants at tight junction zoom, pixel counting
  found: A(ss=S,segi=GAME)=490559 B(ss=L,segi=GAME)=490509 C(ss=S,segi=A)=490613 D(ss=L,segi=A)=490468. All within 0.03% (noise). The cartoon trace IS continuous in all variants (no literal gap). The "disconnected" look is a SHAPE issue (sheet arrow shape vs loop tube shape), not a rendering gap.
  implication: Fix = set ss='L' (loop) on GAME residues instead of copying neighbor's ss. A loop renders as a smooth round TUBE that visually connects as a continuous extension. A sheet renders as a flat ARROW that looks like a separate object. This aligns the display ss with the geometry ss (ss=4 parameter = flat/loop dihedrals, already loop-like).

## Resolution

root_cause: |
  Issue 1 (5 hiders -> 1): pick_terminal_residues caps cartoon hiders at one per chain
    (Open Risk 5: attaching many to one terminus chains them). 1ubq has 1 chain ->
    max 1 cartoon hider regardless of requested count. BY DESIGN, not a bug. The
    missing piece is USER FEEDBACK — the user is not told that fewer hiders were
    generated than requested.
  Issue 2 (disconnected arrow): insert_cartoon_hider step 8 copies the neighbor's
    ss onto the GAME residues (ss=stored_ss where stored_ss = neighbor ss). For
    1ubq, the N-terminus is a beta strand (ss='S'), so the 2 GAME residues get
    ss='S'. A 2-residue ss='S' segment renders as a small flat sheet ARROW in
    cartoon. The arrow SHAPE looks visually "disconnected" from the main chain
    tube even though the cartoon trace IS continuous (verified: no literal gap;
    CA-CA ~3.8A normal; pixel counts identical across ss=S/L and segi=GAME/A).
    The function's own docstring says "ss=4 (flat/loop) gives the least
    conspicuous extension (no helix ribbon or sheet arrow)" but step 8
    contradicts this by copying the neighbor's ss.
fix: |
  Issue 1 (5 hiders -> 1): Added a QMessageBox.warning in __init__._on_start
    that fires when len(terminals) < count for the cartoon/ribbon branch. The
    warning is non-blocking (game still starts with the hiders that WERE
    generated) and explains WHY (one-per-chain to avoid chaining at a terminus).
    The message: "Requested 5 cartoon hiders but only 1 chain available; 1 hider
    generated (cartoon/ribbon hiders attach one per chain to avoid chaining them
    at a terminus)." NOT a code-generation change (generating 5 hiders on 1 chain
    would chain them — bad); just user feedback.
  Issue 2 (disconnected arrow): In mutation.insert_cartoon_hider step 8, changed
    the alter from ss=stored_ss (neighbor's ss) to ss='L' (loop). A 2-residue
    loop renders as a smooth round TUBE that connects as a continuous extension;
    a 2-residue sheet (ss='S' from a beta-strand neighbor) renders as a flat
    ARROW that looks disconnected. Also simplified step 1 (iterate reads only
    color, not chain/ss — n_ss is no longer needed). Updated the docstring to
    explain the ss='L' rationale and align the display ss with the geometry ss
    (ss=4 parameter = flat/loop dihedrals).
verification: |
  Headless phase5_smoke.py: 29/29 ALL PASSED (was 28; +1 new regression check
    "cartoon: GAME C-alphas ss='L' (loop tube, not sheet arrow, 05-05)").
  WSL gates: py_compile OK; 173 unittests OK; Pitfall-1 0 matches;
    exec_ only on QMessageBox (gui_game.py:137, allowed).
  Issue 1 warning logic: verified headless (pure function) — count=5, 1 chain
    -> warning fires; count=1, 1 chain -> no warning; count=5, 3 chains ->
    warning fires. Message format correct.
  Issue 2 ss='L': verified headless — GAME C-alphas now have ss='L' (smoke
    check confirms count_atoms("... and segi GAME and name CA and ss L") >= 2).
    Color still matches neighbor (blend preserved). Cleanup still restores
    count to orig (660). Cartoon trace IS continuous (pixel test confirmed no
    literal gap in any variant).
files_changed:
  - biochemeleon/__init__.py (Issue 1: _on_start under-generation warning for cartoon/ribbon)
  - biochemeleon/mutation.py (Issue 2: insert_cartoon_hider ss='L' loop instead of neighbor ss)
  - smoke/phase5_smoke.py (+1 regression check for ss='L')
