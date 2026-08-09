---
phase: 05-line-stick-and-cartoon-generators
plan: 09
subsystem: testing
tags: [pymol, ribbon, cartoon, rep-forwarding, headless-smoke, gap-closure, rep-inheritance]

# Dependency graph
requires:
  - phase: 05-line-stick-and-cartoon-generators (plan 05)
    provides: insert_cartoon_hider (the function with the hardcoded 'cartoon' show call at line 478) + the 05-05 human-verify that found ribbon hiders render in cartoon (gap #3)
  - phase: 05-line-stick-and-cartoon-generators (plan 04)
    provides: smoke/phase5_smoke.py — the headless smoke extended here with section 5c
  - phase: 05-line-stick-and-cartoon-generators (plan 07)
    provides: the gap-closure precedent (minimal 1-file fix + smoke section + headless smoke as the gate, autonomous, no human-verify checkpoint) this plan mirrors
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: mutation.cleanup_hiders (used by section 5c cleanup) + the sentinel design (segi GAME + b<0) that section 5c relies on
provides:
  - Ribbon rep is now playable: a `ribbon` rep request flows `_on_start` -> `hider_specs` -> `game.start` loop -> `insert_hider_for_rep(rep='ribbon')` -> `insert_cartoon_hider(rep='ribbon')` -> `cmd.show('ribbon', GAME)`. The 05-05 gap #3 (ribbon hiders rendered in cartoon) is closed.
  - `insert_cartoon_hider` now accepts a `rep='cartoon'` keyword (default preserves existing cartoon behavior — no regression for existing callers) and the `insert_hider_for_rep` dispatcher forwards `rep=rep` to it. The `cmd.show` call is parameterized (`cmd.show(rep, ...)`, was hardcoded `cmd.show('cartoon', ...)`).
  - smoke/phase5_smoke.py section 5c — verifies a cartoon-geometry hider inserted with `rep='ribbon'` renders in RIBBON (not cartoon): 8 new checks, 41/41 ALL PASSED, exit 0. Includes the corrected regression guard (ribbon on GAME atoms but NOT on the rest of the polymer — proves rep= forwarding).
affects: [Phase 6 (hint/reveal — the ribbon path now works end-to-end), Phase 11 (Alt-conf Cartoon/Ribbon Hider — the rep-forwarding fix is a prerequisite for any ribbon work), any future rep-parameterized show call]

# Tech tracking
tech-stack:
  added: []  # no new libs; 3-change parameterization + a smoke section
  patterns:
    - "Rep parameterization via keyword default: `def f(..., rep='cartoon')` + `cmd.show(rep, ...)` lets one function serve two reps (cartoon + ribbon) without touching callers (the default preserves existing behavior). The dispatcher forwards the rep it already receives: `f(..., rep=rep)`. Minimal, low-risk — no `cmd.create`, no state manipulation, no coordinate changes."
    - "PyMOL default-rep inheritance: a freshly-fetched protein (e.g. 1ubq) has `cartoon` shown by DEFAULT on its polymer (~602 atoms), but NOT `ribbon`. Newly-attached polymer residues INHERIT the cartoon rep from the polymer. So `count_atoms('obj and segi GAME and rep cartoon')` is nonzero for a cartoon-geometry hider REGARDLESS of which rep the show call used — cartoon comes from inheritance, not the explicit `cmd.show`. A regression guard that asserts `rep cartoon == 0` on GAME atoms is therefore WRONG. The correct distinguishing assertion for rep= forwarding: ribbon is on GAME atoms but NOT on the rest of the polymer (ribbon is not a default rep, so it can only come from the explicit `cmd.show('ribbon', GAME)` call)."
    - "Apples-to-oranges diag trap: `count_atoms('... and name CA and rep ribbon')` (CA only, =2) vs `count_atoms('... and rep cartoon')` (all atoms, =13) compare different atom sets. Always use the same atom filter (or none) when comparing two reps, or the numbers mislead."

key-files:
  created: []
  modified:
    - biochemeleon/mutation.py — insert_cartoon_hider signature: added `rep='cartoon'` keyword (line 254); show call: `cmd.show('cartoon', ...)` -> `cmd.show(rep, ...)` (line 479) + comment updated; insert_hider_for_rep dispatcher: cartoon/ribbon branch forwards `rep=rep` (line 536). 3 changes total, no other function touched. 619 -> 620 lines.
    - smoke/phase5_smoke.py — new section 5c (RIBBON REP SUPPORT) inserted between section 5b and section 6: 65 lines, 8 new ribbon checks. The regression guard was corrected (Rule 1 fix: the plan's `rep cartoon == 0` check was wrong — cartoon is inherited from 1ubq's default polymer rep). 277 -> 331 lines.

key-decisions:
  - "Minimal fix: 3 changes in mutation.py (signature +rep='cartoon', show call cmd.show(rep, ...), dispatcher rep=rep). No `__init__.py` change — the (chain, terminus_resi, is_c_terminus) payload already travels with rep via hider_specs.append((term, rep)) in game.start / _on_start; the dispatcher already receives rep, it just wasn't forwarding it. This mirrors the 05-07 gap-closure precedent (minimal 1-file fix + smoke section + headless smoke as the gate)."
  - "The regression guard in the smoke was CORRECTED (Rule 1 — smoke-check bug): the plan's `count_atoms('... and segi GAME and rep cartoon') == 0` check assumed cartoon on GAME atoms comes ONLY from the explicit show call. Empirical diagnosis (diag_5c.py, since removed) proved a freshly-fetched 1ubq polymer has cartoon shown by DEFAULT (602 atoms), so newly-attached GAME residues inherit cartoon — the check would ALWAYS fail. Replaced with `count_atoms('... and segi GAME and rep ribbon') > 0 and count_atoms('... and polymer and not segi GAME and rep ribbon') == 0` which correctly distinguishes old (hardcoded 'cartoon' -> ribbon=0) vs new (rep= forwarding -> ribbon>0 on GAME only, polymer ribbon=0). The fix in mutation.py is verified correct by `GAME_rep_ribbon=2` (the old code would give 0)."
  - "No `__init__.py` change needed — confirmed via `git diff --name-only biochemeleon/__init__.py` (empty). The rep forwarding closes at the dispatcher level."

patterns-established:
  - "Rep forwarding via keyword default: parameterize a show call with `rep=<default>` so one function serves multiple reps without touching existing callers; the dispatcher forwards the rep it already receives."
  - "PyMOL rep-inheritance awareness for regression guards: when asserting on `rep <X>` counts for newly-attached polymer residues, account for the polymer's DEFAULT reps (cartoon is default for fetched proteins; ribbon is not). A `rep <default-rep> == 0` check on GAME atoms is unsound. Prefer a check that isolates the explicit show call's effect (e.g. ribbon on GAME but not on the polymer)."

# Metrics
duration: 13min
completed: 2026-08-09
---

# Phase 5 Plan 09: Ribbon Rep Support Gap Closure Summary

**Parameterized `insert_cartoon_hider`'s show call (`cmd.show('cartoon', ...)` -> `cmd.show(rep, ...)`) + dispatcher `rep=rep` forwarding, closing the 05-05 ribbon gap so `ribbon` hiders render in RIBBON (not cartoon); smoke 41/41 ALL PASSED with a corrected regression guard.**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-08-09T15:18:03Z
- **Completed:** 2026-08-09T15:31:24Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Closed the 05-05 gap #3 (ribbon hiders rendered in cartoon): `insert_cartoon_hider` now accepts `rep='cartoon'` (default preserves existing behavior) and the `insert_hider_for_rep` dispatcher forwards `rep=rep`. A `ribbon` rep request now flows end-to-end: `_on_start` -> `hider_specs` -> `game.start` -> `insert_hider_for_rep(rep='ribbon')` -> `insert_cartoon_hider(rep='ribbon')` -> `cmd.show('ribbon', GAME)`. The `ribbon` rep is now playable.
- Extended `smoke/phase5_smoke.py` with section 5c (RIBBON REP SUPPORT): inserts a cartoon-geometry hider with `rep='ribbon'` and verifies it renders in RIBBON — 8 new checks, all PASS. Headless smoke 41/41 ALL PASSED, exit 0.
- Diagnosed and corrected a flawed regression guard in the plan's smoke section (Rule 1 — smoke-check bug): the plan's `count_atoms('... and segi GAME and rep cartoon') == 0` check assumed cartoon on GAME atoms comes only from the explicit show call. A quick diagnostic (since removed) proved a freshly-fetched 1ubq polymer has `cartoon` shown by DEFAULT (~602 atoms) and NO `ribbon` — so newly-attached GAME residues INHERIT cartoon from the polymer, making the check fail regardless of the fix. Replaced with a correct guard: ribbon is on GAME atoms but NOT on the rest of the polymer (proving `cmd.show('ribbon', GAME)` fired — rep forwarded). The diag confirms: `GAME_rep_ribbon=2, GAME_rep_cartoon=13 (inherited), polymer_rep_ribbon=0`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Parameterize insert_cartoon_hider rep + forward rep from dispatcher** - `2d487af` (fix)
2. **Task 2: Add ribbon rep smoke section 5c (rep forwarding verification)** - `c04a813` (test)

## Files Created/Modified
- `biochemeleon/mutation.py` - `insert_cartoon_hider`: signature `segi='GAME', b=-999.0):` -> `segi='GAME', b=-999.0, rep='cartoon'):` (default preserves existing cartoon behavior); show call `cmd.show('cartoon', _id_sele(all_game_ids))` -> `cmd.show(rep, _id_sele(all_game_ids))` (step-10 comment updated to explain the 05-09 parameterization); `insert_hider_for_rep` cartoon/ribbon branch: `handle=handle)` -> `handle=handle, rep=rep)`. 3 changes, no other function touched.
- `smoke/phase5_smoke.py` - New section 5c (RIBBON REP SUPPORT): re-derive N-terminus -> insert cartoon-geometry hider with `rep='ribbon'` -> assert GAME C-alpha in rep ribbon (>0, >=2) -> assert rep= forwarded (ribbon on GAME but NOT on polymer) -> assert clean sentinel (fetch_all_hider_ids += 1) -> cleanup restores. 8 new checks. Regression guard corrected (plan's `rep cartoon == 0` was unsound — cartoon is inherited).

## Decisions Made
- **Rule 1 — smoke-check bug (corrected, not a mutation.py bug):** The plan's regression guard `count_atoms('... and segi GAME and rep cartoon') == 0` was based on a false assumption (that cartoon on GAME atoms comes only from the explicit show call). Empirical diagnosis proved cartoon is INHERITED from 1ubq's default polymer rep (PyMOL shows cartoon by default for fetched proteins). Replaced with a correct guard that isolates the explicit show call's effect. The fix in mutation.py is verified correct (`GAME_rep_ribbon=2`; the old hardcoded 'cartoon' would give 0). See Deviations for details.
- **No `__init__.py` change:** The `(chain, terminus_resi, is_c_terminus)` payload already travels with `rep` via `hider_specs.append((term, rep))`; the dispatcher already receives `rep` — it just wasn't forwarding it. The fix closes at the dispatcher level.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected flawed regression guard in smoke section 5c**
- **Found during:** Task 2 (headless smoke run — the `rep cartoon == 0` check FAILED: `rep_cartoon=13`)
- **Issue:** The plan's regression guard asserted `count_atoms("obj and segi GAME and rep cartoon") == 0` to verify `rep='ribbon'` was forwarded. The assumption was that cartoon on GAME atoms comes ONLY from the explicit `cmd.show` call. Empirical diagnosis (a throwaway `smoke/diag_5c.py`, since removed via `git clean`) proved a freshly-fetched 1ubq polymer has `cartoon` shown by DEFAULT (~602 atoms) and NO `ribbon`. Newly-attached GAME residues (part of the polymer) INHERIT cartoon from the polymer, so `rep cartoon` on GAME atoms is nonzero regardless of which rep the show call used. The check would ALWAYS fail for a fetched protein — it was unsound.
- **Fix:** Replaced the check with `count_atoms("obj and segi GAME and rep ribbon") > 0 and count_atoms("obj and polymer and not segi GAME and rep ribbon") == 0`. This correctly distinguishes old vs new behavior: with the old hardcoded `'cartoon'`, `GAME rep ribbon` would be 0 (first conjunct FAILS); with the new `rep=rep` forwarding, `GAME rep ribbon > 0` (ribbon explicitly shown) AND `polymer-not-GAME rep ribbon == 0` (ribbon is not a default rep, so it can only come from the explicit `cmd.show('ribbon', GAME)` call). Updated the comment block to document the inheritance finding and updated the diag line to print `GAME_rep_ribbon`, `GAME_rep_cartoon`, and `polymer_rep_ribbon`.
- **Files modified:** `smoke/phase5_smoke.py` (section 5c only — no existing section modified)
- **Verification:** Headless smoke 41/41 ALL PASSED, exit 0. Diag: `GAME_rep_ribbon=2 GAME_rep_cartoon=13 polymer_rep_ribbon=0` — confirms the fix (ribbon on GAME) and the inheritance finding (cartoon inherited, not a bug).
- **Committed in:** `c04a813` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 smoke-check bug)
**Impact on plan:** The deviation corrected an unsound test assertion in the plan's smoke section. The mutation.py fix (Task 1) was correct as written and needed no change. No scope creep — the corrected check is a stronger, more accurate regression guard that the plan was trying to express.

### Notes on plan prose miscounts (not deviations — code matches the plan's code blocks exactly)
- The plan's verify step 6 expected `cmd.show(rep,` to return "exactly ONE match" — it returns 2 (line 248 in `insert_hider`/line-stick path, pre-existing, + line 479 in `insert_cartoon_hider`, new). The line/stick path ALREADY used `cmd.show(rep, ...)`. The semantic gate `cmd.show('cartoon'` = 0 matches (hardcoded literal gone) is what confirms the change; the count mismatch is a prose miscount.
- The plan's verify step 7 expected `handle=handle, rep=rep` to return "exactly ONE match" — it returns 2 (line 530 in the lines/sticks dispatcher, pre-existing, + line 536 in the cartoon/ribbon dispatcher, new). The lines/sticks dispatcher ALREADY forwarded `rep=rep`. Same prose-miscount pattern.
- The plan said "33 existing + 8 new = ~41"; actual is 32 existing + 8 new + 1 spike = 41. Minor miscount (mirrors the 05-07 plan's documented "~34 vs 4" miscount).

## Issues Encountered
None beyond the smoke-check bug documented above (which was auto-fixed via Rule 1).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The `ribbon` rep is now playable end-to-end (the 05-05 gap #3 is closed). The remaining Phase 5 gap (alt-conf cartoon terminal-extension renders disconnected on 1ubq — gap #1) is DEFERRED to Phase 11 (research-required, GUI-runnable verification).
- All WSL gates green: py_compile all + 90 tests (no regression) + Pitfall-1=0 + exec_=1 on allowed QMessageBox.exec_() (gui_game.py:137, the win modal — NOT the main dialog).
- Headless smoke 41/41 ALL PASSED, exit 0 (33 existing + 8 new ribbon checks, no regression).
- No `__init__.py` modification. No `insert_line_stick_hider` / `insert_hider` / `collapse_to_single_state` / `free_nterminal_valence` changes. No alt-conf / Phase 11 work.
- No blockers or concerns for downstream phases. The rep-forwarding pattern (keyword default + dispatcher forwarding) is reusable for any future rep-parameterized show call.

---
*Phase: 05-line-stick-and-cartoon-generators*
*Completed: 2026-08-09*
