---
phase: 05-line-stick-and-cartoon-generators
plan: 04
subsystem: testing
tags: [pymol, headless-smoke, cartoon, line-stick, mixed-rep, attach_amino_acid, oxt, n-terminus, open-risks]

# Dependency graph
requires:
  - phase: 05-line-stick-and-cartoon-generators (plan 01)
    provides: generators.py pure functions (generate_sphere_positions + generate_line_stick_offsets + pick_terminal_residues) exercised by the mixed-rep section
  - phase: 05-line-stick-and-cartoon-generators (plan 02)
    provides: mutation.py insert_line_stick_hider + insert_cartoon_hider + insert_hider_for_rep dispatcher under test
  - phase: 05-line-stick-and-cartoon-generators (plan 03)
    provides: game.py GameController.start dispatch + the (payload, rep) contract exercised by the mixed-rep section
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: backup.snapshot/verify_intact/discard + mutation.cleanup_hiders + the segi GAME + b < 0 sentinel
  - phase: 04-mvp-core-loop-sphere
    provides: the headless smoke pattern (smoke/phase4_smoke.py check/pass/summary + cmd.exe /c run-conda-pymol.bat -cq)
provides:
  - smoke/phase5_smoke.py — Phase 5 headless smoke (25/25 ALL PASSED) proving line/stick + cartoon + mixed-rep insertion at the cmd-coupled runtime tier
  - Runtime verification of the 3 MEDIUM open risks (all PASS, no fallback): Open Risk 1 (segi='GAME' does NOT break the polymer selector), Open Risk 2 (attach_amino_acid works with a named selection, no pk1), Open Risk 3 (hider C-alpha color == neighbor C-alpha color)
  - Open Risk 6 (LOW) confirmed: cmd.iterate_state exposes elem + color (so insert_line_stick_hider's combined (x,y,z,elem,color) read works)
  - Two runtime fixes discovered by the smoke: (1) attach_amino_acid lives in pymol.editor (NOT cmd.attach_amino_acid in 2.5.0); (2) the cartoon MVP switched from C-terminus to N-terminus because the C-terminus carbonyl C carries an OXT that blocks the residue-attach primitive
affects: [05-05 (human-verify checkpoint — the smoke proves the MECHANISM, the human proves the visual BLEND), Phase 6 (hint/reveal — cartoon hiders are N-terminal extensions), Phase 8 (.bcm sidecar — rep reconciliation)]

# Tech tracking
tech-stack:
  added: []  # no new libs; uses existing PyMOL 2.5.0 cmd + pymol.editor
  patterns:
    - "Headless smoke via cmd.exe /c C:\\src\\run-conda-pymol.bat -cq (AGENTS.md): pure pymol.cmd.* runs headlessly from WSL; NO Qt"
    - "resv not int(resi): the hygienic space= dict does not expose Python builtins, so int(resi) raises NameError inside iterate expressions; resv (numeric residue value, already int per the symbol table) sidesteps this"
    - "neighbor selector precedence: `neighbor A and B` can parse as `neighbor (A and B)` (empty); wrap in explicit parens `(neighbor A) and B` to force the intended grouping"
    - "pymol.editor lazy import: attach_amino_acid lives in pymol.editor (editor.py:85), NOT exposed as cmd.attach_amino_acid in 2.5.0 open-source (cmd.py imports editor lazily inside a function); import lazily inside the function so WSL unit tests (pymol stubbed as MagicMock) never trigger it"
    - "N-terminus over C-terminus for cartoon extension: the C-terminus carbonyl C carries an OXT (terminal oxygen) in most structures, saturating the C valence and making the residue-attach primitive fail with 'no target attachment vector found' (ObjectMolecule.cpp:3357); the N-terminus N has a free valence, extends with NO atom removal, and verify_intact passes after sentinel cleanup"

key-files:
  created:
    - smoke/phase5_smoke.py — Phase 5 headless smoke (194 lines, pure pymol.cmd.* — NO Qt); 25/25 ALL PASSED
  modified:
    - biochemeleon/mutation.py — insert_cartoon_hider: lazy `from pymol import editor` (attach_amino_acid not on cmd in 2.5.0); docstring updated for the pymol.editor + N-terminus rationale (387 -> 401 lines)
    - biochemeleon/generators.py — pick_terminal_residues switched from C-terminus (max resi, True) to N-terminus (min resi, False); docstring explains the OXT rationale (97 -> 107 lines)
    - tests/test_generators.py — TestPickTerminalResidues 6 tests updated for N-terminus (min resi, is_c_terminus=False) (225 -> 225 lines)

key-decisions:
  - "Cartoon MVP switched from C-terminus to N-terminus: the C-terminus carbonyl C carries an OXT (terminal oxygen) in 1ubq (and most structures), which saturates the C valence and makes editor.attach_amino_acid fail with 'no target attachment vector found' (ObjectMolecule.cpp:3357). The N-terminus N has a free valence, extends with NO atom removal, so the happy-path sentinel cleanup (segi GAME) restores the structure exactly and verify_intact passes (confirmed: 25/25 smoke, cleanup count back to 660=orig). This is a Rule 1/3 runtime bug fix, NOT an Open Risk 1 fallback (the plan's Open Risk 1 fallback was resn='HIDER' + b=-999 if segi broke the polymer — segi did NOT break the polymer, so that fallback was not needed)."
  - "Used pymol.editor.attach_amino_acid (NOT cmd.attach_amino_acid): the function lives in the pymol.editor module (editor.py:85) and is not exposed on cmd in PyMOL 2.5.0 open-source. Imported lazily inside insert_cartoon_hider so the module-level import stays minimal and WSL unit tests (pymol stubbed as MagicMock) never trigger this path."
  - "Used resv (numeric residue value, int) instead of int(resi) in iterate expressions: the hygienic space={'stored':...} dict does not expose Python builtins, so int(resi) raises NameError. resv is exposed by iterate (symbol table editing.py:1444-1449) and is already an int, sidestepping the namespace issue entirely."
  - "Kept the Phase 3 segi='GAME' + b=-999 sentinel UNCHANGED for cartoon: Open Risk 1 confirmed segi='GAME' on an attached polymer residue does NOT break the polymer selector (count_atoms('segi GAME and polymer') = 5 > 0). No sentinel migration needed — cleanup_hiders (segi GAME) and fetch_all_hider_ids (segi GAME and b < 0) work untouched."

patterns-established:
  - "resv-over-int(resi): in cmd.iterate expressions with a hygienic space= dict, use resv (int) not int(resi) (NameError — builtins not in scope)"
  - "neighbor-parens: wrap `neighbor (sele)` in explicit outer parens before `and ...` to avoid PyMOL selector precedence swallowing the intersect into the neighbor argument"
  - "pymol.editor lazy import: editor-only functions (attach_amino_acid) are imported lazily inside the function that needs them, keeping the module-level import minimal and WSL-test-safe"

# Metrics
duration: 18 min
completed: 2026-08-08
---

# Phase 5 Plan 04: Line/Stick + Cartoon Headless Smoke Summary

**Headless smoke (25/25 ALL PASSED) proving line/stick + cartoon + mixed-rep hider insertion at the cmd-coupled runtime tier, with all 3 MEDIUM open risks resolved and the cartoon MVP switched to N-terminus (C-term OXT blocks attach)**

## Performance

- **Duration:** 18 min
- **Started:** 2026-08-08T09:15:51Z
- **Completed:** 2026-08-08T09:34:31Z
- **Tasks:** 1 (write + run headless smoke + iterate runtime fixes)
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments
- smoke/phase5_smoke.py (194 lines, pure pymol.cmd.* — NO Qt) verifying line/stick + cartoon + mixed-rep insertion + cleanup safety at the cmd-coupled runtime tier via `cmd.exe /c C:\src\run-conda-pymol.bat -cq` — 25/25 ALL PASSED, exit 0.
- All 3 MEDIUM open risks RESOLVED (all PASS, no fallback applied): Open Risk 1 (segi='GAME' does NOT break the polymer selector — polymer_GAME=5), Open Risk 2 (attach_amino_acid works with a named selection, no pk1 needed), Open Risk 3 (hider C-alpha color == neighbor C-alpha color for both line/stick and cartoon).
- Open Risk 6 (LOW) confirmed: cmd.iterate_state exposes elem + color, so insert_line_stick_hider's combined (x,y,z,elem,color) read works in one call.
- Cleanup safety confirmed: gc.cleanup() returns True (verify_intact passes), count back to orig (660), no GAME atoms remain — the happy-path sentinel cleanup restores the structure exactly after a mixed-rep game (sphere + stick + cartoon).
- Discovered + fixed two runtime issues that blocked the cartoon path: (1) attach_amino_acid lives in pymol.editor (not cmd.attach_amino_acid in 2.5.0); (2) the C-terminus OXT blocks the residue-attach primitive → switched the cartoon MVP to the N-terminus (free valence, no atom removal, verify_intact passes).

## Task Commits

Each task was committed atomically (the plan had 1 task; the source fixes were split from the smoke for bisect granularity):

1. **fix(05-04): cartoon hider uses pymol.editor + N-terminus (C-term OXT blocks attach)** - `9c6b009` (fix) — mutation.py + generators.py + tests/test_generators.py
2. **test(05-04): add phase5 headless smoke (line/stick + cartoon + mixed-rep + 3 open risks)** - `ef001c8` (test) — smoke/phase5_smoke.py

**Plan metadata:** (pending — SUMMARY + STATE commit below)

## Files Created/Modified
- `smoke/phase5_smoke.py` — Phase 5 headless smoke (194 lines, pure pymol.cmd.* — NO Qt); 25/25 ALL PASSED. Covers: LINE/STICK (insert_line_stick_hider → rep sticks + sentinel + bond + color), CARTOON (insert_cartoon_hider N-terminus → polymer + rep cartoon + N-C-CA backbone + sentinel + color), MIXED-REP (GameController.start via insert_hider_for_rep → registry counts + per-rep visibility), CLEANUP (verify_intact + count restore), optional iterate_state spike.
- `biochemeleon/mutation.py` — insert_cartoon_hider: `cmd.attach_amino_acid` → lazy `from pymol import editor` + `editor.attach_amino_acid` (the function is in pymol.editor, not on cmd in 2.5.0); docstring updated with the pymol.editor + N-terminus + OXT rationale.
- `biochemeleon/generators.py` — pick_terminal_residues switched from C-terminus (max resi, is_c_terminus=True) to N-terminus (min resi, is_c_terminus=False); docstring explains the OXT rationale (C-term OXT blocks attach at runtime).
- `tests/test_generators.py` — TestPickTerminalResidues 6 tests updated for N-terminus (min resi, is_c_terminus=False).

## Decisions Made
- **Cartoon MVP = N-terminus (not C-terminus).** The C-terminus carbonyl C carries an OXT (terminal oxygen) in 1ubq (and most structures), saturating the C valence → `editor.attach_amino_acid` fails with "no target attachment vector found" (ObjectMolecule.cpp:3357). The N-terminus N has a free valence, extends with NO atom removal, so the happy-path sentinel cleanup restores the structure exactly and verify_intact passes. This is a Rule 1/3 runtime bug fix (the research/plan assumed C-terminus works; the smoke proved it doesn't for OXT-bearing structures), NOT an Open Risk 1 fallback (segi didn't break the polymer — the fallback the plan anticipated was resn='HIDER' if segi broke the trace, which didn't happen). The C-terminus path is still supported by insert_cartoon_hider (is_c_terminus=True) for structures without OXT, but the MVP generator picks the N-terminus.
- **pymol.editor.attach_amino_acid (not cmd.attach_amino_acid).** attach_amino_acid lives in the pymol.editor module (editor.py:85) and is NOT exposed as cmd.attach_amino_acid in PyMOL 2.5.0 open-source (cmd.py imports editor lazily inside a function). Imported lazily inside insert_cartoon_hider so WSL unit tests (pymol stubbed as MagicMock) never trigger this path.
- **resv not int(resi) in iterate expressions.** The hygienic space={'stored':...} dict does not expose Python builtins, so int(resi) raises NameError. resv (numeric residue value, already int per the symbol table) sidesteps this.
- **Kept the Phase 3 segi='GAME' + b=-999 sentinel UNCHANGED for cartoon.** Open Risk 1 confirmed segi='GAME' on an attached polymer residue does NOT break the polymer selector. No sentinel migration needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] cmd.attach_amino_acid does not exist in PyMOL 2.5.0 open-source**
- **Found during:** Task 1 (headless smoke run — section 3 CARTOON)
- **Issue:** `mutation.insert_cartoon_hider` called `cmd.attach_amino_acid(...)` which raised `AttributeError: module 'pymol.cmd' has no attribute 'attach_amino_acid'`. The function lives in the `pymol.editor` module (editor.py:85); `cmd.py` imports `editor` lazily inside a function (cmd.py:197), so `cmd.editor` is not a stable module-level attribute.
- **Fix:** Lazy `from pymol import editor` inside `insert_cartoon_hider`, then `editor.attach_amino_acid(attach_sele, aa, ss=ss, hydro=hydro)`. The lazy import keeps the module-level import minimal and ensures WSL unit tests (pymol stubbed as MagicMock) never trigger this path.
- **Files modified:** biochemeleon/mutation.py
- **Verification:** 25/25 smoke ALL PASSED (cartoon: attach_amino_acid worked with named sele); 173 WSL unit tests pass (no regression — the lazy import is never executed in tests).
- **Committed in:** 9c6b009

**2. [Rule 1 - Bug] C-terminus OXT blocks the residue-attach primitive → switched cartoon MVP to N-terminus**
- **Found during:** Task 1 (headless smoke run — section 3 CARTOON, after fix #1)
- **Issue:** `editor.attach_amino_acid` at the C-terminus C raised `pymol.CmdException: Error: no target attachment vector found` (ObjectMolecule.cpp:3357 — `GetTargetValenceVector` found no free valence). Diagnostic confirmed 1ubq's C-terminal residue (resi 76) has an OXT (terminal oxygen) `[N, CA, C, O, OXT]`, saturating the C valence (CA + O double + OXT = 4). Removing OXT before attach made it succeed, but that breaks the happy-path cleanup (OXT is not tagged segi GAME, so cleanup_hiders can't restore it → verify_intact fails).
- **Fix:** Switched the cartoon MVP from C-terminus to N-terminus: `pick_terminal_residues` now returns `(chain, min_resi, is_c_terminus=False)` (was max resi, True). The N-terminus N has a free valence, extends with NO atom removal, so the happy-path sentinel cleanup restores the structure exactly and verify_intact passes. `insert_cartoon_hider` already supported `is_c_terminus=False` (attach at name N, new_resi = terminus_resi - 1). Updated 6 unit tests.
- **Files modified:** biochemeleon/generators.py, tests/test_generators.py, biochemeleon/mutation.py (docstring)
- **Verification:** 25/25 smoke ALL PASSED (cartoon: N-term attach, polymer_GAME=5, verify_intact True, cleanup count back to 660=orig); 173 WSL unit tests pass (TestPickTerminalResidues updated for N-terminus).
- **Committed in:** 9c6b009

**3. [Rule 1 - Bug] int(resi) raises NameError in iterate expressions with a hygienic space= dict**
- **Found during:** Task 1 (headless smoke run — section 3 CARTOON)
- **Issue:** `cmd.iterate(sele, "stored.append((chain, int(resi), ID))", space={'stored': cas})` raised `NameError: name 'int' is not defined`. The hygienic `space=` dict provides the namespace for the expression but does NOT expose Python builtins like `int`.
- **Fix:** Use `resv` (the numeric residue value, already an int per the iterate symbol table editing.py:1444-1449) instead of `int(resi)`. Applied to both iterate calls (section 3 + section 4 mixed-rep).
- **Files modified:** smoke/phase5_smoke.py
- **Verification:** 25/25 smoke ALL PASSED (cartoon + mixed-rep sections use resv).
- **Committed in:** ef001c8

**4. [Rule 1 - Bug] neighbor selector precedence swallowed the intersect into the neighbor argument**
- **Found during:** Task 1 (headless smoke run — section 2 LINE/STICK)
- **Issue:** `cmd.count_atoms("neighbor (%s and id %d) and id %d" % (obj, neighbor_id, stick_id))` returned 0 even though the bond existed (confirmed via `neighbor (hider_id)` = 1). PyMOL selector precedence parsed `neighbor (1ubq and id 2) and id 661` as `neighbor ((1ubq and id 2) and id 661)` = `neighbor (empty)` = 0.
- **Fix:** Wrap the neighbor expression in explicit outer parens: `(neighbor (%s and id %d)) and id %d` so `neighbor` applies only to `(obj and id neighbor_id)` before the `and id stick_id` intersect. Added diagnostic counts (`neighbor(neighbor_id)`, `neighbor(hider_id)`) to confirm the bond exists.
- **Files modified:** smoke/phase5_smoke.py
- **Verification:** 25/25 smoke ALL PASSED (stick: hider bonded to neighbor — `neighbor(neighbor_id=2)=4 neighbor(hider_id=661)=1`).
- **Committed in:** ef001c8

---

**Total deviations:** 4 auto-fixed (2 Rule 1 bugs, 1 Rule 1 library bug, 1 Rule 3 blocking — plus 1 Rule 1 library bug in the smoke)
**Impact on plan:** All auto-fixes necessary for the cartoon path to work at runtime. No scope creep — the smoke verifies exactly what the plan specified; the fixes make the existing Phase 5 code (05-01/05-02/05-03) actually run. The N-terminus switch is the most consequential: it changes which terminus the cartoon MVP uses (a runtime-correctness decision the research couldn't have made without running the smoke).

## Issues Encountered
- The plan/research assumed C-terminus extension works (05-RESEARCH.md §3 Q8). The smoke proved it does NOT work for OXT-bearing structures (1ubq, most crystal structures). The N-terminus switch is the resolution. This is exactly the kind of runtime unknown the smoke was designed to surface (the research flagged Open Risk 1/2/3 as MEDIUM; the OXT issue is a 4th runtime unknown that the smoke caught). Documented in generators.py + mutation.py docstrings + this SUMMARY for future phases.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 5 MECHANISM is runtime-verified at the headless tier (25/25 ALL PASSED): line/stick hiders render in rep sticks (bonded), cartoon hiders render in rep cartoon (N-terminus extension, polymer, N-C-CA backbone), mixed-rep dispatch works via insert_hider_for_rep, cleanup restores the structure exactly (verify_intact True).
- The 3 MEDIUM open risks are RESOLVED (all PASS): segi doesn't break polymer, named-sele attach works, color matches neighbor. Open Risk 6 (LOW) also confirmed.
- Ready for plan 05-05 (human-verify checkpoint) to confirm the visual BLEND in a real PyMOL GUI session (success criterion 3): the smoke proves the MECHANISM, the human proves the BLEND. The human-verify should test a mixed-rep game (sphere + line/stick + cartoon) on a bundled demo (e.g. 1ubq or 1znf) and visually confirm each hider blends with its rep, is clickable, and cleanup leaves no visible trace.
- **Note for 05-05:** the cartoon hider is now an N-terminus extension (resi 0 for 1ubq), not C-terminus. The human-verify should confirm the N-terminal cartoon tube segment blends with the existing cartoon. If a bundled demo has an N-terminal cap (ACE/formyl), the N-terminus attach may fail — that's a 05-05 runtime concern (the smoke only tested 1ubq, which has a free N-terminus).

---
*Phase: 05-line-stick-and-cartoon-generators*
*Completed: 2026-08-08*
