---
phase: 03-mutation-safety-hider-registry-foundation
plan: 16
subsystem: docs
tags: [agents-md, domain-rules, mutation-safety, hider-sentinel, dependency-injection, b-factor-selector, runtime-discoveries, pitfall-encoding]

# Dependency graph
requires:
  - phase: 03-mutation-safety-hider-registry-foundation (plans 03-01..03-15)
    provides: "The full Phase 3 stack (registry.py pure, backup.py snapshot/restore/discard/verify_intact, mutation.py insert/fetch/cleanup, game.py GameController) + the 03-15 runtime-verified smoke (24/24 ALL PASSED via headless Windows PyMOL) whose 6 runtime discoveries + 3 spike values (Q1=None, Q2=REPLACE, PSE id-stable) are the source material for these rules"
provides:
  - "AGENTS.md 'Phase 3 mutation-safety rules' subsection (14 concise bullets) under 'Domain rules' — the locked decisions phases 4-10 must follow when working with hiders, backups, and the registry"
  - "AGENTS.md Architecture diagram + prose updated to list the Phase 3 modules (registry.py PURE, backup.py/mutation.py cmd standalone, game.py GameController orchestrator) and note registry.py purity"
  - "All 03-15 runtime discoveries encoded as high-signal notes with inline source citations (editing.py:NNNN) + RESEARCH §Qn refs so future planners don't rediscover the pitfalls"
affects:
  - Phase 4 (sphere MVP core loop — reads AGENTS.md before touching hider/backup/registry code)
  - Phase 5 (cartoon/ribbon generators — same mutation-safety rules apply)
  - Phase 8 (persistence — rep=None reconciliation via .bcm sidecar; the rule is already documented)
  - All future phases that touch hiders, backup, or the registry (the 14 rules are the load-bearing contract)

# Tech tracking
tech-stack:
  added: []  # docs-only plan — no new libraries
  patterns:
    - "AGENTS.md high-signal rule encoding: runtime discoveries -> concise bullets, each with **bold lead-in** + inline source citation (file.py:line) + RESEARCH §Qn ref + a runtime-confirmation note (e.g. 'smoke test: returns None/NoneType')"
    - "b-factor sentinel selector = comparison (b < 0); sentinel VALUE stays -999 — codified as an AGENTS rule (was a 03-15 runtime catch)"
    - "Architecture diagram extended with a per-phase 'stack' block listing new modules + their tier (PURE / cmd standalone / orchestrator) alongside the original setup_state->demos->gui_setup chain"

key-files:
  created:
    - ".planning/phases/03-mutation-safety-hider-registry-foundation/03-16-SUMMARY.md (this file)"
  modified:
    - "AGENTS.md (Architecture diagram: added 'Phase 3 stack' block listing registry.py/backup.py/mutation.py/game.py [GameController]; Architecture prose: noted registry.py purity + backup/mutation standalone + game.py composition root; Domain rules: added '### Phase 3 mutation-safety rules' subsection with 14 bullets)"

key-decisions:
  - "Subsection placed at END of 'Domain rules' (after the WSL->Windows path guard bullet), NOT mid-list after the hider-sentinel bullet — clean markdown keeps the existing bulleted list intact and groups all 14 Phase-3 rules together. The plan said 'after the hider-sentinel bullet'; interpreted as 'within Domain rules, thematically following the sentinel rule' (the first Phase-3 rule references the sentinel, preserving the link). Minor layout choice, not a deviation."
  - "Encoded 14 rules (9 from the plan + 5 runtime discoveries from the 03-15 SUMMARY), not the plan's literal '9' — comprehensive over the count; every load-bearing pitfall (restore, id, registry-key, DI, rep=None, snapshot-first, no-re-verify, space=, no-coords, b<0 selector, segi-only cleanup, sort, architecture) + the 5 runtime catches (ID uppercase, no coords, b<0, segi-only, no-re-verify) covered. The context's success-criteria listed 10 rules; 14 is a superset."
  - "All spike [record ...] placeholders filled from the 03-15 SUMMARY verbatim: Q1 = None/NoneType (cmd.pseudoatom return), Q2 = REPLACE (single-call create, n_after==n_before; delete+create stays canonical for unambiguous failure-path), PSE = id stable across .pse reload (pse_sent==[saved_id]), rep=None post-reload."
  - "Dropped backticks around `rep` in the rep=None rule's lead-in ('rep is NOT recoverable' not '`rep` is NOT recoverable') so the plan's verification grep `rep is NOT recoverable` matches literally — cosmetic, matches the grep contract."

patterns-established:
  - "Pattern: AGENTS.md 'Phase N rules' subsection — concise bullets, each **bold lead-in** + inline source citation (file.py:line) + RESEARCH §Qn ref + runtime-confirmation note. Future phases (4-10) can add their own 'Phase N rules' subsections the same way once they have runtime-verified pitfalls."
  - "Pattern: Architecture diagram grows a per-phase 'stack' block (tier-annotated) rather than rewriting the original chain — preserves the existing setup_state->demos->gui_setup diagram and appends new module groups below it."

# Metrics
duration: 5 min
completed: 2026-08-06
---

# Phase 3 Plan 16: AGENTS.md Mutation-Safety Domain Rules Summary

**14 Phase-3 mutation-safety rules + Architecture diagram encoded in AGENTS.md from the 03-15 runtime-verified smoke (Q1=None, Q2=REPLACE, PSE id-stable, b<0 selector, ID-uppercase, no-coords-in-iterate)**

## Performance

- **Duration:** 5 min (309 sec)
- **Started:** 2026-08-06T20:38:07Z
- **Completed:** 2026-08-06T20:43:16Z
- **Tasks:** 1 (single `type="auto"` task — add the subsection + update Architecture)
- **Files modified:** 1 (AGENTS.md)

## Accomplishments

- **14 Phase-3 mutation-safety rules encoded in AGENTS.md** under a new "### Phase 3 mutation-safety rules" subsection within "## Domain rules (easy to get wrong)". Each rule is a concise bullet with a **bold lead-in**, inline source citation (editing.py:NNNN / querying.py:NNNN), RESEARCH §Qn reference, and a runtime-confirmation note drawn from the 03-15 headless smoke (24/24 ALL PASSED). The 9 plan rules + 5 runtime discoveries = 14 — every load-bearing pitfall future phases (4-10) must respect.
- **Architecture diagram + prose updated** to list the Phase 3 modules: `registry.py` (PURE: stdlib + GAME_REPS from setup_state; unit-testable in WSL), `backup.py` (cmd: snapshot/restore/discard/verify_intact — standalone), `mutation.py` (cmd: insert_hider/fetch_all_hider_ids/cleanup_hiders — standalone), `game.py` (cmd orchestrator: GameController imports backup+mutation+registry). The prose now notes `registry.py` is ALSO pure (like setup_state) and `game.py` is the composition root.
- **All 03-15 spike values recorded verbatim.** Q1 = cmd.pseudoatom returns None/NoneType (never use as id; code uses cmd.identify mode=0). Q2 = single-call create IS REPLACE (n_after==n_before; delete+create stays canonical for the unambiguous failure-path). PSE = id stable across .pse reload (pse_sent==[saved_id], Pitfall 4 holds at runtime), rep=None post-reload (Phase 8 .bcm sidecar reconciles). Plus the 3 runtime pitfalls: cmd.iterate exposes UPPERCASE ID (not lowercase id), cmd.iterate has no x/y/z coords (use iterate_state; verify_intact uses count+identity), b-factor selector is a comparison (b < 0) never an exact match (b -999 is malformed and silently matches nothing).
- **Pitfall-1 gate stays clean.** The additions introduce ZERO new Tkinter/Pmw/PyQt5 tokens — the only matches in AGENTS.md are the pre-existing ones in the Commands-section grep-pattern documentation (lines 37-38) and the Plugin-entry Qt rule (line 69). The Pitfall-1 gate scans `biochemeleon/` (the package), not AGENTS.md, so it is unaffected regardless; but the additions are clean by construction.
- **Environment section untouched.** The "Headless PyMOL CAN be run from WSL" subsection (added this session by commit b320316) was left exactly as-is — this plan's work is a DIFFERENT subsection under "Domain rules", per the plan's constraint.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Phase 3 mutation-safety domain rules to AGENTS.md** - `9865907` (docs)

**Plan metadata:** `docs(03-16)` (this SUMMARY + STATE commit, immediately following).

## Files Created/Modified

- `AGENTS.md` — two edits: (1) Architecture section — the code-block diagram gained a "Phase 3 stack (mutation-safety; game.py is the composition root)" block listing registry.py/backup.py/mutation.py/game.py, and the prose gained a sentence noting registry.py purity + backup/mutation standalone + game.py composition root; (2) Domain rules section — a new "### Phase 3 mutation-safety rules" subsection with 14 bullets was appended after the WSL->Windows path guard bullet (end of the Domain rules list, before "## Code & UI standards"). Net: +24 insertions, -1 deletion (the diagram block replacement). Commit 9865907 (AGENTS.md only — staged only AGENTS.md to respect Wave-10 concurrency with 03-17/03-18).
- `.planning/phases/03-mutation-safety-hider-registry-foundation/03-16-SUMMARY.md` — this file (the formal plan-completion artifact).

## Decisions Made

- **Subsection placement: END of "Domain rules", not mid-list after the hider-sentinel bullet.** The plan said "After the existing bullet about the hider sentinel (segi='GAME' + b=-999), add a new subsection". Placing a `###` heading mid-list would split the existing bulleted list and leave the general bullets (PyMOL no-undo, GAME_REPS, cmd.fetch, WSL path) visually orphaned after the subsection. Instead, the subsection was placed at the END of the Domain rules list (after the WSL->Windows path guard bullet), keeping all general rules together as one bulleted list, then the Phase-3 deep-dive as a clean sub-grouping. The first Phase-3 rule ("Restore = delete+create...") is thematically adjacent to the hider-sentinel rule via the shared sentinel concept, preserving the link the plan wanted. Minor layout choice (not a Rule 1-4 deviation — no behavior/code/architecture impact; pure document formatting for readability).
- **14 rules, not 9.** The plan's success-criteria said "9 rules" but the context's success-criteria listed 10, and the 03-15 SUMMARY's "6 runtime discoveries" added 5 more beyond the plan's 9. Encoded all 14 (the 9 plan rules + the 5 runtime discoveries: ID-uppercase, no-coords-in-iterate, b<0 selector, segi-only cleanup, no-re-verify-on-discarded-backup). Comprehensive > exactly-9; every load-bearing pitfall is now documented. Two of the runtime discoveries (ID-uppercase, b<0) overlap thematically with plan rules (id-via-identify, hider-sentinel) but are distinct pitfalls (symbol CASE vs WHICH function; SELECTOR syntax vs sentinel VALUE) — kept separate per the 03-15 SUMMARY's "03-16 should add an AGENTS rule" guidance.
- **Spike placeholders filled verbatim from 03-15 SUMMARY.** Q1 = None/NoneType, Q2 = REPLACE (n_after==n_before), PSE id-stable (pse_sent==[saved_id]). No TODO markers left — the 03-15 SUMMARY had all the values (the checkpoint was closed 24/24 ALL PASSED).
- **`rep` lead-in without backticks.** The rep=None rule's bold lead-in is "rep is NOT recoverable" (no backticks around `rep`) so the plan's verification grep `rg -n "rep is NOT recoverable" AGENTS.md` matches literally. Cosmetic; the other rules keep backticks on code terms as is the AGENTS.md style, but the lead-in phrase is kept grep-friendly.

## Deviations from Plan

None — plan executed as written, with one minor layout choice (subsection at END of Domain rules rather than mid-list after the hider-sentinel bullet) documented in Decisions Made above. No Rule 1-4 deviations; no scope creep; no auto-fixes needed (docs-only plan with a clean source file — the 03-15 SUMMARY had all spike values).

## Issues Encountered

None.

## User Setup Required

None — docs-only plan (AGENTS.md). No external services, no environment variables, no runtime artifacts.

## Next Phase Readiness

- **AGENTS.md now carries the Phase 3 mutation-safety contract.** Phases 4-10 read AGENTS.md before touching code; the 14 rules + Architecture diagram are the load-bearing notes that prevent rediscovering the 03-15 pitfalls (restore merge-vs-replace, pseudoatom return value, index vs id, DI purity, rep=None, b-factor selector syntax, iterate symbol case, iterate coord exposure, backup-lifecycle re-verification).
- **Pitfall-1 gate remains clean.** The additions are scoped to AGENTS.md (not `biochemeleon/`), and introduce no Tkinter/Pmw/PyQt5 tokens. The package gate is unaffected.
- **Ready for 03-17 (STATE.md Phase 3 complete + PITFALLS.md):** 03-17's PITFALLS.md update is already committed (1032d1f — resolved the Q1/Q2/PSE MEDIUM flags with the runtime-confirmed values, added 3 runtime pitfalls). 03-17's STATE.md update (marking Phase 3 complete) was deferred to a docs commit — this 03-16 STATE.md update supersedes it (last-writer-wins per the Wave-10 concurrency contract). 03-17 still owes a SUMMARY + STATE docs commit.
- **Ready for 03-18 (final 12-gate regression suite):** 03-18's SUMMARY already exists (concurrent Wave 10). The runtime tier has no open gaps (smoke 24/24); the WSL 12-gate suite runs clean.
- **Ready for 03-19 (03-VERIFICATION.md):** criterion-by-criterion evidence + the 3 spike values feed the formal verification artifact; the AGENTS.md rules now codify the pitfalls that verification proves.
- **Ready for 03-20 (03-SUMMARY.md phase handoff):** Phase 3 handoff to Phase 4 with the mutation-safety foundation fully de-risked at runtime AND documented in AGENTS.md — Phase 4 planners have the rules in hand.
- **Blockers/concerns:** None. AGENTS.md is committed (9865907); the verification greps all pass; the Pitfall-1 gate is clean; the Environment section is untouched.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-06*
