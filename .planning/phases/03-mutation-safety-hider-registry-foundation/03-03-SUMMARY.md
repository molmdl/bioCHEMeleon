---
phase: 03-mutation-safety-hider-registry-foundation
plan: 03
subsystem: infra
tags: [pymol, pseudoatom, hider, sentinel, cmd-coupled, mutation-safety, atom-id, identify]

# Dependency graph
requires:
  - phase: 01-plugin-bootstrap-dialog-scaffold
    provides: the biochemeleon/ package this module lives in (standalone cmd module — no import of setup_state/registry/backup; soft contract only: the caller is expected to register the returned id via registry.HiderRegistry, but insert_hider does NOT import registry)
provides:
  - mutation.insert_hider(object, pos, rep, handle, segi='GAME', b=-999.0) — inserts one hider pseudoatom INTO an existing object (NOT a new object), tags the segi='GAME' + b=-999 sentinel, and returns the new atom's stable id (fetched via cmd.identify(mode=0), never the pseudoatom return value)
affects: [03-06/03-09 (fetch_all_hider_ids + cleanup_hiders — the sentinel-query + sentinel-cleanup half of mutation.py), 03-11/03-12 (game.py GameController insert loop calls insert_hider), Phase 4/5 (sphere/cartoon/ribbon generators supply pos + rep + handle and call insert_hider), Phase 3 smoke test (insert + sentinel + id-stability assertions)]

# Tech tracking
tech-stack:
  added: []  # no new libs — only pymol.cmd which ships with pymol-open-source
  patterns:
    - "In-place hider insert: cmd.pseudoatom(object=existing, ...) appends INTO the object (no new object created) — the player can't toggle a separate 'hiders' object to win (HIDER-01, AGENTS.md lock)"
    - "Sentinel via single multi-`;` alter + space={}: cmd.alter(sele, \"segi='GAME'; b=-999.0\", space={}) sets both fields in one call (editor.py:354 idiom) with an explicit empty space dict to avoid polluting the global pymol.__dict__ (RESEARCH Q3; Pitfall: global stored namespace)"
    - "Stable id via cmd.identify(mode=0), NEVER the pseudoatom return value: the return dispatches to C (_cmd.pseudoatom, creating.py:1126) and is an unverified status code (RESEARCH Q1); mode=0 returns the integral id list, NOT the fragile index (querying.py:1282-1283; Pitfall 4)"
    - "Defensive cmd.sort after alter: editing.py:1457 warns to sort after altering segi/chain (confounds later create/byres); sort reassigns index but preserves id — safe for the id-keyed registry"

key-files:
  created:
    - biochemeleon/mutation.py
  modified: []

key-decisions:
  - "insert_hider uses cmd.pseudoatom(object=existing) — inserts INTO the object, not cmd.load/cmd.create('hiders', ...) (HIDER-01: a separate object would let the player toggle one object to win; AGENTS.md lock)"
  - "Sentinel segi='GAME' + b=-999 set via cmd.alter with the multi-`;` idiom (editor.py:354) and space={} — hygienic, no global namespace pollution (RESEARCH Q3)"
  - "id fetched via cmd.identify(..., mode=0), NEVER the cmd.pseudoatom return value — the return is an unverified C status code (RESEARCH Q1); mode=0 returns the id list, NOT the fragile index (Pitfall 4)"
  - "cmd.sort(object) called after the alter (defensive — editing.py:1457 alter warning); sort reassigns index but preserves id, safe for the id-keyed registry"
  - "rep accepted as a parameter but NOT used for placement — the registry needs rep for per-rep counts, but placement is Phase 4/5 generator work; Phase 3's insert_hider places at the caller-supplied pos (proves the mechanism, not the generator)"
  - "Scope discipline: fetch_all_hider_ids() and cleanup_hiders() are NOT in this plan — they belong to plans 03-06 and 03-09 (insert_hider subset only)"

patterns-established:
  - "In-place hider insert via cmd.pseudoatom(object=existing): the only built-in in-place atom insert; HIDER-01 (object list unchanged)"
  - "Sentinel-set idiom: cmd.alter(sele, \"segi='GAME'; b=-999.0\", space={}) — multi-field in one call, hygienic space dict (RESEARCH Q3)"
  - "Stable-id fetch idiom: cmd.identify(\"obj and name <handle> and segi GAME\", mode=0) + assert len==1 — never trust the pseudoatom return value (RESEARCH Q1)"
  - "Defensive cmd.sort after segi/chain alter (editing.py:1457) — preserves id, reassigns index"

# Metrics
duration: 16 min
completed: 2026-08-05
---

# Phase 3 Plan 03: mutation.py insert_hider Summary

**Cmd-coupled hider-insertion primitive: insert_hider inserts a pseudoatom INTO an existing object (HIDER-01), tags the segi='GAME'+b=-999 sentinel via a hygienic multi-`;` alter (HIDER-02), and returns the new atom's stable id fetched via cmd.identify(mode=0) — never the unverified pseudoatom return value (RESEARCH Q1)**

## Performance

- **Duration:** 16 min (longer than the ~2 min code work due to a concurrent-execution git collision that required careful untangling — see Issues Encountered)
- **Started:** 2026-08-05T03:54:20Z
- **Completed:** 2026-08-05T04:10:42Z
- **Tasks:** 2 (Task 1 committed; Task 2 gate-run only)
- **Files modified:** 1 (biochemeleon/mutation.py created)

## Accomplishments
- Created `biochemeleon/mutation.py` — the cmd-coupled hider-insertion primitive (mirrors demos.py's `from pymol import cmd` + section-comment + inline-source-citation style; standalone — no import of setup_state/registry/backup)
- `insert_hider(object, pos, rep, handle, segi='GAME', b=-999.0)` implements the single most critical Phase 3 operation:
  - **HIDER-01** — `cmd.pseudoatom(object=object, pos=list(pos), name=handle, segi=segi, b=b, hetatm=1, elem='PS', resn='HIDER', chain='H', resi='9001')` inserts the pseudoatom INTO the existing object (creating.py:1082) — `cmd.get_names('public_objects')` is unchanged (no new object the player could toggle to win)
  - **HIDER-02** — `cmd.alter(f"{object} and name {handle}", "segi='GAME'; b=-999.0", space={})` sets the sentinel in one multi-`;` call (editing.py:1424; editor.py:354 idiom) with `space={}` to avoid global namespace pollution (RESEARCH Q3)
  - **defensive sort** — `cmd.sort(object)` after the alter (editing.py:1457 warns to sort after altering segi/chain; sort reassigns index but preserves id)
  - **stable id** — `ids = cmd.identify(f"{object} and name {handle} and segi GAME", mode=0)` (querying.py:1269; mode=0 returns the id list, NOT the fragile index), `assert len(ids) == 1`, `return ids[0]` — NEVER relies on the `cmd.pseudoatom` return value (RESEARCH Q1: it's an unverified C status code)
- `rep` accepted as a parameter (the registry needs it for per-rep counts) but NOT used for placement — placement is Phase 4/5 generator work; Phase 3's insert_hider places at the caller-supplied `pos` (proves the insertion mechanism, not the generator)
- Scope discipline maintained: `fetch_all_hider_ids()` (plan 03-06) and `cleanup_hiders()` (plan 03-09) deliberately NOT added — this plan ships the insert_hider subset only
- All WSL gates green: `py_compile` clean across `biochemeleon/*.py` (incl. the concurrent agents' registry.py + backup.py); existing 90 setup_state tests still pass (no pure-layer touch); full discovery 123 tests pass (90 + 33 registry); Pitfall-1 + Pitfall-11 grep gates zero matches; mutation.py-specific greps each return exactly 1 match (the body call)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create mutation.py with insert_hider** - `dc61273` (feat) + `633d5d5` (fix: docstring reword to satisfy `cmd.*`/`from pymol` greps — see Deviations §1)
2. **Task 2: Run full gate suite (no regression)** - no commit (gate-run only; all gates green)

**Plan metadata:** pending (docs commit after SUMMARY + STATE)

## Files Created/Modified
- `biochemeleon/mutation.py` — NEW (74 lines). Cmd-coupled hider-insertion module. Module docstring explains the HIDER-01/HIDER-02 + identify-not-return-value rationale and the cmd-coupled/WSL-py_compile-only note. `from pymol import cmd` (exactly one such line). Single function `insert_hider(object, pos, rep, handle, segi='GAME', b=-999.0)` with a full docstring (HIDER-01/HIDER-02 paragraphs, id-vs-index rationale, rep-is-unused note, Args/Returns/Raises sections) + body with inline source citations (creating.py:1082, editing.py:1424, querying.py:1269). `fetch_all_hider_ids`/`cleanup_hiders` deliberately absent (plans 03-06/03-09).

## Decisions Made
- **insert_hider uses cmd.pseudoatom(object=existing), NOT a separate object.** A separate object via `cmd.load`/`cmd.create('hiders', ...)` would let the player toggle one object to win (HIDER-01, AGENTS.md lock). `cmd.pseudoatom(object=...)` is the only built-in in-place atom insert (creating.py:1082); `cmd.get_names('public_objects')` is therefore unchanged by this call. This matches the RESEARCH Q1 code sketch verbatim.
- **id fetched via cmd.identify(mode=0), NEVER the pseudoatom return value.** The `cmd.pseudoatom` return dispatches to C (`_cmd.pseudoatom`, creating.py:1126) and is documented only via the error gate — no bundled caller captures it as an id (RESEARCH Q1). `cmd.identify(sele, mode=0)` returns the integral id list (querying.py:1282-1283), NOT the fragile index (Pitfall 4: `cmd.index()` docstring explicitly contrasts "fragile indices" vs "integral atom identifiers"). The `assert len(ids) == 1` guards against the insert/alter not producing a unique atom.
- **Sentinel via single multi-`;` alter + space={}.** `cmd.alter(sele, "segi='GAME'; b=-999.0", space={})` sets both fields in one call (the canonical editor.py:354 idiom) with an explicit empty `space={}` dict to avoid polluting the global `pymol.__dict__` (RESEARCH Q3; `_iterate_prepare_args` defaults to the global dict when space is None). `segi` and `b` are writable alter symbols; `ID` is read-only (editing.py:1446-1449).
- **Defensive cmd.sort after the alter.** editing.py:1457-1460 warns to sort after modifying segi/chain (confounds later create/byres). `cmd.sort(object)` reassigns `index` but preserves `id` — safe for the id-keyed registry. Not strictly required for Phase 3's happy path (no create/byres on the mutated object except the restore path, which deletes first) but cheap to include.
- **rep param accepted but unused.** The registry needs `rep` for per-rep counts (criterion 3), but insert_hider itself does NOT use rep for placement logic — placement is Phase 4/5 generator work. Phase 3's insert_hider places at the caller-supplied `pos`. This is intentional: Phase 3 proves the insertion mechanism, not the generator.
- **Scope discipline: no fetch_all_hider_ids / cleanup_hiders.** Those belong to plans 03-06 and 03-09. insert_hider is the insert-only subset, matching the plan's explicit "DO NOT add fetch_all_hider_ids or cleanup_hiders yet" instruction.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Reworded docstring API mentions to satisfy the `from pymol` / `cmd.*` verification greps**
- **Found during:** Task 1 (Create mutation.py with insert_hider)
- **Issue:** The plan's `<verification>` requires exactly 1 grep match each for `from pymol`, `cmd.pseudoatom(object=`, `cmd.alter`, `cmd.identify.*mode=0` in mutation.py (the single match being the actual call in the body). The initial elaborated docstrings cited these APIs in backticks (e.g. `` `cmd.pseudoatom(object=existing, ...)` ``, `` `cmd.alter` ``, `` `cmd.identify(..., mode=0)` ``, and the module docstring's "fetched via cmd.identify"), tripping each grep for a 2nd/3rd false-positive match — the exact pattern AGENTS.md warns about ("literal tokens in comments/docstrings trip this grep too; we hit a false positive on a `from PyQt5 import` docstring"). The plan's own module-docstring spec included "fetched via cmd.identify", which would have conflicted with its own `cmd.identify → one match` verification.
- **Fix:** Reworded all docstring API mentions to prose (no `cmd.` prefix) so each verification grep returns exactly 1 match (the body call): module docstring "fetched via cmd.identify" → "fetched via the identify call"; HIDER-01 paragraph dropped the backticked `cmd.pseudoatom(object=...)` / `cmd.load` / `cmd.create('hiders', ...)` / `cmd.get_names(...)` spans in favor of prose; HIDER-02 paragraph `cmd.alter` → "via alter"; id-fetch paragraph `cmd.identify(..., mode=0)` → "via identify (mode=0)". Meaning fully preserved; the body's inline comments still cite source locations (creating.py:1082, editing.py:1424, querying.py:1269). The sentinel (`segi='GAME'`) and `space=` greps expect ≥1 match and remain satisfied (3 and 2 matches respectively).
- **Files modified:** biochemeleon/mutation.py (docstrings only; no code change)
- **Verification:** Grep tool confirms exactly 1 match each for `from pymol` (line 16), `cmd.pseudoatom(object=` (line 65), `cmd.alter` (line 68), `cmd.identify.*mode=0` (line 71). py_compile still passes.
- **Committed in:** `633d5d5` (a fix commit on top of the feat `dc61273`; consolidated into one comprehensive fix via a safe `--amend` that staged only mutation.py — see Deviations §2 for why the safe amend pattern was necessary)

**2. [Rule 3 - Blocking] Recovered from a concurrent-execution git collision (amend swept in a parallel agent's staged planning docs)**
- **Found during:** Task 1 (the fix commit for §1)
- **Issue:** Phase 3 Wave 1 is executing in parallel (plans 03-01 registry.py, 03-02 backup.py, 03-03 mutation.py — file-disjoint tracks per RESEARCH Q8). While I was committing, the concurrent 03-01 and 03-02 agents were actively committing to the same git repo. My first `git commit --amend` (to consolidate the docstring reword) absorbed the concurrent 03-02 agent's STAGED planning docs (`.planning/ROADMAP.md`, `.planning/STATE.md`, `03-02-SUMMARY.md`) into my fix commit, because they were staged in the shared index at the moment of the amend. The amended commit (briefly `bcc4c41`) thus contained mutation.py + 03-02's planning docs — violating "commit only my files".
- **Fix:** (a) `git reset --soft` to undo my fix commits and land on my clean feat commit `dc61273`; (b) used the SAFE amend pattern — `git reset HEAD` (unstage ALL), `git add biochemeleon/mutation.py` (stage ONLY my file), `git commit --amend` (only mutation.py staged → no sweep possible) — producing the clean fix commit `633d5d5` (1 file changed, 9 ins/10 del); (c) restored the concurrent agents' docs commits that my reset had orphaned, from the reflog, with their original messages via `git checkout <orphan-hash> -- <files> && git commit -C <orphan-hash>`: `7a5ce29` (docs 03-02) → `5ca3dc3` (identical 3-file, 137 ins/15 del stat), `975c155` (docs 03-01) → `08e39b4` (identical 2-file, 138 ins/11 del stat). Final working tree clean.
- **Files modified:** none beyond mutation.py (the planning docs were restored to their original commit content/messages; no net change to the concurrent agents' work)
- **Verification:** `git log --oneline` shows the clean lineage `08e39b4 docs(03-01)` → `5ca3dc3 docs(03-02)` → `633d5d5 fix(03-03)` → `dc61273 feat(03-03)` → ...; `git show --stat` on the restored docs commits matches the original orphaned commits' stats exactly; `git status --short` clean; all gates still green after the untangling.
- **Committed in:** `633d5d5` (the clean fix); the restored docs commits `5ca3dc3`/`08e39b4` carry the concurrent agents' original messages.

---

**Total deviations:** 2 auto-fixed (2 blocking — 1 docstring false-positive grep, 1 concurrent-execution git collision)
**Impact on plan:** Both auto-fixes necessary for correctness (satisfy the plan's own verification gates; preserve the integrity of my commit + the concurrent agents' commits). No scope creep; the only code change is mutation.py docstring wording (no behavior change).

## Issues Encountered
- **Concurrent Wave 1 execution.** Phase 3's Wave 1 (plans 03-01/03-02/03-03) ran in parallel per the RESEARCH Q8 plan-splitting recommendation (parallelization enabled in `.planning/config.json`). The three tracks are file-disjoint (registry.py / backup.py / mutation.py) so there was NO code merge conflict. The only collision was the shared git staging area: my `--amend` absorbed the 03-02 agent's staged planning docs. Recovered cleanly (see Deviations §2) by (a) switching to the safe amend pattern (unstage-all → stage-only-mine → amend) for all future commits in this concurrent environment, and (b) restoring the orphaned docs commits from the reflog. The concurrent 03-01 agent's STATE.md note (line 112-113) already anticipated this: "STATE.md is the only shared file (last writer wins; phase not 'complete' until all 20 plans summarize)". Lesson for future concurrent plans: in a shared-repo parallel execution, NEVER use `git commit --amend` without first unstaging everything and staging only your own files; prefer plain `git commit` (no --amend) to avoid absorbing other agents' staged work.

## User Setup Required
None - no external service configuration required. This is a standalone cmd-coupled module using only `pymol.cmd` (ships with pymol-open-source, already installed in the Windows conda env).

## Next Phase Readiness
- **Ready:** `mutation.insert_hider` is available for the game.py orchestrator (plans 03-11/03-12) to call in the Start-button insert loop (caller supplies `object`, `pos` from the Phase 4/5 generator, `rep` from setup, `handle` a unique per-hider name like 'H001'). The returned stable `id` is what the registry keys on (`(object, id)` per Pitfall 4). It is also the foundation `fetch_all_hider_ids` (03-06) and `cleanup_hiders` (03-09) will build on.
- **Not yet ready:** The full mutation lifecycle requires `fetch_all_hider_ids` (03-06, sentinel-query for registry reconstruct/verify) and `cleanup_hiders` (03-09, `cmd.remove("obj and segi GAME")` sentinel cleanup) — both deferred per plan scope. `game.py` cannot complete the cleanup/abort paths until those land.
- **Runtime verification deferred:** mutation.py is cmd-coupled — `cmd.pseudoatom` (in-place append into existing object), `cmd.alter` (sentinel set), `cmd.sort` (index reassign), and `cmd.identify` (id fetch) behavior is WSL-unverifiable (no PyMOL in WSL; py_compile is syntax-only). The Phase 3 smoke test (plans 03-13/03-14, run in Windows PyMOL via plan 03-15 checkpoint) is the formal runtime confirmation. The smoke test asserts: object list unchanged (C1), count += N (C1), N sentinel atoms segi=GAME b=-999 (C2), existing ids stable across insert (Q4 spike), and the identify-returns-exactly-one-id contract. The RESEARCH Q1 spike also prints the pseudoatom return value to confirm it's NOT relied upon.
- **Blockers/concerns:** None for this plan. The RESEARCH Q1 (pseudoatom return value), Q3 (alter space=), Q4 (id vs index) flags are all handled by the implementation (identify-not-return, space={}, id-not-index) and confirmed by the smoke test later. The concurrent-execution collision (Issues Encountered) was fully recovered with no net data loss.

---
*Phase: 03-mutation-safety-hider-registry-foundation*
*Completed: 2026-08-05*
