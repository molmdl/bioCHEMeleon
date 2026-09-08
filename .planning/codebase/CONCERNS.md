# Codebase Concerns

**Analysis Date:** 2026-09-08

**Project state context:** v1 (`pymol/`) is SHIPPED and FROZEN (tag `v1`; last code change 2026-08-22, docs-only 2026-08-28) — its archived concern history lives in `milestones/v1-*` and the phase summaries under `.planning/phases/01..11*/`. v2 (`vmd/`, VMD 1.9.3 / Tcl 8.5.6) is ACTIVE at Phase 17.2 of 23: 12/12 plans BUILT, PHASE HEADLESS-GREEN (205/205 tcltest suites, 29/31 smokes, 0 ERROR/bad-switch in all 44 gate logs — `17.2-11-SUMMARY.md`), with ONE GUI human-verify checkpoint PENDING (`17.2-12-SUMMARY.md`, rep_verify.tcl round-3 cartoon session). This file reflects the CURRENT v2 state; each item carries a status: **open** (action needed or explicitly scheduled), **known-behavior** (locked/documented, mechanism deliberately untouched), or **resolved-but-recorded** (fixed; recorded as a fragility lesson).

---

## Tech Debt

**Byte-frozen `make_bonded_hiders` has an unparenthesized `within` pattern — occupied list silently empty:**
- Issue: `vmd/lib/mutation.tcl:171` uses `within 3.0 of index $aid and not index $aid`. VMD parses trailing expressions INTO the `within` reference (`within D of X and not Y` == `within D of (X and not Y)` == within-of-empty), so the per-anchor occupied-neighborhood list is ALWAYS empty. Placement rejection still works probabilistically via the generator side and the `occupied_hiders` arg (positions from prior tiers, sep 4.0), so all 17.1 smokes stay green — the defect is silent.
- Files: `vmd/lib/mutation.tcl:171` (the query), `vmd/lib/mutation.tcl:126-135` (comment claims the C-side neighborhood works).
- Impact: bonded-tier hiders can land closer to real atoms than MIN_SEP_REAL intends on crowded anchors; blend-quality degradation only, never a crash.
- Status: **open** (hygiene) — deliberately NOT touched under the byte-identical mandate (`17.2-04-SUMMARY.md` Issues; STATE 17.2-04 decision). Fix approach: parenthesize `(within 3.0 of index $aid) and not index $aid` in a dedicated hygiene pass that also re-pins `phase17_bonded_smoke` (byte-identity gates must be lifted in the same commit).

**Rear-junction displacement sign flip lives in the bridge, not the pure layer:**
- Issue: `splice::displacement` (`vmd/lib/splice.tcl:140-155`) is perpendicular to the FORWARD peptide bond only; its projection on the REAR bond (prev C → anchor N) can stretch that junction past the 1.95 Å C–N cutoff at d = 1.0 Å. The fix (flip the sign when the rear projection is positive) lives in `make_residue_hiders` (`vmd/lib/mutation.tcl`, the bridge), leaving `splice::displacement` returning the raw, rear-unsafe vector.
- Files: `vmd/lib/mutation.tcl` (`make_residue_hiders` rear-sign flip), `vmd/lib/splice.tcl:140` (raw contract), `vmd/tests/test_splice.test` (pins the raw contract).
- Impact: any future caller of `splice::displacement` directly gets rear-unsafe geometry; the pure layer's test-pinned contract does not encode the hazard.
- Status: **open** (documented follow-up) — 17.2-04 explicitly deferred promotion to splice.tcl (would need 17.2-01 test updates). Recorded in `17.2-04-SUMMARY.md` Next-Phase-Readiness.

**Production GUI path does NOT collapse multi-frame molecules (frame-raciness caller contract):**
- Issue: `vmd/data/demos/1znf.pdb` ships 37 MODEL records (multi-frame). `vmd/lib/game.tcl` has NO collapse step — the "callers MUST pass single-frame molecules" contract (17.2-04) is enforced only in smokes via `_load_demo_1f` (`vmd/smoke/phase17_splice_smoke.tcl:188-197`). The PENDING 17.2-12 GUI checkpoint round 3 loads 1znf directly through `demos::load_demo` (`vmd/tests/rep_verify.tcl:379`) — un-collapsed.
- Files: `vmd/lib/mutation.tcl:245,281,351` (`$sel frame 0` pins — reads ARE deterministic), `vmd/lib/mutation.tcl` `write_combined_pdb` (writepdb deliberately UNPINNED — the interim write-pin was REVERTED in `c54d77c` because it regressed the byte-frozen bonded tier).
- Impact: generator READS are frame-0 pinned (safe), but `write_combined_pdb`'s writepdb writes whatever frame is CURRENT. Frame drift was observed under probe conditions (frame 1→3→5; `molinfo set frame` does NOT pin). If the current frame is non-0 at write time, real atoms land on a foreign frame while fake residue records carry frame-0 coords → broken junctions. After a fresh `mol new` the current frame is 0, so the common path works — the hazard is drift-inducing intervening frame operations.
- Status: **open** (caller contract only) — engine-side collapse (or a frame-0-pinned write scoped to non-frozen callers) is the structural fix candidate. Watch the 17.2-12 checkpoint log for junction anomalies.

**Two pre-existing draw-dependent smoke reds (the 29/31 gate):**
- Issue 1: `vmd/smoke/phase17_dispatch_smoke.tcl` step 8 — the bare 2-arg randomize on 1k8p (DNA) can draw a residue tier; `make_residue_hiders` errors "no protein anchors" → the supply-0 degrade (`vmd/lib/game.tcl:262-265`) drops the tier, generating 0 (or 1) hiders vs the smoke's pinned 5. 3/3 draws red in the 17.2-11 gate session.
- Issue 2: `vmd/smoke/phase17_licorice_smoke.tcl:162-172` — pins P radius 1.55 (VMD's actual element table: **1.80**, Bondi vdW) and P color {0.5 0.5 0.31} (actual render: **{0.5 0.5 0.2}**); a 1k8p backbone-P anchor draw trips both (2/3 red). The smoke's own comment (lines 164-168) anticipated the re-pin.
- Files: `vmd/smoke/phase17_dispatch_smoke.tcl:335-378`, `vmd/smoke/phase17_licorice_smoke.tcl:162-172`, `vmd/smoke/phase17_points_smoke.tcl` (carries the same inert old P values — never exercised because 1znf has no P atoms).
- Impact: the full-suite gate can never be 31/31 green until fixed; engine behavior is CORRECT in both cases (smoke-side assertions only).
- Status: **open** (gap-closure candidates with recorded recipes — `17.2-11-SUMMARY.md` Issues; do NOT re-diagnose from scratch): dispatch step-8 → drop-ungeneratable-tiers + effective-total-recompute policy + draw-adaptive rewrite; licorice → re-pin per the 17.1-11 corrections (P 1.80, tan {0.5 0.5 0.2}); points smoke → apply the same corrections proactively if its demo ever changes.

**`rep_verify.tcl` driver cosmetics (test-only, non-blocking):**
- Issue: `pv_report` printed finds=0 (the `::pv_finds` counter at `vmd/tests/rep_verify.tcl:109-111,495-503` did not reflect session finds in the 17.1-14 session), and the round-2 dump echoed the INPUT per_rep instead of the DERIVED one.
- Files: `vmd/tests/rep_verify.tcl`.
- Impact: none on the game; registry lines in the log are authoritative. Status: **known-behavior** (recorded non-blocking, `17.1-14` STATE entry; fix opportunistically before the next GUI session).

**tcltest suites lack an explicit `exit` (console hang past stdin EOF):**
- Issue: the `.test` suites end after tcltest reporting; under `vmd -e ... -eofexit < /dev/null` VMD enters its text console and hangs over the WSL→Windows pipe (first 17.2-11 suite run COMPLETED 47/47 in-log, then timed out).
- Files: `vmd/tests/*.test` (6 suites); working wrapper is staging-only `tmp/cap172-gate/suite_driver.tcl` (source suite by name, then `exit`) — NOT in the repo.
- Impact: every future full-suite gate must re-create the wrapper or the gate stalls. Status: **open** (cheap fix: add an explicit exit path or commit the driver pattern into `vmd/tests/`).

**Setup-tab Reset clears setup fields only — hiders remain:**
- Issue: `do_reset` (`vmd/gui/setup_tab.tcl`) applies DEFAULTS to the form; an active round's hiders stay in the scene — expectation mismatch observed at 16-12.
- Files: `vmd/gui/setup_tab.tcl` (do_reset).
- Status: **open** (registered for gap closure; natural home is Phase 19 in-game actions).

**Game tab has no Cleanup/Restart buttons (console-only cleanup):**
- Issue: cleanup/restart require pasting `pv_cleanup`/console calls until Phase 19 lands the buttons. Hiders also remain visible after a win (MVP design).
- Files: `vmd/gui/game_tab.tcl`, `vmd/lib/game.tcl` (`cleanup`/`restart` exist lib-side, unexposed).
- Status: **open** (Phase 19 scope by design — ROADMAP Phase 19 `GAME-05..10`, `BTN-06`).

---

## Known Bugs

**First-click pick quirk (p-press arming) — LOCKED known behavior:**
- Symptoms: clicks before one keyboard `p` press land in labelatom mode (labels ARE added; the in-game count never changes). One `p` press per round arms delivery for the whole round; pasted `mouse mode pick|pick 0|pick 2` never arms; a fresh VMD restart also clears it. Panel checkbox desyncs from hotkey `r` (pick_bridge does not observe hotkey-driven mode changes).
- Files: `vmd/lib/pick_bridge.tcl` (dated FIRST-CLICK QUIRK header comment; mechanism byte-untouched per 16-17 branch c2), `vmd/AGENTS.md` (FIRST-CLICK QUIRK block), `vmd/gui/game_tab.tcl` (checkbox desync), `vmd/tests/rep_verify.tcl` (pv_instructions leads with "press p ONCE").
- Trigger: start a round and click before pressing `p` on the VMD display.
- Workaround: documented player guidance (press `p` or `1` once; Phase 22 will put it in-game help). Root cause pinned: arming is dispatch-path-bound (VMD `user add key` hotkey vs pasted text), NOT submode-bound; `pick 2` == labelatom/2 probe-verified; VMD 1.9.3 has NO mode-query form. Status: **known-behavior** (LOCKED contract; do NOT "fix" the mechanism).

**Restored-original-intercepts-picks (Phase 19 candidate fix):**
- Symptoms: after the active-game guard's cleanup, the restored original stays loaded AND visible; in the 17.1-14 GUI session round 2 logged 6 picks on the restored original (mol=3) before the user hid it manually. Related: restored originals ACCUMULATE in the loaded-objects dropdown (each cleanup `mol new`s a fresh original), and multi-round sessions leave overlapping leftover molecules (17.2-12 checkpoint step 5 explicitly tells the user to hide them).
- Files: `vmd/lib/backup.tcl` (`restore` — `mol new` per cleanup), `vmd/lib/game.tcl` (16-13 active-game guard cleanup path), `vmd/gui/dialog.tcl` (on_start guard wiring).
- Trigger: Start a new round while one is active; the restored original sits in the scene.
- Workaround: hide it manually in VMD Main.
- Status: **open** (Phase 19 candidate: hide/deselect the restored original after guard cleanup; possibly reuse/delete the restored copy).
- Double-Start guard exists and is GUI-confirmed (16-16: never 561 atoms/Segments 3 again) — the stacking defect itself is **resolved-but-recorded**. Close-on-mid-round deliberately leaves the stash alive (consumed by the guard on next Start; cleanup-on-close is Phase 19 scope) — **known-behavior**.

**One observed GUI FREEZE (attribution unknown):**
- Symptoms: the 16-16 DRIVER session froze ("clashed") right after the post-win guard restart; log ends with no `Exiting normally`. The clean control session ran the IDENTICAL guard flow repeatedly with zero freezes and exited normally.
- Files: observation recorded in `.planning/phases/16-mvp-core-loop-sphere/16-VERIFICATION.md` §7; candidate suspects (pv_observe per-fire errors vs VMD 1.9.3 flakiness) explicitly UNCONFIRMED.
- Trigger: not reproducible on demand (1 occurrence in 2 sessions, 2026-09-03).
- Workaround: none known.
- Status: **open** (unattributed single observation — watch every future GUI session; if it recurs, capture the last log lines before declaring VMD flakiness).

**pv_report counter bug (finds=0 print):**
- See Tech Debt driver cosmetics above. Status: **known-behavior** (non-blocking).

**Chain-value selector quoting (v1 lesson, carried into v2 by design):**
- The v1 Phase 11 blank-chain selector bug (unquoted `chain ''` matched every object; FIXED `0702563`) is structurally avoided in v2: `make_residue_hiders` REJECTS blank-chain anchors outright (`vmd/lib/mutation.tcl:272-275` — a blank-chain fake would mis-fragment) and simple hiders use hard-coded chain G (`HID_CHAIN`). Status: **resolved-but-recorded** — rule for any new v2 selector that interpolates a chain id: quote or reject blanks.

---

## Security Considerations

**Shared fixed temp filename under `$env(TEMP)`:**
- Risk: `mutate` writes the combined PDB to a FIXED path — `$::env(TEMP)/biochemeleon_game.pdb` (`vmd/lib/mutation.tcl:610-614`; fallback `[pwd]/biochemeleon_game.pdb`). Two concurrent VMD instances clobber each other's file (write → mol delete original → mol new: a racing instance can load a half-written or wrong-round PDB). This is WHY the full-suite gate is sequential-only (see Performance). The smoke collapse loader also writes `splice_load_collapse.pdb` into `[pwd]` (`vmd/smoke/phase17_splice_smoke.tcl:190`).
- Files: `vmd/lib/mutation.tcl:609-617`.
- Current mitigation: documented sequential-only protocol (`17.1-13`/`17.2-11` gate notes; STATE carry-forward (t)).
- Recommendations: for production (a user running one VMD) the fixed name is fine; if parallel testing is ever wanted, derive the filename from the molid or PID. A predictable temp path is a low concern for a local desktop tool (no multi-user exposure).

**fetch_pdb is a stub and VMD 1.9.3 has NO TLS:**
- Risk: Phase 21 must implement real PDB fetch over `http` (VMD 1.9.3's http pkg lacks tls) — plaintext download of demo structures; RCSB redirects to HTTPS. A downgrade/cleartext concern, plus the v1 lesson that SSL workarounds (`check_hostname=False`) are recorded debt.
- Files: `vmd/lib/demos.tcl:102` (stub comment), root `AGENTS.md` (v1 Phase 9 SSL fallback debt note in STATE v1 reference).
- Status: **open** (Phase 21 design decision: bundled-only fallback vs plaintext http vs external downloader).

**Attribution / citation verification (spec constraint, standing gate):**
- Risk: any new demo PDB without a human-verified DOI + license violates `spec.md` ("Do NOT make up anything").
- Files: `vmd/data/demos/SOURCES.md` (reused from v1: RCSB CC0, MemProtMD CC-BY 4.0, SASBDB free-with-attribution), `pymol/biochemeleon/data/demos/SOURCES.md`.
- Status: **open** (standing process gate for Phases 21+).

**Unbraced `expr` (injection + perf) — gated by convention, not automation:**
- `vmd/AGENTS.md` Tcl 8.5 gotchas mandate `[expr {$a + $b}]`; the 8.6-idiom grep gate does NOT check expr bracing. All reviewed lib code braces exprs (`vmd/lib/splice.tcl`, `vmd/lib/generators.tcl` verified). Status: **open** (latent; a future hygiene gate could grep for unbraced expr in `vmd/lib/`).

---

## Performance Bottlenecks

**Full-suite gate is sequential-only (shared `$env(TEMP)` combined-PDB):**
- Problem: parallel VMD smoke runs race on the fixed temp file (see Security above); a full gate is 44 sequential runs.
- Files: `vmd/lib/mutation.tcl:610-614` (cause), `.planning/phases/17.1-*/17.1-13-SUMMARY.md` + `17.2-11-SUMMARY.md` (gate protocol records).
- Cause: fixed temp filename + VMD's ~2 min startup per run (`timeout >= 330 s` per run is the standing rule).
- Improvement path: per-process temp filename (molid/PID-derived) would unlock parallel gates and cut phase-gate wall time roughly by the core count. Status: **open** (measured: 17.2-11 gate ≈ 45 min; 17.2-10 ≈ 75 min for 13 runs).

**Tachyon render probes render whole scenes per check:**
- Problem: the render-diff harness (`_render_bits` in `vmd/smoke/phase17_splice_smoke.tcl`, copied through the 17.2-05..08 tier smokes) empties every other rep via `mol modselect` + renders + restores, several times per smoke — each render is a full Tachyon export over the whole scene.
- Files: `vmd/smoke/phase17_splice_smoke.tcl` (harness origin), all `vmd/smoke/phase17_*_smoke.tcl` copies.
- Cause: `mol showrep off` is IGNORED in text mode (probe F6) — modselect-emptying is the only text-mode isolation.
- Improvement path: none needed for correctness; keep probe reps LAST (highest index, no renumber) and prefer scene-diff over extra renders when adding checks. Also carry the pinned lesson: Tachyon export RADII ARE SCENE-SCALE-DEPENDENT — pin classes (uniformity + magnitude band), never absolute values across scenes (`vmd/smoke/phase17_dynbonds_smoke.tcl` 17.1-12 correction). Status: **known-behavior** (accepted harness cost).

**Large molecules untested in v2 (1GZM/3GP6 class):**
- Problem: v2 demos are ≤ ~558 atoms; the 100k+-atom fetch demos (1GZM/3GP6, cached at `cache/*.pdb.gz`) are a Phase 21 concern. `vmd/AGENTS.md` performance rules exist (never `$all_sel get {x y z}`; never block the event loop > 200 ms — Tcl is single-threaded, use `after 0` chunking) but are UNPROVEN at scale in v2.
- Files: `vmd/lib/generators.tcl` + `vmd/lib/mutation.tcl` (per-candidate atomselect loops — O(hiders × atoms) selections in `make_residue_hiders`' per-residue N/CA/C/O/CB probe, `vmd/lib/mutation.tcl:279-291`), `cache/` (fetched 1GZM/3GP6/SASDPG4).
- Improvement path: probe `make_residue_hiders` + `write_combined_pdb` on 1GZM before Phase 21 promises the < 30 s budget; the per-candidate 5-selection loop is the first thing to batch. Status: **open** (untested at scale).

---

## Fragile Areas

**Byte-frozen files and diff-verified smoke templates:**
- Files: `vmd/lib/mutation.tcl` (simple-tier procs byte-identical mandates: `make_placeholder_hiders`/`make_bonded_hiders`/`_hider_record`/`tag_sentinels`/`fetch_hider_indices`), `vmd/lib/game.tcl` (16-13 guard byte-identical), the 17.2-05..08 tier smokes (single-file template copies, "only tier swap" diff-verified pre-run).
- Why fragile: byte-identity is an ACTIVE verification gate (`git diff <range> -- vmd/lib/` must be empty in several plan scopes); a "harmless" comment or reorder edit can break a gate or silently change a PRNG call sequence (see next item). The unparenthesized `within` defect (Tech Debt) survives BECAUSE of this mandate.
- Safe modification: byte-frozen regions change only in a dedicated plan that owns re-pinning every dependent smoke in the same commit; template copies are regenerated from the template file, never hand-edited divergently.

**PRNG-stream coupling across the generation flow:**
- Files: `vmd/lib/generators.tcl` (seedless placement draws), `vmd/lib/splice.tcl:184` (`select_anchors` — global PRNG stream, no seed), `vmd/lib/setup_state.tcl` (`randomize_per_rep`), `vmd/lib/game.tcl` (tier loop calls generators in GAME_REPS order).
- Why fragile: ALL generators draw from the GLOBAL PRNG with no seeds; smoke pinned numbers (atom counts, index sets, layout) hold only for identical call sequences in a fresh VMD process, and the Tcl 8.5.6 PRNG is stable per-build, NOT portable. Inserting ONE new generator call into the dispatch changes every downstream draw — pinned smoke expectations flip from green to red with zero engine changes.
- Safe modification: new smoke assertions are draw-adaptive (observed-layout invariants; strict pins only as the full-generation special case — the established 17.2-10/17.2-11 pattern). Never add a PRNG-consuming call to the game flow without re-running the capstone.

**Ordering contracts in the dispatch composition root (`vmd/lib/game.tcl`):**
- Why fragile: four load-bearing orderings, each comment-pinned with a failure mode: (1) `stamp_tier_codes` BEFORE `add_hider_reps` — a static single-frame molecule never re-evaluates cached rep selections on an atom-field change, so reps added before the user3 stamp cache empty selections forever (`vmd/lib/hiders.tcl`, game.tcl step 8); (2) `reconstruct_from_sentinels` ONCE then `assign_reps` — a second reconstruct CLEARS prior tiers (P8); (3) the file-layout slicing walk (17.2-09) depends on `write_combined_pdb` emitting simple records FIRST and one fetch index per residue hider (its CA) — reordering record emission mis-slices every tier; (4) `registry.tcl` is sourced EXACTLY ONCE (re-sourcing wipes `_records`; `namespace eval` re-runs on every source).
- Files: `vmd/lib/game.tcl:220-330` (tier loop + steps 7-11), `vmd/lib/hiders.tcl`, `vmd/lib/registry.tcl`, `vmd/lib/mutation.tcl` (`write_combined_pdb` record order).
- Safe modification: any change to record emission order, tier iteration, or source order in `vmd/biochemeleon.tcl` requires re-running `phase17_capstone_smoke.tcl` (the standing composition-root baseline, PASS x4) plus the dispatch smokes. Test coverage: capstone 5 rounds + dispatch + e2e smokes.

**The GUI/Tk surface is structurally untestable headless:**
- Files: `vmd/gui/dialog.tcl`, `vmd/gui/setup_tab.tcl`, `vmd/gui/game_tab.tcl`, `vmd/lib/pick_bridge.tcl` (C-side delivery).
- Why fragile: Tk does not load in `-dispdev text`; text mode cannot fire a real pick. Every GUI-touching plan ends in a human-verify checkpoint — color/focus/timing/pick-delivery regressions are invisible to the entire headless gate (v1 lost several bugs to exactly this class).
- Safe modification: every GUI edit ships with a checkpoint plan (pattern: 16-12/16-16/17.1-14/17.2-12); never claim a text-mode PASS proves C-side firing.
- Test coverage: the pending 17.2-12 checkpoint IS the only verification of the residue-tier GUI surface.

**`AGENTS.md` tclsh claims are wrong in the current WSL shell:**
- Issue: root `AGENTS.md:15` says "`tclsh` (Tcl 8.5/8.6) is available for tcl syntax checks and `tcltest` pure-layer unit tests" and `vmd/AGENTS.md:31-35` builds the Commands section on `tclsh`. Verified ABSENT (`command -v tclsh` fails, exit 1). Five session summaries (17.2-01/04/09/11/12) record "tclsh unavailable in this WSL session" — the actual syntax/pure-layer gate is headless VMD (load-gate source + definition-block run; tcltest UNDER VMD per the 13-01 decision).
- Files: `AGENTS.md:15`, `vmd/AGENTS.md:31-35,51,64,74`.
- Impact: an agent following the docs runs a nonexistent command; wasted cycles; some gates (pure-layer tcltest without VMD) are currently impossible.
- Fix approach: reword both files to "tclsh may be absent; the authoritative gate is tcltest under headless VMD (13-01 pattern) + the load-gate source check." Also root `AGENTS.md:15` misstates the `opencode.json` denylist (`pip *`/`pip3 *`/`apt *`/`conda *` are `ask`-gated per `opencode.json:60-64`; only `rm *`/`rg *` are `deny` at lines 58-59). Status: **open** (doc fix).

**The `pick_verify.tcl` driver is stale and must NOT be run:**
- Files: `vmd/tests/pick_verify.tcl` (~136-139, ~255-261 read the REMOVED `hiders::hidden_rep`/`found_rep` namespace vars).
- Impact: running it errors mid-session (the 17.1-07 blocker note). `rep_verify.tcl` is the ONLY supported GUI driver.
- Status: **known-behavior** (deliberately left UNREPAIRED as a Phase-16 historical artifact, superseded by `vmd/tests/rep_verify.tcl`; STATE Pending Todos says fix-before-use if ever revived).

**STRIDE ss='L' caveat for cartoon tiers (accepted Option A):**
- Issue: VMD has NO `ss='L'` (PyMOL vocabulary); per-atom ss is the `structure` keyword (T/C/H/G/E/B). A spliced GAM residue gets `T` from the LOAD-TIME STRIDE run and renders as a smooth coil/turn tube; `ssrecalc` is NEVER called in the generation flow (unnecessary + destructive — wipes manual `set structure` writes, Pitfall C2, prohibition block at `vmd/lib/splice.tcl:16-30` and enforced by the `mol ssrecalc` grep gate = 0).
- Files: `vmd/lib/splice.tcl:16-30` (Option A decision block), `vmd/lib/game.tcl:246-248` (NEVER-ssrecalc comment), `vmd/lib/mutation.tcl:605-608`.
- Impact (accepted): a single-residue hider renders as a tube regardless of manual ss overrides (≥ 3-residue helix rule) — the force-SS variant is explicitly out of scope/future polish. Cartoon window counts are STRIDE-shift-variant (22→6 observed with zero pathology) — smokes must assert the BOND scene-diff (A=all vs B=not resname GAM, cylinder delta ≥ 4/fake), never window counts.
- Status: **known-behavior** (recorded decision, `17.2-RESEARCH-cartoon-stride.md`).

---

## Scaling Limits

**Multi-round GUI sessions accumulate molecules and intercept picks:**
- Current capacity: molids are monotonic, never reused; each cleanup/guard-restart `mol new`s a restored original; nothing deletes stale copies.
- Limit: the 17.1-14 session already needed manual hiding of the restored original; 17.2-12's checkpoint instructions warn about overlapping leftover 1k8p copies.
- Scaling path: Phase 19 — hide/deselect (or delete) the restored original after guard cleanup; Game-tab Cleanup/Restart buttons.

**Residue tiers need protein CA anchors — blank-chain and DNA-only scenes degrade to zero:**
- Current capacity: `make_residue_hiders` rejects blank-chain anchors (`vmd/lib/mutation.tcl:272-275`) and errors on DNA-only scenes ("no protein anchors", caught by the supply-0 degrade at `vmd/lib/game.tcl:262-265`).
- Limit: MemProtMD structures (1gzm/3gp6/sasdpg4 — ALL blank-chain, cached in `cache/`) would degrade EVERY residue tier (Cartoon/NewCartoon/Trace/Tube) to 0 records; 1k8p (DNA) likewise. Only simple tiers would play.
- Scaling path: Phase 21 (fetch demos) must either pre-assign chain ids when staging membrane demos or accept simple-tier-only rounds on them; the supply-0 warn is the current honest signal.

**Fake-resid block collision guard is a hard error:**
- `splice::resid_block` errors when the block start (9001) is ≤ the scene's real-resid max (`vmd/lib/splice.tcl:160-165`). Current demos max ~500; a fetched structure with resids ≥ 9001 (large multi-chain assemblies, some CryoEM entries) would hard-error the residue tier mid-round rather than degrade.
- Scaling path: Phase 21 — compute the block start from the scene's real max (the `real_max` parameter already exists).

---

## Dependencies at Risk

**VMD 1.9.3 (2016 binary) — single hard dependency, heavily probe-pinned against THIS build:**
- Risk: the codebase encodes dozens of binary-specific facts: Tcl 8.5.6 PRNG stream (stable per-build, NOT portable — `17.1-01` resolution (c)), element table quirks (P radius 1.80 / tan {0.5 0.5 0.2} — `17.1-11`), `within` trailing-expression swallowing, `molinfo set frame` not pinning, no mouse-mode query form, `save_state` not persisting beta/user/segid, `mol showrep off` ignored in text mode, UG Table 9.4 vs actual `vmd_pick_*` behavior.
- Impact: a VMD upgrade (or a user on a different 1.9.x build) silently invalidates pinned smoke numbers and possibly behavioral contracts; the grep gates would NOT catch behavioral drift.
- Migration plan: stay on 1.9.3. On ANY binary change: re-probe the PRNG seeds (17.1-01 seeds 173/41), re-pin element radii/colors from renders, re-run the full gate + a GUI checkpoint. `vmd-ref/` (gitignored) is the reference corpus.

**`vmd-ref/` and `vmd/3rd_party_lib/` are gitignored:**
- Risk: a fresh clone has no UG PDF, no bundled-plugin patterns, no core-script references; plans referencing `vmd-ref/` paths fail there.
- Files: `vmd/AGENTS.md:21-26` (reference inventory), root `AGENTS.md` (git-ignored list).
- Mitigation: re-derivable from the local VMD install; documented. Status: **known-behavior** (accepted trade).

**Python 3.6 dev-shell constraint (v1 + smoke tooling):**
- Unchanged from the prior audit: 3.7+ syntax fails the WSL gate; keep v1 and any Python tooling at 3.6-compatible syntax. Status: **known-behavior**.

---

## Missing Critical Features

**Remaining v2 roadmap phases (tracked in `.planning/ROADMAP.md`):**
- Phase 18 (materials), Phase 19 (in-game actions: hint/reveal/restart/cleanup buttons, DIFF-01 reveal counter, DIFF-04 found-color picker — `REQUIREMENTS.md:145-146`), Phase 20-22 (persistence/fetch/in-game help incl. the "press p first" advice from 17.1-14), Phase 23 (multi-viewer docs). The Game tab currently exposes only Start + pick/rotate toggle; cleanup is console-only.
- Status: **open** (scheduled, not defects).

**Difficulty calibration — non-sphere tiers blend too well:**
- Problem: 17.1-14 GUI finding — all 6 simple styles applied correctly, but non-sphere tiers blend INTO the default-Lines scene so well the user needed manual rep toggling to spot them. The 17.2-12 checkpoint adds the magnitude question for 1.0 Å splice bumps ("findable but subtle? record if 1.25 tuning is wanted; never ≥ 1.4" — the 1.43 Å hard envelope at `vmd/lib/splice.tcl:70` bounds any tuning).
- Files: `vmd/lib/splice.tcl:70` (SPLICE_DISPLACEMENT), `vmd/lib/generators.tcl` (bond band constants), `.planning/phases/17.1-*/17.1-14-SUMMARY.md` (finding).
- Blocks: game feel on default scenes; Phase 19/22 difficulty work owns it.
- Status: **open** (recorded finding + pending checkpoint data).

**Drop-ungeneratable-tiers + effective-total-recompute policy:**
- Problem: the dispatch degrades supply-0 residue tiers to 0 records but keeps the round on the remaining tiers with the ORIGINAL effective total; smokes pinning the pre-degrade count go red (the dispatch step-8 flake). The recorded policy fix recompute the effective total after drops so request-side bookkeeping matches observed generation.
- Files: `vmd/lib/game.tcl:262-265` (degrade site), `vmd/lib/rep_tiers.tcl` (`resolve_per_rep`/`effective_total`), `vmd/smoke/phase17_dispatch_smoke.tcl` (step 8).
- Status: **open** (gap-closure candidate, recipe in `17.2-11-SUMMARY.md`).

---

## Test Coverage Gaps

**The 17.2-12 GUI checkpoint is PENDING — the phase's last unverified surface:**
- What's not tested: real-Tk rendering of cartoon-family bumps (blend verdicts a-g in `17.2-12-SUMMARY.md`), real-mouse C-side pick delivery on cartoon geometry, and the open CA vs N/C/O/CB pick-target question (the PICK VERDICT log lines answer it). Text-mode smokes deliberately do NOT claim real-mouse firing.
- Files: `vmd/tests/rep_verify.tcl` (driver, pv_round3 + verdict logging built), `vmd/lib/pick_bridge.tcl`, `vmd/gui/game_tab.tcl`.
- Risk: residue-tier GUI defects (blend quality, bump clickability, fallback delivery) surface only here.
- Priority: **HIGH** — blocking Phase 17.2 closure.

**Residue-tier fallback picks verified only via direct `on_pick` calls:**
- What's not tested: the C-side pick path re-targeting a bump click (N/C/O/CB) to the registered CA through the real GUI (`vmd/lib/game.tcl:513-531` `_resolve_pick`; `vmd/lib/game.tcl:584-598` on_pick fallback branch proven headlessly by direct invocation in 17.2-09/17.2-11 round D).
- Priority: **HIGH** — same checkpoint closes it.

**GUI/Tk widgets and timers (standing structural gap, unchanged from v1):**
- What's not tested: `vmd/gui/setup_tab.tcl` (19 procs), `vmd/gui/game_tab.tcl` (countdown/timer `after` chains, win box), `vmd/gui/dialog.tcl` (on_start/on_close). Headless smokes cover the loading layer only; widget behavior is human-verify.
- Priority: **MEDIUM** — inherent to the WSL/Windows split; mitigated by the checkpoint pattern.

**2 pre-existing red smokes (standing known-reds):**
- `vmd/smoke/phase17_dispatch_smoke.tcl` (step-8 draw-dependence) and `vmd/smoke/phase17_licorice_smoke.tcl` (P pins) — see Tech Debt. Any NEW red beyond these two is attributable to new changes (full-suite green baseline: `17.2-11`).
- Priority: **MEDIUM** — recipes recorded; fix in the gap-closure plan.

**Large-molecule paths never exercised in v2:**
- What's not tested: generator/mutate performance and correctness on 10k+ atom structures (per-candidate selection loops, `%8.3f` overflow guards near |9999|, combined-PDB write time).
- Files: `vmd/lib/mutation.tcl`, `vmd/lib/generators.tcl`, `vmd/lib/splice.tcl` (max_coord guard).
- Priority: **LOW** until Phase 21 makes fetched demos playable.

---

*Concerns audit: 2026-09-08 (v2 Phase 17.2 built + headless-green, GUI checkpoint pending; supersedes the 2026-08-18 v1-scoped audit — v1 items are archived with the shipped milestone, only standing process gates retained here)*
