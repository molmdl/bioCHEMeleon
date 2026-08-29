---
phase: 14-setup-tab-bundled-demos
plan: 03
subsystem: gui
tags: [tcl, vmd, tk, ttk, gui, setup-tab, spinbox, menubutton, state-roundtrip, headless-smoke]

# Dependency graph
requires:
  - phase: 14-setup-tab-bundled-demos (plan 01)
    provides: validate_state (full deterministic clamp) + DEFAULTS/GAME_REPS/DEMO_MANIFEST/SETUP_FORMAT constants; the canonicalizer apply_state calls on init
  - phase: 14-setup-tab-bundled-demos (plan 02)
    provides: demos.tcl mol bridge (load_demo/get_active_reps/save+load_setup/atom_count/list_loaded_molecules); the GUI sources it for every molecule operation
  - phase: 13-bootstrap-sourced-entry
    provides: entry bootstrap (re-source guard + namespace + package provide + ::biochemeleon::state dict with `setup` key + tk_version-guarded public procs + menu registration); the ttk::notebook pattern
provides:
  - "vmd/gui/dialog.tcl — ::biochemeleon::open_dialog extracted from the entry (modeless toplevel + ttk::notebook Setup+Game; sources setup_tab.tcl at load time; calls setup_tab::build to populate Setup tab)"
  - "vmd/gui/setup_tab.tcl — ::biochemeleon::setup_tab namespace: full Setup form (4 groups: Target/Hiders/Difficulty/Actions) + collect_state/apply_state (with _loading guard, catch-based error reset) + switch_page + _dget helper + 10 stub callbacks"
  - "vmd/biochemeleon.tcl modified: sources demos.tcl + gui/dialog.tcl; inline open_dialog removed; public procs + menu registration intact (thin bootstrap)"
  - "vmd/smoke/phase14_gui_smoke.tcl — 11-check headless smoke (BCHM_SMOKE_RESULT marker) verifying the loading layer"
affects:
  - "14-04 (wire callbacks: fills the 10 stubs with real impls + adds WM_DELETE_WINDOW handler with trace vdelete + the GUI human-verify checkpoint for widget rendering)"
  - "Phase 16 (Start flow reads the Setup state via collect_state; Game tab populated)"
  - "Phase 20 (.bcm Save/Load: do_save/do_load call demos::save_setup/load_setup with .bcm extension)"

# Tech tracking
tech-stack:
  added: []  # stdlib tcl + Tk/ttk (ships with VMD 1.9.3); no new libraries
  patterns:
    - "Top-level `source` of a sibling module at load time (NOT inside a proc body): dialog.tcl sources setup_tab.tcl at its own top level where [info script] = dialog.tcl's path. Avoids the 14-02 [info script]-is-call-time trap (a proc-body source would resolve to the call-time context, empty under `vmd -e`)."
    - "_loading guard + catch-based error reset (tcl 8.5 has no try/finally): apply_state sets _loading=1, wraps the body in `catch`, ALWAYS sets _loading=0 after, then re-raises on error. The direct port of v1's self._loading boolean."
    - "_dget helper for dict-get-with-default: tcl 8.5 `dict get` has NO 3-arg default form (probe-verified); the plan's `dict get $state key $default` would error. _dget uses `dict exists`+`dict get` to achieve the same safety intent."
    - "Stacked-pages-in-one-grid-cell + `raise` (the QStackedWidget analog): 3 page frames gridded in the SAME cell; switch_page raises the selected. The mergestructs/autoionize idiom."
    - "menubutton + menu + radiobutton entries for molecule dropdowns (the clonerep pattern); trace variable vmd_molecule w for refresh (registered in build; callback is a stub in this plan, real in Plan 04)."
    - "Plain `spinbox` (NOT ttk::spinbox — ABSENT in Tk 8.5.6, Pitfall 1) for hider count + per-rep counts."
    - "Comment hygiene: avoid the literal gated terms (grab set / lmap / try / finally / ttk::spinbox / bare tk_version) in COMMENTS so the grep gates return zero (matching 14-02's pattern)."

key-files:
  created:
    - "vmd/gui/dialog.tcl — open_dialog extracted from entry; sources setup_tab.tcl at load time; modeless toplevel + ttk::notebook + setup_tab::build; no grab set, no WM_DELETE_WINDOW handler (Plan 04)"
    - "vmd/gui/setup_tab.tcl — full Setup form (19 procs: 8 full-body structural + _dget + 10 stub callbacks); namespace vars for all widget-bound state"
    - "vmd/smoke/phase14_gui_smoke.tcl — 11-check headless smoke (loading layer: entry + open_dialog proc + 4 namespaces + 4 key procs + validate_state spot-check)"
  modified:
    - "vmd/biochemeleon.tcl — added `source demos.tcl` + `source gui/dialog.tcl` to the source block; removed inline open_dialog (now in dialog.tcl); public procs + menu registration kept"

key-decisions:
  - "Source setup_tab.tcl at dialog.tcl's TOP LEVEL (load time), NOT inside open_dialog: [info script] is dynamic (call-time), so a proc-body source would fail when open_dialog is called from the console/menu. Top-level source runs during dialog.tcl's own source where [info script] is correct. (Applied the 14-02 KEY LESSON proactively.)"
  - "_dget helper replaces the plan's `dict get $state key $default`: probe-verified that tcl 8.5.6 `dict get` has NO 3-arg default form (the 3rd arg is a nested key -> 'missing value to go with key'). _dget = `dict exists`+`dict get`. Same safety intent, 8.5-correct."
  - "Callbacks are STUBS (body = return) in THIS plan: the form renders + state round-trips programmatically (collect_state/apply_state are full); buttons/dropdown/trace do nothing until Plan 04. This makes Plan 04 purely 'wire the callbacks' — a clean, focused task."
  - "No WM_DELETE_WINDOW handler in this plan: it would call collect_state + trace vdelete which reference Plan 04 callbacks. The trace IS registered in build (refresh_mol_menu stub is a safe no-op); Plan 04 adds the handler that does trace vdelete."
  - "refresh_mol_menu takes `args` (the trace callback signature is {name1 name2 op} — Pitfall 2); the args form accepts and ignores them."

patterns-established:
  - "Top-level sibling-source at load time: `source [file join [file dirname [info script]] sibling.tcl]` at a module's top level (NOT in a proc body). The standard way to source a sibling that a proc later uses."
  - "_dget (dict-get-with-default) is the tcl-8.5-correct default-get; reusable by any Phase 14+ GUI proc that reads a possibly-half-populated dict."
  - "_loading guard + catch error-reset: the tcl-8.5 port of try/finally for 'always reset a flag'. Reusable by Plan 04's real callbacks that set _loading-sensitive state."
  - "GUI headless smoke = loading-layer only (namespaces + procs exist; NO widget calls — Tk doesn't load in -dispdev text). Widget rendering is a human-verify checkpoint (Plan 04)."

# Metrics
duration: 21min
completed: 2026-08-29
---

# Phase 14 Plan 03: GUI Setup tab structure Summary

**Extracted `open_dialog` to `gui/dialog.tcl` + built the full `gui/setup_tab.tcl` form (4 widget groups, collect_state/apply_state with the `_loading` guard, switch_page, 10 stub callbacks) + wired the entry to source the GUI layer — 11-check headless smoke green; modeless/8.6/ttk::spinbox/tk_version gates clean.**

## Performance

- **Duration:** 21 min
- **Started:** 2026-08-29T12:31:23Z
- **Completed:** 2026-08-29T12:52:24Z
- **Tasks:** 2 (Task 1: dialog.tcl + setup_tab.tcl + entry; Task 2: headless GUI smoke + verification)
- **Files modified:** 4 (3 created + 1 modified)

## Accomplishments
- Extracted `::biochemeleon::open_dialog` from the entry to `vmd/gui/dialog.tcl` (modeless toplevel + ttk::notebook Setup+Game tabs); sources `setup_tab.tcl` at LOAD TIME (top-level source, where `[info script]` is correct — applied the 14-02 KEY LESSON proactively to avoid the call-time trap); calls `setup_tab::build` to populate the Setup tab. No `grab set`, no WM_DELETE_WINDOW handler (Plan 04 adds it).
- Built `vmd/gui/setup_tab.tcl` — the complete Setup form in `::biochemeleon::setup_tab` (19 procs): 4 group builders (Target = 3-mode selector + stacked pages with menubutton+menu dropdowns; Hiders = plain spinbox + lock-scene + 10 per-rep rows; Difficulty = Easy/Hard radiobuttons; Actions = 4 buttons), `collect_state`/`apply_state` (with the `_loading` guard + catch-based error reset + `dict set ::biochemeleon::state setup` persistence), `switch_page` (frame-raise), `_dget` (dict-get-with-default), and 10 STUB callbacks (body = return; Plan 04 fills them).
- Modified `vmd/biochemeleon.tcl` to source `demos.tcl` + `gui/dialog.tcl`; removed the inline `open_dialog` block; kept the public procs (`biochemeleon`, `biochemeleon_tk_cb`) + menu registration (proc resolution is at call-time, so they call `::biochemeleon::open_dialog` now defined in dialog.tcl). The entry stays a thin bootstrap.
- Created `vmd/smoke/phase14_gui_smoke.tcl` — 11-check headless smoke (loading layer): entry sources cleanly, `biochemeleon` cmd exists, `open_dialog` proc exists, `setup_state`/`registry`/`demos`/`setup_tab` namespaces exist, `build`/`collect_state`/`apply_state`/`switch_page` procs exist, `validate_state` spot-check (Plan 01 intact). Uses the Phase 13 pattern (`[pwd]` path resolution, `BCHM_SMOKE_RESULT` marker, collect failures).
- All gates clean: modeless (no `grab set` in vmd/gui/), 8.6 features (no lmap/try/throw/finally/tailcall/coroutine/yield in vmd/gui/), ttk::spinbox absence (plain spinbox used), tk_version qualifier (no bare `info exists tk_version`). GUI smoke PASS=1; Phase 13 smoke still PASS=1 (no regression); Phase 14 mol smoke still PASS=1 (mol bridge intact after entry sources demos).

## Task Commits

Each task was committed atomically:

1. **Task 1: Create gui/dialog.tcl + gui/setup_tab.tcl + modify entry** - `86207c0` (feat)
2. **Task 2: Create headless GUI smoke + run verification** - `0d1efdd` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `vmd/gui/dialog.tcl` — extracted `open_dialog` (modeless toplevel + ttk::notebook Setup+Game); sources `setup_tab.tcl` at load time (top-level source for correct `[info script]`); calls `setup_tab::build`; keeps the Game tab placeholder "Game tab (Phase 16)".
- `vmd/gui/setup_tab.tcl` — full Setup form: 8 full-body procs (`build`, `build_target_group`, `build_hiders_group`, `build_diff_group`, `build_actions`, `collect_state`, `apply_state`, `switch_page`) + `_dget` helper + 10 stub callbacks (`refresh_mol_menu args`, `select_demo`, `select_loaded_mol`, `on_rep_toggled`, `update_cap`, `recompute_per_rep_maxes`, `do_reset`, `do_randomize`, `do_save`, `do_load`). Plain spinbox, menubutton+menu dropdowns, 3-radiobutton+frame-raise mode selector.
- `vmd/biochemeleon.tcl` — source block extended (`source demos.tcl` + `source gui/dialog.tcl`); inline `open_dialog` removed (extraction note added); public procs + menu registration intact.
- `vmd/smoke/phase14_gui_smoke.tcl` — 11-check headless smoke; `BCHM_SMOKE_RESULT` marker; does NOT call `biochemeleon`/`open_dialog` (loading layer only; widget rendering is Plan 04's human-verify).

## Decisions Made
- **Source setup_tab.tcl at dialog.tcl's top level (load time):** `[info script]` is dynamic (call-time context, not definition-time file). A `source setup_tab.tcl` INSIDE `open_dialog`'s proc body would resolve `[info script]` to the call-time context — empty when `open_dialog` is invoked from the console/menu (exactly the 14-02 `load_demo` bug). Sourcing at dialog.tcl's top level runs during dialog.tcl's own source, where `[info script]` = dialog.tcl's path, so `setup_tab.tcl` resolves correctly. The plan's "sourced once" + "load-time is safe" wording pointed here; this makes it robust.
- **`_dget` helper (not `dict get $state key $default`):** Probe-verified under VMD tcl 8.5.6 that `dict get $d key DEFAULT` has NO 3-arg default form — the 3rd arg is interpreted as a NESTED key path, erroring "missing value to go with key". The plan/research called for the 3-arg form; it does NOT exist. `_dget {state key default}` uses `dict exists`+`dict get` to achieve the same safety on half-populated dicts (the plan's intent). apply_state uses `_dget` for all 8 scalar keys + per_rep.
- **Callbacks are STUBS in this plan:** The form renders + state round-trips programmatically (collect_state/apply_state are full); the 10 callbacks (dropdown select, button actions, trace refresh, per-rep toggle) are `return`. This isolates "build the widget tree + state plumbing" (this plan) from "wire the callbacks" (Plan 04) — clean, focused tasks. Plan 04 also adds the WM_DELETE_WINDOW handler (collect_state + trace vdelete).
- **Trace registered in build (callback is a stub):** `trace variable vmd_molecule w ::biochemeleon::setup_tab::refresh_mol_menu` is registered in `build`; `refresh_mol_menu` is a stub (no-op) in this plan, so a mol add/delete after the dialog closes is safe (no error spam). Plan 04 makes it real + adds the matching `trace vdelete` in the WM_DELETE_WINDOW handler.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `dict get $state key $default` (3-arg) does NOT exist in tcl 8.5.6**
- **Found during:** Task 1 (before writing apply_state; confirmed via a probe under headless VMD tcl 8.5.6).
- **Issue:** The plan and the GUI research both specified `dict get $state key $default` (the "3-arg form, available in 8.5") for safe default-get on half-populated dicts. Probe-verified this is WRONG: tcl 8.5 `dict get dictionary ?key ...?` interprets the 3rd arg as a NESTED key path; `dict get $d a DEFAULT` errors "missing value to go with key". Using it would make apply_state error on every call.
- **Fix:** Added a private `_dget {state key default}` helper using `dict exists $state $key` + `dict get $state $key` (the tcl-8.5-correct default-get). apply_state uses `_dget` for all 8 scalar keys + per_rep. Same safety intent, no error.
- **Files modified:** `vmd/gui/setup_tab.tcl` (added `_dget`; apply_state uses it).
- **Verification:** syntax_probe + entry_probe + GUI smoke all PASS=1; `_dget` is defined (syntax probe check).
- **Committed in:** `86207c0` (part of the Task 1 commit)

**2. [Rule 3 - Blocking] `tclsh` not available in WSL — syntax check adapted to headless VMD**
- **Found during:** Task 1 verify (plan's verify step 5 specified `tclsh -c '...'`; `which tclsh` → not found; 14-01/14-02 documented the same constraint).
- **Issue:** The plan's quick syntax check requires `tclsh`, which is not installed in WSL (AGENTS.md forbids apt).
- **Fix:** Wrote `syntax_probe.tcl` (sourced under headless VMD's tcl 8.5.6) that sources setup_state + registry + demos + dialog and asserts all 19 setup_tab procs + open_dialog are defined. Sourcing only DEFINES procs (no mol/tk calls at source time), so this is a pure syntax/definition check. Also wrote `entry_probe.tcl` to verify the FULL entry chain sources cleanly. Results: `BCHM_SYNTAX_RESULT PASS=1` + `BCHM_ENTRY_RESULT PASS=1`.
- **Files modified:** none (probes live in gitignored `tmp/`)
- **Verification:** both probes PASS=1 (all procs defined, no syntax error).
- **Committed in:** N/A (workflow adaptation)

**3. [Rule 3 - Blocking] `rm` denied by opencode.json — staging adapted (same as 14-01/14-02)**
- **Found during:** Task 2 verify (plan's staging used `rm -rf tmp/biochemeleon-vmd`; `rm` is denied by opencode.json).
- **Issue:** The plan's staging command uses `rm -rf` to clean the staging dir, but `rm` is denied.
- **Fix:** Reused the 14-01/14-02 pattern: fresh staging dir `tmp/bchm143-stage` with `mkdir -p && cp -r vmd tmp/bchm143-stage/` (cp creates the vmd tree; overwrites on repeat). `tmp/` is gitignored so leftover dirs are harmless.
- **Files modified:** none (workflow-only)
- **Verification:** GUI smoke + Phase 13 + Phase 14 mol smoke all ran successfully via this staging.
- **Committed in:** N/A (workflow adaptation)

**4. [Rule 1 - Quality] Grep gates matched comments mentioning the forbidden terms**
- **Found during:** Task 1 verify (the modeless/8.6/ttk::spinbox gates returned matches in COMMENTS that explained the constraints, e.g. "NO `grab set`", "NO lmap/try/finally", "NOT ttk::spinbox").
- **Issue:** The plan's gates expect ZERO matches from `grep -rnE '...' vmd/gui/`. Informative comments that literally mentioned the forbidden terms (to explain why they're avoided) tripped the gates — false positives that would fail the plan's verify.
- **Fix:** Reworded the comments to convey the constraints WITHOUT the literal forbidden terms (e.g. "NO modal grab" instead of "NO `grab set`"; "uses foreach+lappend + catch (no 8.6 control-flow idioms)" instead of "NO lmap/try/finally"; "the ttk spinbox variant is ABSENT" instead of "NOT ttk::spinbox"; "re-raise" instead of "re-throw"; "the unqualified form" instead of "bare tk_version"). This matches 14-02's pattern (demos.tcl comments avoid the literal gated words). All 4 gates now return zero.
- **Files modified:** `vmd/gui/dialog.tcl`, `vmd/gui/setup_tab.tcl` (comment wording only; no code change).
- **Verification:** all 4 gates PASS (zero matches).
- **Committed in:** `86207c0` (part of the Task 1 commit)

---

**Total deviations:** 4 auto-fixed (1 Rule 1 bug + 1 Rule 1 quality + 2 Rule 3 blocking environment constraints)
**Impact on plan:** The `_dget` fix (#1) was necessary — the plan's specified API would have errored on every apply_state call. The comment rewording (#4) makes the plan's own gates pass cleanly. The 2 Rule 3 adaptations are environment-driven (same as 14-01/14-02) and don't affect any deliverable. All plan objectives met exactly as specified.

## Issues Encountered
- The `dict get` 3-arg myth (deviation #1) was the most consequential: both the plan AND the research (line 324) explicitly claimed `dict get $state key $default` is "available in 8.5". A 30-second probe under headless VMD (the only tcl 8.5.6 available) disproved it definitively ("missing value to go with key"). Lesson reinforced: when a plan specifies a tcl API "form", verify it under the actual runtime (VMD tcl 8.5.6) before using it — the 14-02 `[info script]` lesson generalizes to "don't trust research API claims unprobed".
- Pre-verified the `variable arr` (no value) array-creation behavior with a probe BEFORE writing setup_tab.tcl: confirmed `variable foo` (no value) leaves `foo` undefined (exists=0) and `set foo(bar) 1` creates it as an array (the research skeleton's pattern is correct). This de-risked the per-rep rows before writing the code.

## User Setup Required
None — no external service configuration required. The GUI uses only VMD 1.9.3's bundled Tcl/Tk 8.5.6 + ttk (already installed). The headless smoke runs under the existing VMD install. Widget rendering (the form actually drawing) is a Plan 04 human-verify checkpoint (Tk doesn't load in `-dispdev text`).

## Next Phase Readiness
- **Ready for 14-04 (wire callbacks):** All 10 stub callbacks are in place (body = return); Plan 04 replaces each with a full impl: `refresh_mol_menu` (trace callback -> re-populate menu from `[molinfo list]`), `select_demo`/`select_loaded_mol` (dropdown -> set target + update_cap), `on_rep_toggled` (enable/disable per-rep spinbox + recompute_per_rep_maxes), `recompute_per_rep_maxes`/`update_cap` (hider_count cap via demos::atom_count + hider_count_cap), `do_reset` (apply_state DEFAULTS), `do_randomize` (apply_state [randomize_state ...]), `do_save`/`do_load` (tk_getSaveFile/tk_getOpenFile + demos::save_setup/load_setup with `.bcm` extension). Plan 04 also adds the WM_DELETE_WINDOW handler (`collect_state` + `trace vdelete vmd_molecule w ...` + `destroy`) and the GUI human-verify checkpoint (the form renders + state round-trips via user interaction).
- **Ready for Phase 16 (Start flow):** `collect_state` is the bridge from the Setup form to the game engine; `apply_state` (init from `::biochemeleon::state setup`) survives dialog destroy/recreate.
- **No blockers.** The GUI structure + state plumbing is verified at the loading layer; widget rendering is the only remaining GUI unknown (Plan 04 human-verify).
- **Note for downstream:** `_dget` is the tcl-8.5-correct dict-get-with-default — reuse it (don't reach for the nonexistent 3-arg `dict get`). The top-level-sibling-source pattern (dialog.tcl -> setup_tab.tcl) is the template for Phase 16's game_tab.tcl (dialog.tcl will source it the same way).

---
*Phase: 14-setup-tab-bundled-demos*
*Completed: 2026-08-29*
