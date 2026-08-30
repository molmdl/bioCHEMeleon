---
phase: 15-mutation-safety-hider-registry
plan: 03
plan_name: backup.tcl viewpoint + rep save/restore on a NEW molid
subsystem: vmd-mol-bridge
tags: [vmd, tcl, molinfo, viewpoint, viewmaster, reps, clonerep, backup, mutation-safety]
requires:
  - "Phase 13 (pure layer + headless-smoke conventions)"
  - "Phase 14 (mol new / molinfo proven on bundled demos)"
provides:
  - "vmd/lib/backup.tcl — ::biochemeleon::backup namespace (snapshot/apply/restore); STANDALONE mol bridge"
  - "restore {snapshot molid_to_delete} 2-arg contract: deletes the LIVE game_molid (PASSED by caller), NOT the dead snapshot.molid — the PDB-rebuild-flow integration guard for Plan 04 (game.tcl) / Plan 05 (capstone)"
  - "apply {snapshot molid} state-only half (no mol ops) for game.tcl's SC4 forward mutate-reload path"
affects:
  - "15-04 (game.tcl): calls backup::snapshot (start) + backup::apply (forward mutate) + backup::restore (cleanup)"
  - "15-05 (capstone): the dead-original sub-case in this smoke is the isolated regression guard for the Plan-03/04 integration blocker the checker flagged"
tech-stack:
  added: []   # no new deps — STANDALONE, VMD 1.9.3 built-ins only (mol/molinfo/dict)
  patterns:
    - "viewmaster 4-matrix combined molinfo get/set {rotate_matrix center_matrix scale_matrix global_matrix} (positional — get/set MUST match field order)"
    - "clonerep clear-then-addrep form B (captured count + always mol delrep 0; mol addrep then mol modstyle/modselect/modcolor/modmaterial — isolated, no global-default mutation)"
    - "combined-braces molinfo rep form: molinfo $m get \"{rep $i} {selection $i} {color $i} {material $i}\" (single-field form FAILS — demos.tcl Pitfall 3)"
    - "recursive-flatten viewpoint compare (_vp_maxdiff) — viewpoint is a NESTED 4-element list of 4x4 matrices, NOT a flat 64-list"
    - "BCHM_SMOKE_RESULT marker (VMD does NOT propagate tcl exit codes) + [pwd]-based sourcing under vmd -e"
key-files:
  created:
    - vmd/lib/backup.tcl
    - vmd/smoke/phase15_backup_smoke.tcl
  modified: []
---

# Phase 15 Plan 03: backup.tcl Viewpoint + Rep Save/Restore Summary

**One-liner:** STANDALONE mol bridge with `snapshot` (viewpoint+reps+PDB-path dict), `apply` (state-only re-apply to an existing molid), and 2-arg `restore` (deletes the LIVE passed game_molid, NOT the dead snapshot.molid — the PDB-rebuild-flow contract), proving an exact viewmaster + clonerep round-trip on a NEW molid under headless VMD.

## What Was Built

`vmd/lib/backup.tcl` — the mol bridge that snapshots viewpoint + rep list (and the original PDB path) before mutation and restores them on a NEW molid after `mol delete` + `mol new`. Three exported procs, all probe-verified against `vmd-ref/` (viewmaster.tcl, clonerep.tcl, save_state.tcl):

- **`snapshot {molid} -> dict {molid filename viewpoint reps}`** — saves ALL reps (not just GAME_REPS, per SC2 "same reps") via the combined-braces `molinfo $m get "{rep $i} {selection $i} {color $i} {material $i}"` form (the same form `demos.tcl:94` uses; single-field form fails — Pitfall 3); viewpoint via the viewmaster 4-matrix combined get `{rotate_matrix center_matrix scale_matrix global_matrix}` (positional); filename via `molinfo $m get filename` (exact load path, already `C:/` for bundled demos — no `to_vmd_path` needed). A bad molid lets `molinfo` error naturally so the caller (game.tcl) can abort.
- **`apply {snapshot molid} -> {}`** — the state-only half: clear ALL reps (clonerep captured-count + always `mol delrep 0` — NOT save_state's buggy ascending-`delrep $i`; Pitfall 4) then re-apply each saved rep via FORM B (`mol addrep` then `mol modstyle/modselect/modcolor/modmaterial` — isolated, no global-default mutation; Pitfall 5) then restore the viewpoint positionally (SAME field order as the get). NO `mol delete`/`mol new` — game.tcl calls this on the game_molid after `mutation::mutate` to satisfy SC4's forward mutate-reload path.
- **`restore {snapshot molid_to_delete} -> new_molid`** — the FULL cleanup cycle: `mol delete $molid_to_delete` (the LIVE game_molid PASSED by the caller `game::cleanup`, NOT `[dict get $snapshot molid]` which is the ORIGINAL molid already deleted by `mutation::mutate` during `start_game` and is DEAD by cleanup time) + `set new_molid [mol new [dict get $snapshot filename] type pdb]` + `apply $snapshot $new_molid` + `return $new_molid`. Composes through `apply` (DRY — the research inlined the same logic). The 2-arg signature is REQUIRED: the old 1-arg `restore` that deleted `snapshot.molid` would either error on "no such molecule" or silently no-op and LEAK the 560-atom game molecule — the Plan-03/04 integration blocker the checker flagged.

`vmd/smoke/phase15_backup_smoke.tcl` — the headless smoke proving the round-trip (SC2 + SC4) + the PDB-rebuild contract. STANDALONE (local `_to_vmd` helper — does NOT source demos.tcl; would reverse dependency). Three cases:
- **CASE 1 (live-original):** load 1xdn (2597 atoms), 3 reps (default Lines + VDW on `name CA` + Cartoon on `protein` with Structure color + Transparent material), mutate viewpoint (`rotate x by 30; rotate y by 45; scale to 0.8; translate by 0.5 0.5 0.5`); snapshot; `restore $snap $m -> new_m`. Asserts new_m > m (monotonic), atoms 2597==2597, numreps 3==3, each rep matches saved, viewpoint `_vp_maxdiff < 1e-4`, and the PASSED molid `$m` is deleted (`catch {molinfo $m get numatoms}` nonzero — locks the contract).
- **CASE 2 (dead-original regression guard):** load 2nd 1xdn -> m2 (same setup); `snapshot $m2 -> snap2`; manually `mol delete $m2` (simulates `mutation::mutate` deleting the original -> `snap2.molid` is DEAD); load live m3; `restore $snap2 $m3 -> new_m2`. Asserts round-trip on new_m2 vs snap2; m3 (the PASSED `molid_to_delete`) is GONE; m2 (dead `snapshot.molid`) stays DEAD (restore did NOT error re-deleting it and did NOT resurrect it). This sub-case would have CAUGHT the Plan-03/04 integration blocker (1-arg restore deleting `snapshot.molid`) in isolation.
- **CASE 3:** `snapshot 999` errors (caller can abort the game).

## Verification Results

| Gate | Result |
| --- | --- |
| Task 1 load-gate (headless VMD) | `OK:snapshot OK:apply OK:restore` + `BCHM_SMOKE_RESULT PASS=1` |
| 8.6 gate (`\b(lmap\|try\|throw\|finally\|tailcall\|coroutine\|yield)\b` in backup.tcl) | ZERO matches |
| No-atomselect gate (`\batomselect\b` in backup.tcl) | ZERO matches |
| Task 2 smoke (headless VMD, 1xdn.pdb, 3 reps) | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` |
| Smoke `ERROR)` line scan | ZERO matches (cosmetic "Unusual bond" warnings only — VMD structure analysis of 1xdn, harmless) |
| Smoke tcl-error string scan | ZERO matches ("no such molecule" / "can't use" / "invalid" / etc. — none) |

Probe-verified expectations confirmed: viewpoint maxdiff 0.0 (< 1e-4 — exact viewmaster round-trip on a NEW molid); new molid monotonic-higher; atoms 2597==2597; numreps 3==3 with each rep `{style,sel,color,material}` matching saved; the PASSED molid is deleted; the dead-original sub-case passes (restore deletes the LIVE m3, leaves dead m2 dead).

## Decisions Made

1. **`backup::restore` owns the FULL restore cycle** (mol delete + mol new + apply + return new_molid), not just state re-apply. Keeps VMD-reload knowledge in ONE mol bridge; game.tcl stays a thin orchestrator (snapshot/apply/restore calls). Research Open Question 1 — primary recommendation chosen over the alternative split (`mutation::cleanup` owns delete+new, backup exposes `restore_reps`/`restore_viewpoint`).
2. **`restore` is 2-arg `(snapshot, molid_to_delete)`** — deletes the LIVE game_molid PASSED by the caller, NOT the dead `snapshot.molid`. This is the PDB-rebuild-flow contract: `mutation::mutate` deletes the original during `start_game`, so `snapshot.molid` is dead by cleanup. The old 1-arg form was the Plan-03/04 integration blocker the checker flagged; the smoke's dead-original sub-case regression-guards it in isolation. [From the plan's CRITICAL DESIGN POINT — not a deviation.]
3. **`apply` factored out as the state-only half** and `restore` composes through it (DRY). game.tcl uses `apply` for SC4's forward mutate-reload (no mol ops on the game_molid) and `restore` for cleanup. Both share one clear/addrep/viewpoint code path.
4. **Save only 4 rep fields** `{style, selection, color, material}` — sufficient for Setup-tab-created reps with default params (research PROBE4: 0 mismatches). Style PARAMETERS (line thickness, sphere scale) are NOT in `{rep $i}` anyway (Pitfall 7). Documented limitation: a hand-tuned rep's style params are not restored (acceptable — Setup tab uses defaults). Research Open Question 2.
5. **Single-string filename handling only** (research Open Question 3) — `molinfo $m get filename` returns a single string for single-PDB bundled demos; multi-file molecules are out of scope for Phase 15 (would need `[lindex $filename 0]` + `mol addfile`).
6. **FORM B rep re-apply** (`mol addrep` then `mol mod*`) over FORM A (`mol representation/color/...` then `mol addrep`) — isolated, no global-default mutation (Pitfall 5). Form A is verified-correct but mutates the global "current default" rep/color/selection/material, risking a later bare `mol addrep` silently inheriting the last rep's values.
7. **Use 1xdn.pdb (protein, 2597 atoms)** for the smoke, not 1k8p (nucleic) — Cartoon + Structure render cleanly without Stride warnings (Pitfall 8).

## Deviations from Plan

None — plan executed exactly as written. The CRITICAL DESIGN POINT (2-arg `restore` deleting the PASSED `molid_to_delete`, not `snapshot.molid`) was already baked into the plan by the prior `fix(15)` checker revision (commit `03edeed`); the dead-original sub-case in the smoke was specified by the plan and passes.

### Notes on plan fidelity

- **Comment rewording (not a deviation):** the initial backup.tcl header comment listed the bare forbidden 8.6 keywords (`lmap`/`try`/...) and the bare word `atomselect` in prose, which tripped the 8.6-gate and no-atomselect-gate grep (the gates are zero-match, and demos.tcl passes by not enumerating them). Reworded the comments to "no 8.6 control-flow idioms" and "no atom-field snapshot" — no logic change, gates now clean. (Committed in the Task 1 `feat` commit before the load-gate run.)

## Authentication Gates

None — VMD 1.9.3 runs locally via the WSL alias; no external auth required.

## Next Phase Readiness

- **Unblocks:** Plan 15-04 (game.tcl composition root) — `game::cleanup` calls `backup::restore $snap $game_molid` (passing the LIVE `game_molid` from `game_state` as the 2nd arg). Plan 15-05 (capstone) — the full backup→mutate→reconstruct→cleanup→restore pipeline.
- **Coordination with 15-02 (mutation.tcl):** `mutation::mutate` MUST delete the original molid during `start_game` (so `snapshot.molid` is dead by cleanup) AND return the new game_molid so `game.tcl` can pass it to `backup::restore`. This contract is asserted by the dead-original sub-case in this smoke.
- **No blockers / concerns.** backup.tcl is STANDALONE (sources nothing) so it does NOT depend on 15-01/15-02 being merged first — verified by running the smoke in this worktree where 15-01/15-02 are absent.

## Metrics

- **Duration:** ~5h wall-clock (active execution ~10 min; the 2 headless-VMD gates each ~3 min; remainder inter-step idle). Start 2026-08-29T19:14:35Z, end 2026-08-30T00:21:32Z.
- **Completed:** 2026-08-30
- **Tasks:** 2/2 complete
- **Commits on `exec/15-03`:** `013204a` (feat), `441679f` (test) + this `docs` metadata commit.
