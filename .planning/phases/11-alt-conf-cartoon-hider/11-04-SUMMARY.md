---
phase: 11-alt-conf-cartoon-hider
plan: 04
subsystem: mutation
tags: [pymol, alt-conf, cartoon, ribbon, hider, cmd-coupled, mutation, dispatcher]

# Dependency graph
requires:
  - phase: 11-alt-conf-cartoon-hider-01
    provides: pick_segments (disjoint mid-chain segment picker) + generate_middle_displacement (rigid unit-vector RNG) from generators.py (Wave 1, pure layer)
  - phase: 05-cartoon-hider
    provides: insert_cartoon_hider (legacy terminal-extension path, kept for 3-tuple backward compat) + insert_hider_for_rep dispatcher skeleton
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: b<0 selector convention, space={} hygiene, ID uppercase, zoom=0 pitfall, id-keyed registry, backup.snapshot-before-insert invariant
provides:
  - insert_altconf_cartoon_hider(object, chain, start_resi, end_resi, handle, backup_name, rep, displacement, is_first_altconf, segi, b) — the 4-call alt-conf construction (create tmp from clean backup -> alter alt/segi/ss -> alter_state middle displacement -> create append -> delete tmp) returning the anchor middle-CA stable id
  - insert_hider_for_rep arity-based dispatcher extension — 4-tuple payloads route to insert_altconf_cartoon_hider (Phase 11); 3-tuple payloads keep the legacy insert_cartoon_hider path (backward compat with phase5_smoke)
affects: [11-06 (_prepare_and_start builds 4-tuple payloads + passes backup_name/is_first_altconf), 11-07 (headless smoke exercises the full alt-conf lifecycle), 11-08 (GUI human-verify for auto-zoom/multi-state/coord-corruption), future on_pick/wizard extension plans (alt/resv gate consumes the anchor id this returns)]

# Tech tracking
tech-stack:
  added: []  # no new libraries — pure pymol.cmd.* (PyMOL 2.5.0 open-source)
  patterns:
    - "4-call alt-conf construction sequence (create tmp from clean backup -> alter alt/segi/ss -> alter_state rigid middle displacement -> create append with target_state -> delete tmp) — replaces the Phase 5 terminal-extension attach_amino_acid approach"
    - "Arity-based backward-compatible dispatcher routing (4-tuple -> new path; 3-tuple -> legacy path) — zero migration for existing callers"
    - "Source from CLEAN backup (NOT live object) for multi-hider safety — Bug 4 Part A; insert_altconf_cartoon_hider receives backup_name, NEVER reads from the live object which may already hold alt-conf atoms from a prior hider in the same round"
    - "target_state=0 for 1st alt-conf (state 1), -1 for 2nd+ (new state) — Bug 4 Part B; avoids retroactive coord corruption on the 1st alt-conf"
    - "Rigid displacement on TEMP before append (NOT on obj after append) — sidesteps Bug 2 iterate_state corruption; alter_state runs on the single-state tmp, then create carries the displaced coords into the target state"

key-files:
  created: []
  modified:
    - biochemeleon/mutation.py

key-decisions:
  - "Displacement runs on tmp (BEFORE the append), NOT on obj (after the append) — cleaner than research Example 1 (which displaced on obj post-append and had to derive hider_state); tmp is single-state so alter_state(1, tmp_sele, ...) is unambiguous, and cmd.create carries the displaced coords into the target state (create copies coords bit-for-bit)"
  - "handle param kept in signature for symmetry with insert_hider/insert_line_stick_hider/insert_cartoon_hider but UNUSED in the body — alt-conf copies inherit the source residue atom names (N/CA/C/O), so the anchor is selected by chain+resi+name CA+segi GAME, not by atom name handle (documented in docstring)"
  - "Arity-based routing (len(payload) == 4) over an explicit flag — zero migration for existing 3-tuple callers (phase5_smoke, any Phase 5 GUI paths); the dispatcher auto-detects Phase 11 vs Phase 5 payloads"
  - "Reworded 2 docstring lines to avoid space=None / b -999 literal false-positives tripping the grep verification gates — mirrors the 03-02/03-06/03-09/03-10/04-04 precedent (Rule 3 blocking)"

patterns-established:
  - "insert_altconf_cartoon_hider signature: (object, chain, start_resi, end_resi, handle, backup_name, rep='cartoon', displacement=None, is_first_altconf=True, segi='GAME', b=-999.0) -> int anchor middle-CA id — consumed by Plan 06 _prepare_and_start (builds 4-tuple payloads) and Plan 07 headless smoke"
  - "insert_hider_for_rep signature: (object, rep, payload, handle, backup_name=None, is_first_altconf=True) — backup_name + is_first_altconf are passed through ONLY on the 4-tuple alt-conf path; ignored by spheres/lines/sticks and the 3-tuple legacy cartoon path"
  - "Anchor on FIRST MIDDLE residue CA (resi=start_resi+1) — fetch_all_hider_ids (segi GAME and b<0) returns exactly 1 atom per hider (USER REQ 3); the registry registers this single anchor id"

# Metrics
duration: 6 min
completed: 2026-08-15
---

# Phase 11 Plan 04: Alt-conf Cartoon/Ribbon Hider Construction Summary

**The 4-call alt-conf backbone-only segment construction (insert_altconf_cartoon_hider) + arity-based backward-compatible dispatcher routing in insert_hider_for_rep, with all 4 Bug fixes (zoom=0, space={}, b<0 selector, clean-backup sourcing, target_state multi-hider)**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-08-15T09:00:00Z
- **Completed:** 2026-08-15T09:06:17Z
- **Tasks:** 2
- **Files modified:** 1 (biochemeleon/mutation.py)

## Accomplishments
- `insert_altconf_cartoon_hider` implements the 4-call alt-conf construction sequence (research §3b, 10/10 headless verified mechanism): (1) `cmd.create(tmp, "<backup> and chain X and resi N-M and backbone", 1, 1, zoom=0)` copies BACKBONE ONLY from the CLEAN backup (Bug 4 Part A; USER REQ 1); (2) `cmd.alter(tmp, "alt='B'; segi='GAME'; ss='L'", space={})` tags alt-conf + sentinel + loop ss on TEMP (hygienic; Pitfall 12); (3) `cmd.alter_state(1, "<tmp middle>", "x=x+dx; y=y+dy; z=z+dz", space={})` rigid-translates ALL middle backbone atoms by the SAME offset (Pitfall 15; USER REQ 2; endpoints NOT displaced = blend); (4) `cmd.create(object, tmp, target_state=(0 if first else -1), zoom=0)` appends as true alt-conf (Bug 4 Part B; Bug 3 zoom=0); (5) `cmd.delete(tmp); cmd.sort(object)`.
- The anchor b=-999 sentinel is set on the FIRST MIDDLE residue CA (resi=start_resi+1), selected by `chain + resi + name CA + segi GAME` (NOT by shared id — Pitfall 4; NOT by atom name handle — alt-conf copies inherit source atom names). `fetch_all_hider_ids` (segi GAME and b<0) returns exactly 1 atom per hider (USER REQ 3).
- All 4 Bug fixes from the reverted 05-08 attempt are baked in: (1) id collision -> Plan 01 disjoint segments (consumed downstream); (2) iterate_state corruption -> displacement runs on tmp (BEFORE append), not on obj (after); (3) auto-zoom -> `zoom=0` on BOTH cmd.create calls; (4) retroactive coord corruption -> source from clean `backup_name` + `target_state=-1` for 2nd+ alt-conf.
- `insert_hider_for_rep` extended with `backup_name=None` + `is_first_altconf=True` params and ARITY-based cartoon/ribbon routing: 4-tuple `(chain, start_resi, end_resi, displacement_vec)` -> `insert_altconf_cartoon_hider` (Phase 11); 3-tuple `(chain, terminus_resi, is_c_terminus)` -> legacy `insert_cartoon_hider` (backward compat with phase5_smoke). spheres/lines/sticks/else branches UNCHANGED. `insert_cartoon_hider` NOT deleted.
- All WSL gates green: py_compile all modules; 269 pure-layer tests (test_setup_state + test_registry + test_generators + test_persistence) pass (no regression); Pitfall-1 = 0; exec_ gate = 1 (existing QMessageBox in gui_game.py only); zoom=0 = 5; space={} = 9; space=None = 0; b -999 selector = 0; b < 0 = 6.

## Task Commits

Each task was committed atomically:

1. **Task 1: insert_altconf_cartoon_hider — the 4-call alt-conf construction** — `db3c3d2` (feat)
2. **Task 2: Extend insert_hider_for_rep dispatcher — arity-based routing** — `c724217` (feat)

**Plan metadata:** (pending — created after this SUMMARY)

## Files Created/Modified
- `biochemeleon/mutation.py` — added `insert_altconf_cartoon_hider` (lines 485-576, the 4-call alt-conf construction with all pitfall rules; placed under `# ---- Alt-conf cartoon/ribbon inserter (Phase 11) ----` between `insert_cartoon_hider` and `insert_hider_for_rep`); extended `insert_hider_for_rep` signature with `backup_name=None` + `is_first_altconf=True` (line 579) and replaced the `elif rep in ('cartoon', 'ribbon'):` branch with arity-based routing (4-tuple -> alt-conf; 3-tuple -> legacy; lines 644-659). Also reworded 2 docstring lines (fetch_all_hider_ids line 102 + insert_altconf_cartoon_hider line 531) to avoid space=None / b -999 literal false-positives in the grep verification gates.

## Decisions Made
- **Displacement on tmp (BEFORE append), not on obj (AFTER append):** The plan body specifies the displacement runs on `tmp` at step 3 (before the append at step 4), which is cleaner than research Example 1 (which displaced on `obj and segi GAME and alt B` at step 5 after the append and had to derive `hider_state`). The tmp-first approach: (a) tmp is single-state, so `alter_state(1, tmp_sele, ...)` is unambiguous (no hider_state derivation needed); (b) `cmd.create` copies coords bit-for-bit, so the displaced coords travel into the target state; (c) sidesteps Bug 2 (iterate_state corruption) entirely — we never read state coords from obj after an alt-conf insert. This is a load-bearing improvement over the research example and matches the plan body verbatim.
- **handle param UNUSED in body (documented in docstring):** The alt-conf copies inherit the source residue's atom names (N/CA/C/O), not a throwaway handle. The anchor is selected by `chain + resi + name CA + segi GAME`. handle is kept in the signature for symmetry with the other inserters (so the dispatcher can pass it uniformly) but is documented as unused. The plan explicitly required this documentation.
- **Arity-based routing (len(payload) == 4) over an explicit flag:** Zero migration for existing 3-tuple callers (phase5_smoke, Phase 5 GUI paths). The dispatcher auto-detects Phase 11 (4-tuple) vs Phase 5 (3-tuple) payloads. Plan 06 will build 4-tuple payloads; existing 3-tuple callers keep working without change.
- **Reword 2 docstring lines to clear grep gates (Rule 3 blocking):** The plan's verification requires `grep -nE "space=None" biochemeleon/mutation.py (0)` and `grep -nE "b -999" biochemeleon/mutation.py (0)`. The existing `fetch_all_hider_ids` docstring (line 102) contained `space=None` in prose ("NOT ``space=None``"), and my new `insert_altconf_cartoon_hider` docstring (line 531) contained `b -999` in prose ("NEVER ``b -999``"). Both are documentation WARNING AGAINST using those tokens, but `grep -nE` counts literal occurrences regardless of context (the AGENTS.md-documented false-positive pattern). Reworded both to preserve the warnings without the literal tokens: "(NOT the bare None default, which runs...)" and "(NEVER an exact-match on the sentinel value -- PyMOL has no exact-match b-factor selector and the literal equality form is malformed...)". Mirrors the 03-02/03-06/03-09/03-10/04-04 precedent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded docstrings to avoid space=None / b -999 literal false-positives in grep verification gates**
- **Found during:** Task 1 (verification gates)
- **Issue:** The plan's Task 1 verification requires `grep -nE "space=None" biochemeleon/mutation.py (0)` and `grep -nE "b -999" biochemeleon/mutation.py (0)`. The pre-existing `fetch_all_hider_ids` docstring (line 102) contained the literal `space=None` in prose ("NOT ``space=None``"), and the new `insert_altconf_cartoon_hider` docstring (line 531) contained the literal `b -999` in prose ("NEVER ``b -999``"). Both are documentation WARNING AGAINST using those tokens (the AGENTS.md-documented false-positive pattern: "literal tokens in comments/docstrings trip this grep too"). `grep -nE` counts literal occurrences regardless of context, so the gates would fail (1 match each instead of 0).
- **Fix:** Reworded both docstring lines to preserve the warnings without the literal tokens:
  - Line 102: "(NOT ``space=None``, which runs..." -> "(NOT the bare None default, which runs..."
  - Line 531: "The SELECTOR is ``b < 0`` (NEVER ``b -999`` -- malformed; AGENTS.md)." -> "The SELECTOR is ``b < 0`` (NEVER an exact-match on the sentinel value -- PyMOL has no exact-match b-factor selector and the literal equality form is malformed, silently matching nothing; AGENTS.md)."
- **Files modified:** biochemeleon/mutation.py
- **Verification:** `grep -nE "space=None" biochemeleon/mutation.py` -> exit 1 (0 matches = PASS); `grep -nE "b -999" biochemeleon/mutation.py` -> exit 1 (0 matches = PASS). All other gates unaffected (b < 0 = 6, space={} = 9).
- **Committed in:** db3c3d2 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking — grep gate false-positive rewording)
**Impact on plan:** Minimal — the rewording preserves the original warning semantics (the docstrings still explain WHY `space=None` and exact-match b-factor selectors are forbidden). No code behavior change. Mirrors the established repo precedent (03-02/03-06/03-09/03-10/04-04 all reworded docstrings to clear grep gates).

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required. Pure `pymol.cmd.*` (PyMOL 2.5.0 open-source) + existing pure layer. No `pip install` (opencode.json denies `pip*`/`apt*`/`conda*`).

## Next Phase Readiness
- `insert_altconf_cartoon_hider` + the extended `insert_hider_for_rep` dispatcher are ready for Plan 06 (`_prepare_and_start`), which will build 4-tuple payloads `(chain, start_resi, end_resi, displacement_vec)` from `pick_segments` + `generate_middle_displacement` (Wave 1) and pass `backup_name=self._backup_name` + `is_first_altconf` through the dispatcher.
- Plan 07 (headless smoke) will exercise the full alt-conf lifecycle: insert -> sentinel -> show rep -> verify_intact after backup.restore -> .pse round-trip -> `alt` survival (Open Risk 2/3).
- Plan 08 (GUI human-verify) is the MANDATORY methodology checkpoint — headless smoke is structurally blind to `auto_zoom`, multi-state display, and retroactive coord corruption (the 05-08 methodology failure). The `zoom=0` on both `cmd.create` calls (Bug 3) and `target_state=-1` for 2nd+ alt-conf (Bug 4 Part B) are baked in here; Plan 08 verifies them in a real Windows PyMOL GUI session.
- No blockers. Runtime is deferred to Plan 07/08 per the plan — this plan is cmd-coupled (py_compile + grep gates only; no headless run here).
- The `handle` param being UNUSED in the alt-conf body is documented and intentional — Plan 06/07 callers can still pass it uniformly through the dispatcher for signature symmetry.

---
*Phase: 11-alt-conf-cartoon-hider*
*Completed: 2026-08-15*
