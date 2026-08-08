---
phase: 05-line-stick-and-cartoon-generators
plan: 05
type: execute
status: partial-approval
checkpoint: human-verify
approved: partial
date: 2026-08-08

must_haves_verified:
  - "Headless smoke 25/25 ALL PASSED (05-04) then 29/29 after fixes"
  - "Cartoon hider inserts + clickable + cleanup restores (terminal extension approach)"
  - "Mixed-rep on 1znf (cartoon+line+stick+sphere) works well — user confirmed"
  - "Sphere + line/stick hiders insert + clickable (1znf mixed-rep test)"

must_haves_unverified:
  - "Cartoon hider visual blend on 1ubq — terminal extension renders disconnected (ss=L helps but fundamental limitation)"
  - "Line/stick hider on 1ubq — IndexError on neighbor_id (GUI-only bug, not caught by smoke)"
  - "Ribbon representation — errors when chosen (unsupported)"
  - "Alt-conf segment replication — NOT implemented (only terminal extension)"

commits:
  - "9c49a22 fix(05-05): use resv not int(resi) in iterate expression (NameError on builtins)"
  - "ff666f4 fix(05-05): cartoon hider attach on multi-state/capped structures (Issue 2+3)"
  - "05a24b6 fix(05-05): fetch mode reuses loaded object + collapse before data collection (Issue 1+2)"
  - "90ab355 docs(05-05): resolve debug session for 3 GUI issues (fetch/cartoon/visible)"
  - "ef3dbb0 fix(05-05): cartoon hider visible via sphere fallback (single-residue cartoon does not render)"
  - "2ba9aac fix(05-05): 2-residue cartoon tube (visible blend, no sphere)"
  - "56c8315 fix(05-05): warn user when fewer cartoon hiders generated than requested"
  - "bbcf8df fix(05-05): cartoon hider ss=L loop for connected tube (not sheet arrow)"

gap_closure_needed:
  - "Alt-conf cartoon hider (replicate a segment as alternate position) — replaces terminal extension"
  - "Line/stick IndexError on neighbor_id (GUI-only, smoke doesn't catch)"
  - "Ribbon representation support (currently errors)"
---

# 05-05 SUMMARY: Human-Verify Checkpoint (Partial Approval)

## Status: PARTIAL APPROVAL

The user partially approved Phase 5 after extensive GUI testing. The core mechanism works (hiders insert, are clickable, cleanup restores). However, the cartoon hider's **terminal-extension** approach has a fundamental visual limitation (disconnected on 1ubq), and the roadmap's **alt-conf segment replication** approach was never implemented. Two additional GUI-only bugs were discovered. The user decided to pause and create gap-filling plans later.

## What Was Tested

### Test A — Cartoon blend (1ubq): PARTIAL
- Cartoon hider DOES insert at N-terminus (2 glycine residues, ss='L' loop tube)
- IS clickable (user clicked GLY`0/CA and GLY`-1/CA)
- Renders as a **disconnected** segment on 1ubq (fundamental terminal-extension limitation)
- After multiple debug iterations (sphere fallback → 2-residue tube → ss='L' loop), still disconnected on 1ubq
- **User decision:** stop debugging terminal extension; implement alt-conf replication in a gap-filling plan

### Test B — Line/stick blend (1ubq): FAILED (GUI-only bug)
- `IndexError: list index out of range` at `insert_line_stick_hider` line 220 (`nbr[0]`)
- The `cmd.iterate_state` for neighbor coords returned an empty list
- The smoke uses a different neighbor-selection path (CA atoms), so this bug was NOT caught by 05-04 smoke
- **Needs gap closure**

### Test C — Mixed-rep (1znf): PASS
- 1znf with sphere + line/stick + cartoon (mixed-rep): user confirmed "works well"
- All hider types inserted, clickable, cleanup restored
- The cartoon hider looked connected in the 1znf mixed-rep case (possibly because the whole residue was shown alongside other reps, making it appear connected)
- This is the strongest positive result — the mixed-rep dispatch works end-to-end

### Test D — 1znf cartoon: PARTIAL
- 1znf ACE cap removal + N-terminus attach works (no "no target attachment vector" error)
- 37-state NMR collapse works
- Cartoon hider inserts + clickable
- Same disconnected-look issue as 1ubq (terminal extension limitation)

### Test E — spectrum b: SKIPPED
- User confirmed `select segi GAME; zoom sele` is the better "cheat" method
- spectrum b test can be skipped in future verification

## Bugs Found During Checkpoint (8 fix commits)

### Fixed during checkpoint:
1. **`int(resi)` NameError** (9c49a22) — hygienic `space=` doesn't expose builtins; use `resv`
2. **Multi-state + ACE cap blocking attach** (ff666f4, 05a24b6) — `collapse_to_single_state` + `free_nterminal_valence` + `hydro=1`
3. **Fetch mode re-fetch failure** (05a24b6) — `_on_start` reuses loaded object instead of re-fetching
4. **Single-residue cartoon invisible** (ef3dbb0 → 2ba9aac) — sphere fallback → 2-residue tube (PyMOL can't render 1-residue cartoon)
5. **5-hider cap silent** (56c8315) — added QMessageBox.warning when fewer cartoon hiders generated than requested
6. **Sheet arrow disconnected look** (bbcf8df) — changed ss from neighbor-copy to 'L' (loop tube)

### NOT fixed (gap closure needed):
7. **Line/stick IndexError on neighbor_id** — `insert_line_stick_hider` line 220 `nbr[0]` fails when `cmd.iterate_state` returns empty. GUI-only (smoke uses CA selection, _on_start uses `not segi GAME` selection). Root cause likely: the neighbor_id passed from `_on_start` doesn't match what `iterate_state` expects, OR the object state changed between id capture and iterate_state.
8. **Ribbon representation errors** — ribbon uses the same `insert_cartoon_hider` path but errors when chosen. Needs investigation.
9. **Cartoon terminal extension disconnected** — fundamental limitation; alt-conf replication is the roadmap's alternative approach ("replicating a segment as alternate position using C-alpha geometry"). NOT a bug to fix — a different approach to implement.

## Why the Smoke Passed but GUI Failed

The 05-04 headless smoke (25/25 → 29/29 ALL PASSED) bypasses `_on_start` (Qt-coupled) and builds `hider_specs` directly. The GUI path goes through `_on_start` which:
- Uses a different neighbor-id selection (`not segi GAME` vs `name CA`) → empty list → IndexError
- Re-fetches the object (double-fetch mmCIF error) → fixed
- Doesn't collapse multi-state or free N-terminal valence → fixed
- The cartoon visual blend is a rendering issue the smoke can't check (no human eye)

## Key Design Decisions

1. **Terminal extension is the MVP cartoon approach** — works mechanically but visually disconnected. Alt-conf is the better approach but needs research.
2. **2-residue tube for cartoon** — PyMOL can't render 1-residue cartoon; 2 residues give the tube a segment to draw between.
3. **ss='L' (loop) for cartoon hider** — a smooth tube connects better than a sheet arrow; also matches the `ss=4` (flat/loop) geometry.
4. **segi=GAME on all atoms, b=-999 on clickable CA only** — cleanup removes all GAME atoms; `fetch_all_hider_ids` returns only the clickable CA (1 registry entry per cartoon hider).
5. **One cartoon hider per chain** (Open Risk 5) — attaching many to one terminus chains them; capped at `max_chains=count` but limited by available chains.

## Gap Closure Plans Needed

The user will create these via `/gsd-plan-phase 5 --gaps`:

### Gap 1: Alt-conf cartoon hider
- Implement "replicating a segment as alternate position using C-alpha geometry" (roadmap success criterion 2)
- Replaces the terminal-extension approach for better visual blend
- May allow multiple cartoon hiders per chain (not capped at 1/chain)
- Needs research: PyMOL alt-conf API (`cmd.alter` altloc, `cmd.create` with altloc, cartoon rendering of alt-conf)

### Gap 2: Line/stick + ribbon fixes
- Fix `insert_line_stick_hider` IndexError (neighbor_id empty in GUI path)
- Fix ribbon representation error
- May need to align the neighbor-id selection between `_on_start` and the smoke

## What Works Now (Ready for Phase 6+)

- **Sphere hiders**: fully working (Phase 4, unchanged)
- **Line/stick hiders**: work headlessly (smoke 29/29); GUI has IndexError (gap closure)
- **Cartoon hiders (terminal extension)**: work mechanically (insert + click + cleanup); visually disconnected on 1ubq (alt-conf gap closure)
- **Mixed-rep dispatch**: works (1znf mixed-rep test confirmed all reps)
- **Cleanup**: verify_intact passes for all hider types (sphere, line/stick, cartoon)
- **Sentinel**: segi=GAME + b=-999 on all hider types; cleanup by segi GAME; read by b < 0
- **Backup/restore**: snapshot-before-mutation + restore-on-failure (Phase 3, unchanged)

## Output
Phase 5 is PARTIALLY COMPLETE. The user will create gap-filling plans via `/gsd-plan-phase 5 --gaps` to address:
1. Alt-conf cartoon hider (replaces terminal extension)
2. Line/stick IndexError + ribbon support
