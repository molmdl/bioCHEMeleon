# AGENTS.md

High-signal notes for OpenCode sessions. Read before touching code. See `spec.md` and `.planning/PROJECT.md` for full project context.

> **Scope:** Multi-viewer project. This root file covers **shared/environment concerns only**. Each viewer has its own AGENTS.md with viewer-specific domain rules, architecture, and commands:
> - **`pymol/AGENTS.md`** — v1 PyMOL 2.5.0 plugin (Python/PyQt5, shipped). Read before touching any `pymol/` code.
> - **`vmd/AGENTS.md`** — v2 VMD 1.9.3 tcl script (active milestone). Read before touching any `vmd/` code.
>
> When a milestone is active, read BOTH this root file AND the viewer-specific AGENTS.md for the viewer you're working on.

## Environment — the WSL/Windows split (read first)

This is the single most common way to break things. Both viewers run on Windows; development happens in WSL Ubuntu.

- **Dev shell is WSL Ubuntu.** Do NOT install anything, do NOT create conda envs, do NOT `pip install`. `python3.6` (3.6.9) is for syntax checks and unit tests ONLY. (`opencode.json` denies `pip*`, `apt*`, `conda*`, `rm*`.) `tclsh` (Tcl 8.5/8.6) is available for tcl syntax checks and `tcltest` pure-layer unit tests.
- **PyMOL 2.5.0 runs in a Windows conda env**, not WSL. Accessed via `setenv.bat`. Headless PyMOL CAN be run from WSL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>`. See `pymol/AGENTS.md` for the full staging + headless command.
- **VMD 1.9.3 (Windows) is accessible from WSL** via alias `vmd` → `/mnt/c/Program Files (x86)/University of Illinois/VMD/vmd.exe`. Headless mode: `bash -ic "vmd -dispdev text -e <script> -eofexit < /dev/null"` from a `/mnt/c` cwd (script must be Windows-visible). See `vmd/AGENTS.md` for details.
- **Both viewers' GUIs cannot be run from WSL** — PyMOL needs Qt (real display); VMD needs Tk (doesn't load in `-dispdev text`). GUI/picking-by-real-mouse tests are human-verify checkpoints in both viewers.
- **WSL→Windows path guard applies to both viewers:** Windows PyMOL can't resolve `/mnt/c/...` (needs `C:\...` backslashes); Windows VMD can't resolve `/mnt/c/...` either (needs `C:/...` forward slashes). Each viewer has its own path-converter helper.

## Code & UI standards (spec.md constraints)

- Code must be efficient, traceable, clean, and safe; the repo must be structured.
- UI must be simple and user-friendly, with clear but sufficient in-game explanation.

## Dependencies & attribution (spec.md constraints)

- **v1 (PyMOL):** Assume only what `pymol-open-source` ships (PyQt5 via `pymol.Qt`, numpy). Any additional Python lib must be user-approved. See `pymol/AGENTS.md`.
- **v2 (VMD):** Assume only what VMD 1.9.3 ships (Tcl/Tk 8.5 + ttk). Zero external deps confirmed. Any additional tcl lib (e.g. tooltip.tcl) must be user-approved and vendored under `vmd/3rd_party_lib/` with license noted. See `vmd/AGENTS.md`.
- Do NOT make up anything. ALL claims and citations (DOIs, PDB IDs, sources) MUST BE VERIFIED against a source and explicitly approved by a human. Demo sources: `pymol/biochemeleon/data/demos/SOURCES.md` (v1, reused by v2).

## GSD workflow (`.planning/`)

This repo uses the OpenCode "get-shit-done" workflow. `.planning/` is the source of truth for scope and state:
- `PROJECT.md` (what & why), `ROADMAP.md` (phase plan), `STATE.md` (current position), `REQUIREMENTS.md` (requirement IDs).
- `research/` — `STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `FEATURES.md`, `SUMMARY.md`. Read these before non-trivial viewer work; they encode verified API behavior and the pitfalls behind the viewer-specific AGENTS.md domain rules.
- `phases/<NN-name>/` — `NN-MM-PLAN.md`, `NN-MM-SUMMARY.md`, optional `RESEARCH.md` / `VERIFICATION.md` / `UAT.md`.
- Commit style: Conventional Commits with phase-plan scope, e.g. `feat(02-03):`, `docs(02-03):`, `test(02-01):`, `fix(02):`. Planning docs are committed (`commit_docs: true`).

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

## Git-ignored (don't rely on / don't commit)

`Pymol-script-repo/` (v1 reference plugins), `vmd-ref/` (v2 VMD reference material — UG PDF, bundled tcl plugins, core scripts, tklib tooltip), `3rd_party_lib/` (v1 vendored libs), `vmd/3rd_party_lib/` (v2 vendored libs), `tmp/`, `biochemeleon.zip` (staged fallback install artifact), `*.pyc`.
