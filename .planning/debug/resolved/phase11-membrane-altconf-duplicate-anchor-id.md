# Phase 11 Bug: Membrane-protein cartoon-segment hider — duplicate anchor id

**Status:** RESOLVED — fix applied (commit 0702563) + headless-verified (86/86 smoke) + GUI human-verified APPROVED on 1gzm (2026-08-16). Root cause was NOT alt-confs (the original hypothesis was wrong) — it was an unquoted blank-chain PyMOL selector. See "Corrected Root Cause" section below.
**Scope:** Phase 11 (cartoon/ribbon segment hider), NOT Phase 9
**Severity:** blocks mixed-rep on membrane proteins (1gzm, 3gp6, sasdpg4) — sphere hiders work fine
**Triggered by:** selecting 1gzm / 3gp6 / sasdpg4 (MemProtMD / SASBDB demos) + any non-sphere hider (cartoon or mixed-rep with cartoon/ribbon)

## Reproduction

1. Start the plugin in Windows PyMOL GUI (`setenv.bat` → `pymol`)
2. Select "Membrane protein — 1gzm (Very challenging)" → set hider count + a non-sphere rep (cartoon, or mixed sphere+cartoon+stick) → Start
3. After fetch+finalize completes, the drain calls `_continue_after_large_demo_fetch` → `GameController.start(hider_specs)` → for the cartoon/ribbon hider, `insert_hider_for_rep` dispatches to `insert_cartoon_segment_hider` → **AssertionError**

## Error message (exact)

Three variants observed, all in the same code path:

```
AssertionError: expected 1 anchor id, got [25, 25]          # 1gzm first attempt
AssertionError: expected 1 anchor id, got [25, 25, 19]     # sasdpg4 mixed-rep
AssertionError: expected 1 anchor id, got [24, 24]          # 1gzm restart (after delete all)
```

The `[id, id]` signature (same id twice) is NOT alt-conf duplication (the
trigger files have NO alt-confs — verified on MemProtMD-cached 1gzm.pdb.gz,
3gp6 dry, and SASDPG4 fit2_model1). It is a PyMOL selector parser quirk with
blank chain identifiers (see Root cause below). The specific id values (25,
24, 895, 19) depend on the structure's atom ordering; the doubling mechanism
is identical across all three trigger structures.

## Stack trace (canonical, from 1gzm first attempt)

```
File ".../biochemeleon/__init__.py", line 481, in drain
    self._continue_after_large_demo_fetch(
File ".../biochemeleon/__init__.py", line 380, in _continue_after_large_demo_fetch
    self._controller.start(hider_specs)
File ".../biochemeleon/game.py", line 84, in start
    aid = mutation.insert_hider_for_rep(
File ".../biochemeleon/mutation.py", line 751, in insert_hider_for_rep
    return insert_cartoon_segment_hider(
File ".../biochemeleon/mutation.py", line 676, in insert_cartoon_segment_hider
    assert len(ids) == 1, "expected 1 anchor id, got %r" % (ids,)
AssertionError: expected 1 anchor id, got [25, 25]
```

## Root cause (VERIFIED — NOT alt-conf)

~~The original hypothesis (below, struck through) attributed the bug to native
alt-confs in the trigger structures. This was DISPROVEN: the orchestrator
verified that the MemProtMD-cached 1gzm.pdb.gz, 3gp6 dry, and SASDPG4
fit2_model1 ALL have blank altLoc on every atom (NO alt-confs). The bug is
something else entirely.~~

~~**1gzm and 3gp6 have native alternate conformations (altLoc).** The segment
selection matches alt-conf atoms multiple times...~~ — WRONG.

### The actual root cause: unquoted blank-chain PyMOL selector

The trigger structures (1gzm, 3gp6, sasdpg4) share a critical structural
property: **ALL atoms are on a single BLANK chain** (chain identifier = `''`,
the empty string). This is standard for MemProtMD membrane simulations (one
unnamed chain containing the protein + lipids).

`insert_cartoon_segment_hider` (mutation.py:619) builds the segment selection:
```python
segment_sele = "%s and chain %s and resi %d-%d and backbone" % (
    backup_name, chain, start_resi, end_resi)
```
When `chain` is `''` (blank), the format string produces `chain  and ...`
(chain + space + empty + space + and) — an **unquoted blank chain selector**.
PyMOL's C-level selector parser interprets this malformed selector in a way
that **IGNORES the object scope** (`backup_name and ...`) and matches
blank-chain atoms from **EVERY object in the session**.

### The doubling mechanism (confirmed headlessly on 3gp6)

1. `backup.snapshot("3gp6")` creates `_bchm_backup` — now TWO objects with
   blank-chain atoms exist (3gp6 + _bchm_backup, both 19221 atoms).
2. `cmd.count_atoms("_bchm_backup and chain  and resi 77-79 and backbone")`
   returns **30** (not 15) — it matches the 15 backbone atoms from
   `_bchm_backup` AND the 15 identical atoms from `3gp6`, ignoring the
   `_bchm_backup and` scope.
3. `cmd.create(tmp, segment_sele, 1, 1, zoom=0)` copies 30 atoms — each of
   the 15 source atoms appears TWICE with the same id (PyMOL preserves source
   ids; the same atom from two objects gets the same id).
4. After retagging to chain H + new resi, there are **2 CAs** at
   `(chain H, resi new_mid, segi GAME)` with the **same id**.
5. `cmd.identify(anchor_sele + " and b < 0", mode=0)` returns `[895, 895]`
   (or `[25, 25]` on 1gzm — the id depends on the structure's atom ordering).
6. `assert len(ids) == 1` → **AssertionError**.

### Why 1ubq does NOT trigger the bug

1ubq has chain `A` (a named, non-blank chain). The unquoted `chain A` selector
is well-formed and correctly scopes to the named object. No doubling. The
Phase 11 smoke (77/77 on 1ubq) passed because it never exercises the blank-
chain path.

### Evidence (headless diagnostic on 3gp6 dry, 2026-08-16)

Diagnostic: `smoke/diag_phase11_dup_id.py` — loads `tmp/3gp6_default_dppc-
atomistic_dry.pdb` (19221 atoms, ALL on blank chain, NO alt-confs, NO
duplicate serials) and traces `insert_cartoon_segment_hider` step-by-step.

Key output (BEFORE fix):
```
  [step1] segment_sele = '_bchm_backup and chain  and resi 77-79 and backbone'
  [step1] atoms matching segment_sele in backup: 30         ← DOUBLED (expect 15)
  [step1] same WITHOUT chain filter: 15                      ← correct (no chain filter)
  [step1] tmp has DUPLICATE IDS: [(884, 2), (886, 2), ...]  ← each atom twice
  [step2] CAs at (chain H, resi 10078): 2                    ← TWO anchor CAs
  [step7] identify(...) = [895, 895]                         ← THE CRASH
  >>> BUG REPRODUCED on 3gp6!
```

Selector-form probe (`smoke/test_backup_selector.py`):
```
  chain (blank)     3gp6=30  backup=30  *** DIFFERS (expect 15)
  chain ''          3gp6=15  backup=15  SAME (correct)
  chain ""          3gp6=15  backup=15  SAME (correct)
```
With 3 objects in session: unquoted `chain ` matches 45 (triple) — confirming
it matches across ALL objects, ignoring the named-object scope.

### The fix

**Single-quote the chain value in all `chain %s` selectors** in mutation.py:
`chain %s` → `chain '%s'`. The quoted form `chain ''` is unambiguous — the
parser correctly scopes to the named object and matches only blank-chain
atoms from that object (15, not 30). Verified for both blank chains (`''`)
and named chains (`'A'`, `'H'`): both return the correct count with no
duplicates.

Applied to all 6 `chain %s` occurrences in mutation.py:
- `insert_cartoon_segment_hider` segment_sele (line 632) — THE BUG
- `insert_cartoon_hider` residue_sele (line 390) — defensive (legacy path)
- `free_nterminal_valence` n_sele + cap detection + cap removal + H removal
  (lines 841, 848, 854, 857) — defensive (legacy path)

### Verification

- **1ubq regression:** `smoke/phase11_smoke.py` **86/86 PASSED** (77 original
  tests + 9 new blank-chain regression tests in section N). The new section N
  retags 1ubq to a blank chain (mimicking MemProtMD layout) and verifies the
  cartoon hider inserts cleanly + cleanup restores.
- **3gp6 fix confirmation:** `game.start` on 3gp6 dry **SUCCEEDED**
  (registry len=1, id=895, endpoint_resvs=(10077, 10079)). `cleanup` restored
  count to 19221 (original). No AssertionError.
- **WSL gates:** py_compile (0), unit tests (112 OK), Pitfall-1 (0 matches),
  exec_ (QMessageBox only) — all green.
- **GUI human-verify PENDING:** the fix cannot be GUI-verified from WSL
  (AGENTS.md: no display). See the checkpoint below.

### Files changed

- `biochemeleon/mutation.py`: 6 `chain %s` → `chain '%s'` fixes + explanatory
  comment at the primary fix site (insert_cartoon_segment_hider step 1).
- `smoke/phase11_smoke.py`: new section N (blank-chain regression, 9 checks).
- `smoke/diag_phase11_dup_id.py`: headless diagnostic (untracked, staged to
  tmp/ for the Windows run).
- `smoke/test_blank_chain_selector.py` + `smoke/test_backup_selector.py` +
  `smoke/test_quoted_chain.py`: selector-form probes (untracked, staged to
  tmp/ for the Windows run).

## Why it's NOT Phase 9

Phase 9 SC1 only requires: "Selecting 1GZM or 3GP6 and clicking Start fetches from MemProtMD (cache miss) → progress dialog → finalize → game starts with membrane visible (no water)". The fetch + finalize + game-start flow COMPLETES (confirmed by the user: sphere hiders on 1gzm/3gp6 work — download, play, hint, reveal, restart, clean all working). The cartoon-segment hider is Phase 11 alt-conf code (`insert_cartoon_segment_hider`, git log `aaf4fea docs(11): record GUI human-verify PASS`), invoked only when the user requests a non-sphere rep on a structure that has native alt-confs. The Phase 9 must-haves (SC1-SC4) are satisfied.

## What's confirmed working (do NOT re-test during Phase 11 debug)

- **Phase 9 fetch UX:** modeless progress dialog, Cancel button, cache-hit, all 4 tier labels (SC1 partial / SC4 — user-approved)
- **MemProtMD fetch + finalize + load:** 1gzm + 3gp6 download successfully, the `.dry` extension bug is fixed (`format='pdb'` — commit d54f22e), membrane visible (no water) — sphere hiders play correctly
- **SASBDB fetch + finalize + load + glycan:** sasdpg4 downloads (SSL fallback — commit e0f8302), glycan HETATM (2601) visible, mixed-rep works (user confirmed "glycoprotein now working from download, and mixed representation working well") — SC2 ✓
- **DATA_SOURCES.md:** 09-04 human-verified, all citations/licenses approved — SC3 ✓
- **Sphere hiders on all demos:** 1znf, sasdpg4, 1gzm, 3gp6 — confirmed working

## What Phase 11 must address

1. ~~**The duplicate anchor id bug** — handle native alt-confs in the target structure.~~
   **DONE (2026-08-16):** The root cause was NOT alt-confs but an unquoted blank-chain
   PyMOL selector. Fix: single-quote the chain value (`chain '%s'`) in all 6
   `chain %s` selectors in mutation.py. Headless-verified on 3gp6 (blank chain)
   + 1ubq (named chain). GUI human-verify pending (see checkpoint below).
2. ~~**Test on alt-conf structures**~~ **Test on blank-chain structures:** 3gp6 dry
   tested headlessly (game.start succeeds, cleanup restores). 1gzm and sasdpg4
   require GUI verification (the cached files are not in all worktrees).
3. **GUI-runnable verification (the Phase 11 methodology lesson):** headless
   smoke (`-cq`) defaults `auto_zoom=-1`; GUI defaults `auto_zoom=1`. The fix
   addresses a SELECTOR bug (not a `cmd.create`/`cmd.zoom` issue), so auto-zoom
   is not a direct concern here, but the GUI human-verify is still needed to
   confirm the cartoon hider renders connected + clickable on 1gzm/3gp6/sasdpg4
   in the real Windows PyMOL GUI.

## Relevant files

- `biochemeleon/mutation.py` lines 617-635 (the fix: `chain '%s'` in segment_sele) +
  lines 390, 841, 848, 854, 857 (defensive fixes on the legacy path)
- `biochemeleon/game.py` line 84 (the start() loop that calls insert_hider_for_rep)
- `biochemeleon/__init__.py` lines 380, 481 (_continue_after_large_demo_fetch + drain)
- `smoke/phase11_smoke.py` section N (blank-chain regression, 9 checks)
- `smoke/diag_phase11_dup_id.py` (headless diagnostic that confirmed the root cause)
- `.planning/phases/11-alt-conf-cartoon-hider/` (Phase 11 is COMPLETE; this was a
  follow-up gap discovered during Phase 9 GUI human-verify)

## Out of scope for Phase 9 finalization

This bug does NOT block Phase 9 verification. Phase 9 SC1-SC4 are satisfied:
- SC1 ✓ (MemProtMD fetch + modeless dialog + membrane visible — sphere hiders work)
- SC2 ✓ (SASBDB fetch + glycan visible — user confirmed)
- SC3 ✓ (DATA_SOURCES.md — human-approved in 09-04)
- SC4 ✓ (4-tier sub-menu — user confirmed)

Phase 9 can be marked complete. This debug file is for Phase 11 follow-up.

## Resolution

**Root cause:** Unquoted blank-chain PyMOL selector (`chain ` with empty value)
in `insert_cartoon_segment_hider` segment_sele. The malformed selector ignores
the object scope and matches blank-chain atoms from ALL objects in the session
(backup + live), doubling the atom count in `cmd.create` → duplicate-id atoms
→ `cmd.identify` returns `[id, id]` → AssertionError.

**Fix:** Single-quote the chain value in all 6 `chain %s` selectors in
mutation.py: `chain '%s'`. The quoted form correctly scopes to the named
object for both blank (`''`) and named (`'A'`, `'H'`) chains.

**Verification:** phase11_smoke.py 86/86 PASSED (1ubq 77 + blank-chain 9).
3gp6 game.start succeeds headlessly. WSL gates green. GUI human-verify pending.
