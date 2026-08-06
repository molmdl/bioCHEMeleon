---
phase: 03-mutation-safety-hider-registry-foundation
plan: phase-summary
subsystem: mutation-safety
tags: [pymol, hider-registry, mutation-safety, dependency-injection, headless-pymol, smoke-test, pse-round-trip, b-factor-selector, atom-id-stability]

# Dependency graph
requires:
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: "The biochemeleon/ package shell + PluginDialog (the module surface Phase 3's game.py plugs into)"
  - phase: 02-setup-tab-configuration-and-bundled-demos
    provides: "setup_state.py pure layer (GAME_REPS 5 reps, DEMO_MANIFEST) that registry.py imports GAME_REPS from — keeps the registry pure"
provides:
  - "biochemeleon/registry.py (PURE, 272 lines, 10 HiderRegistry methods) — the id-keyed hider data model, WSL-unit-testable"
  - "biochemeleon/backup.py (cmd, 85 lines) — snapshot/restore/discard/verify_intact; the no-undo safety net"
  - "biochemeleon/mutation.py (cmd, 148 lines) — insert_hider/fetch_all_hider_ids/cleanup_hiders; sentinel-based hider lifecycle"
  - "biochemeleon/game.py (cmd orchestrator, 69 lines) — GameController start/cleanup/abort_on_error/reconstruct_registry"
  - "tests/test_registry.py (54 unit tests) + smoke/phase3_smoke.py (24 runtime checks) — the verification backbone"
  - "03-VERIFICATION.md — the formal criterion-by-criterion evidence (4/4 criteria PASS, 3/3 requirements satisfied, 3 spikes resolved)"
affects:
  - 04-mvp-core-loop-sphere (builds the sphere generator + click-to-find + timer + win on this foundation)
  - 05-line-stick-cartoon-generators (reuse insert_hider + registry; cartoon is the L-complexity swing)
  - 06-hint-reveal (registry.mark_found + by_rep drive hint neighbor selection)
  - 07-found-hider-management-restart-cleanup (cleanup_hiders + backup.restore + reconstruct_registry)
  - 08-persistence (registry.to_dict/from_dict shape is the .bcm sidecar; rep=None reconciliation)

# Tech tracking
tech-stack:
  added:
    - "biochemeleon/registry.py (pure: stdlib + GAME_REPS from setup_state; no `from pymol`)"
    - "biochemeleon/backup.py (cmd-coupled, standalone)"
    - "biochemeleon/mutation.py (cmd-coupled, standalone)"
    - "biochemeleon/game.py (cmd-coupled orchestrator / composition root)"
    - "smoke/phase3_smoke.py (headless-runnable runtime smoke; pure pymol.cmd.*)"
    - "tests/test_registry.py (54 WSL unit tests)"
  patterns:
    - "3-module split (registry pure + backup/mutation cmd-standalone + game.py composition root) — enables 3 parallel waves + WSL-testability of the pure layer"
    - "Dependency injection for purity: reconstruct_from_sentinels(iterate_fn) takes the cmd-coupled iterate as a parameter so registry.py stays pure (no `from pymol`); game.py injects `lambda: mutation.fetch_all_hider_ids(obj)`"
    - "Sentinel-based hider identity: segi='GAME' + b=-999 survives .pse reload; cleanup/reconstruct key on the sentinel, NEVER on resi/chain/index (unstable)"
    - "id-keyed registry: HiderRegistry keys on (object, atom id); id is stable across add/remove (Pitfall 4), index is NOT"
    - "Headless PyMOL from WSL: cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script> from the staged tmp/bioCHEMeleon/ path — closes the WSL/Windows runtime gap for cmd-only smoke scripts (no Qt/GUI)"
    - "b-factor sentinel selector = comparison (b < 0), NEVER exact (b -999 — malformed, silently matches nothing); sentinel VALUE stays -999"

key-files:
  created:
    - "biochemeleon/registry.py"
    - "biochemeleon/backup.py"
    - "biochemeleon/mutation.py"
    - "biochemeleon/game.py"
    - "tests/test_registry.py"
    - "smoke/phase3_smoke.py"
    - ".planning/phases/03-mutation-safety-hider-registry-foundation/03-VERIFICATION.md"
  modified:
    - "AGENTS.md (Phase 3 mutation-safety rules + Architecture diagram)"
    - ".planning/research/PITFALLS.md (Q1/Q2/Q2b/PSE resolved flags + 3 runtime pitfalls)"

key-decisions:
  - "3-module split for parallelism + WSL-testability: registry.py pure / backup.py + mutation.py cmd-standalone / game.py orchestrator"
  - "Restore = cmd.delete(target) + cmd.create(target, backup) two-step, NEVER single-call create(existing, backup) (smoke confirmed single-call IS REPLACE, but delete+create stays canonical/unambiguous)"
  - "Hider id via cmd.identify(..., mode=0) after insert, NEVER the cmd.pseudoatom return value (smoke: returns None/NoneType)"
  - "Registry keys on atom id (stable across add/remove + .pse reload), NEVER index (fragile, shifts on insert/remove)"
  - "reconstruct_from_sentinels uses dependency injection — registry.py stays pure, game.py injects the iterate fn"
  - "rep=None after .pse reload — sentinel carries no rep; Phase 8 .bcm sidecar reconciles (smoke-confirmed)"
  - "backup.snapshot MUST precede any mutation.insert_hider — PyMOL Open Source has NO undo; the backup is the only recovery mechanism"
  - "B-factor sentinel SELECTOR is b < 0 (comparison), NEVER b -999 (exact — malformed, silently matches nothing); sentinel VALUE stays -999"

patterns-established:
  - "Pattern: 3-module split (pure data / cmd primitives / orchestrator) for any future PyMOL subsystem that has both WSL-testable logic and cmd-coupled runtime"
  - "Pattern: dependency injection to keep a pure layer pure (the iterate fn is a parameter, not an import)"
  - "Pattern: headless smoke from WSL via run-conda-pymol.bat -cq for any pure-cmd verification (no Qt/GUI)"
  - "Pattern: sentinel-based identity that survives .pse reload (segi + b-factor), NEVER resi/chain/index"
  - "Pattern: VERIFICATION.md as the phase-complete auditable artifact — written AFTER smoke + gates are green so it codifies already-verified results"

# Metrics
duration: ~2.2 hours (20 plans across 12 waves)
completed: 2026-08-06
---

# Phase 3: Mutation Safety & Hider Registry Foundation — Summary

**The mutation-safety foundation (registry pure + backup/mutation cmd + game.py orchestrator) is runtime-verified at the headless-PyMOL tier — 4/4 success criteria PASS (smoke 24/24 ALL PASSED), 3/3 requirements satisfied, 3 research spikes resolved; Phase 4 builds the sphere generator + click-to-find + timer + win on top of it.**

**Phase:** 03-mutation-safety-hider-registry-foundation
**Plans:** 20 (across 12 waves)
**Status:** COMPLETE — verified (smoke 24/24 ALL PASSED + 03-VERIFICATION.md 4/4 PASSED + 12-gate WSL regression green + 144 unit tests green)
**Completed:** 2026-08-06

## What Shipped

### New modules (3 + orchestrator)

- **biochemeleon/registry.py** (PURE, 272 lines, stdlib + `GAME_REPS` from setup_state; NO `from pymol`):
  - `HiderRecord` (`__slots__=('id','object','rep','status','pos')`; `rep` validated against `GAME_REPS`; `rep=None` tolerance for post-reload reconstruction; `to_dict()` omits `pos` when None)
  - `HiderRegistry` backed by `OrderedDict` keyed by `(object, id)` tuple (Pitfall 4 lock: id stable; index is NOT)
  - 10 methods: `register`/`get`/`all`/`remove` (core CRUD) + `by_rep`/`counts_by_rep`/`mark_found` (queries/status) + `to_dict`/`from_dict` (serialization — the Phase 8 `.bcm` sidecar shape) + `reconstruct_from_sentinels` (DI-based post-`.pse`-reload rebuild; `rep=None`)
  - 54 WSL unit tests (TestHiderRecord + TestHiderRegistryCore/Queries/Serialize/Reconstruct/EdgeCases)

- **biochemeleon/backup.py** (cmd-coupled, standalone, 85 lines): `BACKUP_PREFIX='_bchm_backup'` (underscore-hidden from `public_objects`). `snapshot(target)` (delete stale + create fresh), `restore(target, backup)` (delete+create two-step — NEVER single-call), `discard(backup)` (idempotent), `verify_intact(target, backup)` (count gate + `(resn, resi, name, chain, segi)` identity multiset — NO x/y/z; `cmd.create` copies coords bit-for-bit so count+identity suffices per RESEARCH §Q6 fallback).

- **biochemeleon/mutation.py** (cmd-coupled, standalone, 148 lines): `insert_hider(object, pos, rep, handle)` (`cmd.pseudoatom(object=existing)` in-place + `cmd.alter` sentinel `segi='GAME'`+`b=-999.0` via hygienic `space={}` + `cmd.sort` + `cmd.identify(mode=0)` → stable id — NEVER the pseudoatom return value). `fetch_all_hider_ids(object)` (sentinel iterate with `space=`, selector `segi GAME and b < 0`). `cleanup_hiders(object)` (sentinel `cmd.remove` by `segi GAME` alone — never by resi/chain/index).

- **biochemeleon/game.py** (cmd-coupled orchestrator / composition root, 69 lines): `GameController(target_obj)` with `start(hider_specs)` (snapshot → insert loop → register), `cleanup()` (cleanup_hiders + verify_intact + discard — returns the verify_intact bool), `abort_on_error()` (restore + discard — returns the restore bool), `reconstruct_registry()` (DI: `registry.HiderRegistry().reconstruct_from_sentinels(lambda: mutation.fetch_all_hider_ids(obj))`). Wires all 3 modules (gate 12: 18 orchestration matches).

### Tests + smoke

- **tests/test_registry.py** (54 WSL unit tests): TestHiderRecord + TestHiderRegistryCore (register/get/all/remove) + TestHiderRegistryQueries (by_rep/counts_by_rep/mark_found) + TestHiderRegistrySerialize (to_dict/from_dict round-trip) + TestHiderRegistryReconstruct (reconstruct_from_sentinels + rep=None + counts_by_rep guard) + TestHiderRegistryEdgeCases.
- **smoke/phase3_smoke.py** (112 lines, 24 runtime checks): complete round-trip — setup + C1 (object list unchanged + count+=3) + C2 (3 sentinels segi=GAME b=-999) + Q4 (ids stable across insert) + C3 (registry len + per-rep counts + by_rep) + C4 happy path (cleanup returns True + count back to orig + id-set matches + backup discarded) + failure path (abort returns True + count back to orig) + Q2 (single-call create IS REPLACE) + Q1 (pseudoatom returns None) + PSE spikes (sentinel survives reload, id stable, b=-999.0 preserved, reconstruct works, rep=None). Ran headlessly 24/24 ALL PASSED via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq`.
- **144 unit tests total** (54 registry + 90 setup_state) — all green at the WSL tier (03-18 gate 4).

## What's Proven (4 Success Criteria — 24/24 ALL PASSED at runtime)

The full criterion-by-criterion evidence lives in **[03-VERIFICATION.md](./03-VERIFICATION.md)** (338 lines: each criterion mapped to smoke checks by name + PASS/FAIL + spike findings + WSL gates + artifacts). Summary:

1. **Insert INTO existing object** — `cmd.pseudoatom(object=existing)` keeps the public object list unchanged; count += N. Smoke C1 PASS + Q4 spike (existing ids stable across insert, exactly N new ids). [HIDER-01]
2. **Sentinel + registry** — every hider carries `segi='GAME'` + `b=-999`; registered in `HiderRegistry` keyed by `(object, id)` via `cmd.identify(mode=0)`. Smoke C2 + C3 PASS + Q1 spike (pseudoatom returns None/NoneType; code uses identify). [HIDER-02, HIDER-06]
3. **Registry queries** — `all()`/`by_rep()`/`counts_by_rep()`/`mark_found()` work; `counts_by_rep()` zero-fills all 5 `GAME_REPS`. Smoke C3 PASS + 54 WSL unit tests PASS. [HIDER-06]
4. **Cleanup/restore integrity** — happy path (`cleanup_hiders` by sentinel → `verify_intact`) AND failure path (`restore` delete+create → `discard`) both leave the target atom-for-atom identical to its pre-game backup. Smoke C4 happy + failure PASS + Q2 spike (single-call create IS REPLACE; delete+create stays canonical). [Criterion 4]

**12-gate WSL regression (03-18) — ALL GREEN:** py_compile ALL, unittest test_registry (54), unittest test_setup_state (90), combined (144), Pitfall-1 (0), Pitfall-11 (0), registry purity (0 `from pymol`), cmd-coupled (1/1/1), sentinel segi='GAME' (5), space= hygiene (9), architecture setup_state pure (0), orchestration (18). Plus 7 confirmation gates (module completeness 3/5/4/11-documented-overlap, b -999=0 / b < 0=1, lowercase-id=0 / uppercase-ID=3) and the optional headless smoke re-confirmation (24/24 ALL PASSED, no code changed since 03-15). Full table in 03-VERIFICATION.md §"WSL Regression Gate Results".

## Research Spikes Resolved (3 UNVERIFIED → RESOLVED at runtime)

All three MEDIUM/UNVERIFIED flags from 03-RESEARCH.md are resolved with runtime-confirmed values (recorded in PITFALLS.md "Phase 3 — Resolved Research Flags"; future research must NOT re-investigate):

- **Q1 (pseudoatom return value)**: `cmd.pseudoatom(...)` returns `None` (type `NoneType`) — NOT an id, status code, or object reference. Code never relies on it; `insert_hider` fetches the id via `cmd.identify(..., mode=0)`. Informational — the implementation already does the right thing.
- **Q2 (create merge-vs-replace)**: a single-call `cmd.create(existing, src)` IS a **REPLACE** (`n_after == n_before`; no doubling). The RESEARCH §Q2 MEDIUM flag is cleared. `backup.restore` keeps the explicit `cmd.delete(target)` + `cmd.create(target, backup)` two-step regardless — unambiguous for the failure path even though single-call is also REPLACE.
- **PSE (round-trip id/sentinel stability)**: the `segi='GAME'` sentinel SURVIVES `.pse` reload (load-bearing — the whole reconstruct-after-reload mechanism depends on it); atom `id` is STABLE across the round-trip (`pse_sent == [saved_id]`, Pitfall 4 holds at runtime); `b=-999.0` preserved exactly; `reconstruct_from_sentinels` rebuilds a 1-record registry (`fetch_all_hider_ids('1ubq')` returns `[('1ubq', 662)]`); `rep=None` after reload (sentinel carries no rep). Pitfalls 4 + 7 confirmed at runtime.

## Architecture Decision

**3-module split** for parallelism + WSL-testability:

```
setup_state.py  (PURE: stdlib only — no pymol, no Qt; unit-testable in WSL)
      ↑
demos.py        (cmd bridge: imports FROM setup_state; uses pymol.cmd)
      ↑
gui_setup.py    (Qt + cmd: imports FROM setup_state AND demos)

Phase 3 stack (mutation-safety; game.py is the composition root):
  registry.py  (PURE: stdlib + GAME_REPS from setup_state; unit-testable in WSL)
  backup.py    (cmd: snapshot/restore/discard/verify_intact — standalone)
  mutation.py  (cmd: insert_hider/fetch_all_hider_ids/cleanup_hiders — standalone)
  game.py      (cmd orchestrator: GameController imports backup+mutation+registry)
```

- **Dependency direction is strict** (never reversed): `setup_state.py ← registry.py ← backup.py/mutation.py ← game.py`. `registry.py` has NO `from pymol` (gate 7: 0 matches) — WSL-unit-testable. `game.py` is the composition root that wires all three (gate 12: 18 orchestration matches).
- **Dependency injection for purity**: `reconstruct_from_sentinels(iterate_hider_keys)` takes the cmd-coupled iterate as a **parameter**, not an import — `registry.py` stays pure; `game.py` injects `lambda: mutation.fetch_all_hider_ids(obj)`.
- **Parallelism payoff**: Waves 1-3 ran 3 plans in parallel across the 3 file-disjoint tracks (registry / backup / mutation), then Wave 5 wired them via `game.py`.

## 6 Runtime Discoveries (library bugs vs smoke-test bugs)

The WSL gate suite (py_compile + 144 unit tests + grep Pitfall-1/11) verifies SYNTAX + pure-layer behavior but CANNOT exercise `cmd.iterate`, `cmd.pseudoatom`, `cmd.create`, `.pse` save/load, or the backup lifecycle. The 03-15 headless smoke surfaced 6 runtime bugs — each auto-fixed (Rule 1 bug / Rule 3 blocker), committed, and re-run until 24/24 ALL PASSED. Full detail in 03-VERIFICATION.md §"Runtime Discoveries".

### Library bugs (PyMOL API behavior — apply to ALL future cmd-coupled code)

| # | Discovery | Commit | Lesson for Phase 4+ |
|---|-----------|--------|---------------------|
| 1 | `cmd.iterate` exposes atom id as uppercase `ID`, NOT lowercase `id` (Python builtin → NameError/wrong value) | `e38cff7` | Iterate symbols are CASE-SENSITIVE + UPPERCASE (`ID`, `MODEL`, `RESN`, …). The 03-RESEARCH symbol table is authoritative. |
| 2 | `cmd.iterate` does NOT expose `x`/`y`/`z` (state-dependent; need `iterate_state`) | `5ed6a13` | For structure-identity checks, count + `(resn, resi, name, chain, segi)` multiset suffices (`cmd.create` copies coords bit-for-bit). |
| 6 | `b -999` is a malformed selector (silently matches nothing); `b < 0` is the valid comparison form (load-bearing fix) | `6a15a29` | B-factor selectors are COMPARISONS (`b < 0`, `b > N`), NEVER exact matches. A malformed selector silently returns `[]` — dangerously plausible. |

### Smoke-test bugs (the smoke script itself — apply only to future smoke tests)

| # | Discovery | Commit | Lesson |
|---|-----------|--------|--------|
| 3 | Redundant `verify_intact` on a backup already discarded by `cleanup()` → `CmdException` | `9e40e8a` | Assert the orchestrator's RETURN value; don't re-derive it by re-calling cmd helpers on discarded objects. |
| 4 | Same redundant `verify_intact` on the failure path (twin of #3) | `9b00657` | Both cleanup paths (happy + failure) discard the backup; the smoke must not touch it afterward. |
| 5 | `cmd.save("/tmp/phase3_test.pse")` — Windows PyMOL cannot resolve WSL/Linux `/tmp` | `039bc6a` | Use relative paths (resolve against the cmd.exe cwd) or Windows-style `C:\...`. `demos.to_windows_path()` is the WSL guard. |

Plus 1 diagnostic (`cf702a1` — PSE-DIAG triage lines) + 1 docs (`b320316` — AGENTS.md headless method). All 6 fixes are 1-line corrections (no architectural changes, no scope creep). Every discovery is encoded as an AGENTS.md rule + a PITFALLS.md entry so Phase 4+ doesn't rediscover them.

## Residual Risks for Phase 4

### Gaps Phase 4 must fill

1. **`start()` uses a placeholder insert.** Phase 3's `GameController.start(hider_specs)` takes a list of `(pos, rep)` tuples and inserts at the caller-supplied positions. Phase 4 must replace this with the **real sphere generator** (pick random atoms, place sphere hiders near them). The snapshot → insert → register mechanism is proven; only the position-picking logic is Phase 4 work.
2. **No click handler yet.** Phase 4 wires `cmd.id_atom(picked_selection)` → `registry.get(object, id)` → `registry.mark_found`. `mark_found` raises `KeyError` on unregistered atoms — the clean error signal for "clicked a non-hider" (click on a non-hider is a caller bug, handled gracefully).
3. **No UI wiring yet.** `GameController.start`/`cleanup`/`abort_on_error` are library functions. Phase 4 connects them to the Setup tab's **Start** button and the Game tab's **Restart**/**Cleanup** buttons, plus the 3-2-1 countdown, rolling info log, and timer.
4. **`rep=None` after `.pse` reload.** `reconstruct_from_sentinels` sets `rep=None` (the sentinel carries no rep). Phase 4's click handler must tolerate `rep=None` records (or Phase 8's `.bcm` sidecar must be loaded to recover `rep` before play resumes). Documented in AGENTS.md.
5. **Multi-object games.** Phase 3 assumes one target object; `_bchm_backup` is a single backup name. If Phase 9 supports parallel games on multiple objects, backup naming needs per-target suffixes (out of scope for Phase 3).

### PyMOL API contracts Phase 4 must respect (encoded in AGENTS.md)

6. **`fetch_all_hider_ids` uses `b < 0` (comparison), NEVER `b -999` (exact — malformed, silently matches nothing).** The sentinel VALUE stays `-999` (set in `insert_hider`/`cleanup` docstrings); only the SELECTOR uses `b < 0` (matches `-999.0`).
7. **`cmd.iterate` exposes atom id as uppercase `ID`, NOT lowercase `id`** (Python builtin → `NameError` or wrong value). Same for `MODEL`, `RESN`, `RESI`, `NAME`, `CHAIN`, `SEGI`, `B`.
8. **`cmd.iterate` has NO `x`/`y`/`z`** (state-dependent; need `cmd.iterate_state`). `verify_intact` uses count + `(resn, resi, name, chain, segi)` identity — coords omitted per Q6 fallback (`cmd.create` copies coords bit-for-bit).
9. **Headless PyMOL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` works from WSL** (documented in AGENTS.md). Stage the package + script to `tmp/bioCHEMeleon/` first (`wsl2win_cp.sh`), `cd` into it, then run. Exit 0 = clean. Phase 4 smoke tests can reuse this for any pure-cmd verification. Qt/GUI paths (PluginDialog, Setup tab, click-to-find loop) STILL need a human in a real PyMOL session — only pure `pymol.cmd.*` scripts are headless-runnable.

## Phase 4 Readiness

**The foundation Phase 4 builds on is proven at the runtime tier, not just syntax-checked:**

| Foundation piece | Proven by | Phase 4 uses it for |
|---|---|---|
| `mutation.insert_hider` (in-place pseudoatom + sentinel + identify→id) | smoke C1/C2 + Q1/Q4 | sphere generator calls it per hider |
| `mutation.cleanup_hiders` (sentinel remove) | smoke C4 happy | Cleanup button |
| `backup.snapshot`/`restore`/`discard`/`verify_intact` | smoke C4 happy + failure + Q2 | Start (snapshot) + Restart/abort (restore) + Cleanup (verify+discard) |
| `registry.HiderRegistry` CRUD/queries/serialize/reconstruct | 54 unit tests + smoke C3 + PSE | click handler (`get`/`mark_found`), Game tab counts (`counts_by_rep`/`by_rep`), Save/Load (`to_dict`/`from_dict`), reload (`reconstruct_from_sentinels`) |
| `GameController.start`/`cleanup`/`abort_on_error`/`reconstruct_registry` | smoke C1-C4 + failure + PSE | Start button → `start`; Cleanup button → `cleanup`; error path → `abort_on_error`; reload → `reconstruct_registry` |

**Phase 4 — MVP Core Loop (Sphere) builds:**
- the **sphere generator** (replace the placeholder insert — pick random atoms, place sphere hiders near them)
- the **click handler** (`cmd.id_atom` → `registry.get` → `registry.mark_found`)
- the **timer** (counting up from start) + **win condition** (all hiders found → stop timer + winning message)
- the **Game tab UI** (rolling info log, timer, remaining-hiders count, 3-2-1 countdown)

The highest-risk area (safe object mutation + hider registry) is fully de-risked. Phase 4's work is feature-building on a proven base, not research.

## Dependency Graph (frontmatter summary)

- **requires**: Phase 1 (package shell + PluginDialog), Phase 2 (`setup_state.py` pure layer — `GAME_REPS` + `DEMO_MANIFEST`)
- **provides**: the mutation-safety foundation (registry pure + backup/mutation cmd + game.py orchestrator) + the smoke/verification pattern + 14 AGENTS.md rules + 6 resolved PITFALLS
- **affects**: Phase 4 (sphere MVP core loop), Phase 5 (line/stick + cartoon generators), Phase 6 (hint/reveal — registry queries), Phase 7 (found-management/restart/cleanup), Phase 8 (persistence — `to_dict`/`from_dict` shape + `rep=None` reconciliation)

## Next

**Phase 4 — MVP Core Loop (Sphere).** Replace the placeholder insert with the sphere generator, wire the click handler (`cmd.id_atom` → `registry.mark_found`), add the timer + win condition + Game tab UI. The foundation (`snapshot → insert → register → cleanup/restore`) is proven; Phase 4 builds the player-facing loop on top of it.

**Required reading for the Phase 4 planner:** this SUMMARY + `AGENTS.md` (the 14 Phase-3 mutation-safety rules + Architecture diagram) + `03-VERIFICATION.md` (the criterion-by-criterion evidence). Together they are the complete handoff — no need to re-read the 20 per-plan SUMMARYs.

---

*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
*Plans: 20/20 (across 12 waves)*
*Status: COMPLETE — verified (smoke 24/24 ALL PASSED + 03-VERIFICATION.md 4/4 PASSED + 12-gate WSL regression green)*
