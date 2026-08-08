---
status: resolved
trigger: "Fix Phase 5 cartoon hider visibility so it renders as a proper cartoon tube (blending with the cartoon), NOT as a sphere. Previous sphere fallback (ef3dbb0) was too easy to find."
created: 2026-08-08T22:00:00Z
updated: 2026-08-08T22:45:00Z
---

## Current Focus

hypothesis: Attaching 2 glycine residues at the N-terminus gives PyMOL two consecutive C-alphas to draw a cartoon tube segment BETWEEN, making the hider visible as a short tube that blends with the existing cartoon (no sphere needed).
test: headless diagnostic — attach 2 glycines at 1ubq N-term, render PNG, compare byte count vs 1-residue (blank) and sphere fallback.
expecting: 2-residue PNG byte count > 1-residue (blank) PNG, proving the tube renders visible content.
next_action: write + run headless diagnostic confirming 2-residue tube renders

## Symptoms

expected: Cartoon hider renders as a short cartoon tube segment at the N-terminus that blends with the existing cartoon (same color, same style) — visible but not a glaring sphere.
actual: Previous fix (ef3dbb0) showed the C-alpha as a SPHERE — "a big green sphere... I don't need to cheat to see it." Defeats the hide-and-seek purpose. Too easy to find.
errors: none
reproduction: GUI — start cartoon game on 1ubq, see a sphere at the N-terminus instead of a blended tube.
started: The sphere fallback was added in ef3dbb0 because a single isolated residue renders no cartoon geometry.

## Eliminated

- hypothesis: hiders not inserted (prior session's theory)
  evidence: 7 GAME atoms confirmed present; insertion succeeds. Bug was RENDERING not INSERTION.
  timestamp: 2026-08-08T21:00:00Z
- hypothesis: changing ss (S/L/H) makes single-residue cartoon visible
  evidence: headless PNG comparison — ss S/L/H all render identical to blank control (cartoon hidden). Single residue = no segment regardless of ss.
  timestamp: 2026-08-08T21:10:00Z
- hypothesis: sphere fallback is an acceptable visible blend (the previous fix)
  evidence: User reports sphere is too easy to find — "a big green sphere." A sphere does NOT blend with the cartoon; it stands out by shape. Reject as the hider mechanism.
  timestamp: 2026-08-08T22:00:00Z

## Evidence

- timestamp: 2026-08-08T22:00:00Z
  checked: git history (ef3dbb0) + existing debug session (phase5-cartoon-hider-invisible.md)
  found: |
    Root cause already confirmed: PyMOL cartoon draws tubes/segments BETWEEN consecutive
    C-alpha atoms. A single isolated residue at the N-terminus has no "next" residue
    toward which to draw a tube -> zero visible pixels. The sphere fallback was a
    visibility hack that breaks the blend (sphere shape stands out).
  implication: Fix = attach 2 residues so there are 2 consecutive C-alphas (the tube renders between them). Remove sphere fallback.

## Resolution

root_cause: |
  PyMOL's cartoon renderer draws tubes/segments BETWEEN consecutive C-alpha atoms.
  A single isolated residue at the N-terminus has no segment to draw (zero visible
  pixels). The sphere fallback (ef3dbb0) made it visible but as a SPHERE, not a
  blended tube — defeating the hide-and-seek purpose.
fix: |
  Attach TWO glycine residues at the N-terminus so PyMOL has 2 consecutive C-alphas
  to draw a cartoon tube segment between. The 2nd residue is "support geometry"
  (not a separate hider). Clean sentinel design: segi=GAME on ALL atoms of both
  residues (cleanup removes all via `segi GAME`), b=-999 on the clickable CA ONLY
  (fetch_all_hider_ids returns 1 -> 1 registry entry per hider). id-diff selection
  (not resi) because `resi -1` parses as a RANGE in PyMOL, not a residue number.
  Free the 1st glycine's N valence (remove H) before the 2nd attach. NO sphere
  fallback — the tube blends (neighbor color + ss copied via alter).
verification: |
  Headless 1-residue vs 2-residue PNG comparison (400x300 ray, zoomed to GAME):
    1-residue cartoon only: 1911 bytes (vs blank 2195) -> diff=-284 -> VISIBLE=False
      (a single residue renders NOTHING — even smaller than the blank control)
    2-residue cartoon only: 6313 bytes (vs blank 2195) -> diff=4118 -> VISIBLE=True
      (the tube between the 2 new C-alphas renders real content)
    1-residue + sphere (old fallback): 21599 bytes (3.4x bigger than the tube —
      a glaring sphere that defeated the hide-and-seek purpose)
  Production insert_cartoon_hider verify (actual mutation.py code):
    GAME atoms=13 (2 residues, 6+7 after H removal for 2nd attach);
    GAME C-alphas in rep cartoon=2 (both residues -> tube renders);
    GAME atoms in rep spheres=0 (sphere fallback REMOVED);
    fetch_all_hider_ids=[('1ubq', 662)] count=1 (clean sentinel -> 1 per hider);
    clickable CA sentinel (segi,b,color)=('GAME',-999.0,26) (blends: color=26=neighbor);
    PNG tube=8698 vs blank=2187 diff=6511 VISIBLE=True;
    cleanup removed=13 after=660=orig MATCH=True; verify_intact=True; GAME after=0.
  phase5_smoke.py: 28/28 ALL PASSED (was 26+1 sphere check; replaced sphere check
    with: 2 C-alphas in rep cartoon, NO GAME atoms in rep spheres, fetch +=1,
    2-residue backbone >=6 atoms).
  WSL gates: py_compile OK (biochemeleon/*.py + smoke); 173 unittests OK;
    Pitfall-1 0 matches; exec_ only on QMessageBox (allowed).
files_changed:
  - biochemeleon/mutation.py (insert_cartoon_hider: 2-residue attach via id-diff,
    clean sentinel segi=GAME-all/b=-999-CA-only, free 1st N valence for 2nd attach,
    removed sphere fallback; full docstring rewrite)
  - smoke/phase5_smoke.py (removed sphere-fallback check; added 2-residue tube
    check, no-spheres regression guard, clean-sentinel fetch +=1 check, 2-residue
    backbone >=6; fetch_before_cartoon delta capture)
