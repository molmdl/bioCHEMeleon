---
phase: 13-bootstrap-sourced-entry
verified: 2026-08-29T08:30:15Z
status: passed
score: 15/15 must-haves verified
re_verification: false
evidence_sources:
  code_inspection: 15  # all truths structurally verified by reading files
  headless_smoke_rerun: 3  # 13-02 truths 5, 6, 7 re-run live
  tcltest_rerun: 2  # both suites re-run live (Failed=0)
  grep_gate_rerun: 1  # both gates re-run live (zero matches)
  human_gui_checkpoint: 4  # 13-02 truths 1, 2, 3, 4 (already APPROVED; VMD GUI can't run from WSL)
---

# Phase 13: Bootstrap & Sourced Entry Verification Report

**Phase Goal:** The script loads cleanly into VMD and opens a modeless dialog — the stable shell every later phase builds on, with the 3D viewer kept interactive for click-to-find.
**Verified:** 2026-08-29T08:30:15Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

All 15 plan-level must-haves (8 from 13-01, 7 from 13-02) are verified against the ACTUAL codebase. The phase goal is achieved: the entry script loads cleanly, opens a modeless `ttk::notebook` dialog with Setup+Game tabs, keeps the 3D viewer interactive (no `grab set`), survives re-sourcing, runs headlessly from WSL, and establishes the pure-layer tcl foundation with passing tcltest suites.

## Observable Truths

| # | Truth | Status | Evidence |
|---|------|--------|----------|
| 1 | lib/setup_state.tcl sources cleanly under headless VMD with no mol/tk dependency | ✓ VERIFIED | tcltest sourced it under headless VMD (12/12 PASSED); grep gate 1 returned EXIT=1 (zero matches for mol/atomselect/tk/toplevel/ttk::) |
| 2 | lib/registry.tcl sources cleanly under headless VMD with no mol/tk dependency | ✓ VERIFIED | tcltest sourced it under headless VMD (5/5 PASSED); grep gate 1 returned EXIT=1 |
| 3 | GAME_REPS is the 10-rep v2 list (Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds) | ✓ VERIFIED | setup_state.tcl:10 `variable GAME_REPS {Lines VDW Licorice CPK Cartoon NewCartoon Trace Tube Points DynamicBonds}` — exact match; tests `game_reps_count`=10, `game_reps_first_is_lines`="Lines" PASSED |
| 4 | hider_count_cap matches v1's heuristic (212→4, 0→1, 100000→50) | ✓ VERIFIED | setup_state.tcl:51-59; tests `hider_cap_small`=4, `hider_cap_zero`=1, `hider_cap_large`=50 all PASSED |
| 5 | DEMO_MANIFEST has the 6 bundled demo entries (1znf/1xdn/5e54/1k8p/2qbz/4wb3) | ✓ VERIFIED | setup_state.tcl:34-40 has all 6 keys with source=bundled; tests `demo_manifest_has_6_bundled`=6, `demo_manifest_1znf_bundled`="bundled" PASSED; 6 PDB files exist on disk |
| 6 | registry reconstruct_from_sentinels accepts injected fetch_hider_ids (DI) and clears+repopulates _records | ✓ VERIFIED | registry.tcl:31-38 `set _records [dict create]` then `foreach idx [{*}$fetch_hider_ids]`; tests `reconstruct_clears_and_populates`={1 1 1 0}, `reconstruct_clears_previous`={0 1 1} PASSED |
| 7 | tcltest passes under headless VMD with Failed=0 (parsed from BCHM_TEST_RESULT marker, NOT $?) | ✓ VERIFIED | Re-run live: setup_state `BCHM_TEST_RESULT Total=12 Passed=12 Failed=0 Skipped=0`; registry `BCHM_TEST_RESULT Total=5 Passed=5 Failed=0 Skipped=0` |
| 8 | grep gate ZERO matches for mol/atomselect/tk/toplevel/ttk:: AND ZERO for lmap/try/throw/tailcall/coroutine/yield in pure layer | ✓ VERIFIED | Re-run live: both greps returned EXIT=1 (zero matches) on vmd/lib/*.tcl (+ entry for the 8.6-idioms gate) |
| 9 | Sourcing biochemeleon.tcl registers 'bioCHEMeleon' under Extensions → Visualization with no errors | ✓ VERIFIED | biochemeleon.tcl:149 `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"` inside `if {[info exists tk_version]}` (line 147); GUI checkpoint APPROVED (13-02-SUMMARY.md:78; commit 57bcc53 "Found via GUI human-verify checkpoint") |
| 10 | Re-sourcing biochemeleon.tcl does not reset state or duplicate the dialog (guard prints warning + returns) | ✓ VERIFIED | biochemeleon.tcl:29-32 guard BEFORE namespace eval: `if {[info exists ::biochemeleon::loaded] && $::biochemeleon::loaded} { vmdcon -warn "bioCHEMeleon already loaded; ignoring re-source"; return }`; GUI checkpoint APPROVED |
| 11 | Running biochemeleon command opens a modeless ttk::notebook dialog with Setup and Game placeholder tabs | ✓ VERIFIED | biochemeleon.tcl:85-104 `open_dialog`: `toplevel .biochemeleon` + `ttk::notebook $w.nb` + `$nb add $nb.setup -text "Setup"` + `$nb add $nb.game -text "Game"`; GUI checkpoint APPROVED (tabs switch confirmed) |
| 12 | The 3D viewer stays interactive — NO grab set on the main dialog | ✓ VERIFIED | No `grab set` command in `open_dialog` (lines 85-104); grep for `grab set` matches ONLY comment lines 80-81 (the "NO grab set" explanation), never a command; GUI checkpoint APPROVED (viewer interactive confirmed) |
| 13 | The script runs headlessly from WSL via vmd -dispdev text -e <smoke> -eofexit without error (BCHM_SMOKE_RESULT PASS=1) | ✓ VERIFIED | Re-run live: `BCHM_SMOKE_RESULT PASS=1 FAIL=none` (all 5 smoke assertions passed) |
| 14 | The biochemeleon command no-ops gracefully in headless mode (tk_version guard prints vmdcon -warn and returns) | ✓ VERIFIED | biochemeleon.tcl:117-120 `if {![info exists ::tk_version]} { vmdcon -warn "..."; return }` (global qualifier `::tk_version` — the bug-fix from commit 57bcc53 is present); smoke output showed `Warning) bioCHEMeleon: GUI requires Tk (not available in -dispdev text).` + clean `0` return |
| 15 | ::biochemeleon::setup_state and ::biochemeleon::registry namespaces are loaded after sourcing the entry | ✓ VERIFIED | biochemeleon.tcl:70-72 sources BOTH lib files via `[file dirname [info script]]`; smoke asserts `namespace exists ::biochemeleon::setup_state` + `::biochemeleon::registry` (lines 39-46) PASSED |

**Score:** 15/15 truths verified

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `vmd/lib/setup_state.tcl` | Pure layer: GAME_REPS, SETUP_FORMAT, DEFAULTS, DEMO_MANIFEST, hider_count_cap, validate_state stub | ✓ VERIFIED | 66 lines; namespace `::biochemeleon::setup_state`; all symbols present + exported (line 45); no stub patterns (validate_state is a CONTRACTED scoped stub, tested by `validate_state_stub_returns_defaults`) |
| `vmd/lib/registry.tcl` | Pure layer: HIDER_STATUS, _records, reconstruct_from_sentinels (DI), is_hider, mark_found | ✓ VERIFIED | 57 lines; namespace `::biochemeleon::registry`; DI via `[{*}$fetch_hider_ids]` (line 34); exports documented (line 19); is_hider/mark_found are scoped stubs with tested contracts |
| `vmd/biochemeleon.tcl` | 8-step entry: guard, namespace, package provide, source lib, open_dialog, biochemeleon proc, _tk_cb, vmd_install_extension | ✓ VERIFIED | 153 lines; all 8 steps present (comments at lines 21,35,53,62,76,107,126,137); re-source guard BEFORE namespace eval; package provide (line 59) BEFORE vmd_install_extension (line 149); NO grab set; `::tk_version` global qualifier |
| `vmd/smoke/phase13_smoke.tcl` | Headless smoke using [pwd] to locate entry; BCHM_SMOKE_RESULT marker | ✓ VERIFIED | 54 lines; uses `[file join [pwd] vmd biochemeleon.tcl]` (line 17); 5 assertions; BCHM_SMOKE_RESULT marker (lines 50-53); re-run PASSED |
| `vmd/tests/test_setup_state.test` | tcltest suite, 12 cases, BCHM_TEST_RESULT marker | ✓ VERIFIED | 74 lines; 12 cases; re-run Total=12 Passed=12 Failed=0 |
| `vmd/tests/test_registry.test` | tcltest suite, 5 cases, BCHM_TEST_RESULT marker | ✓ VERIFIED | 55 lines; 5 cases; re-run Total=5 Passed=5 Failed=0 |
| `vmd/pkgIndex.tcl` | Optional packaged-install form | ✓ VERIFIED | 9 lines; `package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]` |
| `vmd/wsl2win_cp.sh` | Staging script | ✓ VERIFIED | 13 lines; copies vmd/ to staging path |
| `vmd/gui/.gitkeep` | Placeholder dir for Phase 14/16 gui files | ✓ VERIFIED | Exists (0 bytes) |
| `vmd/data/demos/*.pdb` (6) | Bundled demo PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) | ✓ VERIFIED | All 6 PDBs exist on disk (1znf 1.3MB, 1xdn 465KB, 5e54 493KB, 1k8p 86KB, 2qbz 342KB, 4wb3 803KB) |
| `vmd/data/demos/SOURCES.md` | Attribution | ✓ VERIFIED | Exists; points to repo-root DATA_SOURCES.md (Phase 9 DEMO-04) |

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `biochemeleon.tcl` (entry) | `lib/setup_state.tcl` | `source [file join $_dir lib setup_state.tcl]` (line 71) | ✓ WIRED | Smoke asserted `namespace exists ::biochemeleon::setup_state` PASSED |
| `biochemeleon.tcl` (entry) | `lib/registry.tcl` | `source [file join $_dir lib registry.tcl]` (line 72) | ✓ WIRED | Smoke asserted `namespace exists ::biochemeleon::registry` PASSED |
| `biochemeleon` global proc | `open_dialog` | `::biochemeleon::open_dialog` (line 121) | ✓ WIRED | GUI checkpoint: console command opened the dialog (after the ::tk_version fix) |
| `biochemeleon_tk_cb` | `open_dialog` | `::biochemeleon::open_dialog` (line 132) | ✓ WIRED | GUI checkpoint: menu click opened the dialog |
| `vmd_install_extension` | `biochemeleon_tk_cb` | registration call (line 149) | ✓ WIRED | GUI checkpoint: Extensions → Visualization → bioCHEMeleon item appeared |
| `open_dialog` | ttk::notebook Setup+Game | `$nb add $nb.setup`/`$nb add $nb.game` (lines 94-95) | ✓ WIRED | GUI checkpoint: notebook rendered with switchable Setup+Game tabs |
| `reconstruct_from_sentinels` | injected `fetch_hider_ids` | `foreach idx [{*}$fetch_hider_ids]` (line 34) | ✓ WIRED | tcltest: 3 reconstruct tests PASSED with injected `apply` lambdas |
| `phase13_smoke.tcl` | `biochemeleon.tcl` | `source [file join [pwd] vmd biochemeleon.tcl]` (line 17) | ✓ WIRED | Re-run: smoke sourced the entry + all 5 assertions PASSED |
| `test_setup_state.test` | `lib/setup_state.tcl` | `source [file join [pwd] vmd lib setup_state.tcl]` (line 13) | ✓ WIRED | Re-run: 12/12 PASSED |
| `test_registry.test` | `lib/registry.tcl` | `source [file join [pwd] vmd lib registry.tcl]` (line 12) | ✓ WIRED | Re-run: 5/5 PASSED |

## Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| ENTRY-01 (sourced tcl + biochemeleon command opens modeless ttk::notebook Setup+Game; NO grab) | ✓ SATISFIED | None — open_dialog (lines 85-104) + no grab set; GUI checkpoint APPROVED |
| ENTRY-02 (vmd_install_extension registers Extensions item; re-source guard prevents reset/duplicate) | ✓ SATISFIED | None — line 149 + guard lines 29-32; GUI checkpoint APPROVED |
| ENTRY-03 (all v2 code under vmd/; zero external deps — only tcl/Tk 8.5 + ttk) | ✓ SATISFIED | None — entire v2 tree under vmd/; pure layer grep gate clean; entry uses only stdlib + VMD-bundled Tk/ttk |
| TEST-01 (headless testing via vmd -dispdev text -e from WSL) | ✓ SATISFIED | None — smoke + both tcltest suites re-run headlessly from WSL, all PASSED |
| TEST-02 (pure-layer architecture; lib/*.tcl stdlib-only, unit-testable via tcltest) | ✓ SATISFIED | None — grep gate zero matches; tcltest 17/17 PASSED under headless VMD |

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `vmd/lib/setup_state.tcl` | 61-66 | `validate_state` returns DEFAULTS (stub) | ℹ️ Info | CONTRACTED scoped stub — Phase 13 scope is "file + loadability"; full validation is Phase 14. Tested by `validate_state_stub_returns_defaults` (asserts `format` key present). NOT a blocker. |
| `vmd/lib/registry.tcl` | 40 | comment "Phase 13 stubs (a later phase fills in the real logic)" | ℹ️ Info | is_hider/mark_found are real working implementations (not no-ops); the comment refers to the broader registry logic (sentinel iteration injection point) which is Phase 15. Tested. NOT a blocker. |

No 🛑 blockers. No ⚠️ warnings. The two ℹ️ items are explicitly-scoped, tested stubs that match the Phase 13 contract ("file + loadability + DI proc shape" per registry.tcl:4). They are intentional, not incomplete placeholders.

## Human Verification Required

**None pending.** The GUI-dependent truths (menu item registration visual confirmation, ttk::notebook rendering, viewer interactivity, re-source guard behavior) were already verified by a human in a real VMD 1.9.3 GUI session during Plan 13-02 Task 3 (checkpoint:human-verify APPROVED). The checkpoint was substantive — it caught the `tk_version` scoping bug (checks 11-12 failed), which was fixed in commit `57bcc53` and re-tested before approval. VMD's GUI cannot run from WSL (needs Tk + a real display), so the checkpoint record is the only available evidence for GUI-rendering truths; this is the documented v2 human-verify split (same as v1's Qt split).

Evidence the checkpoint actually ran (not just claimed):
- Commit `57bcc53 fix(13-02): use ::tk_version global qualifier in biochemeleon proc` — message: "Found via GUI human-verify checkpoint (checks 11-12 failed)" — a real bug was caught and fixed via the checkpoint.
- 13-02-SUMMARY.md:78 documents the approval: "GUI checkpoint APPROVED ... Extensions → Visualization → bioCHEMeleon menu item appears and opens the dialog; ttk::notebook renders with Setup+Game tabs that switch; 3D viewer stays interactive ... re-source guard prints a warning and prevents duplicate dialog + state reset."

## Gaps Summary

No gaps found. All 15 must-haves verified by a combination of:
- **Code inspection** (all 15 truths — structure confirmed by reading the actual files, not SUMMARY claims)
- **Headless smoke re-run** (truths 13, 14, 15 — `BCHM_SMOKE_RESULT PASS=1 FAIL=none`)
- **tcltest suites re-run** (truths 1-7 — setup 12/12, registry 5/5, both Failed=0)
- **Grep gate re-run** (truth 8 — zero matches on both gates)
- **Human GUI checkpoint** (truths 9, 10, 11, 12 — already APPROVED; the only way to verify GUI rendering since VMD GUI can't run from WSL)

The phase goal — "the script loads cleanly into VMD and opens a modeless dialog, the stable shell every later phase builds on, with the 3D viewer kept interactive" — is achieved. Phase 13 is the stable shell. Ready to proceed to Phase 14.

---

_Verified: 2026-08-29T08:30:15Z_
_Verifier: OpenCode (gsd-verifier)_
