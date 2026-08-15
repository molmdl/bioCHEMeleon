---
status: resolved
trigger: "Phase 11 alt-conf cartoon/ribbon hider registration fails with KeyError: \"hider ('1ubq', 289) already registered\" when GUI setup JSON contains BOTH cartoon + ribbon hiders."
created: 2026-08-15T00:00:00Z
updated: 2026-08-16T00:00:00Z
resolution: "RESOLVED. Root cause fix committed (ebd5086: consolidate cartoon+ribbon pick_segments into a single global pick). Headless verified: 63/63 smoke green, keyerror repro PASS, 313 unit tests OK. ULTIMATELY SUPERSEDED by single-state refactor (d65fb2c, debug session phase11-cartoon-hider-single-state-refactor.md) which eliminated the alt-conf approach entirely — new-chain copies get NEW atom ids (no id sharing, no duplicate-registration KeyError possible). User-verified working in Windows PyMOL GUI: KeyError gone, all reps render. The pick_segments consolidation (ebd5086) remains in the codebase as good practice (globally disjoint segments across reps) even though the KeyError can no longer occur under the single-state design."
---

## Current Focus

hypothesis: CONFIRMED by headless repro (smoke/phase11_keyerror_repro.py). In `_prepare_and_start` (biochemeleon/__init__.py:192-216), `pick_segments(cas_by_chain, count)` is called INDEPENDENTLY per rep. For count=1 it picks the CENTERED window DETERMINISTICALLY (generators.py:159-160, no RNG), so cartoon + ribbon both pick the SAME segment on a single-chain protein -> same anchor middle CA id (alt-conf copies SHARE ids with originals, Pitfall 10) -> `registry.register` raises KeyError on the second rep (registry.py:206-207).
test: Headless repro mimicking the per-rep independent pick_segments calls (cartoon=1, ribbon=1) + game.start.
expecting: KeyError (bug present); after fix: 2 hiders, no KeyError, distinct anchor ids.
result: REPRODUCED -- cartoon_segs == ribbon_segs == [('A', 37, 39)]; KeyError("hider ('1ubq', 289) already registered") at game.py:87 -> registry.py:207. Exact match to the bug report.
next_action: Implement approach (a) single global pick_segments for combined cartoon+ribbon count in _prepare_and_start; add headless regression test to phase11_smoke.py Section M; verify smoke 54+ -> green, unit tests green, grep gates clean.

## Symptoms

expected: GUI setup with a setup JSON containing both cartoon + ribbon hiders starts the game cleanly -- all hiders registered, no KeyError.
actual: `registry.register` raises `KeyError: "hider ('1ubq', 289) already registered"` on the second rep's hider insertion when both cartoon + ribbon hiders are configured.
errors: KeyError on duplicate `(object, id)` registration.
reproduction: In `biochemeleon/__init__.py` `_prepare_and_start`, `pick_segments` is called independently per rep. Each call picks disjoint segments WITHIN its own rep, but segments can OVERLAP ACROSS reps -> same middle residue -> same anchor id -> registry.register raises KeyError on duplicate `(object, id)`. Trigger via a GUI setup JSON having both cartoon + ribbon hiders.
started: Phase 11, discovered by the executor agent. Branch `exec/11`, worktree `tmp/exec-11` (commit 670b23e). Headless smoke `smoke/phase11_smoke.py` currently 54/54 PASSED (it sidesteps the bug by calling `pick_segments(..., 2)` ONCE and manually splitting across reps -- smoke line 257, 264-265).

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-08-15T00:01:00Z
  checked: `biochemeleon/__init__.py` `_prepare_and_start` lines 192-216 (the per-rep loop)
  found: `for rep, count in per_rep.items()` calls `generators.pick_segments(cas_by_chain, count)` INDEPENDENTLY per rep (line 212). For cartoon AND ribbon, the SAME `cas_by_chain` is used (built once at lines 179-190). No cross-rep exclusion / dedup.
  implication: Two reps can pick the same or overlapping segments.

- timestamp: 2026-08-15T00:01:30Z
  checked: `biochemeleon/generators.py` `pick_segments` lines 111-178
  found: For `count=1` (need==1 branch, line 155-160): `mid = (len(windows) - 1) // 2`; `out.append((ch, windows[mid][0], windows[mid][1]))`. Fully DETERMINISTIC (no RNG; `cas_by_chain` is the only input). Both cartoon and ribbon calls with count=1 and the same `cas_by_chain` return the IDENTICAL `(chain, start_resi, end_resi)`.
  implication: cartoon=1 + ribbon=1 on 1ubq (single chain) -> identical segment -> identical anchor middle residue -> identical anchor CA atom id.

- timestamp: 2026-08-15T00:02:00Z
  checked: `biochemeleon/mutation.py` `insert_altconf_cartoon_hider` lines 485-576
  found: Anchor = `start_resi + 1` (first middle residue, line 565). `cmd.alter(anchor_sele, "b=-999")` on `chain + resi + name CA + segi GAME` (line 566-568). `ids = cmd.identify(anchor_sele + " and b < 0", mode=0)` (line 570); `assert len(ids) == 1` (line 571). Returns `clickable_id = ids[0]` (line 572). Docstring line 536-537: "the anchor middle-CA's stable id (shared with the original CA -- Bug 1)".
  implication: The registered id is the anchor CA's id, SHARED across alt-conf copies (Pitfall 10). Two hiders with the same anchor residue -> same id.

- timestamp: 2026-08-15T00:02:30Z
  checked: `biochemeleon/game.py` `start` lines 48-103; `biochemeleon/registry.py` `register` lines 188-209
  found: `game.start` loops `hider_specs`, calls `mutation.insert_hider_for_rep` -> `insert_altconf_cartoon_hider` -> returns `aid`; then `self.registry.register(object=self.target_obj, id=aid, rep=rep, **extra)` (line 87-88). `registry.register` raises `KeyError("hider %r already registered" % (rec.key(),))` if `(object, id)` already in `self._records` (line 206-207).
  implication: Second hider with the same anchor id -> KeyError. Matches the bug report exactly.

- timestamp: 2026-08-15T00:03:00Z
  checked: `smoke/phase11_smoke.py` Section I (mixed-rep) lines 247-282
  found: Section I calls `generators.pick_segments(build_cas_by_chain(), 2)` ONCE (line 257), then manually assigns `segs_i[0]` to cartoon and `segs_i[1]` to ribbon (lines 264-265). This sidesteps the per-rep independent-call path in `_prepare_and_start`. That is why the smoke is 54/54 green despite the bug.
  implication: The smoke test does NOT cover the buggy `_prepare_and_start` path. A new headless regression test is needed that exercises the per-rep independent-call path (or, after the fix, the consolidated path).

- timestamp: 2026-08-15T00:03:30Z
  checked: `smoke/phase11_gui_diag.py` checklist item 9 (lines 208-212)
  found: Item 9 is EXACTLY the bug scenario: "set per_rep: cartoon=1, ribbon=1, spheres=1, sticks=1 ... Click Start in the plugin. ... Tests the full _prepare_and_start integration". This is a GUI-only (human-verify) test -- it goes through `_prepare_and_start` and would hit the KeyError.
  implication: The GUI reproduction needs a human with a real PyMOL session (Qt path, no WSL display). The headless fix verification should add a cmd-only regression test mirroring this path.

## Resolution

root_cause: CONFIRMED. `_prepare_and_start` (biochemeleon/__init__.py:212) calls `generators.pick_segments(cas_by_chain, count)` INDEPENDENTLY per rep inside the `for rep, count in per_rep.items()` loop. For count=1, `pick_segments` is fully DETERMINISTIC (no RNG; generators.py:159-160 picks the centered window `windows[(len(windows)-1)//2]`). With the same `cas_by_chain` (built once at __init__.py:179-190) and count=1, BOTH cartoon and ribbon return the IDENTICAL `(chain, start_resi, end_resi)` -> identical anchor middle residue (`start_resi+1`) -> identical anchor CA atom id (alt-conf copies SHARE ids with originals -- Pitfall 10; mutation.py:536-537). `game.start` then calls `registry.register(object, anchor_id, rep)` (game.py:87); the second rep's register hits the existing `(object, id)` key and raises `KeyError("hider %r already registered")` (registry.py:206-207). Headless repro confirmed: cartoon_segs == ribbon_segs == [('A', 37, 39)]; KeyError("hider ('1ubq', 289) already registered"). The bug report's framing is EXACTLY correct (no discrepancy). The smoke test is 54/54 green only because Section I (smoke line 257, 264-265) sidesteps the bug by calling `pick_segments(..., 2)` ONCE and manually splitting across reps.
fix: Approach (a) -- single global pick. In `_prepare_and_start`, pre-compute the combined cartoon+ribbon count and call `pick_segments` ONCE (globally disjoint segments), then consume from the shared pool in the per-rep loop (preserving per_rep.items() order so hider_specs order + is_first_altconf/all_states behavior is unchanged). `pick_segments` signature/behavior UNCHANGED (approach (b) rejected: it would change the pure signature + logic, affecting test_generators.py + all smoke calls -- larger blast radius). cartoon and ribbon both need the same kind of mid-chain backbone segment (insert_altconf_cartoon_hider is the same function; rep only controls cmd.show), so a single global pick is semantically correct. Under-generation: first-processed rep gets priority from the shared pool; per-rep warning preserved (now based on `_take < count`).
verification:
  - Headless repro (smoke/phase11_keyerror_repro.py): PART 1 (buggy per-rep independent pattern) reproduces `KeyError("hider ('1ubq', 289) already registered")` with cartoon_segs == ribbon_segs == [('A', 37, 39)]; PART 2 (fixed single-global-pick pattern) succeeds -- registry len=2, counts={cartoon:1, ribbon:1}, ids=[19, 45] DISTINCT, no KeyError. Both parts PASS, exit 0.
  - Headless smoke (smoke/phase11_smoke.py): 63/63 PASSED (was 54/54; +9 new Section M "CROSS-REP DISJOINT" checks: 2 disjoint segments available, no KeyError, len==2, counts cartoon==1 ribbon==1, DISTINCT anchor ids, segments globally disjoint across reps, both is_altconf True, both alt_tag=='B', all_states set, cleanup restores atom count). Exit 0.
  - Pure-layer unit tests: `python3.6 -m unittest tests.test_generators tests.test_registry tests.test_game_controller tests.test_persistence tests.test_setup_state` -> 313 tests OK (test_setup_state alone = 112 OK). No regressions.
  - py_compile all modules: OK.
  - Pitfall-1 grep gate: ZERO matches (exit 1 = no match). Clean.
  - exec_ grep gate: 1 hit at biochemeleon/gui_game.py:303 `msg.exec_()` on a QMessageBox (line 298 `msg = QtWidgets.QMessageBox(...)`) -- explicitly ALLOWED by AGENTS.md. Pre-existing, not introduced by this fix. Clean.
  - GUI human-verify (PENDING): the GUI/Qt path through `_prepare_and_start` with per_rep={'cartoon':1,'ribbon':1} (plus optional spheres=1, sticks=1) cannot be run from WSL (no display). Surfaced as a human-verify checkpoint -- see the return message. The headless Section M mirrors the fixed _prepare_and_start pattern at the cmd tier (single global pick + split), so the fix logic IS headless-verified; only the full Qt integration (PluginDialog -> Setup tab -> Start button) needs a human.
files_changed: [biochemeleon/__init__.py, smoke/phase11_smoke.py, smoke/phase11_keyerror_repro.py, .planning/debug/phase11-cartoon-ribbon-hider-keyerror.md]
commits:
  - ebd5086 fix(11): consolidate cartoon+ribbon pick_segments to prevent duplicate anchor id KeyError
  - 355889b test(11): add cross-rep disjoint smoke regression + keyerror repro
  - 4c3e13a docs(11): debug session for cartoon+ribbon hider KeyError
stability: smoke re-run from committed state -> 63/63 PASSED, exit 0 (not flaky).
