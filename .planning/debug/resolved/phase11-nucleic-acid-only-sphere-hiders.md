---
status: resolved
trigger: "nucleic acid systems seems to accept only sphere hiders. confirmed that cartoon hider has error with finding connection point so fallback to sphere. not sure about wire/stick/ribbon. tested with bundled nucleic acid. unsure if glycoprotein/membrane has this issue."
created: 2026-08-16T00:00:00Z
updated: 2026-08-16T01:00:00Z
gui_verified: 2026-08-16 — user confirmed PASS in real Windows PyMOL GUI on 1k8p (DNA): cartoon/ribbon segment P atoms (DG`10004/P, DG`10003/P, DT`10007/P) + sphere hiders (HIDER`9001/H000-H003) clickable; real-trace miss (A/K`26/K); mark_found green recolor fires ("Colored 1180 atoms"). Session closed by user ("working, can close it now").
---

## Current Focus

hypothesis: CONFIRMED — `name CA` selectors excluded nucleic acids (no CA atoms).
fix: APPLIED — generalized to `name CA or name P` (P = nucleic phosphate trace atom).
verification: PASSED — 45/45 hider-insertion tests + 12/12 render tests + 77/77
Phase 11 smoke (protein regression) all green headlessly.

## Symptoms

expected: All 5 GAME_REPS (lines, sticks, spheres, cartoon, ribbon) should produce
hiders for ANY loaded molecule the game supports, including nucleic acids (DNA/RNA)
and mixed protein+nucleic systems.
actual: On bundled nucleic-acid demos (5e54 RNA, 1k8p DNA, 2qbz RNA), only sphere
hiders appear. Cartoon hider errors ("finding connection point") and falls back to
sphere. Line/stick/ribbon behavior on nucleic acids is UNCONFIRMED.
errors: "finding connection point" error reported by user on cartoon hider path for
nucleic acids. Matches `editor.attach_amino_acid` "invalid connection point"
(editor.py:126) — a PROTEIN-only primitive.
reproduction: Load a bundled nucleic acid demo (5e54/1k8p/2qbz) via Setup tab,
configure multiple reps (spheres=1, sticks=1, cartoon=1, ribbon=1), click Start.
Observe: only sphere hiders appear (or sphere fallback).
started: Discovered during Phase 11 follow-up testing (2026-08-16).

## Eliminated

- hypothesis: The "finding connection point" error is reachable on current HEAD
  evidence: On current HEAD (22f53d4), `_prepare_and_start` builds 4-tuples
  (line 243-244) which route to `insert_cartoon_segment_hider` (cmd.create, NOT
  attach_amino_acid). For nucleic acids, `cas_by_chain` is EMPTY (no CA) →
  `pick_segments` returns [] → 0 segments → NO 4-tuples built → NO cartoon insert
  attempted → NO error, just silent sphere fallback. The "connection point" error
  is from the Phase 5 era 3-tuple path (`insert_cartoon_hider` via
  `editor.attach_amino_acid`), which is NOT dispatched from the GUI on current HEAD.
  timestamp: 2026-08-16T00:04Z

## Evidence

- timestamp: 2026-08-16T00:01Z
  checked: `biochemeleon/__init__.py:174,185` — data-collection selectors
  found: Both use `name CA`. Nucleic acids have NO CA atoms (they use P, C1', C4' etc.)
  implication: `neighbor_ids` (lines/sticks) and `cas_by_chain` (cartoon/ribbon) are
  EMPTY for pure-nucleic demos → 0 non-sphere hiders → sphere fallback at line 255-258.

- timestamp: 2026-08-16T00:02Z
  checked: `biochemeleon/__init__.py:255-258` — sphere fallback
  found: `if not hider_specs:` → defaults to spheres using hider_count.
  implication: When all non-sphere reps produce 0 hiders, hider_specs is empty →
  sphere fallback fires. THIS is the "fallback to sphere" the user observed.

- timestamp: 2026-08-16T00:03Z
  checked: `biochemeleon/mutation.py:662` — anchor selection in insert_cartoon_segment_hider
  found: `anchor_sele = ("%s and chain H and resi %d and name CA and segi %s" ...)`
  implication: Even if segment copy succeeds (backbone is nucleic-aware), the anchor
  selection `name CA` would fail for nucleic backbone (no CA). Must also generalize.

- timestamp: 2026-08-16T00:03Z
  checked: `tmp/pymol-src/modules/pymol/editor.py:126` — "connection point" error
  found: `print("Error: invalid connection point: must be one atom, name N or C.")`
  in `attach_amino_acid` — a PROTEIN-only primitive.
  implication: User's "finding connection point" = "invalid connection point" from
  `editor.attach_amino_acid`, reachable ONLY via the legacy 3-tuple path. On current
  HEAD, this path is NOT dispatched from the GUI (4-tuples only). The error is from
  an older version (pre-d65fb2c single-state refactor).

- timestamp: 2026-08-16T00:05Z
  checked: Headless diagnostic (smoke/diag_nucleic_hiders.py) — atom counts per selector
  found: 5e54 (RNA): name CA=0, name P=133, polymer=2826, backbone=1598.
         1k8p (DNA): name CA=0, name P=22, polymer=502, backbone=258.
         2qbz (RNA): name CA=0, name P=153, polymer=3263, backbone=1837.
         1znf (protein control): name CA=25, name P=0.
         4wb3 (mixed): name CA=213 (chains A/B/C), name P=78 (chains D/E).
  implication: CONFIRMS root cause — pure-nucleic demos have 0 CA atoms. `name P`
  is the correct nucleic anchor (one per residue, stable, valid bond target, and
  the PyMOL cartoon trace atom for nucleic acids). `polymer and (name CA or name P)`
  captures both protein + nucleic. `backbone` already matches both.

- timestamp: 2026-08-16T00:15Z
  checked: Headless verification (smoke/verify_nucleic_fix.py) — full hider insertion
  found: ALL 5 reps produce hiders on ALL 5 demos (45/45 PASS):
    1znf: 5 specs, 5 registry, cleanup 424→424 ✓
    5e54: 5 specs, 5 registry, cleanup 2844→2844 ✓
    1k8p: 5 specs, 5 registry, cleanup 555→555 ✓
    2qbz: 5 specs, 5 registry, cleanup 3408→3408 ✓
    4wb3: 5 specs, 5 registry, cleanup 3779→3779 ✓
  implication: Fix works — all reps (including lines/sticks/cartoon/ribbon) produce
  hiders on nucleic acids. Cleanup restores original atom count (no corruption).

- timestamp: 2026-08-16T00:20Z
  checked: Headless render verification (smoke/verify_nucleic_render.py) — rep visibility
  found: Cartoon + ribbon DO render on nucleic GAME segments (12/12 PASS):
    1znf: cartoon=30 atoms, ribbon=15 atoms on GAME segment ✓
    5e54: cartoon=72 atoms, ribbon=36 atoms on GAME segment ✓
    1k8p: cartoon=66 atoms, ribbon=33 atoms on GAME segment ✓
    2qbz: cartoon=72 atoms, ribbon=36 atoms on GAME segment ✓
  implication: The `backbone` selector correctly copies nucleic backbone (P, O5',
  C5', C4', C3', O3'), and PyMOL's cartoon renderer draws the trace through P atoms.

- timestamp: 2026-08-16T00:25Z
  checked: Phase 11 smoke (smoke/phase11_smoke.py) — protein regression
  found: 77/77 PASS (no regression on protein path).
  implication: The `name CA or name P` change is backward-compatible — protein
  demos still match `name CA` (they have no P), so behavior is unchanged.

- timestamp: 2026-08-16T00:26Z
  checked: WSL gates (py_compile, unit tests, pitfall-1 grep, exec_ gate)
  found: All pass — 112/112 unit tests, 0 pitfall-1 matches, 1 exec_ (QMessageBox,
  allowed).
  implication: Fix is clean and doesn't violate any project constraints.

## Resolution

root_cause: The hider data-collection selectors in `_prepare_and_start`
(`biochemeleon/__init__.py:174,185`) and the anchor selection in
`insert_cartoon_segment_hider` (`biochemeleon/mutation.py:662`) all used
`name CA` exclusively. Nucleic acids (DNA/RNA) have NO `name CA` atoms —
their backbone trace atom is P (phosphate). This made `neighbor_ids`
(lines/sticks bond targets) and `cas_by_chain` (cartoon/ribbon segment
anchors) EMPTY for pure-nucleic demos, causing 0 non-sphere hiders to be
generated. When `hider_specs` stayed empty (or only spheres were configured),
the sphere fallback at `__init__.py:255-258` fired — the "fallback to sphere"
the user observed. The "finding connection point" error was from an older
version (Phase 5 era 3-tuple path via `editor.attach_amino_acid`, a
PROTEIN-only primitive); on the current HEAD (post-Phase-11 single-state
refactor), the cartoon path silently produces 0 hiders instead of erroring.

fix: Generalized the anchor-atom selector from `name CA` (protein-only) to
`name CA or name P` (protein CA + nucleic acid P) in three locations:
  1. `biochemeleon/__init__.py:174` — neighbor_ids collection (lines/sticks)
  2. `biochemeleon/__init__.py:185` — cas_list collection (cartoon/ribbon)
  3. `biochemeleon/mutation.py:662` — anchor selection in insert_cartoon_segment_hider
P is the nucleic-acid equivalent of CA: a stable one-per-residue backbone atom,
a valid bond target for line/stick hiders, and the PyMOL cartoon trace atom
(the cartoon renderer draws the tube through P for nucleic acids, just as it
draws through CA for proteins). The `backbone` selector (already used in the
segment copy at mutation.py:616) already matches both protein and nucleic
backbones, so no change was needed there. `pick_segments` uses resi values
(not atom names), so it works unchanged.

verification:
  - Headless hider-insertion test (smoke/verify_nucleic_fix.py): 45/45 PASS
    — all 5 reps produce hiders on all 5 demos (1znf protein, 5e54 RNA,
    1k8p DNA, 2qbz RNA, 4wb3 mixed); cleanup restores original atom count.
  - Headless render test (smoke/verify_nucleic_render.py): 12/12 PASS
    — cartoon + ribbon reps render on nucleic GAME segments.
  - Phase 11 smoke (smoke/phase11_smoke.py): 77/77 PASS — no protein regression.
  - WSL gates: py_compile OK, 112/112 unit tests, 0 pitfall-1 matches,
    exec_ gate clean (QMessageBox only).
  - GUI verification (human-verify): PASSED 2026-08-16 — user confirmed in a
    real Windows PyMOL GUI session on 1k8p (DNA bundled demo). Cartoon/ribbon
    segment P atoms + sphere hiders register clicks; real-trace atoms miss;
    mark_found green recolor fires. Session closed by user
    ("working, can close it now").

files_changed:
  - biochemeleon/__init__.py: `name CA` → `(name CA or name P)` at lines 174, 185
    + updated comments explaining the nucleic-acid generalization.
  - biochemeleon/mutation.py: `name CA` → `(name CA or name P)` at line 662
    (anchor selection) + updated docstrings/comments.

deferred:
  - Glycoprotein (sasdpg4) / membrane protein (1gzm, 3gp6): all are type
    'protein' (have CA atoms), so the fix doesn't affect them. They require
    network fetch (not bundled), so headless verification was not possible.
    Defer to Phase 9 checkpoint.
  - GUI human-verify: RESOLVED 2026-08-16 (user-verified PASS on 1k8p DNA;
    see frontmatter `gui_verified`).
  - Known pre-existing limitation: `new_mid = new_start + 1` in
    insert_cartoon_segment_hider assumes consecutive resi values in the
    segment window. This applies to BOTH protein and nucleic (missing residues
    create gaps). Not triggered by the bundled demos (consecutive resi). Not
    introduced by this fix.
