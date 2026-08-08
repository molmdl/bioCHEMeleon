---
phase: 05-line-stick-and-cartoon-generators
plan: 06
subsystem: testing
tags: [pymol, alt-conf, cartoon, ribbon, headless-smoke, research-spike, gap-closure]

# Dependency graph
requires:
  - phase: 05-line-stick-and-cartoon-generators (05-05 human-verify)
    provides: "PARTIAL APPROVAL finding that cartoon terminal-extension renders DISCONNECTED on 1ubq (the sheet arrow SHAPE); gap closure needed for alt-conf approach"
  - phase: 03-mutation-safety-hider-registry-foundation
    provides: "mutation.fetch_all_hider_ids + cleanup_hiders (sentinel read/cleanup path tested in section 11)"
provides:
  - "smoke/altconf_spike.py (314 lines, pure pymol.cmd.*, 10/10 ALL PASSED headless) — runtime-verified alt-conf segment replication mechanism"
  - "05-RESEARCH.md sec 12 — spike findings + implementation recommendation for plan 05-08"
  - "WORKING approach: cmd.create(tmp,seg) + cmd.alter(tmp,alt='B';segi='GAME') + cmd.create(obj,tmp) — appends TRUE alt-conf pairs"
  - "Three critical caveats for 05-08: identify excludes alt-conf (use segi GAME selectors), id matches both alt versions (use resi), residual alt-conf state requires backup.restore between rounds"
affects: [05-08 (alt-conf cartoon hider implementation), Phase 5 gap closure, GameController cleanup path]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Alt-conf segment replication: create+alter(alt='B';segi='GAME')+create — appends true alt-conf pairs (same chain/resv/name, alt='B')"
    - "segi GAME selectors (NOT id-diff) for finding alt-conf atoms — cmd.identify excludes alt-conf by default"
    - "segi GAME + resi <resv> (NOT id <id>) for unambiguous alt-conf atom selection — id matches both alt='' and alt='B'"

key-files:
  created:
    - smoke/altconf_spike.py
  modified:
    - .planning/phases/05-line-stick-and-cartoon-generators/05-RESEARCH.md

key-decisions:
  - "Alt-conf approach IS VIABLE — plan 05-08 should implement insert_cartoon_hider (alt-conf variant) using create+alter+create"
  - "PRIMARY cmd.create(obj,seg,1,1) is a NO-OP (merge by identity) — plan hypothesis DISPROVED"
  - "FALLBACK cmd.fuse(tmp,obj,mode=3) renames atoms (CA→C02, no CA) — plan 12.2 fallback DISPROVED"
  - "WORKING approach: create(tmp,seg) + alter(tmp,alt='B';segi='GAME') + create(obj,tmp) — appends true alt-conf pairs"
  - "all_states is NOT required for cartoon to render alt-conf (game_cartoon_ca=3 with default settings)"
  - "Cleanup for alt-conf hiders MUST use backup.restore (delete+create), NOT just cmd.remove('segi GAME') — residual alt-conf state breaks re-insertion"
  - "Use segi GAME selectors (NOT id-diff) and segi GAME + resi (NOT id) for alt-conf atom identification"

patterns-established:
  - "Alt-conf duplication via create+alter+create: the alt='B' tag differentiates identity so cmd.create APPENDS (not merges)"
  - "segi GAME selector sees alt-conf atoms; cmd.identify(obj,mode=0) does NOT — 05-08 must use segi GAME selectors"
  - "backup.restore required for alt-conf cleanup between game rounds (sentinel remove alone leaves residual alt-conf state)"

# Metrics
duration: 47min
completed: 2026-08-09
---

# Phase 5 Plan 06: Alt-Conf Research Spike Summary

**Headless research spike proving the alt-conf segment-replication approach IS VIABLE for cartoon/ribbon hiders via create+alter+create (10/10 ALL PASSED), with three critical caveats documented for plan 05-08.**

## Performance

- **Duration:** ~47 min (across 2 sessions — interrupted and resumed)
- **Started:** 2026-08-08T16:53:24Z
- **Completed:** 2026-08-08T17:40:42Z
- **Tasks:** 2/2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- Wrote and ran `smoke/altconf_spike.py` (314 lines, pure `pymol.cmd.*`, NO Qt) — 10/10 ALL PASSED headlessly via `cmd.exe /c C:\src\run-conda-pymol.bat -cq`
- Discovered the WORKING alt-conf duplication mechanism: `cmd.create(tmp, seg)` + `cmd.alter(tmp, "alt='B'; segi='GAME'")` + `cmd.create(obj, tmp)` — appends TRUE alt-conf pairs (same chain/resv/name=CA, alt='B'), 25 atoms, 3 CAs, cartoon renders them, polymer, alter_state displaces, cleanup restores
- Disproved the plan's PRIMARY hypothesis (`cmd.create(obj, seg, 1, 1)` same-object = NO-OP, merge by identity) and the plan's FALLBACK (`cmd.fuse mode=3` renames atoms, no CA)
- Documented three critical caveats for 05-08: (1) `cmd.identify` excludes alt-conf atoms — use `segi GAME` selectors, (2) `id <id>` matches both alt='' and alt='B' — use `segi GAME and resi <resv>`, (3) residual alt-conf state after `cmd.remove("segi GAME")` breaks re-insertion — use `backup.restore` between rounds
- Appended §12 to 05-RESEARCH.md (124 new lines) with spike results table, implementation recommendation, key API calls, displacement strategy, and sentinel compatibility analysis

## Task Commits

Each task was committed atomically:

1. **Task 1: Write + run alt-conf research spike headlessly** — `a6fd26a` (feat)
2. **Task 2: Document alt-conf findings in 05-RESEARCH.md §12** — `1f22014` (docs)

## Files Created/Modified
- `smoke/altconf_spike.py` (NEW, 314 lines) — Headless alt-conf research spike; 10 checks testing cmd.create same-object duplication (NO-OP), fuse fallback (renames), working create+alter+create approach (appends true alt-conf pairs), cartoon/ribbon render, polymer classification, alter_state displacement, cleanup, sentinel compatibility
- `.planning/phases/05-line-stick-and-cartoon-generators/05-RESEARCH.md` (823→947 lines) — Appended §12 "Alt-Conf Segment Replication — Spike Findings" with 5 subsections (12.1-12.5): results table, implementation recommendation, key API calls, displacement strategy, sentinel compatibility

## Decisions Made
- **Alt-conf approach IS VIABLE.** The spike proves cartoon renders alt-conf CAs (game_cartoon_ca=3), they're polymer (game_polymer=25), alter_state displaces them (dx=2.0), and the sentinel design works (fetch_all_hider_ids returns 1). Plan 05-08 should implement using the WORKING approach.
- **WORKING approach: create+alter+create.** `cmd.create(tmp, seg, 1, 1)` + `cmd.alter(tmp, "alt='B'; segi='GAME'", space={})` + `cmd.create(obj, tmp)` + `cmd.delete(tmp)`. The `alt='B'` tag differentiates identity so `cmd.create` APPENDS (not merges). This was discovered during spike development — neither the plan's PRIMARY nor FALLBACK worked.
- **all_states NOT required.** Cartoon renders alt-conf CAs with default settings (all_states=off). Plan 05-08 does NOT need `cmd.set('all_states', 'on')`.
- **Cleanup needs backup.restore for alt-conf.** The Phase 3 `cleanup_hiders` (sentinel `cmd.remove("segi GAME")` alone) restores the count but leaves residual alt-conf state that breaks subsequent alt-conf insertions. Plan 05-08 MUST use `backup.restore` (delete+create two-step) for alt-conf cleanup between game rounds.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's PRIMARY cmd.create same-object hypothesis is a NO-OP**
- **Found during:** Task 1 (first headless run)
- **Issue:** The plan's primary mechanism `cmd.create(obj, seg, 1, 1)` (same-name create) is a NO-OP — `cmd.create` MERGES by identity (segi, chain, resi, name) when target name equals source object. A subset selection overwrites itself, producing 0 new ids. The plan's claim that "name == source object => appends duplicated atoms" is incorrect for same-object subsets.
- **Fix:** Tested the plan's FALLBACK (fuse mode=3 — also failed, renames atoms), then discovered the WORKING approach: `create(tmp, seg)` + `alter(tmp, "alt='B'; segi='GAME'")` + `create(obj, tmp)`. The `alt='B'` tag differentiates identity so `cmd.create` appends TRUE alt-conf pairs.
- **Files modified:** smoke/altconf_spike.py (documents all three approaches: PRIMARY no-op, FALLBACK renames, WORKING appends)
- **Verification:** 10/10 ALL PASSED headlessly; the WORKING approach appends 25 atoms (3 CAs, all alt-conf pairs), cartoon renders them, cleanup restores
- **Committed in:** a6fd26a (Task 1)

**2. [Rule 1 - Bug] id selector matches both alt='' and alt='B' versions**
- **Found during:** Task 1 (section 11 sentinel test debugging)
- **Issue:** The `id <id>` selector in PyMOL matches BOTH the original (alt='') and the alt-conf (alt='B') versions of the same atom (they share id space). `cmd.alter("obj and id 227", "b=-999.0")` sets b=-999 on the original too, and the alt-conf CA's b may not be set reliably. The plan's section 4/11 used `cmd.alter("id <clickable_id>", "b=-999.0")` which doesn't work for alt-conf atoms.
- **Fix:** Changed to `cmd.alter("obj and segi GAME and name CA and resi <resv>", "b=-999.0")` — unambiguous because the original has segi='A' (excluded by `segi GAME`). Read `(ID, resv)` via iterate, use `resv` (int) in the selector.
- **Files modified:** smoke/altconf_spike.py (sections 4 and 11)
- **Verification:** `segi GAME b<0 count=1` after the alter; `fetch_all_hider_ids` returns `[('1ubq', 227)]`
- **Committed in:** a6fd26a (Task 1)

**3. [Rule 3 - Blocking] Residual alt-conf state breaks re-insertion**
- **Found during:** Task 1 (section 11 sentinel test)
- **Issue:** After `cmd.remove("segi GAME")` (section 10 cleanup), a second create+alter+create flow (section 11) produces 25 atoms (count 660→685) but `cmd.iterate("segi GAME and name CA")` finds 0 CAs. The residual alt-conf "slots" from the first round confuse the second round's `cmd.create(obj, tmp)`. This means the Phase 3 `cleanup_hiders` (sentinel remove alone) is INSUFFICIENT for alt-conf hiders in a "New Game" flow.
- **Fix:** Added `cmd.delete(obj); cmd.fetch("1ubq", async_=0)` before section 11's re-insert to guarantee a clean state. Documented in §12.2 caveat 3: plan 05-08 MUST use `backup.restore` (delete+create two-step) for alt-conf cleanup between rounds.
- **Files modified:** smoke/altconf_spike.py (section 11); 05-RESEARCH.md §12.2 caveat 3 + §12.5
- **Verification:** Section 11 passes with the reload (10/10 ALL PASSED); documented as a critical caveat for 05-08
- **Committed in:** a6fd26a (Task 1), 1f22014 (Task 2)

**4. [Rule 1 - Bug] segment_sele matches both originals and duplicates**
- **Found during:** Task 1 (section 3 check)
- **Issue:** `segment_sele = "1ubq and chain A and resi 30-32"` matches BOTH the original CAs (alt='', segi='A') AND the alt-conf duplicates (alt='B', segi='GAME') since they share chain/resi. The `orig_props` iterate returned 6 entries (3 originals + 3 duplicates) instead of 3, causing the "same chain/resi/name" check to fail.
- **Fix:** Added `and not segi GAME` to the orig_props iterate: `segment_sele + " and name CA and not segi GAME"`.
- **Files modified:** smoke/altconf_spike.py (section 3)
- **Verification:** `orig_props=[('A',30,'CA',''),('A',31,'CA',''),('A',32,'CA','')]` (3 entries, alt=''); `new_props=[('A',30,'CA','B'),...]` (3 entries, alt='B') — check PASSES
- **Committed in:** a6fd26a (Task 1)

---

**Total deviations:** 4 auto-fixed (3 bugs, 1 blocking)
**Impact on plan:** The plan's PRIMARY and FALLBACK approaches were both disproved, requiring discovery of the WORKING approach (create+alter+create). Three caveats documented for 05-08. The spike's purpose (test alt-conf viability) was achieved — the approach IS viable, just via a different mechanism than the plan hypothesized.

## Issues Encountered
- The plan's PRIMARY `cmd.create(obj, seg, 1, 1)` hypothesis was incorrect (NO-OP, merge by identity) — discovered during the first headless run. Required exploratory testing (5 variants: A-E) to find the working mechanism. The plan's FALLBACK (fuse mode=3) also failed (renames atoms, no CA). The WORKING approach (create+alter+create with alt='B' tag) was discovered through systematic exploration of PyMOL's create/fuse semantics.
- The `id` selector's behavior with alt-conf atoms (matches both alt='' and alt='B') was unexpected and required a fix to use `segi GAME and resi <resv>` for unambiguous selection.
- Residual alt-conf state after cleanup was the most subtle issue — required a reload workaround in the spike and a `backup.restore` recommendation for 05-08.

## Next Phase Readiness
- **Plan 05-08 can proceed** with the alt-conf approach using the WORKING mechanism documented in §12.2-12.3. The spike provides:
  - Exact API calls (§12.3) with source citations
  - Displacement strategy (§12.4): 1.0-2.0 Å, alter_state verified
  - Sentinel compatibility (§12.5): read/fetch paths unchanged, cleanup needs backup.restore
  - Three critical caveats (§12.2): segi GAME selectors (not id-diff), segi GAME + resi (not id), backup.restore between rounds
- **05-08 human-verify needed:** the cartoon trace visual blend (does the displaced alt-conf segment look like a natural "conformational variant" or a visible "fork"?), displacement magnitude fine-tuning (1.5 Å vs 0.5 Å), and the backup.restore cleanup path in a real "New Game" flow.
- **Phase 5 gap closure:** this spike closes the alt-conf gap from 05-05 (disconnected cartoon). The line/stick IndexError gap (05-07) and ribbon support gap remain.
