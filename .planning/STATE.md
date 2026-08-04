# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-02)

**Core value:** The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition.
**Current focus:** Phase 2 — Setup Tab Configuration & Bundled Demos (Wave 2 done; Wave 3 = 02-04 smoke test)

## Current Position

Phase: 2 of 10 (in progress)
Plan: 3 of 4 in Phase 2 (02-04 = Windows PyMOL smoke test, the human-verify checkpoint)
Status: Wave 2 complete; ready for Wave 3 (02-04)
Last activity: 2026-08-04 — Completed 02-03-PLAN.md (demos.py + gui_setup.py populated)

Progress: [████████░░] 80% (4/5 concrete plans: 01-01, 02-01, 02-02, 02-03)

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: ~11 min
- Total execution time: ~0.7 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Plugin Bootstrap & Dialog Scaffold | 1 | ~35 min | ~35 min |
| 2. Setup Tab Configuration & Bundled Demos | 3/4 | ~7 min | ~2 min |

**Recent Trend:**
- Last 4 plans: 01-01 ~35min, 02-01 ~2min, 02-02 ~1min, 02-03 ~4min
- Trend: Phase 2 plans are fast (pure code + grep gates; no Windows PyMOL needed until 02-04)

*Updated after each plan completion*

## Accumulated Context

### Wave 1 outputs (02-01 + 02-02 — STILL AVAILABLE)

- **setup_state.py (Plan 02-01)**: GAME_REPS (5 reps), DEMO_MANIFEST (6 demos), DEFAULTS (9 keys), SETUP_FORMAT, hider_count_cap, randomize_state, validate_state. 48 unit tests pass.
- **data/demos/*.pdb (Plan 02-02)**: 6 valid PDBs (1znf, 1xdn, 5e54, 1k8p, 2qbz, 4wb3) + SOURCES.md (64 lines, 6 DOIs). Git-tracked.

### Wave 2 outputs (02-03 — JUST COMPLETED)

- **demos.py (137 lines)**: 5 cmd-coupled utilities — to_windows_path (WSL guard), list_loaded_molecule_objects, fetch_pdb (async_=0), get_active_reps (`rep <name>` selector), load_demo (__file__-relative + cmd.load). Imports GAME_REPS, DEMO_MANIFEST from setup_state.
- **gui_setup.py (390 lines)**: full SetupTab — PyMOLObjectCombo, 3-mode QStackedWidget, capped hider spinbox, lock-scene auto-detect, 5 per-rep rows, difficulty toggle, 4 buttons, collect/apply round-trip, JSON save/load, randomize/validate.

### Decisions

Decisions are logged in PROJECT.md Key Decisions table. Recent decisions affecting current work:

- [Roadmap]: PyMOL plugin (PyQt5 via `pymol.Qt`) is v1; VMD tcl is v2 — phased delivery
- [Roadmap]: Phase order de-risks object mutation (Phase 3) BEFORE generators, ships sphere MVP (Phase 4) ASAP
- [Roadmap]: Cartoon/ribbon generators (Phase 5) flagged as highest-risk / highest-research area
- [Roadmap]: Hider sentinels `segi='GAME'` + `b=-999` are the cleanup-safety and session-reload mechanism
- [Phase 1]: PluginDialog lives in `__init__.py`; all GUI modules use `from pymol.Qt import` (never raw PyQt5); dialog is modeless `.show()`
- [02-01]: GAME_REPS and DEMO_MANIFEST live in setup_state.py (pure layer); demos.py imports FROM it
- [02-02]: PDB filenames lowercase, package-relative under biochemeleon/data/demos/
- [02-03]: hider_count_cap imported from setup_state (NOT demos) — single source of truth for pure layer
- [02-03]: apply_state uses a _loading flag (not blockSignals) to suppress cascading signal handlers during programmatic state application — ensures Save->Load round-trips verbatim
- [02-03]: demos.py is the cmd-coupled bridge; gui_setup.py imports FROM setup_state (pure) AND demos (cmd bridge) — never the reverse
- [02-03]: load_demo imported by gui_setup per key_links API contract but not called in Phase 2 (demo loading deferred to Phase 4 Start button)

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 5]: Cartoon/ribbon hider geometry is genuinely novel (no reference plugin) — likely to need a research spike and is the most likely phase to slip into a sub-phase or v1.x
- [Phase 9]: MemProtMD was unreachable at research time — per-entry license MUST be verified before bundling membrane coordinates
- [Cross-phase]: PyMOL Open Source has NO undo — every destructive op needs a `cmd.create('_bchm_backup', ...)` snapshot + restore-on-failure (Phase 3 establishes this; all later phases rely on it)
- [02-04]: The `rep <name>` selector and the hider-count cap are WSL-unverifiable (need Windows PyMOL); the 02-04 smoke test is the formal confirmation (research 12.1 mitigation: per-rep try/except degrades gracefully)

## Session Continuity

Last session: 2026-08-04 (Plan 02-03 executed — demos.py + gui_setup.py populated, all verification gates passed)
Stopped at: Completed 02-03-PLAN.md. Wave 2 complete. Ready for Wave 3 (02-04 Windows PyMOL smoke test — human-verify checkpoint).
Resume file: .planning/phases/02-setup-tab-configuration-bundled-demos/02-03-SUMMARY.md
