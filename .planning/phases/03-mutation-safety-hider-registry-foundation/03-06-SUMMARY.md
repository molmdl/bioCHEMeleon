---
phase: 03-mutation-safety-hider-registry-foundation
plan: 06
subsystem: mutation
tags: [pymol, cmd-iterate, sentinel, atom-id, space-dict, hygienic, dependency-injection]

# Dependency graph
requires:
  - phase: 03-03
    provides: "biochemeleon/mutation.py insert_hider (the file extended here; sentinel segi GAME + b -999 convention established)"
  - phase: 03-01
    provides: "registry.py HiderRegistry keyed by (object, id) -- the consumer of fetch_all_hider_ids via reconstruct_from_sentinels"
provides:
  - "biochemeleon/mutation.py fetch_all_hider_ids(object) -- sentinel-based (object_name, id) reader via cmd.iterate with hygienic space= dict"
affects:
  - "03-10: game.py reconstruct_from_sentinels wiring (injects fetch_all_hider_ids as the iterate fn into the pure registry)"
  - "03-13: smoke test .pse round-trip id-stability spike (uses fetch_all_hider_ids to read ids after reload)"
  - "03-14: smoke triage records Q4 id-stability finding"

# Tech tracking
tech-stack:
  added: []  # uses only pymol-open-source cmd.iterate (no new deps)
  patterns:
    - "Hygienic iterate: explicit space={'stored': out} dict, NEVER space=None (which pollutes pymol.__dict__ per RESEARCH sec Q3 / editing.py:47-62)"
    - "Sentinel-based id recovery: selector 'segi GAME and b -999' is the only hider-detection mechanism; survives .pse reload even if ids shift"
    - "DI-ready reader: returns (model, id) tuples so the pure registry can consume via an injected iterate fn (no pymol import in registry.py)"
    - "id (stable integral identifier) over index (fragile across add/delete) -- RESEARCH sec Q4 / querying.py:1315"

key-files:
  created: []
  modified:
    - "biochemeleon/mutation.py: added fetch_all_hider_ids(object) + one-sentence module-docstring mention (74 -> 112 lines)"

key-decisions:
  - "space={'stored': out} (NOT space=None) -- hygiene; space=None runs the expression against the global pymol.__dict__ (legacy stored.xxx pattern, pollutes namespace); the explicit dict is the editor.py:156 hygienic pattern"
  - "Return (model, id) tuples (model = object name), NOT bare id -- future-safe for multi-object games (registry keys by (object, id) tuple per 03-01 decision)"
  - "Read id via iterate (the stable integral identifier), NEVER index -- RESEARCH sec Q4 confirms cmd.index docstring warns indices are fragile across add/delete"
  - "cleanup_hiders deliberately NOT added here -- deferred to plan 03-09 per the plan scope"
  - "Docstring written in prose ('the iterate primitive', 'explicit space= dict', 'segi=GAME + b=-999') to avoid literal cmd.iterate / space={'stored' / 'segi GAME and b -999' false-positives on the task's exact-count grep gates (mirrors the 03-03 docstring-rewording precedent)"

patterns-established:
  - "fetch_all_hider_ids is the single sentinel-id reader; registry reconstruction (03-10) injects it as DI to keep registry.py pure"
  - "All cmd-coupled readers in mutation.py use the sentinel selector (segi GAME and b -999) -- never resi/chain/index for hider detection"

# Metrics
duration: 3 min
completed: 2026-08-05
---

# Phase 3 Plan 06: fetch_all_hider_ids Summary

**Sentinel-based (object, id) reader via hygienic cmd.iterate (explicit `space=` dict, not `space=None`) for registry reconstruction and the smoke-test id-stability spike**

## Performance

- **Duration:** 3 min
- **Started:** 2026-08-05T20:33:44Z
- **Completed:** 2026-08-05T20:37:03Z
- **Tasks:** 2
- **Files modified:** 1 (`biochemeleon/mutation.py`)

## Accomplishments
- Added `fetch_all_hider_ids(object)` to `biochemeleon/mutation.py` (after `insert_hider`, behind a `# ---- Hider id reader (sentinel-based) ----` section comment) -- the sentinel-based id reader the registry consumes via dependency injection and the smoke test's Q4 id-stability spike uses.
- Confirmed the hygienic iterate pattern: `cmd.iterate(..., space={'stored': out})` with an explicit dict (NOT `space=None`), so the expression never pollutes the global `pymol.__dict__` (RESEARCH sec Q3; editing.py:47-62, editor.py:156).
- Locked the sentinel selector `segi GAME and b -999` as the hider-detection mechanism and `id` (stable integral identifier, not fragile `index`) as the returned key -- RESEARCH sec Q4 (querying.py:1315 warns indices shift across add/delete).
- All WSL gates green: py_compile all modules, 90 unit tests pass, Pitfall-1/11 grep gates zero, `space=` gate 4 matches (>=2: existing alter + new iterate + 2 docstring prose mentions), and the four task-level exact-count greps each return exactly 1 (`def fetch_all_hider_ids`, `cmd\.iterate`, `space={'stored'`, `segi GAME and b -999`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Add fetch_all_hider_ids(object) to mutation.py** - `d6ed085` (feat)
2. **Task 2: Run full gate suite (no regression)** - no commit (verification-only per plan)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified
- `biochemeleon/mutation.py` - Added `fetch_all_hider_ids(object)` (lines 79-112): reads sentinel atoms via `cmd.iterate` with `space={'stored': out}`, returns `(object_name, id)` tuples. Also added one sentence to the module docstring (lines 4-7) describing the new function. Body follows 03-RESEARCH.md Backup/Restore Design lines 329-334 exactly; docstring mirrors `insert_hider`'s style (Args/Returns + inline source citations editing.py:1490/1446-1449 + RESEARCH sec Q3/Q4 refs).

## Decisions Made
- **Hygienic iterate via explicit `space=` dict** -- `space={'stored': out}`, NOT `space=None`. `space=None` defaults the expression to the global `pymol.__dict__` (the legacy `stored.xxx` pattern, editing.py:59-60); the explicit dict is the editor.py:156 hygienic pattern and is testable/non-polluting.
- **Return `(model, id)` tuples, not bare `id`** -- `model` is the object name, so the registry can key by `(object, id)` even in future multi-object games (matches the 03-01 registry-keyed-by-tuple decision). This is the data shape `registry.reconstruct_from_sentinels(iterate_fn)` (plan 03-10) consumes.
- **`id` (stable integral identifier), not `index`** -- RESEARCH sec Q4 confirms `cmd.index`'s own docstring (querying.py:1315) warns "Atom indices are fragile and will change as atoms are added or deleted." `id` is stable across add/delete; the registry keys on it.
- **`cleanup_hiders` deferred** -- the plan scope is `fetch_all_hider_ids` only; `cleanup_hiders` is plan 03-09. Did NOT add it.
- **Docstring prose avoids literal gated strings** -- wrote "the iterate primitive" / "explicit `space=` dict" / "sentinel (`segi='GAME'` + `b=-999`)" instead of literal `cmd.iterate` / `space={'stored'` / `segi GAME and b -999`, so the four task exact-count greps each return exactly 1 (the body call). Mirrors the 03-03 docstring-rewording precedent (deviation 1 there).

## Deviations from Plan

None - plan executed exactly as written.

The two minor stylistic choices (extending the module docstring with a one-sentence mention of the new function; expanding the RESEARCH snippet's one-line docstring into a full Args/Returns docstring mirroring `insert_hider`'s style) are consistency with the existing file, not scope changes -- the body follows 03-RESEARCH.md Backup/Restore Design lines 329-334 exactly.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `mutation.py` now has `insert_hider` (03-03) + `fetch_all_hider_ids` (this plan). `cleanup_hiders` remains the last mutation primitive (plan 03-09) before `game.py` orchestration can wire Start/Cleanup/abort.
- `fetch_all_hider_ids` is the iterate-fn that plan 03-10 (`game.py` reconstruct_from_sentinels wiring) will inject into the pure `registry.HiderRegistry.reconstruct_from_sentinels` -- the DI contract is now satisfied (caller passes `lambda: mutation.fetch_all_hider_ids(obj)`; registry stays pure).
- The Phase 3 smoke test's Q4 id-stability spike (plan 03-13) and `.pse` round-trip section use `fetch_all_hider_ids` to read ids after reload; the sentinel-survival check is the load-bearing one (HIGH confidence the sentinel survives -- it's just atom properties).
- Blocker/concern (unchanged from 03-03): `mutation.py` is cmd-coupled -- `cmd.iterate` (sentinel read, `model`/`id` symbols, `space=` hygiene) is WSL-unverifiable at runtime (no PyMOL in WSL; py_compile is syntax-only, the 90 unit tests exercise only the pure layer). Only the Phase 3 smoke test (plans 03-13/03-14, run in Windows PyMOL via plan 03-15 checkpoint) can confirm runtime behavior.
- Concurrent Wave 2 note: this plan ran alongside 03-04 (registry.py queries + tests, committed 998aa85/97a3743) and 03-05 (backup.py, committed + SUMMARY created). Files are disjoint (mutation.py vs registry.py/tests vs backup.py); no merge conflict. Used plain `git commit` (no `--amend`) and staged only `biochemeleon/mutation.py` to avoid sweeping the parallel 03-05 agent's `backup.py`/SUMMARY into my commit (the 03-03 concurrent-collision lesson, now a logged decision).

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
