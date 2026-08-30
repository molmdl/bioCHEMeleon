---
phase: 15-mutation-safety-hider-registry
plan: 04
plan_name: game.tcl composition root (start/cleanup/restart)
subsystem: game-orchestrator
tags: [tcl, vmd, composition-root, dependency-injection, apply-lambda, game-state, orchestration, headless-smoke, sc4-forward]

# Dependency graph
requires:
  - phase: 13-bootstrap-sourced-entry
    provides: entry source-time [info script] pattern + re-source guard (the `info exists && $loaded` guard this plan bypasses for the load-gate); [pwd]-based headless smoke conventions + BCHM_SMOKE_RESULT marker
  - phase: 14-setup-tab-bundled-demos
    provides: demos::load_demo (bundled 1znf, 424 atoms) + to_vmd_path; phase14_mol_smoke.tcl regression target
  - phase: 15-mutation-safety-hider-registry (Plan 01)
    provides: registry::count_hiders + reset (the smoke asserts count_hiders == N after start / == 0 after cleanup); the bound-arg [list apply {lambda} <arg>] DI shape (pure-layer-verified)
  - phase: 15-mutation-safety-hider-registry (Plan 02)
    provides: mutation::make_placeholder_hiders {molid count} -> {name x y z} records + mutation::mutate {molid hider_records} -> new game molid (mol delete original + mol new combined + tag sentinels); 2-arg mutate signature
  - phase: 15-mutation-safety-hider-registry (Plan 03)
    provides: backup::snapshot {molid} -> dict + backup::apply {snapshot molid} (state-only, SC4 forward) + backup::restore {snapshot molid_to_delete} -> new_molid (2-arg; deletes the LIVE passed game_molid, NOT the dead snapshot.molid -- the PDB-rebuild-flow contract)
provides:
  - "vmd/lib/game.tcl -- ::biochemeleon::game namespace (composition root) with start_game, cleanup, restart; sources NOTHING; owns NO mol delete/mol new (delegates forward to mutation::mutate, restore to backup::restore)"
  - "start_game {molid hider_count} -> game_state dict {game_molid hider_count snapshot}; the EXACT non-negotiable ordering: snapshot -> make_placeholder_hiders -> mutate -> backup::apply on game_molid (SC4 forward) -> registry::reconstruct_from_sentinels via the [list apply {lambda} $game_molid] DI"
  - "cleanup {game_state} -> restored molid: backup::restore $snapshot $game_molid (passes LIVE game_molid, NOT dead snapshot.molid) + registry::reset"
  - "restart {game_state} -> new game_state: cleanup + start_game with the same hider_count"
  - "Entry sources backup+mutation+game in dep order after demos.tcl, before gui/dialog.tcl; registry sourced ONCE"
  - "vmd/smoke/phase15_game_smoke.tcl proving the orchestration (game_state shape + start/cleanup/restart round-trip + game_molid-deleted contract); BCHM_SMOKE_RESULT PASS=1"
affects:
  - "15-05 (capstone): the full backup -> mutate -> reconstruct -> cleanup -> restore pipeline with detailed SC1-SC4; game.tcl is the integration point this capstone exercises"
  - "16-mvp-loop (generators + PickBridge click loop): game.tcl is the orchestrator the click loop calls (mark_found on the registry); Phase 16 swaps make_placeholder_hiders for real sphere placement -- the start_game signature, game_state shape, and DI injection line stay identical"
  - "20-persistence (.bcm sidecar): game_state is the in-memory round state the sidecar serializes (registry, timer, found-status)"

# Tech tracking
tech-stack:
  added: []   # no new deps -- VMD 1.9.3 tcl 8.5 stdlib only (dict + apply + atomselect via the injected lambda)
  patterns:
    - "Composition root (GameController): the ONLY module that references all three of backup/mutation/registry; thin orchestrator like v1 game.py. Owns the game_state dict + the atomselect apply-lambda injection (the ONLY place atomselect touches the registry). Owns NO mol delete/mol new -- each reload delegated to exactly one mol-bridge module (mutation::mutate forward, backup::restore cleanup)."
    - "Apply-lambda DI as a COMMAND-PREFIX VALUE: [list apply {{molid} {...}} $game_molid] injected into registry::reconstruct_from_sentinels (the registry's [{*}$fetch_hider_ids] expands + invokes it). NEVER [apply {lambda} $game_molid] (evaluates immediately -> 'invalid command name <first-index>' -- the 13-01 DI bug, probe-verified)."
    - "game_state dict {game_molid hider_count snapshot}: the in-memory round state. game_molid IS stored (cleanup must mol delete it); the original molid is intentionally NOT stored (dead after mutate; recoverable only via snapshot.filename)."
    - "Delegate-each-reload-to-one-bridge: mutation::mutate owns the forward mutate-reload (mol delete original + mol new combined); backup::restore owns the restore-reload (mol delete game_molid + mol new original + apply reps/viewpoint). game.tcl owns neither -- clean split, no game->bridge coupling."
    - "Non-negotiable start_game ordering: snapshot MUST run before mutate (captures the LIVE original before mutate deletes it); backup::apply MUST run after mutate (on the NEW game_molid); reconstruct_from_sentinels MUST run after mutate (the lambda selects on the game_molid)."

key-files:
  created:
    - vmd/lib/game.tcl
    - vmd/smoke/phase15_game_smoke.tcl
  modified:
    - vmd/biochemeleon.tcl   # +3 source lines (backup, mutation, game) in dep order after demos.tcl; comment block updated

key-decisions:
  - "Apply-lambda DI (the plan's explicit choice) over the proc-prefix form 15-02 used in its own smoke. game.tcl injects [list apply {{molid} {atomselect...}} $game_molid] -- a self-contained command-prefix VALUE. Both forms work with the registry's [{*}$fetch_hider_ids] expansion; the plan chose apply-lambda so game.tcl is self-contained (no dependency on mutation::fetch_hider_indices existing) and the 15-01 pure suite's bound-arg case directly mirrors it. The lambda hardcodes 'resname GAM and beta < 0' (canonical selector) because apply-lambda scope doesn't link mutation's HID_RESNAME variable."
  - "cleanup passes game_molid (NOT snapshot.molid) to backup::restore -- the PDB-rebuild integration contract. mutation::mutate deletes the ORIGINAL during start_game, so snapshot.molid is DEAD by cleanup time. Passing the dead snapshot.molid would error 'no such molecule' or silently no-op and LEAK the 426-atom game molecule. The smoke's game_molid-deleted assertion (catch {molinfo $game_molid get numatoms} nonzero) guards this in isolation."
  - "game.tcl sources NOTHING. The entry sources backup+mutation+registry in dep order before game.tcl; re-sourcing registry here would WIPE _records (registry's namespace eval re-inits _records to empty). game.tcl references ::biochemeleon::registry::* at CALL time (tcl proc resolution is call-time, so source order only needs the namespace to exist before the first CALL, which is always after the entry finishes sourcing)."
  - "Entry source order: setup_state -> registry -> demos -> backup -> mutation -> game -> dialog. registry sourced ONCE; backup/mutation/game do NOT re-source it. (demos + mutation each re-source setup_state themselves -- harmless constant re-init, the existing demos.tcl pattern.)"
  - "start_game {molid hider_count} is Phase-16-ready: Phase 16 swaps the single make_placeholder_hiders line for real generator dispatch (sphere placement from setup_state), but the signature, game_state shape, and DI injection line stay identical. No setup-state params added in Phase 15."
  - "Smoke uses 1znf (424 atoms) + 2 hiders (not 1k8p/555/5 from the research skeleton) -- smaller + faster, and the plan's explicit choice. 424+2=426 atoms; 2 sentinels; count_hiders==2. The assertions scale identically to any demo/count."

patterns-established:
  - "Composition-root DI injection line (verbatim, copy-paste-safe): ::biochemeleon::registry::reconstruct_from_sentinels [list apply {{molid} { set sel [atomselect $molid \"resname GAM and beta < 0\"]; set ids [$sel get index]; $sel delete; return $ids }} $game_molid]. The [list apply] (VALUE) vs [apply] (evaluated) distinction is the single highest-risk integration detail; the comment in game.tcl documents it inline."
  - "game_state round lifecycle: start_game (snapshot+mutate+apply+reconstruct) -> cleanup (restore+reset) -> restart (cleanup+start_game). The registry is a namespace singleton with NO cross-reload persistence in Phase 15 (rebuild-from-sentinels each round); persistence/.bcm is a later phase."
  - "Load-gate guard bypass: set ::biochemeleon::loaded 0 (via namespace eval) before sourcing the entry headlessly so the re-source guard's `info exists && $loaded` is false -> the namespace eval + source lines run. Confirms the full entry (incl. all Phase-15 lib files + dialog.tcl) sources cleanly in -dispdev text mode."

# Metrics
duration: 14min
completed: 2026-08-30
---

# Phase 15 Plan 04: game.tcl Composition Root Summary

**Thin GameController composition root wiring backup+mutation+registry into a start/cleanup/restart lifecycle, injecting the atomselect apply-lambda as a `[list apply ...]` command-prefix VALUE into the pure registry -- proven by a headless 1znf round-trip smoke (game_state shape, SC4 forward reps restore on the game_molid, SC2 cleanup, the game_molid-DELETED contract, and a restart round-trip).**

## Performance

- **Duration:** ~14 min (827 sec)
- **Started:** 2026-08-30T00:47:55Z
- **Completed:** 2026-08-30T01:01:42Z
- **Tasks:** 2/2 complete
- **Files:** 2 created (vmd/lib/game.tcl, vmd/smoke/phase15_game_smoke.tcl) + 1 modified (vmd/biochemeleon.tcl)

## Accomplishments

- Built `vmd/lib/game.tcl` -- the Phase 15 composition root (GameController). 3 exported procs (`start_game`, `cleanup`, `restart`); the ONLY module that references all three of `backup`/`mutation`/`registry`. Owns the `game_state` dict and the atomselect apply-lambda injection (the only place atomselect touches the registry). Owns NO `mol delete`/`mol new` directly -- each reload is delegated to exactly one mol-bridge module (`mutation::mutate` forward, `backup::restore` cleanup).
- `start_game {molid hider_count}` implements the EXACT non-negotiable ordering: `backup::snapshot` (BEFORE mutate) -> `mutation::make_placeholder_hiders` -> `mutation::mutate` (mol delete original + mol new combined + tag sentinels -> new game_molid) -> `backup::apply` on the NEW game_molid (SC4 forward: restore reps+viewpoint) -> `registry::reconstruct_from_sentinels` via the `[list apply {{molid} {...}} $game_molid]` DI (command-prefix VALUE, not evaluated -- the 13-01 fix). Returns `game_state` dict `{game_molid hider_count snapshot}`.
- `cleanup {game_state}` passes the LIVE `game_molid` (NOT the dead `snapshot.molid`) as the 2nd arg to `backup::restore` -- the PDB-rebuild integration contract (the original was deleted by `mutation::mutate` during `start_game`, so `snapshot.molid` is dead by cleanup time). Then `registry::reset`. Returns the restored molid.
- `restart {game_state}` = `cleanup` + `start_game` with the same `hider_count` on the restored molid.
- Wired the 3 new lib files into `vmd/biochemeleon.tcl` in dependency order (`backup` -> `mutation` -> `game`) AFTER `demos.tcl` and BEFORE `gui/dialog.tcl`. `registry.tcl` is sourced exactly ONCE; backup/mutation/game do NOT re-source it (would WIPE `_records`). Updated the preceding comment block to document the Phase 15 additions + the dep-order rationale.
- Proved the orchestration end-to-end under headless VMD (`phase15_game_smoke.tcl`, 1znf + 2 hiders): `BCHM_SMOKE_RESULT PASS=1 FAIL=none`, zero `ERROR)` lines. The smoke asserts the `game_state` shape, `start_game` (426 atoms + 2 sentinels + `count_hiders==2` via the DI + reps restored on game_molid = SC4 forward), `cleanup` (424 atoms + 0 sentinels + `count_hiders==0` + reps restored = SC2 + the LIVE game_molid DELETED -- proves `backup::restore` deleted the game_molid, not the dead original), and a `restart` round-trip (426 atoms + 2 sentinels + `count_hiders==2`).

## Verification Results

| Gate | Result |
| --- | --- |
| Task 1 load-gate (source full entry headlessly; guard bypass) | `OK:start_game OK:cleanup OK:restart` + `BCHM_SMOKE_RESULT PASS=1`, no `ERROR)` lines |
| 8.6 gate on game.tcl (`\b(lmap\|try\|throw\|finally\|tailcall\|coroutine\|yield)\b`) | ZERO matches |
| game.tcl sources nothing (`^\s*source\b`) | ZERO matches |
| game.tcl owns no `mol delete`/`mol new` commands (only comment mentions) | ZERO command matches (4 comment mentions only) |
| apply-lambda DI is `[list apply ...]` (command-prefix VALUE) | confirmed (game.tcl reconstruct_from_sentinels line) |
| cleanup passes `game_molid` to `backup::restore` (not `snapshot.molid`) | confirmed (game.tcl cleanup line) |
| REGRESSION: phase14_mol_smoke.tcl re-run | `BCHM_SMOKE_RESULT PASS=1` (no regression; the entry change only ADDS source lines) |
| 8.6 gate on phase15_game_smoke.tcl | ZERO matches |
| Task 2 smoke (headless VMD, 1znf, 2 hiders) | `BCHM_SMOKE_RESULT PASS=1 FAIL=none` |
| Smoke `ERROR)` line scan | ZERO matches |
| Smoke atom-count trace (424 -> 426 -> 424 -> 426) | all 4 steps ran with correct counts (Segments: 2 / Fragments: 3 on the combined molecule = hider segment added) |

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement game.tcl + wire the 3 new lib files into the entry** - `f8df463` (feat)
2. **Task 2: Write + run phase15_game_smoke.tcl (orchestration + game_state shape + restart)** - `0622605` (test)

**Plan metadata:** `docs(15-04): complete game composition root plan` (this commit).

## Files Created/Modified

- `vmd/lib/game.tcl` (NEW) -- ::biochemeleon::game namespace (composition root). `start_game {molid hider_count}` (snapshot -> make_placeholder_hiders -> mutate -> backup::apply on game_molid -> registry::reconstruct_from_sentinels via `[list apply {lambda} $game_molid]` DI -> return game_state dict); `cleanup {game_state}` (backup::restore $snapshot $game_molid + registry::reset); `restart {game_state}` (cleanup + start_game same hider_count). Sources NOTHING; owns no mol delete/mol new. Tcl 8.5 only.
- `vmd/biochemeleon.tcl` (MODIFIED) -- +3 source lines (`backup.tcl`, `mutation.tcl`, `game.tcl`) in dependency order after `demos.tcl` and before `gui/dialog.tcl`, with a comment block documenting the Phase 15 additions + the dep-order rationale + the registry-sourced-ONCE constraint. Re-source guard, package provide, public procs, and menu registration unchanged.
- `vmd/smoke/phase15_game_smoke.tcl` (NEW) -- headless smoke proving game.tcl's orchestration on 1znf (424 atoms) + 2 hiders. Sources lib files in dep order directly (mirrors the entry, avoids GUI/dialog baggage). Asserts game_state shape, start_game (426 atoms + 2 sentinels + count_hiders==2 + reps restored = SC4 forward), cleanup (424 atoms + 0 sentinels + count_hiders==0 + reps restored = SC2 + game_molid DELETED), restart round-trip. BCHM_SMOKE_RESULT PASS=1 FAIL=none.

## Decisions Made

1. **Apply-lambda DI (plan's explicit choice) over the proc-prefix form 15-02 used.** game.tcl injects `[list apply {{molid} {atomselect...}} $game_molid]` -- a self-contained command-prefix VALUE. Both forms work with the registry's `[{*}$fetch_hider_ids]` expansion; the plan chose apply-lambda so game.tcl is self-contained (no dependency on `mutation::fetch_hider_indices` existing) and the 15-01 pure suite's bound-arg case directly mirrors it. The lambda hardcodes `resname GAM and beta < 0` (canonical selector) because apply-lambda scope doesn't link mutation's `HID_RESNAME` variable. This is CRITICAL DESIGN POINT #2 from the plan.
2. **cleanup passes `game_molid` (NOT `snapshot.molid`) to `backup::restore`** -- the PDB-rebuild integration contract. `mutation::mutate` deletes the original during `start_game`, so `snapshot.molid` is dead by cleanup time. The smoke's game_molid-deleted assertion guards this in isolation. CRITICAL DESIGN POINT #3.
3. **game.tcl sources NOTHING.** The entry sources its deps; re-sourcing registry would WIPE `_records`. game.tcl references `::biochemeleon::registry::*` at CALL time (tcl proc resolution is call-time). CRITICAL DESIGN POINT #4.
4. **Entry source order: setup_state -> registry -> demos -> backup -> mutation -> game -> dialog.** registry sourced ONCE. CRITICAL DESIGN POINT #5.
5. **game.tcl owns NO mol delete/mol new directly** -- delegates forward to `mutation::mutate`, restore to `backup::restore`. CRITICAL DESIGN POINT #6. (The smoke confirms: the only `mol delete`/`mol new` calls are in mutation.tcl + backup.tcl, never in game.tcl's proc bodies.)
6. **1znf (424 atoms) + 2 hiders for the smoke** (plan's choice, not the research skeleton's 1k8p/555/5) -- smaller + faster; assertions scale identically. 424+2=426; 2 sentinels; `count_hiders==2`.

## Deviations from Plan

None -- plan executed exactly as written. The plan's `start_game` body already used the correct 2-arg `mutate {molid hider_records}` signature (15-02's actual API, not the research skeleton's 3-arg proposal) and `cleanup` already used the correct 2-arg `restore {snapshot molid_to_delete}` with `game_molid` (15-03's actual API, not the research skeleton's 1-arg form). The apply-lambda DI (`[list apply ...]`), the game_state shape, the entry source order, and the "game.tcl sources nothing" constraint were all transcribed verbatim from the plan. All 6 CRITICAL DESIGN POINTS were honored as specified.

### Notes on plan fidelity

- **Load-gate guard-bypass form (not a deviation):** the plan's load-check used `set ::biochemeleon::loaded 0` before sourcing. I used the semantically-identical `namespace eval ::biochemeleon {variable loaded 0}` (creates the namespace + sets loaded=0) to guarantee the bypass works regardless of whether tcl auto-creates namespaces on `set ::ns::var`. Same effect: the guard's `info exists && $loaded` is false -> the namespace eval + source lines run. The load-gate passed (all 3 game procs OK).
- **`info commands` for the proc-existence check (not a deviation):** the plan's load-check used `info procs ::biochemeleon::game::$p`. I used `info commands ::biochemeleon::game::$p` (procs are commands; `info commands` with a fully-qualified pattern is reliable from any namespace). Same intent; the load-gate confirmed all 3 procs resolve.

## Issues Encountered

- **`bash -ic` exit codes vary (124 on the regression run, 5 on the smoke run)** -- the known WSL/VMD `tcsetattr` interaction at VMD exit. Not a failure: the authoritative result is the `BCHM_SMOKE_RESULT` marker (printed BEFORE the hang), not `$?` (VMD always exits 0 / the wrapper's exit is unreliable). All 3 VMD runs (load-gate, regression, smoke) parsed the marker successfully via grep.
- **`rg` not installed in WSL** -- used the Grep tool (ripgrep-backed) for the static gates instead of bash `rg`. No impact on the gates (8.6 gate + sources-nothing + no-mol-delete all returned the expected zero/expected matches).

## Authentication Gates

None -- VMD 1.9.3 runs locally via the WSL alias; no external auth required.

## User Setup Required

None -- no external service configuration required. game.tcl uses only VMD 1.9.3 tcl 8.5 stdlib (dict + apply + atomselect via the injected lambda). The smoke runs headless from WSL via the established `bash -ic 'cd <staging> && vmd -dispdev text -e <smoke> -eofexit < /dev/null'` pattern.

## Next Phase Readiness

- **Unblocks:** Plan 15-05 (capstone) -- the full backup -> mutate -> reconstruct -> cleanup -> restore pipeline with detailed SC1-SC4. game.tcl is the integration point; the capstone exercises the same `start_game`/`cleanup`/`restart` lifecycle this plan proved, with the detailed success-criterion assertions (SC1 atom count + sentinel indices, SC2 restored reps + viewpoint, SC3 exact-set registry, SC4 forward reps on game_molid).
- **Ready for Phase 16 (MVP loop / generators + PickBridge):** game.tcl is the orchestrator the click loop calls (`registry::mark_found` on a pick). Phase 16 swaps `mutation::make_placeholder_hiders` for real sphere placement; the `start_game` signature, `game_state` shape, and DI injection line stay identical (the plan designed `start_game` Phase-16-ready). `restart` gives the "new round" mechanism.
- **Coordination with the Wave-1 modules (all merged):** `mutation::mutate` deletes the original during `start_game` (so `snapshot.molid` is dead by cleanup -- the contract `cleanup` relies on); `backup::restore`'s 2-arg signature accepts the LIVE `game_molid` as `molid_to_delete`; `registry::count_hiders` + `reset` are the smoke's SC3 assertions. All three contracts are exercised + proven by this plan's smoke.
- **No blockers / concerns.** The 3 Wave-1 modules compose cleanly through game.tcl; the apply-lambda DI is correct (command-prefix VALUE); the game_molid-deleted contract holds; the entry loads all Phase-15 lib files cleanly in headless mode; Phase 14 mol smoke is unaffected (no regression).

---
*Phase: 15-mutation-safety-hider-registry*
*Plan: 04*
*Completed: 2026-08-30*
