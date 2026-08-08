---
status: resolved
trigger: "Cartoon hider visibility bug: 7 GAME-sentinel atoms confirmed present in 1ubq object (segi=GAME, b=-999, rep cartoon shown), but `select segi GAME; zoom sele` shows EMPTY SPACE — cartoon hider not visually rendering. Previous debug session (phase5-gui-3-issues) WRONGLY marked this resolved — hiders now insert but are still invisible."
created: 2026-08-08T21:00:00Z
updated: 2026-08-08T21:30:00Z
---

## Current Focus

hypothesis: A single isolated residue at a terminus does not render a visible cartoon segment. PyMOL cartoon draws tubes/arrows BETWEEN consecutive residues; a one-residue sheet (ss='S' copied from neighbor) at the N-terminus produces no visible arrow/tube because sheet arrows need multiple residues to form a body+head.
test: headless diagnostic — insert cartoon hider on 1ubq, then test (a) spheres on CA, (b) ss='H'/'L', (c) 2-residue segment, (d) zoom behavior
expecting: confirm single-residue cartoon invisible; identify which alternative makes it visible
next_action: write + run headless diagnostic script

## Symptoms

expected: User starts cartoon-hider game on 1ubq (fetch mode, per_rep cartoon=1). Runs `select segi GAME; zoom sele`. Should see the cartoon hider (a small cartoon segment at the N-terminus) visible in the viewer.
actual: zoom shows EMPTY SPACE — the 7 GAME-sentinel atoms exist (selector reports 7 atoms) but nothing renders visually in cartoon.
errors: none (game starts successfully, no exceptions)
reproduction: GUI — start cartoon game on 1ubq, run `select segi GAME; zoom sele` in PyMOL command line
started: discovered during 05-05 human-verify checkpoint (the prior debug session's Issue 3 was NOT actually fixed — only the insertion was fixed, not the visibility)

## Background (from objective)

- 7 GAME atoms confirmed present (segi=GAME, b=-999)
- cartoon rep shown on GAME C-alpha (verified headless)
- new residue = glycine attached at N-terminus (resi 0 for 1ubq)
- 3.79 Å from original N-term C-alpha
- new residue ss copied from neighbor ('S' = sheet for 1ubq N-terminus)
- so the hider is a one-residue sheet extension at the N-terminus

## Eliminated

- hypothesis: hiders not inserted (prior session's Issue 3 theory)
  evidence: 7 GAME atoms confirmed present; selector reports 7 atoms; insertion succeeds. The bug is RENDERING not INSERTION.
  timestamp: 2026-08-08T21:00:00Z

## Evidence

- timestamp: 2026-08-08T21:10:00Z
  checked: headless diagnostic (diag_cartoon_vis.py) — insert cartoon hider on 1ubq, render PNGs per variant
  found: |
    Mechanism: 7 GAME atoms (N,CA,C,O,H,3HA,HA); GAME CA in rep cartoon=1; GAME in polymer=7;
    new residue ss='S' (copied from neighbor); CA-CA distance=3.79 A; coords confirmed.
    PNG size comparison (400x300 ray, zoomed to GAME, white bg):
      A_sheet(ss=S, cartoon)=22801  B_loop(ss=L)=22871  C_helix(ss=H)=22800
      D_sphere(cartoon+spheres on CA)=26851  E_ctrl(neighbor, visible)=37235
      F_blank(cartoon HIDDEN on GAME)=22871
    A/B/C (cartoon, all ss) == F_blank (cartoon hidden) => cartoon renders NOTHING
    for a single residue regardless of ss. D_sphere > blank => spheres ARE visible.
  implication: Root cause CONFIRMED — PyMOL cartoon cannot render a visible segment for a single isolated terminal residue (tube/arrow drawn BETWEEN consecutive C-alphas; 1 residue = no segment). ss change (S/L/H) does NOT help. Spheres on CA is a working visible fallback.

- timestamp: 2026-08-08T21:10:00Z
  checked: game.py on_pick + cleanup_hiders + verify_intact for sphere-fallback safety
  found: on_pick uses registry by id (not rep); cleanup_hiders removes by segi GAME (all atoms); verify_intact checks (resn,resi,name,chain,segi) multiset (rep-agnostic). Adding spheres to cartoon CA breaks nothing.
  implication: Fix = show spheres on GAME C-alpha IN ADDITION to cartoon (visibility fallback). Clickability preserved (CA id registered). Blend preserved (neighbor color already copied).

## Resolution

root_cause: |
  PyMOL's cartoon renderer does NOT produce visible geometry for a single isolated
  residue at a polymer terminus. The cartoon tube/arrow is drawn BETWEEN consecutive
  C-alpha atoms; a one-residue N-terminal extension (the cartoon hider) has no
  "next" residue to form a segment toward, so nothing renders — regardless of ss
  (verified headless: ss='S'/'L'/'H' all render identical to a blank control where
  cartoon is hidden). The 7 GAME atoms exist and have rep cartoon shown, but the
  cartoon produces zero visible pixels. The prior debug session (phase5-gui-3-issues)
  wrongly marked this resolved — it only fixed INSERTION, not RENDERING.
fix: |
  In insert_cartoon_hider, AFTER showing cartoon on the GAME residue, ALSO show
  spheres on the GAME C-alpha (visible fallback). The cartoon show is kept
  (harmless — renders if the residue ever connects to 2+ residues). The sphere is
  colored with the neighbor's color (already copied via alter) so it blends, but
  its shape (sphere vs tube) makes it visible. The player clicks the C-alpha
  (now shown as a sphere) — clickability preserved (CA id is registered).
verification: |
  Headless verify_fix.py (actual fix code, not manual sphere show):
  - GAME CA in rep cartoon=1 (cartoon still shown, no regression)
  - GAME CA in rep spheres=1 (the fix — sphere on CA)
  - PNG with fix=26909 bytes vs blank=22847 bytes -> diff=4062 -> VISIBLE: True
    (sphere renders real visible content over the blank control)
  - cleanup removed=7 atoms, count back to 660 (orig) -> match=True
    (verify_intact passes; structure restored exactly)
  phase5_smoke.py: 26/26 ALL PASSED (was 25; +1 new regression check
    "cartoon: GAME C-alpha in rep spheres (visible fallback, 05-05)")
  WSL gates: py_compile OK; 173 unittests OK; Pitfall-1 0 matches;
    exec_ only on QMessageBox (allowed).
files_changed:
  - biochemeleon/mutation.py (insert_cartoon_hider: sphere on CA visibility fallback + docstring)
  - smoke/phase5_smoke.py (+1 regression check for sphere fallback)
