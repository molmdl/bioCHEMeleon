---
phase: quick-009
plan: 01
type: summary
subsystem: mutation + plugin init (alt-conf backbone handling)
tags: [alt-conf, mutation, cartoon-hider, anchor-duplicate, 4wb3, headless-smoke, bugfix]
files_modified:
  - pymol/biochemeleon/__init__.py
  - pymol/biochemeleon/mutation.py
  - pymol/smoke/diag_4wb3_altconf_fix.py
  - pymol/smoke/diag_4wb3_anchor.py
  - .planning/debug/009-4wb3-anchor-duplicate-id.md
commits:
  - hash: 4f7ed72
    msg: "fix(quick-009): dedup alt-conf backbone atoms in cartoon segment hider"
  - hash: (pending)
    msg: "docs(quick-009): close 4wb3 alt-conf anchor-duplicate fix (summary + debug resolved)"
---

# Quick Task 009 — Summary

## What

Fixed the `AssertionError: expected 1 anchor id, got [256, 257]` raised by
`insert_cartoon_segment_hider` on structures with **alternate-location
(alt-conf) backbone atoms**. 4wb3 (nucleosome, bundled demo) has alt-conf at
chain-A residues 710 (CA alt-A id=256, CA alt-B id=257) and 734; any structure
with alt-conf backbone atoms hit this — it is NOT specific to mixed
protein-nucleic. Quick-005's even segment spreading lowered the trigger
threshold from 11 to 6 hiders, exposing a pre-existing bug in the `alt=''`
retagging path.

Root cause: the `backbone` selector in the segment copy matches ALL alt-conf
variants of a residue's backbone atoms. The subsequent `alt=''` retag merges
both alt-conf CAs into duplicate atoms at the same
`(chain=H, resi=new_mid, name=CA, alt='', segi=GAME)`, so the anchor selector
`name CA or name P` matches N>1 → `AssertionError`.

Two-part fix, both verified headlessly on the bundled 4wb3 (32/32 smoke checks
pass; the exact pre-fail path now returns 1 anchor).

## Changes

### `pymol/biochemeleon/__init__.py` (Fix 1 — cas_by_chain dedup, +14/-1)

In `_continue_after_large_demo_fetch`, the `cas_by_chain` construction
(`cmd.iterate("polymer and (name CA or name P)")`) matches BOTH alt-conf CAs
per alt-conf residue, producing duplicate `(resv, ID)` entries. This inflates
chain lengths and compresses `pick_segments` windows (a 3-res window could
span only 2 unique residues), AND makes the alt-conf chain appear longest so
it is picked first.

Added a `_seen_res` set and dedup by `(chain, resv)`: keep the FIRST entry per
residue (alt-A; the alt-B duplicate is dropped). A comment explains WHY.

Side effect observed in the smoke: dedup drops chain A from 70 → 68 entries,
so chain C (69) becomes longest and `pick_segments(count=6)` lands all 6
segments on chain C (no alt-conf). Fix 1 alone shifts picks away from the
alt-conf chain for 4wb3. Fix 2 is the essential defense for structures whose
**longest** chain has alt-conf (directly verified below).

### `pymol/biochemeleon/mutation.py` (Fix 2 — segment-copy alt-conf dedup, +22)

In `insert_cartoon_segment_hider`, immediately after
`cmd.create(tmp, segment_sele, 1, 1, zoom=0)` and BEFORE the `cmd.alter(tmp,
... alt='' ...)` retag: iterate `tmp` for `(ID, chain, resv, name)`, find
duplicate `(chain, resv, name)` atoms (the alt-conf variants), and
`cmd.remove` the duplicates by id (keeping the first per key). This prevents
the `alt=''` retag from merging both alt-conf CAs into true duplicates, so
the anchor selector matches exactly 1.

Hygienic `space={'stored': ...}` (AGENTS.md; never `space=None`). Iterates
expose the atom id as UPPERCASE `ID` (AGENTS.md; editing.py:1444-1449). The
dedup is a **no-op when no alt-conf atoms are present** (`_dup_ids` is empty,
no `cmd.remove` calls) — verified by the protein-only phase5_smoke regression.

### `pymol/smoke/diag_4wb3_altconf_fix.py` (verification smoke, +267)

New headless smoke (the authoritative fix verification). Imports the REAL
`biochemeleon.{backup,generators,mutation}` modules so it exercises the actual
fix code path — not a copy. 32 checks across 8 sections:

1. Load bundled 4wb3 (3779 atoms).
2. Detect alt-conf backbone atoms (chain A 710: ids [256,257]; 734: [459,460]).
3. Build `cas_by_chain` WITH the Fix-1 dedup; assert 0 duplicate `(chain,
   resv)` entries and that the alt-conf residues were the ones deduped.
4. `pick_segments(count=6)` → 6 segments on chain C (Fix 1 side effect: picks
   avoid the alt-conf chain); informational, not a failure.
5. Insert the 6 `pick_segments` hiders via the REAL `insert_cartoon_segment_hider`
   → all return int ids, no AssertionError.
6. **DIRECT alt-conf segment inserts** (authoritative Fix 2 test): chain A
   resi 709-711 (middle=710, alt-conf CA [256,257]) and 733-735 (middle=734,
   [459,460]) — the EXACT path that pre-fix raised AssertionError. Both now
   return 1 anchor each (ids 256, 459 = the alt-A variants; dedup keeps first),
   no AssertionError.
7. All 8 anchors are DISTINCT ids and exactly 1 GAME sentinel atom each
   (`segi GAME and b < 0`).
8. `cleanup_hiders` + `backup.discard` → object restores to 3779 atoms exactly.

### `pymol/smoke/diag_4wb3_anchor.py` (bug-reproducer diagnostic, +272, retained)

The diagnostic written during the diagnosis phase that confirmed the bug
mechanism (loads 4wb3, builds `cas_by_chain` with the OLD unfixed logic, calls
`pick_segments`, simulates the copy+retag, and shows the anchor selector
matching 2). Retained in the repo as the bug reproduction case; documents how
the root cause was isolated (does NOT import the real modules — copies the
logic so it is a static snapshot of the pre-fix behavior).

### `.planning/debug/009-4wb3-anchor-duplicate-id.md` (status → resolved)

Updated the diagnosis note frontmatter `status: diagnosed` → `status:
resolved` (with `resolved_by: quick-009 (commit 4f7ed72)`) and the
`## Resolution` section from `fix: (not yet — find_root_cause_only mode)` /
`files_changed: []` to the applied fix details, verification results, and
files changed. Follows the established `.planning/debug/` pattern
(`docs(11): update debug status to resolved`).

## Verification (run, all green)

1. **Unit tests**: `PYTHONPATH=pymol python3.6 -m unittest tests.test_generators
   tests.test_setup_state tests.test_game_controller -v` → `Ran 197 tests in
   0.093s — OK` (exit 0). No regression in the pure/testable layer.
2. **Syntax gate**: `python3.6 -m py_compile pymol/biochemeleon/__init__.py
   pymol/biochemeleon/mutation.py pymol/smoke/diag_4wb3_altconf_fix.py` →
   exit 0 (all three compile).
3. **Pitfall-1 gate**: `grep -rnE "import Tkinter|import tkinter|from
   tkinter|import Pmw|from Pmw|app\.root|grab_set|mainloop|Toplevel|
   menuBar\.addmenuitem|from PyQt5 import|import PyQt5" pymol/biochemeleon/`
   → **0 matches** (exit 1 = no matches; the desired result). No new
   forbidden imports.
4. **exec_ gate**: `grep -rnE "\.exec_\(\)" pymol/biochemeleon/` → 3 matches,
   all on `msg.exec_()` / `help_dlg.exec_()` child dialogs (gui_game.py:345,
   gui_game.py:404, __init__.py:965) — the allowed pattern (QMessageBox /
   child QDialog, NOT the main PluginDialog which stays modeless via
   `.show()`). My edits (line ~412 in __init__.py, ~634 in mutation.py) did
   NOT touch any of these. No new violations.
5. **Headless smoke (authoritative for the 4wb3 fix)**:
   `cd tmp/bioCHEMeleon && timeout 120 cmd.exe /c "C:\src\run-conda-pymol.bat
   -cq smoke\diag_4wb3_altconf_fix.py"` → **32/32 checks passed**, exit 0.
   The DIRECT alt-conf segment inserts (the exact pre-fail path) return 1
   anchor each with no AssertionError; cleanup restores 3779 atoms exactly.
6. **Regression — protein-only**: `phase5_smoke.py` (1ubq, no alt-conf) →
   **41/41 passed**, exit 0. Fix 2's dedup is a no-op when no alt-conf atoms
   are present (`_dup_ids` empty), so the non-alt-conf path is unaffected.

## Backward compatibility

- **`cas_by_chain` shape unchanged**: still `{chain: [(resi, ca_id), ...]}`;
the dedup only removes duplicate `(chain, resv)` entries (alt-conf variants),
keeping one entry per residue. `pick_segments` consumes the list by index
(`resis[i]`, `resis[i + segment_size - 1]`) and only depends on the return
shape + disjointness, both preserved. The dedup is strictly more correct
(one anchor per residue, which is the intended semantic).
- **`insert_cartoon_segment_hider` signature unchanged**; the dedup block is
an internal step between two existing operations (`cmd.create` → dedup →
`cmd.alter`). For non-alt-conf structures the block does nothing (no atoms
removed, no ids change), so existing callers and the phase5_smoke legacy
path are unaffected.
- **Anchor id semantics**: Fix 2 keeps the FIRST (alt-A) variant and removes
the alt-B duplicate. The returned anchor id is therefore the alt-A id (256
for resi 710, 459 for resi 734), which is the lower-numbered id and the one
`cmd.iterate` yields first (alt-A before alt-B). This is deterministic and
matches the "keep first" dedup policy used in Fix 1.

## Deviations from plan

None — plan executed exactly as written. The two-part fix (both files in one
`fix(quick-009):` commit) matches the task's commit-style guidance. The only
addition beyond the literal spec was the smoke's structure: the task said to
call `pick_segments(count=6)` and assert each segment returns 1 anchor. During
execution I discovered that with Fix 1 applied, `count=6` picks land on chain C
(the new longest chain after dedup), so the alt-conf middle is NOT exercised
by `count=6` alone. I therefore added a DIRECT alt-conf segment test (chain A
709-711 / 733-735, middle = the alt-conf residue) to authoritatively verify
Fix 2 — this is the exact pre-fail path. This is a verification strengthening
(Rule: the plan's verification goal is met more rigorously), not a scope
change; both fixes are verified. Documented in the smoke's header comment and
Section 6.

## Out of scope / untested

- The fix is verified headlessly on 4wb3 (the bundled demo that triggered the
bug). Other alt-conf structures were not exhaustively tested, but the root
cause (alt-conf backbone atoms + `alt=''` retag) is general and the fix
addresses it at the mechanism level (dedup by `(chain, resv, name)`).
- The visual blend (does the displaced middle residue still look like part of
the trace?) remains a human-verify checkpoint, unchanged by this fix (the fix
only changes WHICH atoms are in the copy, not the displacement or rendering).
- STATE.md / ROADMAP.md are NOT updated by this executor (orchestrator handles
after merge, per the task constraints).

## Commits

- `4f7ed72` — `fix(quick-009): dedup alt-conf backbone atoms in cartoon
  segment hider` (4 files: __init__.py, mutation.py, diag_4wb3_altconf_fix.py,
  diag_4wb3_anchor.py; +575/-1)
- (pending) — `docs(quick-009): close 4wb3 alt-conf anchor-duplicate fix
  (summary + debug resolved)` (this SUMMARY + the debug note status update)

One atomic fix commit (both code fixes + their verification/diagnostic smokes)
+ one bookkeeping commit, matching the task's commit-style guidance
("`fix(quick-009):` for the code fix (both files in one commit);
`docs(quick-009):` for the summary").
