---
phase: 03-mutation-safety-hider-registry-foundation
plan: 15
subsystem: testing
tags: [pymol, smoke-test, headless-pymol, wsl-windows-bridge, hider-sentinel, pse-round-trip, b-factor-selector, dependency-injection]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation (plans 03-01..03-14)
    provides: "The full Phase 3 stack (registry.py pure layer, backup.py snapshot/restore/discard/verify_intact, mutation.py insert/fetch/cleanup, game.py GameController orchestrator) + smoke/phase3_smoke.py (setup + 4 criteria + failure path + Q1/Q2/PSE spikes + summary block) committed in 03-13/03-14"
provides:
  - "Runtime-verified Phase 3 smoke results: 24/24 ALL PASSED via headless Windows PyMOL (run-conda-pymol.bat -cq) from WSL — the 4 blocking criteria C1/C2/C3/C4 + failure-path restore + Q1/Q2/PSE spikes all confirmed at the runtime tier"
  - "Spike findings (verbatim): Q1 cmd.pseudoatom returns None (NoneType); Q2 single-call create IS REPLACE (n_after==n_before); PSE sentinel survives reload (len 1); PSE id stable across round-trip (pse_sent==[saved_id]); PSE b=-999.0 preserved; PSE reconstruct works after the b<0 fix (fetch returns [('1ubq',662)]); PSE rep=None"
  - "fetch_all_hider_ids selector corrected: b -999 -> b < 0 (PyMOL has no exact-match b-factor selector; b < 0 matches the -999.0 sentinel and is valid comparison syntax)"
  - "6 runtime discoveries documented for 03-16 (AGENTS rules) / 03-17 (PITFALLS) / 03-19 (VERIFICATION): iterate symbol ID uppercase, iterate has no coords (use iterate_state), redundant verify_intact on discarded backup (2x), /tmp path unresolvable on Windows, b-factor exact-match selector invalid"
affects:
  - 03-16 (AGENTS.md Phase 3 domain rules + grep gates — record Q1=None, Q2=REPLACE, PSE id-stable, ID-uppercase, no-coords-in-iterate, b<0 selector)
  - 03-17 (STATE.md Phase 3 complete + PITFALLS.md — resolve the Q1/Q2/PSE MEDIUM flags from 03-RESEARCH with the runtime-confirmed values)
  - 03-18 (final 12-gate regression suite — the smoke is now runtime-verified, no open runtime gaps)
  - 03-19 (03-VERIFICATION.md — criterion-by-criterion evidence + the 3 spike values feed the formal verification artifact)
  - 03-20 (03-SUMMARY.md — phase handoff to Phase 4 with Phase 3 fully de-risked at runtime)

# Tech tracking
tech-stack:
  added: []  # no new libraries; headless PyMOL via existing run-conda-pymol.bat + cmd.exe bridge (documented in AGENTS.md this checkpoint)
  patterns:
    - "Headless PyMOL from WSL: cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script> run from the staged Windows path (tmp/bioCHEMeleon/) — closes the WSL/Windows runtime gap for cmd-only scripts (no Qt/GUI); documented in AGENTS.md (b320316)"
    - "b-factor sentinel selector must use a comparison (b < 0), NEVER an exact match (b -999) — PyMOL has no exact-match b-factor selector; b -999 is malformed and silently matches nothing"
    - "cmd.iterate exposes atom id as uppercase ID (not lowercase id — the Python builtin); x/y/z coords are NOT exposed by iterate (need iterate_state) — count + identity tuple is sufficient for verify_intact per RESEARCH Q6 fallback"

key-files:
  created:
    - ".planning/phases/03-mutation-safety-hider-registry-foundation/03-15-SUMMARY.md (this file — the formal checkpoint artifact)"
  modified:
    - "biochemeleon/mutation.py (line 113: b -999 -> b < 0 in fetch_all_hider_ids; commit 6a15a29) [ALSO earlier: line ~98 comment id->ID via e38cff7]"
    - "biochemeleon/backup.py (verify_intact: dropped x/y/z from iterate tuple; commit 5ed6a13)"
    - "smoke/phase3_smoke.py (removed 2 redundant verify_intact calls on discarded backups [9e40e8a, 9b00657]; /tmp -> relative path [039bc6a]; added PSE-DIAG triage lines [cf702a1])"
    - "AGENTS.md (documented the headless PyMOL invocation method from WSL; commit b320316)"

key-decisions:
  - "b -999 -> b < 0 (NOT b == -999): PyMOL has no exact-match b-factor selector; b -999 emits 'Selector-Error: Malformed selection' and matches nothing. b < 0 is valid comparison syntax and matches -999.0 (the sentinel value). Kept the sentinel VALUE as -999 in docstrings (prose) — only the SELECTOR syntax changed."
  - "verify_intact identity tuple = (resn, resi, name, chain, segi) — DROPPED x/y/z: cmd.iterate does not expose coordinates (state-dependent; needs iterate_state). count gate + identity multiset is sufficient per RESEARCH Q6 fallback (cmd.create copies coords bit-for-bit, so a count+identity match implies structural identity)."
  - "Headless PyMOL via run-conda-pymol.bat -cq from WSL replaces the human-in-Windows-GUI step for cmd-only smoke scripts — the 03-15 checkpoint was closed WITHOUT any human PyMOL session (a WSL agent ran cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py from the staged Windows path). Qt/GUI paths still need a human."

patterns-established:
  - "Pattern: headless smoke from WSL — stage the package + script to tmp/bioCHEMeleon/ (wsl2win_cp.sh), then run `timeout 90 cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\<script>.py` from that directory (cd via workdir). Exit 0 = clean; nonzero = crash. This closes the runtime gap for cmd-only scripts."
  - "Pattern: b-factor sentinels are matched by comparison (b < 0 / b > N), never exact (b -999). The sentinel VALUE stays -999 (set in insert_hider + cleanup docstrings); only the SELECTOR uses the comparison form."

# Metrics
duration: ~1 min (this continuation: 105s for the b<0 fix + re-run + SUMMARY; the full checkpoint resolution spanned 2 sessions on 2026-08-06 — the prior session applied 5 fixes + diagnostic + AGENTS.md doc, this session applied the b<0 fix and reached 24/24)
started: 2026-08-06T20:26:14Z (this continuation; prior session earlier 2026-08-06)
completed: 2026-08-06T20:27:59Z
---

# Phase 3 Plan 15: Smoke Test Checkpoint (Headless PyMOL) Summary

**Phase 3 smoke test verified at runtime via headless Windows PyMOL from WSL — 24/24 ALL PASSED after a 1-line b-factor selector fix (b -999 -> b < 0) in mutation.fetch_all_hider_ids**

## Performance

- **Duration:** ~1 min (this continuation: 105s) — the full 03-15 checkpoint resolution spanned 2 sessions on 2026-08-06 (prior: 5 fixes + diagnostic + AGENTS.md doc; this: the b<0 fix + re-run + SUMMARY)
- **Started:** 2026-08-06T20:26:14Z (this continuation)
- **Completed:** 2026-08-06T20:27:59Z
- **Tasks:** 1 checkpoint task (human-verify) — resolved via 6 auto-fixes (Rule 1 bugs / Rule 3 blockers) + 1 diagnostic + 1 doc update across 2 sessions, reaching 24/24 ALL PASSED
- **Files modified:** 4 (biochemeleon/mutation.py, biochemeleon/backup.py, smoke/phase3_smoke.py, AGENTS.md) — committed in the 6 fix commits + 1 diagnostic + 1 docs commit (NOT in this SUMMARY commit; the SUMMARY commit contains only this SUMMARY.md)

## Accomplishments

- **03-15 checkpoint VERIFIED via headless PyMOL run.** The complete `smoke/phase3_smoke.py` ran headlessly from WSL (`cmd.exe /c C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py` from the staged `tmp/bioCHEMeleon/` path) and reached **24/24 ALL PASSED, exit 0** — with NO human PyMOL session required (the headless bridge documented in AGENTS.md this checkpoint closed the runtime gap for cmd-only scripts).
- **All 4 blocking criteria confirmed at the runtime tier.** C1 (public object list unchanged + count += 3), C2 (3 sentinel atoms, all segi=GAME + b=-999), C3 (registry len 3 + per-rep counts spheres/sticks/lines=1 cartoon/ribbon=0 + by_rep spheres len 1), C4 (cleanup returned True + count back to orig + id-set matches orig + backup discarded) — every criterion check prints PASS. The WSL gate suite (py_compile + 144 unit tests + grep Pitfall-1/11) only verifies SYNTAX + pure-layer behavior; this checkpoint is the only place the cmd-coupled modules (backup/mutation/game) are exercised at runtime.
- **Failure path confirmed.** `gc2.abort_on_error()` returns True (the delete+create two-step restore from backup works), count back to orig after abort — criterion 4's alternate (failure-path) holds at runtime, so the RESEARCH Q2 "never single-call create(existing, backup)" sidestep landed atom-for-atom.
- **All 3 research spikes recorded verbatim.** Q1 (cmd.pseudoatom return value = None / NoneType — confirms RESEARCH §Q1; code correctly uses cmd.identify(mode=0)), Q2 (single-call create IS REPLACE — RESEARCH §Q2 MEDIUM flag resolved: no doubling, delete+create in 03-05/03-12 is correct/unambiguous), PSE (sentinel survives reload + id stable + b=-999.0 preserved + reconstruct works after the b<0 fix + rep=None). These feed 03-16 (AGENTS rules), 03-17 (PITFALLS), 03-19 (VERIFICATION).
- **The b -999 selector bug fixed.** `fetch_all_hider_ids` used `segi GAME and b -999` — PyMOL has no exact-match b-factor selector; `b -999` is malformed and silently matched nothing, so reconstruct_registry produced an empty registry (2 PSE checks FAILED). Changed to `b < 0` (valid comparison syntax, matches -999.0); `fetch_all_hider_ids('1ubq')` now returns `[('1ubq', 662)]` and both PSE-reconstruct checks PASS.

## Task Commits

The 03-15 checkpoint was resolved across 2 sessions via 8 atomic commits (the checkpoint task had no single "task commit" — it was an iterative triage; each fix is its own commit):

1. **fix(03-15): iterate symbol id->ID** — `e38cff7` (fix — library bug: PyMOL iterate exposes uppercase ID)
2. **fix(03-15): verify_intact drop x/y/z** — `5ed6a13` (fix — library bug: iterate has no coords)
3. **fix(03-15): smoke remove redundant verify_intact call (backup already discarded by cleanup)** — `9e40e8a` (fix — smoke-test bug: line 57)
4. **fix(03-15): smoke remove redundant verify_intact on discarded backup (failure path twin of 9e40e8a)** — `9b00657` (fix — smoke-test bug: line 66)
5. **fix(03-15): smoke use relative phase3_test.pse path (Windows PyMOL cannot resolve /tmp)** — `039bc6a` (fix — smoke-test bug: /tmp path)
6. **fix(03-15): smoke guard PSE rep check + add reconstruct triage diagnostic (b -999 selector)** — `cf702a1` (fix/diagnostic — added PSE-DIAG lines that confirmed the sentinel EXISTS but the b -999 selector fails to match it)
7. **docs(03): document headless PyMOL invocation from WSL (run-conda-pymol.bat -cq)** — `b320316` (docs — AGENTS.md headless method)
8. **fix(03-15): correct b-factor selector in fetch_all_hider_ids (b -999 -> b < 0; PyMOL has no exact-match b selector)** — `6a15a29` (fix — library bug: the b-factor selector; THIS continuation)

**Plan metadata:** `docs(03-15)` (this SUMMARY commit, immediately following).

## Files Created/Modified

- `biochemeleon/mutation.py` — line 113: `f"{object} and segi GAME and b -999"` -> `f"{object} and segi GAME and b < 0"` in `fetch_all_hider_ids` (commit 6a15a29; the 1-line fix that unblocked the 2 PSE-reconstruct checks). Earlier: line ~98 docstring `id` -> `ID` (commit e38cff7).
- `biochemeleon/backup.py` — `verify_intact`: dropped `x, y, z` from the iterate tuple (`(resn, resi, name, chain, segi, x, y, z)` -> `(resn, resi, name, chain, segi)`); count + identity multiset is sufficient per RESEARCH Q6 fallback (commit 5ed6a13).
- `smoke/phase3_smoke.py` — removed 2 redundant `verify_intact` calls on backups already discarded by `cleanup()`/`abort_on_error()` (lines 57 + 66, commits 9e40e8a + 9b00657); changed `cmd.save("/tmp/phase3_test.pse")` -> `cmd.save("phase3_test.pse")` (commit 039bc6a); added 2 `PSE-DIAG` print lines to triage the reconstruct failure (commit cf702a1). The smoke itself is UNCHANGED by this continuation (only mutation.py was touched here).
- `AGENTS.md` — documented the headless PyMOL invocation method from WSL (`cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` from the staged Windows path; commit b320316) — this closes the WSL/Windows runtime gap for cmd-only scripts and is how this checkpoint was closed without a human PyMOL session.
- `.planning/phases/03-mutation-safety-hider-registry-foundation/03-15-SUMMARY.md` — this file (the formal checkpoint artifact).

## Decisions Made

- **b -999 -> b < 0 (the selector), KEEP b=-999 (the sentinel value).** PyMOL has no exact-match b-factor selector: `b -999` emits "Selector-Error: Malformed selection" and matches nothing (silent — returns `[]`, no exception). `b < 0` is valid comparison syntax and matches the -999.0 sentinel value. The sentinel VALUE stays -999 everywhere it appears in docstrings (prose: `segi='GAME'` + `b=-999`); only the SELECTOR uses the comparison form. The user approved Option A (fix in mutation.py, re-run headless, close out 03-15) — this is a 1-line selector-SYNTAX correction, NOT a logic/architecture change.
- **verify_intact identity tuple = (resn, resi, name, chain, segi) — no x/y/z.** `cmd.iterate` does NOT expose coordinates (they are state-dependent; `iterate_state` would be needed). The count gate + identity multiset is sufficient per RESEARCH Q6 fallback: `cmd.create` copies coordinates bit-for-bit, so a matching atom count + matching (resn, resi, name, chain, segi) multiset implies full structural identity (coordinates included). This avoids a state-dependent iterate call.
- **Close the checkpoint via headless PyMOL, not a human GUI session.** AGENTS.md now documents that `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` runs PyMOL headlessly from WSL (the `-cq` flags = command-line, quiet, no GUI). The smoke script is pure `pymol.cmd.*` (no Qt, no interactive viewer), so it runs headlessly. This closed 03-15 without any human action — a WSL agent ran the smoke, captured 24/24 ALL PASSED exit 0, and wrote this SUMMARY. Qt/GUI paths (the PluginDialog, Setup tab, click-to-find loop) STILL need a human in a real PyMOL session — only cmd-only scripts are headless-runnable.

## Deviations from Plan

The 03-15 plan was a single `checkpoint:human-verify` task. The plan expected a human to run the smoke in Windows PyMOL and report results. Instead, the checkpoint uncovered **6 runtime bugs** that the WSL gate suite (py_compile + unit tests + grep gates) could not catch — each was auto-fixed (Rule 1 bug / Rule 3 blocker) and re-run, iterating until 24/24 ALL PASSED. These are the deviations; they are all auto-fixes (no architectural changes, no scope creep).

### Auto-fixed Issues

**1. [Rule 1 - Bug] iterate symbol `id` -> `ID` (library bug)**
- **Found during:** 03-15 checkpoint — first headless run crashed at the `cmd.iterate(..., "stored.append((model, id))")` call in `fetch_all_hider_ids`.
- **Issue:** PyMOL's `cmd.iterate` exposes the atom id as the uppercase symbol `ID`, NOT lowercase `id` (which is the Python builtin and resolves to the builtin function inside the iterate expression). The 03-RESEARCH.md symbol table had `ID` uppercase, but the code sketches in 03-06 used lowercase `id` (a transcription error). Lowercase `id` either errored or appended the wrong value.
- **Fix:** Changed `"stored.append((model, id))"` -> `"stored.append((model, ID))"` in `fetch_all_hider_ids` (mutation.py) AND `"stored.append((id, segi, b))"` -> `"stored.append((ID, segi, b))"` in the smoke C2 iterate + `"stored.append(id)"` -> `"stored.append(ID)"` in the PSE iterate.
- **Files modified:** biochemeleon/mutation.py (line ~98 comment context), smoke/phase3_smoke.py (C2 + PSE iterate expressions)
- **Verification:** Headless re-run advanced past the iterate crash.
- **Committed in:** `e38cff7`
- **Lesson:** PyMOL iterate symbols are case-sensitive and UPPERCASE (`ID`, `MODEL`, `RESN`, etc.) — the 03-RESEARCH symbol table is authoritative; code sketches that lowercase them are transcription errors. 03-16 should add an AGENTS rule + grep gate for `id` vs `ID` in iterate expressions.

**2. [Rule 1 - Bug] `verify_intact` dropped x/y/z from iterate tuple (library bug)**
- **Found during:** 03-15 checkpoint — headless run crashed at `backup.verify_intact` because `cmd.iterate` does not expose `x, y, z` coordinates.
- **Issue:** The 03-08 implementation built the identity tuple as `(resn, resi, name, chain, segi, x, y, z)` per the RESEARCH doc's tuple spec. But `cmd.iterate` only exposes atom-level properties (not state-dependent coordinates); `x/y/z` need `cmd.iterate_state`. The tuple spec in the RESEARCH doc was wrong about iterate exposing coords.
- **Fix:** Dropped `x, y, z` from the tuple -> `(resn, resi, name, chain, segi)`. Count gate + identity multiset is sufficient per RESEARCH Q6 fallback (`cmd.create` copies coords bit-for-bit, so count+identity match implies structural identity).
- **Files modified:** biochemeleon/backup.py (verify_intact iterate tuples — both target + backup)
- **Verification:** Headless re-run advanced past `verify_intact` (C4 cleanup returned True).
- **Committed in:** `5ed6a13`
- **Lesson:** `cmd.iterate` exposes atom properties only; coordinates are state-dependent (`cmd.iterate_state`). For structure-identity checks, count + (resn, resi, name, chain, segi) multiset suffices because `cmd.create` is a bit-for-bit copy. 03-17 should note this in PITFALLS (resolve the RESEARCH tuple spec).

**3. [Rule 3 - Blocking] smoke line 57 redundant `verify_intact` on discarded backup (smoke-test bug)**
- **Found during:** 03-15 checkpoint — headless run crashed AFTER `gc.cleanup()` (C4 happy path passed) when the smoke re-called `backup.verify_intact` on the backup that `cleanup()` had already discarded.
- **Issue:** `gc.cleanup()` already runs `backup.verify_intact` internally (returns its bool as `intact`) and then calls `backup.discard(self._backup_name)` (deletes the backup). The smoke then re-called `verify_intact` on the now-deleted backup object -> `CmdException` (object not found). Line 54 (`check("C4: cleanup returned True (intact)", intact is True)`) already proves `verify_intact` passed; the re-call was redundant.
- **Fix:** Removed the redundant `verify_intact` re-call on line 57.
- **Files modified:** smoke/phase3_smoke.py (line 57)
- **Verification:** Headless re-run advanced past C4.
- **Committed in:** `9e40e8a`
- **Lesson:** The smoke must not re-invoke cmd-coupled helpers on objects the orchestrator already discarded — `cleanup()`/`abort_on_error()` own the backup lifecycle. The smoke should assert the orchestrator's RETURN value, not re-derive it.

**4. [Rule 3 - Blocking] smoke line 66 redundant `verify_intact` on discarded backup — failure-path twin (smoke-test bug)**
- **Found during:** 03-15 checkpoint — headless run crashed at the failure-path twin of deviation 3 (same class, different code path).
- **Issue:** `gc2.abort_on_error()` already runs `backup.restore` (delete+create) + `backup.discard` internally (the backup is gone). The smoke re-called `verify_intact` on the discarded backup -> `CmdException`. `check("failure-path abort returns True", ok is True)` (line 64) already proves restore worked.
- **Fix:** Removed the redundant `verify_intact` re-call on line 66.
- **Files modified:** smoke/phase3_smoke.py (line 66)
- **Verification:** Headless re-run advanced past the failure path.
- **Committed in:** `9b00657`
- **Lesson:** Same as deviation 3 — both cleanup paths (happy + failure) discard the backup; the smoke must not touch it afterward. Mirror fix.

**5. [Rule 3 - Blocking] smoke `/tmp/phase3_test.pse` -> `phase3_test.pse` (smoke-test bug)**
- **Found during:** 03-15 checkpoint — headless run crashed at `cmd.save("/tmp/phase3_test.pse")` because Windows PyMOL cannot resolve the WSL/Linux `/tmp` path.
- **Issue:** The PSE round-trip spike saved to `/tmp/phase3_test.pse` (a WSL convention). Windows PyMOL resolves paths against the Windows filesystem; `/tmp` is not a valid Windows path -> save/load failed. (The cmd.exe cwd is the staged `tmp/bioCHEMeleon/` Windows path; a relative path resolves there.)
- **Fix:** Changed `cmd.save("/tmp/phase3_test.pse")` -> `cmd.save("phase3_test.pse")` and `cmd.load("/tmp/phase3_test.pse")` -> `cmd.load("phase3_test.pse")` (relative path, resolves against the cmd.exe cwd).
- **Files modified:** smoke/phase3_smoke.py (PSE save + load lines)
- **Verification:** Headless re-run advanced to the PSE round-trip section.
- **Committed in:** `039bc6a`
- **Lesson:** Windows PyMOL cannot resolve WSL/Linux paths (`/tmp`, `/home/...`). Use relative paths (resolved against the cmd.exe cwd) or Windows-style paths (`C:\\...`). The `demos.to_windows_path()` WSL guard converts `/mnt/c/...` -> `C:\\...` for this reason — smoke scripts should use relative paths when run from the staged directory.

**6. [Rule 1 - Bug] `b -999` -> `b < 0` in `fetch_all_hider_ids` selector (library bug — the load-bearing fix)**
- **Found during:** 03-15 checkpoint — the headless run reached 22/24 PASS but the 2 PSE-reconstruct checks FAILED: `fetch_all_hider_ids` returned `[]` (empty), so `reconstruct_registry` produced an empty registry.
- **Issue:** `mutation.py:113` used `cmd.iterate(f"{object} and segi GAME and b -999", ...)`. PyMOL has NO exact-match b-factor selector: `b -999` is INVALID syntax (b-factor selectors require comparisons: `b < 0`, `b > 50`). `b -999` emits "Selector-Error: Malformed selection" and silently matches nothing -> `fetch_all_hider_ids` returns `[]` -> reconstruct is empty -> both PSE-reconstruct checks FAIL. The diagnostic (commit cf702a1) confirmed the sentinel atom EXISTS after .pse reload (`segi GAME` finds it; `b=-999.0` is preserved) — only the `b -999` selector failed to match it.
- **Fix:** Changed the selector `f"{object} and segi GAME and b -999"` -> `f"{object} and segi GAME and b < 0"`. `b < 0` is valid PyMOL comparison syntax and matches `-999.0` (the sentinel b value). Kept the rest of the call identical (`"stored.append((model, ID))"` expression with `ID` uppercase from deviation 1, `space={'stored': out}` hygiene, return of the `out` list). The docstring already describes the sentinel as `segi='GAME'` + `b=-999` (the VALUES in prose) — unchanged (it never mentioned the selector syntax `b -999` literally).
- **Files modified:** biochemeleon/mutation.py (line 113 — the 1-line fix)
- **Verification:** Headless re-run reached 24/24 ALL PASSED: `PSE-DIAG: fetch_all_hider_ids('1ubq') = [('1ubq', 662)]` (non-empty), `PASS: PSE: registry reconstructs from sentinels`, `PASS: PSE: reconstructed rep is None (sentinel carries no rep)`, exit 0.
- **Committed in:** `6a15a29`
- **Lesson:** PyMOL b-factor selectors are COMPARISONS (`b < 0`, `b > N`, `b <= X`), NEVER exact matches (`b -999`). A malformed selector silently matches nothing (no exception) — this is a particularly dangerous failure mode because the count looks plausible (0 hiders found) rather than crashing. 03-16 should add an AGENTS rule: b-factor sentinels are matched by comparison; the sentinel VALUE stays -999 (set in insert_hider + cleanup docstrings), only the SELECTOR uses `b < 0`.

---

**Total deviations:** 6 auto-fixed (4 library bugs [1, 2, 6 + the load-bearing fix], 3 smoke-test bugs [3, 4, 5]) — all Rule 1 (bug) or Rule 3 (blocker). Plus 1 diagnostic commit (cf702a1, added PSE-DIAG triage lines — not a deviation, a smoke enhancement to triage the reconstruct failure) and 1 docs commit (b320316, AGENTS.md headless method — not a deviation, a documentation update).
**Impact on plan:** All auto-fixes were necessary to reach 24/24 ALL PASSED — the WSL gate suite (py_compile + 144 unit tests + grep Pitfall-1/11) verified SYNTAX + pure-layer behavior but could not catch any of these 6 runtime bugs (iterate symbol case, iterate coord exposure, backup lifecycle re-calls, Windows path resolution, b-factor selector syntax). No scope creep — every fix was a 1-line correction to existing code (no new functions, no logic/architecture changes). This is exactly why the 03-15 checkpoint exists: the runtime tier is the only place these bugs surface.

## Issues Encountered

The 03-15 checkpoint required **3 fix iterations** to reach 24/24 ALL PASSED — each headless run crashed at a NEW spot, each fix unblocked the next. This is the expected behavior of a runtime checkpoint that the WSL tier cannot simulate:

- **Iteration 1 (prior session):** crashed at `cmd.iterate(..., "stored.append((model, id))")` — lowercase `id` (deviation 1, e38cff7). Fixed -> re-run.
- **Iteration 2 (prior session):** crashed at `backup.verify_intact` — `x, y, z` not exposed by iterate (deviation 2, 5ed6a13). Fixed -> re-run.
- **Iteration 3 (prior session):** crashed at the smoke's redundant `verify_intact` on the discarded backup (deviation 3, line 57, 9e40e8a) AND its failure-path twin (deviation 4, line 66, 9b00657) AND the `/tmp` path (deviation 5, 039bc6a). Fixed all three (plus added the PSE-DIAG triage lines, cf702a1, to diagnose the next failure) -> re-run reached 22/24 PASS but the 2 PSE-reconstruct checks FAILED.
- **Iteration 4 (this continuation):** the 22/24 run's PSE-DIAG lines (`cf702a1`) confirmed the sentinel atom EXISTS after .pse reload but `b -999` matches nothing. Applied the load-bearing fix: `b -999` -> `b < 0` (deviation 6, 6a15a29) -> re-run reached **24/24 ALL PASSED, exit 0**.

The checkpoint existed precisely because the WSL tier (python3.6 syntax + pure-layer unit tests + grep gates) cannot exercise `cmd.iterate`, `cmd.pseudoatom`, `cmd.create`, `.pse` save/load, or the backup lifecycle. Every one of the 6 bugs is a PyMOL-runtime behavior that no WSL gate could catch. The 2-session iteration is the cost of closing the runtime gap; the payoff is that 03-16/03-17/03-19 now have verified runtime values to codify (not research guesses).

## User Setup Required

None — this checkpoint was closed WITHOUT any human PyMOL session. The headless PyMOL invocation method (documented in AGENTS.md this checkpoint, commit b320316) lets a WSL agent run cmd-only smoke scripts directly:

```bash
# 1. Stage the package + script to the Windows-facing path:
bash wsl2win_cp.sh                                          # biochemeleon/ -> tmp/bioCHEMeleon/biochemeleon/
mkdir -p tmp/bioCHEMeleon/smoke && cp smoke/phase3_smoke.py tmp/bioCHEMeleon/smoke/
# 2. Run headlessly from the staged Windows path (no GUI):
cd tmp/bioCHEMeleon && timeout 90 cmd.exe /c "C:\\src\\run-conda-pymol.bat -cq smoke\\phase3_smoke.py" 2>&1 | tail -50
# 3. Exit 0 = clean; nonzero = crash.
```

Qt/GUI paths (the PluginDialog, Setup tab, click-to-find loop in Phase 4+) STILL need a human in a real PyMOL session — only pure `pymol.cmd.*` scripts (no Qt, no interactive viewer) are headless-runnable. The 03-15 smoke is pure cmd, so it ran headlessly.

## Next Phase Readiness

- **Phase 3 smoke VERIFIED at runtime.** 24/24 ALL PASSED via headless Windows PyMOL — all 4 blocking criteria (C1/C2/C3/C4) + failure-path restore + Q1/Q2/PSE spikes confirmed. The cmd-coupled modules (backup.py, mutation.py, game.py) are now runtime-verified, not just syntax-checked.
- **`reconstruct_registry` works.** The `b < 0` selector matches the -999.0 sentinel; `fetch_all_hider_ids('1ubq')` returns `[('1ubq', 662)]` after .pse reload; `gc3.reconstruct_registry()` rebuilds a 1-record registry with `rep=None` (the sentinel carries no rep — RESEARCH Open Risk 6 confirmed; Phase 8 .bcm sidecar reconciles). The DI design (registry stays pure, game.py injects the iterate fn) holds at runtime.
- **Ready for 03-16 (AGENTS.md Phase 3 domain rules + grep gates):** record Q1=None (pseudoatom return value, never use as id), Q2=REPLACE (single-call create is replace, delete+create still correct/unambiguous), PSE id-stable (Pitfall 4 holds at runtime), ID-uppercase (iterate symbol), no-coords-in-iterate (use count+identity), b<0 selector (b-factor sentinels matched by comparison, value stays -999).
- **Ready for 03-17 (STATE.md Phase 3 complete + PITFALLS.md):** resolve the Q1/Q2/PSE MEDIUM flags from 03-RESEARCH with the runtime-confirmed values (Q1=None/NoneType, Q2=REPLACE/no-doubling, PSE sentinel+id survive reload, b=-999.0 preserved). The 6 runtime discoveries become PITFALLS entries (iterate symbol case, iterate coord exposure, Windows path resolution, b-factor selector syntax).
- **Ready for 03-18 (final 12-gate regression suite):** the runtime tier has no open gaps — the smoke is 24/24. The WSL 12-gate suite runs clean (py_compile all + 144 tests + Pitfall-1/11 ZERO + mutation.py gates: fetch_all_hider_ids=1, space={'stored'=1, segi GAME=4 [>=2], b -999=0, b < 0=1, completeness=3).
- **Ready for 03-19 (03-VERIFICATION.md):** criterion-by-criterion evidence (C1 object-list-unchanged + count+=3, C2 3-sentinels segi=GAME+b=-999, C3 registry-queries + per-rep-counts, C4 cleanup-intact + failure-restore) + the 3 spike values (Q1=None/NoneType, Q2=REPLACE, PSE sentinel-survives + id-stable + b-preserved + reconstruct-works + rep=None) feed the formal verification artifact.
- **Ready for 03-20 (03-SUMMARY.md):** Phase 3 handoff to Phase 4 with the highest-risk area (safe object mutation + hider registry) fully de-risked at runtime — the foundation Phase 4 (sphere MVP core loop) builds on is proven.
- **Blockers/concerns:** None. The b<0 fix is committed (6a15a29); the smoke is 24/24; the WSL gates are green. The headless method is documented for future cmd-only smoke tests (Phase 4+ can reuse it for any pure-cmd verification).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
