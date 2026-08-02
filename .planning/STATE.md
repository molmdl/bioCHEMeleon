# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-02)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** Phase 2 — Setup Tab Configuration & Bundled Demos (next)

## Current Position

Phase: 1 of 10 COMPLETE → ready for Phase 2
Plan: 1 of 1 in Phase 1 (verified passed 5/5)
Status: Phase 1 verified complete; ready to plan Phase 2
Last activity: 2026-08-03 — Phase 1 verified (5/5 must-haves, PLUGIN-01/02/03 satisfied)

Progress: [█░░░░░░░░░] 10%

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: ~35 min
- Total execution time: ~0.6 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1 | ~35 min | ~35 min |

**Recent Trend:**
- Last 5 plans: 01-01: ~35min (plugin shell)
- Trend: baseline (1 plan)

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- [Roadmap]: PyMOL plugin (PyQt5 via `pymol.Qt`) is v1; VMD tcl is v2 — phased delivery
- [Roadmap]: Phase order de-risks object mutation (Phase 3) BEFORE generators, and ships the sphere MVP core loop (Phase 4) ASAP per PROJECT.md core value
- [Roadmap]: Cartoon/ribbon generators (Phase 5) flagged as highest-risk / highest-research area
- [Roadmap]: Hider sentinels `segi='GAME'` + `b=-999` are the cleanup-safety and session-reload mechanism
- [Phase 1]: PluginDialog lives in `__init__.py` (Option A) — may extract to `gui_dialog.py` if it grows in Phase 2
- [Phase 1]: Install workflow = copy `biochemeleon/` to `tmp/` + Plugin Manager (clean-source); scan-path/junction is an alternative for live-edit
- [Phase 1]: All GUI modules use `from pymol.Qt import` (never `from PyQt5 import`); entry point is `__init_plugin__(app=None)`; dialog is modeless `.show()` (never `.exec_()`)
- [Phase 1]: 3 stub modules (wizard.py/game.py/demos.py) created as placeholders; demos.py carries the `to_windows_path()` Phase-2 TODO

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 5]: Cartoon/ribbon hider geometry is genuinely novel (no reference plugin) — likely to need a research spike and is the most likely phase to slip into a sub-phase or v1.x
- [Phase 9]: MemProtMD was unreachable at research time — per-entry license MUST be verified before bundling membrane coordinates
- [Cross-phase]: PyMOL Open Source has NO undo — every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (Phase 3 establishes this; all later phases rely on it)

## Session Continuity

Last session: 2026-08-03 (Phase 1 executed, smoke test approved, verified 5/5 passed)
Stopped at: Phase 1 COMPLETE (verified). Ready to discuss/plan Phase 2.
Resume file: .planning/phases/01-plugin-bootstrap-dialog-scaffold/01-01-SUMMARY.md
