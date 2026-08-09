# Phase 5 Gap Closure Brief — Ribbon Rep Support (Option B)

**Scope:** ribbon-only fix (gap #3 from 05-05 partial approval). Do NOT include alt-conf (gap #1, deferred to Phase 11) or line/stick IndexError (gap #2, already fixed via 05-07).

## The gap

When a user selects `ribbon` in `per_rep` and clicks Start, the game inserts cartoon hiders but shows them in the **cartoon** representation, not ribbon. The show call is hardcoded to `'cartoon'`. The function never receives `rep`.

This is gap #3 from the 05-05 partial approval:
- Gap #1 (alt-conf cartoon, disconnected on 1ubq) → DEFERRED to Phase 11 (out of scope)
- Gap #2 (line/stick IndexError) → FIXED via 05-07 (already cherry-picked)
- Gap #3 (ribbon unsupported) → THIS BRIEF

## Root cause (single line)

`biochemeleon/mutation.py` line 478 in `insert_cartoon_hider`:
```python
cmd.show('cartoon', _id_sele(all_game_ids))  # viewing.py:491
```
`'cartoon'` is hardcoded. When `rep='ribbon'` is the requested rep, cartoon is shown instead. The function never receives `rep`.

## The fix (3 small changes, ALL in mutation.py — NO __init__.py change needed)

### Change 1 — `insert_cartoon_hider` signature (add `rep` param)

Current signature (terminal-extension version, ~line 297):
```python
def insert_cartoon_hider(object, chain, terminus_resi, is_c_terminus, handle, ...):
```
Add `rep='cartoon'` parameter.

### Change 2 — `insert_cartoon_hider` show call (line 478)

```python
# BEFORE:
cmd.show('cartoon', _id_sele(all_game_ids))
# AFTER:
cmd.show(rep, _id_sele(all_game_ids))
```

### Change 3 — `insert_hider_for_rep` dispatcher (lines 530-535)

```python
# BEFORE:
elif rep in ('cartoon', 'ribbon'):
    chain, terminus_resi, is_c_terminus = payload
    return insert_cartoon_hider(object, chain=chain,
                                terminus_resi=terminus_resi,
                                is_c_terminus=is_c_terminus,
                                handle=handle)
# AFTER:
elif rep in ('cartoon', 'ribbon'):
    chain, terminus_resi, is_c_terminus = payload
    return insert_cartoon_hider(object, chain=chain,
                                terminus_resi=terminus_resi,
                                is_c_terminus=is_c_terminus,
                                handle=handle, rep=rep)
```

**No `__init__.py` change needed** — the payload `(chain, terminus_resi, is_c_terminus)` already travels with the rep via `hider_specs.append((term, rep))` (line 177); `game.start`'s loop passes `rep` to `insert_hider_for_rep`, which now forwards it.

## Why this is low-risk (headless-verifiable, no GUI-vs-headless trap)

- It's just a `cmd.show` call — no `cmd.create`, no state manipulation, no coordinate changes. The `auto_zoom`/multi-state/coord-corruption class of bugs that killed the alt-conf attempt CANNOT occur here.
- Headless smoke CAN verify: `count_atoms("obj and segi GAME and rep ribbon") > 0` after inserting a ribbon hider.
- The reverted 05-08 already proved `cmd.show(rep, ...)` works (it was in the alt-conf version that passed headless smoke).

## Smoke verification (extend smoke/phase5_smoke.py)

Add a ribbon check after the existing cartoon check:
```python
# Ribbon: insert with rep='ribbon', verify it shows in ribbon (not cartoon)
mutation.cleanup_hiders(obj)
# ... insert a cartoon hider with rep='ribbon' ...
check("ribbon: GAME CA in rep ribbon",
      cmd.count_atoms("%s and segi GAME and rep ribbon" % obj) > 0)
check("ribbon: NOT in rep cartoon (rep-specific)",
      cmd.count_atoms("%s and segi GAME and rep cartoon" % obj) == 0)
mutation.cleanup_hiders(obj)
```

## Constraints

- `space={}` hygienic; `ID` uppercase in iterate; `b < 0` selector (NOT `b -999`); `segi GAME` cleanup; pure `pymol.cmd.*` in smoke; WSL gates: py_compile + tests + Pitfall-1=0 + exec_=allowed-only.
- Do NOT touch `insert_line_stick_hider`, `insert_hider`, `collapse_to_single_state`, `free_nterminal_valence`, or `__init__.py` — this is a 1-file fix (mutation.py) + smoke.
- Do NOT include alt-conf / segment replication / pick_segments / Phase 11 work — that's deferred, separate.

## Expected outcome

- 1-task gap plan: `05-09-PLAN.md` (ribbon support)
- Files modified: `biochemeleon/mutation.py` (3 small changes) + `smoke/phase5_smoke.py` (ribbon check)
- Headless smoke ALL PASSED (existing + new ribbon checks)
- Closes Phase 5 gap #3; Phase 5 then closes as PARTIAL (only alt-conf/cosmetic-disconnection remains, deferred to Phase 11)

## Context files to reference

- `biochemeleon/mutation.py` — `insert_cartoon_hider` (signature ~line 297, show call line 478), `insert_hider_for_rep` dispatcher (lines 482-537)
- `smoke/phase5_smoke.py` — existing cartoon check (extend with ribbon check)
- `biochemeleon/setup_state.py` — `GAME_REPS` (includes 'ribbon')
- `AGENTS.md` — domain rules (space=, ID uppercase, b<0, segi GAME)
- `.planning/phases/05-line-stick-and-cartoon-generators/05-05-SUMMARY.md` — the 3 gaps that triggered closure (this closes #3)
