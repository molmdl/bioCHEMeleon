---
phase: 15-mutation-safety-hider-registry
plan: 02
subsystem: engine
tags: [vmd, tcl, pdb-rebuild, atomselect, sentinel, dependency-injection, headless-smoke]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: registry.tcl DI shape (foreach idx [{*}$fetch_hider_ids]) + is_hider + reconstruct_from_sentinels; entry source-time script_dir pattern
  - phase: 14-setup-tab-bundled-demos
    provides: demos::to_vmd_path (WSL->VMD path guard); [pwd]-based headless smoke conventions + BCHM_SMOKE_RESULT marker; the 14-04 `variable a b` = name-VALUE-PAIRS lesson
provides:
  - "vmd/lib/mutation.tcl ::biochemeleon::mutation namespace (mol bridge) with 5 exported procs (make_placeholder_hiders, write_combined_pdb, tag_sentinels, fetch_hider_indices, mutate) + _hider_record helper + HID_* sentinel constants + script_dir"
  - "The FORWARD mutate-reload mechanism (write combined PDB -> mol delete original -> mol new combined -> tag sentinels in-place) -- the highest-risk VMD-specific unknown, de-risked"
  - "fetch_hider_indices as the DI fn injected into registry::reconstruct_from_sentinels (canonical selector 'resname GAM and beta < 0')"
  - "vmd/smoke/phase15_mutation_smoke.tcl proving SC1 + SC3-DI + SC2-mechanism end-to-end under headless VMD"
affects: [15-03-backup-restore (backup::restore owns the restore-reload + reps + viewpoint; mutation owns forward only), 16-mvp-loop (game.tcl orchestrator calls mutate + injects fetch_hider_indices; Phase 16 swaps make_placeholder_hiders for real sphere placement -- signature + sentinel mechanism stay identical), 20-persistence (.bcm sidecar reconciles per-hider user/rep/status post-load -- user is lost on writepdb)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PDB-rebuild forward mutate-reload (writepdb-then-splice + mol delete original + mol new combined + in-place tag) -- VMD has no in-place atom insertion, so hiders + originals must become ONE molecule via a PDB round-trip"
    - "writepdb-then-splice (VMD's own writepdb handles every original field correctly; only the HIDER records are hand-written with strict 78-col format) -- avoids the atomselect-get-has-no-icode pitfall"
    - "In-place sentinel tagging via atomselect after mol new (rescues any PDB column misalignment; defense-in-depth) -- set beta/segid even though %6.1f lets segid GAME survive in the PDB"
    - "Canonical selector 'resname GAM and beta < 0' (NEVER 'beta < 0' alone -- over-matches negative-beta real atoms)"
    - "DI via tcl command-prefix + {expand}: fetch_hider_indices injected as [list ::biochemeleon::mutation::fetch_hider_indices $molid] into registry::reconstruct_from_sentinels (keeps registry.tcl pure -- no mol/atomselect)"
    - "mutate 2-arg signature (molid hider_records) -- temp PDB path computed internally ($env(TEMP) fallback [pwd]); caller never manages the temp file"

key-files:
  created:
    - vmd/lib/mutation.tcl
    - vmd/smoke/phase15_mutation_smoke.tcl
  modified: []

key-decisions:
  - "mutate 2-arg signature (molid hider_records) -- computes the temp PDB path internally ($env(TEMP)/biochemeleon_game.pdb, fallback [pwd]). The research proposed a 3-arg signature (caller passes out_path); the plan ADAPTED it to 2-arg so game.tcl never manages temp files. write_combined_pdb stays 3-arg (the smoke calls it directly to verify PDB content)."
  - "mutation.tcl owns the FORWARD mutate-reload ONLY -- NO cleanup/restore/reps/viewpoint proc (backup.tcl::restore owns the restore-reload; clean split, no backup->mutation coupling). This matches researchers B & C."
  - "Proc-prefix DI style (fetch_hider_indices lives in mutation.tcl, the mol bridge) over apply-lambda (researcher C). atomselect belongs in the mol bridge, not the orchestrator; fetch_hider_indices is reusable and directly smoke-testable. registry.tcl stays pure (the {*}$fetch_hider_ids expansion is DI-agnostic)."
  - "beta format %6.1f -> '-999.0' (6 cols, no overflow; segid GAME survives in PDB cols 73-76). %6.2f -> '-999.00' OVERFLOWS the 6-col beta field and corrupts segid. In-place tag_sentinels rescues any misalignment anyway (belt-and-suspenders)."
  - "make_placeholder_hiders returns {name x y z} records with deterministic jitter from molinfo center (nested-list-safe lassign [lindex [molinfo $m get center] 0]). Phase 16 swaps this for real sphere placement; the record shape + mutate signature stay identical."

patterns-established:
  - "PDB-rebuild forward mutate-reload: the v2 mechanism for getting hiders into the same molecule as originals (VMD has no in-place insert). mutation.tcl is the ONLY component that calls writepdb + does the forward mol delete/mol new."
  - "writepdb-then-splice: trust VMD's writepdb for originals (handles every field), hand-write only the hider ATOM records with strict 78-col format. Drop trailing END, append hiders, write END."
  - "In-place sentinel tagging after every mol new: atomselect 'resname GAM' -> set beta -999 + set segid GAME -> return index list. Always $sel delete. Robust against PDB column bugs."
  - "DI command-prefix for registry reconstruction: [list ::biochemeleon::mutation::fetch_hider_indices $molid] passed to registry::reconstruct_from_sentinels (the {expand} form)."

# Metrics
duration: 19min
completed: 2026-08-30
---

# Phase 15 Plan 02: Mutation PDB-rebuild Engine Summary

**Forward mutate-reload via writepdb-then-splice + in-place sentinel tagging: 5-proc mutation.tcl mol bridge that writes a combined PDB (originals + 5 hider ATOM records), mol-deletes the original, mol-news the combined file, and tags GAM/-999/GAME sentinels in-place -- proven end-to-end by headless smoke (560 atoms, 5 sentinels at indices 555-559, registry DI via injected fetch_hider_indices).**

## Performance

- **Duration:** 19 min
- **Started:** 2026-08-30T00:20:56Z
- **Completed:** 2026-08-30T00:40:37Z
- **Tasks:** 2
- **Files modified:** 2 (both new)

## Accomplishments
- Built `vmd/lib/mutation.tcl` -- the mol-bridge PDB-rebuild engine owning the FORWARD mutate-reload (the highest-risk VMD-specific unknown, already de-risked by probe). 5 exported procs + `_hider_record` helper + HID_* sentinel constants + script_dir captured at source time.
- Proved the PDB-rebuild mechanism end-to-end under headless VMD: 1k8p (555 atoms) + 5 placeholder hiders -> ONE molecule with 560 atoms; the canonical selector `resname GAM and beta < 0` picks exactly 5 at indices 555-559; segid GAME sticks in-place; original atom0 (N1) intact. This is SC1.
- Proved the registry DI (SC3 mechanism): `reconstruct_from_sentinels [list ::biochemeleon::mutation::fetch_hider_indices $m1]` -> `is_hider 555`/`is_hider 559` true, `is_hider 0` false. The pure registry reconstructs from sentinels via the injected command-prefix (no mol/atomselect in registry.tcl).
- Proved the cleanup mechanism (SC2): raw `mol delete` + `mol new` original -> 0 sentinels (backup.tcl::restore wraps this in Plan 03; this smoke tests mutation.tcl ALONE).
- Verified `write_combined_pdb` DIRECT call returns 555, the file has 560 atom records (428 ATOM + 127 HETATM originals + 5 hider ATOM), and the 5 hider lines carry GAM / -999.0 / GAME (the %6.1f beta format lets segid GAME survive in the PDB columns).

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement vmd/lib/mutation.tcl (5 procs + sentinel constants)** - `4e58e29` (feat)
2. **Task 2: Write + run phase15_mutation_smoke.tcl (SC1 + SC3-DI mechanism)** - `b64f5c0` (test)

**Plan metadata:** `docs(15-02): complete mutation PDB-rebuild plan` (this commit)

## Files Created/Modified
- `vmd/lib/mutation.tcl` - MOL BRIDGE: 5-proc PDB-rebuild engine (make_placeholder_hiders, write_combined_pdb, tag_sentinels, fetch_hider_indices, mutate) + _hider_record helper + HID_* constants. Owns the forward mutate-reload only (write combined PDB -> mol delete original -> mol new combined -> tag sentinels). No cleanup/restore/reps (backup.tcl's job).
- `vmd/smoke/phase15_mutation_smoke.tcl` - Headless smoke proving SC1 (560 atoms, 5 sentinels, indices 555-559, segid GAME, N1 intact) + SC3-DI (registry reconstruct via fetch_hider_indices, is_hider correct) + SC2-mechanism (raw mol delete + mol new -> 0 sentinels). BCHM_SMOKE_RESULT PASS=1 FAIL=none.

## Decisions Made
- **mutate 2-arg signature (molid hider_records):** The research proposed 3-arg (caller passes out_path). The plan ADAPTED to 2-arg so game.tcl never manages temp files -- mutate computes `$env(TEMP)/biochemeleon_game.pdb` (fallback [pwd]) internally. `write_combined_pdb` stays 3-arg so the smoke can verify PDB content directly. Fixed filename is fine for Phase 15 (single game; writepdb overwrites -- no `rm` needed, which is denied anyway).
- **No cleanup proc in mutation.tcl:** The restore-reload (mol delete game + mol new original + re-apply reps + restore viewpoint) is `backup.tcl::restore` (Plan 03). mutation.tcl owns the forward mutate-reload only. Clean split, no backup->mutation coupling. Matches researchers B & C.
- **Proc-prefix DI (not apply-lambda):** `fetch_hider_indices` lives in mutation.tcl (the mol bridge -- natural home for atomselect); game.tcl injects `[list ::biochemeleon::mutation::fetch_hider_indices $new_m]`. Keeps game.tcl a pure orchestrator; `fetch_hider_indices` is reusable and directly smoke-testable. (Researcher C proposed apply-lambda in game.tcl; both work with the existing `{*}$fetch_hider_ids` DI shape -- stylistic choice, reconciled per the research recommendation.)
- **%6.1f beta format:** `-999.0` is 6 chars (fits the 6-col beta field; segid GAME survives in PDB cols 73-76). `%6.2f` -> `-999.00` overflows by 1 and corrupts segid. In-place `tag_sentinels` sets segid regardless (defense-in-depth, rescues any column bug).
- **make_placeholder_hiders = pure data prep:** Returns `{name x y z}` records with deterministic jitter from `molinfo center` (nested-list-safe). Reads coords only; does NOT write or load. Phase 16 swaps this for real sphere placement; the record shape + mutate signature stay identical.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed tcl 8.5 `variable` name-VALUE-pairs scoping bug in research skeleton**
- **Found during:** Task 1 (implement mutation.tcl)
- **Issue:** The research skeleton (15-RESEARCH-pdb-rebuild.md lines 116, 145, 162) used `variable HID_RESNAME HID_BETA HID_SEGID` (and similar multi-arg forms) INSIDE procs. In tcl 8.5, `variable a b` = name-VALUE pairs (scalar `set a b`), NOT name links -- the 14-04 lesson (STATE.md): `variable HID_RESNAME HID_BETA HID_SEGID` would SET `HID_RESNAME` to the string "HID_BETA" (corrupting the "GAM" constant) and leave `HID_BETA` unlinked -> "no such variable" error on `$sel set beta $HID_BETA`. This would have made `tag_sentinels`/`_hider_record`/`fetch_hider_indices` error or select 0 atoms.
- **Fix:** Used the verified-correct one-per-line form (`variable HID_RESNAME` / `variable HID_BETA` / `variable HID_SEGID` on separate lines) to LINK the namespace constants into proc scope without overwriting. This is the pattern demos.tcl already uses (single-arg `variable`).
- **Files modified:** vmd/lib/mutation.tcl (all procs that reference HID_* constants)
- **Verification:** Load-gate smoke (all 5 procs OK under headless VMD) + phase15_mutation_smoke.tcl PASS=1 (tag_sentinels correctly selected 5 GAM atoms, set beta/segid, returned indices 555-559).
- **Committed in:** 4e58e29 (Task 1 commit)

**2. [Rule 1 - Bug] tag_sentinels user-set via single list-set (not per-atom loop)**
- **Found during:** Task 1 (implement mutation.tcl)
- **Issue:** The research skeleton set per-atom `user` via a `foreach` loop creating N atomselects (`set one [atomselect $molid "index $i"]; $one set user $u; $one delete`). This works but creates N extra atomselects (leak risk per Pitfall 3, and wasteful for 50 hiders).
- **Fix:** Replaced with a single `$sel set user $ords` where `$ords` is a list `{0 1 2 3 4}` built to match the selection's atom order. VMD atomselect `set` with a list of N values sets each atom to the corresponding value (standard VMD idiom, same probe-verified result `chk_user=0.0 1.0 2.0 3.0 4.0` from P6).
- **Files modified:** vmd/lib/mutation.tcl (tag_sentinels proc)
- **Verification:** phase15_mutation_smoke.tcl PASS=1 (tag_sentinels returned 5 indices; the registry DI + canonical selector both passed, confirming the sentinel fields are correct).
- **Committed in:** 4e58e29 (Task 1 commit)

**3. [Rule 1 - Bug] Comment reworded to avoid literal 8.6-gated terms**
- **Found during:** Task 1 (8.6 gate verification)
- **Issue:** The file header comment contained "no lmap/try" -- the 8.6 gate `grep -nE '\b(lmap|try|...)\b'` matched the comment (false positive). Per the 14-02/14-03 pattern (STATE.md: "comments reworded to avoid the literal gated terms"), the gate should be cleanly zero.
- **Fix:** Reworded to "Tcl 8.5 only (no 8.6 control constructs; ...)".
- **Files modified:** vmd/lib/mutation.tcl (header comment)
- **Verification:** 8.6 gate grep returns zero matches.
- **Committed in:** 4e58e29 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 - Bug)
**Impact on plan:** All three were necessary for correct operation (the `variable` bug would have broken tag_sentinels/_hider_record/fetch_hider_indices) or gate cleanliness. No scope creep; all within the plan's prescribed proc bodies. The probe-verified skeletons worked first run after the `variable` fix.

## Issues Encountered
None. The probe-verified PDB-rebuild mechanism (research 15-RESEARCH-pdb-rebuild.md, every API claim headless-verified) worked on the first smoke run after the `variable` scoping fix. The `%6.1f` beta format, the nested-list `molinfo center` unwrap, the in-place sentinel tagging, and the DI command-prefix all behaved exactly as the research predicted. VMD text-mode command-result echoes ("3", "atomselect6", "0" near the end) are normal and confirm m2=3 (monotonic molid), the 6th atomselect object, and `[$left num]`=0 leftover hiders -- not errors.

## User Setup Required
None - no external service configuration required. mutation.tcl uses only VMD 1.9.3 stdlib (mol/atomselect/molinfo/writepdb + tcl 8.5 stdlib). The smoke runs headless from WSL via the established `bash -ic 'cd <staging> && vmd -dispdev text -e <smoke> -eofexit < /dev/null'` pattern.

## Next Phase Readiness
- **mutation.tcl is complete and proven.** The forward mutate-reload mechanism (the highest-risk VMD-specific unknown) is de-risked before any generator builds on it.
- **Plan 03 (backup.tcl) can proceed:** backup::restore owns the restore-reload (mol delete game + mol new original + re-apply reps + restore viewpoint). The smoke proved the underlying mechanism (raw mol delete + mol new -> 0 sentinels, 555 atoms restored). backup.tcl wraps this + adds reps/viewpoint.
- **Plan 01 (registry count_hiders) is independent** -- this smoke deliberately did NOT call count_hiders (worktree isolation; registry.tcl in this branch has only Phase 13's is_hider/mark_found/reconstruct_from_sentinels). The orchestrator merges 15-01 + 15-02 + 15-03; after merge, the full registry is available.
- **Phase 16 (MVP loop / game.tcl) can call:** `set hiders [mutation::make_placeholder_hiders $m $count]; set new_m [mutation::mutate $m $hiders]; backup::restore_reps_viewpoint $new_m $snap; registry::reconstruct_from_sentinels [list mutation::fetch_hider_indices $new_m]`. Phase 16 swaps make_placeholder_hiders for real sphere placement; the mutate signature + sentinel mechanism stay identical.
- **Phase 20 (.bcm sidecar):** the per-hider `user` field is set in-place by tag_sentinels but LOST on writepdb (Pitfall 7) -- the .bcm reconciles user/rep/status post-load.
- **No blockers.** The clean split (mutation=forward, backup=restore, game=orchestrate) is validated by this smoke.

---
*Phase: 15-mutation-safety-hider-registry*
*Plan: 02*
*Completed: 2026-08-30*
