---
phase: 14-setup-tab-bundled-demos
plan: 02
subsystem: mol-bridge
tags: [tcl, vmd, mol, molinfo, demos, save-load, headless-smoke, path-resolution]

# Dependency graph
requires:
  - phase: 14-setup-tab-bundled-demos (plan 01)
    provides: validate_state (full deterministic clamp) + randomize_state + GAME_REPS/DEMO_MANIFEST/SETUP_FORMAT/DEFAULTS constants + hider_count_cap; the canonicalizer load_setup calls for defense-in-depth
provides:
  - "vmd/lib/demos.tcl — mol bridge namespace ::biochemeleon::demos with 8 procs (to_vmd_path, list_loaded_molecules, load_demo, get_active_reps, fetch_pdb stub, save_setup, load_setup, atom_count)"
  - "load_demo: script-relative bundled-demo loading via mol new (source-time-frozen script_dir)"
  - "get_active_reps: combined-braces molinfo form (survives mol delrep renumbering)"
  - "save_setup/load_setup: key-value line format + DEFAULTS-key-order rebuild (order-stable eq round-trip)"
  - "fetch_pdb: clean Phase-14 stub (VMD 1.9.3 lacks tls for HTTPS; Phase 21 implements real fetch)"
  - "atom_count: molinfo numatoms helper (0 on error) for the GUI cap computation"
  - "vmd/smoke/phase14_mol_smoke.tcl — 7-check headless smoke (BCHM_SMOKE_RESULT marker)"
affects:
  - "14-03/14-04 (GUI setup_tab sources demos.tcl for load_demo/get_active_reps/save+load_setup/list_loaded_molecules/atom_count)"
  - "Phase 15 (backup.tcl reuses the combined-braces molinfo rep-query pattern for rep save/restore)"
  - "Phase 16 (Start flow calls load_demo + atom_count for the cap; get_active_reps for lock-scene)"
  - "Phase 21 (real fetch_pdb replaces the stub; large demos)"

# Tech tracking
tech-stack:
  added: []  # stdlib tcl + VMD mol/molinfo; no new libraries
  patterns:
    - "script_dir capture at source time: [info script] is DYNAMIC (call-time context, not definition-time file), so proc bodies cannot use it; capture [file dirname [info script]] into a namespace variable inside `namespace eval` (runs during source) and reference the frozen variable in proc bodies. Standard tcl 'where am I defined' pattern (cf. the entry's top-level _dir)."
    - "Combined-braces molinfo rep query: molinfo $mol get \"{rep $i} {selection $i} {color $i} {material $i}\" + foreach {style sel col mat} ... { break } (single-field form FAILS -- Pitfall 3)"
    - "Key-value save/load format + DEFAULTS-key-order rebuild on load for order-stable `eq` round-trip (Pitfall 5); load_setup calls validate_state for defense-in-depth canonicalization"
    - "`eq` operator (NOT `dict eq` subcommand) for dict comparison -- research 'dict eq' is shorthand for expr {$a eq $b}; `dict eq` is not a tcl 8.5 subcommand"

key-files:
  created:
    - "vmd/lib/demos.tcl — mol bridge (8 procs in ::biochemeleon::demos); sources setup_state.tcl for constants"
    - "vmd/smoke/phase14_mol_smoke.tcl — 7-check headless smoke (BCHM_SMOKE_RESULT marker)"
  modified: []

key-decisions:
  - "load_demo captures script_dir at source time (namespace variable) instead of calling [info script] in the proc body -- [info script] is dynamic (call-time) and returns '' under `vmd -e` after source completes (Rule 1 fix; research Pattern 1 was subtly wrong for proc-body usage)"
  - "fetch_pdb is a clean stub returning -code error 'not implemented in Phase 14' (VMD 1.9.3 lacks tls for HTTPS; RCSB is https-only) -- Phase 21 implements the real fetch (research Open Question 2 resolved per recommendation (a))"
  - "save/load uses the key-value line format + DEFAULTS-key-order rebuild (LOCKED DECISION #1, NOT [list]+source) with the `eq` operator for round-trip verification"
  - "load_setup parses each line as key + REST-of-line (regex) so multi-token scalar values like selected_object '1k8p.pdb (0)' round-trip correctly (research skeleton used lindex $parts 1 which dropped everything after the first space)"

patterns-established:
  - "script_dir capture: namespace variable script_dir = [file dirname [info script]] set inside `namespace eval` (source time); proc bodies reference the frozen variable. REQUIRED for any proc that needs its defining file's location (load_demo now; Phase 15 backup/restore will need it too)."
  - "Combined-braces molinfo form is the load-bearing rep-query primitive (get_active_reps now; Phase 15 backup/restore reuse)"
  - "Headless mol smoke pattern: source demos.tcl via [pwd] (not [info script], empty under -e); collect failures in a list; BCHM_SMOKE_RESULT marker; `eq` operator for dict comparison"

# Metrics
duration: 17min
completed: 2026-08-29
---

# Phase 14 Plan 02: Mol bridge demos.tcl Summary

**Mol bridge `demos.tcl` (8 procs: load_demo via source-time-frozen script_dir, get_active_reps via combined-braces molinfo, save/load_setup with DEFAULTS-order rebuild, fetch_pdb stub) sourcing the pure layer, plus a 7-check headless smoke verifying all 6 bundled demos load with correct atom counts, rep detection survives delrep renumbering, and save/load round-trips with `eq`=1.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-08-29T12:08:47Z
- **Completed:** 2026-08-29T12:25:20Z
- **Tasks:** 2 (Task 1: demos.tcl; Task 2: smoke + verification)
- **Files modified:** 2 created

## Accomplishments
- Created `vmd/lib/demos.tcl` — the mol bridge (`::biochemeleon::demos`) with all 8 procs: `to_vmd_path` (WSL→VMD path guard), `list_loaded_molecules` (dropdown display strings), `load_demo` (script-relative bundled-demo loading), `get_active_reps` (combined-braces molinfo form), `fetch_pdb` (Phase-14 stub), `save_setup`/`load_setup` (key-value format + DEFAULTS-order rebuild), `atom_count` (molinfo numatoms helper). Sources `setup_state.tcl` (Plan 01) for constants.
- Created `vmd/smoke/phase14_mol_smoke.tcl` — 7-check headless smoke following the Phase 13 pattern (`[pwd]` path resolution, `BCHM_SMOKE_RESULT` marker). All 7 check groups green under headless VMD.
- Verified all 6 bundled demos load via `mol new` with the exact probe-verified atom counts (1znf=424, 1xdn=2597, 5e54=2844, 1k8p=555, 2qbz=3408, 4wb3=3779).
- Verified `get_active_reps` returns `Lines` on a fresh mol, `Lines VDW` after `mol addrep`, and `VDW` after `mol delrep 0` (style detection survives renumbering — Pitfall 2).
- Verified `save_setup`/`load_setup` round-trips a `randomize_state 42 555` dict with `[expr {$loaded eq $original}]` = 1 (DEFAULTS-key-order rebuild — Pitfall 5).
- demos.tcl passes the 8.6-features gate (zero lmap/try/throw/finally/tailcall/coroutine/yield) and the tk-gate (zero tk/toplevel/ttk) — it is the mol bridge, no Tk.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create vmd/lib/demos.tcl (mol bridge — 8 procs)** - `b5c9d9f` (feat)
2. **(deviation fix) Correct load_demo path resolution (script_dir capture)** - `ce91f4b` (fix) — Rule 1 bug found during Task 2 verification
3. **Task 2: Create headless mol smoke + run verification** - `bbeb5e9` (test)

**Plan metadata:** (this commit)

## Files Created/Modified
- `vmd/lib/demos.tcl` — mol bridge: 8 procs in `::biochemeleon::demos`; sources `setup_state.tcl`; captures `script_dir` at source time for `load_demo`; `load_setup` uses key+rest line parse + DEFAULTS-order rebuild + `validate_state` canonicalization.
- `vmd/smoke/phase14_mol_smoke.tcl` — 7-check headless smoke (to_vmd_path, load_demo×6, list_loaded_molecules, get_active_reps renumbering, atom_count, fetch_pdb stub, save/load round-trip); `BCHM_SMOKE_RESULT` marker.

## Decisions Made
- **`script_dir` capture (not `[info script]` in proc body):** `[info script]` is DYNAMIC — it returns the call-time sourcing context, not the definition-time file. Using it inside `load_demo`'s proc body returned `""` under `vmd -e` (the smoke's invocation), so demos resolved to the wrong path. Fix: capture `[file dirname [info script]]` into namespace variable `script_dir` inside `namespace eval` (which runs during source, when `[info script]` = this file's path), and reference the frozen variable in `load_demo`. This is the standard tcl "where am I defined" pattern (the entry already uses it at top-level via `set _dir`). The research Pattern 1 claim that `[info script]` works in `source`'d helpers was subtly wrong: it works at TOP LEVEL during source, but NOT in proc bodies called after source completes.
- **`fetch_pdb` is a clean stub:** Returns `-code error "not implemented in Phase 14"` (research Open Question 2 resolved per recommendation (a)). VMD 1.9.3 has `http` but no `tls` → HTTPS (RCSB) impossible; the robust fetch is Phase 21. The GUI shows the option but catches the error.
- **`eq` operator (not `dict eq`):** tcl 8.5 has NO `dict eq` subcommand; the research's "dict eq" phrasing is shorthand for `expr {$a eq $b}` (string-rep comparison). The smoke uses `[expr {$loaded eq $original}]` for the round-trip check.
- **`load_setup` key+rest line parse:** The research skeleton used `lindex [split $line " "] 1` for scalar values, which silently dropped everything after the first space (e.g. `selected_object 1k8p.pdb (0)` → `1k8p.pdb`). Replaced with `regexp {^(\S+)\s+(.*)$} $line -> key val` so multi-token scalar values round-trip correctly. The randomized smoke state has `selected_object=""` so this latent bug wasn't exercised by the smoke, but it would corrupt GUI-saved states (Plan 03/04) — fixed proactively (Rule 1).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `load_demo` `[info script]` returned empty under `vmd -e`**
- **Found during:** Task 2 verify (headless smoke — all 6 load_demo checks failed with "demo file not found: .../tmp/data/demos/1znf.pdb")
- **Issue:** The plan/research specified `[file dirname [info script]]` inside `load_demo`'s proc body. But `[info script]` is DYNAMIC (call-time, not definition-time): it returns `""` once source completes under `vmd -e`, so demo PDBs resolved relative to the cwd (`tmp/data/demos/`) instead of demos.tcl's dir (`tmp/bchm14-stage/vmd/data/demos/`). Confirmed by a dedicated probe (`AFTER_SOURCE_procbody_info_script=<<>>`).
- **Fix:** Capture `[file dirname [info script]]` into namespace variable `script_dir` at source time (inside `namespace eval`, which runs during source); `load_demo` references the frozen `$script_dir`. The top-level `source setup_state.tcl` line was already correct (runs during source). Standard tcl pattern.
- **Files modified:** `vmd/lib/demos.tcl`
- **Verification:** Re-ran smoke → all 6 load_demo checks pass; probe confirmed the mechanism.
- **Committed in:** `ce91f4b`

**2. [Rule 1 - Bug] Smoke used `dict eq` (nonexistent tcl 8.5 subcommand) — round-trip check was a silent no-op**
- **Found during:** Task 2 verify (spotted `unknown or ambiguous subcommand "eq"` in the smoke output; the smoke had FALSELY reported PASS=1 because the error aborted check 7 without appending a failure)
- **Issue:** The plan's success criterion says "save/load round-trips with dict eq=1". I implemented this as `if {![dict eq $loaded $original]}`, but `dict eq` is NOT a tcl 8.5 subcommand (only append/create/exists/.../values/with). The research's "dict eq" is shorthand for the `eq` string-equality OPERATOR (`expr {$a eq $b}`), which compares dict string reps. The error made the round-trip check a no-op (false PASS).
- **Fix:** Changed to `set same [expr {$loaded eq $original}]; if {$same == 0} { fail }`. Re-ran smoke → `eq`=1 genuinely verified (no error, no DEBUG output, tmp file cleanup ran = post-eq code path executed).
- **Files modified:** `vmd/smoke/phase14_mol_smoke.tcl`
- **Verification:** Smoke re-run: no `ambiguous` error, `BCHM_SMOKE_RESULT PASS=1 FAIL=none`, no DEBUG lines.
- **Committed in:** `bbeb5e9`

**3. [Rule 1 - Bug] `load_setup` dropped multi-token scalar values (latent)**
- **Found during:** Task 1 (proactive, while transcribing the research skeleton)
- **Issue:** The research `load_setup` skeleton used `lindex [split $line " "] 1` for scalar values, dropping everything after the first space. A scalar like `selected_object 1k8p.pdb (0)` would load back as `1k8p.pdb` (losing `(0)`). Not exercised by the smoke (randomized state has `selected_object=""`), but would corrupt GUI-saved states.
- **Fix:** Parse each line as key + REST-of-line via `regexp {^(\S+)\s+(.*)$} $line -> key val`; scalar values preserve embedded spaces. `per_rep_entry`/`pdb_pool_entry` keep their own token splits.
- **Files modified:** `vmd/lib/demos.tcl`
- **Verification:** Smoke round-trip eq=1 (selected_object="" round-trips via the empty-value else-branch); the multi-token path is correct by construction.
- **Committed in:** `b5c9d9f` (part of the initial Task 1 commit)

**4. [Rule 3 - Blocking] `tclsh` not available in WSL — syntax check adapted to headless VMD**
- **Found during:** Task 1 verify (plan's verify step 2 specified `tclsh -c '...'`; `which tclsh` → not found; 14-01 documented the same constraint)
- **Issue:** The plan's syntax check requires `tclsh`, which is not installed in WSL (AGENTS.md forbids apt; 14-01 confirmed).
- **Fix:** Wrote a `syntax_probe.tcl` that sources `setup_state.tcl` + `demos.tcl` under headless VMD's tcl 8.5.6 and checks all 8 procs are defined. Sourcing demos.tcl only DEFINES procs (no mol calls execute at source time), so this is a pure syntax/definition check. Result: `OK` + `BCHM_SYNTAX_RESULT PASS=1 FAIL=none`.
- **Files modified:** none (probe lives in gitignored `tmp/`)
- **Verification:** `BCHM_SYNTAX_RESULT PASS=1 FAIL=none` (all 8 procs defined, no syntax error).
- **Committed in:** N/A (workflow adaptation)

**5. [Rule 3 - Blocking] `rm` denied by opencode.json — staging adapted (same as 14-01)**
- **Found during:** Task 2 verify (plan's staging used `rm -rf tmp/biochemeleon-vmd`; `rm` is denied by opencode.json)
- **Issue:** The plan's staging command uses `rm -rf` to clean the staging dir, but `rm` is denied.
- **Fix:** Reused the 14-01 pattern: fixed staging dir `tmp/bchm14-stage` with `mkdir -p && cp -r vmd tmp/bchm14-stage/` (cp overwrites changed files). Same clean-staging result without `rm`. `tmp/` is gitignored.
- **Files modified:** none (workflow-only)
- **Verification:** Smoke ran successfully via this staging approach.
- **Committed in:** N/A (workflow adaptation)

---

**Total deviations:** 5 auto-fixed (3 Rule 1 bugs + 2 Rule 3 blocking environment constraints)
**Impact on plan:** The 3 Rule 1 fixes were necessary for correctness — #1 made load_demo work at all under the standard invocation, #2 made the round-trip verification real (not a false PASS), #3 prevented future GUI-state corruption. The 2 Rule 3 adaptations are environment-driven (same as 14-01) and don't affect any deliverable. All plan objectives met.

## Issues Encountered
- The `dict eq` false-PASS (deviation #2) was the subtlest issue: the smoke reported PASS=1 on the first run, but a careful read of the full output revealed the `unknown or ambiguous subcommand "eq"` error had silently aborted check 7. Lesson reinforced: always read the FULL smoke output, not just the marker line — VMD's `-e` mode catches top-level errors and continues, so an error mid-script does NOT prevent the marker from printing. The marker only reflects the `failures` list, which an aborted check never appends to.

## User Setup Required
None — no external service configuration required. The mol bridge uses only VMD 1.9.3's built-in `mol`/`molinfo` commands (already installed). The headless smoke runs under the existing VMD install.

## Next Phase Readiness
- **Ready for 14-03/14-04 (GUI setup_tab):** The GUI sources `demos.tcl` for every molecule operation — `load_demo` (DEMO-01), `list_loaded_molecules` (SETUP-01 dropdown), `get_active_reps` (SETUP-03 lock-scene), `save_setup`/`load_setup` (BTN-03/BTN-04), `atom_count` (hider_count_cap input), `fetch_pdb` (stub, GUI catches the error). The `script_dir` capture pattern means the GUI can `source demos.tcl` from anywhere and demo loading works.
- **Ready for Phase 15 (backup/restore):** The combined-braces molinfo rep-query form (`get_active_reps`) is the load-bearing primitive for rep save/restore; `backup.tcl` will reuse it. The `script_dir` pattern is available for any proc needing its defining file's location.
- **Ready for Phase 16 (Start flow):** `load_demo` + `atom_count` feed the cap computation; `get_active_reps` feeds lock-scene detection.
- **No blockers.** The mol-coupled layer for the Setup tab is verified.
- **Note for downstream:** `load_demo`'s `script_dir` is captured at source time — if a future phase moves/renames `demos.tcl`, the capture still works (it's relative to wherever the file is sourced from). The `fetch_pdb` stub MUST be replaced in Phase 21 (real fetch with network/tls handling).

---
*Phase: 14-setup-tab-bundled-demos*
*Completed: 2026-08-29*
