> UNDER DEVELOPMENT

# bioCHEMeleon

A "hide-and-seek" game played on molecular structures inside PyMOL. Foreign atoms are inserted directly into a molecule's own object — styled to blend with the local representation (line/stick, cartoon/ribbon, spheres) — and the player must hunt them down by clicking atoms in the OpenGL viewer. Because hiders live in the same object as the real structure, the player can't trivially isolate them by toggling object visibility; they must visually spot the impostors.

For structural-biology users, students, and educators who want an engaging way to explore and study molecular representations.

> **Status:** Planning complete. v1 (PyMOL plugin) is being built; v2 (VMD tcl script) is deferred.
> See `.planning/ROADMAP.md` for the phase breakdown.

---

## What It Does

- **Setup tab** — choose a target molecule (loaded object, PDB fetch, or curated demo set with difficulty tiers), set the hider count, lock the current scene or randomize representations, assign per-representation hider counts, and pick a difficulty (total-only vs per-rep remaining).
- **Game tab** — rolling info log, counting-up timer, remaining-hiders counter, hint (colors neighbors), reveal-one / reveal-all (with confirm), found-hider management dropdown, save, and restart.
- **Core loop** — Start → 3-2-1 countdown → click atoms to find hiders → win when all found, timer stops.
- **Persistence** — save a game as a PyMOL session (`.pse`) + companion `.bcm` sidecar; prepare puzzles with Generate & export and share them via Import.
- **Demos** — bundled small PDBs (protein, RNA, DNA, mixed) and on-demand fetched large molecules (membrane proteins from MemProtMD, glycoprotein from SASBDB), with full source attribution.

## Requirements

- **PyMOL 2.5.0** (anaconda build or equivalent)
- PyQt5 (bundled with PyMOL's Qt GUI — no extra install)
- numpy (PyMOL build dependency — no extra install)

> No external Python dependencies beyond what PyMOL already ships. If any are introduced later, they will be listed for explicit user approval and either user-installed or vendored into `./3rd_party_lib/` (git-ignored) with their license noted.

## Install

Install via PyMOL's **Plugin Manager** (universal across Windows/Linux/macOS):

1. In PyMOL: `Plugin → Plugin Manager → Install New Plugin`
2. Point the file picker at the `biochemeleon/` package directory
3. The plugin registers a **bioCHEMeleon** item under the Plugins menu

> **WSL dev note:** When developing in WSL against a Windows conda PyMOL launched via `setenv.bat`, point the Windows file picker at the package via `\\wsl$\...` or a Windows-side copy. The plugin lands in `%APPDATA%/pymol/startup/biochemeleon/`.

## Usage

1. Load a molecule into PyMOL (or pick a demo from the Setup tab).
2. Open **Plugins → bioCHEMeleon**.
3. Configure the game in the Setup tab (target, hider count, representations, difficulty).
4. Press **Start** — after the 3-2-1 countdown, click atoms in the viewer to find hiders.
5. Use **Hint** (colors neighbors) or **Reveal** (gives up hiders) if stuck.
6. Find all hiders to win — the timer stops and shows your time (plus hints/reveals used).
7. **Save** to checkpoint, **Restart** to replay, **Cleanup model** to restore the original object.

## Demo Molecules

| Tier | Source | IDs |
|------|--------|-----|
| Protein Easy | RCSB PDB | 1znf |
| Protein Hard | RCSB PDB | 1xdn |
| RNA Easy | RCSB PDB | 5E54 |
| DNA Easy | RCSB PDB | 1K8P |
| Nucleic Hard | RCSB PDB | 2QBZ |
| Mixed | RCSB PDB | 4WB3 |
| Glycoprotein + glycan | SASBDB | (see `DATA_SOURCES.md`) |
| Membrane helix | MemProtMD | 1GZM (dppc-atomistic) |
| Membrane sheets | MemProtMD | 3GP6 (dppc-atomistic) |

Full attribution in `DATA_SOURCES.md` (produced during development).

## Project Structure

```
bioCHEMeleon/
├── .planning/          # GSD workflow artifacts (PROJECT, ROADMAP, REQUIREMENTS, research)
├── biochemeleon/       # The PyMOL plugin package (created during Phase 1)
├── Pymol-script-repo/  # Reference plugins (git-ignored)
├── 3rd_party_lib/      # Vendored libs if needed (git-ignored)
├── spec.md             # Original project spec
├── setenv.bat          # Windows cmd launcher for conda PyMOL
├── opencode.json       # OpenCode agent config
└── README.md
```

## License

BSD 3-Clause — see [LICENSE](LICENSE).

## Acknowledgements

Demo data courtesy of [RCSB PDB](https://www.rcsb.org/), [SASBDB](https://www.sasbdb.org/), and [MemProtMD](https://memprotmd.bioch.ox.ac.uk). Plugin architecture informed by the open-source plugins in [Pymol-script-repo](https://github.com/PymolScriptRepository) and [pymol-open-source](https://github.com/schrodinger/pymol-open-source).

---
*This README is updated as the project evolves. Last updated: 2026-08-03 after project initialization.*
