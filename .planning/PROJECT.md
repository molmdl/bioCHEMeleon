# bioCHEMeleon

## What This Is

A "hide-and-seek" game played on molecular structures inside PyMOL (v1 shipped), VMD (v2 deferred), and chimeraX (future candidate). Given a user-provided molecule or PyMOL scene, the game inserts foreign atoms directly into the molecule's own object — styled to blend with the local representation (line/stick mimic, cartoon/ribbon segment copy, spheres anywhere) — and the player must hunt them down by clicking atoms in the OpenGL viewer. Because hiders live in the same object as the real structure, the player can't trivially isolate them by toggling object visibility; they must visually spot the impostors. For structural-biology users, students, and educators who want an engaging way to explore and study molecular representations.

## Core Value

The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition. If nothing else works, this loop must work.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

#### PyMOL Plugin (v1 — shipped 2026-08-18)

- ✓ Installs as a standard PyMOL plugin (PyMOL 2.5.0) — v1
- ✓ Setup window opens on launch with configurable game parameters — v1
- ✓ Object selector: pick loaded object, fetch from PDB, or choose from demo set (with sub-menu for demo categories) — v1
- ✓ Hider count input (capped to a reasonable maximum) — v1
- ✓ "Lock current scene" checkbox — when true, generate hiders from current representations and detect rep list from the scene; when false, randomize representations and list all available reps — v1
- ✓ Per-representation hider list with optional per-rep counts (random per-rep if unspecified, total respects hider count) — v1
- ✓ Difficulty toggle: show only total remaining (hard) vs. also show remaining per representation (easy) — v1
- ✓ Setup buttons: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup model, Start — v1
- ✓ Generate & export saves the initial game state to a file for sharing / later loading — v1
- ✓ Cleanup model removes all game-generated representations/atoms not in the original object — v1
- ✓ Start stores initial state, generates hiders per setup, switches to Game status tab, and counts down 3-2-1 — v1
- ✓ Game status tab: rolling info box, timer, remaining hiders (total and optionally per-rep), import button, hint button, reveal-one / reveal-all (with confirm), found-hider visibility/color dropdown, save, restart — v1
- ✓ Click-to-find: clicking an atom in the viewer checks if it is a registered hider → marks "found" (recolors or hides it); counts reveal usage for the reveal buttons — v1
- ✓ Hint: changes color of the N atoms/residues around a hider — v1
- ✓ Win: when all hiders are "found", stop the timer and show a winning message with the time taken — v1
- ✓ Save game state as a PyMOL session (`.pse`) + `.bcm` JSON sidecar (zipped `.bcmz`) for checkpointing — v1
- ✓ Restart from the stored initial state — v1
- ✓ Demo PDB set bundled (small) / fetched (large) with sources documented — v1

#### Hider Generation Logic (v1 — shipped)

- ✓ Line/stick hiders: new atoms mimic connected atoms or alternate positions — v1
- ✓ Cartoon/ribbon hiders: replicate a segment (loop) via single-state new-chain copy using C-alpha — v1 (Phase 11 refactor)
- ✓ Sphere hiders: place anywhere — v1
- ✓ Surface representation: NOT supported (out of scope) — v1

### Active

<!-- Current scope. Building toward these. -->

#### VMD tcl Script (v2 — deferred)

- [ ] Sourced tcl + command to launch GUI; similar gameplay to PyMOL
- [ ] Research and limit the set of VMD materials/representations the game plays on
- [ ] Seek approval for any additional VMD tcl libs (e.g. tooltip.tcl)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Surface representation hiders — excluded by user spec; does not fit the "blend in" mechanic well
- VMD plugin — deferred to v2 milestone; different tech (tcl vs python) and testing, delivered as a separate milestone
- Installing packages or creating conda envs in the dev environment — explicit constraint; WSL is for syntax checking only, PyMOL runs in Windows conda via setenv.bat
- Auto-fetching/installing external Python libs silently — any non-PyMOL dependency must be listed to a file, approved by the user, then either user-installed or vendored into ./3rd_party_lib (git-ignored) with license noted

## Context

- **v1 shipped 2026-08-18.** ~14,000 lines of Python (5,621 biochemeleon + 4,420 smoke + 3,959 tests). 125 unit tests green + 6 headless smoke suites + 9 human-verify checkpoints APPROVED. Milestone audit PASSED (46/46 requirements, 12/12 phases, 9/9 integration, 6/6 E2E flows).
- **Working environment:** WSL Ubuntu for development. PyMOL 2.5.0 (anaconda) runs in a Windows conda env, accessed via `setenv.bat` (a Windows cmd.exe batch script). Python 3.6 is available in the WSL shell for syntax checking only — nothing may be installed in WSL, and no conda envs may be created. Headless PyMOL (cmd-only, no Qt) CAN be run from WSL via `cmd.exe /c C:\\src\\run-conda-pymol.bat -cq <script>` (discovered Phase 3).
- **Reference material:** `./Pymol-script-repo` (git-ignored) holds open-source PyMOL plugins for learning how to write PyMOL plugins.
- **Demo PDBs:** 6 bundled small PDBs (1znf, 1xdn, 5E54, 1K8P, 2QBZ, 4WB3) + 3 fetched large demos (1GZM, 3GP6 from MemProtMD; SASDPG4 from SASBDB). Sources cited in `biochemeleon/data/demos/SOURCES.md` and `DATA_SOURCES.md`.
- **Known tech debt (v1):** Phase 9 SSL fallback uses check_hostname=False for SASBDB HARICA cert gap (revisit for v2); Phase 9 .pdb.gz cache in repo-relative tmp/ won't exist for installed plugin (out of v1 scope); Phase 11 hider fragment renders as loop (ss='L') — doesn't inherit parent secondary structure (cosmetic, future enhancement); stale docstrings in game.py/__init__.py (cosmetic).
- **Next milestone:** v2 — VMD tcl script (deferred per spec.md); chimeraX port is a later candidate (placeholder dir chimeraX/ exists). Run `/gsd-new-milestone`.

## Constraints

- **Tech stack:** PyMOL plugin (Python, PyMOL 2.5.0) for v1; VMD tcl script for v2. No web/backend.
- **Compatibility:** Must run under PyMOL 2.5.0 (anaconda, Windows) launched via `setenv.bat`.
- **Dependencies:** Only libraries required by pymol-open-source may be assumed. Any additional Python library must be written to a list file and explicitly approved by the user before use; approved libs are either user-installed locally or vendored into `./3rd_party_lib` (git-ignored) with their license noted. The user must be told whether a Linux-like env is needed or the "call cmd from WSL" approach still works.
- **Environment:** WSL Ubuntu — do NOT install anything, do NOT create conda envs. Python 3.6 is only for syntax checks.
- **Code quality:** Efficient, traceable, clean, safe. Repo must be structured.
- **UI:** Simple, user-friendly, with clear but sufficient in-game explanation.
- **Repo hygiene:** Vendored libs (`3rd_party_lib/`) and the reference repo (`Pymol-script-repo/`) are git-ignored. Large processed demo PDBs should be compressed.

## Key Decisions

<!-- Decisions that constrain future work. Outcomes: ✓ Good, ⚠️ Revisit, — Pending -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| PyMOL plugin is v1, VMD tcl is v2 | Different tech stacks and testing setups; phased delivery reduces risk | ✓ Good — v1 shipped on PyMOL 2.5.0 |
| Hiders are added into the same PyMOL object, not a separate object | Otherwise too easy — player could just hide the whole new object | ✓ Good — core mechanic validated |
| Hider placement depends on representation type (line/stick mimic, cartoon/ribbon segment copy, sphere anywhere) | Matches how each representation visually blends with real structure | ✓ Good — all reps working (Phase 11 closed cartoon gap) |
| Surface representation is not supported | Does not fit the blend-in mechanic; excluded by user spec | ✓ Good — held throughout v1 |
| Find interaction = click picks atom, check if index is a registered hider | Standard PyMOL picking; reliable atom identification | ✓ Good — PickWizard.do_pick → do_select routing fixed in Phase 4 |
| Bundle small demo PDBs, fetch large membrane PDBs on demand | Large MemProtMD files are too big to bundle; small PDBs ensure offline demos work | ✓ Good — 6 bundled + 3 fetched with full attribution |
| No installs / no conda envs in WSL dev env; PyMOL runs in Windows conda via setenv.bat | Explicit user constraint on the working environment | ✓ Good — held throughout |
| Pure-layer architecture (setup_state.py + registry.py stdlib-only, WSL-unit-testable) | Keeps data contract unit-testable in WSL without PyMOL; strict dependency direction | ✓ Good — 125 tests green, 14000 LOC |
| Headless PyMOL from WSL via `cmd.exe /c run-conda-pymol.bat -cq` | Closed the WSL/Windows runtime gap for cmd-only scripts (discovered Phase 3) | ✓ Good — 6 smoke suites run headlessly |
| Parallel-subagent worktree/branch protocol (one worktree per parallel plan) | Eliminates shared-index races when ≥2 plans run concurrently | ✓ Good — no collisions since adoption |
| Phase 11 single-state new-chain copy (abandoned alt-conf design mid-execution) | Alt-conf caused 4 GUI-only bug cycles; single-state copy gives connected, blended cartoon hiders | ✓ Good — verified on 1ubq |

---
*Last updated: 2026-08-18 after v1 milestone*
