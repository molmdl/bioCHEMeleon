# Phase 11 Bug: Membrane-protein cartoon-segment hider — duplicate anchor id

**Status:** pending — discovered during Phase 9 GUI human-verify (2026-08-16)
**Scope:** Phase 11 (alt-conf cartoon/ribbon hider), NOT Phase 9
**Severity:** blocks mixed-rep on membrane proteins (1gzm, 3gp6) — sphere hiders work fine
**Triggered by:** selecting 1gzm or 3gp6 (MemProtMD demos) + any non-sphere hider (cartoon or mixed-rep with cartoon/ribbon)

## Reproduction

1. Start the plugin in Windows PyMOL GUI (`setenv.bat` → `pymol`)
2. Select "Membrane protein — 1gzm (Very challenging)" → set hider count + a non-sphere rep (cartoon, or mixed sphere+cartoon+stick) → Start
3. After fetch+finalize completes, the drain calls `_continue_after_large_demo_fetch` → `GameController.start(hider_specs)` → for the cartoon/ribbon hider, `insert_hider_for_rep` dispatches to `insert_cartoon_segment_hider` → **AssertionError**

## Error message (exact)

Three variants observed, all in the same code path:

```
AssertionError: expected 1 anchor id, got [25, 25]          # 1gzm first attempt
AssertionError: expected 1 anchor id, got [25, 25, 19]     # sasdpg4 mixed-rep (also triggered — SASBDB glycoprotein has alt-confs too)
AssertionError: expected 1 anchor id, got [24, 24]          # 1gzm restart (after delete all)
```

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

## Root cause hypothesis

**1gzm (bacteriorhodopsin, PDB 1GZM) and 3gp6 (PagP, PDB 3GP6) have native alternate conformations (alt-conf / altLoc) in their atomic records.** The Phase 11 `insert_cartoon_segment_hider` uses `cmd.identify` on a segment selection that returns multiple atom ids when the segment contains alt-conf atoms — e.g. `[25, 25]` means atom id 25 matched TWICE (once per altLoc variant `A` and `B`), and `[25, 25, 19]` means 2 alt-conf atoms at id 25 plus 1 at id 19. The assert `len(ids) == 1` fails because the selection semantics didn't account for alt-conf duplication.

**Evidence supporting the alt-conf hypothesis:**
- 1gzm (bacteriorhodopsin) is a high-resolution X-ray structure known to have alt-confs in flexible side chains.
- 3gp6 (PagP beta-barrel) similarly.
- sasdpg4 (SASBDB glycoprotein) ALSO triggered `[25, 25, 19]` — the modeled glycoprotein has alt-conf glycans (the fit2_model1 file includes altLoc for some sugar residues).
- The duplicate id `[25, 25]` (same id twice) is the signature of `cmd.identify` returning one entry per altLoc of the same physical atom — PyMOL's identify with `mode=0` returns the integral atom id, but a selection spanning alt-confs can match the same id multiple times if the selection expression doesn't restrict to a single altLoc.

**The bug is in the SELECTION, not the assert.** `insert_cartoon_segment_hider` builds a selection that matches alt-conf atoms multiple times. The fix is to either:
- (a) Restrict the segment selection to a single altLoc: `... and alt A` (or pick the first altLoc programmatically).
- (b) De-duplicate the id list: `ids = list(dict.fromkeys(ids))` (preserves order, drops dup) — but if the duplicate means the segment selection ITSELF is wrong (matching 2 segments not 1), de-dup hides the real bug.
- (c) Investigate whether the segment-selection expression (whatever it is at mutation.py:670-676) is correctly scoping to ONE residue's C-alpha — if it's matching the C-alpha of the N+1 residue AND a side-chain alt-conf atom, that's a selection bug, not a de-dup case.

**Investigation should start at mutation.py:670-680** to read the exact selection expression + the `cmd.identify` call. Then cross-reference with PyMOL's alt-conf selection semantics (`alt A` / `alt +A` selectors in `querying.py`).

## Why it's NOT Phase 9

Phase 9 SC1 only requires: "Selecting 1GZM or 3GP6 and clicking Start fetches from MemProtMD (cache miss) → progress dialog → finalize → game starts with membrane visible (no water)". The fetch + finalize + game-start flow COMPLETES (confirmed by the user: sphere hiders on 1gzm/3gp6 work — download, play, hint, reveal, restart, clean all working). The cartoon-segment hider is Phase 11 alt-conf code (`insert_cartoon_segment_hider`, git log `aaf4fea docs(11): record GUI human-verify PASS`), invoked only when the user requests a non-sphere rep on a structure that has native alt-confs. The Phase 9 must-haves (SC1-SC4) are satisfied.

## What's confirmed working (do NOT re-test during Phase 11 debug)

- **Phase 9 fetch UX:** modeless progress dialog, Cancel button, cache-hit, all 4 tier labels (SC1 partial / SC4 — user-approved)
- **MemProtMD fetch + finalize + load:** 1gzm + 3gp6 download successfully, the `.dry` extension bug is fixed (`format='pdb'` — commit d54f22e), membrane visible (no water) — sphere hiders play correctly
- **SASBDB fetch + finalize + load + glycan:** sasdpg4 downloads (SSL fallback — commit e0f8302), glycan HETATM (2601) visible, mixed-rep works (user confirmed "glycoprotein now working from download, and mixed representation working well") — SC2 ✓
- **DATA_SOURCES.md:** 09-04 human-verified, all citations/licenses approved — SC3 ✓
- **Sphere hiders on all demos:** 1znf, sasdpg4, 1gzm, 3gp6 — confirmed working

## What Phase 11 must address

1. **The duplicate anchor id bug** — `insert_cartoon_segment_hider` must handle native alt-confs in the target structure. Read mutation.py:670-676 (the selection + identify call), determine whether it's a selection-scoping bug (fix the selector) or a de-dup case (legitimate same-atom-matched-twice), and fix accordingly.
2. **Test on alt-conf structures:** 1gzm (bacteriorhodopsin), 3gp6 (PagP), sasdpg4 (glycoprotein with alt-conf glycans). All three triggered the assert.
3. **GUI-runnable verification (the Phase 11 methodology lesson):** headless smoke (`-cq`) defaults `auto_zoom=-1`; GUI defaults `auto_zoom=1`. Any `cmd.create`/`cmd.zoom`/segment-selection verification MUST run in BOTH modes OR in the GUI directly. Headless smoke passing does NOT prove GUI correctness for alt-conf-heavy code paths (this is the documented Phase 11 research requirement — see ROADMAP.md Phase 11 details).

## Relevant files (read in this order during Phase 11 debug)

- `biochemeleon/mutation.py` lines ~660-760 (insert_cartoon_segment_hider + insert_hider_for_rep dispatcher)
- `biochemeleon/game.py` line 84 (the start() loop that calls insert_hider_for_rep)
- `biochemeleon/__init__.py` lines 380, 481 (_continue_after_large_demo_fetch + drain — the async path that surfaces the error)
- `tmp/pymol-src/modules/pymol/querying.py` (cmd.identify + alt-conf selector semantics — for understanding why the selection returns duplicates)
- `tmp/pymol-src/modules/pymol/selecting.py` (if the segment selection uses cmd.select internally)
- `.planning/phases/11-*` (when it exists — Phase 11 is not yet planned; the ROADMAP flags it as research-required)

## Out of scope for Phase 9 finalization

This bug does NOT block Phase 9 verification. Phase 9 SC1-SC4 are satisfied:
- SC1 ✓ (MemProtMD fetch + modeless dialog + membrane visible — sphere hiders work)
- SC2 ✓ (SASBDB fetch + glycan visible — user confirmed)
- SC3 ✓ (DATA_SOURCES.md — human-approved in 09-04)
- SC4 ✓ (4-tier sub-menu — user confirmed)

Phase 9 can be marked complete. This debug file is for Phase 11 follow-up.
