# Phase 20: Persistence (Combined-PDB + .bcm JSON) — VMD/Tcl Mechanics Research

**Researched:** 2026-09-26
**Domain:** zip mechanics, hand-rolled JSON (Tcl 8.5), combined-PDB round-trip, reconcile-by-index, temp/paths/atomicity, headless testability — all inside VMD 1.9.3 (Windows) Tcl 8.5.6
**Confidence:** HIGH — every load-bearing conclusion below is PROBE-VERIFIED by headless VMD runs on this machine today. Probe scripts + fixtures live in `tmp/p20probe/` (gitignored); raw evidence excerpts are embedded per finding. Negative results (no zlib; `tar -a` produces a tar, not a zip; beta -999 writepdb overflow) are empirical, not inferred.

**Companion docs:** `20-RESEARCH-v1-carryover-format.md` (v1 `.bcmz`/`.bcm` format + JSON schema carryover), `20-RESEARCH-integration-gui.md` (GUI seams). This doc owns the VMD/Tcl mechanics + probes.

---

## Executive Summary

**All four hard mechanics are proven feasible with ZERO new dependencies, by headless probes:**

1. **ZIP: use Windows bsdtar (`System32\tar.exe`, 3.8.4 — same OS-shipped class as Phase 21's curl.exe) with the EXPLICIT format flag: `exec tar --format zip -c -f <out.bcmz> -C <staging> game.pdb game.bcm`.** It produces a real PK zip (magic `504b0304`, DEFLATE: 160 KB → 26.6 KB) in ~60-90 ms, with flat member names and rc=0. TWO traps verified: `tar -a` does **NOT** infer zip from the `.bcmz` extension (unknown suffix → silently writes a ustar **tar**, magic `67616d65`), and absolute-path members strip the drive letter, exit rc=1, and store a directory tree. Extraction is `exec tar -xf <x.bcmz> -C <dir>` (format auto-detected, ~60 ms, overwrites existing files). Fallback: PowerShell `Compress-Archive`/`Expand-Archive` (works via a temp-`.zip`-name + `file rename`; refuses `.bcmz` natively; ~4-6 s startup). Last resort: a pure-Tcl STORE-method zip writer/reader (proven byte-identical through tar.exe AND PowerShell, ~90 lines + a CRC-32 verified against Python zlib).

2. **JSON: a ~170-line hand-rolled emit/parse pair (`tmp/p20probe/bcm_json.tcl`, liftable to `vmd/lib/`) round-trips 100% of adversarial cases in VMD's Tcl 8.5.6** — Windows backslash paths, spaces, embedded quotes, embedded newlines, UTF-8 (β, ć), numeric-looking strings, empty lists/dicts, booleans as 0/1, floats. Emit is **schema-typed** (S/I/F/B scalars + closed `D` + open `DO` + record-list `L` types) because Tcl has no type tags (a generic auto-typer misclassifies `C:/Program Files/x.pdb` as a dict). Parse is generic recursive descent (~120 lines). 50-record sidecar: emit 51 ms, parse 32 ms. All corrupt/hand-mangled inputs produce clean catchable errors.

3. **Reload: `mol new <game.pdb>` re-finds every hider via the existing `fetch_hider_indices`** (`resname GAM and beta < 0`), atom order survives **byte-for-byte** (names/resids/coords identical; coord drift = 0), and bonds re-derive deterministically (total bond count identical across the round trip: 1132 → 1132).

4. **THE critical new defect found — beta `-999` writepdb overflow.** VMD's own `writepdb` formats beta `%6.2f`; the sentinel -999 becomes `-999.00` (7 chars) which overflows the 6-col beta field, shifting segid/element: reload reads `element=X` (blend radius broken — the probe-J defect class) and `segid=GAM`. **Fix (probe-verified): pre-clamp hider beta to -99.9 before writepdb, restore -999 after** — produces a clean 78-char line, `element=C` + `segid=GAME` survive, and `beta < 0` still selects everything (float32 wobble `-99.9000015258789` is still < 0; idempotent across repeated saves). The SAVE path is the first flow that ever writepdb's a molecule already carrying -999 hiders — this defect was unreachable before Phase 20.

**Primary recommendation:** implement save as *stage-dir → two files (writepdb with beta pre-clamp + `bcm_json::write_bcm`) → `tar --format zip` → atomic `file rename -force`*, and load as *`tar -xf` into a fresh staging dir → integrity gates (tar rc + PK magic + `.bcm` magic/schema) → `mol new` → `fetch_hider_indices` → registry reconstruct → reconcile-by-index (straight set-intersection) → replay found-status*. The full cycle runs headless (probe_z6: 20/20 mechanics asserts PASS, ~130 ms of zip work total).

**User-approval flag (explicitly requested by the task):** `tar.exe` and `powershell.exe` are OS-shipped executables, not libraries — arguably outside the "zero external deps" claim's letter. Phase 21 already crossed this exact bridge with `curl.exe` (System32) and it was accepted; surface tar.exe at the Phase 20 human-verify checkpoint the same way. The pure-Tcl STORE zip exists as the proven no-exec fallback if approval is refused.

---

## Probe Log (per unknown)

All probes: `tmp/p20probe/probe_*.tcl`, run via `bash -ic "vmd -dispdev text -e tmp/p20probe/<script> -eofexit" < /dev/null` from the repo root (VMD cwd = `C:/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon`). Module under test: `tmp/p20probe/bcm_json.tcl` (liftable to `vmd/lib/bcm_json.tcl`).

### Unknown 1 — ZIP create/extract, zero deps

**1a. Does VMD's Tcl have zlib?** — `probe_z1_caps.tcl`
```
P1>> info commands zlib = ''
P1>> compression-ish packages: ()
P1>> full package list = (Tcl http msgcat platform tcl::tommath tcltest)
```
**Verdict: NO zlib, no zip/compression package** (matches Phase 21's `package names` census).

**1b. tar.exe create/extract** — `probe_z1_caps.tcl` + `probe_z1b_caps.tcl`
```
P1>> tar version line: bsdtar 3.8.4 - libarchive 3.8.4 zlib/1.2.5.f-ipp cng/2.0 libb2/bundled
P1>> tar -a -c -f <abs>.bcmz <abs-files> rc=1 msg='tar.exe: Removing leading drive letter from member names'
P1>> tar -tf rc=0 listing=(Users/nglok/AppData/Local/Temp/p20probe_z1/game.pdb ...)   <- DIRECTORY TREE members!
P1b>> tar -a -c -f <out> -C <stage> game.pdb game.bcm rc=0 size=3072
P1b>> magic=67616d65   <-- 'game' = ustar name field = TAR, NOT ZIP (unknown .bcmz suffix)
P1b>> tar --format zip -c -f <out> -C <stage> game.pdb game.bcm rc=0 size=452
P1b>> explicit magic=504b0304    <-- REAL ZIP
P1b>> tar -xf <out> -C "extract dir with spaces" rc=0 ; byte fidelity = IDENTICAL
P1b>> re-create over existing rc=0 ; extract over existing rc=0 (both overwrite)
P1b>> create spaced-member rc=0 ; members=(my game.bcm ...)
P1b>> zip create 1000-atom pdb+json: rc=0 time=62 ms ; extract 61 ms
```
**Verdict: tar.exe works with the exact call shape `exec tar --format zip -c -f <out.bcmz> -C <staging> game.pdb game.bcm`.** `--format zip` output is DEFLATE (z2: 160,000 B pdb → 26,596 B archive, 90 ms). Corrupt archive: `tar -tf/-xf` rc=1 with `Unrecognized archive format` (clean error surface); truncated zip also rc=1 (it partially lists first — trust the rc, not the listing). Availability: bsdtar ships Windows 10 1803+ (same class as curl.exe, Phase 21-verified).

**1c. PowerShell fallback** — `probe_z2_pwsh.tcl` + `probe_z2b_pwsh.tcl`
```
P2>> pwsh Compress-Archive: rc=1 time=5976 ms msg='Compress-Archive : .bcmz is not a supported archive file format. .zip is the only supported archive file format.'
P2b>> pwsh Compress->.zip: rc=0 time=5009 ms size=26664 ; rename .zip->.bcmz rc=0 ; magic=504b0304
P2b>> pwsh Expand from .zip: rc=0 time=4392 ms pdb=1 bcm=1
P2b>> tar -xf of PWSH-zip: rc=0 ; byte fidelity = IDENTICAL
P2b>> pwsh Expand garbage: rc=1 msg-first='New-Object : ... "Central Directory corrupt."'
```
**Verdict: works but MUST write to a `.zip` temp name then `file rename -force`** (Compress/Expand validate the extension). ~4-6 s per call (pwsh startup) — ~50-70× slower than tar. Cross-tool interop both directions (tar reads pwsh zips ✓).

**1d. Pure-Tcl STORE zip (last resort)** — `probe_z5b_store.tcl` (layout: APPNOTE LFH 30 + CD 46 + EOCD 22)
```
P5b>> crc32 160KB: ~300 ms value=44749525  <-- EXACT match with Python zlib.crc32 of the same CRLF bytes
P5b>> tcl STORE write: 321 ms size=160222 (STORE = uncompressed, ~input size)
P5b>> tcl STORE read: 42 ms ; self fidelity = IDENTICAL
P5b>> tar -tf of tcl-store zip: rc=0 members=(game.pdb game.bcm) ; tar -xf: byte-fidelity=IDENTICAL
P5b>> pwsh Expand of tcl-store zip: rc=0 byte-fidelity=IDENTICAL   (Explorer-class readers OK)
```
**Verdict: fully viable fallback.** ~90 lines (writer+reader+CRC table). Two Tcl 8.5 traps found while building it (see Pitfalls): counted `binary format` takes ONE list arg, and nested parens inside array subscripts fail in `expr`.

**1e. Decision matrix**

| Criterion | tar --format zip (PRIMARY) | PowerShell + .zip-rename (FALLBACK) | Pure-Tcl STORE (LAST RESORT) |
|---|---|---|---|
| Real PK zip (Explorer-readable) | YES, DEFLATE | YES, DEFLATE | YES, STORE (any tool reads it) |
| Speed (160 KB) | 60-90 ms | ~5,000 ms | ~320 ms write + ~300 ms CRC |
| Reliability/exit codes | rc=0/1 + clean msg | rc=0/1 + verbose msg | pure Tcl (no exit codes; catch) |
| Error surface (corrupt input) | `Unrecognized archive format`, rc=1 | `Central Directory corrupt`, rc=1 | own parser (we only read our own) |
| Windows availability | Win 10 1803+ (System32) | Win 7+ (powershell.exe) | any VMD |
| Quoting hazards | none (list-form exec, `-C` + relative names) | path quoting into `-Command` (space-sensitive) | none |
| Code weight | 1 exec line per direction | ~2 lines + rename dance | ~90 lines vendored |
| New dependency? | OS executable (curl precedent, Phase 21) | OS executable | none |

**Recommendation: tar --format zip primary; PowerShell fallback; pure-Tcl STORE documented (vendor only if the checkpoint rejects OS executables).** Extraction always `tar -xf` (reads all three producer variants).

### Unknown 2 — Hand-rolled JSON emit/parse

**Design** (`tmp/p20probe/bcm_json.tcl`, ~170 lines, Tcl 8.5-only, brace-balanced comments):

- **Emit is schema-typed** — `emit_object {value schema}` walks a schema dict: scalar types `S` (escaped string) / `I` / `F` / `B` (bool as raw 0/1), `D` closed sub-dict, `DO` open dict (arbitrary keys, e.g. `per_rep` rep-name → count), `L` list of records each matching a sub-dict. Extra/missing keys ERROR (schema drift fails loudly). Why typed: Tcl has no type tags — `C:/Program Files/x.pdb` is also a valid 2-pair dict, so a generic auto-typer misclassifies real paths (verified reasoning; the closed-vs-open dict distinction was forced by probe: `per_rep {VDW 10}` against an empty closed sub-schema errored `emit_object: unexpected key 'VDW' not in schema` until `DO` was added).
- **Escaping (one-pass `string map`):** `\\ → \\\\`, `" → \"`, newline → `\n`, CR → `\r`, tab → `\t`, backspace/formfeed; remaining C0 controls → `\u00XX` defensively (regexp-gated fast path). `string map` is single-pass so inserted backslashes are never reprocessed — backslash doubling is safe (probe: `C:\odd\\path` and `C:\new<LF>line` both round-trip).
- **Parse is generic recursive descent** (`_parse_value/_parse_object/_parse_array/_parse_string/_skip_ws`): object→dict, array→list, numbers kept as strings, `true/false→1/0`, `null→""`, `\uXXXX` decoded (surrogate-pair aware, defensive — never emitted). File I/O via `fconfigure -encoding utf-8` both directions.
- **Validation:** `parse_bcm` checks root-is-object + required top-level keys; emit-side schema checks catch drift at write time.

**Round-trip evidence** — `probe_z3_json.tcl` (+ z3b/c/d):
```
P3>> top-level round-trip fails=0        (12/12 keys incl. records + per_rep + setup)
P3>> records field-compare fails=0
P3>> OK (S) 'C:\Users\nglok\Desktop\1ubq.pdb'      P3>> OK (S) 'C:/Program Files (x86)/VMD/x y z.pdb'
P3>> OK (S) 'he said "hi" \ and / or'              P3>> OK (S) 'line1\nline2\ttab'
P3>> OK (S) 'molećule'   P3>> OK (S) 'β-factor'    P3>> OK (S) 'C:\odd\\path'
P3>> OK (S) '9001'       P3>> OK (S) ''            P3>> OK (S) 'C:<LF>ew<LF>line'
P3>> OK (I) 117898 / 0 / -999   P3>> OK (F) -999.0 / 1.5   P3>> OK (B) 0 / 1
P3d>> empty-state re-emit identical = YES (empty records [], empty per_rep {})
P3d>> 50-record sidecar: emit 51 ms parse 32 ms
P3>> utf8 magic='mβl' kind='ćk' target='a<LF>b'    (through FILE both directions)
```
**Error surfaces** (z3c — all caught, never crash/hang):
```
'{{not json'        -> json: expected object key at offset 1
'{"magic": }'       -> json: bad value at offset 10
'{"magic": "x",}'   -> json: expected object key at offset 14
'not json at all'   -> json: bad value at offset 0
'{}' / '[]'         -> bcm: missing key 'magic' (schema gate)
'{"magic": true}'   -> parses, magic=1 (true→1)
emit rogue key      -> emit_object: unexpected key 'rogue' not in schema
emit missing key    -> emit_object: missing key 'extra' (schema-constrained)
```
**Concrete artifact** — `tmp/p20probe/sample_game.bcm` (1 line, 899 B):
```json
{"magic": "BIOCHEMELEON-BCM", "schema_version": 1, "kind": "checkpoint", "target_name": "1k8p", "original_pdb_path": "C:/Users/nglok/Desktop/WORKDIR/molmdl/bioCHEMeleon/vmd/data/demos/1k8p.pdb", "timer_epoch": 1769400000, "timer_elapsed_final": 42.0, "reveal_count": 1, "hint_count": 2, "per_rep": {"VDW": 10}, "records": [{"index": 555, "rep": "VDW", "status": "found"}, ...], "setup": {"hider_count": 10, "mode": "random", "seed": "", "lock_scene": 0}}
```
(Exact field set/names stay the v1-carryover researcher's + planner's call; this is the mechanically-proven envelope.)

### Unknown 3 — Combined-PDB round-trip

**THE OVERFLOW (probe_z4_roundtrip.tcl):** built a real game molecule (1k8p + 10 placeholder hiders via the shipped `mutation.tcl` flow), tagged sentinels (-999), then `$all writepdb` — the SAVE-shaped write:
```
P4>> raw hider line (len 79):   <-- 78 expected; 1-char overflow
     'ATOM    557  G02 GAM G9001      -2.667   7.970  29.101  1.00-999.00      GAME C'
P4>>   beta cols 61-66 = '-999.0'      (reads back OK)
P4>>   segid cols 73-76 = ' GAM'       (CORRUPTED -> reload reads segid 'GAM')
P4>>   element cols 77-78 = 'E '       (CORRUPTED -> reload reads element 'X' = radius 1.50!)
P4>> reload save999: element=X X X X X X X X X X segid=GAM GAM ... (blend field broken)
P4>> -99.9 hider line (len 78): 'ATOM    557  G02 GAM G9001      -2.667   7.970  29.101  1.00-99.90      GAME C'
P4>>   beta='-99.90' segid='GAME' element=' C'   (all clean)
P4>> reload save9999: fetch n=10 ; element=C C C C C C C C C C ; segid=GAME GAME ... ; beta(first)=-99.9000015258789
```
**Verdict:** SAVE must pre-clamp hider beta to -99.9 (`$hsel set beta -99.9` → writepdb → `set beta -999` restore). The restore keeps the live molecule's canonical sentinel value; skipping the restore is also safe (selector is `beta < 0`). Real atoms are safe on all bundled demos (z4b: max beta 184.11 on 5e54 — overflow needs >999.99). Residue rounds: same clamp applies to the CA-only beta set (z8).

**Field survival** (writepdb → mol new, probe-verified):
- `beta < 0` sentinel: survives (as -99.9; still selects). `resname GAM`: survives (cols 18-20 untouched). `segid GAME`: survives with the clamp (corrupted without it). `element`: survives with the clamp (`C`; residue atoms `N C O` set survives — z8: `elem-set=C N O`). `user`/`user2`: LOST on writepdb (Phase 15 Pitfall 7 re-confirmed) — the .bcm replays them (probe_z6 PASS: `user2=1 on exactly the 3 replayed found hiders`).
- Precision: hider max coord drift pre/post save = **0** (writepdb `%8.3f` + re-read is lossless for already-3-decimal coords).

**Frames:** every `mol new` of our single-model files yields `frames=1` (z4/z4b/z8). The game molecule is ALWAYS single-frame (17.2 collapse discipline; 1znf ships 37 frames → writepdb+reload collapse verified again in z8: `frames=37 → collapsed frames=1`). Keep the `$sel frame 0` pinning discipline before coordinate reads (17.2-04 rule; all probes pin and drift=0 confirms determinism).

**Bonds:** `write_combined_pdb`/`writepdb` emit NO CONECT → VMD re-bonds by distance at load. Distance bonding is **deterministic**: total bond count identical across the save round trip (z4b: 1132 → 1132, per-atom `numbonds` lists string-equal). Note (pre-existing, Phase 15): the combined molecule has FEWER bonds than the pristine original (1k8p 1164 → combined 1132 — CONECT-derived bonds lost at first mutate); cosmetic for the Lines rep, irrelevant to DynamicBonds (computes by distance) and to picks (index-keyed). Placeholder hiders are mostly unbonded after reload (`numbonds=0 0 0 0 0 2 0 0 0 0`) — expected: only the bonded tier guarantees `numbonds >= 1`.

### Unknown 4 — Reconcile-by-index

```
P4>> index stability: all-names identical = YES ; all-resid identical = YES
P4>> hider name order identical = YES ; hider max coord drift = 0
P6>> reconcile: every .bcm index matches a sentinel (mismatch=0)
```
**Verdict: atom order survives writepdb→mol new byte-for-byte** (name sequence, resid sequence, and coordinates identical; hiders stay contiguous at indices `orig_n..N-1`). Reconciliation is therefore a **straight set-intersection VALIDATION, not a remap**: every `.bcm` record index must exist in the freshly fetched sentinel set (`mismatch == 0` gate); then replay rep/status per record (`set_rep` / `mark_found` + `user2 1`). Any mismatch = corrupt/foreign file → refuse. Molids change on reload (monotonic, z6: molid 1 → 2) — established Phase 15; the registry is index-keyed so this is invisible to reconciliation.

### Unknown 5 — Temp dir + paths

```
P1>> TEMP=C:\Users\nglok\AppData\Local\Temp   (VMD $env(TEMP) — Windows path, forward-slash file joins fine)
P1>> file tempfile supported = 1 (error)  <-- NOT in Tcl 8.5: "bad option "tempfile": must be atime, attributes, ..."
P1b>> -C "extract dir with spaces" works ; .bcmz named "my puzzle.bcmz" works ; spaced member "my game.bcm" works
```
**Verdict:** staging lives under `$env(TEMP)` (the shipped `mutate` already uses it). `file tempfile` does NOT exist in Tcl 8.5 — use the probe pattern: `file delete -force $stage; file mkdir $stage` with a `clock clicks`/pid-unique name. All runtime paths inside VMD are already Windows paths (tk_getSaveFile returns them; `$env(TEMP)` is one); the WSL→Windows conversion (`demos::to_vmd_path`) is a probe-harness/staging concern only — no save-path code needs it.

### Unknown 6 — Atomicity

```
P1>> file rename -force over existing: rc=0 b-contains=AAA (overwrite works)
P1>> file rename -force staging->final: rc=0 final-contains=NEW staged-gone=1
P1b>> tar re-create over existing .bcmz rc=0 ; extract over existing files rc=0 (overwrites)
```
**Verdict:** write-then-rename is safe on Windows VMD (`file rename -force` overwrites; Phase 21's probeE reached the same conclusion for the cache). Recommended shape: build BOTH members in one staging dir under `$env(TEMP)`, zip to `<final>.part` (or directly stage it), then `file rename -force` into the user-chosen target. Same-directory rename is the atomic case; if the target dir differs from the staging volume, zip the `.part` file into the TARGET dir's parent (tar's `-f` output can land anywhere) so the final rename is same-dir. Crash-mid-write leaves either the old `.bcmz` or a `.part` orphan (harmless, cleaned on next save).

### Unknown 7 — Headless testability

**Proven:** the ENTIRE cycle runs under `vmd -dispdev text -e ... -eofexit` (probe_z6: save → zip → `mol delete` + `registry::reset` → extract → `mol new` → parse → reconcile → 20 asserts, all mechanics PASS; z8 residue variant PASS). No Tk anywhere in the flow; paths are passed directly (no dialogs). CANNOT be headless-tested → GUI checkpoint: `tk_getSaveFile`/`tk_getOpenFile` dialog behavior (filters `*.bcmz`, default extension append), the Save-checkpoint / Import / Generate&Export buttons' wiring, and any error `tk_messageBox` surfacing.

---

## Don't Hand-Roll / Use As-Is

| Problem | Don't build | Use | Why |
|---|---|---|---|
| Zip container | custom container or `tar -a` | `tar --format zip` (real PK zip) | `-a` mis-infers `.bcmz` → tar (magic-verified); Explorer/manual-unzip must work |
| Zip member naming | absolute paths | `-C <staging>` + relative names | drive-letter strip + rc=1 + directory-tree members (verified) |
| JSON | auto-typing emitter / regex parsing | the schema-typed emit + recursive-descent parse | Tcl has no type tags; paths-are-dicts misclassification; escaping edge cases all probed |
| Sentinel writeback | trusting writepdb with -999 | pre-clamp -99.9 → writepdb → restore | %6.2f overflow corrupts segid+element (verified 79-char line) |
| Index recovery | re-mapping tables | straight set-intersection (order is byte-stable) | probe: names/resids/coords identical pre/post |
| Bond restoration | bond list serialization | nothing — distance re-bonding is deterministic | 1132→1132 identical |
| Uniqueness | `file tempfile` | `clock clicks`-unique staging dir | `file tempfile` absent in 8.5 (verified) |

## Common Pitfalls (new, probe-verified this session)

1. **`tar -a` is NOT zip for `.bcmz`** — bsdtar's suffix table doesn't know the extension; it silently writes ustar. Always `--format zip`.
2. **Absolute member paths in tar** — drive-letter stripped, rc=1, members stored as directory trees; extraction then lands in a subdirectory. Always `-C staging` + bare names.
3. **beta -999 writepdb overflow** — 79-char lines; reload degrades element to X (radius 1.50) + segid to GAM. Pre-clamp -99.9.
4. **`regexp -start` + `^`** — `^` does NOT match at the `-start` offset (only at true string start); anchor via `string range` substring instead. (Broke every bare-number JSON parse until fixed.)
5. **Unbalanced braces in Tcl comments** — comments inside proc bodies participate in brace matching; one `;# consume {` kills every proc defined after it in the same file ("missing close-brace: possible unbalanced brace in comment").
6. **Nested parens in array subscripts fail in `expr`** — `$tbl(($a ^ $b) & 0xFF)` → "unbalanced close paren"; compute the index into an intermediate variable first. (Broke CRC-32.)
7. **Counted `binary format` takes ONE list argument** — `binary format s5 20 0 0 0 0` errors ("number of elements in list does not match count"); use `binary format s5 {20 0 0 0 0}`.
8. **Uncaught errors in `-e` scripts drop VMD into its interactive prompt where `-eofexit` does NOT reliably exit** (verified 120 s hang once); a script-abort can also be silent (error text interleaves with VMD's console echo of top-level results — don't grep-filter probe output, tee it). Probe discipline: catch everything, small independent scripts.
9. **`[info script]` is EMPTY at top level under `vmd -e`** (VMD evals, doesn't source) — source paths must be cwd-relative or absolute; can't be derived from `[info script]` in a top-level probe.
10. **PowerShell cmdlets validate extensions** — Compress/Expand-Archive refuse `.bcmz`; temp-`.zip` + `file rename -force` required.

## Integration gaps found (for the planner)

- **`registry.tcl` has NO bulk accessor and NO rep getter** (`status_all` is phantom; only `status_of`/`set_rep` per index). The .bcm writer needs either a tiny pure accessor (e.g. `records_snapshot {}` returning `_records` — 3 lines, pure, tcltest-able) or the game layer must derive records from its own per_rep/tier bookkeeping (what probe_z6 did).
- `hiders::mark_found_visual` (user2 + rep re-assert) is the replay primitive for found hiders post-load — z6 verified `user2 1` lands on exactly the replayed indices; wire the real call through it (integration researcher's seam).
- The writepdb output uses CRLF on Windows (Phase 21 census; z5b fixture 160,000 B = 158,000 + 2,000 CR) — `write_combined_pdb`'s read-back splice already tolerates it; any new line-splicing code must too.

## Timing budget (all measured)

| Operation | Time |
|---|---|
| writepdb 565-atom game.pdb | < 50 ms (45 KB) |
| .bcm emit (10 records) | < 5 ms (899 B) |
| tar --format zip create | 60-90 ms |
| tar -xf extract | 60 ms |
| mol new combined.pdb | ~50 ms (z6 total load < 150 ms) |
| JSON parse 10 records | < 5 ms (50 records: 32 ms) |
| **Whole save / whole load** | **~150 ms / ~120 ms** (vs the 30 s generate budget — negligible) |

## Open Questions (non-blocking)

1. **Deflate-vs-store for the shipped .bcmz** — `--format zip` gives DEFLATE (6× on text PDBs); STORE (pure-Tcl fallback) is ~1×. No decision needed unless file-size matters for sharing; both are universally readable.
2. **Restore-vs-leave the -999 sentinel after save** — restore keeps the AGENTS.md sentinel constant literal in the live molecule (recommended; 2 lines); leaving -99.9 is equally functional. Planner's one-line call.
3. **`.bcm` field set/naming** — mechanics doc proves the envelope (magic/schema/kind/records/per_rep/timer/setup round-trip); exact schema is the v1-carryover + integration researchers' deliverable.
4. **`original_pdb_path` semantics on import** — the .bcm carries it (round-trips), but reload NEVER needs it (the combined PDB is self-contained); it's informational (v1 used it for cleanup context). Integration researcher's seam.

## Sources

### Primary (HIGH — probe evidence, this session)
- `tmp/p20probe/probe_z1_caps.tcl`, `probe_z1b_caps.tcl` — capability census, tar create/extract/overwrite/error surfaces, rename atomicity
- `tmp/p20probe/probe_z2_pwsh.tcl`, `probe_z2b_pwsh.tcl` — PowerShell fallback + extension refusal + interop
- `tmp/p20probe/bcm_json.tcl` + `probe_z3_json.tcl`/`z3b`/`z3c`/`z3d` — JSON module + round-trip/error/timing evidence
- `tmp/p20probe/probe_z4_roundtrip.tcl`, `probe_z4b_bonds.tcl` — overflow, field survival, index stability, bonds, betas
- `tmp/p20probe/probe_z5b_store.tcl` (+ z5c/z5d/z5e isolations) — pure-Tcl zip + Tcl 8.5 expr/binary traps
- `tmp/p20probe/probe_z6_e2e.tcl` — full save→zip→destroy→extract→load→reconcile cycle
- `tmp/p20probe/probe_z7_sample.tcl` + `sample_game.bcm` — concrete .bcm artifact
- `tmp/p20probe/probe_z8_residue.tcl` — residue-round save round trip
- Python zlib cross-check (WSL) for CRC-32: `44749525` exact match

### Secondary (HIGH — established repo knowledge)
- `vmd/AGENTS.md` — headless recipe, Tcl 8.5 rules, sentinel spec, Pitfall 7 (user lost), Phase-15 index/molid rules
- `vmd/lib/mutation.tcl` — `write_combined_pdb`/`tag_sentinels*`/`fetch_hider_indices`/`mutate` (shipped, probe-pinned formats)
- `.planning/phases/21-large-fetched-demos-attribution/21-RESEARCH-vmd-fetch-mechanics.md` — exec curl precedent, package census, `file rename -force` precedent, writepdb census (CRLF, no CONECT, hex serials)
- `.planning/phases/17.2-cartoon-newcartoon-generators/17.2-RESEARCH-cartoon-stride.md` — writepdb collapses multi-model (37→1), frame raciness + pinning rule
- `.planning/phases/08-persistence-and-shareable-puzzles/08-file-format-RESEARCH.md` — v1 `.bcmz` design (game.pse + game.bcm, fixed member names, magic header) — the format contract this phase's mechanics serve

## Metadata

**Confidence breakdown:**
- Zip mechanics: HIGH — every form probed incl. failure modes (tar/-a/abs paths/pwsh extension/corrupt inputs)
- JSON emit/parse: HIGH — 17/17 adversarial + 12/12 keys + error taxonomy + timing, in VMD's exact Tcl 8.5.6
- Combined-PDB round-trip: HIGH — raw-byte evidence for the overflow; field survival and index/bond stability asserted
- Reconcile-by-index: HIGH — byte-stable order + subset-validation proven in the e2e cycle
- Atomicity/paths: HIGH — rename -force and space-handling probed; cross-volume rename untested (design avoids it)

**Research date:** 2026-09-26
**Valid until:** ~2026-10-26 (VMD 1.9.3 is frozen upstream; Windows tar/PowerShell behavior stable)

## RESEARCH COMPLETE
