# Phase 16 Research — The VMD 1.9.3 Atom-Pick Mechanism (PickBridge contract)

**Phase:** 16 — MVP Core Loop (Sphere). THE critical unknown of the phase (was flagged MEDIUM confidence, ⚠️ PICK MECHANISM HUMAN-VERIFY).
**Researched:** 2026-08-30
**Method:** 4 headless VMD 1.9.3 probes (`tmp/biochemeleon-vmd/probe_pick{,2,3,4}.tcl`) + UG PDF text extraction (`tmp/biochemeleon-vmd/ug_text.txt`, python3+zlib stream inflation — no pdftotext in WSL) + full read of every shipped script/plugin that touches picking.
**Headline:** The prior research docs were BOTH partially wrong. The verified truth: **trace `::vmd_pick_event` with a `{args}` proc and read globals `vmd_pick_atom` / `vmd_pick_mol`** (UG Table 9.4 + shipped `www.tcl` pattern), entering pick-atom mode via **`mouse mode pick 2`** — NOT `mouse mode 4 2` (that is *userpoint* mode in the 1.9.3 binary!) and NOT `mouse mode pick 0` (that is *query* mode). `::vmd_pick_atom_callbacks` is a **phantom** — not in the UG, not in any shipped script, not pre-created by VMD.

**Confidence:** HIGH for everything probe-verified (mouse-mode mapping, trace mechanics, label API, callbacks-list absence). MEDIUM for GUI-only behaviors that a real click must confirm (marked ⚠️ GUI-VERIFY below). LOW for write-order/edge inferences (marked).

---

## 1. Mechanism reconciliation — the four candidates

The conflict to resolve (from `.planning/research/STACK.md`, `ARCHITECTURE.md` Pattern 3, `PITFALLS.md` Pitfall 5, `SUMMARY.md`):

| Source | Claimed mechanism | Verdict after this research |
|---|---|---|
| STACK.md §Click-to-find | `mouse mode 4 2` + `trace add variable ::vmd_pick_event write <cb>`; read `vmd_pick_atom`/`vmd_pick_mol` | **Half right.** Trace+globals = CORRECT (UG-documented). **Mouse mode WRONG**: `4` = `userpoint`, not pick, in the 1.9.3 binary (probe4). |
| ARCHITECTURE.md Pattern 3 | `lappend ::vmd_pick_atom_callbacks <proc>` + `mouse mode pick 0`; read `vmd_pick_atom`/`vmd_pick_molecule`/`vmd_pick_state`/`vmd_pick_selection` | **Half right.** `mouse mode pick 0` = **query** mode, not atom (probe4 + hotkeys.tcl comments). The callbacks list is a **phantom** (see 1B). Global names `vmd_pick_molecule/state/selection` appear **nowhere** in the UG or shipped scripts. |
| PITFALLS.md Pitfall 5 | poll `label list Atoms`; `mouse callback on` gates pick callbacks | **Right as fallback.** Label API verified headless (probe1/2). `mouse callback on` gates the *hover* (silent) variables, not the click event (UG §9.3.23). |
| vmd/AGENTS.md | "register in `::vmd_pick_atom_callbacks` + `mouse mode pick 0`" | **Superseded by this document** — update AGENTS.md when the contract is GUI-locked. |

### 1A. Mechanism A — trace `::vmd_pick_event` (THE click mechanism) ✅ RECOMMENDED

**Exists? YES — UG-documented + shipped-script-proven.** HIGH confidence on the contract shape; MEDIUM on real-click firing (⚠️ GUI-VERIFY, can't fire a click headless).

- **UG Table 9.4** (Tcl callback variables, extracted from `vmd-ref/ug.pdf` §9.4, `ug_text.txt:17780-17800`):
  > *"An atom has been picked using the 'Pick' mouse mode → `vmd_pick_event`. When receiving this event, the following global variables are also set: `vmd_pick_atom` (id of picked atom), `vmd_pick_mol` (id of picked molecule)"*
  > *"Atom picked → `vmd_pick_shift_state`: 1 if shift key down during pick, 0 otherwise"*
- **UG §9.4 official example** (`ug_text.txt:17540-17770`) registers exactly:
  ```tcl
  proc mol_weight {args} {                       # NOTE: {args} — receives (name1 name2 op)
      global vmd_pick_atom vmd_pick_mol          # read globals INSIDE the callback
      set sel [atomselect $vmd_pick_mol "same residue as index $vmd_pick_atom"]
      # ...
  }
  trace add variable ::vmd_pick_event write mol_weight      # register
  trace remove variable ::vmd_pick_event write mol_weight   # unregister ("when you are done with it")
  ```
  The example uses `atomselect $vmd_pick_mol "index $vmd_pick_atom"` — proving **`vmd_pick_atom` is the 0-based atom INDEX** (the registry key we already use) and **`vmd_pick_mol` is the molid**.
- **Shipped-script proof** — `vmd-ref/scripts/www.tcl` (the ONLY shipped script using picking; VMD's own "hyperref" feature, lines 31-83):
  ```tcl
  trace variable vmd_pick_atom w vmd_hyperref_update        ;# OLD-STYLE trace on the atom global itself
  proc vmd_hyperref_update {args} {
      global vmd_pick_atom vmd_pick_mol                     ;# reads BOTH globals
      if {! [info exists vmd_hyperref_urls($vmd_pick_mol,$vmd_pick_atom)] } { return }
  ```
  www.tcl calls **no** `mouse callback on`, **no** `mouse mode` — a plain trace on the pick globals is sufficient machinery on VMD's side (⚠️ GUI-VERIFY: confirm no `mouse callback on` is needed in 1.9.3 GUI).
- **Probe evidence (trace mechanics, HIGH):** probe1 §7 — `trace add variable ::vmd_pick_event write on_event` registers clean headless; on a write, callback fires with **args = `<::vmd_pick_event {} write>`** (name1/name2/op — NOT molid/atom); globals readable inside. Old-style `trace variable vmd_pick_atom w` also works (www.tcl form).
- **Name correction:** it is `vmd_pick_mol`, **never** `vmd_pick_molecule` (grep of `ug_text.txt` + `vmd-ref/` = zero hits for the longer name). Defensive code may read both, but expect `vmd_pick_mol`.

**Pros:** UG-canonical; click-based (not hover); zero polling; traces natively coexist with any user traces (additive — no clobbering, unlike a list you'd overwrite); unregister is clean.
**Cons:** cannot be fired headless (GUI-verify); a traced variable can also be written by *other scripts* (spurious fires — filter in handler, see Pitfalls).
**Headless-testable:** registration + simulated fire + removal — yes (probe1/2/3). Real firing — no.

### 1B. Mechanism B — `::vmd_pick_atom_callbacks` list ❌ PHANTOM — do not rely on it

**Evidence it does not exist as a VMD feature (all HIGH):**
1. **Not in the UG.** `grep callbacks ug_text.txt` → §9.3.23 (`callback on/off` for the *silent* hover vars), §9.4 intro, §10.4 (Python callbacks) — no mention of any `vmd_pick_atom_callbacks` list. The UG states the dispatch mechanism plainly: *"When certain events occur, VMD notifies the Tcl interpreter **by setting certain Tcl variables**"* (§9.4 intro) — i.e., traces are THE Tcl callback interface.
2. **Not in any shipped script/plugin.** `rg vmd_pick` over `vmd-ref/scripts/` + `vmd-ref/plugins/` → only `www.tcl` (trace pattern). Zero hits for `*_callbacks`.
3. **Not pre-created by VMD.** probe1 §5: `info exists ::vmd_pick_atom_callbacks` → **0** at startup. VMD creates/updates `vmd_mouse_mode`, `vmd_frame`, `vmd_molecule`, etc. as real variables — it does not create this one.
4. The prior probe's "confirmation" (`lappend ::vmd_pick_atom_callbacks ::bcm_pick_cb` succeeds) is a **Tcl-truth, not a VMD-truth**: `lappend` auto-creates ANY variable name. This was the research trap — "I can write it" ≠ "VMD reads it".
5. Cannot prove a hard negative headlessly (VMD could theoretically read it only in GUI builds), but three independent negatives + a documented alternative mechanism = decisive for design. **Keep at most a no-op compat shim (one `catch {lappend ...}`); never gate correctness on it.** ⚠️ GUI-VERIFY step 7 will falsify it definitively (register a proc ONLY in the list, click, observe nothing fires).

### 1C. Mechanism C — `mouse callback on` + trace `vmd_pick_atom_silent` — exists, but it's HOVER, not click

**Exists? YES (UG-documented). Suitable as click mechanism? NO.**
- UG §9.3.23 (`ug_text.txt:16054-16058`): *"`callback on/off`: Turn the callbacks on or off. To use the callbacks, trace the variable `vmd_pick_atom_silent`."*
- UG Table 9.4: `vmd_pick_mol_silent` / `vmd_pick_atom_silent` — *"id of nearby mol/atom"* — set when **"Pointer moved"** (i.e., every mouse-move hover), NOT on click. (`vmd_pick_client` — name of VR pointer — also hover.)
- **Why not for the game:** a hover-based "find" would mark hiders the moment the cursor passes over them — destroys the click skill mechanic; and tracing every mouse-move is a per-frame Tcl callback (perf tax on 100k-atom scenes). Role in PickBridge: **none for MVP**; a future "hover highlight" polish feature could use it. `mouse callback on/off` itself is a no-op-able call (probe1 §4: both accepted silently headless).
- ⚠️ GUI-VERIFY note: confirm a real click does NOT depend on `mouse callback on` (expected: independent — www.tcl never enables it).

### 1D. Mechanism D — label-poll (`label list Atoms`) — ✅ verified fallback

**Exists? YES — fully headless-verified (HIGH).** In pick-atom mode, VMD's click **creates an atom label** (that is literally what "Pick Atom" mode does), so the new-label diff is a click detector.
- UG §9.3.13 `label`: categories `Atoms|Bonds|Angles|Dihedrals|Springs`; `list <category>`, `add <category> <molID>/<atomID> [...]`, `delete <category> <all|label number>`.
- probe1 §6 (quoted output): `label list` → `Atoms Bonds Angles Dihedrals Springs`; `label add Atoms 0/0` → *"Added new Atoms label UNK0:X"*; **`label list Atoms` → `{{0 0} 0.000000 show}`** — format `{{molid index} value showstate}`.
- probe2 §D: baseline-count → `label add Atoms 0/3` → count 0→1; newest entry = **last** list element; `lindex $entry 0` = `{molid index}` pair. `label delete Atoms 0` renumbers (delete-first leaves `{{0 2} ...}`); **`label delete Atoms all` works; `label delete Atoms end-0` FAILS** (`expected integer but got "end-0"` — no end-based indices); out-of-range `label add Atoms 0/99` → *"Unable to add label."* (catch it).
- **Use as fallback only:** polling needs an `after` timer (CPU tax), and the click-created label must be deleted or the viewer clutters with distance labels. It is the safety net if (and only if) GUI-VERIFY shows the event trace doesn't fire on real clicks.

### Reconciliation verdict

| | Exists in 1.9.3? | Fires on | Callback signature | Headless-testable | Verdict |
|---|---|---|---|---|---|
| **A. trace `vmd_pick_event`** | ✅ UG Table 9.4 + §9.4 + www.tcl | **click** (pick modes) | `{args}` (name1 name2 op); read `vmd_pick_atom`/`vmd_pick_mol`/`vmd_pick_shift_state` | register/sim/rem ✅; real fire ⚠️GUI | **PRIMARY** |
| B. `vmd_pick_atom_callbacks` | ❌ phantom (UG ✗, shipped scripts ✗, pre-created ✗) | unknown (likely never) | unknown | lappend ✅ (meaningless) | **compat shim only** |
| C. `mouse callback on` + trace `_silent` | ✅ UG §9.3.23 + Table 9.4 | **hover** (pointer moved) | `{args}`; read `vmd_pick_atom_silent`/`vmd_pick_mol_silent` | register ✅; fire ❌ (no mouse moves) | **NOT for clicks** (future hover polish) |
| D. label-poll | ✅ UG §9.3.13 + probes | click (via created label) | n/a (poll diff) | ✅ fully | **FALLBACK** |

---

## 2. Recommended PickBridge design

New module `vmd/lib/pick.tcl` (mol-bridge layer: calls `mouse`/`label`/`trace`; no Tk), sourced by the entry between `mutation.tcl` and `game.tcl`. Namespaces per repo convention; Tcl 8.5 only; braced `expr`; one-per-line `variable` declarations.

### 2.1 Mouse-mode facts to encode (all probe-verified, HIGH)

The **numeric forms are a minefield — never use them.** Runtime mapping (probe4, quoted):

```
mouse mode 0 0 -> rotate     mouse mode 4 0 -> userpoint    mouse mode 8 0 -> labelatom
mouse mode 1 0 -> translate  mouse mode 5 0 -> pick         (pick family:)
mouse mode 2 0 -> scale      mouse mode 6 0 -> query         pick 0 -> query      (UG/hotkeys: "query item")
mouse mode 3 0 -> light      mouse mode 7 0 -> center        pick 1 -> center
                                                             pick 2 -> labelatom  ("# atom" in hotkeys.tcl)
                                                             pick 3 -> labelbond  ... pick 5 -> labeldihedral
```

- The UG's "mode 4 N = picking mode N" (§9.3.23 AND the UG hotkey table) is **stale relative to the 1.9.3 binary** — `userpoint` was inserted at index 4, shifting the numeric space. STACK.md's `mouse mode 4 2` would silently put the player in **User Point** mode.
- **Pick-atom mode = `mouse mode pick 2`** (resolves to `labelatom` = VMD GUI "Mouse → Pick → Pick Atom", hotkey `1`). Clicking there creates an atom label AND (per UG Table 9.4, ⚠️GUI-VERIFY which submodes fire) the pick event.
- **Rotate mode = `mouse mode rotate`** (hotkey `r`). Pick and rotate are mutually exclusive — the in-panel toggle just switches between these two commands.
- **vmdinit.tcl:279-280**: `set vmd_mouse_mode rotate; set vmd_mouse_submode -1` — the fresh-session default state to expect in snapshots.
- Restore fidelity (probe2 §B, HIGH): snapshot → `mouse mode pick 2` → `mouse mode translate 3` restore → globals report `translate/3` exactly. Named resolved modes re-set cleanly (`mouse mode labelatom 2`, `rotate -1`, `query 0` all valid). **Restore using the snapshotted resolved values**: `mouse mode $saved_mode $saved_submode`.
- Quirk (probe1 §3): `mouse mode bogus 5` errors BUT still sets `vmd_mouse_submode` to 5 — mode-set is **not atomic**; on restore failure, force a fallback `mouse mode rotate`.

### 2.2 Reference contract (tcl 8.5, repo style)

```tcl
# vmd/lib/pick.tcl — PickBridge: click-to-find wiring (Phase 16).
# PRIMARY mechanism: trace ::vmd_pick_event (UG Table 9.4 / §9.4 / shipped www.tcl).
# FALLBACK: label-poll diff (label list Atoms) — selectable via ::BCM::pick::mechanism.
# DO NOT USE: ::vmd_pick_atom_callbacks (phantom — not a VMD 1.9.3 feature);
#             mouse mode 4 2 (userpoint!); mouse mode pick 0 (query!).
namespace eval ::biochemeleon::pick {
    variable active        0     ;# re-entrancy guard (double trace = double fire, probe3)
    variable mechanism     trace ;# trace | labelpoll — final value locked by GUI-verify
    variable saved_mode    {}    ;# user's mouse mode before Start
    variable saved_submode {}    ;# user's mouse submode before Start
    variable active_mol    {}    ;# game molid (PDB-rebuild CHANGED it — bind AFTER start_game)
    variable label_base    0     ;# label count at activate (clean up only OUR labels)
}

# activate {game_molid} — call AFTER start_game returns (game_molid is the NEW molid).
proc ::biochemeleon::pick::activate {game_molid} {
    variable active mechanism saved_mode saved_submode active_mol label_base
    if {$active} { return }                      ;# idempotent: duplicate trace fires TWICE (probe3)
    # 1. snapshot the user's mouse state BEFORE switching (vmdinit.tcl:279 defaults: rotate/-1)
    set saved_mode    $::vmd_mouse_mode
    set saved_submode $::vmd_mouse_submode
    # 2. baseline labels so deactivate cleans only what the game created
    set label_base [llength [label list Atoms]]
    set active_mol $game_molid
    # 3. engage pick-atom mode ("Pick Atom", hotkey 1). NOT 4 2 (userpoint), NOT pick 0 (query).
    mouse mode pick 2
    # 4. register per mechanism. trace remove BEFORE add (idempotency belt-and-suspenders).
    if {$mechanism eq "trace"} {
        catch {trace remove variable ::vmd_pick_event write ::biochemeleon::pick::_on_event}
        trace add variable ::vmd_pick_event write ::biochemeleon::pick::_on_event
    } else {
        ::biochemeleon::pick::_poll_once        ;# seeds baseline; re-armed via after-loop in gui layer
    }
    set active 1
}

# _on_event — trace callback. Signature MUST be {args}: receives (name1 name2 op).
# A wrong-signature proc (e.g. {molid atom}) makes the VARIABLE WRITE ITSELF FAIL
# ("can't set ::vmd_pick_event: wrong # args" — probe3) and the pick is LOST.
proc ::biochemeleon::pick::_on_event {args} {
    variable active active_mol
    if {!$active} { return }
    if {[catch {
        global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state
        if {![info exists vmd_pick_atom] || ![info exists vmd_pick_mol]} { return }
        if {$vmd_pick_mol ne $active_mol} { return }      ;# ignore picks on other molecules
        ::biochemeleon::game::on_pick $vmd_pick_atom      ;# forward index to controller (GAME-01 logs miss/hit)
        ::biochemeleon::pick::_clear_new_labels           ;# delete the click's label (clutter)
    } err]} {
        vmdcon -err "bioCHEMeleon pick handler: $err"     ;# NEVER propagate: an error in this proc
    }                                                      ;# BLOCKS VMD's variable write (probe3)
    return
}

# _clear_new_labels — remove labels created after the baseline (click-created; renumber-safe:
# delete from the END while above baseline; 'label delete Atoms all' nukes user labels — avoid).
proc ::biochemeleon::pick::_clear_new_labels {} {
    variable label_base
    while {[llength [label list Atoms]] > $label_base} {
        set n [llength [label list Atoms]]
        catch {label delete Atoms [expr {$n - 1}]}
    }
}

# set_view_mode {mode} — the in-panel Rotate/Pick toggle (BTN requirement). Game stays active.
proc ::biochemeleon::pick::set_view_mode {mode} {
    switch -- $mode {
        pick   { mouse mode pick 2 }
        rotate { mouse mode rotate }
        default { error "set_view_mode: pick or rotate" }
    }
}

# deactivate — call on win/cleanup/restart/dialog-destroy. ALWAYS restores the user's state.
proc ::biochemeleon::pick::deactivate {} {
    variable active mechanism saved_mode saved_submode label_base
    if {!$active} { return }
    catch {trace remove variable ::vmd_pick_event write ::biochemeleon::pick::_on_event}
    # clean only OUR labels (baseline-preserved); keep any user labels
    ::biochemeleon::pick::_clear_new_labels
    # restore the user's mouse mode; fallback to rotate on any failure (non-atomic mode-set quirk)
    if {[catch {mouse mode $saved_mode $saved_submode}]} {
        catch {mouse mode rotate}
    }
    set active 0
}
```

### 2.3 Found-marking and the "hidden reps cannot be picked" caveat

UG node140 (`ug_text.txt:15645`): *"showrep molecule number [on|off] — Get/set whether the given rep is shown or hidden. **Hidden reps cannot be picked** and do not show any graphics."*

Design consequences (HIGH on the rule, MEDIUM on GUI confirmation):
- **Hider reps must stay SHOWN while unfound** — never `mol showrep ... off` a rep containing unfound hiders (they become unpickable → unwinnable).
- **Mark found by recolor, not by hiding.** Recommended: give the sphere game rep `mol modcolor User` and mark a found hider by `$sel set user <colorid>` (e.g. a bright color) on that atom — the rep stays shown, unfound hiders and real atoms stay pickable, and the change is per-atom. Alternative: `mol modselect` the rep to `resname GAM and not (index <found>)` — shrinks the rep so found hiders disappear; safe (unfound remain in the rep) but visually "hider vanished" may read as "I was wrong". Pick ONE in planning; recolor-via-User is the recommendation for MVP (also preserves count-at-a-glance).
- Verify the found-hider visual in the GUI checkpoint (same session).

### 2.4 Pick-vs-rotate toggle integration

- VMD binds ONE mouse mode globally (unlike v1 PyMOL where pick coexisted with middle-drag rotate). Player UX: Start → game activates `pick 2`; player clicks to find; to rotate, either press **`r`** (shipped hotkey, `hotkeys.tcl:109`) or the panel toggle; toggle back with `0`-analog → our button calls `set_view_mode pick` (`mouse mode pick 2`). Document hotkeys `r` (rotate) and `1` (pick atom) in the info box.
- While in rotate mode, clicks don't pick (no event) — hiders can't be found while rotating; the toggle button state should show which mode is live.
- On deactivate (win/cleanup/restart), restore the snapshotted user mode — the player gets whatever they had before Start (rotate/-1 on a fresh session).

### 2.5 Lifecycle integration with Phase 15 game.tcl

- `start_game` (PDB-rebuild) **changes the molid** — `pick::activate $game_molid` must run AFTER `start_game` returns, using `dict get $game_state game_molid`. Never bind to the pre-rebuild molid.
- `restart` = cleanup+start: `deactivate` → cleanup (mol delete+reload) → `start_game` → `activate` with the NEW molid.
- `cleanup` / win / dialog destroy: `deactivate` FIRST (restores mouse + trace removed), then molecule ops. An active trace on a deleted molid is harmless (handler's `$vmd_pick_mol ne $active_mol` filter) but deactivate keeps state clean.

---

## 3. GUI human-verify checkpoint (LOCK THE CONTRACT)

Run in a REAL VMD GUI session (`vmd -e <script>` from Windows, or `bash -ic "vmd -e /mnt/c/.../pick_verify.tcl"`). Stage `vmd/tests/pick_verify.tcl` implementing steps 1-9 with `vmdcon -info` output; the human performs the clicks/keys and records answers into `.planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md`. **Estimated time: ~10 minutes.**

1. **Base session:** start GUI VMD, load a small demo (1k8p), `source vmd/biochemeleon.tcl`; run Start (sphere, 3 hiders). **Q: does the mouse switch to pick mode (GUI Mouse menu shows Pick → Pick Atom; clicking an atom creates a label)?** (Validates `mouse mode pick 2` in GUI — the numeric-form trap means this is NOT assumable from docs.)
2. **THE core test:** add the trace in the Tk console: `trace add variable ::vmd_pick_event write {apply {{args} {global vmd_pick_atom vmd_pick_mol vmd_pick_shift_state; vmdcon -info "PICK ev=$args atom=$vmd_pick_atom mol=$vmd_pick_mol shift=[info exists vmd_pick_shift_state]"}}}`. Click a hider. **Q: does the trace fire? What are the EXACT values** (`vmd_pick_atom` = 0-based index? `vmd_pick_mol` = game molid? shift present?). This single step locks Mechanism A.
3. **Submode test:** switch `mouse mode pick 0` (query), click an atom. **Q: does the event still fire?** (Decides whether query mode is usable/needs guarding.) Switch back `mouse mode pick 2`.
4. **`mouse callback` independence:** with `mouse callback off` (default), repeat step 2. **Q: still fires?** (If a click only fires with `callback on`, PickBridge must add `mouse callback on` at activate / `off` at deactivate.)
5. **Rotate exclusivity:** press `r` (rotate), click-drag then click an atom. **Q: no pick event, view rotates?** Toggle back via the panel (or `mouse mode pick 2`). **Q: clicking finds again?** (Validates the toggle + hotkey UX.)
6. **Label side-effects:** after a few finds, **Q: did labels accumulate on clicked atoms? Did the game's auto-delete keep the view clean?** Does a click-created label appear in `label list Atoms` (fallback viability proof)?
7. **Phantom falsification:** in the Tk console: `proc phantom_cb {args} { vmdcon -info "PHANTOM FIRED" }; catch {lappend ::vmd_pick_atom_callbacks phantom_cb}`. Click atoms. **Q: does PHANTOM FIRED ever appear?** (Expected: never → confirms 1B; the compat shim stays a no-op.)
8. **Hidden-rep caveat (UG node140):** `mol showrep <game_molid> <hider_rep_idx> off` on a rep containing an unfound hider; click where it was. **Q: no event/no find?** Turn it back on; click; find works? (Confirms the found-marking rule from §2.3.)
9. **Found-marking visual:** find all hiders. **Q: found markers (User-color recolor) visible + remaining counter hits 0 + win box + timer stops? After Cleanup, is the user's mouse mode restored (was rotate) and are labels clean?**

**After the lock — keep vs delete:**
- If step 2 fires (expected): KEEP the trace mechanism as primary; KEEP the label-poll code as `mechanism labelpoll` (dormant, ~20 lines — cheap insurance for other users' VMD builds); DELETE any args-parsing branches that assume VMD passes `(molid atom)` positionally; DELETE `vmd_pick_molecule`/`vmd_pick_state`/`vmd_pick_selection` reads; keep the `vmd_pick_mol`-with-`vmd_pick_molecule`-fallback only if step 2 shows a different name.
- If step 2 does NOT fire but step 6 shows labels: flip `mechanism` default to `labelpoll` + `after`-poll loop; delete the trace path.
- If step 4 shows `mouse callback on` is required: add it to activate/deactivate (with save/restore of nothing — it's stateless on/off).
- Update `vmd/AGENTS.md` §Picking with the locked contract (remove MEDIUM flag).

---

## 4. Headless-testable subset (automated, no GUI)

Verified safe to smoke-test headlessly (all probe-proven HIGH) — include as `vmd/smoke/` checks or a Phase 16 tcltest/smoke section:

1. **Mouse-mode round-trip** (probe2 §B): snapshot `vmd_mouse_mode`/`vmd_mouse_submode` → `mouse mode pick 2` → assert globals = `labelatom`/`2` → restore → assert equals snapshot. Also default-state restore (`rotate`/`-1`).
2. **Wrong-mode guard**: assert `mouse mode 4 2` yields `userpoint` (documents the trap) — or simply assert our code contains no `mouse mode 4`.
3. **Trace register/simulate/remove** (probe1 §7 + game_api_smoke.tcl §4 pattern): register `_on_event` → `set ::vmd_pick_atom 3; set ::vmd_pick_mol $m; set ::vmd_pick_event 1` → assert the controller received index 3 → `trace remove` → simulate again → assert no double-processing. **This validates the tcl mechanics ONLY — never claim it validates VMD's C-side firing (that is GUI-VERIFY's job).**
4. **Signature safety** (probe3 §B): assert `_on_event` is declared `{args}` (grep) — a `{molid atom}` signature makes the traced WRITE fail.
5. **Idempotent activate** (probe3 §A): call `activate` twice → simulate one pick → assert exactly ONE `on_pick` delivery.
6. **Label API** (probe1/2): `label add Atoms $m/0` → `label list Atoms` format `{{molid index} value show}` → `_clear_new_labels` returns count to baseline → `label delete Atoms all` on empty doesn't error.
7. **Phantom absence**: assert `info exists ::vmd_pick_atom_callbacks` == 0 in a fresh VMD (if a user's `.vmdrc` created it, log-and-continue, don't depend on it).
8. **Pick filter**: simulate `vmd_pick_mol` = a different molid → assert `game::on_pick` NOT called.

---

## 5. Pitfalls (silent-failure catalog)

1. **Wrong trace signature BLOCKS the pick event itself** — HIGH (probe3 §B). A proc declared `{molid atom}` errors with `can't set "::vmd_pick_event": wrong # args` **during VMD's own variable write** — the event is lost, possibly with console spam per click. Prevention: `{args}` signature + `catch` around the entire handler body; smoke-test #4 greps the signature.
2. **Duplicate trace = every click processed twice** — HIGH (probe3 §A: two identical registrations fired twice for one write; Tcl does NOT dedupe). Re-sourcing the script then re-activating would double-count finds/timer weirdness. Prevention: `active` flag + `trace remove` before `trace add`.
3. **`mouse mode 4 2` is User Point mode** — HIGH (probe4). The UG (§9.3.23 and the hotkey table) still says "4 N = picking" — stale vs the binary. A player in userpoint mode clicks nothing into the registry; the game looks dead with zero errors. Prevention: only `mouse mode pick 2`; smoke grep for `mouse mode 4`.
4. **`mouse mode pick 0` is Query, not atom-pick** — HIGH (probe4 + hotkeys.tcl comments). Query may or may not fire the pick event (⚠️GUI-VERIFY step 3) and does NOT create labels (fallback dead). Prevention: `pick 2`.
5. **`vmd_pick_atom_callbacks` phantom** — HIGH (1B). Any logic that waits for a callbacks-list invocation never runs. Prevention: shim only; GUI-VERIFY step 7 falsifies.
6. **Non-atomic mouse-mode set** — HIGH (probe1 §3: `mouse mode bogus 5` errored but still set submode 5). A failed restore can leave a hybrid state. Prevention: catch restore → fallback `mouse mode rotate`.
7. **Hidden reps cannot be picked** — MEDIUM (UG node140 text; real-click confirm in step 8). Hiding a rep with `showrep off` makes its atoms unpickable — found-marking must never hide a rep containing unfound hiders (§2.3).
8. **Spurious event fires** — MEDIUM (inference): `vmd_pick_event` is an ordinary tcl variable — ANY script writing it fires our trace (our own sim does; a user's `.vmdrc` script could too; a second bioCHEMeleon instance would). Prevention: handler validates `vmd_pick_mol == active_mol` and `vmd_pick_atom` is a valid index (< `molinfo $m get numatoms`) before acting; active-flag gate.
9. **User's own pick traces coexist** — LOW risk, by design: traces are additive; www.tcl's hyperref (if the user enabled Alt-h) and ours both fire — no clobbering (this is a reason to prefer traces over the list-clobbering Pattern-3 save/restore of `vmd_pick_atom_callbacks`).
10. **Click-created label clutter** — HIGH (mechanism fact): every click in labelatom mode adds a label (visible distance label "UNK0:X"). Prevention: `_clear_new_labels` after each processed pick + baseline-guarded cleanup on deactivate; never `label delete Atoms all` blindly (nukes user labels); `label delete` renumbers — delete from the END only (probe2 §D; `end-0` syntax unsupported).
11. **Globals named wrong** — HIGH (UG grep): `vmd_pick_mol` (not `vmd_pick_molecule`); `vmd_pick_state`/`vmd_pick_selection`/`vmd_pick_atominfo` do not exist in the UG or any shipped script (ARCHITECTURE.md Pattern 3 invented them). Reading non-existent globals inside the handler → handler error → pitfall 1 cascade. Prevention: `info exists` guards.
12. **Picks on other molecules** — the session may hold multiple molecules; `vmd_pick_mol ne $game_molid` picks must be ignored (registry is keyed by index *within* the game molid — a same-index hit on another molecule would corrupt found-state). Prevention: molid filter in `_on_event` (probe testable, #8).
13. **Trace left registered after abnormal exit** — if the dialog is destroyed without deactivate (VMD window close, error path), the trace survives, `vmd_mouse_mode` stays pick. Prevention: deactivate in every exit path incl. `wm protocol WM_DELETE_WINDOW`; the `vmd_quit` trace (UG Table 9.4) is available for belt-and-suspenders later.

---

## Sources

**Probe-verified (HIGH)** — `tmp/biochemeleon-vmd/probe_pick.tcl`, `probe_pick2.tcl`, `probe_pick3.tcl`, `probe_pick4.tcl` (reproducible: `bash -ic "cd tmp/biochemeleon-vmd && vmd -dispdev text -e probe_pick<N>.tcl -eofexit < /dev/null"`):
- Numeric+named mouse-mode space mapping; family resolution (`pick N` → query/center/labelatom/...); `4` = userpoint; restore round-trip incl. defaults; non-atomic mode-set quirk; `mouse callback on/off` accepted; `vmd_pick_atom_callbacks` not pre-created; `label` category list/add/list-format/delete/renumber/`all`/range-error; trace `{args}` signature `(name1 name2 op)`; dup-trace double-fire; wrong-signature blocks the write; remove-unregistered OK.

**Official docs (HIGH for API facts; MEDIUM for GUI-only behaviors)** — `vmd-ref/ug.pdf` → extracted text `tmp/biochemeleon-vmd/ug_text.txt`:
- §9.3.23 `mouse` (line ~16000): mode table; `callback on/off` → trace `vmd_pick_atom_silent`.
- §9.4 Tcl callbacks (line ~17521): "VMD notifies ... by setting certain Tcl variables"; official `mol_weight` example: `trace add variable ::vmd_pick_event write ...`, globals `vmd_pick_atom` (index) / `vmd_pick_mol`; explicit remove-when-done guidance.
- Table 9.4 (line ~17780): full callback-variable table (pick_event/atom/mol/shift_state; silent hover vars; vmd_frame/molecule/initialize_structure/quit).
- node140 `showrep` (line ~15645): "Hidden reps cannot be picked and do not show any graphics."
- §9.3.13 `label` (line ~12894): categories, add/list/delete syntax.

**Shipped scripts (HIGH)** — `vmd-ref/scripts/www.tcl` (the only shipped pick consumer: old-style trace `vmd_pick_atom w`, reads `vmd_pick_mol`, no `mouse callback on`); `hotkeys.tcl:109-140` (`r`=rotate, `p`=pick, `0`=pick 0 "# query", `1`=pick 2 "# atom", ...); `vmdinit.tcl:279-280` (`vmd_mouse_mode rotate` / `vmd_mouse_submode -1` defaults).

**Prior research reconciled** — `.planning/research/{STACK,ARCHITECTURE,PITFALLS,SUMMARY}.md` (conflict source and verdicts in §1 table).

**Metadata:** Research date 2026-08-30. Stable domain (VMD 1.9.3 is frozen 2016) — findings valid until the target VMD install changes. Post-GUI-lock, fold verified values into `vmd/AGENTS.md` and the phase VERIFICATION doc.
