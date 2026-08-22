# Feature Research

**Domain:** Molecular visualization "hide-and-seek" game — VMD tcl script (v2.0), porting v1's PyMOL plugin to VMD 1.9.3. Hiders are blended-into-molecule atoms styled to match the local representation, and the player hunts them by clicking atoms.
**Researched:** 2026-08-22
**Confidence:** HIGH (rep/material/pick APIs — headless-verified against VMD 1.9.3; see Verification Log) / MEDIUM (rep blend-in viability — reasoned from v1 analogues + VMD rep semantics, not yet gameplay-validated) / LOW (material-blending gameplay value — verified API works but pedagogical value is a hypothesis)

> **Scope:** v2.0 (VMD 1.9.3 tcl script). v1 (PyMOL 2.5.0) shipped 2026-08-18. This file covers the FEATURES dimension for the v2 port. See `STACK.md` for the tcl/VMD toolchain, `ARCHITECTURE.md` for module structure, `PITFALLS.md` for VMD-specific traps (PDB column alignment, molid drift, no in-place atom insertion).
>
> **Method:** All API claims marked "verified" were confirmed by running headless VMD 1.9.3 scripts (`vmd -dispdev text -e <script> -eofexit` from WSL) against the v1 bundled demo `1znf.pdb` (424 atoms, 37 NMR frames). Test scripts in `tmp/vmd-test/vmd_test{1..6}.tcl` (gitignored under `tmp/`). Where a claim is reasoned-not-verified, it is marked MEDIUM/LOW confidence.

## Feature Landscape

This is a port of a shipped, audited game (v1), not a greenfield design. The feature set is therefore *derivative* — v1's 46 requirements map to v2 — but the **implementation surface is different** because VMD's molecular data model differs fundamentally from PyMOL's (see Critical Architecture Difference below). The research focus per the spec (`spec.md` line 61): *"VMD has many more materials and representations, do research and suggest to limit the representation this game could play on."* This file answers that question.

### Critical Architecture Difference (informs every feature below)

| Concern | PyMOL (v1) | VMD (v2) | Implication |
|---------|-----------|----------|-------------|
| In-place atom insertion | `cmd.pseudoatom(object=existing, ...)` inserts an atom INTO a loaded object in-memory | **No equivalent.** `atomselect` only *modifies* existing atoms (verified: methods = frame/molid/text/delete/global/update/num/list/get/set/getbonds/setbonds/getbondorders/getbondtypes/moveto/moveby/lmoveto/lmoveby/move/writepdb/writeXXX — no `add`/`insert`) | v2 must **write a PDB with hider atoms appended, then reload as a NEW molecule replacing the original** (Option D, verified working — see Atom Insertion). This is the single biggest v1→v2 change. |
| Hider sentinel | `segi='GAME' + b=-999` (PyMOL `segi` = 4-char segment) | `resname='GAM' + beta=-999` (PDB resname = **3 chars**, cols 18-20); `segid='GAME'` (4 chars, cols 73-76) as secondary | v2 sentinel must use 3-char resname `GAM` (PDB resname field is 3 cols — a 4-char `GAME` is silently truncated/dropped, **verified by test5**). `segid GAME` works *only with correct PDB column alignment* (cols 73-76). `beta < 0` selector works (verified). |
| Rep model | GUI-layered via `cmd.show(rep, sel)` on the object; `cmd.count_atoms("{obj} and rep {rep}") > 0` detects active reps | Command-listed reps: `mol addrep`, `mol modstyle`, `mol delrep`, `mol showrep`; `molinfo $mol get numreps` + `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` queries (verified) | v2 rep setup is explicit and ordered (rep index 0,1,2...). Default is **1 rep: Lines, sel=all, color=Name, material=Opaque** (verified). |
| Atom picking | `cmd.identify` returns atom IDs from Wizard do_pick; reliable | `label add Atoms <molid>/<atomindex>` creates a pick-label; global `vmd_pick_atom`/`vmd_pick_mol` set on GUI click; `trace variable vmd_pick_atom w <cb>` is the callback (verified: `label add` + `label list Atoms` return `{{<molid> <atomindex>} <value> <show>}`) | v2 click-to-find uses a trace on `vmd_pick_atom` instead of a Wizard. **Picking cannot be fully tested headless** — `vmd_pick_atom` is only populated on real GUI clicks (verified: vars don't exist in text mode). The `label add` programmatic path is the testable proxy. |
| Undo | None in PyMOL Open Source — v1 uses `cmd.create('_bchm_backup', ...)` snapshot + restore | VMD has **no undo either**, but the recovery model differs: v2 keeps the *original PDB file path* and reloads it (the "backup" is the on-disk source file) | v2's "backup" = remember the original molecule's file path + rep state; "restore" = `mol delete` the game-mol + `mol new <original.pdb>` + re-apply saved reps. Simpler than v1's in-memory backup, but loses unsaved user edits to the original mol. |
| Session save | `.pse` binary + `.bcm` JSON sidecar → `.bcmz` zip | `save_state <file.vmd>` writes a **text tcl script** (22-25KB verified) recreating mols+reps+materials+viewpoints+colors; game sidecar = JSON | v2 session = `.vmd` (VMD native, text) + `.bcm` sidecar (JSON, game state) → `.bcmz` zip. The `.vmd` being text means game state *could* be injected, but separate sidecar is cleaner (v1 pattern). |

### v1 Features Being Ported (baseline — all v1-verified, v2-researched)

These come from `v1-ROADMAP.md` / `v1-REQUIREMENTS.md` (46 reqs) and `v1-MILESTONE-AUDIT.md` (PASSED 2026-08-18). They are **table stakes for v2** — missing any breaks the core loop. Complexity here is the **v2 port cost** (tcl reimplementation), not v1's original cost.

---

## Table Stakes (Users Expect These — game breaks or feels broken without them)

### Plugin entry & GUI
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Sourced tcl script + command to launch GUI | Spec.md line 60: "loaded by sourcing the vmd tcl then calling certain command to start the GUI" — different from v1's plugin-manager install | S | `source biochemeleon.tcl; biochemeleon` pattern (mirrors `ramaplot`/`autoionize` reference plugins). Entry proc creates a `toplevel .biochemeleon`. |
| Modeless main window (3D viewer stays interactive for click loop) | v1 AGENTS.md rule: main dialog modeless (`dialog.show()` never `.exec_()`); same principle in tcl — `wm withdraw`/`wm deiconify`, never `tkwait window`/`grab set` on main | S | Child `tk_messageBox`/`tk_getOpenFile` dialogs CAN be modal (`grab set`). Reference: `autoionizegui.tcl`, `mergestructs.tcl` use `toplevel` + `wm protocol WM_DELETE_WINDOW`. |
| Two-tab setup/game dialog (ttk::Notebook or frame switcher) | v1 had Setup + Game tabs; spec req 2 (setup) + req 6 (game status) | S | Tcl `ttk::notebook` (built into Tk 8.5, shipped with VMD). No 3rd-party lib needed for tabs. |
| Standard VMD plugin UX (molecule dropdown, trace on mol list) | Users expect to pick from loaded molecules like other VMD plugins | S | `molinfo list` + `trace variable vmd_molecule w` to refresh dropdown (reference: `clonerep.tcl` `UpdateMolecule`, `ramaplot.tcl` `ramaUpdateMolecules`). `vmd_molecule` is an ARRAY (verified). |

### Setup tab — configuration (spec req 2)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Object selector: loaded mol + PDB fetch + demo set | Spec req 2 item 1; v1 had loaded+demo+PDB fetch | M | Loaded: `molinfo list` + `molinfo $m get name`. PDB fetch: `mol new <url> type pdb` (VMD can fetch URLs directly? — verify; v1 used `cmd.fetch`). Demo set: reuse v1's 6 bundled + 3 fetched PDBs (1znf/1xdn/5e54/1k8p/2qbz/4wb3 + 1gzm/3gp6/sasdpg4). Demos live under `vmd/data/demos/` mirroring v1's `pymol/biochemeleon/data/demos/`. |
| Hider count input (capped to reasonable max) | Spec req 2 item 2 | S | Cap by `molinfo $mol get numatoms` to avoid impossible density. |
| "Lock current scene" checkbox | Spec req 2 item 3 — true: detect reps from scene; false: randomize + list all available reps | M | **Detect active reps:** iterate `molinfo $mol get numreps` querying each rep's style via `molinfo $mol get "{rep $i}..."` (verified). **List all available:** the curated GAME_REPS list (see Rep Viability below). **Randomize:** quick-008 fix baked in (random per-rep distribution from start, NOT all-spheres default — PROJECT.md key decision). |
| Per-representation hider list with optional per-rep counts | Spec req 2 items 4-5 | M | Checkboxes per rep in GAME_REPS; spinbox for per-rep count. Total respects hider count. |
| Difficulty toggle (total-only hard vs per-rep easy) | Spec req 2 item 6 | S | Drives game-tab remaining-counter display (pull model, v1 Phase 4.1). |

### Setup tab — 7 buttons (spec req 3)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Reset / Randomize | Spec 3.1/3.2 | S | Restore defaults / randomize setup params. |
| Save Setup / Load Setup | Spec 3.3/3.4 | S | JSON file of setup params (tcl `json` package or hand-rolled — verify VMD ships json). |
| Generate & export | Spec 3.5 — build a puzzle for sharing | M | Generate hiders (Option D PDB write), save `.vmd` + `.bcm` sidecar as `.bcmz`. Paired with Import. |
| Cleanup model | Spec 3.6 — remove game-generated atoms/reps, restore original | M | **v2 cleanup = `mol delete` game-mol + `mol new <original.pdb>` + re-apply saved reps.** Unlike v1 (which deletes sentinel atoms from the in-memory object), v2 reloads the original file. Must save original file path + rep state at Start. |
| Start — store initial state, generate hiders, switch to Game tab, countdown 3-2-1 | Spec 3.7 — THE core action | M | Deps: initial-state storage (original PDB path + rep snapshot via viewmaster's `save_reps` pattern, verified) + hider generation (Option D) + tab switch + countdown UI. |

### Hider generation (the core mechanic — most research-sensitive)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| **Sphere/VDW hiders** — place anywhere in bounding box | Spec hider-mechanic; v1's easiest rep. Maps to VMD `VDW` (and `CPK`) | S | `measure minmax [atomselect $mol all]` gives bbox (verified). Generate random `[x,y,z]` in bbox. Write hider as PDB ATOM record with element=C (gray sphere). **v1's `generate_sphere_positions` is pure-stdlib (random only) → directly portable to tcl.** |
| **Line/stick hiders** — mimic bonded atoms | Spec hider-mechanic; maps to VMD `Lines`/`Bonds`/`Licorice`/`DynamicBonds` | M | Pick a real neighbor, offset by small `[-1,1]` Å, write hider PDB ATOM record bonded to that neighbor. **VMD bond caveat:** PDB has no explicit bond records — VMD infers bonds from distance on load. So a hider placed ~1.5Å from a real C will auto-bond on reload (verified: "Determining bond structure from distance search" on `mol new`). This is actually *easier* than v1 (which needed `cmd.bond`). |
| **Cartoon/ribbon hiders** — replicate a segment via C-alpha | Spec hider-mechanic; maps to VMD `Cartoon`/`NewCartoon`/`Tube`/`Ribbons`/`NewRibbons`/`Trace`. The educational centerpiece (hardest to spot) | L | v1's Phase 11 approach: single-state new-chain copy using C-alpha. For v2: write hider C-alpha atoms as a new residue (resname=GAM, resid=999, segid=GAME) at a terminal or mid-chain position. **STRIDE auto-runs on Cartoon reps** (verified: "Added new Atoms label" + STRIDE license notice when adding Cartoon). v1's known caveat (hider fragment renders as loop `ss='L'`, not inheriting parent SS) likely **persists in v2** — VMD's Cartoon uses STRIDE-computed SS, and a GAM residue won't be recognized as helix/sheet. Document as accepted caveat (mirrors v1 Phase 11 user-accepted 2026-08-16). |
| Hider sentinel: `resname=GAM + beta=-999` (primary); `segid=GAME` (secondary) | v1 rule: sentinel-only cleanup, never by resid/chain/index (unstable) | S | **Verified:** `atomselect $mol "beta < 0"` finds hiders; `atomselect $mol "resname GAM"` finds hiders; `segid GAME` works *only with correct PDB column alignment* (cols 73-76 — test5 had a column bug; test6 confirmed `resname GAM` + `beta < 0` reliable). **Use `resname GAM and beta < 0` as the canonical selector** (most robust; doesn't depend on segid column alignment). |
| Registry keyed by atom **index** (stable across reload) | v1 rule: registry keys on atom id (stable across add/delete/.pse reload) | M | **Verified:** atom `index` IS stable across PDB reload (test5: `index=7 serial=8` matched before/after). VMD `index` is 0-based internal numbering; `serial` is the PDB serial number. **Key on `index`** (the atomselect `get index` value), not `serial` (PDB serial can have gaps). |
| Random per-rep distribution from start (quick-008 fix baked in) | v1.1 quick-008: all-spheres default was a post-ship patch; PROJECT.md key decision: bake fix in from start | S | v1's `randomize_per_rep(hider_count, game_reps, seed)` is pure-stdlib → directly portable to tcl. |

### Game status tab (spec req 6)
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Rolling info box (status log) | Spec req 6 item 1 — feedback channel | S | Tcl `text` widget, append + `see end`. |
| Timer (counts up after start, stops on win) | Spec req 6 item 2 | S | Tcl `after` loop. |
| Remaining hiders (total + per-rep per difficulty) | Spec req 6 item 3 | S | Pull model: registry counts found/total. |
| Import button | Spec req 6 item 4 — paired with Generate & export | M | Load `.bcmz`, unzip, `play <file.vmd>` (VMD's session-load command — verify), read `.bcm` sidecar to reconstruct registry from sentinels. |
| Hint — color N atoms/residues around a hider | Spec req 6 item 5 | M | `atomselect $mol "within 5 of (index <hider_idx>)"` (verified: `within` selector works). Recolor via `mol modcolor <rep> $mol ColorID <n>` or per-atom `label` color. **VMD hint challenge:** VMD colors by rep-method (Name/Structure/etc.), not per-atom. To color a specific atom's neighbors, either (a) add a new rep with `selection "within 5 of index N"` + `color ColorID 4` (red), or (b) use `label` highlighting. Option (a) mirrors v1's `cmd.color` but via a rep. |
| Reveal-one / Reveal-all (with confirm) | Spec req 6 item 6 — give-up escape valve | M | Mark hider found, count reveals. Confirm via `tk_messageBox -type yesno`. |
| Found-hider dropdown (hide/show/color) | Spec req 6 item 7 | S | Toggle `mol showrep` on a "found" rep, or recolor. |
| Save button — `.vmd` + `.bcm` sidecar → `.bcmz` | Spec req 6 item 8 — checkpointing | M | `save_state <file.vmd>` (verified 22-25KB) + write `.bcm` JSON + zip. Sidecar holds: hider registry, found-status, timer, hint/reveal counts, setup params, original PDB path. |
| Restart — restart from initial state | Spec req 6 item 9 | S | `mol delete` game-mol + `mol new <original.pdb>` + re-apply saved reps + regenerate hiders (or reload saved game-start state). |

### Core loop
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| **Click-to-find** — click atom → check if registered hider → mark found | Spec req 7 — THE core mechanic. Without it there is no game | M | **VMD pick = `trace variable vmd_pick_atom w <callback>`** (verified mechanism). On click, `vmd_pick_atom` = atom index, `vmd_pick_mol` = molid. Callback checks if `vmd_pick_atom` is in the hider registry. **Cannot fully test headless** (vars only populate on GUI click — verified). Testable proxy: `label add Atoms $mol/<idx>` then parse `label list Atoms`. Must also `mouse mode 0 0` (pick mode) at game start, restore prior mode on exit. |
| Win — all hiders found → stop timer → winning message with time | Spec req 8 | S | Counter reaches 0 → `tk_messageBox` with time. |

### Demo content
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| Demo PDB set (6 bundled small + 3 fetched large) with sources documented | Spec Note 1 + PROJECT.md; v1 had 1znf/1xdn/5e54/1k8p/2qbz/4wb3 + 1gzm/3gp6/sasdpg4 | M | **Reuse v1's PDB files directly** (copy `pymol/biochemeleon/data/demos/*.pdb` → `vmd/data/demos/`). Sources already cited in v1 `SOURCES.md` + `DATA_SOURCES.md` (human-approved). Fetched demos: `mol new <url> type pdb` may work for direct URL fetch (verify; v1 used urllib + SSL fallback — tcl may be simpler or harder). MemProtMD strip (water/salt) reuses v1's strip logic. |

### Accessibility / clarity
| Feature | Why Expected | Complexity | Notes / Deps |
|---------|--------------|------------|--------------|
| In-game explanation (tooltips/help) | PROJECT.md constraint "clear in-game explanation" | S | **tooltip.tcl from tklib is staged in `vmd-ref/tooltip/`** as reference. Spec.md line 60: "seek my approval if u need additional vmd tcl lib, e.g. tooltip.tcl". **Recommend:** vendor `tooltip.tcl` under `vmd/3rd_party_lib/` (Tcl/Tk license) OR use built-in `balloon` help via `bind <Enter>`/`<Leave>` on widgets (no 3rd-party lib). Decision pending user approval. |
| Controls help — how to click/navigate/zoom/rotate | v1 had this; users new to VMD need it | S | Help dialog or text panel. VMD mouse modes: `mouse mode 0 0` (pick), default rotate. |

---

## Differentiators (Competitive Advantage — VMD-specific opportunities)

These are where v2 can **exceed v1** by exploiting VMD-specific capabilities. The strongest is the **material system** (spec.md line 61 + PROJECT.md: "Explore whether VMD's material system adds a blending dimension beyond v1's rep-based approach").

### Material-based blending (THE v2 differentiator — spec explicitly asks to explore)

| Feature | Value Proposition | Complexity | Notes / Deps |
|---------|-------------------|------------|--------------|
| **Hider with slightly-different material** (e.g. opacity 0.85 vs 1.0, or different specular) | A hider rendered with `GameBlend` material (opacity 0.85, specular 0.65) is subtly more translucent/shiny than real atoms (Opaque, opacity 1.0). Hard to spot but visible on close inspection. **This is a blending dimension v1 didn't have** — v1 only blended by rep style. | M | **Verified API:** `material add GameBlend` + `material change opacity GameBlend 0.85` + `material change specular GameBlend 0.65` + `mol modmaterial <rep> $mol GameBlend` (all verified in test6). A hider on its own rep (e.g. `mol addrep` with `selection "resname GAM"` + `material GameBlend`) gets the subtle material. **Pedagogical value (MEDIUM confidence):** teaches students to notice material/lighting artifacts — a real visual-literacy skill for structural biology. |
| **Per-hider material variation** (each hider gets a slightly different opacity) | Increases difficulty variety — some hiders nearly invisible (opacity 0.95), others slightly off (0.80). Player must scan for subtle translucency differences. | M | `material add HiderMat0/HiderMat1/...` per hider with varied opacity. OR a single `GameBlend` with a rep per hider. **Caution:** too many materials clutters the material list; cap at 3-5 material variants. |
| **Glass/Translucent material hiders** (use built-in Glass1/Glass2/Glass3/Translucent) | A hider with Glass material is semi-transparent — blends with the structure behind it. Visually distinct from Opaque real atoms but hard to spot in a busy scene. | S | VMD ships Glass1 (opacity 0.15), Glass2 (0.68), Glass3 (0.50), Translucent (0.30), Ghost (0.10). Apply via `mol modmaterial <rep> $mol Glass1`. No custom material needed. **This is the cheapest material differentiator** — no `material add` required, just use built-ins. |
| **Material as a "rep" in the lock-scene list** | In setup, "material blending" becomes a toggle alongside rep-based blending. Player chooses whether hiders blend by rep, by material, or both. | M | Setup UI: checkbox "use material blending" → generates hiders with GameBlend/Glass material. Adds a 3rd blending axis beyond v1's rep-only. |

### Additional viable reps (beyond v1's 5)

v1's `GAME_REPS = ['lines','sticks','spheres','cartoon','ribbon']`. VMD has 27 reps. The spec asks to "limit the representation this game could play on." Below are reps that **fit the blend-in mechanic** (discrete atoms you can insert-and-match) and are NOT in v1's set. See **Rep Viability Matrix** (next section) for the full 27-rep analysis.

| Feature | Value Proposition | Complexity | Notes / Deps |
|---------|-------------------|------------|--------------|
| **NewCartoon** hiders | Smoother cartoon than Cartoon; common in publications. Hider = same C-alpha approach as Cartoon. | M | Same generator as Cartoon (C-alpha segment). NewCartoon is the modern default in VMD — many users prefer it. Offering both Cartoon + NewCartoon = broader coverage. |
| **CPK** hiders | Spheres + bonds (ball-and-stick). Hider = sphere placed among real spheres, auto-bonded to neighbor. | M | Like sphere + line combined. Common in teaching. |
| **Licorice** hiders | All bonded atoms as sticks (no H). Hider = atom bonded to real atom. | M | v1's "stick" maps here (Licorice is VMD's stick rep). Slightly different geometry from Bonds. |
| **Trace** hiders | C-alpha trace (thin line through backbone). Hider = C-alpha extending a chain. | M | Simpler than Cartoon (no SS-dependent rendering). Good intermediate difficulty. |
| **Tube** hiders | Smooth tube through C-alpha. Hider = C-alpha extending a chain. | M-L | Like Trace but thicker/smooth. Tube ignores SS, so hider blends regardless of STRIDE assignment — **avoids v1's Phase 11 SS-inheritance caveat.** |
| **Points** hiders | Single dots. Hider = one point. | S | Easiest to generate but **too easy to spot** (a lone point in a line/sphere scene). Low difficulty tier only. |
| **DynamicBonds** hiders | Bonds computed from distance dynamically. Hider = atom that forms a dynamic bond to a real atom when in range. | M | Hider placed ~1.5Å from real atom auto-bonds (distance-based). Similar to Line/Stick but bonds appear/disappear on rotation. |
| **Beads** hiders | One bead per residue (coarse-grain). Hider = a bead for a fake residue. | M | Niche but viable for coarse-grain demos. Bead placed at residue centroid. |

### VMD-specific differentiators (not rep/material)

| Feature | Value Proposition | Complexity | Notes / Deps |
|---------|-------------------|------------|--------------|
| **VMD trace callbacks** for real-time game state | VMD's `trace variable vmd_frame w` fires on frame change — could support **trajectory demos** (hiders hidden across NMR frames). v1 had no trajectory concept. | L | Spec doesn't require it, but VMD's strength is trajectories. A future "trajectory mode" where hiders must be found across frames is a v2.x differentiator. **Flag for v2.x, not v2.0 MVP.** |
| **VMD's `vmdrestoremymaterials` in .vmd** | Since `.vmd` is text tcl, game state could be injected directly. But separate `.bcm` sidecar is cleaner. | S | Architectural choice — keep sidecar pattern from v1. |
| **Breadth of VMD materials** (23 vs PyMOL's fewer) | More blending options than v1. | S | 23 materials verified: Opaque, Transparent, BrushedMetal, Diffuse, Ghost, Glass1-3, Glossy, HardPlastic, MetallicPastel, Steel, Translucent, Edgy, EdgyShiny, EdgyGlass, Goodsell, AOShiny, AOChalky, AOEdgy, BlownGlass, GlassBubble, RTChrome. |

---

## Rep Viability Matrix (the spec's core question)

**The spec asks:** "do research and suggest to limit the representation this game could play on." Below is the full 27-rep analysis. All 27 are **verified valid** in VMD 1.9.3 (`mol representation <name>` accepted — tested in test3). Categorization is by **blend-in mechanic fit**: can you insert a hider atom that visually matches the rep?

### Table-stakes reps (must have — direct v1 port)

| VMD Rep | v1 Equivalent | Blend-in Mechanism | Complexity | Confidence |
|---------|--------------|-------------------|------------|------------|
| **Lines** | lines | Hider = atom auto-bonded to neighbor (VMD infers bonds from distance on PDB load — verified). Draws as a line segment. | S | HIGH (verified: default rep, bond inference works) |
| **Bonds** | sticks (partial) | Hider = atom bonded to neighbor, drawn as cylinder bond. Same as Lines but thicker. | S-M | HIGH |
| **VDW** | spheres | Hider = atom placed anywhere in bbox (sphere radius by element). **v1's `generate_sphere_positions` ports directly.** | S | HIGH (verified: `measure minmax` gives bbox) |
| **Cartoon** | cartoon | Hider = C-alpha at terminal/segment, STRIDE assigns SS (verified: STRIDE auto-runs). v1 Phase 11 caveat (renders as loop) likely persists. | L | MEDIUM (v1 caveat may persist; STRIDE behavior verified) |
| **NewCartoon** | (new) | Hider = C-alpha, smoother rendering. Modern VMD default. | M | MEDIUM |
| **Licorice** | sticks | Hider = atom bonded to neighbor, all-bonds stick rep. **v1's stick hider maps here.** | M | HIGH |
| **Trace** | ribbon (partial) | Hider = C-alpha extending chain. Thin trace, SS-independent. | M | MEDIUM |
| **Tube** | ribbon (partial) | Hider = C-alpha extending chain. Smooth tube, **SS-independent (avoids v1 Phase 11 caveat).** | M | MEDIUM |
| **Ribbons** | ribbon | Hider = C-alpha, flat ribbon. Older ribbon style. | M | MEDIUM |
| **NewRibbons** | (new) | Hider = C-alpha, modern ribbon. | M | MEDIUM |

### Differentiator reps (nice to have — VMD-specific additions)

| VMD Rep | Blend-in Mechanism | Complexity | Confidence |
|---------|-------------------|------------|------------|
| **CPK** | Hider = sphere + bond (ball-and-stick). Combines sphere + line. | M | HIGH (VDW + Bonds logic) |
| **Points** | Hider = single point. Easiest but low difficulty. | S | HIGH |
| **DynamicBonds** | Hider = atom forming distance-based bonds. Bonds appear/disappear on rotation — dynamic challenge. | M | MEDIUM |
| **HBonds** | Hider = atom forming H-bonds. Tricky — H-bond geometry is specific. | M | LOW (H-bond geometry finicky) |
| **Beads** | Hider = bead for fake residue (coarse-grain). | M | MEDIUM |

### Anti-feature reps (do NOT fit blend-in — deliberately exclude)

These are **verified valid VMD reps** but **don't fit the blend-in mechanic**: they render continuous surfaces, volumetric data, or exotic shapes with no discrete-atom insertion that blends.

| VMD Rep | Why Excluded | Rationale |
|---------|-------------|-----------|
| **QuickSurf** | Surface representation. Continuous mesh, not discrete atoms. | Same as v1's `surface` exclusion. You can't insert an atom that "blends" into a surface mesh — it would render as a sphere on top of the surface, not as part of it. |
| **Surf** | Surface (Solvent-excluded). Continuous. | Same as QuickSurf. |
| **MSMS** | Surface (Sanner MSMS). Continuous. | Same. |
| **VolumeSlice** | Volumetric data slice. No atom-based structure. | Requires a volumetric map (density/potential). Hiders are atoms, not volume. |
| **Isosurface** | Volumetric isosurface. No atom-based structure. | Same as VolumeSlice. |
| **FieldLines** | Volumetric field lines. No atom-based structure. | Requires a vector field. |
| **Orbital** | Quantum orbital. No atom-based structure. | Requires orbital coefficients. |
| **Polyhedra** | Polyhedral coordination rep. Niche, hard to blend. | Renders coordination polyhedra — a hider atom would create a weird polyhedron, not blend. |
| **PaperChain** | Exotic/artsy (beta-sheet paperchain). Niche. | Not a standard structural-biology rep; hard to make a hider blend. |
| **Twister** | Exotic/artsy (twisted ribbon). Niche. | Same — non-standard. |
| **Dotted** | Surface dots. Niche. | Surface-derived; same exclusion as surface reps. |
| **Solvent** | Solvent-accessible surface. Niche. | Surface-derived. |

### Recommended GAME_REPS for v2.0

Based on the matrix, the **recommended v2.0 GAME_REPS** (balancing port cost, educational value, and blend-in fit):

```tcl
# v2 GAME_REPS — 10 reps (vs v1's 5), adding VMD-specific strengths
set GAME_REPS {
    Lines        ;# v1 lines (VMD default)
    VDW          ;# v1 spheres
    Licorice     ;# v1 sticks
    CPK          ;# NEW: ball-and-stick (differentiator)
    Cartoon      ;# v1 cartoon (hardest)
    NewCartoon   ;# NEW: modern cartoon (differentiator)
    Trace        ;# NEW: SS-independent (avoids v1 caveat)
    Tube         ;# NEW: SS-independent (avoids v1 caveat)
    Points       ;# NEW: easy tier
    DynamicBonds ;# NEW: dynamic challenge
}
```

**MVP subset (v2.0 phase 1):** `Lines`, `VDW`, `Licorice`, `Cartoon` (direct v1 ports — lowest risk).
**Phase 2 additions:** `NewCartoon`, `Tube`, `Trace` (SS-independent, avoid v1 caveat).
**Phase 3 differentiators:** `CPK`, `Points`, `DynamicBonds` + material blending.

---

## Anti-Features (Commonly Requested, Often Problematic — deliberately NOT build)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Surface rep hiders** (QuickSurf/Surf/MSMS/Dotted/Solvent) | "VMD has surface reps, why not support them?" | Doesn't fit blend-in (continuous mesh, not discrete atoms). Explicitly excluded by spec (same as v1's `surface` exclusion). | Support the 10 reps in GAME_REPS above. Document exclusion in UI. |
| **Volumetric rep hiders** (VolumeSlice/Isosurface/FieldLines/Orbital) | "VMD does volumes, could hide in density" | Requires volumetric data, not atoms. Hiders are atoms. Anti-feature. | Atoms-only hiders. |
| **In-place atom insertion** (PyMOL `cmd.pseudoatom` equivalent) | "Just add an atom to the loaded mol" | **VMD has no such API** (verified: atomselect has no `add`/`insert` method). Would require C++ plugin dev. | Option D: write PDB with hiders appended, `mol new` reload as new mol replacing original. Verified working. |
| **Separate GAME molecule for hiders** (Option B) | "Simpler — just make a 2nd mol for hiders" | **Breaks the core mechanic:** player could toggle the GAME mol off via GUI and trivially win (v1 AGENTS.md rule: "hiders in same object, else player toggles one to win"). | Option D: hiders in SAME molecule as real atoms (one PDB, one `mol new`). Verified. |
| **Graphics primitives as hiders** (Option C) | "`graphics $mol sphere` draws a sphere" | **Not pickable as atoms** (verified: `molinfo $gfx_id get numatoms` = 0). Click-to-find would need a custom pick handler for graphics objects — complex and non-standard. | Atoms-only hiders (Option D). Graphics OK for hints/highlights, not hiders. |
| **psfgen-based atom insertion** (Option A) | "It's the canonical VMD atom-addition pattern (autoionize)" | Requires topology files for real residues; hiders are fake atoms (resname GAM) with no topology entry. Overkill for our use case. | Option D (PDB write + reload) is simpler and sufficient. psfgen reserved for future "real residue" hiders if needed. |
| **Web backend / cloud / online leaderboard** | "Compare times online" | Out of scope per spec (no web/backend); VMD is single-user desktop. | Local-only. Times in `.bcm` sidecar. |
| **Auto-installing tcl libs** | "Just `package install` whatever" | Spec constraint: any lib must be listed, approved, vendored under `vmd/3rd_party_lib/`. | Use built-in `ttk` (Tk 8.5 ships with VMD). `tooltip.tcl` pending user approval (spec line 60). |
| **Modifying the original molecule's atoms** | "Move a real atom to make room for hiders" | Breaks scientific integrity; original molecule must be preserved. | Only ADD hider atoms (via Option D PDB append); never alter real atoms. |
| **Touch / mobile support** | "Run on a tablet" | VMD is desktop OpenGL; touch isn't a VMD target. | Desktop mouse + keyboard only. |
| **chimeraX port in v2** | "Why not ship both?" | Different tech stack; chimeraX is a later milestone (PROJECT.md). | VMD tcl is v2. chimeraX is future. |
| **Hard time limit / fail state** | "Lose if you don't find them in 60s" | Spec's timer is for scoring, not failure. Changes cozy-educational tone. | Timer counts up; no fail state. Reveal-all to end. |
| **Custom shaders for hiders** | "Make hiders glow when found" | Out of scope; rely on VMD's built-in OpenGL + `mol modcolor`/`mol showrep`. | Standard VMD recolor/hide for found status. |

---

## Feature Dependencies

```
[source biochemeleon.tcl] ──> [biochemeleon command] ──> [Setup window]
                                                          │
                ┌─────────────────────────────────────────┤
                ▼                                           ▼
    [Molecule dropdown] (molinfo list + trace vmd_molecule)  [Hider count]
                │                                           │
                ├──> [Demo set] (vmd/data/demos/)           │
                ├──> [PDB fetch] (mol new <url>)            │
                │                                           │
                ▼                                           ▼
    [Lock-scene checkbox] ──> [Per-rep hider list] ──> [Per-rep counts]
                │                                           │
                ▼                                           ▼
    [Detect active reps]                [Randomize per-rep] (quick-008 baked in)
    (molinfo get numreps + rep $i)      (randomize_per_rep port from v1)
                │
                ▼
    [7 Setup buttons]
        ├──> [Reset], [Randomize]
        ├──> [Save Setup] <──> [Load Setup] (JSON)
        ├──> [Generate & export] ──> [Option D: write PDB + hiders]
        │       └──> [.bcmz = .vmd + .bcm sidecar zipped]
        ├──> [Cleanup model] ──> [mol delete game-mol + mol new original + re-apply reps]
        └──> [Start] ──> [Initial-state storage]
                │       (original PDB path + rep snapshot via save_reps pattern)
                ├──> [Hider generation] (Option D)
                │       ├──> [Sphere/VDW hiders] (S — bbox RNG, ports from v1)
                │       ├──> [Line/stick/Licorice hiders] (M — auto-bond on reload)
                │       ├──> [Cartoon/NewCartoon hiders] (L — C-alpha segment, STRIDE)
                │       ├──> [Trace/Tube/Ribbons hiders] (M — C-alpha, SS-independent)
                │       ├──> [CPK/Points/DynamicBonds hiders] (M — differentiators)
                │       └──> [Material-blend hiders] (M — GameBlend/Glass material) ← v2 differentiator
                ├──> [Switch to Game tab]
                └──> [Countdown 3-2-1]

[Start] ──> [Timer] ──> [Win condition] (stops timer)
[Start] ──> [Game tab] ──> [mouse mode 0 0] (pick mode) ──> [trace vmd_pick_atom w]

[Game tab]
   ├──> [Rolling info box]
   ├──> [Remaining count] ──> [Difficulty toggle] (per-rep display)
   ├──> [Hint] ──> [add rep "within 5 of index N" + color ColorID] OR [label highlight]
   ├──> [Reveal-one] ──> [Reveal-all] ──> [Reveal counter]
   ├──> [Found-hider dropdown] ──> [mol showrep / mol modcolor]
   ├──> [Save] ──> [save_state .vmd + .bcm sidecar → .bcmz]
   └──> [Restart] ──> [mol delete + mol new original + re-generate]

[Core loop]
   [Click-to-find] ──> [trace vmd_pick_atom w callback]
        └──> check if vmd_pick_atom in hider registry (keyed by atom index)
        └──> [Found-status tracking] ──> [Win condition]

[Cross-cutting]
   [In-game explanation] (tooltips/help) ── enhances ──> everything
   [Controls help]       ── enhances ──> [Click-to-find]
   [Post-game debrief]   ── enhances ──> [Win condition] (differentiator)

[Conflicts]
   [Surface/volumetric reps]      ── conflicts ─> [Blend-in mechanic] → excluded (anti-features)
   [Separate GAME mol (Option B)] ── conflicts ─> [Core mechanic]     → use Option D (same mol)
   [Graphics primitives (Option C)] ── conflicts ─> [Click-to-find]  → atoms only (Option D)
   [psfgen (Option A)]            ── conflicts ─> [Simplicity]         → use Option D (PDB write)
   [tooltip.tcl 3rd-party lib]    ── conflicts ─> [No-unapproved-libs] → pending user approval
```

### Dependency Notes

- **Start requires hider generation (Option D) + initial-state storage + tab switch + countdown.** Start is the integration point — build it last among Setup-tab features.
- **Click-to-find requires the hider registry (atom-index list) + `trace variable vmd_pick_atom w`.** Build hider generation such that every hider's `(molid, atom_index)` is recorded; click handling is then `vmd_pick_atom in hider_registry`. **Picking can ONLY be GUI-tested** (vars don't populate headless — verified); testable proxy is `label add Atoms <molid>/<idx>` + `label list Atoms`.
- **Cleanup model requires the original PDB path + rep state saved at Start.** Unlike v1 (in-memory backup object), v2's "backup" is the on-disk source file. Cleanup = `mol delete game-mol` + `mol new <original.pdb>` + re-apply saved reps (viewmaster's `save_reps`/`restore_reps` pattern, verified).
- **Save/Load = `save_state .vmd` (VMD native, text) + `.bcm` JSON sidecar (game state) → `.bcmz` zip.** The `.vmd` captures mols+reps+materials+viewpoints (verified 22-25KB). The `.bcm` captures hider registry, found-status, timer, counts, setup params, original PDB path.
- **Cartoon/NewCartoon hiders are the hardest v2 feature (L).** STRIDE auto-runs on Cartoon reps (verified) but assigns SS to residues — a fake `GAM` residue will likely get `ss='C'` (coil), same as v1's Phase 11 caveat. **Tube/Trace are SS-independent alternatives** (recommended for v2.0 to sidestep the caveat).
- **Material blending is the v2 differentiator (spec line 61).** Verified API (`material add` + `material change opacity` + `mol modmaterial`). A hider with `GameBlend` (opacity 0.85) or `Glass1` (opacity 0.15) is subtly different from Opaque real atoms. Pedagogical value is MEDIUM confidence (hypothesis — needs gameplay validation).
- **Demo PDBs reuse v1's files directly** (copy `pymol/biochemeleon/data/demos/` → `vmd/data/demos/`). Sources already human-approved. No re-verification needed.

---

## MVP Definition

### Launch With (v2.0 — core loop must work on VMD)

The non-negotiable set to validate "source → launch GUI → setup → start → click-to-find → win" on VMD.

- [ ] Sourced tcl script + `biochemeleon` command → setup window (S)
- [ ] Setup: molecule dropdown (loaded + demo), hider count, lock-scene, per-rep list, difficulty (M)
- [ ] 7 setup buttons: Reset, Randomize, Save Setup, Load Setup, Generate & export, Cleanup, Start (M)
- [ ] **Hider generation via Option D (PDB write + reload):** Sphere/VDW + Line/Licorice + Cartoon (M) — the 3 v1 reps, ported. Random per-rep distribution baked in (quick-008).
- [ ] Game tab: info box, timer, remaining count, import, hint, reveal-one/all, found-dropdown, save, restart (M)
- [ ] **Click-to-find via `trace variable vmd_pick_atom w`** (M) — GUI-verify checkpoint (can't test headless)
- [ ] Win condition + winning message with time (S)
- [ ] Save/load = `.vmd` + `.bcm` sidecar → `.bcmz` (M)
- [ ] Bundled demo PDBs (reuse v1's 6) with sources cited (S — copy from v1)
- [ ] In-game explanation + controls help (S)
- [ ] Hider sentinel: `resname GAM + beta < 0` (S)

### Add After Validation (v2.1 — differentiators)

- [ ] **Material-blend hiders** (GameBlend/Glass material) — the spec's explicit exploration target. Trigger: core loop proven on VMD.
- [ ] **NewCartoon + Tube + Trace reps** (SS-independent alternatives to Cartoon) — Trigger: if v1's Phase 11 SS-inheritance caveat resurfaces in v2 Cartoon.
- [ ] **CPK + Points + DynamicBonds reps** — Trigger: users want more rep variety.
- [ ] **Post-game debrief** (show all hiders + "why hard to spot") — Trigger: positive feedback on educational angle.
- [ ] **Reveal counter + win-screen stats** — Trigger: once win condition is stable.
- [ ] **Fetched large demos** (1gzm/3gp6/sasdpg4) — Trigger: users want harder demos; needs VMD URL-fetch verification + strip pipeline.

### Future Consideration (v2.x+)

- [ ] **Trajectory mode** — hiders hidden across NMR frames (VMD's `vmd_frame` trace). VMD-specific; v1 had no trajectory concept.
- [ ] **Per-hider material variation** — each hider a slightly different opacity (ratchet difficulty).
- [ ] **chimeraX port** — future milestone (different extension model).
- [ ] **Puzzle authoring mode** — hand-place hiders (v1 future consideration too).

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Click-to-find (`trace vmd_pick_atom`) | HIGH | M | P1 |
| Hider generation — Sphere/VDW (Option D) | HIGH | S | P1 |
| Hider generation — Line/Licorice (Option D) | HIGH | M | P1 |
| Hider generation — Cartoon (Option D + STRIDE) | HIGH | L | P1* (phase if needed) |
| Start + countdown + tab switch | HIGH | M | P1 |
| Timer + win condition | HIGH | S | P1 |
| Hider registry + found-status (atom-index keyed) | HIGH | M | P1 (foundation) |
| Setup window (dropdown, count, lock, per-rep, difficulty) | HIGH | M | P1 |
| 7 setup buttons | HIGH | M | P1 |
| Game tab (info, remaining, hint, reveal, found-mgmt, save, restart) | HIGH | M | P1 |
| Save/load (`.vmd` + `.bcm` → `.bcmz`) | HIGH | M | P1 |
| Cleanup model (mol delete + reload original) | MEDIUM | M | P1 (safety net) |
| Bundled demo PDBs (reuse v1) | HIGH | S | P1 |
| In-game explanation + controls help | HIGH | S | P1 (constraint) |
| Generate & export / Import (paired) | MEDIUM | M | P1 (spec) |
| Hint (color neighbors via rep) | HIGH | M | P1 |
| Reveal-one / Reveal-all | HIGH | M | P1 |
| Restart from initial state | HIGH | S | P1 |
| **Material-blend hiders (GameBlend/Glass)** | HIGH (differentiator) | M | **P2 (v2.1 — spec exploration target)** |
| NewCartoon + Tube + Trace reps | MEDIUM | M | P2 |
| CPK + Points + DynamicBonds reps | MEDIUM | M | P2 |
| Post-game debrief | HIGH (educational) | M | P2 |
| Reveal counter + win-screen stats | MEDIUM | S | P2 |
| Fetched large demos | MEDIUM | M | P2 |
| Trajectory mode (vmd_frame) | LOW (v2.x) | L | P3 |
| Per-hider material variation | LOW | M | P3 |
| chimeraX port | HIGH (for v3) | L | P3 (future milestone) |

**Priority key:** P1 = must have for v2.0 launch; P2 = add after validation (v2.1); P3 = future (v2.x+).

\* Cartoon is spec'd as v1 (P1) but is the highest-risk item; if timeline forces a phase, ship Sphere/VDW + Line/Licorice first and bring Cartoon in v2.1 — OR use Tube/Trace (SS-independent) as the v2.0 cartoon-equivalent to sidestep the STRIDE caveat.

---

## Verification Log (headless VMD 1.9.3 tests)

All claims marked "verified" were confirmed by running headless VMD from WSL:
```bash
bash -ic "vmd -dispdev text -e C:/<path>/vmd_testN.tcl -eofexit" 2>&1 | tail -200
```
Test scripts: `tmp/vmd-test/vmd_test{1..6}.tcl` (gitignored under `tmp/`). Load target: `pymol/biochemeleon/data/demos/1znf.pdb` (424 atoms, 37 NMR frames).

| Claim | Test | Result |
|-------|------|--------|
| Default rep = Lines, sel=all, color=Name, material=Opaque | test1/2 | ✅ verified |
| `molinfo $mol get "{rep $i} {selection $i} {color $i} {material $i}"` returns flat list | test2 | ✅ verified (e.g. `Lines all Name Opaque`) |
| `mol addrep/modstyle/delrep/showrep` work | test2 | ✅ verified |
| `material list` = 23 materials | test3 | ✅ verified (Opaque, Transparent, BrushedMetal, Diffuse, Ghost, Glass1-3, Glossy, HardPlastic, MetallicPastel, Steel, Translucent, Edgy, EdgyShiny, EdgyGlass, Goodsell, AOShiny, AOChalky, AOEdgy, BlownGlass, GlassBubble, RTChrome) |
| `material add <name>` works | test3/6 | ✅ verified (GameMat1, GameBlend created) |
| `material change <prop> <name> <value>` works (prop: opacity/ambient/diffuse/specular/etc.) | test6 | ✅ verified |
| `mol modmaterial <rep> $mol <name>` applies material | test6 | ✅ verified |
| `atomselect get` works for: name/type/index/resname/resid/chain/segid/x/y/z/beta/occupancy/mass/charge/element/radius/atomicnumber/structure/phi/psi | test3 | ✅ verified (all 18 attrs) |
| `atomselect "beta < 0"` finds hiders | test4/6 | ✅ verified (3 atoms found) |
| `atomselect "resname GAM"` finds hiders | test6 | ✅ verified (3 atoms found) |
| `atomselect "segid GAME"` finds hiders | test6 | ⚠️ verified but PDB column-alignment-sensitive (test5 had a bug; segid must be in cols 73-76). Use `resname GAM and beta < 0` as canonical. |
| `label add Atoms <molid>/<atomindex>` creates pick-label | test4/6 | ✅ verified (e.g. `label list Atoms` = `{{1 424} 0.000000 show}`) |
| `vmd_pick_atom`/`vmd_pick_mol`/`vmd_pick_atom_clicks` exist in GUI mode | test3/4 | ⚠️ Do NOT exist in text mode (verified: `info exists` = 0). Only populated on real GUI click. Trace mechanism setup is valid. |
| `trace variable vmd_pick_atom w <cb>` setup works | test4 | ✅ verified (trace fires on `set vmd_pick_atom`) |
| `save_state <file.vmd>` writes text tcl script | test3/6 | ✅ verified (22-25KB; contains `vmdrestoremymaterials` + `mol new`/`mol addrep`/`material change`) |
| **Option D (write PDB + reload) inserts hiders into same molecule** | test6 | ✅ **verified: mol2 = 427 atoms (424 orig + 3 hiders), all in one `mol`** |
| atom `index` stable across PDB reload | test5 | ✅ verified (index=7 serial=8 matched before/after) |
| atomselect has NO `add`/`insert` method (no in-place atom insertion) | test4 | ✅ verified (methods list = frame/molid/text/delete/global/update/num/list/get/set/getbonds/setbonds/getbondorders/getbondtypes/moveto/moveby/lmoveto/lmoveby/move/writepdb/writeXXX) |
| `measure minmax` gives bounding box | test4/6 | ✅ verified |
| `atomselect get structure` returns SS code (STRIDE auto-runs) | test3/6 | ✅ verified (returns C/H/E; STRIDE license notice printed) |
| `trace variable vmd_initialize_structure w` fires on mol add/delete | test3 | ✅ verified (but it's an ARRAY var — callback must handle array) |
| `graphics $mol sphere/text` draws primitives (NOT pickable as atoms) | test3 | ✅ verified (numatoms=0 in graphics mol) |
| All 27 rep names accepted by `mol representation` | test3 | ✅ verified (Lines/Bonds/DynamicBonds/HBonds/Points/VDW/CPK/Licorice/Polyhedra/Trace/Tube/Ribbons/NewRibbons/Cartoon/NewCartoon/PaperChain/Twister/QuickSurf/Surf/MSMS/VolumeSlice/Isosurface/FieldLines/Orbital/Beads/Dotted/Solvent) |
| Color method `Structure` valid; `SecondaryStructure` INVALID | test3 | ✅ verified (use `Structure` for SS coloring) |
| `psfgen` available (v1.6.4) | test4 | ✅ verified (but Option D is simpler for fake-atom hiders) |

---

## Sources

- **Headless VMD 1.9.3 tests** (HIGH): `tmp/vmd-test/vmd_test{1..6}.tcl` — verified all API claims against `1znf.pdb`. Run via `bash -ic "vmd -dispdev text -e <path> -eofexit"`.
- **VMD 1.9.3 User's Guide** (HIGH): https://www.ks.uiuc.edu/Research/vmd/current/ug/ — Molecular Drawing Methods (node54), 27 representations (node55-82), Color categories (node84), Materials (node88), Selections (node89). Cross-verified rep list and color categories.
- **VMD reference plugins** (HIGH, in `vmd-ref/`):
  - `ramaplot1.1/ramaplot.tcl` — mouse pick callbacks, `trace variable vmd_frame`, molecule dropdown via `trace variable vmd_initialize_structure`, `atomselect` patterns. Closest to click-to-find.
  - `autoionize1.4/autoionize.tcl` — psfgen atom-addition pattern (Option A — rejected for v2 as overkill), GUI with `toplevel` + `wm protocol`.
  - `viewmaster2.6/viewmaster.tcl` — **THE canonical save/restore rep pattern**: `save_reps`/`restore_reps` iterate `molinfo $mol get numreps` + `molinfo $mol get "{rep $i}..."` + `mol addrep`/`mol modstyle`/`mol modselect`/`mol modcolor`/`mol modmaterial`/`mol showrep`/`mol showperiodic`/`mol selupdate`/`mol colupdate`/`mol scaleminmax`/`mol smoothrep`/`mol drawframes`/`mol clipplane`. Also `save_molecules` (viewpoint matrices via `molinfo $mol get {rotate_matrix center_matrix scale_matrix global_matrix}`) + `save_graphics` + `save_colors` + `save_colordefs` + `save_colorscale`.
  - `clonerep1.3/clonerep.tcl` — rep cloning across molecules (`clone_reps`), `molinfo list` molecule menu, `trace variable vmd_molecule w` for mol-list updates.
  - `mergestructs1.1/mergestructs.tcl` — psfgen merge (Option A variant), GUI patterns.
- **VMD materials.dat** (HIGH, `vmd-ref/scripts/materials.dat`): material definitions (Ambient/Diffuse/Specular/Shininess/Mirror/Opacity). Note: file has 11 entries but VMD 1.9.3 ships 23 (newer materials like Edgy/AO*/BlownGlass compiled in — verified via `material list`).
- **VMD colordefs.dat** (HIGH, `vmd-ref/scripts/colordefs.dat`): color category definitions.
- **VMD atomselect.tcl** (HIGH, `vmd-ref/scripts/atomselect.tcl`): `vmd_atomselect_lmoveby`/`moveto`/`lmoveto` — confirms `moveby`/`moveto` are the coord-modify methods (no `add`/`insert`).
- **v1 FEATURES.md** (HIGH, `.planning/research/FEATURES.md`): the v1 feature baseline being ported (46 reqs).
- **v1 MILESTONE-AUDIT.md** (HIGH, `.planning/milestones/v1-MILESTONE-AUDIT.md`): v1 PASSED (46/46 reqs, 12/12 phases) — confirms the feature set is validated.
- **v1 generators.py** (HIGH, `pymol/biochemeleon/generators.py`): pure-stdlib hider generators (`generate_sphere_positions`, `generate_line_stick_offsets`, `pick_terminal_residues`, `pick_segments`, `randomize_per_rep`) — directly portable to tcl (no pymol dependency).
- **v1 setup_state.py** (HIGH): `GAME_REPS = ['lines','sticks','spheres','cartoon','ribbon']`, `DEMO_MANIFEST` (9 demos), `PDB_POOL` (34 verified PDBs).
- **PROJECT.md** (HIGH): v2.0 target features + key decisions (Option D, quick-008 baked in, material exploration, headless testing).
- **spec.md** (HIGH): the source-of-truth requirement list. Line 61: "VMD has many more materials and representations, do research and suggest to limit the representation this game could play on."

---
*Feature research for: molecular visualization hide-and-seek game (bioCHEMeleon, VMD tcl script v2.0)*
*Researched: 2026-08-22*
*Method: headless VMD 1.9.3 API verification + v1 codebase analysis + VMD UG cross-verification*
