---
phase: 10-polish-endgame-help
plan: 01
subsystem: data
tags: [tdd, pure-layer, diff-03, debrief, setup_state, wsl-testable, game_reps]

# Dependency graph
requires:
  - phase: 04.1 (format_remaining pure-formatter precedent — same module, same test file, same pattern)
    provides: The "pure HTML/text formatter in setup_state.py + WSL unit tests mirroring TestFormatRemaining" pattern this plan copies.
  - phase: 03 (registry.counts_by_rep — the data source the formatter consumes)
    provides: counts_by_rep() zero-filled GAME_REPS dict (skips rep=None) — the contract format_debrief_text's input is shaped against.
provides:
  - "DEBRIEF_EXPLANATIONS dict (5 keys, one per GAME_REPS) — domain-accurate per-rep 'why hard to spot' body text, verbatim from 10-RESEARCH-endgame.md."
  - "format_debrief_text(counts_by_rep) pure function — returns HTML rich-text (frame sentence + <ul> of per-rep bullets in GAME_REPS order, reps with count>0 only) usable in QMessageBox.setInformativeText; graceful fallback string for empty/None/all-zero input."
  - "_DEBRIEF_FALLBACK module constant — single source of truth for the fallback string shared by the empty-dict and all-zero-bullets branches."
  - "5 WSL unit tests (TestFormatDebrief) pinning: empty dict, all-zero, single-rep bullet content, GAME_REPS order, rep=None defensive skip."
affects: [10-06 (gui_game.py debrief QMessageBox consumes format_debrief_text via registry.counts_by_rep()), 10-09 (smoke asserts DEBRIEF_EXPLANATIONS text is domain-accurate)]

# Tech tracking
tech-stack:
  added: []  # stdlib only; no new dependencies
  patterns: ["TDD RED-GREEN-REFACTOR (3 commits: RED + GREEN + REFACTOR)", "pure-layer HTML rich-text formatter mirroring format_remaining (same module, same test file)", "module-level fallback constant (_DEBRIEF_FALLBACK) shared by two branches — single source of truth (DRY)"]

key-files:
  created: []
  modified:
    - biochemeleon/setup_state.py  # +95 lines: _DEBRIEF_FALLBACK + DEBRIEF_EXPLANATIONS dict + format_debrief_text function (appended after format_remaining)
    - tests/test_setup_state.py    # +67 lines: TestFormatDebrief class (5 tests) + format_debrief_text added to the import block

key-decisions:
  - "Iterate GAME_REPS (NOT the input dict) for bullet order — deterministic regardless of the input dict's insertion order (the test_format_debrief_game_reps_order test enforces this with an anti-GAME_REPS insertion-order input). Mirrors format_remaining's `for rep in GAME_REPS` pattern."
  - "Defensive `if not rep: continue` guard skips a None key in the input dict — the real counts_by_rep never emits a None key (it skips rep=None records per 03-10), but the formatter must not crash on a corrupt input (TypeError on None as a key in .get would otherwise surface). Guarded by test_format_debrief_rep_none_defensive."
  - "Empty dict, None input, AND all-zero dict all collapse to the SAME fallback string — the `if not bullets:` branch catches the all-zero case (no bullets accumulated because count>0 is false for every rep) so the dialog never shows an empty <ul>. Single _DEBRIEF_FALLBACK constant (REFACTOR) means both branches share one literal."
  - "DEBRIEF_EXPLANATIONS text is VERBATIM from 10-RESEARCH-endgame.md 'Per-Rep Why Hard to Spot Explanations' (lines 133/138/143/148/153) — no invented science. Each explanation is grounded in the actual mutation.py insertion mechanism (spheres = matching elem/color/radius ball; lines/sticks = bonded pseudoatom; cartoon/ribbon = copied real backbone segment on a new chain with a displaced middle). The dict values carry the BODY text only (no `<rep>:` prefix, no `<b>` tags) — the formatter adds the `<b>%s: %d hider(s)</b>` header."
  - "`total` is the SUM of count>0 entries (matches len(registry.all()) for non-degraded games; uses the per-rep sum so the headline reflects the bullets shown even if a None-key record is silently skipped)."
  - "REFACTOR applied: extracted _DEBRIEF_FALLBACK module constant — the GREEN implementation had the fallback literal duplicated in two branches; the plan explicitly suggested this as the example refactor opportunity. No behavior change (byte-identical return); tests stay green."

patterns-established:
  - "Pure-layer HTML rich-text formatter for a Qt consumer: the formatter lives in setup_state.py (stdlib only, WSL-unit-testable) and returns an HTML string the Qt caller (gui_game.py's QMessageBox.setInformativeText) writes straight onto the widget — the Qt layer stays a thin shell over a tested pure helper. This extends the format_remaining precedent from plain-text labels to HTML rich-text."

# Metrics
duration: 7 min
completed: 2026-08-18
---

# Phase 10 Plan 01: Debrief text formatter (DIFF-03 pure layer) Summary

**TDD-added a pure `format_debrief_text(counts_by_rep)` + `DEBRIEF_EXPLANATIONS` dict to `setup_state.py` — the WSL-unit-testable HTML rich-text foundation for the post-game debrief (DIFF-03) that Plan 10-06's gui_game.py QMessageBox consumes.**

## Performance

- **Duration:** 7 min (RED 01:50 → REFACTOR 01:57 +0800)
- **Started:** 2026-08-17T17:50Z (2026-08-18 01:50 +0800)
- **Completed:** 2026-08-17T17:57Z (2026-08-18 01:57 +0800)
- **Tasks:** 3 (RED, GREEN, REFACTOR)
- **Files modified:** 2

## Accomplishments
- Added `DEBRIEF_EXPLANATIONS` dict (5 keys, one per GAME_REPS) with domain-accurate per-rep "why hard to spot" body text, verbatim from `10-RESEARCH-endgame.md`. Each explanation is grounded in the actual `mutation.py` insertion mechanism (spheres = matching elem/color/radius ball; lines/sticks = bonded pseudoatom with copied elem/color; cartoon/ribbon = copied real backbone segment on a new chain with a displaced middle). No invented science.
- Added `format_debrief_text(counts_by_rep)` pure function returning an HTML rich-text string (frame sentence + `<ul>` of per-rep bullets in GAME_REPS order, reps with `count > 0` only) usable in `QMessageBox.setInformativeText`. Empty dict, None input, and all-zero dict all collapse to the graceful fallback string `_DEBRIEF_FALLBACK` so the dialog never shows an empty `<ul>`. A None key in the input dict is skipped defensively (no TypeError). Pure (stdlib only — no pymol, no Qt) — WSL-unit-testable.
- Added 5 WSL unit tests (`TestFormatDebrief`) pinning every behavior in the plan's spec: empty-dict fallback, all-zero fallback, single-rep bullet content (frame sentence + exactly one `<li>` + `<b>spheres: 3 hider(s)</b>` + sphere explanation opener + `<ul>` wrap), GAME_REPS-order bullets (anti-GAME_REPS insertion-order input), rep=None defensive skip. All deterministic `assertEqual`/`assertIn`/`assertLess` (no mocks).
- Zero backward-compat breakage: `format_remaining` and all existing setup_state functions UNALTERED (additive new code appended at file tail). All 120 pre-existing setup_state tests pass (125 total with the 5 new) — no regression.

## Task Commits

Each TDD phase was committed atomically on branch `exec/10-01`:

1. **RED — add failing TestFormatDebrief tests** — `e65197a` (test)
   - 5 new tests added; `format_debrief_text` added to the import block. All fail with `ImportError: cannot import name 'format_debrief_text'` (standard TDD RED — the unimportable name breaks the whole test module's import until GREEN fixes it). The plan's "existing suite unaffected" verify claim is a minor misjudgment (adding an unimportable name to the import list breaks the whole module's import); the core RED criterion (tests fail with ImportError on format_debrief_text) is met.
2. **GREEN — implement DEBRIEF_EXPLANATIONS + format_debrief_text** — `03a1e7a` (feat)
   - `_DEBRIEF_FALLBACK` constant + `DEBRIEF_EXPLANATIONS` dict (5 keys) + `format_debrief_text` function appended after `format_remaining` behind a `# ---- Post-game debrief formatter (Phase 10 DIFF-03) ----` section comment. All 5 TestFormatDebrief tests pass; full suite 125 tests pass (120 existing + 5 new).
3. **REFACTOR — extract _DEBRIEF_FALLBACK constant** — `a2a21d4` (refactor)
   - The GREEN implementation had the fallback literal `"All hiders are highlighted in the viewer."` duplicated in two branches (empty-dict early return + no-bullets late return). Extracted to the module-level `_DEBRIEF_FALLBACK` constant so both branches share one literal (single source of truth — the plan's example refactor opportunity). No behavior change (byte-identical return); tests stay green (125 pass).

## Files Created/Modified
- `biochemeleon/setup_state.py` — Appended `_DEBRIEF_FALLBACK` constant + `DEBRIEF_EXPLANATIONS` dict (5 keys, verbatim research text) + `format_debrief_text(counts_by_rep)` function (lines 449-543) after `format_remaining`, behind a Phase 10 DIFF-03 section comment. +95 lines. Module stays PURE (stdlib only — no `from pymol`, no `from pymol.Qt`; verified by PURITY gate = 0 matches).
- `tests/test_setup_state.py` — Added `format_debrief_text` to the `from biochemeleon.setup_state import (...)` block (line 26, right after `format_remaining,`) + `TestFormatDebrief` class (5 tests) placed after `TestFormatRemaining` (the precedent), following its `assertEqual` pattern. +67 lines. Total setup_state tests: 120 → 125.

## Decisions Made
- **Iterate GAME_REPS (not the input dict) for bullet order** (vs. iterating the dict): deterministic regardless of the input dict's insertion order. The `test_format_debrief_game_reps_order` test enforces this with an anti-GAME_REPS input (`{'cartoon': 2, 'spheres': 1}`) and asserts the spheres bullet precedes the cartoon bullet. Mirrors `format_remaining`'s `for rep in GAME_REPS` pattern (the established pure-layer precedent).
- **Defensive None-key skip** (`if not rep: continue`): the real `counts_by_rep()` never emits a None key (it skips `rep=None` records per the 03-10 decision), but the formatter must not crash on a corrupt input. A None key reaching `counts_by_rep.get(rep, 0)` would not crash (dict.get tolerates None keys), but the `DEBRIEF_EXPLANATIONS[rep]` lookup WOULD raise KeyError on None — the early `if not rep: continue` guard prevents that. Guarded by `test_format_debrief_rep_none_defensive` (also asserts no "None" substring leaks into the output).
- **All-zero collapse to fallback via the `if not bullets:` branch** (not a separate all-zero check): an all-zero dict produces no bullets (every `count > 0` is false), so the `if not bullets: return _DEBRIEF_FALLBACK` branch naturally catches it. This means empty-dict, None-input, and all-zero all share the SAME fallback path — no special-casing. Guarded by `test_format_debrief_all_zero`.
- **`total` = sum of count>0 entries** (not `len(registry.all())`): the formatter has no registry access (pure layer), so the headline count is derived from the input dict's count>0 entries. This matches `len(registry.all())` for non-degraded games (all records have valid reps) and reflects the bullets actually shown even if a None-key record is silently skipped.
- **DEBRIEF_EXPLANATIONS text verbatim from research** (no paraphrasing): the AGENTS.md "do NOT make up anything / ALL claims verified against a source" rule applies. Each of the 5 explanation strings matches `10-RESEARCH-endgame.md` lines 133/138/143/148/153 byte-for-byte (the body text without the `"N hider(s)"` prefix — the formatter adds that prefix). The cartoon explanation's "COPIED real backbone segment" + "middle residues are slightly displaced" phrasing is grounded in `mutation.py:518-696` (`insert_cartoon_segment_hider` copies a real 3-residue backbone segment, rigid-translates the middle atoms — research line 150).
- **REFACTOR applied (not skipped)**: unlike 04.1-01 (where REFACTOR was skipped because GREEN was already clean), here the GREEN implementation had a clear DRY improvement available — the fallback literal was duplicated. The plan explicitly listed this as the example refactor opportunity, so the `_DEBRIEF_FALLBACK` constant was extracted. Tests stayed green (no behavior change).

## Deviations from Plan

None (no Rule 1-4 deviations). Plan executed as written.

One minor plan inconsistency noted (not a deviation — the RED phase behaved exactly as TDD requires): the Task 1 `<verify>` claims "The full existing suite `python3.6 -m unittest tests.test_setup_state -v` still passes (the import addition is harmless — it just adds a name to the import list)." This is incorrect — adding an unimportable name (`format_debrief_text`) to the `from biochemeleon.setup_state import (...)` list breaks the WHOLE test module's import, so the full suite ALSO fails during RED (with the same `ImportError`). This is the standard/expected TDD RED signal (the plan's own "all 5 MUST FAIL with ImportError" confirms the import IS expected to fail). The GREEN commit restored the full suite to green. No code change was needed for this — it's the inherent nature of TDD RED with a top-level import.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. Pure data-layer function + WSL unit tests; no runtime/PyMOL/Qt involvement.

## Next Phase Readiness
- **Ready for 10-06** (the gui_game.py debrief plan): `format_debrief_text(counts_by_rep)` is the documented handoff — `gui_game.py`'s debrief QMessageBox calls `format_debrief_text(self._controller.registry.counts_by_rep())` and writes the returned string straight onto `QMessageBox.setInformativeText`. The function is pure, WSL-verified, and additive — 10-06 can import it from `setup_state` (alongside the existing `format_remaining` import on `gui_game.py:15`) without any `setup_state.py` change.
- **Ready for 10-09** (the smoke plan): `DEBRIEF_EXPLANATIONS` text is domain-accurate (verified against the research at RED/GREEN time) — 10-09's "PASS if the explanations match the domain-accurate text from the research" check will pass against the verbatim strings.
- **No blockers.** All WSL gates green:
  - `python3.6 -m unittest tests.test_setup_state -v` — 125 tests pass (120 existing + 5 new).
  - `python3.6 -m unittest tests.test_setup_state.TestFormatDebrief -v` — 5/5 pass.
  - `python3.6 -m py_compile biochemeleon/*.py` — all modules syntax-clean.
  - Pitfall-1 gate (`import Tkinter|...|from PyQt5 import|import PyQt5` in `biochemeleon/`) — 0 matches (the new code is pure stdlib; no Qt tokens).
  - exec_ gate (`\.exec_\(\)` in `biochemeleon/`) — exactly 1 hit (`gui_game.py:312 msg.exec_()` — the existing `_finish_win` QMessageBox; this plan did NOT touch Qt, so unchanged).
  - PURITY gate (`from pymol|import pymol` in `setup_state.py`) — 0 matches (module stays in the PURE layer).
  - `DEBRIEF_EXPLANATIONS` defined exactly once; `format_debrief_text` defined exactly once; `_DEBRIEF_FALLBACK` defined exactly once.
- **Runtime/Qt verification deferred** to 10-06's human-verify checkpoint (the debrief QMessageBox is Qt-coupled — not WSL-reachable). The pure formatter is fully WSL-verified.

---
*Phase: 10-polish-endgame-help*
*Completed: 2026-08-18*
