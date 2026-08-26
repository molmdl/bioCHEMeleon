# Phase 13 Research: VMD Extension Entry, Modeless Dialog & File Layout

**Researched:** 2026-08-27
**Domain:** VMD 1.9.3 sourced-tcl extension bootstrap (entry mechanism, modeless Tk dialog, `vmd/` file layout)
**Confidence:** HIGH (every API claim cited to `vmd-ref/` source or VMD-install script, read directly); MEDIUM-HIGH on `ttk::notebook` rendering (present in `scripts/tk8.5/ttk/` but unverifiable headless — Tk doesn't load in `-dispdev text`)
**Scope:** Entry/dialog/file-layout ONLY. The pure-layer tcl internals (`lib/setup_state.tcl`, `lib/registry.tcl`, tcltest) and the headless-execution smoke harness are owned by the parallel researcher — this doc states only the interface boundary.

---

## Summary

Phase 13's job is to make `source vmd/biochemeleon.tcl` register an Extensions-menu item and define a `biochemeleon` console command that opens a **modeless** `toplevel` + `ttk::notebook` with two placeholder tabs — the shell every later phase builds on. The canonical VMD 1.9.3 extension pattern is fully nailed down across 5 bundled reference plugins (`clonerep`, `viewmaster`, `ramaplot`, `autoionize`, `mergestructs`) and the VMD-install source `scripts/vmd/loadplugins.tcl`. The contract: a `namespace eval ::biochemeleon` + `package provide biochemeleon $ver` (top-level, OUTSIDE the namespace) + procs + a global `biochemeleon` proc (user-runnable console command) + a `biochemeleon_tk_cb` proc (returns the widget path for the Extensions menu) + a `vmd_install_extension` call guarded by `if {[info exists tk_version]}`. Sourcing DEFINES the command and registers the menu; the `biochemeleon` command (or menu click) OPENS the dialog — sourcing does NOT auto-open (requirement ENTRY-01 says "the `biochemeleon` command opens" the dialog; auto-open would also break headless sourcing).

Two findings the planner MUST get right (both verified deeper than the milestone research): (1) **the re-source guard must run BEFORE the `namespace eval` body** — the literal PITFALLS.md pattern (`variable loaded 0` inside `namespace eval` then `if {$loaded} return` after) has a reset-on-re-source bug because `variable loaded 0` re-initializes on every `source`; (2) the **Extensions-menu path must be category-prefixed** (`"Visualization/bioCHEMeleon"`, matching `clonerep`/`viewmaster`) — the milestone research is inconsistent (`STACK.md:68` says `"Visualization/bioCHEMeleon"` but `ARCHITECTURE.md:184` and `PITFALLS.md:420` say `"Extensions/bioCHEMeleon"`, which would double-nest an "Extensions" submenu inside the Extensions menu).

**Primary recommendation:** Build `vmd/biochemeleon.tcl` as a single sourced file that (a) guards re-source via a top-of-file `info exists ::biochemeleon::loaded` check BEFORE the namespace body, (b) `package provide biochemeleon 2.0` so `vmd_install_extension`'s internal `package require` is a no-op (no `pkgIndex.tcl` needed for the sourced form), (c) defines a global `biochemeleon` proc + a `biochemeleon_tk_cb` proc returning `$::biochemeleon::w`, (d) registers via `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"` inside an `if {[info exists tk_version]}` block, (e) builds a modeless `toplevel .biochemeleon` with `ttk::notebook` (Setup/Game tabs), singleton re-show via `wm deiconify`, and NO `grab set` anywhere on the main dialog. Source `vmd/lib/setup_state.tcl` to establish the pure layer from day one (success criterion 4).

---

## Entry Mechanism

### 1. `vmd_install_extension` — exact contract

**Definition** — `vmd-ref/scripts/loadplugins.tcl:114-122`:
```tcl
proc vmd_install_extension {package tk_callback menupath {winname ""}} {
  if ![string length $winname] {set winname $package}

  if [catch {package require $package} msg] {
    puts "The $package package could not be loaded:\n$msg"
  } elseif [catch {menu tk register $winname $tk_callback $menupath} msg] {
    puts "The $package window could not be created:\n$msg"
  }
}
```

**Verified facts:**
- Signature: `vmd_install_extension <package> <tk_callback> <menupath> {?winname?}`.
- It does two things: `package require $package`, then `menu tk register $winname $tk_callback $menupath`. Both are wrapped in `catch` — a failure PRINTS a warning but does NOT abort the script. So calling it in text mode won't crash sourcing, but it WILL print "The biochemeleon window could not be created" noise (because `menu tk register` needs Tk). **Guard it with `if {[info exists tk_version]}`** so text-mode sourcing is silent.
- `winname` defaults to `$package` — this is the "menu window name" VMD uses to track open/close state. Pass it explicitly only if the package name and the window-tracking name differ (e.g. `autoionizegui` uses `winname=autoionize` — `loadplugins.tcl:181`). For biochemeleon, package name == window name == `biochemeleon`, so omit the 4th arg.
- **The `tk_callback` proc takes NO arguments and returns the toplevel widget path** — VMD needs the path for menu open/close tracking. Verified across all 5 reference plugins:
  - `clonerep.tcl:237-240`: `proc clonerep_tk_cb {} { ::CloneRep::clonerepgui; return $::CloneRep::w }`
  - `viewmaster.tcl:1087-1090`: `proc viewmaster_tk_cb {} { ::ViewMaster::init; return $ViewMaster::w }`
  - `ramaplot.tcl:663-666`: `proc ramaplot_tk {} { ::RamaPlot::ramaplot; return $::RamaPlot::w }`
  - `mergestructs.tcl:992-995`: `proc mergestructs_tk {} { ::MergeStructs::mergestructs; return $::MergeStructs::w }`
  - `autoionizegui.tcl:13-15`: `proc autoigui {} { return [::Autoi::autoi_gui] }` (and `autoi_gui` ends `return $w` at line 194)
- **GUI-only registration:** `vmd_load_extension_packages` (the function VMD itself calls at startup to register the bundled plugins) returns early in text mode — `loadplugins.tcl:131-134`:
  ```tcl
  proc vmd_load_extension_packages {} {
    global tk_version
    global env
    if ![info exists tk_version] return
    ...
  ```
  So at VMD startup, bundled extensions only register in GUI mode. For our SOURCED script, the same `if {[info exists tk_version]}` guard applies to our own `vmd_install_extension` call (we control it; we want it skipped in text mode).

### 2. Sourced-script entry pattern — `source` → command defined

The requirement (ENTRY-01) says: "Sourced tcl script + `biochemeleon` command opens a modeless Tk toplevel." So sourcing must (a) DEFINE a `biochemeleon` command, and (b) register the Extensions-menu item. Sourcing does NOT open the dialog — the user runs `biochemeleon` (or clicks the menu item) to open it. This is the cleanest model and matches the requirement text exactly.

**How `source biochemeleon.tcl` makes `biochemeleon` available at the console:** define a GLOBAL proc named `biochemeleon` that delegates to the namespace proc. This is exactly the `autoionize` pattern — `autoionize.tcl:50`:
```tcl
proc autoionize { args } { return [eval ::autoionize::autoionize $args] }
```
For biochemeleon, the global command opens the dialog in GUI mode and no-ops (with a console message) in text mode:
```tcl
proc biochemeleon {args} {
    if {![info exists tk_version]} {
        vmdcon -warn "bioCHEMeleon: GUI not available (headless mode); the dialog requires Tk."
        return
    }
    ::biochemeleon::open_dialog
    return $::biochemeleon::w
}
```
(`ramaplot.tcl:109-111` is the same idiom: a global `proc ramaplot {} { ::RamaPlot::ramaplot }` that the user types, delegating to the namespace proc.)

**Cleanest sourced-script structure** (synthesized from `clonerep.tcl:16-27` + `viewmaster.tcl:26-58` + the autoionize dual-proc pattern):
```tcl
# vmd/biochemeleon.tcl — Phase 13 entry
# --- (1) re-source guard MUST come before the namespace eval body (see §Pitfalls) ---
if {[info exists ::biochemeleon::loaded] && $::biochemeleon::loaded} {
    vmdcon -warn "bioCHEMeleon already loaded; ignoring re-source"
    return
}

# --- (2) namespace + state (variable initializers only run once thanks to the guard) ---
namespace eval ::biochemeleon {
    variable version 2.0
    variable loaded  1            ;# set on first load; guard above stops re-entry
    variable w                     ;# toplevel handle (namespace scope = GC prevention)
    variable state                 ;# game state — init only if not already set
    if {![info exists state]} {
        set state [dict create timer 0 found [list] setup [dict create]]
    }
    namespace export biochemeleon
}

# --- (3) package provide BEFORE vmd_install_extension so its package require is a no-op ---
package provide biochemeleon $::biochemeleon::version

# --- (4) source the pure layer + (later) GUI/engine modules ---
set _dir [file dirname [info script]]
source [file join $_dir lib setup_state.tcl]
# (Phase 13: only setup_state.tcl is sourced. lib/registry.tcl + gui/*.tcl come in later phases.)
unset _dir

# --- (5) the dialog proc (GUI; called by both the console command and _tk_cb) ---
proc ::biochemeleon::open_dialog {} {
    variable w
    if {[winfo exists .biochemeleon]} { wm deiconify $w; return }   ;# singleton re-show
    set w [toplevel .biochemeleon]
    wm title $w "bioCHEMeleon"
    set nb [ttk::notebook $w.nb]
    ttk::frame $nb.setup ; ttk::frame $nb.game
    $nb add $nb.setup -text "Setup"
    $nb add $nb.game  -text "Game"
    pack $nb -fill both -expand yes
}

# --- (6) global console command (user types `biochemeleon` at the VMD console) ---
proc biochemeleon {args} {
    if {![info exists tk_version]} {
        vmdcon -warn "bioCHEMeleon: GUI requires Tk (not available in -dispdev text)."
        return
    }
    ::biochemeleon::open_dialog
    return $::biochemeleon::w
}

# --- (7) Extensions-menu callback (returns the widget path VMD tracks) ---
proc biochemeleon_tk_cb {} {
    ::biochemeleon::open_dialog
    return $::biochemeleon::w
}

# --- (8) register in the Extensions menu (GUI mode only) ---
if {[info exists tk_version]} {
    if {[llength [info commands vmd_install_extension]]} {
        vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"
    }
}
# Sourcing does NOT auto-open the dialog — the user runs `biochemeleon` or clicks the menu item.
```

**`package provide` before `vmd_install_extension` — why this works without a `pkgIndex.tcl`:** `vmd_install_extension` calls `package require biochemeleon` (loadplugins.tcl:117). In Tcl, `package require` on an already-`provide`d package returns immediately without sourcing anything — no `pkgIndex.tcl` on `auto_path` is needed for the SOURCED form. `package provide biochemeleon $ver` (line 3 above) marks it loaded before the `vmd_install_extension` call. This keeps the door open for the optional packaged form (drop in a `pkgIndex.tcl` later) while making the sourced form work standalone. Verified reasoning against Tcl 8.5 package semantics; this is exactly how `viewmaster.tcl:26` does `package provide ViewMaster 2.6` at the top.

**Does sourcing open the dialog?** NO. The requirement (ENTRY-01) and ROADMAP success criterion 2 both say the *command* opens it. Auto-open-on-source (suggested in `STACK.md:147` `if {[info exists tk_version]} { ::bioCHEMeleon::gui }`) is an alternative but is REJECTED here because: (a) it contradicts the requirement text, (b) it would surprise users who source from `.vmdrc` (they want the menu registered, not a window popping up on every VMD launch), (c) the clean "source defines; command opens" model is what `clonerep`/`viewmaster`/`ramaplot` all do (they expose a `*_tk_cb` the menu calls; they never auto-open on source). The planner should follow the requirement.

### 3. Re-source guard — the top-of-file `info exists` check

**Why the guard is needed:** re-sourcing re-runs the `namespace eval` body, and `variable x <value>` RE-INITIALIZES `x` every time (Pitfall 13 — `PITFALLS.md:402`: "`namespace eval ::DoubleTest` twice → second `variable x 10` WINS (x reset to 10)"). Without a guard, re-sourcing resets game state mid-session.

**CORRECT pattern (check BEFORE the namespace eval body, at the very top of the file):**
```tcl
if {[info exists ::biochemeleon::loaded] && $::biochemeleon::loaded} {
    vmdcon -warn "bioCHEMeleon already loaded; ignoring re-source"
    return
}
```
- `info exists ::biochemeleon::loaded` is SAFE on a not-yet-created namespace (returns 0, no error) — verified Tcl 8.5 `info exists` semantics.
- `return` at the top level of a sourced file terminates the `source` cleanly (standard Tcl: `source` treats a top-level `return` as normal completion). This is the early-exit idiom.

**BUG IN THE LITERAL MILESTONE PATTERN — flag for the planner:** `PITFALLS.md:407-415` recommends:
```tcl
namespace eval ::BioChm { variable loaded 0; variable state ... }
if {$::BioChm::loaded} { vmdcon -warn ...; return }
set ::BioChm::loaded 1
```
This is BUGGY: `variable loaded 0` inside `namespace eval` resets `loaded` to 0 on EVERY source, so the `if {$::BioChm::loaded}` check immediately after ALWAYS sees 0 (just reset) and never returns. The check must run BEFORE the namespace eval body re-initializes the flag. The correct form is the top-of-file check shown above, OR (equivalently) using `if {![info exists loaded]} { set loaded 0 }` INSIDE the namespace eval and checking after. The top-of-file form is simpler and is what this research recommends.

**What must persist across re-sources:** the `loaded` flag, and any game-state variables (`state` dict, the toplevel handle `w`). Guard state init with `if {![info exists state]} { set state ... }` INSIDE the namespace eval (shown in the skeleton above). Procs do NOT need guarding — Tcl silently redefines a proc on re-source (last wins, no error — `PITFALLS.md:417` "Procs are safe to redefine").

**What must NOT happen on re-source:** (a) game state reset to defaults, (b) a SECOND toplevel opening (the `winfo exists .biochemeleon` singleton check in `open_dialog` prevents this — see §Modeless Dialog), (c) duplicate Extensions-menu registration (the `loaded` guard stops the whole re-source, so `vmd_install_extension` is not re-called; even if it were, `menu tk register` with the same `winname` is idempotent-ish but noisy — better to skip via the guard).

### 4. Extensions-menu label — exact string

The requirement (ENTRY-02) says the item is `"bioCHEMeleon"` in the VMD Extensions menu. The `menu tk register` (inside `vmd_install_extension`) takes a `menupath` whose LAST segment is the item label and whose preceding segments are submenu names under the Extensions menu. Verified against every bundled call in `loadplugins.tcl:137-236`:
- `"Analysis/Ramachandran Plot"` (line 153) → Extensions → Analysis → "Ramachandran Plot"
- `"Modeling/Merge Structures"` (line 192) → Extensions → Modeling → "Merge Structures"
- `"Visualization/Clone Representations"` (line 213) → Extensions → Visualization → "Clone Representations"
- `"Visualization/ViewMaster"` (line 231) → Extensions → Visualization → "ViewMaster"
- `"Tk Console"` (line 235, no slash) → top-level item directly under Extensions

**Recommendation: `"Visualization/bioCHEMeleon"`** — gives the item label "bioCHEMeleon" (satisfies ENTRY-02) under the Visualization submenu, matching the two closest analog plugins (`clonerep` and `viewmaster`, both rep/scene-visualization tools like ours). This also matches `STACK.md:68`.

**DO NOT use `"Extensions/bioCHEMeleon"`** (as `ARCHITECTURE.md:184` and `PITFALLS.md:420` suggest) — there is no "Extensions" submenu inside the Extensions menu (the Extensions menu IS the root); this would create a redundant nested "Extensions" submenu. Flagged as a milestone-research inconsistency for the planner to resolve. (A bare `"bioCHEMeleon"` with no slash is also valid and puts the item at the top level of the Extensions menu, like "Tk Console" — but the category-prefixed form is more conventional and keeps the menu tidy.)

**Casing:** the string is passed verbatim as the menu label. `"bioCHEMeleon"` preserves the project's camelCase. No casing constraints beyond what the string itself expresses.

### 5. "Package install" (pkgIndex.tcl + package require) vs "direct source"

Two loading strategies exist (`PITFALLS.md:418-420`):
- **Direct `source` (RECOMMENDED for Phase 13, the primary form per spec).** User runs `source /path/to/biochemeleon.tcl` (or `.vmdrc` does). No `pkgIndex.tcl` needed — the `package provide` inside the script makes `vmd_install_extension`'s internal `package require` a no-op (see §2). The re-source guard handles double-load.
- **`package require` (optional, future).** Ship a `pkgIndex.tcl` with `package ifneeded biochemeleon 2.0 [list source [file join $dir biochemeleon.tcl]]` (the exact form in every `vmd-ref/plugins/*/pkgIndex.tcl`, e.g. `clonerep1.3/pkgIndex.tcl:11`, `viewmaster2.6/pkgIndex.tcl:11`); user `lappend auto_path /dir` in `.vmdrc`, then `vmd_install_extension biochemeleon biochemeleon_tk_cb "Visualization/bioCHEMeleon"` (or `package require biochemeleon`).

**For Phase 13, ship BOTH hooks cheaply:** write `vmd/biochemeleon.tcl` to work standalone when sourced (the `package provide` + guard + `vmd_install_extension` call inside the script), AND include a `vmd/pkgIndex.tcl` so the optional packaged form works too. The `pkgIndex.tcl` costs 2 lines and unlocks the "auto-appears in Extensions menu" install path without changing the sourced form. This matches the `STACK.md:79` guidance: "Design the file to support BOTH — costs nothing and keeps the door open."

---

## Modeless Dialog

### 6. Modeless `toplevel` + `ttk::notebook` — exact tcl

**Singleton re-show pattern** (re-calling `biochemeleon` focuses the existing dialog, doesn't open a second). Verified across the reference GUI plugins:
- `viewmaster.tcl:66-69`:
  ```tcl
  if { [winfo exists .viewmaster] } {
      wm deiconify $w
      return
  }
  ```
- `autoionizegui.tcl:46-49`:
  ```tcl
  if { [winfo exists .autoigui] } {
      wm deiconify .autoigui
      return
  }
  ```
- `ramaplot.tcl:125-128`:
  ```tcl
  if [winfo exists .rama] {
      wm deiconify $w
      return
  }
  ```
- `mergestructs.tcl:44-47`: same `winfo exists .mergestructs → wm deiconify $w → return`.

(`clonerep.tcl:166-168` is the ANTI-pattern for our use: `set w .clonerepgui; catch {destroy $w}; toplevel $w` — it DESTROYS and recreates every time. We do NOT want this because it would lose game state held in GUI widgets. Use the `viewmaster`/`ramaplot`/`autoionizegui` deiconify pattern instead.)

**`ttk::notebook` with two placeholder tabs** — ready-to-adapt skeleton (the `open_dialog` proc from §2):
```tcl
proc ::biochemeleon::open_dialog {} {
    variable w
    if {[winfo exists .biochemeleon]} { wm deiconify $w; return }
    set w [toplevel .biochemeleon]
    wm title $w "bioCHEMeleon"

    set nb [ttk::notebook $w.nb]
    ttk::frame $nb.setup
    ttk::frame $nb.game
    $nb add $nb.setup -text "Setup"
    $nb add $nb.game  -text "Game"

    # Placeholder content (Phase 13 ships empty tabs; Phase 14/16 populate them)
    ttk::label $nb.setup.placeholder -text "Setup tab (Phase 14)"
    ttk::label $nb.game.placeholder  -text "Game tab (Phase 16)"
    pack $nb.setup.placeholder -padx 20 -pady 20
    pack $nb.game.placeholder  -padx 20 -pady 20

    pack $nb -fill both -expand yes
}
```
**`ttk::notebook` API (standard Tk 8.5 ttk):** `ttk::notebook $path` creates it; `$nb add $tab -text "label"` adds a tab; `$nb select $tab` / `$nb index current` select/query. ttk ships with VMD's Tk 8.5 (`scripts/tk8.5/ttk/` per `STACK.md:22`). **Confidence MEDIUM-HIGH:** the widget library is present but cannot be exercised headless (Tk doesn't load in `-dispdev text` — `STACK.md:21`, `PITFALLS.md:464`); flag for the first GUI smoke. None of the 5 bundled reference plugins use `ttk::notebook` (they predate widespread ttk adoption and use `frame`/`menubutton`), so there's no direct in-repo example — but `ttk::notebook` is standard Tk 8.5.

### 7. NO `grab set` — the hard constraint

**`grab set` on the main panel is FORBIDDEN** (ENTRY-01: "the main dialog does NOT use `grab set` so the 3D viewer stays interactive for click-to-find"). `grab set` redirects ALL pointer events to one window — the OpenGL viewer gets nothing (Pitfall 4, `PITFALLS.md:135-152`).

**Verified that the reference plugins NEVER `grab set` on a main window** — `grab set` appears exactly ONCE across all 5 plugins, on a *transient sub-dialog*:
- `mergestructs.tcl:138`: `grab set ".ibselectmol"` — a forced "pick a molecule" popup, released when the user picks. NOT on `.mergestructs` (the main window).
- `clonerep.tcl`, `viewmaster.tcl`, `ramaplot.tcl`, `autoionize*.tcl`: ZERO `grab set` on any window.

The main dialogs all use bare `toplevel` + `wm title` + `wm deiconify` (singleton re-show) with no grab. This is the convention. Our `open_dialog` above follows it: no `grab`, no `tkwait`, no `vwait`.

**`grab set` IS allowed** on brief transient children (e.g. a "pick a molecule to start" popup) and `tk_messageBox` is fine (modal but brief — every reference plugin uses it, e.g. `clonerep.tcl:183`, `viewmaster.tcl:1078`). Never on the main `.biochemeleon` panel.

**MEDIUM-confidence flag (needs one GUI human-verify, `PITFALLS.md:152`, Open Question 1):** whether `grab set` *fully* blocks the VMD OpenGL viewer in 1.9.3 (vs just blocking other Tk windows) couldn't be verified headless. Prevention is the same either way (modeless main panel) — so this flag doesn't change Phase 13's design, only the verification checklist.

### 8. GUI/headless guard — the exact idiom

**The idiom is `if {[info exists tk_version]}`** (NOT `if {[winfo exists .]}` — `winfo` needs Tk, so it would itself fail headless). Verified:
- `loadplugins.tcl:132-134`: `global tk_version ... if ![info exists tk_version] return`
- `STACK.md:147`: `if {[info exists tk_version]} { ::bioCHEMeleon::gui }`
- `PITFALLS.md:421`: "guard GUI setup with `if [info exists tk_version]` so text-mode sourcing doesn't error on Tk commands"
- `PITFALLS.md:495`: "Guard with `if [info exists tk_version]`; it returns early otherwise (`loadplugins.tcl:134`)."

`tk_version` is a global set by Tk when it loads; it is ABSENT in `-dispdev text` (verified `PITFALLS.md:464`, `STACK.md:21`: `package require Tk` fails headless). So `info exists tk_version` is the clean GUI-only predicate.

**What happens headlessly when `biochemeleon` is called but `tk_version` doesn't exist:** the global `biochemeleon` proc (skeleton §2) prints `vmdcon -warn "bioCHEMeleon: GUI requires Tk (not available in -dispdev text)."` and returns. This is the graceful no-op that satisfies ROADMAP success criterion 3 (headless `source` + `biochemeleon` runs "without error"). The `vmd_install_extension` call (§2 step 8) is also inside `if {[info exists tk_version]}`, so text-mode sourcing skips it entirely (no `menu tk register` noise).

---

## File Layout

### 9. Proposed `vmd/` tree — mirroring `pymol/biochemeleon/`

This mirrors the milestone decision (`SUMMARY.md:76-84`, `STATE.md` v2 architecture) and the v1 layout (`pymol/biochemeleon/__init__.py` + flat modules + `pymol/biochemeleon/data/demos/` + `pymol/tests/` + `pymol/smoke/`), with v2's cleaner `lib/`+`gui/` split per the milestone research:

```
vmd/
├── biochemeleon.tcl          # ENTRY (sourced): namespace + package provide + re-source guard +
│                             #   global `biochemeleon` proc + `biochemeleon_tk_cb` + vmd_install_extension.
│                             # Sources lib/*.tcl and gui/*.tcl. Mirrors pymol/biochemeleon/__init__.py.
├── pkgIndex.tcl              # OPTIONAL (2 lines): package ifneeded biochemeleon 2.0 [list source ...]
│                             #   Enables the packaged-install form. No cost; keeps the door open (STACK.md:79).
├── lib/                      # Engine + pure layer (mirrors pymol/biochemeleon/*.py modules)
│   ├── setup_state.tcl       # PURE: stdlib-only tcl (no mol, no tk). GAME_REPS + DEMO_MANIFEST live here.
│   │                         #   Unit-testable in WSL via tclsh/tcltest. Mirrors setup_state.py. [OTHER RESEARCHER]
│   ├── registry.tcl          # PURE: dict-keyed hider registry + DI reconstruct_from_sentinels. [OTHER RESEARCHER]
│   ├── backup.tcl            # cmd bridge: snapshot viewpoint+reps+original-path; restore = mol delete + reload.
│   ├── mutation.tcl          # cmd bridge: PDB-rebuild + sentinel tagging + cleanup.
│   ├── pick.tcl              # cmd bridge: mouse mode + trace/callback registration (Phase 16).
│   ├── game.tcl              # cmd orchestrator (composition root): start/on_pick/hint/reveal/save/restart. Mirrors game.py.
│   ├── persistence.tcl       # cmd bridge: .bcm JSON sidecar + combined-PDB round-trip. Mirrors persistence.py.
│   ├── demos.tcl             # cmd bridge: demo manifest + mol new loader. Mirrors demos.py.
│   └── generators.tcl        # pure-ish: per-rep hider placement (sphere/lines/cartoon/...). Mirrors generators.py.
├── gui/                      # GUI layer — Tk/ttk ONLY, NO mol calls (mirrors gui_setup.py + gui_game.py)
│   ├── dialog.tcl            # toplevel .biochemeleon + ttk::notebook + singleton re-show. open_dialog proc.
│   ├── setup_tab.tcl         # Setup tab widgets (Phase 14). Mirrors gui_setup.py.
│   └── game_tab.tcl          # Game tab widgets (Phase 16). Mirrors gui_game.py.
├── data/
│   └── demos/                # Bundled PDBs (REUSED VERBATIM from pymol/biochemeleon/data/demos/ — viewer-agnostic)
│       ├── 1k8p.pdb          #   6 small bundled demos (1k8p, 1xdn, 1znf, 2qbz, 4wb3, 5e54)
│       ├── 1xdn.pdb          #   + SOURCES.md (human-approved CC0/RCSB/MemProtMD citations from v1)
│       ├── 1znf.pdb          #   Large fetched demos (1GZM, 3GP6) added in Phase 21 (DEMOS-02/03).
│       ├── 2qbz.pdb
│       ├── 4wb3.pdb
│       ├── 5e54.pdb
│       └── SOURCES.md        # Attribution (carried over from v1, human-approved).
├── tests/                    # tcltest pure-layer tests (mirrors pymol/tests/)
│   ├── test_setup_state.test # tcltest; runs under WSL `tclsh` (NO VMD, NO Python). [OTHER RESEARCHER]
│   └── test_registry.test    # tcltest; pure registry. [OTHER RESEARCHER]
└── smoke/                    # Headless VMD smoke scripts (mirrors pymol/smoke/)
    └── phase13_smoke.tcl     # source + biochemeleon headless smoke (the entry half this research informs).
```

**Phase 13 creates ONLY the entry skeleton + the pure-layer stub:**
- `vmd/biochemeleon.tcl` (full entry, per §2 skeleton)
- `vmd/lib/setup_state.tcl` (minimal: `namespace eval ::biochemeleon::setup { variable GAME_REPS ... ; variable DEMO_MANIFEST ... }`, stdlib-only — the OTHER researcher owns the full internals + its `tests/test_setup_state.test`)
- `vmd/pkgIndex.tcl` (2-line optional)
- `vmd/smoke/phase13_smoke.tcl` (the entry-half smoke: `source` + `biochemeleon` + assert no error — the OTHER researcher owns the harness invocation mechanics)
- The `lib/` engine modules, `gui/` tab modules, and `data/demos/` PDBs are created in later phases (Phase 14+), but the directory structure is established now so ENTRY-03 ("all v2 code lives under `vmd/`") holds from day one. Copy v1's `pymol/biochemeleon/data/demos/*.pdb` + `SOURCES.md` into `vmd/data/demos/` now OR in Phase 14 — they're viewer-agnostic (PDB is PDB); the milestone reuses them verbatim (`SUMMARY.md:47`, `PITFALLS.md:40`).

**ENTRY-03 confirmation (zero external deps, only tcl/Tk 8.5 + ttk):** the entry/dialog use only `toplevel`, `wm`, `winfo`, `ttk::notebook`, `ttk::frame`, `ttk::label`, `pack`, `info exists`, `namespace`, `package provide`, `proc`, `dict`, `vmdcon`, `vmd_install_extension` — all shipped with VMD 1.9.3 (`STACK.md:19-24` verified Tcl 8.5.6 + Tk 8.5 + ttk bundled, no `pip`/`npm`/`package install`). No `tooltip.tcl`, no `tklib`, no `BWidget` (none ship — `STACK.md:31`, `PITFALLS.md:93`). CONFIRMED.

**Module-path resolution in the entry:** `set _dir [file dirname [info script]]; source [file join $_dir lib setup_state.tcl]`. `[info script]` returns the path of the file being sourced — the standard Tcl idiom for locating sibling files relative to the script. This works under VMD (`PITFALLS.md:324` references `[info script]` for demo paths). `unset _dir` cleans up the temp var.

---

## Verified API Facts (file:line citations)

| Claim | Citation | Confidence |
|-------|----------|------------|
| `vmd_install_extension {package tk_callback menupath {winname ""}}` signature | `vmd-ref/scripts/loadplugins.tcl:114` | HIGH (read source) |
| It does `package require $package` then `menu tk register $winname $tk_callback $menupath`, both in `catch` | `loadplugins.tcl:117-121` | HIGH |
| `winname` defaults to `$package` | `loadplugins.tcl:115` | HIGH |
| `vmd_load_extension_packages` returns early if no `tk_version` (GUI-only) | `loadplugins.tcl:132-134` | HIGH |
| `_tk_cb` proc takes no args, returns the widget path | `clonerep.tcl:237-240`, `viewmaster.tcl:1087-1090`, `ramaplot.tcl:663-666`, `mergestructs.tcl:992-995` | HIGH (4 plugins) |
| Global `<name>` proc delegates to namespace proc (user console command) | `autoionize.tcl:50` (`proc autoionize {args} { return [eval ::autoionize::autoionize $args] }`), `ramaplot.tcl:109-111` | HIGH |
| `package provide <Name> <ver>` at top-level, OUTSIDE `namespace eval` | `viewmaster.tcl:26` (`package provide ViewMaster 2.6`), `clonerep.tcl:27`, `ramaplot.tcl:13`, `mergestructs.tcl:13` | HIGH |
| `pkgIndex.tcl` form: `package ifneeded <name> <ver> [list source [file join $dir <file>.tcl]]` | `clonerep1.3/pkgIndex.tcl:11`, `viewmaster2.6/pkgIndex.tcl:11`, `autoionize1.4/pkgIndex.tcl:11`, `mergestructs1.1/pkgIndex.tcl:11`, `ramaplot1.1/pkgIndex.tcl:11` | HIGH |
| Singleton re-show: `if {[winfo exists .name]} { wm deiconify $w; return }` | `viewmaster.tcl:66-69`, `autoionizegui.tcl:46-49`, `ramaplot.tcl:125-128`, `mergestructs.tcl:44-47` | HIGH (4 plugins) |
| Main dialog: `toplevel .name` + `wm title` + NO `grab` | `viewmaster.tcl:70-71`, `ramaplot.tcl:130-131`, `clonerep.tcl:168-169`, `autoionizegui.tcl:50-51`, `mergestructs.tcl:51-52` | HIGH |
| `grab set` appears ONCE, only on a transient sub-dialog (never main) | `mergestructs.tcl:138` (`grab set ".ibselectmol"`) | HIGH |
| GUI guard idiom: `if {[info exists tk_version]}` / `if ![info exists tk_version]` | `loadplugins.tcl:132-134`, `STACK.md:147`, `PITFALLS.md:421,495` | HIGH |
| Tcl 8.5.6 — NO `lmap`/`try`/`tailcall`/`coroutine`; `dict`/`lassign`/`trace` available | `STACK.md:20`, `PITFALLS.md:374-375` | HIGH (runtime-verified) |
| Menu path is category-prefixed (`"Visualization/ViewMaster"`) | `loadplugins.tcl:213,231` | HIGH |
| `namespace eval` body re-runs on re-source; `variable x <val>` re-initializes | `PITFALLS.md:402` (runtime-verified) | HIGH |
| Procs silently redefine on re-source (last wins, no error) | `PITFALLS.md:417` | HIGH |
| v1 modeless analog: `dialog.show()` never `.exec_()`; module-level `dialog = None` singleton | `pymol/biochemeleon/__init__.py:5,141-153` | HIGH (read v1 source) |
| `[info script]` for sibling-file path resolution | `PITFALLS.md:324` | HIGH |

---

## Pitfalls & Mitigations (entry/dialog subset)

| # | Pitfall | Mitigation | Citation |
|---|---------|------------|----------|
| 1 | **Re-source resets game state** — `variable x <val>` inside `namespace eval` re-initializes on every `source`. The literal `PITFALLS.md:407-415` pattern has this bug (guard checks AFTER the reset). | Top-of-file guard BEFORE the namespace eval body: `if {[info exists ::biochemeleon::loaded] && $::biochemeleon::loaded} { vmdcon -warn ...; return }`. State init inside namespace eval guarded by `if {![info exists state]} { set state ... }`. | `PITFALLS.md:402,417`; this research §3 |
| 2 | **`vmd_install_extension` noise in text mode** — `menu tk register` fails without Tk, printing "The biochemeleon window could not be created" (caught, doesn't crash, but noisy). | Wrap the `vmd_install_extension` call in `if {[info exists tk_version]}`. It's already internally `catch`-wrapped so it won't crash either way, but the guard keeps sourcing silent. | `loadplugins.tcl:117-121,134`; `PITFALLS.md:495` |
| 3 | **Unguarded Tk calls error on headless source** — `toplevel`/`wm`/`ttk::notebook` are "invalid command name" in `-dispdev text` (Tk absent). | ALL GUI code (the `open_dialog` proc body, the `vmd_install_extension` call) reachable at source-time must be inside `if {[info exists tk_version]}` or inside a proc only called from the GUI-guarded path. Defining a proc that CONTAINS Tk commands is safe (not executed at define-time); CALLING it at top-level is what must be guarded. | `PITFALLS.md:464`; `STACK.md:21` |
| 4 | **`package require` without `pkgIndex.tcl`** — if the script called `package require biochemeleon` at top WITHOUT a prior `package provide`, it would fail (no pkgIndex on auto_path). | `package provide biochemeleon $ver` BEFORE `vmd_install_extension` (which does the `package require`). Then `package require biochemeleon` is a no-op (already provided). No pkgIndex needed for the sourced form. | `PITFALLS.md:404`; Tcl package semantics |
| 5 | **`grab set` on main panel blocks the 3D viewer** — click-to-find dies. | NEVER `grab set` on `.biochemeleon`. The skeleton has no `grab` anywhere. `grab set` only on brief transient children (none in Phase 13). | `PITFALLS.md:135-152`; `mergestructs.tcl:138` |
| 6 | **Dialog re-opens a second window on re-call** — without the singleton check, each `biochemeleon` call creates a new toplevel, leaking windows and fragmenting state. | `if {[winfo exists .biochemeleon]} { wm deiconify $w; return }` at the top of `open_dialog` (the 4-plugin singleton pattern). | `viewmaster.tcl:66-69` et al. |
| 7 | **`_tk_cb` doesn't return the widget path** — VMD can't track open/close. | `proc biochemeleon_tk_cb {} { ::biochemeleon::open_dialog; return $::biochemeleon::w }` — always return `$w`. | `PITFALLS.md:496`; `clonerep.tcl:237-240` |
| 8 | **Tcl 8.5 syntax traps** — `lmap`/`try` are 8.6+ parse errors; `variable`/`global` must be declared inside procs. | Use `foreach`+`lappend`, `catch` (no `try`), declare `variable w` / `variable state` inside each namespace proc that touches them. Braced `expr`. | `PITFALLS.md:374-392` |
| 9 | **Menu path double-nests** — `"Extensions/bioCHEMeleon"` creates Extensions → Extensions → bioCHEMeleon. | Use `"Visualization/bioCHEMeleon"` (category-prefixed, matching clonerep/viewmaster). | `loadplugins.tcl:213,231` |
| 10 | **Sourcing auto-opens the dialog** (if following `STACK.md:147` literally) — breaks headless sourcing, surprises `.vmdrc` users, contradicts the requirement. | Sourcing DEFINES the command + registers the menu; the `biochemeleon` command (or menu click) OPENS. No auto-open-on-source. | ENTRY-01; ROADMAP criterion 2 |

---

## Open Questions (flag for Phase 13 GUI human-verify checkpoint)

1. **[MEDIUM] Does the Extensions-menu item actually appear and open the dialog?** The `menu tk register` mechanics (loadplugins.tcl:119) can't be exercised headless (Tk absent). Phase 13's GUI smoke must confirm: source the script in a real VMD GUI → Extensions → Visualization → "bioCHEMeleon" exists → clicking it opens the `ttk::notebook` dialog with Setup + Game tabs. (This is the canonical "human-verify checkpoint" the milestone preserves from v1 — `SUMMARY.md:84`, `PITFALLS.md:528`.)
2. **[MEDIUM-HIGH] Does `ttk::notebook` render correctly in VMD 1.9.3's Tk?** The widget library is present (`scripts/tk8.5/ttk/`, `STACK.md:22`) but no bundled reference plugin uses `ttk::notebook` (they use classic `frame`/`menubutton`). First GUI smoke confirms the two tabs render and are selectable. If ttk somehow misbehaves, fallback is classic `frame` + `button`-driven tab switching (more code; not expected to be needed).
3. **[MEDIUM] Does the modeless dialog keep the 3D viewer interactive?** I.e. can the user rotate the molecule while `.biochemeleon` is open? This is the Pitfall-4 MEDIUM flag (`PITFALLS.md:152`, Open Question 1) — `grab set` blocking the OpenGL viewer couldn't be verified headless. Our design has NO `grab`, so this SHOULD pass; the GUI smoke confirms rotate-while-open works. Prevention is modeless regardless.
4. **[LOW] Menu path: `"Visualization/bioCHEMeleon"` vs bare `"bioCHEMeleon"`.** Recommend Visualization/ (matches peer plugins); GUI smoke confirms it lands in the expected submenu. Minor; both satisfy ENTRY-02's "bioCHEMeleon item in the VMD Extensions menu."
5. **[LOW] Does `vmd_install_extension` idempotently re-register on the (guarded-against) re-source?** The re-source guard stops re-entry before `vmd_install_extension` runs again, so this should never arise — but if the guard were ever bypassed, `menu tk register` with the same `winname` might warn. Not a Phase 13 concern (the guard prevents it); noted for completeness.

---

## Interface Boundary with the Testing / Pure-Layer Researcher

The entry script `vmd/biochemeleon.tcl` SOURCES the pure layer via `source [file join [file dirname [info script]] lib setup_state.tcl]`, and the pure layer is expected to expose a stdlib-only tcl namespace (`namespace eval ::biochemeleon::setup { ... }`) with NO `mol`/`atomselect`/`tk` dependency, so that `tclsh vmd/lib/setup_state.tcl` loads clean and `tcltest` can exercise it (ROADMAP criterion 4 — the OTHER researcher owns the pure-layer internals + `vmd/tests/test_setup_state.test` + `test_registry.test`). All GUI code in the entry (the `open_dialog` proc body, the `vmd_install_extension` call) is reachable only through `if {[info exists tk_version]}` guards or procs called from the GUI-guarded path, so the SAME `biochemeleon.tcl` runs headless AND in GUI mode — the OTHER researcher's headless smoke (`vmd -dispdev text -e <staged>/biochemeleon.tcl -eofexit`, run from a `/mnt/c` cwd with the script staged to a Windows-visible path per `STACK.md:217-225`) exercises the non-GUI half (source + `biochemeleon` console no-op + pure-layer load), while the GUI half is the human-verify checkpoint above. The entry-half smoke (`vmd/smoke/phase13_smoke.tcl`) asserts: source succeeds, `biochemeleon` command exists (`info commands biochemeleon` non-empty), calling `biochemeleon` headlessly returns cleanly with a `vmdcon -warn` (no crash), and `::biochemeleon::setup` namespace exists post-source. The OTHER researcher owns the smoke-harness invocation (`bash -ic "vmd -dispdev text -e ... -eofexit"` mechanics, exit-code checks, the `< /dev/null` stdin guard); this research owns what the smoke asserts about entry/dialog.

---

## Sources

### Primary (HIGH confidence — read directly)
- `vmd-ref/scripts/loadplugins.tcl:114-134,137-236` — `vmd_install_extension` definition + every bundled registration call (menu-path format, GUI-only guard).
- `vmd-ref/plugins/clonerep1.3/clonerep.tcl:16-27,159-234,237-240` — namespace + `package provide` + `clonerep_tk_cb` + singleton (destroy-recreate anti-pattern at 166-168) + `trace variable vmd_molecule`.
- `vmd-ref/plugins/viewmaster2.6/viewmaster.tcl:26-58,62-125,1087-1090` — `package provide` outside namespace + singleton `wm deiconify` re-show (66-69) + `viewmaster_tk_cb`.
- `vmd-ref/plugins/ramaplot1.1/ramaplot.tcl:13-27,109-145,663-666` — global `ramaplot` proc delegating to namespace + `ramaplot_tk` returning `$w` + singleton re-show (125-128).
- `vmd-ref/plugins/autoionize1.4/autoionize.tcl:14-50` — `package provide` + global `proc autoionize {args}` delegating to namespace (the dual-proc console-command pattern).
- `vmd-ref/plugins/autoionize1.4/autoionizegui.tcl:13-15,41-50,194` — `autoigui` callback + singleton re-show + `return $w`.
- `vmd-ref/plugins/mergestructs1.1/mergestructs.tcl:13-25,30-54,992-995` — `package provide` + singleton re-show + the ONE `grab set` (138, transient sub-dialog) + `mergestructs_tk`.
- `vmd-ref/plugins/*/pkgIndex.tcl` (all 5) — `package ifneeded` form.
- `pymol/biochemeleon/__init__.py:5,129-153` — v1 modeless analog (`dialog.show()` never `.exec_()`, module-level singleton).

### Secondary (HIGH — milestone research cross-reference)
- `.planning/research/STACK.md:19-31,41-42,68,79,107-148,211-227,255-276` — Tcl 8.5.6/Tk 8.5/ttk verified, sourced-script structure pattern, headless command, vmd_install_extension semantics, ttk MEDIUM-HIGH flag.
- `.planning/research/PITFALLS.md:135-152,374-431,464,495-496` — Pitfall 4 (grab), Pitfall 12 (Tcl 8.5), Pitfall 13 (re-source), GUI guard idiom, `_tk_cb` returns widget.
- `.planning/research/SUMMARY.md:40,76-84` — modeless requirement, v2 `vmd/` layout (lib/ + gui/ + tests/).
- `.planning/ROADMAP.md:42-56` — Phase 13 goal + success criteria.
- `.planning/REQUIREMENTS.md:14-16` — ENTRY-01/02/03.

### Tertiary (MEDIUM — flagged for GUI human-verify)
- `ttk::notebook` rendering in VMD 1.9.3 Tk — present in `scripts/tk8.5/ttk/` but unverifiable headless (Open Question 2).
- `grab set` fully blocking the OpenGL viewer — MEDIUM, needs GUI check (Open Question 3 / Pitfall 4 flag).

## Metadata

**Confidence breakdown:**
- Entry mechanism (`vmd_install_extension`, sourced-script → command, re-source guard): HIGH — read the VMD-install source + 5 reference plugins.
- Modeless dialog (toplevel + ttk::notebook, no grab, singleton, GUI guard): HIGH on the toplevel/singleton/grab patterns (4 plugins); MEDIUM-HIGH on `ttk::notebook` (standard Tk 8.5 but no in-repo example + unverifiable headless).
- File layout: HIGH — direct mirror of v1 + milestone decision.
- Pitfalls: HIGH (all cited to PITFALLS.md runtime-verified evidence or reference-plugin source).

**Research date:** 2026-08-27
**Valid until:** 2026-09-26 (stable — VMD 1.9.3 is from 2016, extension mechanism unchanged; re-verify ttk::notebook rendering after the first GUI smoke).
