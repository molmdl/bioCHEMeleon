# Feature Research

**Domain:** Molecular visualization "hide-and-seek" game — PyMOL plugin (v1), with blended-into-object hider atoms.
**Researched:** 2026-08-02
**Confidence:** HIGH (features) / MEDIUM (educational framing) / LOW (competitor existence — see notes)

## Feature Landscape

This is a novel concept. I found **no existing "molecular hide-and-seek" / "spot the impostor atom" game** in the PyMOL/VMD/MolStar/ChimeraX ecosystem (LOW confidence — searched, could not positively confirm absence, but no evidence surfaced). The closest analogues are:

- **Hidden object game genre** (Wikipedia, HIGH): conventions = hints (magnifying glass), remaining-items counter, timer, zoom booster, time extension. bioCHEMeleon should adopt hint + remaining + timer; **skip** zoom booster (PyMOL already zooms) and time extension (timer is for scoring, not a hard limit per spec).
- **PyMOL plugin UX patterns** (verified against `./Pymol-script-repo/plugins/` and the official `pymol-open-source` plugin engine, HIGH): standard = `__init_plugin__(pmgapp)` + `addmenuitem(...)` registration, a setup `Dialog`, often a `NoteBook` (multi-tab). The **APBS plugin** is the canonical multi-tab example (10 tabs: Main, Dielectric, Other, Ions, Mesh, Grid, Locations, About). bioCHEMeleon needs just **2 tabs (Setup, Game status)**.
- **PyMOL atom picking** (`cmd.identify`, HIGH): returns atom IDs from a selection → the click-to-find mechanic is straightforward and reliable.
- **PyMOL session save** (`.pse` binary, `cmd.save`/`cmd.load`, HIGH): native checkpointing. Game-specific state can be serialized alongside (pickle/JSON sidecar).

Features below are mapped back to the user's spec (`spec.md` + `PROJECT.md`). Complexity: **S** = small (hours), **M** = medium (1–3 days), **L** = large (a week+).

---

### Table Stakes (Users Expect These — game breaks or feels broken without them)

These map 1:1 to the spec. Missing any = the core value loop ("load → generate → click-to-find → win") doesn't work.

#### Setup tab — configuration
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Standard PyMOL plugin install (menu item, opens on launch) | Users install via Plugin Manager; if it doesn't register cleanly, they never reach the game | S | Dep: `__init_plugin__` + `addmenuitem`. No Pmw — pure tkinter/ttk |
| Setup window opens on launch with configurable params | Spec req 1–2; the entry point | S | Dep: plugin install |
| Object selector: pick loaded object / fetch from PDB / demo set (with sub-menu for demo categories) | Spec req 2 item 1; no target = no game | M | Dep: needs `cmd.get_names()` for loaded objects; PDB fetch (`cmd.fetch`); demo set (see Demo PDBs row below) |
| Hider count input (capped to a reasonable max) | Spec req 2 item 2; controls game length | S | Cap by object atom count to avoid impossible/dense scenes |
| "Lock current scene" checkbox — true: detect reps from scene; false: randomize reps + list all available reps | Spec req 2 item 3; controls the core gameplay variant (blend-in vs freeform) | M | Dep: rep detection (`cmd.get_names('all', comp=1)` style), per-rep list |
| Per-representation hider list with optional per-rep counts (random per-rep if unspecified; total respects hider count) | Spec req 2 items 4–5 | M | Dep: hider count + lock-scene state |
| Difficulty toggle: show only total remaining (hard) vs also per-rep remaining (easy) | Spec req 2 item 6; the only "difficulty" knob besides setup | S | Dep: game-tab remaining-counter display |

#### Setup tab — 7 buttons (spec req 3)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Reset — restore default settings | Spec 3.1; users will experiment and want a clean slate | S | — |
| Randomize — randomize setup | Spec 3.2; fast onboarding for new users | S | Dep: object selector + per-rep list |
| Save Setup — save setup params to file | Spec 3.3; reproducibility / classroom prep | S | Dep: JSON/pickle sidecar |
| Load Setup — load setup params from file | Spec 3.4; paired with Save Setup | S | Dep: Save Setup format |
| Generate & export — generate game and save initial state to file for sharing / later loading | Spec 3.5; the "build a puzzle" workflow for educators | M | Dep: hider generation + Import button (Game tab) |
| Cleanup model — remove all game-generated reps/atoms not in original object | Spec 3.6; recovery tool so the user's scene isn't polluted | M | Dep: registry of game-generated atoms/reps (must track what was added) |
| Start — store initial state, generate hiders per setup, switch to Game tab, countdown 3-2-1 | Spec 3.7; THE core action | M | Dep: initial-state storage + hider generation + tab switch + countdown UI |

#### Hider generation (v1)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Line/stick hiders — new atoms mimic connected atoms or alternate positions | Spec hider-mechanic; the most common rep users see | M | Dep: atom-insertion into same object; bond topology mimicry |
| Sphere hiders — place anywhere | Spec hider-mechanic; easiest rep to place | S | Dep: coordinate sampling in bounding region |
| Cartoon/ribbon hiders — extend at a terminal or replicate a segment (e.g. a loop) as alternate position; uses C-alpha | Spec hider-mechanic; the educational centerpiece (hardest to spot) | L | Dep: cartoon geometry understanding, C-alpha chain handling. **Hardest v1 feature** — may need phasing |

#### Game status tab
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Rolling info box (status messages / log) | Spec req 6 item 1; the feedback channel — without it users are blind to clicks/hints | S | — |
| Timer — counts after start, stops on win | Spec req 6 item 2; scoring basis | S | Dep: Start + Win condition |
| Remaining hiders count (total + optionally per-rep per difficulty) | Spec req 6 item 3; progress indicator | S | Dep: found-status tracking + difficulty toggle |
| Import button — import a game prepared by "Generate & export" | Spec req 6 item 4; paired with Generate & export for shareable puzzles | M | Dep: Generate & export file format |
| Hint button — change color of N atoms/residues around a hider | Spec req 6 item 5; standard hidden-object-game hint pattern (HIGH, genre convention) | M | Dep: hider registry + neighbor selection (`cmd.expand` / by-residue `around`) |
| Reveal-one hider button (with confirm) — random hider → "found" status, count reveal usage | Spec req 6 item 6; "give up" escape valve | M | Dep: hider registry + found-status tracking |
| Reveal-all hiders button (with confirm) — all → "found" | Spec req 6 item 6; full give-up | M | Dep: Reveal-one |
| Found-hider management dropdown — hide/show/change color of found hiders | Spec req 6 item 7; lets player declutter after finds | S | Dep: found-status tracking |
| Save button — save state as PyMOL session + game-specific state info for checkpointing | Spec req 6 item 8; resume later | M | Dep: `cmd.save(.pse)` + sidecar state (pickle/JSON) |
| Restart button — restart from initial state | Spec req 6 item 9; replay without reconfiguring | S | Dep: initial-state storage (from Start) |

#### Core loop
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Click-to-find — clicking atom in viewer checks if it's a registered hider → marks found (recolors or hides); counts reveal usage | Spec req 7; THE core mechanic. Without this there is no game | M | Dep: PyMOL picking + `cmd.identify` (HIGH, verified) + hider ID registry |
| Win — all hiders "found" → stop timer → show winning message with time taken | Spec req 8; the payoff | S | Dep: found-status tracking + timer |

#### Demo content
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Demo PDB set bundled (small) / fetched (large), sources documented | Spec Note 1 + PROJECT.md; without demos, new users have nothing to try | L | Curated tiers: Protein Easy 1znf / Hard 1xdn; Nucleic RNA 5E54 / DNA 1K8P / Hard 2QBZ; Mixed 4WB3; Glycoprotein (SASBDB); Membrane 1GZM/3GP6 (MemProtMD). Bundle small; fetch large on demand; cite sources in docs |

#### Accessibility / clarity
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| In-game explanation — what each button does, what each rep means | PROJECT.md constraint "clear in-game explanation"; users unfamiliar with reps will be lost | S | Tooltips / a help panel |
| Controls help — how to click, navigate, zoom, rotate | Users new to PyMOL need this; without it clicking is confusing | S | — |

---

### Differentiators (Competitive Advantage — make it engaging / educational)

Not required for the loop, but they're what make bioCHEMeleon worth building instead of "just a demo". The strongest differentiators lean into the **educational angle**: the player learns to *recognize molecular-representation artifacts* (visual literacy), which is genuinely valuable for structural-biology students.

| Feature | Value Proposition | Complexity | Notes / Deps |
|---------|-------------------|------------|--------------|
| Difficulty-tiered demo metadata shown in the demo sub-menu | The curated tiers (Easy/Hard/Challenge/Very challenging) become a learning curve, not just a list | S | Dep: demo PDB set |
| Hint that colors **neighbors** (not the hider itself) | Preserves challenge while teaching spatial context — unlike typical "highlight the item" hints. Strong genre-aware differentiator | S | Already part of the Hint feature; call out as a design choice |
| Reveal counter — track how many reveals used | Adds a skill metric beyond time ("you found 8/10 without reveals") | S | Dep: Reveal-one/all |
| Win screen with stats — time taken, hints used, reveals used | Replayability + self-challenge; standard for puzzle games (HIGH, genre convention) | S | Dep: Win condition + hint/reveal counters |
| Per-rep difficulty reflected in stats (e.g., "cartoon finds took longer") | Educational: surfaces that some reps are harder to spot → teaches visual literacy | S | Dep: per-rep found tracking + timer |
| Post-game debrief — "show all hiders" highlight + explanation of why each was hard to spot | **THE teachable moment.** This is where molecular-representation education actually happens | M | Dep: Win condition + reveal-all + hider registry with placement rationale |
| Hiders that genuinely blend (line/stick mimic real bond topology; cartoon extends a real helix) | The core educational hook — players learn to spot representation artifacts. Quality of blending = quality of learning | M | Dep: line/stick + cartoon/ribbon hider generation. This is where engineering effort pays off pedagogically |
| Non-destructive to user's scene (Cleanup model restores original object) | Differentiates from tools that pollute the session; safe for educators running on shared machines | M | Already table stakes as Cleanup, but framed as a guarantee it's a differentiator |
| Color picker for found-hider highlight (player chooses how to mark finds) | Personalization; accessibility (color-blind users can pick a visible color) | S | Dep: found-hider management dropdown |
| Bundled small PDBs work offline | Classroom / exam / no-network use cases | S | Dep: bundled demo PDBs |
| Shareable puzzle files (Generate & export → Import) | Educator builds a puzzle once, students load it — classroom workflow | M | Already in table stakes; the *classroom* framing is the differentiator |
| Restart preserves setup | Smooth replay loop; encourages "try again with same setup to beat your time" | S | Dep: Restart + setup persistence |
| Breadth of demo molecule types (protein, RNA, DNA, mixed, glycoprotein, membrane) | Educational breadth in one tool | M | Dep: demo PDB set (the L feature) |

---

### Anti-Features (Commonly Requested, Often Problematic — deliberately NOT build)

Documented to prevent scope creep. Several are already in `PROJECT.md` "Out of Scope" — restated here with rationale and alternatives.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Surface representation hiders** | "It's a common rep, why not support it?" | Doesn't fit the blend-in mechanic (surface is a continuous mesh, not discrete atoms you can insert-and-match); explicitly excluded by spec | Support line/stick/cartoon/sphere only. Document the exclusion in the UI |
| **VMD plugin in v1** | "Why not ship both at once?" | Different tech stack (tcl vs python), different testing setup; bundling doubles risk and delays v1 | Build PyMOL v1 first; VMD tcl is v2 (deferred milestone) |
| **Web backend / cloud / online leaderboard** | "Let players compare times online" | Out of scope per spec ("no web/backend"); adds infra, auth, privacy concerns; offline educational tool shouldn't need network | Local-only. Times live in the saved session sidecar |
| **Auto-fetching/installing external Python libs silently** | "Just `pip install` whatever's needed" | Explicit constraint: any non-stdlib lib must be listed, approved, then user-installed or vendored into `./3rd_party_lib` with license | Use only stdlib (`tkinter`/`ttk`) + PyMOL-bundled libs. Avoid `Pmw` (3rd-party) unless approved & vendored — reference plugins use it, but `emovie.py` proves pure Tkinter works |
| **Real-time / network multiplayer** | "Race a friend to find hiders" | Massive scope (networking, sync, conflict resolution); wrong tool (PyMOL is single-user desktop) | Single-player. Shareable puzzle files approximate async multiplayer |
| **Touch / mobile support** | "Run on a tablet" | PyMOL is desktop OpenGL; touch isn't a PyMOL target | Desktop mouse + keyboard only |
| **Procedural generation of novel molecules** | "Generate random new structures to hide in" | Out of scope; risks scientific inaccuracy; the game inserts atoms *into* the user's existing object, it doesn't synthesize new structures | Insert hiders into user-provided/demo molecules only |
| **Adaptive AI difficulty scaling** | "Make it harder as the player improves" | Over-engineering for v1; the setup params + curated tiers already give difficulty control | Static difficulty via setup + demo tiers |
| **Sound effects / background music** | "Games have audio, right?" | Adds asset + dependency complexity; risk of audio lib needing approval; PyMOL isn't an audio platform | Silent v1. (Could be a later differentiator; not now) |
| **In-app plugin self-update mechanism** | "Auto-update the plugin" | Out of scope; standard PyMOL plugin install/update flow is enough | Use standard PyMOL Plugin Manager install/update |
| **Custom 3D rendering / shaders for hiders** | "Make hiders glow when found" | Out of scope; rely on PyMOL's built-in OpenGL + `cmd.color`/`cmd.hide` | Use standard PyMOL recolor/hide for found status |
| **Modifying the original molecule's atoms** | "Maybe move a real atom to make room" | Breaks scientific integrity; user's molecule must be preserved | Only *add* atoms/coords into the object; never alter real atoms |
| **Installing conda envs / system packages from within the plugin** | "Set up its own env" | Explicit environment constraint (PROJECT.md) — WSL may not install; PyMOL runs in Windows conda via `setenv.bat` | Plugin assumes the PyMOL 2.5.0 env it's loaded into; document prerequisites |
| **Cloud achievements / badges sync** | "Persistent achievements across machines" | Implies backend (already excluded) | Achievements, if any, are local + ephemeral within a session |
| **Hard time limit / fail state** | "Lose if you don't find them in 60s" | Spec's timer is for *scoring*, not failure (PROJECT.md: "win = all found + timer stops"); a fail state changes the cozy-educational tone to stressful | Timer counts up; no fail state. Player can always reveal-all to end |

---

## Feature Dependencies

```
[Plugin install] ──> [Setup window]
                          │
                          ├──> [Object selector] ──> (everything below needs a target)
                          │        ├──> [Demo PDB set] (one source of objects)
                          │        └──> [PDB fetch]    (another source)
                          │
                          ├──> [Hider count input]
                          ├──> [Lock-scene checkbox] ──> [Per-rep hider list] ──> [Per-rep counts]
                          ├──> [Difficulty toggle]
                          │
                          └──> [7 Setup buttons]
                                  ├──> [Reset], [Randomize]
                                  ├──> [Save Setup] <──> [Load Setup]
                                  ├──> [Generate & export] <──> [Import button (Game tab)]
                                  ├──> [Cleanup model] ──> needs [Registry of game-generated atoms]
                                  └──> [Start] ──> [Initial-state storage]
                                          ├──> [Countdown 3-2-1]
                                          ├──> [Hider generation]
                                          │       ├──> [Sphere hiders]
                                          │       ├──> [Line/stick hiders]
                                          │       └──> [Cartoon/ribbon hiders]  ← hardest, may phase
                                          └──> [Switch to Game tab]

[Start] ──> [Timer] ──> [Win condition] (stops timer)
[Start] ──> [Game tab]

[Game tab]
   ├──> [Rolling info box]
   ├──> [Remaining count] ──> [Difficulty toggle] (controls per-rep display)
   ├──> [Hint] ──> needs [Hider registry] + neighbor selection
   ├──> [Reveal-one] ──> [Reveal-all] ──> [Reveal counter] (differentiator)
   ├──> [Found-hider mgmt dropdown] ──> [Color picker] (differentiator)
   ├──> [Save game state] ──> needs [PyMOL session .pse] + [state sidecar]
   └──> [Restart] ──> needs [Initial-state storage]

[Core loop]
   [Click-to-find] ──> [Found-status tracking] ──> [Win condition]
        └── needs [Hider registry w/ atom IDs] + cmd.identify (PyMOL picking)

[Cross-cutting]
   [In-game explanation] ── enhances ──> everything (tooltips/help)
   [Controls help]       ── enhances ──> [Click-to-find]
   [Post-game debrief]   ── enhances ──> [Win condition] (differentiator)

[Conflicts]
   [Surface rep hiders]  ── conflicts ──> [Blend-in mechanic]  → excluded
   [Pmw dependency]      ── conflicts ──> [No-unapproved-libs constraint] → use tkinter/ttk
   [Web backend]         ── conflicts ──> [Offline-only constraint] → local sidecar only
```

### Dependency Notes

- **Start requires Hider generation + Initial-state storage + tab switch + countdown.** Start is the integration point — it's where Setup becomes Game. It should be built last among the Setup-tab features.
- **Click-to-find requires the Hider registry (atom-ID list) before it can do anything.** Build hider generation such that every generated hider's `(object, atom-ID)` is recorded; click handling is then `picked_id in hider_registry`.
- **Win requires Found-status tracking.** Found-status is a per-hider flag; "remaining" = total − found. Build found-status as a single source of truth that remaining-counter, found-management, reveal, and win all read.
- **Cleanup model requires a registry of what the game added** (atom IDs, rep names). If hider generation records its additions, Cleanup is "remove these IDs / hide these reps" — cheap. Build the registry *with* generation, not as an afterthought.
- **Save/Load game state = PyMOL `.pse` (geometry/scene) + sidecar (game state JSON/pickle).** The sidecar must include hider registry, found-status, timer, hint/reveal counts, setup params. Restart loads the sidecar; Import loads a Generate-and-export sidecar.
- **Import ↔ Generate & export are a paired file format.** Define the format once; both ends use it.
- **Hint, Reveal-one, Reveal-all, Restart, Win all read the same hider registry + found-status.** Centralize that state.
- **Cartoon/ribbon hiders are the hardest v1 feature (L).** If MVP timeline is tight, ship sphere + line/stick first and phase cartoon/ribbon — but spec lists cartoon as v1, so flag this as the highest-risk v1 item.
- **Demo PDBs (L) is independent of the game engine** — can be prepared in parallel (download, strip water/salt for membrane PDBs, compress, cite sources). Don't let it block the engine.

---

## MVP Definition

### Launch With (v1 — core loop must work)

The non-negotiable set to validate "load → generate → click-to-find → win". Derived from PROJECT.md "Active: PyMOL Plugin (v1)".

- [ ] Standard PyMOL plugin install (S)
- [ ] Setup window: object selector (loaded + demo), hider count, lock-scene checkbox, per-rep hider list, difficulty toggle (M)
- [ ] All 7 setup buttons: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup model, Start (M)
- [ ] Hider generation: **sphere + line/stick** (M). Cartoon/ribbon is v1 per spec but is the highest-risk item — see phasing note
- [ ] Game tab: rolling info box, timer, remaining count, import, hint, reveal-one/all, found-hider dropdown, save, restart (M)
- [ ] Click-to-find mechanic (M)
- [ ] Win condition + winning message with time (S)
- [ ] Restart from initial state (S)
- [ ] Save/load game state = `.pse` + sidecar (M)
- [ ] Bundled small demo PDBs with sources cited (M — portion of the L demo set)
- [ ] In-game explanation + controls help (S)

### Add After Validation (v1.x)

- [ ] **Cartoon/ribbon hiders** — if not in initial MVP (trigger: cartoon is the educational centerpiece; prioritize once sphere+line/stick loop is proven)
- [ ] Reveal counter + win-screen stats (time, hints, reveals) — trigger: once win condition is stable
- [ ] Post-game debrief / "show all hiders" with explanations — trigger: positive feedback on the educational angle
- [ ] Color picker for found-hider highlight — trigger: accessibility feedback
- [ ] Fetched large demo PDBs (MemProtMD 1GZM/3GP6) on demand — trigger: users want harder demos; requires water/salt stripping + compression pipeline
- [ ] Difficulty-tiered demo metadata surfaced in UI — trigger: once the full demo set is in

### Future Consideration (v2+)

- [ ] **VMD tcl plugin** — deferred milestone; different tech stack
- [ ] Shareable-puzzle educator workflow polish (one-click "puzzle pack" bundling) — trigger: classroom adoption
- [ ] Sound effects / ambient audio — trigger: post-v1 polish; requires audio lib approval
- [ ] Local achievements (no cloud) — trigger: replayability feedback
- [ ] Optional "puzzle authoring" mode (curate which atoms become hiders, place by hand) — trigger: power-user educators

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Click-to-find mechanic | HIGH | M | P1 |
| Hider generation — sphere | HIGH | S | P1 |
| Hider generation — line/stick | HIGH | M | P1 |
| Hider generation — cartoon/ribbon | HIGH | L | P1* (phase if needed) |
| Start + countdown + tab switch | HIGH | M | P1 |
| Timer + win condition | HIGH | S | P1 |
| Hider registry + found-status tracking | HIGH | M | P1 (foundation) |
| Setup window (object selector, count, lock, per-rep, difficulty) | HIGH | M | P1 |
| 7 setup buttons | HIGH | M | P1 |
| Game tab (info box, remaining, hint, reveal, found-mgmt, save, restart) | HIGH | M | P1 |
| Save/load game state (.pse + sidecar) | HIGH | M | P1 |
| Cleanup model | MEDIUM | M | P1 (safety net) |
| Bundled small demo PDBs | HIGH | M | P1 |
| In-game explanation + controls help | HIGH | S | P1 (constraint) |
| Generate & export / Import (paired) | MEDIUM | M | P1 (spec) |
| Hint (color neighbors) | HIGH | M | P1 |
| Reveal-one / Reveal-all | HIGH | M | P1 |
| Restart from initial state | HIGH | S | P1 |
| Difficulty-tiered demo metadata in UI | MEDIUM | S | P2 |
| Reveal counter | MEDIUM | S | P2 |
| Win-screen stats (time, hints, reveals) | MEDIUM | S | P2 |
| Post-game debrief (show all + explain) | HIGH (educational) | M | P2 |
| Color picker for found-hider highlight | LOW | S | P2 (accessibility) |
| Fetched large demo PDBs (MemProtMD) | MEDIUM | L | P2 |
| Per-rep difficulty in stats | LOW | S | P3 |
| VMD tcl plugin | HIGH (for v2) | L | P3 (v2 scope) |

**Priority key:** P1 = must have for v1 launch; P2 = add after validation (v1.x); P3 = future (v2+).

\* Cartoon/ribbon is spec'd as v1 (P1) but is the highest-risk item; if timeline forces a phase, ship sphere+line/stick first and bring cartoon in v1.x.

---

## Competitor Feature Analysis

There are no direct competitors (a molecular hide-and-seek game) that I could verify (LOW confidence — absence not positively confirmed). The table below benchmarks against adjacent platforms and the genre.

| Feature | PyMOL (platform) | VMD (platform) | Hidden-object games (genre) | Our Approach (bioCHEMeleon) |
|---------|------------------|----------------|-----------------------------|------------------------------|
| Reps (line/stick/cartoon/sphere/surface) | Full | Full (more materials) | n/a | Use line/stick/cartoon/sphere; **exclude surface** (blend-in mechanic) |
| Atom picking / click identification | `cmd.identify` (HIGH) | tcl pick | n/a | Use `cmd.identify` for click-to-find (verified solid) |
| Multi-tab setup dialog | Common (APBS = 10 tabs via Pmw.NoteBook) | Less common | n/a | 2 tabs (Setup, Game status) via `ttk.Notebook` (avoid Pmw — 3rd-party) |
| Session save/load | `.pse` (binary) | `.dsv`/state | n/a | `.pse` + game-state sidecar (JSON/pickle) for checkpointing |
| Hints | n/a | n/a | Magnifying glass, zoom booster, time extension | Hint colors *neighbors* (not the item) — preserves challenge + teaches context |
| Timer | n/a | n/a | Usually a hard limit | Counts up for scoring; **no fail state** (cozy-educational tone) |
| Remaining counter | n/a | n/a | Standard | Total (hard mode) + per-rep (easy mode) |
| Shareable puzzles | n/a | n/a | Some (level files) | Generate & export / Import pair — classroom workflow |
| Educational layer | None | None | None | Post-game debrief + rep-artifact recognition = the core educational hook |
| Multiplayer / online | n/a | n/a | Some (co-op) | **Excluded** — offline single-player |
| Sound | n/a | n/a | Standard | **Excluded in v1** — silent |

### Implications

- **UX pattern to follow:** APBS-style multi-tab dialog, but with `ttk.Notebook` (stdlib) instead of `Pmw.NoteBook` (3rd-party, would need approval + vendoring). `emovie.py` in the reference repo proves pure-Tkinter plugins work.
- **Core mechanic verification:** `cmd.identify` reliably returns atom IDs from a selection — click-to-find is engineering-low-risk. The *real* engineering risk is **hider blending quality** (line/stick mimicry, cartoon extension), which is the educational differentiator.
- **Novel positioning:** Since no competitor exists, bioCHEMeleon can define the "molecular hide-and-seek" subgenre. The differentiators (post-game debrief, rep-artifact recognition, classroom puzzle sharing) are where it earns "educational tool" status rather than "novelty toy".

---

## Sources

- **PyMOL plugin engine** (HIGH): `pymol-open-source/modules/pymol/plugins/__init__.py` — `__init_plugin__`, `addmenuitem`, plugin registration. https://github.com/schrodinger/pymol-open-source/blob/master/modules/pymol/plugins/__init__.py
- **Reference plugins** (HIGH): `./Pymol-script-repo/plugins/` — APBS plugin (canonical multi-tab via Pmw.NoteBook), `emovie.py` (pure-Tkinter pattern, Python 3 compat), `rendering_plugin.py` (single-group pattern). Confirms Pmw is optional, ttk/tkinter suffices.
- **PyMOL `cmd.identify`** (HIGH): returns atom IDs from a selection — basis for click-to-find. https://pymolwiki.org/index.php/Identify
- **Hidden object game genre** (HIGH): conventions = hints, remaining counter, timer, zoom booster, time extension. https://en.wikipedia.org/wiki/Hidden_object_game
- **PROJECT.md / spec.md** (HIGH): the source-of-truth feature list. All table-stakes features map 1:1 to spec requirements.
- **Competitor existence** (LOW): no verified existing "molecular hide-and-seek" game found; searched ecosystem (PyMOL/VMD/MolStar/ChimeraX/Jmol) via webfetch — could not positively confirm absence, but no evidence surfaced. bioCHEMeleon appears novel.

---
*Feature research for: molecular visualization hide-and-seek game (bioCHEMeleon, PyMOL plugin v1)*
*Researched: 2026-08-02*
