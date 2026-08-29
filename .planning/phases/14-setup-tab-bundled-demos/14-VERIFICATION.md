---
phase: 14-setup-tab-bundled-demos
verified: 2026-08-29T16:24:22Z
status: passed
score: 14/14 must-haves verified
re_verification: false
---

# Phase 14: Setup Tab & Bundled Demos — Verification Report

**Phase Goal:** The user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience, before touching the risky PDB-rebuild.
**Verified:** 2026-08-29T16:24:22Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

The 14 must-have truths were distilled from the 4 PLAN frontmatters (one per plan) and verified against the actual codebase + re-run tests/smokes (NOT trusted from SUMMARY claims).

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | validate_state deterministically clamps hider_count to [1, cap] and drops invalid per_rep entries via insertion-order drop-overflow (never truncates) | ✓ VERIFIED | `vmd/lib/setup_state.tcl:126-197` (set result $DEFAULTS; drop-overflow clamp lines 180-189); tcltest `validate_state_clamps_per_rep_sum_drop_overflow` expects `{VDW 5}` for `{VDW 5 Cartoon 5 Lines 5}` hc=8 — PASSED |
| 2 | randomize_per_rep distributes hider_count across a random non-empty subset of reps — the quick-008 guarantee (>=1 rep with count > 0 when hider_count > 0) | ✓ VERIFIED | `vmd/lib/setup_state.tcl:204-225` (`_randint 1 [llength $game_reps]` = subset size; non-empty guarantee lines 221-223); tcltest `randomize_per_rep_non_empty_when_count_positive` (seed 0..19, hc=1) + `randomize_per_rep_all_counts_positive_and_sum_le_total` (seed 0..29, hc=15) — PASSED |
| 3 | randomize_state returns a complete 11-key dict with all DEFAULTS keys, deterministic given a seed | ✓ VERIFIED | `vmd/lib/setup_state.tcl:234-292` (dict create with 11 keys lines 281-292; calls randomize_per_rep with NO seed line 278); tcltest `randomize_state_seed_determinism` + `randomize_state_has_all_defaults_keys` — PASSED |
| 4 | All tcltest cases pass under headless VMD (BCHM_TEST_RESULT Failed=0) | ✓ VERIFIED | RE-RUN: `BCHM_TEST_RESULT Total=41 Passed=41 Failed=0 Skipped=0` (covers DEFAULTS, hider-count cap, GAME_REPS, DEMO_MANIFEST, validate_state full, randomize_per_rep, randomize_state) |
| 5 | load_demo loads all 6 bundled demos via mol new with correct atom counts (1znf=424, 1xdn=2597, 5e54=2844, 1k8p=555, 2qbz=3408, 4wb3=3779) | ✓ VERIFIED | `vmd/lib/demos.tcl:58-82` (`mol new $path type pdb` line 78); RE-RUN mol smoke: `BCHM_SMOKE_RESULT PASS=1 FAIL=none` with all 6 "Finished with coordinate file" lines; all 6 PDBs present in `vmd/data/demos/` |
| 6 | get_active_reps detects reps matching GAME_REPS using the combined-braces molinfo form | ✓ VERIFIED | `vmd/lib/demos.tcl:89-100` (`molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` line 94); mol smoke check 4 verified fresh=`Lines`, after addrep=`Lines VDW`, after delrep 0=`VDW` (survives renumbering) |
| 7 | list_loaded_molecules returns "<name> (<molid>)" display strings | ✓ VERIFIED | `vmd/lib/demos.tcl:46-52` (`lappend out "[molinfo $m get name] ($m)"` line 49); mol smoke check 3 verified 6 display strings after loading 6 demos |
| 8 | save_setup/load_setup round-trips a setup dict with eq = 1 (DEFAULTS-key-order rebuild on load) | ✓ VERIFIED | `vmd/lib/demos.tcl:116-181` (save_setup key-value lines; load_setup rebuild in DEFAULTS key order lines 175-178 + validate_state line 180); mol smoke check 7: `[expr {$loaded eq $original}]` = 1 (no DEBUG lines = genuine pass, not the 14-02 false-PASS) |
| 9 | fetch_pdb stub returns -code error (Phase 14 deferral) | ✓ VERIFIED | `vmd/lib/demos.tcl:106-108` (`return -code error "fetch_pdb not implemented in Phase 14..."`); mol smoke check 6 verified catch returns error containing "not implemented" |
| 10 | Sourcing biochemeleon.tcl headlessly loads dialog.tcl + setup_tab.tcl + demos.tcl without error; open_dialog creates toplevel+notebook+setup_tab::build | ✓ VERIFIED | `vmd/biochemeleon.tcl:79-80` (sources demos + dialog); `vmd/gui/dialog.tcl:26` (sources setup_tab), `:40-64` (open_dialog: toplevel + ttk::notebook + setup_tab::build $nb.setup); RE-RUN GUI smoke: `BCHM_SMOKE_RESULT PASS=1 FAIL=none` (entry + open_dialog proc + 4 namespaces + 4 key procs + validate_state spot-check) |
| 11 | setup_tab::build lays out all 4 groups (Target 3-mode + stacked pages, Hiders spinbox+lock+10 per-rep rows, Difficulty, Actions 4 buttons) | ✓ VERIFIED | `vmd/gui/setup_tab.tcl:66-97` (build calls 4 builders lines 70-76 + packs); build_target_group (106-165, 3 radiobuttons + stacked pages + Loaded/Fetch/Demo menubuttons); build_hiders_group (174-209, spinbox + lock + 10 per-rep rows over GAME_REPS); build_diff_group (215-224); build_actions (230-238, 4 buttons) |
| 12 | Selecting a loaded molecule / bundled demo updates the hider-count cap; selecting a demo loads it via mol new; toggling per-rep enables/disables its spinbox | ✓ VERIFIED | select_loaded_mol (416-425) + select_demo (399-412) call update_cap; select_demo calls `::biochemeleon::demos::load_demo` (line 406); update_cap (489-526) reconfigures spinbox -to via hider_count_cap(atom_count) (line 503); on_rep_toggled (438-477) enables/disables spinbox (lines 450/473) |
| 13 | Reset/Randomize/Save/Load each work as labeled; Save/Load round-trips to a .bcm file | ✓ VERIFIED | do_reset (581-583, apply_state DEFAULTS); do_randomize (589-599, apply_state [randomize_state ...]); do_save (613-669, tk_getSaveFile .bcm + demos::save_setup + validate_state-on-save warning); do_load (674-685, tk_getOpenFile .bcm + demos::load_setup + apply_state); round-trip verified by mol smoke eq=1 + GUI checkpoint |
| 14 | Closing the dialog preserves in-progress edits (WM_DELETE_WINDOW) + cleans up the trace; dialog stays modeless | ✓ VERIFIED | `vmd/gui/dialog.tcl:63` (wm protocol WM_DELETE_WINDOW ::biochemeleon::on_close); on_close (77-89: collect_state -> dict set state setup + `trace vdelete vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu` line 87 + destroy); modeless gate: `grep -rnE 'grab set' vmd/gui/` = ZERO |

**Score:** 14/14 truths verified

### Required Artifacts

All artifacts verified at three levels (existence, substantive, wired). Line counts and stub-pattern scans confirm real implementations, not placeholders.

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `vmd/lib/setup_state.tcl` | validate_state full + randomize_state + randomize_per_rep + 6 helpers | ✓ VERIFIED | 293 lines; no stubs; pure-layer gate clean (0 mol/atomselect/tk/toplevel/ttk); 8.6 gate clean; sourced by test + demos |
| `vmd/tests/test_setup_state.test` | ~41 tcltest cases (Phase 13 baseline + Phase 14 additions) | ✓ VERIFIED | 287 lines; 41 tests (12 Phase 13 + 29 Phase 14); sources setup_state.tcl line 13; RE-RUN Failed=0 |
| `vmd/lib/demos.tcl` | 8-proc mol bridge | ✓ VERIFIED | 189 lines; 8 procs (to_vmd_path, list_loaded_molecules, load_demo, get_active_reps, fetch_pdb, save_setup, load_setup, atom_count); sources setup_state.tcl line 12; tk-gate clean; 8.6 gate clean |
| `vmd/smoke/phase14_mol_smoke.tcl` | 7-check headless smoke | ✓ VERIFIED | 147 lines; BCHM_SMOKE_RESULT marker; RE-RUN PASS=1 |
| `vmd/gui/dialog.tcl` | open_dialog extracted + on_close WM_DELETE handler | ✓ VERIFIED | 89 lines; open_dialog (40-64) + on_close (77-89); sources setup_tab.tcl line 26; modeless |
| `vmd/gui/setup_tab.tcl` | 4 group builders + collect_state/apply_state + 10 callbacks (full) | ✓ VERIFIED | 686 lines; 19 procs (8 structural + _dget + 10 callbacks); all 10 callbacks have substantive bodies (smallest do_reset=4 lines [correct minimal impl], largest do_save=58 lines); no stub `return`-only bodies; one-per-line `variable` fix present (lines 251-260, 296-305); live-cap present (on_rep_toggled 449-477, recompute_per_rep_maxes 537-578, update_cap 489-526) |
| `vmd/biochemeleon.tcl` | thin bootstrap sourcing demos + gui/dialog | ✓ VERIFIED | 141 lines; sources setup_state + registry + demos + gui/dialog (lines 71-80); re-source guard (29-32); inline open_dialog removed (extraction note 84-92); public procs + menu registration intact |
| `vmd/smoke/phase14_gui_smoke.tcl` | 11-check headless smoke (loading layer) | ✓ VERIFIED | 87 lines; BCHM_SMOKE_RESULT marker; RE-RUN PASS=1 |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| test_setup_state.test | setup_state.tcl | `source [file join [pwd] vmd lib setup_state.tcl]` | ✓ WIRED | line 13; 41 tests pass |
| randomize_state | randomize_per_rep | `randomize_per_rep $hider_count $GAME_REPS` (NO seed — continues sequence) | ✓ WIRED | setup_state.tcl:278 |
| validate_state | DEFAULTS | `set result $DEFAULTS` (canonical key order) | ✓ WIRED | setup_state.tcl:131 |
| demos.tcl | setup_state.tcl | `source [file join [file dirname [info script]] setup_state.tcl]` | ✓ WIRED | demos.tcl:12 |
| load_demo | mol new | `catch {mol new $path type pdb}` | ✓ WIRED | demos.tcl:78 |
| load_setup | validate_state | `return [::biochemeleon::setup_state::validate_state $loaded]` | ✓ WIRED | demos.tcl:180 |
| biochemeleon.tcl | gui/dialog.tcl | `source [file join $_dir gui dialog.tcl]` | ✓ WIRED | biochemeleon.tcl:80 |
| dialog.tcl | setup_tab.tcl | `source [file join [file dirname [info script]] setup_tab.tcl]` + `setup_tab::build $nb.setup` | ✓ WIRED | dialog.tcl:26, 53 |
| setup_tab.tcl | demos::* | 6 call sites (load_demo, atom_count×3, save_setup, load_setup) | ✓ WIRED | setup_tab.tcl:406, 498, 594, 625, 666, 681 |
| setup_tab.tcl | setup_state::* | 17 call sites (validate_state, DEFAULTS, DEMO_MANIFEST, GAME_REPS, SETUP_FORMAT, hider_count_cap, randomize_state) | ✓ WIRED | setup_tab.tcl:84, 86, 158, 193, 262, 269, 319, 332, 444, 459, 499, 512, 551, 558, 582, 598, 627 |
| refresh_mol_menu | trace variable vmd_molecule w | registered in build | ✓ WIRED | setup_tab.tcl:95 (register), dialog.tcl:87 (vdelete cleanup) |
| do_save | demos::save_setup | tk_getSaveFile -> save_setup | ✓ WIRED | setup_tab.tcl:666 |
| do_load | demos::load_setup | tk_getOpenFile -> load_setup -> validate_state -> apply_state | ✓ WIRED | setup_tab.tcl:681 |
| do_randomize | setup_state::randomize_state | apply_state [randomize_state ...] | ✓ WIRED | setup_tab.tcl:598 |
| WM_DELETE_WINDOW | on_close | `wm protocol $w WM_DELETE_WINDOW ::biochemeleon::on_close` | ✓ WIRED | dialog.tcl:63 |

### Requirements Coverage

All 11 Phase 14 requirements mapped to supporting truths/artifacts and verified.

| Requirement | Status | Evidence |
| --- | --- | --- |
| SETUP-01 (molecule dropdown: loaded + fetch + bundled demos; selecting demo loads via mol new) | ✓ SATISFIED | build_target_group (3 radiobuttons + stacked pages + Loaded/Fetch/Demo menubuttons); refresh_mol_menu (trace); select_loaded_mol; select_demo -> load_demo (mol new). DEMO_MANIFEST drives the Demo menu (6 entries). |
| SETUP-02 (hider count capped to atom count) | ✓ SATISFIED | update_cap reconfigures hider spinbox `-to` via `hider_count_cap([demos::atom_count $current_molid])` (setup_tab.tcl:498-503); clamps current value (line 506). |
| SETUP-03 (lock-scene checkbox) | ✓ SATISFIED | build_hiders_group lock_scene checkbutton (line 183-184); collect_state reads lock_scene (line 275). Detection of reps from the scene is Phase 16 START; Phase 14 reflects the state (per spec — SETUP-03's "detect the rep list from the scene" is the Phase 16 START behavior). |
| SETUP-04 (per-rep list with optional per-rep counts) | ✓ SATISFIED | build_hiders_group 10 per-rep rows (checkbutton + spinbox, disabled by default); on_rep_toggled enables/disables the spinbox (lines 450/473); live-cap keeps sum <= hider_count. |
| SETUP-05 (difficulty toggle easy/hard) | ✓ SATISFIED | build_diff_group 2 radiobuttons (Easy=1/Hard=0) bound to difficulty_easy (lines 217-220). |
| SETUP-06 (random total distribution — quick-008 baked in, never all-spheres when only total set) | ✓ SATISFIED | randomize_per_rep = quick-008 random NON-EMPTY subset (1..len) + non-empty guarantee (setup_state.tcl:204-225); do_randomize calls randomize_state (setup_tab.tcl:598). NOTE: implementation uses "random non-empty subset" (not literal "all reps") — this is the verified v1 quick-008 behavior (14-01-SUMMARY: research Open Q1 resolved per recommendation (a); matches generators.py:252). Satisfies the requirement's intent ("never all-spheres when only a total is set"). |
| BTN-01 (Reset) | ✓ SATISFIED | do_reset -> apply_state $DEFAULTS (setup_tab.tcl:582). |
| BTN-02 (Randomize) | ✓ SATISFIED | do_randomize -> apply_state [randomize_state "" $atom_count $lock_src [collect_state]] (setup_tab.tcl:598); empty seed = non-deterministic. |
| BTN-03 (Save Setup) | ✓ SATISFIED | do_save -> tk_getSaveFile (.bcm) + validate_state-on-save + warning popup + demos::save_setup (setup_tab.tcl:613-669). |
| BTN-04 (Load Setup) | ✓ SATISFIED | do_load -> tk_getOpenFile (.bcm) + demos::load_setup (validates internally) + apply_state (setup_tab.tcl:674-685). |
| DEMO-01 (6 bundled demos: 1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) | ✓ SATISFIED | DEMO_MANIFEST has 6 bundled entries (setup_state.tcl:34-40); all 6 PDBs in vmd/data/demos/; load_demo via mol new; mol smoke verified atom counts (424/2597/2844/555/3408/3779). |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| — | — | — | — | None found. Scanned setup_state.tcl, demos.tcl, dialog.tcl, setup_tab.tcl, biochemeleon.tcl for TODO/FIXME/placeholder/stub/return-null/console.log-only patterns. All gates clean (modeless, 8.6 features, ttk::spinbox, pure-layer, tk-gate). No stub callback bodies remain (all 10 callbacks substantive). |

### Re-run Verification (tests + smokes, not trusted from SUMMARY)

| Check | Command | Result |
| --- | --- | --- |
| Pure-layer tcltest | `cd tmp/bchm14-stage && vmd -dispdev text -e vmd/tests/test_setup_state.test -eofexit` | `BCHM_TEST_RESULT Total=41 Passed=41 Failed=0 Skipped=0` ✓ |
| Mol bridge smoke | `cd tmp/bchm14-stage && vmd -dispdev text -e vmd/smoke/phase14_mol_smoke.tcl -eofexit` | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` (0 Error/error/DEBUG lines; 6 demos loaded; full output read per 14-02 lesson) ✓ |
| GUI smoke | `cd tmp/bchm14-stage && vmd -dispdev text -e vmd/smoke/phase14_gui_smoke.tcl -eofexit` | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` ✓ |
| Phase 13 regression | `cd tmp/bchm14-stage && vmd -dispdev text -e vmd/smoke/phase13_smoke.tcl -eofexit` | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` ✓ |
| Modeless gate | `grep -rnE 'grab set' vmd/gui/` | 0 matches ✓ |
| 8.6 features gate | `grep -rnE '\b(lmap\|try\|throw\|finally\|tailcall\|coroutine\|yield)\b'` (lib + gui) | 0 matches ✓ |
| ttk::spinbox gate | `grep -rnE 'ttk::spinbox' vmd/gui/` | 0 matches ✓ (plain spinbox used) |
| Pure-layer gate | `grep -rnE '\b(mol\|atomselect\|tk\|toplevel\|ttk)\b' vmd/lib/setup_state.tcl` | 0 matches ✓ |
| tk-gate (demos) | `grep -rnE '\b(tk\|toplevel\|ttk)\b' vmd/lib/demos.tcl` | 0 matches ✓ |

Staging used the established `tmp/bchm14-stage` pattern (`mkdir -p && cp -r vmd`, no `rm`) per the SUMMARYs (rm denied by opencode.json). Tcl 8.5.6 constraints honored throughout (no 8.6 idioms; braced expr; one-per-line `variable` for multi-var links after the 14-04 fix).

### Human Verification Required

The GUI rendering cannot be verified headless (Tk does not load in `-dispdev text` — the WSL/Windows runtime split documented in vmd/AGENTS.md). The 14-04-PLAN Task 2 `checkpoint:human-verify` gate was run by the user in a real VMD 1.9.3 GUI session and **APPROVED** (recorded in 14-04-SUMMARY "Verification Results" + STATE.md "Last activity"). No standalone UAT.md exists — the human-verify was an inline blocking checkpoint per the plan's `<resume-signal>`.

What the human-verify confirmed (carried over as the authoritative GUI evidence — not re-verifiable programmatically):

1. **Dialog opens modeless** — Extensions → Visualization → bioCHEMeleon opens the ttk::notebook (Setup + Game tabs); 3D viewer stays interactive (rotate with mouse while dialog open — ENTRY-01).
2. **Target group (SETUP-01)** — 3 radio buttons switch stacked pages; Demo menu lists 6 demos; selecting 1k8p/1znf loads them + caps update (1k8p→11, 1znf→8); Loaded menu lists loaded mols after Refresh; Fetch page shows the "Phase 14: bundled demos only" info label.
3. **Hiders group (SETUP-02/03/04)** — hider count clamps to cap (50→11 for 1k8p, 0→1); lock-scene toggles; 10 per-rep rows; checking VDW/Cartoon enables their spinboxes + live-cap keeps the sum <= hider_count; unchecking disables + clears.
4. **Difficulty (SETUP-05)** — Easy/Hard radio toggle.
5. **Action buttons (BTN-01..04)** — Reset restores defaults; Randomize produces random valid state with a non-empty per_rep set (quick-008), different each click; Save opens a file dialog + writes a human-readable .bcm; Load round-trips (incl. hand-edited hider_count=5 reloaded → shows 5).
6. **Close + reopen (ENTRY-01, trace cleanup)** — close preserves in-progress edits (WM_DELETE handler); reopen shows them; after close, `mol new` in console produces NO error spam (trace vdelete cleaned up).
7. **Re-source guard** — re-sourcing the entry prints the "already loaded" warning (no duplicate dialog, no state reset).

The two bugs found + fixed during that checkpoint (Tcl 8.5 `variable a b` name-VALUE-pairs trap [c3f6d3a] + per-rep-sum live-cap + save warning [fec7c63]) are verified present in the actual codebase: one-per-line `variable` in collect_state/apply_state (lines 251-260, 296-305) and the three-pronged live-cap (on_rep_toggled/recompute_per_rep_maxes/update_cap).

### Gaps Summary

No gaps found. All 14 must-have truths verified. All 8 required artifacts exist, are substantive (no stubs/placeholders), and are wired. All 15 key links connected. All 11 Phase 14 requirements satisfied (SETUP-01..06, BTN-01..04, DEMO-01). All gates clean. The pure-layer tcltest (41/41) + both headless smokes + the Phase 13 regression smoke all re-run green. The GUI human-verify checkpoint was APPROVED in a real VMD session (the one item not re-verifiable headless). The 14-04 checkpoint bug fixes (one-per-line `variable` + live-cap + save warning) are confirmed in the codebase.

The phase goal — "the user can fully configure every game parameter in the Setup tab and load bundled demo molecules — the entire pre-game configuration experience" — is achieved. Phase 14 success criteria 1-4 from ROADMAP.md are all met:
1. ✓ Setup tab molecule dropdown + 6 bundled demos load via mol new (mol smoke-verified).
2. ✓ Hider count capped, lock-scene, per-rep with optional counts, difficulty, total-only random distribution (quick-008 baked in).
3. ✓ Reset/Randomize/Save/Load work as labeled; Save/Load round-trips to a .bcm file (mol smoke eq=1 + GUI checkpoint).
4. ✓ Pure setup-state model unit-tested via tcltest (DEFAULTS, hider-count cap, randomize_state, validate_state, GAME_REPS, DEMO_MANIFEST) — 41 tests green.

Ready to proceed to Phase 15 (Mutation Safety & Hider Registry — HIGHEST RISK).

---

_Verified: 2026-08-29T16:24:22Z_
_Verifier: OpenCode (gsd-verifier)_
