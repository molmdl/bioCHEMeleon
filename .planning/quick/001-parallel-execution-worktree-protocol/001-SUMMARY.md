---
quick: 001
slug: parallel-execution-worktree-protocol
subsystem: infra
tags: [git, worktree, parallel-execution, gsd, orchestrator, agents-md]

# Dependency graph
requires:
  - phase: phase-04 (MVP Core Loop) — Wave 1 shared-index collision incident
    provides: the empirical motivation (3 parallel executors raced on a shared git index, ~3 Rule-3 collision fixes)
provides:
  - Documented worktree/branch protocol in AGENTS.md for parallel `gsd-executor` commit-safety
  - Referenceable `.planning/quick/001-*` for the rationale + rejected alternatives
affects: [gsd-orchestrator, future-parallel-waves, phase-04-wave-1-and-later, agent-spawning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One-worktree-per-parallel-plan: orchestrator creates `git worktree add tmp/exec-NN-MM -b exec/NN-MM` per parallel plan, spawns each agent with workdir=that path for isolated git index"
    - "Merge-back-in-dependency-order: orchestrator fast-forwards/merges each exec branch into base in order after all agents return"
    - "Single-plan-waves-skip-worktree: only ≥2 concurrent plans need worktrees"

key-files:
  created: []
  modified:
    - AGENTS.md (inserted "Parallel subagent execution (worktree/branch protocol)" section, +31 lines)

key-decisions:
  - "Chose Option A (worktree/branch protocol) over message-board lock and orchestrator commit gate — isolates index per agent without collapsing TDD commit granularity"
  - "Protocol applies ONLY when ≥2 plans run concurrently; single-plan waves commit directly on the base branch (zero overhead for the common case)"

patterns-established:
  - "Parallel-execution commit-safety: one worktree per parallel plan → isolated index → merge back in dependency order"

# Metrics
duration: 2min
completed: 2026-08-08
---

# Quick Task 001: Parallel Execution Worktree Protocol Summary

**Added the worktree/branch protocol to AGENTS.md so future `/gsd-execute-phase` waves with ≥2 parallel plans avoid the shared-git-index commit collisions that cost ~3 Rule-3 fixes in Phase 4 Wave 1**

## Performance

- **Duration:** ~2 min
- **Completed:** 2026-08-08T05:05Z
- **Tasks:** 1
- **Files modified:** 1 (AGENTS.md)

## Accomplishments
- Inserted a new `## Parallel subagent execution (worktree/branch protocol)` section between the existing `## GSD workflow` and `## Git-ignored` sections of AGENTS.md (+31 lines)
- Documented the one-worktree-per-parallel-plan protocol (`git worktree add tmp/exec-NN-MM -b exec/NN-MM`, spawn agents with `workdir=tmp/exec-NN-MM`) so each parallel `gsd-executor` commits on an isolated git index — eliminating shared-index races
- Documented merge-back-in-dependency-order, single-plan-wave skip rule, and TDD multi-commit safety guarantees
- Referenced `.planning/quick/001-*` for the rationale + rejected alternatives (message-board lock, orchestrator commit gate) so future readers can find the why

## Task Commits

Each task was committed atomically:

1. **Task 1: Add "Parallel subagent execution" section to AGENTS.md** - `531d92e` (docs)

**Plan metadata:** not yet committed (SUMMARY.md created below; per task constraints, STATE.md/ROADMAP.md are NOT updated by this executor — the orchestrator handles STATE.md after return)

## Files Created/Modified
- `AGENTS.md` - Inserted the "Parallel subagent execution (worktree/branch protocol)" section (lines 121-150) between "GSD workflow" (ends line 119) and "Git-ignored" (now line 152). No other section touched.

## Decisions Made
- **Chose the plan's verbatim section content.** Inserted the markdown block from the plan's `<action>` exactly as specified (the protocol bullet list, the "Orchestrators:" closing paragraph, and the `.planning/quick/001-*` reference). No rewording — the plan content was the canonical source.
- **Edit anchor choice.** Used the GSD-workflow section's last bullet line + blank line + `## Git-ignored` heading as a unique anchor (the blank-line-then-heading pair alone is non-unique across the file). This guarantees the new section lands in the correct position with zero ambiguity.
- **Scope discipline.** Per the explicit constraint, did NOT update STATE.md or ROADMAP.md (quick tasks are separate from planned phases; the orchestrator handles STATE.md after the executor returns).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. This is a single-file documentation edit.

## Next Phase Readiness
- AGENTS.md now documents the worktree/branch protocol; future `/gsd-execute-phase` orchestrators running parallel waves can reference this section to avoid shared-index collisions.
- The protocol is opt-in by wave size: single-plan waves skip it (commit directly on the base branch), only ≥2-plan waves create worktrees.
- Rejected alternatives (message-board lock, orchestrator commit gate) are referenced via the `.planning/quick/001-*` pointer for anyone questioning the choice.
- No blockers or concerns.

---
*Quick: 001 — parallel-execution-worktree-protocol*
*Completed: 2026-08-08*
