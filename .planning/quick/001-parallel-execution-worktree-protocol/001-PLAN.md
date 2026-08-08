---
quick: 001
slug: parallel-execution-worktree-protocol
description: Add Option A (worktree/branch protocol) to AGENTS.md for parallel subagent commit-safety
files_modified:
  - AGENTS.md
autonomous: true
---

<objective>
Add a "Parallel subagent execution" section to AGENTS.md documenting the
worktree/branch protocol (Option A) so future `/gsd-execute-phase` runs with
≥2 parallel plans in a wave avoid the shared-git-index commit collisions that
cost ~3 Rule-3 fixes in Phase 4 Wave 1.

Purpose: Wave 1 of Phase 4 had 3 parallel executors racing on a shared git
index — one agent's `git commit` swept in another's staged files, and parallel
`git reset` calls orphaned commits twice. This protocol eliminates that
collision class by giving each parallel agent its own worktree/branch.

Output: AGENTS.md +~25 lines (one new section between "GSD workflow" and
"Git-ignored").
</objective>

<tasks>

<task type="auto">
  <name>Add "Parallel subagent execution" section to AGENTS.md</name>
  <files>AGENTS.md</files>
  <action>
    In `AGENTS.md`, insert a new `## Parallel subagent execution` section
    BETWEEN the existing `## GSD workflow` section (ends ~line 119) and
    `## Git-ignored` section (starts ~line 121). Use the edit tool to replace
    the `\n## Git-ignored` heading with the new section followed by the
    Git-ignored heading.

    The new section content (insert verbatim):

    ```markdown
    ## Parallel subagent execution (worktree/branch protocol)

    When `/gsd-execute-phase` runs **≥2 plans in parallel** (one wave with
    multiple autonomous plans), each `gsd-executor` subagent commits on a
    **shared git index** — concurrent `git add`/`git commit` calls race and
    sweep in each other's staged files (happened in Phase 4 Wave 1: 3 agents,
    ~3 Rule-3 collision fixes). To eliminate this collision class:

    - **One worktree per parallel plan.** Before spawning a wave, the
      orchestrator creates a git worktree (or branch) per parallel plan:
      `git worktree add tmp/exec-04-01 -b exec/04-01` (etc.). Each agent is
      spawned with `workdir=tmp/exec-04-01` so it commits on an isolated
      index — zero shared-index races.
    - **Merge back in dependency order.** After all agents in the wave return,
      the orchestrator merges/fast-forwards each branch into the base in
      dependency order (`git merge exec/04-01`, then `exec/04-02`, ...). Real
      conflicts (same file touched by two plans — should be rare given
      disjoint `files_modified` frontmatter) are resolved explicitly here.
    - **Single-plan waves skip this.** Waves with one plan (no parallelism)
      need no worktree — commit directly on the base branch. The protocol
      only applies when ≥2 plans run concurrently.
    - **TDD multi-commit safety.** Each agent can still do atomic
      RED/GREEN/REFACTOR commits freely on its own branch — the per-task
      commit granularity is preserved (unlike an orchestrator-owned commit
      gate, which would collapse TDD's commit boundaries).

    Orchestrators: if `parallelization: true` in `.planning/config.json` and a
    wave has >1 plan, use this protocol. See `.planning/quick/001-*` for the
    rationale + rejected alternatives (message-board lock, orchestrator commit
    gate).
    ```

    Do NOT modify any other section of AGENTS.md. Do NOT change the GSD
    workflow section or the Git-ignored list — only insert the new section
    between them.

    Commit: `git add AGENTS.md && git commit -m "docs(quick-001): add parallel-subagent worktree/branch protocol to AGENTS.md"`
  </action>
  <verify>
    - `grep -n "Parallel subagent execution" AGENTS.md` → 1 (the new heading)
    - `grep -n "worktree" AGENTS.md` → >=2 (the protocol mentions worktrees)
    - `grep -n "Git-ignored" AGENTS.md` → 1 (the existing heading still present, AFTER the new section)
    - `grep -n "GSD workflow" AGENTS.md` → 1 (the existing heading still present, BEFORE the new section)
    - Section order: GSD workflow → Parallel subagent execution → Git-ignored (read the file to confirm)
  </verify>
  <done>
    AGENTS.md has the new "Parallel subagent execution" section between GSD
    workflow and Git-ignored; committed; section order correct.
  </done>
</task>

</tasks>

<success_criteria>
- AGENTS.md documents the worktree/branch protocol for parallel executor waves
- Future orchestrators can reference this section to avoid shared-index collisions
</success_criteria>

<output>
After completion, create `.planning/quick/001-parallel-execution-worktree-protocol/001-SUMMARY.md`
</output>
