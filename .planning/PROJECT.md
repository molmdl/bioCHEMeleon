# CHEMeleon

## What This Is

A "hide-and-seek" game played on molecular structures inside PyMOL (v1) and VMD (v2). Given a user-provided molecule or PyMOL scene, the game inserts foreign atoms directly into the molecule's own object — styled to blend with the local representation (line/stick mimic, cartoon/ribbon extension or loop replica, spheres anywhere) — and the player must hunt them down by clicking atoms in the OpenGL viewer. Because hiders live in the same object as the real structure, the player can't trivially isolate them by toggling object visibility; they must visually spot the impostors. For structural-biology users, students, and educators who want an engaging way to explore and study molecular representations.

## Core Value

The player can load a molecule, generate blended "hider" atoms that match the local representation style, and reliably find them by clicking — with a working timer and win condition. If nothing else works, this loop must work.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

#### PyMOL Plugin (v1)

- [ ] Installs as a standard PyMOL plugin (PyMOL 2.5.0)
- [ ] Setup window opens on launch with configurable game parameters
- [ ] Object selector: pick loaded object, fetch from PDB, or choose from demo set (with sub-menu for demo categories)
- [ ] Hider count input (capped to a reasonable maximum)
- [ ] "Lock current scene" checkbox — when true, generate hiders from current representations and detect rep list from the scene; when false, randomize representations and list all available reps
- [ ] Per-representation hider list with optional per-rep counts (random per-rep if unspecified, total respects hider count)
- [ ] Difficulty toggle: show only total remaining (hard) vs. also show remaining per representation (easy)
- [ ] Setup buttons: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup model, Start
- [ ] Generate & export saves the initial game state to a file for sharing / later loading
- [ ] Cleanup model removes all game-generated representations/atoms not in the original object
- [ ] Start stores initial state, generates hiders per setup, switches to Game status tab, and counts down 3-2-1
- [ ] Game status tab: rolling info box, timer, remaining hiders (total and optionally per-rep), import button, hint button, reveal-one / reveal-all (with confirm), found-hider visibility/color dropdown, save, restart
- [ ] Click-to-find: clicking an atom in the viewer checks if it is a registered hider → marks "found" (recolors or hides it); counts reveal usage for the reveal buttons
- [ ] Hint: changes color of the N atoms/residues around a hider
- [ ] Win: when all hiders are "found", stop the timer and show a winning message with the time taken
- [ ] Save game state as a PyMOL session + game-specific state info for checkpointing
- [ ] Restart from the stored initial state
- [ ] Demo PDB set bundled (small) / fetched (large) with sources documented

#### Hider Generation Logic (v1)

- [ ] Line/stick hiders: new atoms mimic connected atoms or alternate positions
- [ ] Cartoon/ribbon hiders: extend at a terminal, or replicate a segment (e.g. a loop) as an alternate position; uses C-alpha
- [ ] Sphere hiders: place anywhere
- [ ] Surface representation: NOT supported (out of scope)

#### VMD tcl Script (v2 — deferred)

- [ ] Sourced tcl + command to launch GUI; similar gameplay to PyMOL
- [ ] Research and limit the set of VMD materials/representations the game plays on
- [ ] Seek approval for any additional VMD tcl libs (e.g. tooltip.tcl)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Surface representation hiders — excluded by user spec; does not fit the "blend in" mechanic well
- VMD plugin in v1 — deferred to v2; different tech (tcl vs python) and testing, delivered as a separate milestone
- Installing packages or creating conda envs in the dev environment — explicit constraint; WSL is for syntax checking only, PyMOL runs in Windows conda via setenv.bat
- Auto-fetching/installing external Python libs silently — any non-PyMOL dependency must be listed to a file, approved by the user, then either user-installed or vendored into ./3rd_party_lib (git-ignored) with license noted

## Context

- **Working environment:** WSL Ubuntu for development. PyMOL 2.5.0 (anaconda) runs in a Windows conda env, accessed via `setenv.bat` (a Windows cmd.exe batch script). Python 3.6 is available in the WSL shell for syntax checking only — nothing may be installed in WSL, and no conda envs may be created.
- **Reference material:** `./Pymol-script-repo` (git-ignored) holds open-source PyMOL plugins for learning how to write PyMOL plugins.
- **Demo PDBs (Note 1):**
  - Protein — Easy: 1znf; Hard: 1xdn
  - Nucleic acid — Easy: RNA 5E54, DNA 1K8P; Hard: 2QBZ
  - Mixed: 4WB3
  - Challenge — Glycoprotein with glycan: an Alpha-1-glycoprotein model from SASBDB (https://www.sasbdb.org) — cite source and IDs in docs
  - Very challenging — Membrane protein from MemProtMD (https://memprotmd.bioch.oxy.ac.uk) with full membrane (dppc-atomistic): 1GZM (helix), 3GP6 (sheets). Large files — strip water and salt, then compress before bundling.
- **Demo data strategy:** Bundle the small PDBs in the repo (in a data/ dir or git-ignored as needed); fetch the large membrane-protein files on demand. Cite all sources in documentation.
- **Hider mechanic detail:** Hiders are new atoms/coordinates added INTO the same PyMOL object (not a separate object), so the player cannot trivially hide the whole new object. They adopt the same representation as at least one nearby/connecting item to blend in. Click detection uses standard PyMOL atom picking — we check whether the picked atom's index is a registered hider.

## Constraints

- **Tech stack:** PyMOL plugin (Python, PyMOL 2.5.0) for v1; VMD tcl script for v2. No web/backend.
- **Compatibility:** Must run under PyMOL 2.5.0 (anaconda, Windows) launched via `setenv.bat`.
- **Dependencies:** Only libraries required by pymol-open-source may be assumed. Any additional Python library must be written to a list file and explicitly approved by the user before use; approved libs are either user-installed locally or vendored into `./3rd_party_lib` (git-ignored) with their license noted. The user must be told whether a Linux-like env is needed or the "call cmd from WSL" approach still works.
- **Environment:** WSL Ubuntu — do NOT install anything, do NOT create conda envs. Python 3.6 is only for syntax checks.
- **Code quality:** Efficient, traceable, clean, safe. Repo must be structured.
- **UI:** Simple, user-friendly, with clear but sufficient in-game explanation.
- **Repo hygiene:** Vendored libs (`3rd_party_lib/`) and the reference repo (`Pymol-script-repo/`) are git-ignored. Large processed demo PDBs should be compressed.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| PyMOL plugin is v1, VMD tcl is v2 | Different tech stacks and testing setups; phased delivery reduces risk | — Pending |
| Hiders are added into the same PyMOL object, not a separate object | Otherwise too easy — player could just hide the whole new object | — Pending |
| Hider placement depends on representation type (line/stick mimic, cartoon/ribbon extend-or-replicate, sphere anywhere) | Matches how each representation visually blends with real structure | — Pending |
| Surface representation is not supported | Does not fit the blend-in mechanic; excluded by user spec | — Pending |
| Find interaction = click picks atom, check if index is a registered hider | Standard PyMOL picking; reliable atom identification | — Pending |
| Bundle small demo PDBs, fetch large membrane PDBs on demand | Large MemProtMD files are too big to bundle; small PDBs ensure offline demos work | — Pending |
| No installs / no conda envs in WSL dev env; PyMOL runs in Windows conda via setenv.bat | Explicit user constraint on the working environment | — Pending |

---
*Last updated: 2026-08-02 after initialization*
