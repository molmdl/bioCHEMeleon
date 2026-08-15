---
phase: 11-alt-conf-cartoon-hider
plan: 05
subsystem: game-orchestrator (scoring + lifecycle)
tags: [alt-conf, scoring, on_pick, wizard, do_pick, all_states, import_state, object-scoped, pymol-cmd]

# Dependency graph
requires:
  - phase: 11-alt-conf-cartoon-hider-02
    provides: HiderRecord 3 alt-conf fields (is_altconf/endpoint_resvs/alt_tag) + HiderRegistry.get_altconf_by_resv (pure resv-range lookup) + .bcm round-trip (list->tuple coercion)
  - phase: 11-alt-conf-cartoon-hider-04
    provides: insert_altconf_cartoon_hider (4-call construction) + insert_hider_for_rep arity-based dispatcher (backup_name + is_first_altconf passthrough)
  - phase: 03-mutation-safety-hider-registry
    provides: GameController on_pick/_mark_found/start/cleanup/abort_on_error/import_state skeleton + backup.snapshot-before-insert invariant + space={} hygiene + ID uppercase rule
provides:
  - GameController.on_pick(picked_id, alt='', resv=None) — dual lookup (registry.get then get_altconf_by_resv) + alt/resv gate (alt==rec.alt_tag AND rv1<resv<rv2); backward-compatible signature
  - GameController._mark_found(hider_id, rec=None) — is_altconf branch colors segi GAME middle-range (rv1+1 to rv2-1) instead of by shared id (Pitfall 14); rec=None defaults to by-id (backward compat)
  - PickWizard.do_pick iterates pk1 for (model, ID, alt, resv) via ONE cmd.iterate with space={'stored':...} BEFORE unpick (Pitfall 11: identify returns no alt)
  - GameController.start passes backup_name + is_first_altconf to the dispatcher, registers the 3 alt-conf fields, and toggles OBJECT-SCOPED all_states=on for >=2 alt-conf hiders
  - GameController.cleanup()/abort_on_error() reset object-scoped all_states=off via _all_states_was_set flag (getattr-guarded for pre-Phase-11 games)
  - GameController.import_state defensively re-applies alt=rec.alt_tag on segi GAME atoms (Open Risk 3 fallback) + re-applies object-scoped all_states=on when >=2 alt-conf records reconciled (Open Risk 5)
affects: [11-06 (GUI _prepare_and_start builds 4-tuple payloads + passes backup_name/is_first_altconf through start), 11-07 (headless smoke exercises on_pick scoring + start all_states + import_state alt re-apply), 11-08 (GUI human-verify for multi-state display + found-color on displaced bump)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — pure pymol.cmd.* (PyMOL 2.5.0 open-source) + existing pure layer
  patterns:
    - "Dual-lookup scoring: registry.get(id) for the anchor CA, then get_altconf_by_resv(resv) for non-anchor middle atoms (USER REQ 3: click ANY middle atom). Alt-conf atoms share ids with originals (Pitfall 10), so id alone can't distinguish; the resv-range fallback covers non-anchor middle clicks."
    - "alt/resv gate: alt == rec.alt_tag AND rv1 < resv < rv2 (strict between). Rejects the real trace (alt='') + endpoints (resv=rv1/rv2) + no-resv calls. Non-altconf records skip the gate (unique id, alt='')."
    - "Pitfall 14 coloring: for is_altconf records, color 'segi GAME and resi <rv1+1>-<rv2-1>' (the displaced middle bump), NOT by shared id (coloring by id colors the real trace too)."
    - "Object-scoped all_states (research Example 9): cmd.set('all_states', 'on', self.target_obj) — NOT global (a global set with no object arg leaks to ALL subsequent objects). Reset in cleanup/abort via _all_states_was_set flag."
    - "Open Risk 3 alt re-apply fallback in import_state: cmd.alter('segi GAME and resi <rv1>-<rv2>', \"alt='B'\", space={}) — idempotent (no-op if alt already 'B') + scoped to segi GAME (originals untouched, Pitfall 12). Runs AFTER apply_bcm_dict so rec.alt_tag/endpoint_resvs are reconciled."
    - "do_pick iterate-before-unpick: cmd.iterate('pk1', ...) reads (model, ID, alt, resv) from the one-atom pk1 selection BEFORE cmd.unpick() clears it. ID UPPERCASE (editing.py:1444-1449); space={'stored':...} hygienic (AGENTS.md)."

key-files:
  created: []
  modified:
    - biochemeleon/game.py  (320 -> 436 lines; on_pick dual-lookup+gate, _mark_found is_altconf branch, start backup_name/is_first_altconf/all_states, cleanup/abort all_states reset, import_state alt+all_states re-apply)
    - biochemeleon/wizard.py  (83 -> 89 lines; do_pick iterate pk1 for (model,ID,alt,resv); module docstring updated)
    - tests/test_game_controller.py  (513 -> 696 lines; +TestOnPickAltconf 7 tests + TestMarkFoundAltconf 4 tests)

key-decisions:
  - "_mark_found is_altconf branch implemented in Task 1 (not Task 2 as the plan's NOTE suggested): Task 1's TestOnPickAltconf.test_altconf_anchor_middle_ca_scores asserts cmd.color with 'segi GAME and resi 3-3', which requires the is_altconf coloring branch. The plan's NOTE ('Task 2 makes _mark_found branch on rec') was slightly imprecise prose; the test spec (source of truth for 'done') required the branch in Task 1. Task 2 added the dedicated TestMarkFoundAltconf unit tests + the start/cleanup/import_state work."
  - "getattr(rec, 'is_altconf', False) in on_pick defends against records rebuilt by old reconstruct_from_sentinels (which defaults is_altconf=False) — graceful degradation if a pre-Phase-11 .bcm is loaded."
  - "Object-scoped all_states (NOT global): cmd.set('all_states', 'on', self.target_obj) with the object arg. A global set (no object arg) leaks to ALL subsequent objects. The _all_states_was_set flag tracks whether start()/import_state set it, so cleanup()/abort_on_error() reset it only when needed (getattr-guarded for pre-Phase-11 games that never set it)."
  - "import_state alt re-apply scoped to 'segi GAME and resi <rv1>-<rv2>' (the FULL segment range incl. endpoints), NOT just the middle range. The segi GAME scope ensures originals (segi A) are untouched (Pitfall 12). Idempotent (alt='B' on atoms that already have alt='B' is a no-op)."
  - "do_pick reads (model, ID, alt, resv) via ONE cmd.iterate BEFORE cmd.unpick() — pk1 is a one-atom named selection set by the C layer on click; iterate returns exactly one row. cmd.identify('pk1', mode=1) returns only (model, id) with NO alt (Pitfall 11), so it was replaced entirely."

patterns-established:
  - "on_pick(picked_id, alt='', resv=None) signature — backward compatible (on_pick(100) still works for non-altconf records); the wizard passes alt+resv for alt-conf scoring"
  - "_mark_found(hider_id, rec=None) signature — rec=None defaults to by-id coloring (backward compat for reveal_one/reveal_all); rec passed from on_pick enables the is_altconf middle-range branch"
  - "all_states lifecycle: set in start() (>=2 alt-conf) + re-applied in import_state (>=2 alt-conf reconciled); reset in cleanup()/abort_on_error() via _all_states_was_set flag (object-scoped, never global)"

# Metrics
duration: 7 min
completed: 2026-08-15
---

# Phase 11 Plan 05: Alt-conf Scoring + Orchestrator Wiring Summary

**on_pick dual-lookup + alt/resv gate (scoring truth table) + do_pick iterate pk1 for (model,ID,alt,resv) + _mark_found segi-GAME middle-range coloring (Pitfall 14) + start object-scoped all_states + import_state alt re-apply fallback (Open Risk 3/5)**

## Performance

- **Duration:** 7 min
- **Started:** 2026-08-15T09:12:47Z
- **Completed:** 2026-08-15T09:20:31Z
- **Tasks:** 2
- **Files modified:** 3 (biochemeleon/game.py, biochemeleon/wizard.py, tests/test_game_controller.py)

## Accomplishments

- **on_pick alt/resv gate** (research sec 5 scoring truth table): `on_pick(picked_id, alt='', resv=None)` does a dual lookup — `registry.get(id)` for the anchor CA, then `get_altconf_by_resv(resv)` for non-anchor middle atoms (USER REQ 3: click ANY middle atom). For `is_altconf` records, gates scoring on `alt == rec.alt_tag AND rv1 < resv < rv2` (strict between). Rejects: real trace (alt=''), endpoints (resv=rv1/rv2), no-resv calls. Non-altconf records skip the gate (backward compatible). `getattr(rec, 'is_altconf', False)` defends against old reconstructed records.
- **do_pick iterates pk1 for (model, ID, alt, resv)**: replaced `cmd.identify("pk1", mode=1)` (which returns only `(model, id)` — NO alt, Pitfall 11) with ONE `cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={'stored': props})` BEFORE `cmd.unpick()`. Passes `(aid, alt=alt, resv=resv)` to `on_pick`. ID UPPERCASE (editing.py:1444-1449); space={} hygienic.
- **_mark_found is_altconf branch** (Pitfall 14): for `is_altconf` records, colors `"segi GAME and resi <rv1+1>-<rv2-1>"` (the displaced middle bump) — NOT by shared id (coloring by id colors the real trace too, since alt-conf atoms share ids with originals). `rec=None` defaults to by-id coloring (backward compat for `reveal_one`/`reveal_all`).
- **start alt-conf wiring**: passes `backup_name=self._backup_name` + `is_first_altconf=self._first_altconf` to the dispatcher; registers the 3 alt-conf fields (`is_altconf`/`endpoint_resvs`/`alt_tag`) for 4-tuple cartoon/ribbon payloads; toggles OBJECT-SCOPED `all_states=on` for >=2 alt-conf hiders (Bug 4 Part B; research Example 9 — NOT global).
- **cleanup()/abort_on_error() all_states reset**: reset object-scoped `all_states=off` at the TOP (before restore) via `_all_states_was_set` flag (getattr-guarded for pre-Phase-11 games); setting cleared even if restore raises.
- **import_state alt re-apply fallback** (Open Risk 3): defensively re-applies `alt=rec.alt_tag` on `segi GAME` atoms (idempotent; scoped to `segi GAME` so originals untouched, Pitfall 12). **Open Risk 5**: re-applies object-scoped `all_states=on` when >=2 alt-conf records reconciled (idempotent if already on).
- **11 new WSL tests**: TestOnPickAltconf (7 tests — the full scoring truth table) + TestMarkFoundAltconf (4 unit tests for `_mark_found`). All 313 WSL tests green (302 existing + 11 new); py_compile all; Pitfall-1=0; exec_ gate intact (1 existing QMessageBox); no global all_states set.

## Task Commits

Each task was committed atomically:

1. **Task 1: on_pick alt/resv gate + do_pick iterate pk1 + unit tests (the scoring truth table)** — `9a25f92` (feat)
   - on_pick dual lookup + alt/resv gate; _mark_found is_altconf branch (needed for Test 1); do_pick iterate pk1; 7 TestOnPickAltconf tests
2. **Task 2: _mark_found is_altconf branch + start (backup_name/is_first_altconf/all_states/register fields) + import_state alt re-apply fallback** — `b8474cf` (feat)
   - start alt-conf wiring + object-scoped all_states; cleanup/abort all_states reset; import_state alt+all_states re-apply; 4 TestMarkFoundAltconf unit tests

**Plan metadata:** (pending — created by this commit)

## Files Created/Modified

- `biochemeleon/game.py` (320 → 436 lines) — `on_pick(picked_id, alt='', resv=None)`: dual lookup + alt/resv gate (research sec 5); `_mark_found(hider_id, rec=None)`: is_altconf branch colors segi GAME middle-range (Pitfall 14); `start`: passes backup_name + is_first_altconf, registers 3 alt-conf fields, toggles object-scoped all_states=on for >=2; `cleanup()`/`abort_on_error()`: all_states=off reset at top via _all_states_was_set; `import_state`: Open Risk 3 alt re-apply + Open Risk 5 all_states re-apply.
- `biochemeleon/wizard.py` (83 → 89 lines) — `do_pick`: replaced `cmd.identify("pk1", mode=1)` with `cmd.iterate("pk1", "stored.append((model, ID, alt, resv))", space={'stored': props})` BEFORE unpick; passes `(aid, alt=alt, resv=resv)` to `on_pick`. Module docstring updated (the identify-mode-1 note superseded by the Phase 11 iterate rationale).
- `tests/test_game_controller.py` (513 → 696 lines) — TestOnPickAltconf (7 tests: anchor-middle-CA scores, non-anchor-middle-atom scores, endpoint miss, real-trace miss, no-resv miss, already-found order, sphere backward compat) + TestMarkFoundAltconf (4 tests: 3-residue middle range, 5-residue middle range, rec=None backward compat, non-altconf with rec). Total 35 game-controller tests (24 existing + 11 new).

## Decisions Made

- **_mark_found is_altconf branch in Task 1 (not Task 2):** Task 1's `test_altconf_anchor_middle_ca_scores` asserts `cmd.color` with `"1ubq and segi GAME and resi 3-3"`, which requires the is_altconf coloring branch. The plan's NOTE ("Task 2 makes _mark_found branch on rec") was slightly imprecise prose; the test spec (source of truth for "done") required the branch in Task 1. Implemented the full `_mark_found(hider_id, rec=None)` with the is_altconf branch in Task 1; Task 2 added the dedicated `TestMarkFoundAltconf` unit tests + the `start`/`cleanup`/`import_state` work.
- **`getattr(rec, 'is_altconf', False)` in on_pick:** defends against records rebuilt by old `reconstruct_from_sentinels` (which defaults `is_altconf=False`) — graceful degradation if a pre-Phase-11 `.bcm` is loaded (the alt/resv gate is skipped, anchor-id scoring still works).
- **Object-scoped all_states (NOT global):** `cmd.set("all_states", "on", self.target_obj)` with the object arg. A global set (no object arg) leaks to ALL subsequent objects. The `_all_states_was_set` flag tracks whether `start()`/`import_state` set it, so `cleanup()`/`abort_on_error()` reset it only when needed (getattr-guarded for pre-Phase-11 games that never set it).
- **import_state alt re-apply scoped to full segment range:** `cmd.alter("segi GAME and resi <rv1>-<rv2>", "alt='B'", space={})` — the FULL segment range (incl. endpoints), NOT just the middle. The `segi GAME` scope ensures originals (segi A) are untouched (Pitfall 12). Idempotent (alt='B' on atoms that already have alt='B' is a no-op).
- **do_pick reads (model, ID, alt, resv) via ONE iterate BEFORE unpick:** pk1 is a one-atom named selection set by the C layer on click; iterate returns exactly one row. `cmd.identify("pk1", mode=1)` returns only `(model, id)` with NO alt (Pitfall 11), so it was replaced entirely (not supplemented).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded 1 comment line to avoid a `cmd.set("all_states", "on")` literal false-positive in the grep verification gate**
- **Found during:** Task 2 (verification gates)
- **Issue:** The plan's Task 2 verification requires `grep -nE 'cmd\.set\("all_states", "on"\)' biochemeleon/game.py (0 — NO global set without object arg)`. The actual code calls all include the `self.target_obj` arg (lines 100, 374, 404, 432), so they do NOT match the pattern (the pattern has no third arg). But a comment in `start()` (line 95) contained the literal `cmd.set("all_states", "on")` as an example of what NOT to do ("NOT global (a global cmd.set(..."). `grep -nE` counts literal occurrences regardless of context (the AGENTS.md-documented false-positive pattern: "literal tokens in comments/docstrings trip this grep too").
- **Fix:** Reworded the comment to "NOT global (a global all_states set with NO object arg leaks to ALL subsequent objects)" — preserves the warning semantics without the literal `cmd.set("all_states", "on")` substring.
- **Files modified:** biochemeleon/game.py (1 comment line in `start`)
- **Verification:** `grep -nE 'cmd\.set\("all_states", "on"\)' biochemeleon/game.py` -> exit 1 (0 matches = PASS). All actual `cmd.set("all_states", ...)` calls (4) include `self.target_obj`.
- **Committed in:** `b8474cf` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — comment false-positive grep gate rewording)
**Impact on plan:** Minimal — the rewording preserves the original warning semantics (the comment still explains WHY a global all_states set is forbidden). No code behavior change. Mirrors the established repo precedent (03-02/03-06/03-09/03-10/04-04/11-02/11-04 all reworded docstrings/comments to clear grep gates).

## Issues Encountered

None — both tasks went smoothly. The one subtle point (Task 1's Test 1 requiring the `_mark_found` is_altconf branch that the plan's NOTE attributed to Task 2) was resolved by implementing the branch in Task 1 (following the test spec as source of truth); Task 2 then added the dedicated unit tests + the lifecycle work. No debugging iterations needed.

## User Setup Required

None — no external service configuration required. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer. No `pip install` (opencode.json denies `pip*`/`apt*`/`conda*`).

## Next Phase Readiness

- **Ready for 11-06** (GUI `_prepare_and_start`): `start` now accepts 4-tuple payloads `(chain, start_resi, end_resi, displacement_vec)` for cartoon/ribbon (routed by the 11-04 dispatcher to `insert_altconf_cartoon_hider`) and registers the 3 alt-conf fields. The GUI builds the 4-tuple payloads from `pick_segments` + `generate_middle_displacement` (Wave 1) and passes them through `start`. `backup_name` + `is_first_altconf` flow through automatically.
- **Ready for 11-07** (headless smoke): `on_pick` can be called directly with simulated `(aid, alt, resv)` values to exercise the scoring truth table headlessly (no PickWizard/Qt needed). `start`'s `all_states` toggle + `import_state`'s alt re-apply are pure `pymol.cmd.*` (headless-runnable). The `.pse` round-trip + `alt` survival (Open Risk 2/3) + `all_states` survival (Open Risk 5) can be smoke-verified.
- **Ready for 11-08** (GUI human-verify): the `all_states=on` for >=2 alt-conf hiders (multi-state display) + the `_mark_found` segi-GAME middle-range coloring (found-color on the displaced bump, NOT the real trace) are the GUI human-verify checkpoints. The object-scoped `all_states` (NOT global) + the `zoom=0` on all `cmd.create` (from 11-04) address the 05-08 GUI-only failures.
- **No blockers.** All WSL gates green: 313 tests (35 game-controller + 94 registry + 90 setup_state + 21 generators + 50 persistence + 23 other), py_compile all, Pitfall-1=0, exec_ gate intact (1 existing QMessageBox), no global all_states set, space={} in wizard.py (1), space=None=0. Runtime (headless smoke + GUI human-verify) deferred to Plan 07/08 per the plan.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
