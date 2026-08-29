# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-22)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** v2.0 — VMD tcl port. Phase 14 (Setup Tab & Bundled Demos) in progress — 14-01 (pure-layer setup-state model) + 14-02 (mol bridge demos.tcl) + 14-03 (GUI setup_tab structure + dialog.tcl extraction) complete; 14-04 (wire callbacks + GUI human-verify) next.

## Current Position

Phase: 14 of 23 (Setup Tab & Bundled Demos) — IN PROGRESS
Plan: 3 of 4 in current phase (14-01 + 14-02 + 14-03 complete)
Status: Phase 14 in progress; pure-layer + mol bridge + GUI structure done, ready for 14-04 (wire the 10 stub callbacks + WM_DELETE_WINDOW handler + GUI human-verify checkpoint)
Last activity: 2026-08-29 — Completed 14-03-PLAN.md (GUI setup_tab structure: extracted open_dialog to gui/dialog.tcl + built full gui/setup_tab.tcl form — 4 groups [Target/Hiders/Difficulty/Actions] + collect_state/apply_state with _loading guard + switch_page + 10 stub callbacks; entry sources demos.tcl + gui/dialog.tcl; 11-check headless smoke green; modeless/8.6/ttk::spinbox/tk_version gates clean; Phase 13 + Phase 14 mol smokes still green [no regression]. KEY: tcl 8.5 `dict get` has NO 3-arg default form [probe-verified] — added `_dget` helper using dict exists+dict get; setup_tab.tcl sourced at dialog.tcl's TOP LEVEL [not in a proc body] to avoid the [info script]-is-call-time trap).

Progress: ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ~9% v2.0 (1 of 11 phases complete; Phase 14 in progress 3/4 plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 5 (v2.0); 77 in v1 (archived)
- Average duration: 20 min (v2.0, 5 plans)
- Total execution time: 99 min (v2.0)

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 13. Bootstrap & Sourced Entry | 2/2 | 50 min | 25 min |
| 14. Setup Tab & Bundled Demos | 3/4 | 49 min | 16 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- **v2.0 milestone start (2026-08-22):** Port v1 to VMD 1.9.3 as a sourced tcl script. MVP-first; research drives rep selection; materials explored as differentiator. Phases numbered 13-23 (continuing from v1's 11+04.1).
- **v2 architecture:** PDB-rebuild (Option D) replaces in-place insertion — highest-risk change, de-risked in Phase 15. Backup = reload original PDB (no undo). Registry keyed by atom `index` (no global id). `.bcm` JSON hand-rolled (no `json` package). Pure-layer tcl unit-testable in WSL via `tclsh`/`tcltest`.
- **v2 de-risking order:** Phase 15 (mutation safety) before Phase 16 (MVP loop) — PDB-rebuild proven before generators build on it. Phase 16 locks the pick contract via GUI human-verify (MEDIUM-confidence research flag). Materials (Phase 18) after reps (Phase 17.2) solid.
- **Phase 17 split (2026-08-22 revision):** Phase 17 (rep generators) split into 17.1 (rep setup infrastructure + simple generators — Lines/VDW/Licorice, HIDER-06/HIDER-04) and 17.2 (cartoon generators — Cartoon/NewCartoon, HIDER-05) by generator complexity tier. Simple reps are bonded pseudoatom analogues; cartoon reps carry the STRIDE `ss='L'` L-complexity caveat (v1 Phase 11 analogue) and are de-risked separately.
- **Phase 23 docs (2026-08-22 revision):** Final phase 23 added for documentation — root README (multi-viewer), `vmd/README.md` (VMD tcl install/use), `pymol/README.md` (PyMOL plugin install/use). 3 DOC requirements added (54 total). AGENTS.md VMD/tcl rewrite is a post-workflow task, NOT a roadmap phase.
- **13-01 pure-layer namespaces (2026-08-28):** `::biochemeleon::setup_state` and `::biochemeleon::registry` (filename parity with v1; NOT `::biochemeleon::setup`). Entry script (13-02) MUST source by these exact names.
- **13-01 tcltest under headless VMD (2026-08-28):** `tclsh` NOT in WSL (AGENTS.md forbids apt). tcltest runs UNDER headless VMD via `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e <file>.test -eofexit < /dev/null'`. Result parsed from `BCHM_TEST_RESULT` marker, NOT `$?` (VMD doesn't propagate tcl exit codes). `.test` files are standalone-tclsh-compatible if user later installs tcl.
- **13-01 DI via tcl command-prefix + {expand} (2026-08-28):** `reconstruct_from_sentinels` uses `[{*}$fetch_hider_ids]` (argument expansion), NOT `[$fetch_hider_ids]` (single-word). Supports both proc names and `apply` lambda lists. Downstream Phase 15 game.tcl MUST use `{*}` when injecting `apply` lambdas.
- **13-02 GUI checkpoint + tk_version lesson (2026-08-29):** Phase 13 GUI checkpoint APPROVED — ttk::notebook renders correctly in VMD 1.9.3 Tk; modeless dialog keeps viewer interactive (no grab; brief OpenGL pause during window-move is normal VMD behavior, acceptable); re-source guard works (prints warning, prevents duplicate dialog + state reset); menu path Extensions → Visualization → bioCHEMeleon confirmed. One bug found+fixed: `info exists tk_version` inside a proc checks LOCAL scope only → use `::tk_version` (global qualifier). Downstream Phase 14+ GUI procs MUST use `::tk_version`. Headless smoke pattern (`bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/*.tcl -eofexit < /dev/null'` + `BCHM_SMOKE_RESULT` marker + `[pwd]`-based path resolution) is the established Phase 14+ pattern.
- **14-01 setup-state model + quick-008 (2026-08-29):** validate_state is a DETERMINISTIC clamp (NO randomness) — full v1 port with drop-overflow per_rep clamp (Pitfall 7: keep entries that fit, DROP overflow, never truncate; `{VDW 5 Cartoon 5 Lines 5}` hc=8 → `{VDW 5}`), DEFAULTS-key-order result (Pitfall 5: order-stable dict eq), enum/bool/pdb_pool validation. randomize_per_rep implements quick-008 SETUP-06 as a random NON-EMPTY SUBSET (1..len) of reps + non-empty guarantee (NOT all-reps — the verified v1 quick-008 behavior; research Open Q1 resolved per recommendation (a)). randomize_state seeds the GLOBAL PRNG once (`expr {srand($seed)}`) and calls randomize_per_rep with NO seed (continues the sequence); lock_source=1 preserves locked target else weighted-random mode (loaded/fetch/demo/demo; empty pdb_pool re-rolls fetch→demo). All randomness tests pass an explicit seed arg (Pitfall 4 mitigation — no reliance on residual global PRNG state). 41 tcltest cases green under headless VMD; pure-layer + 8.6 gates clean. Downstream: callers wanting reproducible randomization must pass a seed and NOT interleave `rand()` calls (global PRNG). v2 pdb_pool stays empty (no PDB_POOL constant; fetch is a later phase).
- **14-02 mol bridge demos.tcl (2026-08-29):** 8-proc `::biochemeleon::demos` namespace (to_vmd_path, list_loaded_molecules, load_demo, get_active_reps, fetch_pdb STUB, save_setup, load_setup, atom_count) sourcing setup_state.tcl for constants. KEY: `[info script]` is DYNAMIC (call-time context, NOT definition-time file) — using it inside a proc body returns "" under `vmd -e` after source completes; `load_demo` captures `script_dir` at source time (namespace variable set inside `namespace eval`, which runs during source) and references the frozen variable. This is the standard tcl "where am I defined" pattern (the entry already uses it at top-level via `set _dir`); research Pattern 1 was subtly wrong for proc-body usage. get_active_reps uses the COMBINED-BRACES molinfo form `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` (single-field form FAILS — Pitfall 3). save/load_setup: key-value line format + DEFAULTS-key-order rebuild on load (Pitfall 5 order-stable `eq` round-trip); load_setup calls validate_state for defense-in-depth. Round-trip verified via the `eq` OPERATOR (`expr {$a eq $b}`), NOT a `dict eq` subcommand (does NOT exist in tcl 8.5 — research "dict eq" is shorthand for the eq operator). fetch_pdb is a clean stub (Phase 21 real fetch; VMD 1.9.3 lacks tls for HTTPS). 7-check headless smoke green (6 demos load w/ verified atom counts, rep detection survives delrep renumbering, save/load eq=1). LESSON: always read the FULL smoke output, not just the BCHM_SMOKE_RESULT marker — VMD `-e` catches top-level errors and continues, so an error mid-script does NOT prevent the marker from printing a false PASS.
- **14-03 GUI setup_tab structure (2026-08-29):** Extracted `::biochemeleon::open_dialog` from the entry to `vmd/gui/dialog.tcl` (modeless toplevel + ttk::notebook; NO grab set, NO WM_DELETE_WINDOW handler yet [Plan 04]). Built full `vmd/gui/setup_tab.tcl` — `::biochemeleon::setup_tab` namespace: 19 procs (8 full-body structural [build + 4 group builders + collect_state/apply_state/switch_page] + `_dget` helper + 10 STUB callbacks [body=return; Plan 04 fills]). 4 groups: Target (3 ttk::radiobuttons + frame-raise mode selector + menubutton+menu dropdowns), Hiders (plain spinbox + lock-scene + 10 per-rep rows), Difficulty (Easy/Hard radiobuttons), Actions (4 buttons). collect_state/apply_state with the `_loading` guard + catch-based error reset (tcl 8.5 has no try/finally) + `dict set ::biochemeleon::state setup` persistence. KEY DECISIONS: (1) source setup_tab.tcl at dialog.tcl's TOP LEVEL (load time), NOT in a proc body — `[info script]` is call-time so a proc-body source would fail when open_dialog is called from the console (applied the 14-02 lesson proactively); (2) tcl 8.5 `dict get` has NO 3-arg default form — probe-verified (`dict get $d key default` errors "missing value to go with key"; the 3rd arg is a nested key) — added `_dget` helper using `dict exists`+`dict get` (the plan/research's `dict get $state key $default` was a myth); (3) callbacks are stubs in this plan so Plan 04 is purely "wire the callbacks"; (4) `variable arr` (no value) leaves the var undefined so `set arr($k) v` creates it as an array (probe-verified — the research skeleton's pattern is correct). Entry modified to source demos.tcl + gui/dialog.tcl; inline open_dialog removed; public procs + menu registration intact. 11-check headless smoke green (loading layer only — namespaces + procs exist; widget rendering is Plan 04's human-verify since Tk doesn't load in -dispdev text). Modeless/8.6/ttk::spinbox/tk_version gates clean (comments reworded to avoid the literal gated terms — matching 14-02's pattern). Phase 13 + Phase 14 mol smokes still green (no regression). LESSON: pre-verify tcl API "forms" under the actual runtime (VMD tcl 8.5.6) before using them — the `dict get` 3-arg myth was in BOTH the plan and the research.

### Pending Todos

None yet.

### Blockers/Concerns

- **Phase 16 pick mechanism (MEDIUM confidence):** All 4 researchers referenced VMD's pick system with different specifics; `vmd_pick_*` globals are absent in text mode. Must lock the contract via ONE human-in-GUI test in Phase 16. Design PickBridge defensively (trace + callback-list + label-poll fallback).
- **Phase 15 PDB-rebuild (HIGHEST risk):** Viewpoint/reps must save+restore on a NEW molid; PDB column misalignment silently drops sentinels (mitigation: tag sentinels in-place via atomselect after load, never rely on PDB columns alone).
- **AGENTS.md VMD/tcl rewrite** deferred until after v2 research/execution progresses (currently v1-scoped per header note).

## Session Continuity

Last session: 2026-08-29 — Completed 14-03-PLAN.md (Phase 14 plan 3 of 4)
Stopped at: 14-03 complete. Commits: 86207c0 (feat: GUI setup_tab structure + extract open_dialog to dialog.tcl), 0d1efdd (test: GUI headless smoke). gui/dialog.tcl (open_dialog extracted; sources setup_tab.tcl at load time) + gui/setup_tab.tcl (19 procs: 8 full-body + _dget + 10 stubs; 4 widget groups; collect_state/apply_state with _loading guard) + entry modified (sources demos.tcl + gui/dialog.tcl; inline open_dialog removed). 11-check headless smoke green; Phase 13 + Phase 14 mol smokes still green (no regression); modeless/8.6/ttk::spinbox/tk_version gates clean. DEMO-01/SETUP-01..05 + BTN-01..04 UI STRUCTURE satisfied (callbacks stubbed; Plan 04 wires them).
Resume file: None
Next: 14-04-PLAN.md (wire the 10 stub callbacks with real impls: refresh_mol_menu [trace -> repopulate menu from molinfo list], select_demo/select_loaded_mol [dropdown -> set target + update_cap], on_rep_toggled [enable/disable per-rep spinbox], recompute_per_rep_maxes/update_cap [hider_count cap via demos::atom_count + hider_count_cap], do_reset [apply_state DEFAULTS], do_randomize [apply_state randomize_state], do_save/do_load [tk_getSaveFile/tk_getOpenFile + demos::save_setup/load_setup with .bcm]; + WM_DELETE_WINDOW handler [collect_state + trace vdelete + destroy] + the GUI human-verify checkpoint for widget rendering). Then Phase 15 (mutation-safety: PDB-rebuild, the highest-risk change).

## v1 Milestone Reference (archived)

- **Shipped:** 2026-08-18 — bioCHEMeleon v1 (PyMOL 2.5.0 plugin), 12 phases, 77 plans, 393 commits, 46/46 requirements ✅ PASSED audit. Git tag: `v1`.
- **v1.1:** Shipped 2026-08-22 — 5 bugfix/gameplay quick tasks (207 unit tests green).
- **Archived:** `milestones/v1-{ROADMAP,REQUIREMENTS,MILESTONE-AUDIT}.md`; full execution history in `phases/*/*-SUMMARY.md`.
- **Known v1 tech debt considered for v2:** Phase 9 SSL fallback (check_hostname=False); Phase 11 SS-inheritance (cosmetic). v1.1 quick-008 (random total distribution) baked into v2 from the start (SETUP-06).

---
*Updated: 2026-08-29 after 14-03-PLAN.md completion (Phase 14 in progress, 3/4 plans)*
