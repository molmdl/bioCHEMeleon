---
phase: 03-mutation-safety-hider-registry-foundation
verified: 2026-08-07T00:00:00Z
status: passed
score: 4/4 must-haves verified
verifier: independent (gsd-verifier) — does NOT trust the 03-19 executor self-report
cross_check:
  previous_report: 03-VERIFICATION.md (03-19 executor self-report from headless smoke)
  previous_claim: "24/24 ALL PASSED, status PASSED"
  independent_findings: AGREE — independent headless re-run confirms 24/24 ALL PASSED; all artifacts substantive; all 6 key_links wired; all WSL gates green; registry pure
  regressions: none
  disagreements: none
---

# Phase 3: Mutation Safety & Hider Registry Foundation — Independent Verification Report

**Phase Goal:** The plugin can safely insert hider atoms into an existing object and track them — de-risking the highest-uncertainty area BEFORE any generator is built on it, with a smoke test proving backup → mutate → remove → restore leaves the original structure intact.
**Verified:** 2026-08-07
**Status:** **PASSED**
**Verifier:** Independent (gsd-verifier) — read the actual code; ran the WSL gates; re-ran the headless smoke. Does NOT trust the 03-19 executor's `03-VERIFICATION.md` self-report (cross-checked it instead).

## Verification Method

This is an **independent** verification. I did NOT trust the 03-19 executor's `03-VERIFICATION.md` claims. I:
1. Read every Phase 3 artifact file in full (`registry.py`, `backup.py`, `mutation.py`, `game.py`, `tests/test_registry.py`, `smoke/phase3_smoke.py`).
2. Grepped the actual code for each of the 6 key_link patterns (with line numbers).
3. Ran the WSL gates myself: `py_compile`, `unittest tests.test_registry`, `unittest tests.test_setup_state`, combined (144 tests), Pitfall-1 (Tk/Pmw/PyQt5-raw), Pitfall-11 (`.exec_()`), registry purity (`from pymol`), setup_state purity, cmd-coupling.
4. Verified `registry.py` is pure (0 `from pymol` matches) — the load-bearing architecture claim.
5. Re-ran the headless PyMOL smoke test independently (re-staged via `cmp`-verified byte-identical files) — confirmed **24/24 ALL PASSED** at the runtime tier.
6. Scanned all 6 Phase 3 files for anti-patterns (TODO/FIXME/placeholder/empty returns/`=> {}`).
7. Cross-checked my findings against the 03-19 executor's `03-VERIFICATION.md` — they AGREE on every point.

## Goal Achievement

### Observable Truths (the 4 success criteria from ROADMAP.md)

| #  | Truth | Status | Evidence (from actual code, not SUMMARY claims) |
| -- | ----- | ------ | ------------------------------------------------- |
| 1  | Hider atoms inserted INTO an existing object (object list unchanged) | ✓ VERIFIED | `mutation.py:71` `cmd.pseudoatom(object=object, ...)` inserts INTO existing (the `object=existing` form, NOT `cmd.load`/`cmd.create('hiders',...)`). `game.py:31` loops `mutation.insert_hider(self.target_obj, ...)`. Smoke `C1: public object list unchanged` + `C1: count += 3` both PASS at runtime — no new public object; count += 3 exactly. |
| 2  | Every hider carries `segi='GAME'` + `b=-999` sentinel + recorded in HiderRegistry keyed by atom `id` | ✓ VERIFIED | `mutation.py:74` `cmd.alter(..., "segi='GAME'; b=-999.0", space={})` sets sentinel in one multi-`;` expression. `mutation.py:77` `cmd.identify(..., mode=0)` fetches stable id (NOT the pseudoatom return value; NOT fragile `index`). `game.py:32` `self.registry.register(object=self.target_obj, id=aid, rep=rep)`. `registry.py:142` keys on `(object, int(id))`. Smoke `C2: 3 sentinel atoms` + `C2: all segi=GAME and b=-999` + `C3: registry len == 3` all PASS. |
| 3  | Registry queryable for all hiders (id, rep, status) + per-rep counts | ✓ VERIFIED | `registry.py:153` `all()` (insertion-order list), `168` `by_rep(rep)` (fresh list, `[]` for empty NOT None), `178` `counts_by_rep()` (zero-fills ALL 5 GAME_REPS via `{rep:0 for rep in GAME_REPS}`), `200` `mark_found(object, id)` (sets status). Smoke `C3: registry len == 3` + `C3: per-rep counts == {"spheres":1,"sticks":1,"lines":1,"cartoon":0,"ribbon":0}` + `C3: by_rep spheres len 1` all PASS. 54 WSL unit tests (TestHiderRegistryQueries) green. |
| 4  | After cleanup (or restore), object's atom count + structure match pre-game state exactly | ✓ VERIFIED | Happy path: `mutation.py:145-147` `cleanup_hiders` gates on `count_atoms(f"{obj} and segi GAME")` then `cmd.remove(f"{obj} and segi GAME")` (removes atoms FROM object, NOT the object). `game.py:50-52` cleanup → verify_intact → discard. Failure path: `backup.py:60-61` two-step `cmd.delete(target)` + `cmd.create(target, backup)` (NEVER single-call). `backup.py:75-85` verify_intact: count gate + `(resn, resi, name, chain, segi)` multiset (NO x/y/z — iterate doesn't expose coords). Smoke `C4: cleanup returned True (intact)` + `C4: count back to orig` + `C4: id-set matches orig` + `failure-path abort returns True` + `failure-path: count back to orig` all PASS. |

**Score:** 4/4 truths VERIFIED

### Required Artifacts (three-level check: exists → substantive → wired)

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `biochemeleon/registry.py` | HiderRegistry + HiderRecord (pure, WSL-testable) | ✓ VERIFIED | EXISTS (272 lines). SUBSTANTIVE: `HiderRecord` (4 methods incl. `__slots__`) + `HiderRegistry` (10 non-dunder methods: register/get/all/remove/by_rep/counts_by_rep/mark_found/to_dict/from_dict/reconstruct_from_sentinels). No stub patterns. WIRED: imported by `game.py:5`; `reconstruct_from_sentinels` called in `game.py:39`. PURE: 0 `from pymol` matches (grep-confirmed). |
| `biochemeleon/backup.py` | snapshot/restore/discard/verify_intact (cmd-coupled) | ✓ VERIFIED | EXISTS (85 lines). SUBSTANTIVE: 4 functions (`snapshot`, `restore`, `discard`, `verify_intact`); `BACKUP_PREFIX='_bchm_backup'`. restore uses two-step `cmd.delete`+`cmd.create` (NEVER single-call). verify_intact tuple `(resn, resi, name, chain, segi)` — no x/y/z. No stubs. WIRED: imported by `game.py:5`; called in `game.py:27,51,52,64,65`. |
| `biochemeleon/mutation.py` | insert_hider/fetch_all_hider_ids/cleanup_hiders (cmd-coupled) | ✓ VERIFIED | EXISTS (148 lines). SUBSTANTIVE: 3 functions. `insert_hider` uses `cmd.pseudoatom(object=...)` + `cmd.alter(..., "segi='GAME'; b=-999.0", space={})` + `cmd.identify(mode=0)` + `assert len(ids)==1`. `fetch_all_hider_ids` selector is `segi GAME and b < 0` (NOT malformed `b -999`) with `ID` uppercase. `cleanup_hiders` selector `segi GAME` ALONE (sentinel-only). No stubs. WIRED: imported by `game.py:5`; called in `game.py:31,40,50`. |
| `biochemeleon/game.py` | GameController orchestrator (cmd-coupled) | ✓ VERIFIED | EXISTS (69 lines). SUBSTANTIVE: `GameController` with 5 methods (`__init__`, `start`, `reconstruct_registry`, `cleanup`, `abort_on_error`). No stubs. WIRED: 15 orchestration matches (`backup.\|mutation.\|registry.`); orchestrates all 3 modules. |
| `tests/test_registry.py` | unit tests for pure registry layer | ✓ VERIFIED | EXISTS (579 lines). SUBSTANTIVE: 54 test methods across 6 classes (TestHiderRecord, TestHiderRegistryCore, TestHiderRegistryQueries, TestHiderRegistrySerialize, TestHiderRegistryReconstruct, TestHiderRegistryEdgeCases). Stubs `pymol`/`pymol.Qt` via `MagicMock` (WSL-runnable). WIRED: `python3.6 -m unittest tests.test_registry` → Ran 54 tests, OK. |
| `smoke/phase3_smoke.py` | integration smoke test | ✓ VERIFIED | EXISTS (112 lines). SUBSTANTIVE: 24 `check()` invocations spanning C1-C4 + failure path + Q1/Q2/Q4/PSE spikes. No stubs. WIRED: headless PyMOL run → 24/24 ALL PASSED (independently re-confirmed this verification). |

### Key Link Verification

| # | From | To | Via | Status | Code Location |
| - | ---- | -- | --- | ------ | ------------- |
| 1 | mutation.py | registry.py | `insert_hider` returns id → `registry.register` | ✓ WIRED | `game.py:31` `aid = mutation.insert_hider(...)` → `game.py:32` `self.registry.register(object=..., id=aid, rep=rep)` — id flows insert → identify → register |
| 2 | backup.py | target object | `snapshot` BEFORE any mutation | ✓ WIRED | `game.py:27` `self._backup_name = backup.snapshot(self.target_obj)` precedes `game.py:31` `mutation.insert_hider(...)` in `start()` (snapshot is line 27; first insert is line 31) |
| 3 | mutation.py | sentinel atoms | `cleanup_hiders` removes by `segi GAME` | ✓ WIRED | `mutation.py:145` `count_atoms(f"{object} and segi GAME")` gate → `mutation.py:147` `cmd.remove(f"{object} and segi GAME")` (selector is `segi GAME` ALONE — sentinel-only, never resi/chain/index) |
| 4 | backup.py | game.py | restore followed by verify_intact | ✓ WIRED | Happy: `game.py:50-52` `cleanup_hiders` → `verify_intact` → `discard` (returns `intact` bool). Failure: `game.py:64-65` `restore` → `discard` (returns `ok` bool). Both paths discard after. |
| 5 | registry.py | injected iterate_fn | `reconstruct_from_sentinels` (DI keeps registry pure) | ✓ WIRED | `registry.py:249` `def reconstruct_from_sentinels(self, iterate_hider_keys)` — the iterate fn is a PARAMETER (NOT imported). `registry.py:269` `for (obj, aid) in iterate_hider_keys()`. `game.py:39-40` injects `lambda: mutation.fetch_all_hider_ids(self.target_obj)`. Registry has 0 `from pymol` — DI confirmed. |
| 6 | game.py | backup+mutation+registry | start()/cleanup()/abort_on_error() orchestration | ✓ WIRED | 15 matches for `backup.\|mutation.\|registry.` in game.py (≥6 threshold). `start` wires snapshot+insert+register; `cleanup` wires cleanup_hiders+verify_intact+discard+reset; `abort_on_error` wires restore+discard+reset; `reconstruct_registry` wires reconstruct_from_sentinels+fetch_all_hider_ids. |

### Runtime Fix Verification (the 6 bugs the 03-15 smoke surfaced — all confirmed present in shipped code)

| # | Fix | Code Evidence |
| - | --- | ------------- |
| 1 | `cmd.iterate` exposes atom id as uppercase `ID`, not lowercase `id` | `mutation.py:113` `"stored.append((model, ID))"` (uppercase); smoke lines 38,90 use `ID`. 0 lowercase `id` in `stored.append`. |
| 2 | `cmd.iterate` does NOT expose x/y/z; verify_intact drops coords | `backup.py:80,83` tuple is `(resn, resi, name, chain, segi)` — no x/y/z. |
| 3 | (smoke bug) redundant verify_intact on discarded backup removed | `smoke/phase3_smoke.py:54` asserts `intact is True` (the orchestrator's return), no re-call after. |
| 4 | (smoke bug) failure-path twin removed | `smoke/phase3_smoke.py:64` asserts `ok is True`, no re-call after. |
| 5 | (smoke bug) `/tmp/phase3_test.pse` → relative `phase3_test.pse` (Windows path) | `smoke/phase3_smoke.py:86,88` `cmd.save("phase3_test.pse")` + `cmd.load("phase3_test.pse")` (relative). |
| 6 | `b -999` → `b < 0` selector (load-bearing) | `mutation.py:113` selector is `f"{object} and segi GAME and b < 0"` (NOT `b -999`). 0 `b -999` matches in mutation.py. |

### Requirements Coverage

| Requirement | Status | Evidence |
| ----------- | ------ | -------- |
| HIDER-01 (hiders inserted INTO same object via `cmd.pseudoatom(object=existing)`) | ✓ SATISFIED | `mutation.py:71` + smoke C1 (object list unchanged + count += 3) PASS. REQUIREMENTS.md:37 marked Complete. |
| HIDER-02 (segi='GAME' + b=-999 sentinel + tracked by `id` in HiderRegistry) | ✓ SATISFIED | `mutation.py:74` sentinel + `registry.py:142` id-keyed + smoke C2/C3 PASS. REQUIREMENTS.md:38 marked Complete. |
| HIDER-06 (generation records every hider's `(object, atom-ID)` in registry) | ✓ SATISFIED | `game.py:31-32` insert→register wiring + smoke C3 (registry len == 3) PASS. REQUIREMENTS.md:42 marked Complete. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| `biochemeleon/game.py` | 1, 10, 11, 20 | "placeholder" (in docstrings: "Phase 3 proves the mechanism with a placeholder insert"; "Phase 4/5: real generators replace _placeholder_hiders") | ℹ️ Info | NOT a stub — accurately documents Phase 3 scope. The Phase 3 GOAL is explicitly to de-risk the mechanism BEFORE any generator is built. A placeholder insert (fixed positions) to prove the mechanism IS the correct Phase 3 scope. The smoke test proves the mechanism works (24/24 PASSED). Real generators are Phase 4/5 (out of scope here). |

No TODO/FIXME/XXX/HACK, no `return null`/`return undefined`, no `=> {}`, no "coming soon"/"not implemented" in any of the 6 Phase 3 files. Clean.

### WSL Gate Results (run by me, the independent verifier)

| # | Gate | Command | Result |
| - | ---- | ------- | ------ |
| 1 | py_compile ALL | `python3.6 -m py_compile biochemeleon/*.py smoke/phase3_smoke.py` | **PASS** — exit 0, no output |
| 2 | unittest test_registry | `python3.6 -m unittest tests.test_registry -v` | **PASS** — Ran 54 tests, OK |
| 3 | unittest test_setup_state | `python3.6 -m unittest tests.test_setup_state -v` | **PASS** — Ran 90 tests, OK |
| 4 | combined unittest | `python3.6 -m unittest tests.test_registry tests.test_setup_state` | **PASS** — Ran 144 tests, OK |
| 5 | Pitfall-1 (Tk/Pmw/PyQt5-raw) | `grep -rnE "import Tkinter\|...\|import PyQt5" biochemeleon/` | **PASS** — 0 matches |
| 6 | Pitfall-11 (`.exec_()`) | `grep -rnE "\.exec_\(\)" biochemeleon/` | **PASS** — 0 matches |
| 7 | Registry purity | `grep -n "from pymol" biochemeleon/registry.py` | **PASS** — 0 matches (registry is pure; the load-bearing architecture claim holds) |
| 8 | setup_state purity | `grep -nE "from pymol\|from pymol.Qt" biochemeleon/setup_state.py` | **PASS** — 0 matches |
| 9 | cmd-coupling | `grep -c "from pymol import cmd" backup.py mutation.py game.py` | **PASS** — 1 / 1 / 1 (each cmd-coupled module present) |

### Headless Smoke Test (independent re-run)

Re-staged via `cmp`-verified byte-identical files (all 5 Phase 3 artifacts: `registry.py`, `mutation.py`, `backup.py`, `game.py`, `phase3_smoke.py` — all `identical` vs repo). Ran from the staged Windows-facing path:

```
cd tmp/bioCHEMeleon && timeout 100 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -50
```

**Result: 24/24 passed — ALL PASSED** (independently confirmed). The 24 checks span:
- Setup (4): backup name, backup private, backup in objects, backup count == orig
- C1 (2): public object list unchanged, count += 3
- C2 (2): 3 sentinel atoms, all segi=GAME and b=-999
- Q4 (1): existing ids stable across insert
- C3 (3): registry len == 3, per-rep counts, by_rep spheres len 1
- C4 happy (4): cleanup returned True, count back to orig, id-set matches orig, backup discarded
- Failure path (3): pre-restore count +1, abort returns True, count back to orig
- Q2 (1): single-call create is REPLACE (not append/double)
- PSE (4): hider survives reload, id stable across round-trip, registry reconstructs, rep is None

Diagnostics (informational, not checks — all match expected):
- `Q1: cmd.pseudoatom return value = None (type NoneType)` — confirms code correctly uses `cmd.identify`, not the return value.
- `PSE-DIAG: sentinel b after reload = [-999.0]` — sentinel value preserved across `.pse` round-trip.
- `PSE-DIAG: fetch_all_hider_ids('1ubq') = [('1ubq', 662)]` — non-empty, confirming the `b < 0` selector fix (#6) works at runtime.

### Human Verification Required

None. All 4 success criteria are verified at both the structural tier (code reading + grep wiring + 144 WSL unit tests) AND the runtime tier (headless PyMOL smoke 24/24 ALL PASSED, independently re-run). No item requires a human PyMOL GUI session — the headless smoke closes the WSL/Windows runtime gap for these cmd-only paths (per AGENTS.md). Qt/GUI smoke tests would need a human, but Phase 3 has NO Qt/GUI code paths (game.py/backup.py/mutation.py are pure cmd-coupled; registry.py is pure stdlib) — so nothing is left to a human.

### Gaps Summary

**No gaps.** Phase 3 delivers exactly what it promised:
- The mutation-safety mechanism (backup → mutate → remove/restore → verify intact) is proven at the runtime tier, not just syntax-checked.
- The hider registry (id-keyed, queryable, serializable, reconstructable-from-sentinels via DI) is complete and unit-tested (54 tests).
- The highest-uncertainty area (inserting pseudoatoms INTO an existing object, sentinel survival across `.pse` reload, the no-undo backup lifecycle) is de-risked with runtime-confirmed behavior — exactly the Phase 3 goal.
- All 6 runtime bugs the smoke surfaced are fixed in the shipped code (grep-confirmed: `b < 0` selector, `ID` uppercase, no x/y/z, two-step delete+create, `segi GAME` cleanup, DI iterate fn).

### Cross-Check Against 03-19 Executor's 03-VERIFICATION.md

My independent findings **AGREE** with the 03-19 executor's self-report on every point:
- 24/24 ALL PASSED: confirmed (independent re-run).
- 4/4 success criteria PASS: confirmed (code evidence + smoke).
- 6 artifacts exist + substantive + wired: confirmed.
- 6 key_links wired: confirmed (grep line numbers match).
- registry.py pure (0 `from pymol`): confirmed.
- 144 WSL unit tests green: confirmed (ran myself).
- 6 runtime fixes present in shipped code: confirmed (grep).
- 3/3 requirements (HIDER-01/02/06) satisfied: confirmed (REQUIREMENTS.md + code).

No regressions, no disagreements. The 03-19 executor's report is accurate.

---

## Conclusion

**Phase 3 is VERIFIED — PASSED.** The codebase delivers what Phase 3 promised. The mutation-safety + hider-registry foundation is proven correct at the runtime tier (headless PyMOL smoke 24/24 ALL PASSED, independently re-run) AND the structural tier (all artifacts substantive, all 6 key_links wired, registry pure, 144 WSL unit tests green, all 6 runtime fixes present in shipped code, no anti-patterns). The 3/3 Phase 3 requirements (HIDER-01/02/06) are satisfied.

**Phase 3 is ready for Phase 4 (MVP Core Loop — Sphere).** The foundation Phase 4 builds on — `insert_hider`/`fetch_all_hider_ids`/`cleanup_hiders` + `backup.snapshot`/`restore`/`verify_intact`/`discard` + `GameController.start`/`cleanup`/`abort_on_error`/`reconstruct_registry` + `HiderRegistry` CRUD/queries/serialize/reconstruct — is proven correct, not just syntax-checked. Phase 4 replaces the placeholder insert with real sphere generators; the mechanism those generators plug into is de-risked.

---

_Verified: 2026-08-07_
_Verifier: OpenCode (gsd-verifier) — independent_
_Method: read actual code + grep key_links + ran WSL gates + re-ran headless smoke (NOT trusted the 03-19 executor self-report; cross-checked it)_
