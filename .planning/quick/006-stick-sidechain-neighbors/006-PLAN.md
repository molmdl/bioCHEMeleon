---
phase: quick-006
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - pymol/biochemeleon/__init__.py
  - pymol/smoke/phase5_smoke.py
autonomous: true
commit_prefix: "fix(quick-006):"

must_haves:
  truths:
    - "The line/stick hider neighbor pool includes ALL heavy atoms (backbone + side chain), not just one-per-residue CA/P backbone atoms"
    - "Side-chain heavy atoms (e.g. CB) are valid bond targets for insert_line_stick_hider — the inserter already handles arbitrary neighbor_id (reads elem/color via iterate_state, copies for blend)"
    - "A stick hider bonded to a side-chain neighbor carries the correct sentinel (segi=GAME, b=-999) and blends (color == neighbor color)"
    - "Cleanup restores the original atom count after a side-chain-bonded stick hider (sentinel-only removal via segi GAME)"
    - "The cartoon/ribbon backbone pool at __init__.py line ~409 ('polymer and (name CA or name P)') is UNCHANGED — cartoon/ribbon render through the CA/P trace and MUST stay backbone-only"
    - "Hydrogens are excluded from the line/stick pool (not elem H — too many, tiny, poor bond targets); existing hiders excluded (not segi GAME)"
    - "Syntax gate, pitfall-1 gate, exec_ gate stay clean; pure unit tests (tests/test_setup_state.py) stay green"
    - "phase5_smoke.py passes headlessly (0 exit) with the new side-chain neighbor section ALL PASSED"
  artifacts:
    - path: "pymol/biochemeleon/__init__.py"
      provides: "Widened line/stick neighbor pool (not elem H) + rewritten rationale comment; cartoon/ribbon pool at line ~409 untouched"
      contains: "not segi GAME and not elem H"
    - path: "pymol/smoke/phase5_smoke.py"
      provides: "New smoke section proving a side-chain heavy atom (CB) works as a stick-hider neighbor (insert + sentinel + bond + blend + cleanup)"
      contains: "name CB and not elem H"
  key_links:
    - from: "pymol/biochemeleon/__init__.py:neighbor_ids pool (line ~393)"
      to: "pymol/biochemeleon/mutation.py:insert_line_stick_hider(neighbor_id=...)"
      via: "_rng.sample(neighbor_ids, k) -> each sampled id passed as neighbor_id to insert_line_stick_hider"
      pattern: "not segi GAME and not elem H"
    - from: "pymol/biochemeleon/__init__.py:line/stick pool (line ~393, CHANGED)"
      to: "pymol/biochemeleon/__init__.py:cartoon/ribbon pool (line ~409, UNCHANGED)"
      via: "two DISTINCT pools — line/stick widened to all heavy atoms; cartoon/ribbon stays 'polymer and (name CA or name P)' because cartoon draws through the backbone trace"
      pattern: "polymer and \\(name CA or name P\\)"
---

<objective>
Widen the line/stick hider neighbor pool from backbone-only (`name CA or name P`) to ALL heavy atoms (`not elem H`) so stick hiders can land on side-chain atoms instead of always bonding to the backbone trace (where cartoon/ribbon obscure them).

Purpose: v1 is shipped; this is a post-release gameplay-tuning fix. Stick hiders were almost always placed on backbone CA/P atoms — exactly where cartoon draws its tube — making them hard to find when cartoon is shown. Meanwhile every side-chain heavy atom was wasted as a potential hiding spot. The backbone-only restriction is STALE: it existed because a legacy terminal-valence step could remove non-CA atoms, but Phase 11's single-state refactor eliminated that step (`__init__.py` lines 489-495 confirm "the legacy terminal-extension path that needed it is no longer used"). Side-chain heavy atoms are stable, valid bond targets, and `insert_line_stick_hider` already handles arbitrary `neighbor_id` (it reads elem/color via `iterate_state` and copies them for blending — `mutation.py` lines 212-249). The change is purely "widen the pool."

Output: one selection-line change + comment rewrite in `__init__.py` (the line/stick pool ONLY — the cartoon/ribbon pool at line ~409 stays backbone-only), plus a new smoke section in `phase5_smoke.py` proving a side-chain neighbor (CB) works end-to-end headlessly. No `mutation.py` functional change.

Design is LOCKED by the orchestrator (pre-investigated). The new selector is `"%s and not segi GAME and not elem H"`. Do NOT propose alternatives (e.g. don't restrict to specific side-chain atoms, don't add `polymer`, don't touch the cartoon/ribbon pool).
</objective>

<execution_context>
@~/.config/opencode/get-shit-done/workflows/execute-plan.md
@~/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@pymol/AGENTS.md

# Source files to edit (read each before editing; verify line numbers — they may have shifted):
@pymol/biochemeleon/__init__.py
@pymol/smoke/phase5_smoke.py

# Reference (read-only — confirms insert_line_stick_hider handles arbitrary neighbor_id, NO change needed):
@pymol/biochemeleon/mutation.py
</context>

<tasks>

<task type="auto">
  <name>Task 1: Widen the line/stick neighbor pool + rewrite the rationale comment in __init__.py</name>
  <files>pymol/biochemeleon/__init__.py</files>
  <action>
Read `pymol/biochemeleon/__init__.py` around lines 380-415 first (confirm exact line numbers — they may have shifted). There are TWO distinct pools here; change ONLY the line/stick one:

1. **The line/stick pool (lines ~382-394) — CHANGE THIS.** Replace the comment block (lines ~382-391) AND the `cmd.iterate` selection (line ~393). The exact current text to replace is:

```python
        # For line/stick: pool of real neighbor backbone-anchor atom ids (to
        # bond hiders to). Uses 'name CA or name P' so BOTH protein (CA =
        # C-alpha) and nucleic acid (P = phosphate) backbones are covered —
        # nucleic acids have NO 'name CA' atoms (headless-verified 2026-08-16:
        # 5e54/1k8p/2qbz all return 0 for 'name CA'). P is the nucleic-acid
        # equivalent of CA: a stable one-per-residue backbone atom and a valid
        # bond target. (05-07 fix note: the original 'name CA' rationale was
        # that non-CA atoms could be removed by a terminal-valence step; Phase
        # 11 single-state path no longer runs that step, so the pool just needs
        # stable one-per-residue backbone atoms — CA for protein, P for NA.)
        neighbor_ids = []
        cmd.iterate("%s and not segi GAME and (name CA or name P)" % target_obj,
                    "stored.append(ID)", space={'stored': neighbor_ids})
```

Replace with:

```python
        # For line/stick: pool of real neighbor heavy-atom ids to bond hiders
        # to. 'not elem H' covers ALL heavy atoms (backbone + side chain) for
        # BOTH protein and nucleic acid — side-chain heavy atoms are stable
        # bond targets and land hiders OFF the backbone trace where cartoon/
        # ribbon would obscure them. 'not segi GAME' excludes existing hiders
        # from the pool. Hydrogens are excluded (too many, tiny, poor bond
        # targets). (quick-006 fix: the pool was previously backbone-only
        # 'name CA or name P' — one per residue — because a legacy terminal-
        # valence step could remove non-CA atoms. Phase 11's single-state
        # refactor eliminated that step, so the backbone-only restriction is
        # stale; side-chain heavy atoms are now valid, stable neighbors.
        # insert_line_stick_hider already handles arbitrary neighbor_id — it
        # reads elem/color via iterate_state and copies them for blending.)
        neighbor_ids = []
        cmd.iterate("%s and not segi GAME and not elem H" % target_obj,
                    "stored.append(ID)", space={'stored': neighbor_ids})
```

2. **The cartoon/ribbon pool (line ~409, `cmd.iterate("%s and polymer and (name CA or name P)" ...)` — DO NOT TOUCH.** This is a DIFFERENT pool consumed by `pick_segments` for cartoon/ribbon hiders. Cartoon/ribbon render through the backbone trace (CA for protein, P for nucleic), so a copied backbone segment must come from CA/P. Leave it and its surrounding comment (lines ~395-402) exactly as-is. Verify after editing that line ~409 still reads `polymer and (name CA or name P)`.

3. Do NOT modify `mutation.py`. The `insert_line_stick_hider` function already bonds to any `neighbor_id` and copies the neighbor's elem/color for blending (lines 212-249). The stale "ensure neighbor_ids are sampled from 'name CA' atoms that survive free_nterminal_valence" note in its ValueError message (mutation.py line ~224) is out of scope for this quick task — leave it.

Why `not elem H` (not a positive side-chain list): a positive list (e.g. `name CB or name CG or ...`) would be incomplete (different residue types have different side-chain atoms) and would need maintenance. `not elem H` is the minimal, complete, representationally-correct selector for "all heavy atoms" and is a strict superset of the old `name CA or name P` pool for both protein and nucleic acid. `not segi GAME` keeps existing hiders out of the pool. No `polymer` filter (mirrors the old pool, which also had none — ligand heavy atoms are valid stick bond targets too).
  </action>
  <verify>
From repo root (WSL — syntax only, imports NOT checked because `__init__.py` does `from pymol.Qt import ...` at module level):

```bash
python3.6 -m py_compile pymol/biochemeleon/__init__.py
```
MUST exit 0 (syntax valid).

Confirm the change landed and the cartoon/ribbon pool is untouched:
```bash
grep -n "not segi GAME and not elem H" pymol/biochemeleon/__init__.py
grep -n "polymer and (name CA or name P)" pymol/biochemeleon/__init__.py
```
First command: exactly ONE match (the line/stick pool). Second command: exactly ONE match (the cartoon/ribbon pool, unchanged).

Pitfall-1 + exec_ gates stay clean (this change adds no Qt/Tk imports and no `.exec_()` calls):
```bash
grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/
grep -rnE "\.exec_\(\)" pymol/biochemeleon/
```
First: ZERO matches. Second: only QFileDialog/QMessageBox hits (unchanged from baseline).
  </verify>
  <done>
The line/stick neighbor pool selection is `"%s and not segi GAME and not elem H"` with a rewritten comment explaining the quick-006 rationale (Phase 11 removed the terminal-valence step; side-chain heavy atoms are stable bond targets). The cartoon/ribbon pool at line ~409 is verifiably unchanged (`polymer and (name CA or name P)`). `py_compile` passes; pitfall-1 and exec_ gates stay clean.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add a side-chain-neighbor smoke section to phase5_smoke.py + run it headlessly</name>
  <files>pymol/smoke/phase5_smoke.py</files>
  <action>
Read `pymol/smoke/phase5_smoke.py` in full first (it is ~342 lines; confirm line numbers before editing). The existing section 2 (line/stick) picks a `name CA` neighbor — it tests the INSERT function with a backbone neighbor and MUST stay as-is (regression guard). This task ADDS a new section proving a SIDE-CHAIN heavy atom works as a neighbor, which is the new behavior unlocked by quick-006.

Insert a new section AFTER the optional spike block (the `try:` ... `except Exception as exc:` ending around line ~334) and BEFORE the `# --- summary ---` block (line ~336). Re-fetch 1ubq at the start of the section for a fully clean, self-contained slate (does not disrupt the spike's references to earlier atom ids). Insert exactly this block (indentation matches the file — 0 spaces for section comments, 0 spaces for top-level statements; `check(...)` calls are top-level):

```python

# --- 7. SIDE-CHAIN NEIGHBOR POOL (quick-006) ---
# quick-006 widened the line/stick neighbor pool from backbone-only
# (name CA or name P) to ALL heavy atoms (not elem H). Stick hiders
# previously always bonded to a backbone CA/P -- exactly where cartoon
# draws its tube, obscuring them. Side-chain heavy atoms are stable bond
# targets (Phase 11 removed the terminal-valence step that needed
# backbone-only). This section proves a SIDE-CHAIN neighbor works:
# insert_line_stick_hider bonds cleanly to a non-backbone heavy atom,
# sentinel is set, color blends, cleanup restores. (Section 2 still
# tests the backbone-CA neighbor path as a regression guard.)
cmd.delete(obj)
cmd.fetch("1ubq", async_=0)
orig_count_7 = cmd.count_atoms(obj)
# Pick a side-chain heavy atom: CB (beta carbon) -- present in most non-Gly
# residues, NOT a backbone atom (backbone = N, CA, C, O). 1ubq has many.
sc_ids = cmd.identify("%s and not segi GAME and name CB and not elem H" % obj, mode=0)
check("sidechain: 1ubq has CB atoms (side-chain pool non-empty)", len(sc_ids) > 0)
sc_neighbor_id = sc_ids[0]
offset_7 = [0.4, 0.4, 0.4]
sc_stick_id = mutation.insert_line_stick_hider(obj, offset=offset_7,
                                               neighbor_id=sc_neighbor_id,
                                               handle="S007", rep="sticks")
check("sidechain: insert_line_stick_hider returns int id (side-chain neighbor)",
      isinstance(sc_stick_id, int))
# sentinel set (segi=GAME, b=-999; iterate exposes segi/b lowercase, ID uppercase)
sc_sent = []
cmd.iterate("%s and id %d" % (obj, sc_stick_id), "stored.append((segi, b))",
            space={'stored': sc_sent})
check("sidechain: sentinel set",
      bool(sc_sent) and sc_sent[0][0] == 'GAME' and abs(sc_sent[0][1] - (-999.0)) < 1e-6)
# bonded to the side-chain neighbor (same neighbor(...) selector pattern as
# section 2; explicit outer parens force intended grouping -- see section 2 note)
check("sidechain: hider bonded to side-chain neighbor",
      cmd.count_atoms("(neighbor (%s and id %d)) and id %d" %
                      (obj, sc_neighbor_id, sc_stick_id)) > 0)
# color matches neighbor (blend -- insert copies neighbor color; Open Risk 3)
sc_nbr_col = []
cmd.iterate("%s and id %d" % (obj, sc_neighbor_id), "stored.append(color)",
            space={'stored': sc_nbr_col})
sc_hdr_col = []
cmd.iterate("%s and id %d" % (obj, sc_stick_id), "stored.append(color)",
            space={'stored': sc_hdr_col})
check("sidechain: color matches neighbor (blend)",
      bool(sc_nbr_col) and bool(sc_hdr_col) and sc_nbr_col[0] == sc_hdr_col[0])
print("diag: sc_stick_id=%r sc_neighbor_id=%r (CB) sc_nbr_col=%r sc_hdr_col=%r" %
      (sc_stick_id, sc_neighbor_id, sc_nbr_col, sc_hdr_col))
# cleanup restores count (sentinel-only via segi GAME; AGENTS.md domain rule)
mutation.cleanup_hiders(obj)
check("sidechain: cleanup restores count", cmd.count_atoms(obj) == orig_count_7)
check("sidechain: no GAME atoms remain after cleanup",
      cmd.count_atoms("%s and segi GAME" % obj) == 0)
```

Notes for the executor:
- The block goes BEFORE `# --- summary ---` (line ~336). The summary's fail-count logic (`fails = [n for n, c in RESULTS if not c]`) automatically picks up the new `check(...)` calls — no change to the summary block needed.
- `mutation` is already imported at the top of the file (line 18: `from biochemeleon import generators, game, mutation, registry`).
- `check` and `RESULTS` are defined at the top (lines 20-23) — reuse them; do NOT redefine.
- The `neighbor (...)` selector with explicit outer parens mirrors section 2's proven pattern (avoids PyMOL selector-precedence swallowing the intersect — see section 2 comment lines ~48-51).
- Do NOT modify section 2 (backbone-CA neighbor) — it stays as a regression guard for the original path.
  </action>
  <verify>
This is a cmd-coupled path (NOT WSL-unit-testable — `phase5_smoke.py` does `from pymol import cmd` at runtime). Verify headlessly via the Windows PyMOL bridge (AGENTS.md "Headless PyMOL CAN be run from WSL"):

```bash
# 1. Stage the package + smoke script to the Windows-facing path:
bash wsl2win_cp.sh
mkdir -p tmp/bioCHEMeleon/smoke && cp pymol/smoke/phase5_smoke.py tmp/bioCHEMeleon/smoke/
# 2. Run headlessly (no GUI, ~30-60s). Wrap in timeout + tail to avoid hangs:
cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase5_smoke.py" 2>&1 | tail -60
# 3. Check exit code: 0 = ALL PASSED; nonzero = a check FAILED or a crash.
```

Expected: the run prints `PASS: sidechain: ...` for all 6 new side-chain checks, ends with `ALL PASSED`, and exits 0. The diag line should print `sc_neighbor_id=<int>` (a CB atom id, NOT a CA) and matching `sc_nbr_col`/`sc_hdr_col` values (blend confirmed).

If a side-chain check FAILS or the script crashes:
- A `ValueError: neighbor_id ... not found` from `insert_line_stick_hider` would mean the CB id was stale — unlikely (no removal happens between `identify` and `insert` in this self-contained section), but if so, debug via `tmp/pymol-src/modules/pymol/querying.py` (identify) per AGENTS.md.
- A failed `bonded to side-chain neighbor` check would mean `cmd.bond` refused a side-chain target — consult `tmp/pymol-src/modules/pymol/editing.py` (bond, line ~694) and report back; do NOT silently weaken the assertion.
- Do NOT mark the task done with a failing check. Iterate the section until ALL PASSED, or report the blocker.

Also confirm the pure unit tests still pass (regression — the `__init__.py` edit must not break the package import surface; `test_setup_state.py` imports the pure `setup_state` layer only):
```bash
python3.6 -m unittest tests.test_setup_state -v
```
MUST be all-green (125 tests / whatever the current count is — no new failures).
  </verify>
  <done>
`phase5_smoke.py` has a new section 7 that re-fetches 1ubq, picks a CB (side-chain) heavy atom as the stick-hider neighbor, and proves: insert returns an int id; sentinel (segi=GAME, b=-999) is set; the hider is bonded to the side-chain neighbor; color blends (hider color == neighbor color); cleanup restores the original count and leaves no GAME atoms. The headless run prints `ALL PASSED` and exits 0. The pure unit tests stay green.
  </done>
</task>

</tasks>

<verification>
After both tasks, run the full gate suite from repo root (WSL):

```bash
# 1. Syntax (imports NOT checked -- __init__.py imports pymol.Qt at module level):
python3.6 -m py_compile pymol/biochemeleon/__init__.py pymol/biochemeleon/mutation.py pymol/smoke/phase5_smoke.py

# 2. Pitfall-1 gate (ZERO matches):
grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/

# 3. exec_ gate (only QFileDialog/QMessageBox hits, unchanged from baseline):
grep -rnE "\.exec_\(\)" pymol/biochemeleon/

# 4. Pure unit tests (regression -- must stay green):
python3.6 -m unittest tests.test_setup_state -v

# 5. Confirm BOTH pools are distinct and correct (line/stick widened, cartoon/ribbon untouched):
grep -n "not segi GAME and not elem H" pymol/biochemeleon/__init__.py     # exactly ONE match
grep -n "polymer and (name CA or name P)" pymol/biochemeleon/__init__.py  # exactly ONE match

# 6. Headless smoke (cmd-coupled verification -- the real gate for this change):
bash wsl2win_cp.sh
mkdir -p tmp/bioCHEMeleon/smoke && cp pymol/smoke/phase5_smoke.py tmp/bioCHEMeleon/smoke/
cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase5_smoke.py" 2>&1 | tail -60
# Expect: ALL PASSED, exit 0, 6 new "PASS: sidechain: ..." lines.
```

All six must pass. The headless smoke (step 6) is the authoritative verification — it exercises the widened pool's runtime behavior end-to-end.

Commit (single atomic commit covering both files — the smoke IS the verification for the code change, so they ship together):
```bash
git add pymol/biochemeleon/__init__.py pymol/smoke/phase5_smoke.py
git commit -m "fix(quick-006): widen stick hider neighbor pool to all heavy atoms

The line/stick hider neighbor pool was backbone-only (name CA or name P)
because a legacy terminal-valence step could remove non-CA atoms. Phase 11's
single-state refactor eliminated that step, so the restriction is stale.
Widen to 'not elem H' (all heavy atoms: backbone + side chain) so stick
hiders can land on side-chain atoms where cartoon/ribbon don't obscure them.
insert_line_stick_hider already handles arbitrary neighbor_id (reads
elem/color via iterate_state, copies for blend) -- no mutation.py change.

The cartoon/ribbon pool ('polymer and (name CA or name P)') is UNCHANGED --
cartoon/ribbon render through the backbone CA/P trace.

Adds phase5_smoke.py section 7: proves a CB (side-chain) heavy atom works
as a stick-hider neighbor (insert + sentinel + bond + blend + cleanup).
Headless smoke ALL PASSED."
```
</verification>

<success_criteria>
- `__init__.py` line/stick pool selection is `"%s and not segi GAME and not elem H"` with a rewritten rationale comment.
- `__init__.py` cartoon/ribbon pool is verifiably unchanged (`polymer and (name CA or name P)`).
- `phase5_smoke.py` has a new section proving a CB side-chain neighbor works (6 new PASS checks).
- Headless `phase5_smoke.py` run prints `ALL PASSED` and exits 0.
- `py_compile`, pitfall-1 gate, exec_ gate, and pure unit tests all clean/green.
- One `fix(quick-006):` commit covering both files.
</success_criteria>

<output>
After completion, create `.planning/quick/006-stick-sidechain-neighbors/006-SUMMARY.md` using the standard summary template. Note in the summary: the stale `free_nterminal_valence` reference in `mutation.py` line ~224's ValueError message (out of scope here — candidate for a future quick task).
</output>
