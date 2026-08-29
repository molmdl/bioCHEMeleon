---
phase: 13-bootstrap-sourced-entry
plan: 02
subsystem: ui
tags: [tcl, vmd, ttk, notebook, modeless-dialog, sourced-entry, headless-smoke, vmd_install_extension]

# Dependency graph
requires:
  - phase: 13-01 (pure-layer tcl + tcltest harness)
    provides: "vmd/lib/setup_state.tcl (::biochemeleon::setup_state) + vmd/lib/registry.tcl (::biochemeleon::registry) — the entry sources BOTH"
provides:
  - "v2 entry script vmd/biochemeleon.tcl: 8-step sourced form (re-source guard before namespace eval, package provide, sources pure layer, modeless ttk::notebook Setup+Game dialog, tk_version-guarded biochemeleon command, biochemeleon_tk_cb, vmd_install_extension under Visualization/bioCHEMeleon)"
  - "Headless smoke vmd/smoke/phase13_smoke.tcl: BCHM_SMOKE_RESULT marker pattern + [pwd]-based path resolution (Phase 14+ smokes follow the same pattern)"
  - "vmd/ tree established: gui/ (placeholder), data/demos/ (6 bundled PDBs + SOURCES.md), smoke/, pkgIndex.tcl (optional packaged form), wsl2win_cp.sh (staging)"
  - "Verified GUI contract: ttk::notebook renders in VMD 1.9.3 Tk; modeless dialog keeps viewer interactive (no grab); re-source guard works; menu path Visualization/bioCHEMeleon confirmed"
affects: [14, 15, 16, 17.1, 17.2, 18, 19, 20, 22]

# Tech tracking
tech-stack:
  added: []  # zero external deps — only tcl/Tk 8.5 + ttk bundled with VMD 1.9.3
  patterns:
    - "Sourced-form entry: re-source guard BEFORE namespace eval (top-of-file info exists check); package provide BEFORE vmd_install_extension (no-op package require); sources pure layer via [file dirname [info script]]"
    - "Modeless dialog: toplevel + ttk::notebook + singleton (winfo exists + wm deiconify); NO grab set on main dialog (viewer stays interactive)"
    - "tk_version global-qualifier rule: inside ANY proc, use `info exists ::tk_version` (NOT bare `tk_version` — tcl scoping trap, checks local scope only)"
    - "Headless smoke marker: BCHM_SMOKE_RESULT PASS=1 FAIL=none (VMD does NOT propagate tcl exit codes — gate on marker, NEVER $?)"
    - "[info script] empty under vmd -e: smoke uses [pwd] to locate + source the entry; entry's [info script] then works because it was source'd"

key-files:
  created:
    - vmd/biochemeleon.tcl
    - vmd/pkgIndex.tcl
    - vmd/wsl2win_cp.sh
    - vmd/smoke/phase13_smoke.tcl
    - vmd/gui/.gitkeep
    - vmd/data/demos/1znf.pdb
    - vmd/data/demos/1xdn.pdb
    - vmd/data/demos/5e54.pdb
    - vmd/data/demos/1k8p.pdb
    - vmd/data/demos/2qbz.pdb
    - vmd/data/demos/4wb3.pdb
    - vmd/data/demos/SOURCES.md
  modified: []

key-decisions:
  - "Entry structure = 8-step sourced form (re-source guard → namespace → package provide → source lib files → open_dialog → global biochemeleon proc → biochemeleon_tk_cb → vmd_install_extension)"
  - "Menu path = Visualization/bioCHEMeleon (NOT Extensions/bioCHEMeleon which double-nests; matches clonerep/viewmaster)"
  - "No auto-open on source — sourcing DEFINES command + registers menu; biochemeleon command (or menu click) OPENS dialog"
  - "Singleton dialog via winfo exists + wm deiconify; NO grab set on main dialog (ENTRY-01 hard constraint)"
  - "tk_version scoping: use `::tk_version` (global qualifier) inside procs; bare `tk_version` checks local scope only"

patterns-established:
  - "Entry 8-step structure: Phase 14+ adds setup_tab.tcl to gui/, sources it from the entry; open_dialog is inline in biochemeleon.tcl for Phase 13 (Phase 14 may extract to gui/dialog.tcl)"
  - "Headless smoke pattern: bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/*.tcl -eofexit < /dev/null' + BCHM_SMOKE_RESULT marker — Phase 14+ smokes follow the same pattern"
  - "[info script] caveat: -e'd scripts have empty [info script]; use [pwd] to locate files and source the entry (entry's [info script] then works because it was source'd)"
  - "Grep gate scope: pure layer = vmd/lib/ (zero mol/atomselect/tk); entry + gui are NOT pure and only pass the tcl 8.6-features gate (no lmap/try/throw/tailcall/coroutine/yield)"

# Metrics
duration: ~30 min code + GUI checkpoint (spanned 2026-08-28 to 2026-08-29)
completed: 2026-08-29
---

# Phase 13 Plan 02: Entry Script + Headless Smoke + GUI Checkpoint Summary

**v2 sourced-form entry (re-source guard, modeless ttk::notebook Setup+Game dialog, vmd_install_extension under Visualization/bioCHEMeleon) verified headless (BCHM_SMOKE_RESULT PASS=1) AND in a real VMD GUI session (checkpoint approved after tk_version scoping fix)**

## Performance

- **Duration:** ~30 min code + GUI checkpoint (spanned 2026-08-28 to 2026-08-29 across the checkpoint pause)
- **Started:** 2026-08-28T04:45:52Z
- **Completed:** 2026-08-29T08:20:42Z
- **Tasks:** 3 (2 auto + 1 checkpoint:human-verify approved)
- **Files modified:** 12 created

## Accomplishments
- Created the v2 entry script `vmd/biochemeleon.tcl` following the verified 8-step structure from 13-RESEARCH-entry.md (re-source guard before namespace eval → namespace + state → package provide → source BOTH pure-layer files → open_dialog with ttk::notebook Setup+Game → global biochemeleon proc → biochemeleon_tk_cb → vmd_install_extension under Visualization/bioCHEMeleon). NO grab set on the main dialog (ENTRY-01 hard constraint); singleton re-show via winfo exists + wm deiconify.
- Proved the headless path works end-to-end: `vmd/smoke/phase13_smoke.tcl` prints `BCHM_SMOKE_RESULT PASS=1 FAIL=none` under `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/phase13_smoke.tcl -eofexit < /dev/null'` — all 5 assertions passed (entry sources, biochemeleon cmd exists, headless call no-ops, both pure-layer namespaces loaded).
- Established the `vmd/` tree: `gui/` (placeholder .gitkeep), `data/demos/` (6 bundled PDBs + SOURCES.md copied verbatim from v1 — PDBs are viewer-agnostic), `smoke/`, `pkgIndex.tcl` (2-line optional packaged form), `wsl2win_cp.sh` (staging script).
- GUI checkpoint APPROVED in a real VMD 1.9.3 session: Extensions → Visualization → "bioCHEMeleon" menu item appears and opens the dialog; ttk::notebook renders with Setup+Game tabs that switch; 3D viewer stays interactive while the dialog is open (modeless, no grab); re-source guard prints a warning and prevents duplicate dialog + state reset. One bug found and fixed during the checkpoint (see Deviations).

## Task Commits

Each task was committed atomically:

1. **Task 1: Create entry script + pkgIndex + staging + bundled demos** - `963e201` (feat)
2. **Task 2: Create headless smoke + verify BCHM_SMOKE_RESULT PASS=1** - `8bca26b` (test)
3. **Task 3: GUI verify in real VMD session** - checkpoint:human-verify (APPROVED; no separate commit — the bug found during verification was fixed in `57bcc53`)

**Bug fix during checkpoint:** `57bcc53` (fix) — tk_version global-qualifier scoping trap in the `biochemeleon` proc.

**Plan metadata:** (this commit)

## Files Created/Modified
- `vmd/biochemeleon.tcl` - Entry script: 8-step sourced form. Re-source guard (top-of-file, before namespace eval), `namespace eval ::biochemeleon` (version/loaded/w/state), `package provide biochemeleon 2.0`, sources lib/setup_state.tcl + lib/registry.tcl via `[file dirname [info script]]`, `open_dialog` proc (toplevel + ttk::notebook Setup+Game, singleton winfo+wm deiconify, NO grab), global `biochemeleon` proc (tk_version-guarded, `::tk_version` global qualifier), `biochemeleon_tk_cb` (returns $w), `vmd_install_extension` under "Visualization/bioCHEMeleon" inside `if {[info exists tk_version]}`.
- `vmd/pkgIndex.tcl` - 2-line optional packaged-install form (`package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]`). No cost; keeps the door open.
- `vmd/wsl2win_cp.sh` - Staging script: copies vmd/ to tmp/biochemeleon-vmd/ for Windows-visible headless runs.
- `vmd/smoke/phase13_smoke.tcl` - Headless smoke: uses [pwd] to locate + source the entry (because [info script] is empty under vmd -e), asserts biochemeleon cmd exists + headless no-op + both pure-layer namespaces loaded, prints BCHM_SMOKE_RESULT marker.
- `vmd/gui/.gitkeep` - Placeholder dir (gui/*.tcl come in Phase 14/16).
- `vmd/data/demos/{1znf,1xdn,5e54,1k8p,2qbz,4wb3}.pdb` + `SOURCES.md` - 6 bundled demo PDBs + attribution copied verbatim from v1 (PDBs are viewer-agnostic).

## Decisions Made
- **Entry structure = 8-step sourced form** (adapted from 13-RESEARCH-entry.md lines 80-144, with the registry.tcl source line ADDED — the research skeleton only sourced setup_state.tcl). Followed all 10 LOCKED DECISIONS from the plan (namespace = ::biochemeleon::setup_state; menu path = Visualization/bioCHEMeleon; no auto-open; re-source guard before namespace eval; package provide before vmd_install_extension; singleton via winfo+wm deiconify; NO grab; GUI guard = info exists tk_version; headless smoke invocation; tcl 8.5 only).
- **Menu path = "Visualization/bioCHEMeleon"** (NOT "Extensions/bioCHEMeleon" which double-nests; matches clonerep/viewmaster reference plugins). Confirmed in the GUI checkpoint — item landed under Extensions → Visualization → bioCHEMeleon.
- **No auto-open on source** — sourcing DEFINES the command + registers the menu; the `biochemeleon` command (or menu click) OPENS the dialog. Confirmed: sourcing in the GUI session registered the menu without popping a window.
- **`::tk_version` global qualifier inside procs** — see Deviations (bug found during checkpoint). This is a tcl scoping rule that downstream GUI procs MUST follow.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed tk_version scoping trap in the biochemeleon proc**
- **Found during:** Task 3 (GUI checkpoint — checks 11-12 failed)
- **Issue:** The global `biochemeleon` proc used `if {![info exists tk_version]}` — but inside a proc, bare `info exists tk_version` checks LOCAL scope only, so the global `tk_version` (set by Tk when it loads) was invisible. In GUI mode, the console `biochemeleon` command always hit the headless no-op branch (printed "GUI requires Tk" warning even with Tk loaded) and did nothing. Checks 1-10, 13-17 passed (menu item + dialog via menu worked — `biochemeleon_tk_cb` doesn't have this bug, it doesn't check tk_version); only the console-command path (checks 11-12) failed.
- **Fix:** Changed `info exists tk_version` → `info exists ::tk_version` (global qualifier). Headless path unaffected (`::tk_version` is absent in `-dispdev text` → no-op still correct). The `biochemeleon_tk_cb` proc and the `vmd_install_extension` guard were already correct (the latter is at top-level scope where bare `tk_version` resolves to global; the former doesn't check tk_version).
- **Files modified:** vmd/biochemeleon.tcl
- **Verification:** Headless smoke re-verified `BCHM_SMOKE_RESULT PASS=1 FAIL=none` after the fix. User re-tested checks 11-12 in the GUI (re-sourcing with `set ::biochemeleon::loaded 0` to bypass the guard) and APPROVED.
- **Committed in:** `57bcc53` (separate fix commit, applied by the orchestrator during the checkpoint)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The bug was a tcl scoping trap not catchable headlessly (the headless path is correct either way — `::tk_version` absent → no-op). The GUI checkpoint did exactly its job: caught a GUI-only defect that the headless smoke couldn't. No scope creep. The `::tk_version` lesson is documented for downstream phases.

## Issues Encountered
- **Plan's Task 1 sanity-check command was wrong (Pitfall 3):** the plan's literal sanity command `vmd -dispdev text -e vmd/biochemeleon.tcl` `-e`s the entry directly, but `[info script]` is EMPTY under `vmd -e`, so `[file dirname [info script]]` resolves to `.` and `source ./lib/...` fails. The entry is ALWAYS sourced (by the smoke, by .vmdrc, by the user) — never -e'd directly. Resolved by writing a minimal source-probe (`tmp/biochemeleon-vmd/source_probe.tcl`) that SOURCEs the entry via `[pwd]` (exactly what the Task 2 smoke does), confirming `PROBE_PASS entry_sourced biochemeleon_cmd_exists`. The smoke (Task 2) uses the correct pattern. No code change needed — the entry was correct; only the plan's literal sanity command was wrong.

## User Setup Required

None - no external service configuration required. The headless VMD smoke uses the existing VMD 1.9.3 install (bashrc alias `vmd`); no new dependencies.

## Next Phase Readiness
- **Phase 13 COMPLETE (2/2 plans):** the stable shell is ready. ENTRY-01 (sourced tcl + biochemeleon command opens modeless ttk::notebook with Setup+Game; NO grab; viewer interactive), ENTRY-02 (Extensions menu item via vmd_install_extension under Visualization/bioCHEMeleon; re-source guard), ENTRY-03 (all v2 code under vmd/; zero external deps — only tcl/Tk 8.5 + ttk), TEST-01 (headless testing via vmd -dispdev text -e) all satisfied. ROADMAP Phase 13 success criteria 1, 2, 3 satisfied (criterion 4 was satisfied by 13-01).
- **Ready for Phase 14 (Setup Tab & Bundled Demos):** the `open_dialog` proc is inline in biochemeleon.tcl for Phase 13; Phase 14 may extract it to `gui/dialog.tcl` and adds `gui/setup_tab.tcl` (sourced from the entry). The entry's `source [file join $_dir lib ...]` pattern extends to `gui/` files. The bundled demos are already at `vmd/data/demos/` (ready for the Setup tab's demo dropdown).
- **Downstream tk_version lesson:** inside ANY proc that checks tk_version, use `::tk_version` (global qualifier); bare `tk_version` is invisible in proc scope. Phase 14+ GUI procs MUST follow this — the bug would have recurred in any new GUI-guarded proc.
- **Headless smoke pattern established:** Phase 14+ smokes follow `bash -ic 'cd tmp/biochemeleon-vmd && vmd -dispdev text -e vmd/smoke/*.tcl -eofexit < /dev/null'` + `BCHM_SMOKE_RESULT` marker + `[pwd]`-based path resolution (because `[info script]` is empty under `vmd -e`).
- **Grep gate scope:** pure layer = `vmd/lib/` (zero mol/atomselect/tk); entry + gui are NOT pure and don't pass the mol/atomselect/tk gate, only the tcl 8.6-features gate (no lmap/try/throw/tailcall/coroutine/yield). Re-run after adding any new pure-layer file.
- **AGENTS.md v2 rewrite is a POST-WORKFLOW task** (not a Phase 13 must-have). The current `vmd/AGENTS.md` is stale (uses `::BCM::`, `tclsh`, `"Extensions/bioCHEMeleon"` — all overridden by 13-01/13-02 locked decisions). Key patterns to document in the rewrite: the headless invocation (`bash -ic 'vmd -dispdev text -e ... -eofexit'`), the grep gate (no mol/atomselect/tk in vmd/lib/; no lmap/try), the `[info script]` empty-under-`-e` caveat, the `::tk_version` global-qualifier rule, the BCHM_SMOKE_RESULT/BCHM_TEST_RESULT marker convention, the staging pattern.
- **No blockers.** Phase 13 is complete; the GUI contract (ttk::notebook, modeless, menu path) is locked for all downstream GUI work.

---
*Phase: 13-bootstrap-sourced-entry*
*Completed: 2026-08-29*
