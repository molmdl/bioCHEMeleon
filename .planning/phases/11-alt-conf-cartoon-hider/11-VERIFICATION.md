# Phase 11 Verification: Alt-conf Cartoon/Ribbon Hider (v1 Follow-up)

**Status: PASSED** (with 2 accepted caveats)

---

## IMPORTANT DEVIATION NOTE — read first

The Phase 11 plan frontmatter `must_haves` (in `11-08-PLAN.md` and the 8 plan files) describe the **ORIGINAL alt-conf design**: `alt='B'`, shared atom ids, multi-state `all_states` scaffolding, `insert_altconf_cartoon_hider`, an alt-gate in `on_pick`, `is_altconf=True` records.

**This design was REFACTORED mid-execution to a single-state new-chain copy approach** (commit `d65fb2c`). The original alt-conf design caused GUI-only visibility regressions (only cartoon rendered; multi-state `cmd.create` wiped original coords) that 4 fix cycles could not resolve (the 05-08 methodology failure). Two debug sessions (`.planning/debug/phase11-altconf-only-cartoon-hiders-visible.md` + `.planning/debug/phase11-cartoon-hider-single-state-refactor.md`) documented the root cause and the fix.

**The plan's `must_haves` are STALE.** Verification below is against the **6 outcome-based SUCCESS CRITERIA** from `ROADMAP.md` (Phase 11 section), which are design-agnostic — they describe the OUTCOME (connected render, ribbon, multi-hider, mixed-rep, cleanup, new-game), NOT the mechanism. The single-state refactor satisfies all 6 criteria.

The shipped design:
- `insert_altconf_cartoon_hider` → **`insert_cartoon_segment_hider`** (copy a real 3-residue backbone from the clean backup to a NEW chain 'H' + `alt=''` + `segi='GAME'` + `ss='L'` + NEW resi via `CARTOON_RESI_OFFSET=10000`, rigid-displace the middle, union-create merge into state 1).
- `game.py` dropped `all_states`/`is_first_altconf`; `on_pick` uses a **resv-range gate** (not an alt gate); `_mark_found` uses `endpoint_resvs`-based fragment coloring.
- `registry.py` + `persistence.py` UNTOUCHED (alt-conf fields stay dormant; `is_altconf=False` for new hiders).

---

## Success Criteria Verification

### Criterion 1 — Cartoon hiders render as CONNECTED parts of the cartoon trace (NOT disconnected)

- **What was checked:** A cartoon hider is a real 3-residue backbone copied to chain 'H' with the middle displaced ~1.5 Å; the endpoints coincide with the real trace so the cartoon tube blends at the ends and bulges in the middle. Replaces the Phase 5 terminal-extension approach (which rendered disconnected on 1ubq).
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`, 2026-08-16): the user confirmed the cartoon hider renders as a connected mid-chain bulge on 1ubq in a real Windows PyMOL GUI session. Debug session resolution: "single-state refactor WORKING — cartoon/ribbon hiders render in a single-state object alongside sphere/stick".
  - **Headless smoke** (`phase11_smoke.py` Section C, 77/77 PASSED — recorded in the debug session verification field): `count_atoms("segi GAME and rep cartoon") > 0` confirms GAME atoms have cartoon geometry (the connected-tube VISUAL is GUI-only; headless confirms the geometry exists).
  - **Render-question diagnostic** (`smoke/diag_render_question.py` T7, recorded): a real backbone copy retagged chain H + `alt=''` + union-create merge renders strongly (png 21829 vs blank 1333), single-state, originals survive.
- **Result: PASS**

### Criterion 2 — Ribbon hiders render without error (rep shown is ribbon, not hardcoded cartoon)

- **What was checked:** The hider's rep is forwarded from the dispatcher (`insert_hider_for_rep`), NOT hardcoded to cartoon. A ribbon hider must show in rep ribbon.
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`): the user confirmed ribbon hiders render in ribbon via the plugin Setup tab (checklist item 9).
  - **Headless smoke** (`phase11_smoke.py` Section D, 77/77 PASSED): fresh fetch + ribbon hider; `count_atoms("segi GAME and rep ribbon") > 0` AND `count_atoms("polymer and not segi GAME and rep ribbon") == 0` (ribbon ONLY on GAME — the phase5_smoke pattern proving `rep=` was forwarded, not a global show).
- **Result: PASS**

### Criterion 3 — Multiple cartoon hiders per chain work (mid-chain segments, not capped at 1/chain)

- **What was checked:** 2 disjoint mid-chain segments inserted in one game; both render as separate bulges; no coord corruption (the 05-08 Bug 4 retroactive coord-corruption failure mode).
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`): the user confirmed 2 hiders both visible (checklist item 4) via the GUI diagnostic.
  - **Headless smoke** (`phase11_smoke.py` Section E, 77/77 PASSED): 2 disjoint segments; registry len 2; single-state (`count_states == 1`); originals survive (non-GAME state-1 count preserved); 1st anchor displaced (NOT collapsed — Bug 4 fix verified). Section M (cross-rep disjoint): cartoon+ribbon in one game via the single-global-pick pattern — no KeyError, distinct anchor ids, disjoint segments.
- **Result: PASS**

### Criterion 4 — A game with mixed representations (sphere + line/stick + cartoon + ribbon) produces hiders in each selected rep, all tracked in the registry, all visible + clickable in the GUI

- **What was checked:** Mixed-rep game via the plugin Setup tab (per_rep: sphere + stick + cartoon + ribbon); all 4 reps produce hiders; all tracked in the registry; all visible + clickable.
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`): the user confirmed mixed reps via the plugin Setup tab (checklist item 9) — hiders in each rep, all visible + clickable.
  - **Headless smoke** (`phase11_smoke.py` Section I, 77/77 PASSED): sphere + stick + cartoon + ribbon all in registry (len 4) + all 4 reps visible on GAME atoms + single-state + originals/sphere/stick survive in state 1.
- **Result: PASS**

### Criterion 5 — Cleanup restores the original structure for hiders (verify_intact True + count back to orig)

- **What was checked:** After a game, `cleanup()` (backup.restore delete+create two-step) returns the object to its pre-game state — atom count matches the pre-Start count, no GAME atoms remain.
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`): the user confirmed cleanup restores the original scene (checklist item 7) — no residual bulge, count back to orig.
  - **Headless smoke** (`phase11_smoke.py` Section G, 77/77 PASSED): `backup.restore` returns True; `count_atoms` back to orig; `count_atoms("segi GAME") == 0`.
- **Result: PASS**

### Criterion 6 — New Game flow (cleanup → re-start) works without residual state corruption

- **What was checked:** After cleanup, a fresh `start()` produces a new hider with NO corruption from the prior round (the 05-08 Bug 4 + Pitfall 8 failure mode: residual alt-conf state breaking re-insertion).
- **Evidence:**
  - **User-verified in GUI** (commit `3b7d7b1`): the user confirmed new game works (checklist item 8) — a fresh hider appears with no corruption from the prior round.
  - **Headless smoke** (`phase11_smoke.py` Section H, 77/77 PASSED): cleanup → re-start produces a new hider; cleanup restores count (no residual state corruption).
- **Result: PASS**

---

## WSL Gate Results (run 2026-08-16, actual output recorded)

### Gate 1 — py_compile (syntax check, every module)

```
$ python3.6 -m py_compile biochemeleon/*.py
$ echo $?
0
```

**Result: PASS** (exit 0; all `biochemeleon/*.py` compile cleanly).

### Gate 2 — Unit tests (pure-layer + controller + persistence)

```
$ python3.6 -m unittest tests.test_setup_state tests.test_registry \
    tests.test_generators tests.test_game_controller tests.test_persistence
Ran 313 tests in 0.059s
OK
```

**Result: PASS** (313/313 OK; 0 failures, 0 errors). Includes `test_game_controller.TestOnPickFragment` (the resv-gate truth table that replaced the old `TestOnPickAltconf`).

### Gate 3 — Pitfall-1 gate (NO Tkinter/Pmw/PyQt5/Toplevel/mainloop)

```
$ grep -rnE "import Tkinter|import tkinter|from tkinter|import Pmw|from Pmw|\
app\.root|grab_set|mainloop|Toplevel|menuBar\.addmenuitem|from PyQt5 import|import PyQt5" \
biochemeleon/
(no output; grep exit 1)
```

**Result: PASS** (0 matches across the package — no legacy GUI toolkit leakage).

### Gate 4 — exec_ gate (QFileDialog/QMessageBox only, NEVER the main dialog)

```
$ grep -rnE "\.exec_\(\)" biochemeleon/
biochemeleon/gui_game.py:303:        msg.exec_()
```

Context (gui_game.py:298-303): `msg = QtWidgets.QMessageBox(self.window())` — this is the win-message **QMessageBox** (the `_finish_win` modal). The main PluginDialog stays modeless (`dialog.show()`). This is the single allowed hit (AGENTS.md: "QFileDialog.exec_() / QMessageBox.exec_() on child dialogs ARE allowed").

**Result: PASS** (1 match, on a QMessageBox — allowed).

### Gate 5 — Single-state refactor confirmation (no leftover alt-conf CODE)

```
$ grep -n "insert_altconf_cartoon_hider" biochemeleon/mutation.py
(no output; grep exit 1)              # 0 matches — renamed away

$ grep -n "insert_cartoon_segment_hider" biochemeleon/mutation.py
503:    ...shared by ``insert_cartoon_segment_hider`` (reassigns...   # docstring
518:def insert_cartoon_segment_hider(object, chain, start_resi, ...)  # the fn
701:  ...``insert_cartoon_segment_hider`` (Phase 11 single-state...     # docstring
745:            return insert_cartoon_segment_hider(                    # dispatcher

$ grep -n "CARTOON_RESI_OFFSET" biochemeleon/mutation.py
496:CARTOON_RESI_OFFSET = 10000                                        # constant
513:    ...shifted by CARTOON_RESI_OFFSET.                              # docstring
515:    return (start_resi + CARTOON_RESI_OFFSET, end_resi + CARTOON_RESI_OFFSET)
620:    #    + loop ss + NEW resi (resv shifted by CARTOON_RESI_OFFSET...)
627:                  segi, CARTOON_RESI_OFFSET),                       # alter call
```

**Result: PASS** (0 `insert_altconf_cartoon_hider` — renamed; 4 `insert_cartoon_segment_hider` — present; 5 `CARTOON_RESI_OFFSET` — present).

### Gate 6 — No live alt-conf machinery (all_states / is_altconf dormant)

- `all_states`: only in **explanatory comments** in `game.py:68` ("NO alt-conf, NO multi-state, NO all_states") + `mutation.py:558-559,646-648` ("Single-state (NO multi-state / all_states)"). NO live `cmd.set("all_states", ...)` code.
- `is_altconf` / `alt_tag` / `get_altconf_by_resv`: **dormant fields** in `registry.py` (HiderRecord defaults `is_altconf=False`, `alt_tag=''`) + `game.py` guards (`getattr(rec, 'is_altconf', False)`). These are intentionally kept for backward-compat with old `.bcmz` sidecars (per the debug session: "registry.py + persistence.py UNTOUCHED; is_altconf=False for new hiders -> dormant"). New games produce no `is_altconf=True` records.

**Result: PASS** (no live alt-conf code in the active path; dormant fields are intentional backward-compat).

### Gate 7 — Headless integration smoke (recorded, not re-run in this finalization)

`smoke/phase11_smoke.py` (post-refactor single-state + NEW-resi rewrite, 13 sections A-M): **77/77 PASSED**, exit 0. Recorded in the debug session verification field (2026-08-15). Covers: segment construction (single-state, chain H, alt='', anchor middle CA), connected rendering geometry, ribbon rep forwarding, multi-hider no-corruption, id-keyed scoring truth table, cleanup (backup.restore), new-game, mixed-rep, `.bcm` round-trip (endpoint_resvs survives, is_altconf=False), `.pse` survival (chain-H GAME fragment + alt=''), cross-rep disjoint (KeyError regression).

**Note:** This gate was NOT re-run during this finalization (it requires staging to the Windows-facing path + `cmd.exe /c run-conda-pymol.bat -cq`, a heavier operation). The 77/77 result is the recorded verification from the refactor session, cited as evidence for criteria 1-6 above. All 5 WSL-runnable gates (1-6 above) were run fresh and pass.

---

## Caveats (user-accepted, 2026-08-16)

### Caveat 1 — SS (secondary-structure) copy NOT done

The hider fragment does NOT inherit the parent's secondary structure — it renders as a loop (`ss='L'`). Accepted for now as future visual polish (consistent with the reverted commit `2715df5`). The fragment is visible + clickable; the cosmetic ss-mismatch is a future enhancement, NOT a Phase 11 blocker. Recorded in the debug session resolution.

### Caveat 2 — Bundled demo `KeyError: 'file'` (pre-existing, out of scope)

A `KeyError: 'file'` surfaced during the GUI test when running a bundled demo. It was CONFIRMED PRE-EXISTING on `main` (introduced by an earlier phase, NOT Phase 11). Out of scope for Phase 11. A separate debug file (`.planning/debug/bundled-demo-keyerror-file.md`, status: investigating) exists for a future fix. Phase 11 checkpoint considered PASSED with this caveat.

---

## Conclusion

**Phase 11 goal ACHIEVED.** The HIDER-03/HIDER-05 alt-conf gap from Phase 5 (terminal-extension cartoon rendered disconnected on 1ubq) is CLOSED by the single-state new-chain copy approach.

All 6 success criteria verified:
- **User GUI verification** (commit `3b7d7b1`, 2026-08-16): all 6 criteria PASS in a real Windows PyMOL GUI session on 1ubq.
- **Headless smoke** (`phase11_smoke.py`, 77/77 PASSED): the cmd-tier mechanism (construction, scoring, cleanup, multi-hider, mixed-rep, `.bcm`/`.pse` round-trip) verified.
- **WSL gates** (run fresh 2026-08-16): py_compile (0), unit tests (313/313), Pitfall-1 (0 matches), exec_ (QMessageBox only), single-state refactor confirmed (0 `insert_altconf_cartoon_hider`, `insert_cartoon_segment_hider` + `CARTOON_RESI_OFFSET` present), no live alt-conf machinery (dormant fields only).

The 05-08 methodology failure (headless smoke passing while GUI fails) is closed: the single-state refactor eliminates multi-state + alt-conf, making the GUI-only failure modes (multi-state display, retroactive coord corruption) IMPOSSIBLE by construction. The remaining GUI-only checks (connected-bulge visual, auto-zoom, found-color on the bump) were user-verified via `smoke/phase11_gui_diag.py`.

2 accepted caveats (SS copy deferred; bundled demo KeyError pre-existing) do not block the Phase 11 goal.

---
*Verification date: 2026-08-16*
*Phase: 11-alt-conf-cartoon-hider*
*Status: PASSED*
