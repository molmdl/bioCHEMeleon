# Phase 21 Research — VMD 1.9.3 / Tcl 8.5 Fetch Mechanics (Large Fetched Demos & Attribution)

**Researched:** 2026-09-25
**Domain:** HTTP fetch, gzip, strip/writepdb, and performance mechanics *inside* VMD 1.9.3's Tcl 8.5 (Windows build) for DEMO-02/03 large-demo fetch → strip → cache → load
**Confidence:** HIGH — every load-bearing conclusion below is PROBE-VERIFIED by headless VMD runs on this exact machine (probe scripts + raw logs in `tmp/p21probe/`, all gitignored). Negative results (VMD can't read .gz; `mol pdbload` dead) are empirical, not inferred.

**Probe inventory:** `tmp/p21probe/probeA.tcl` (http/curl/pdbload), `probeB.tcl`+`probeB2.tcl` (gz read/write), `probeC.tcl`+`probeC2.tcl` (strip selectors, writepdb fidelity, serial overflow, timings), `probeD.tcl` (chunking, curl error taxonomy, URL loads), `probeE.tcl` (full pipeline end-to-end), `probeF.tcl`+`probeF2.tcl` (hex-serial reload, fileevent pipeline). Wet MemProtMD files (`1gzm_wet.pdb` 9,314,128 B / `3gp6_wet.pdb` 7,524,042 B) staged in the same dir — byte-exact match to Phase 9 research (`.planning/phases/09-large-demo-fetch-source-attribution/09-RESEARCH-memprotmd.md`).

**Network reality check (RQ6):** Outbound internet WORKS from Windows VMD (all probes fetched real bytes from RCSB, MemProtMD, SASBDB). Everything below marked PROBE-VERIFIED ran over this network today.

---

## Executive verdict

**Fetch path: `exec curl` (Windows System32 curl.exe, verified 8.13.0) is the primary and effectively only viable fetch path.** The pure-Tcl `http` package (2.7.2, present) fails HTTPS with `Unsupported URL type "https"` (no tls in the VMD build) and does not follow redirects (2.7.x); MemProtMD and SASBDB both 301/302 plain-HTTP → HTTPS, so they are **unreachable from pure Tcl**. RCSB is the lone exception: `files.rcsb.org` still serves 200 over plain HTTP (probe-fetched 1UBQ via Tcl http: 78,570 bytes of real PDB), making a no-curl fallback possible **for RCSB-class demos only** — but it is fragile (server sends HSTS headers; could start redirecting at any time) and needs **[HUMAN-APPROVAL-NEEDED]** as a deliberate plain-HTTP posture. VMD's built-ins are dead: `mol pdbload` fails because the `webpdb` plugin's hardcoded `http://www.rcsb.org/pdb/files/<id>.pdb` now 301-redirects to HTTPS and VMD receives 0 bytes (`BaseMolecule: init_atoms called with invalid number of atoms: 0`); `mol new <url>` also fails. Recommended call shape: blocking `exec curl -sS -L --connect-timeout 15 --max-time 120 -A bioCHEMeleon/2.0 -o <tmp> -w "%{http_code} %{size_download}" <url>` for headless/simple cases, and the **non-blocking `open |curl` + `fileevent` + (no) `vwait` pipeline** for the GUI (probe-verified: Tk event loop stays pumpable during a 2.1s SASBDB download; 7.5 MB MemProtMD fetch = 6.7 s, so a frozen dialog is otherwise noticeable).

**Compression path: none — cache plain stripped PDB.** VMD 1.9.3 Windows **cannot read gzipped PDB files at all**: `mol new x.pdb.gz` fails type detection by extension (`Could not determine file type for file 'k8p_ps.pdb.gz' from its extension.`) and even `mol new x.pdb.gz type pdb` / `mol load pdb x.pdb.gz` fail on a probe-verified valid gzip (magic `1f8b`) — `Unable to load file 'k8p_ps.pdb.gz' using file type 'pdb'.` Creating .gz from Tcl is possible (PowerShell `IO.Compression.GzipStream` works: 7.5 MB → 1.3 MB in 1.6 s, valid magic; `gzip.exe` on this dev box is a TeXLive accident — **not stock Windows**; `tar.exe` makes tar/zip containers VMD can't read) — but pointless since VMD can't read it back. Sizes make compression unnecessary: 3gp6 dry = 1.5 MB, 1gzm dry = 2.0 MB, SASDPG4 = 0.4 MB → total cache ≈ 4 MB. This is a deliberate divergence from v1 (PyMOL cache used `.pdb.gz` because PyMOL reads gz natively; VMD does not).

**Strip path: `atomselect $m "not water and not ions"` → `$sel writepdb <dry.part.pdb>` → atomic rename.** VMD's `water`/`ions` keywords match MemProtMD's GROMACS naming exactly (probe: `water` = 75,789 SOL on 3gp6, 91,638 on 1gzm; `ions` = 229 / 286 = NA+CL with GROMACS leading-space fields). The dry counts exactly reproduce Phase 9's staged dry samples (19,221 / 25,974). Full 1GZM strip pipeline = ~1.0 s of VMD work (load 794 ms + select 45 ms + write 175 ms + reload 189 ms) — no chunking needed in the pipeline; chunking remains a generator-side concern (`after 0` pattern probe-verified headless).

---

## Per-question findings

### RQ1 — HTTP fetch options inside VMD 1.9.3 Tcl 8.5

#### RQ1a. `package require http` — PROBE-VERIFIED

- Present: **http 2.7.2** (Tcl 8.5.6 core). Probe A: `HTTP-PKG: OK version=2.7.2`.
- HTTPS fails **hard and early** — not a socket/timeout error but an unregistered-scheme error:
  - `HTTPS-TCL: EXEC-FAIL msg=Unsupported URL type "https"` with `errorCode=NONE`.
  - There is no `tls` package in `package names` (full list captured in `probeA.log`; it's all VMD plugin packages + Tcl core: `msgcat`, `platform`, `tcltest`, `http`, `Tcl`, `bignum`, `tcl::tommath`, … — **no `tls`, no `zlib`, no `json`, no `sha1`/`md5`**).
- Tcl http 2.7.2 does **NOT auto-follow redirects**: probe A on MemProtMD plain-HTTP returned `status=ok ncode=301` with body of 17 bytes (the redirect stub). Re-issuing against the `Location:` (https) hits the unsupported-scheme wall. Dead end for MemProtMD/SASBDB.

#### RQ1b. Plain-HTTP endpoints of the target sources — PROBE-VERIFIED (WSL curl baseline) + PROBE-VERIFIED in-VMD (RCSB)

| Source | Plain-HTTP behavior (verified 2026-09-25) | Tcl-http usable? |
|---|---|---|
| `files.rcsb.org` | **200 + real content** over `http://` (also sends `strict-transport-security` header — browsers upgrade, Tcl doesn't) | **YES** — probe-fetched 1UBQ end-to-end via `::http::geturl http://files.rcsb.org/download/1UBQ.pdb` → `status=ok ncode=200 bytes=78570 first-line=HEADER …1UBQ` |
| `memprotmd.bioch.ox.ac.uk` | `301` → `Location: https://…` | NO (no redirect follow + https unsupported) |
| `www.sasbdb.org` | `302` → `Location: https://…` | NO (same) |

Note the exact download URLs are the sources researcher's domain; the ones exercised here (from Phase 9 research, re-verified): `https://memprotmd.bioch.ox.ac.uk/data/memprotmd/simulations/<id>_default_dppc/files/structures/at.pdb`, `https://www.sasbdb.org/media/pdb_file/<SASDID>_fit2_model1.pdb`, `https://files.rcsb.org/download/<id>.pdb`.

#### RQ1c. `exec curl` — PROBE-VERIFIED (leading candidate confirmed)

- Windows VMD resolves and runs **curl 8.13.0 (Windows) at `C:\Windows\System32\curl.exe`** (`probeB.log WHERE-curl`; Schannel TLS, zlib). Windows 10 ≥1803 ships it — stock-OS assumption, no repo-bundled dependency.
- Real fetches through `exec curl` **from inside headless VMD**, all verified:
  - RCSB https: `200 85698 0.602578` (1K8P) — first line `HEADER DNA …1K8P` ✓
  - SASBDB https: `200 400810` (SASDPG4_fit2_model1.pdb, exact expected size) ✓
  - MemProtMD https (in probeE): `200 7524042` in 6.7 s (3gp6 wet) ✓
- Absent-binary failure shape (documented via a bogus binary; same shape curl would give on pre-1803 Windows): `couldn't execute "definitely_not_a_real_binary_xyz": no such file or directory` + `errorCode = POSIX ENOENT {no such file or directory}`.
- Error taxonomy from probeD (see Error matrix): exit 0 + `-w` output on HTTP errors without `-f`; `CHILDSTATUS <pid> 22` with `-f`; `6` = DNS; `28` = connect timeout; with `-sS` the human-readable `curl: (6) Could not resolve host: …` text lands in the Tcl error message (probeE) — use it for user-facing warnings.

#### RQ1d. VMD built-ins — PROBE-VERIFIED (both dead or absent)

- **`mol pdbload <id>` is BROKEN upstream.** Probe A (`2hhb`) and probeD (`1ubq`) both fail: VMD stdout shows `Using plugin webpdb for structure file 2hhb` then `ERROR) BaseMolecule: init_atoms called with invalid number of atoms: 0` / `ERROR) molecule_structure: Unable to read structure for molecule 0`. Root cause (WSL curl baseline): `http://www.rcsb.org/pdb/files/<id>.pdb` → `301` → `location: https://www.rcsb.org:443/pdb/files/<id>.pdb`; VMD 1.9.3's webpdb plugin doesn't follow the redirect → 0 bytes. Also fails from Tcl. **Do not plan anything on `mol pdbload`.** (Proxy support moot — the endpoint itself is dead.)
- **`mol new <url>` / `mol load` with a URL:** FAIL — `Unable to load file 'http://files.rcsb.org/download/1UBQ.pdb' using file type 'pdb'.` (probeD). No URL-loading path in `mol new`.
- No other fetch plugin exists in the VMD build: `package names` (probeA.log) has no `fetch`/`webpdb` Tcl package; the vmd-ref bundled plugins and core scripts contain no http-fetch utility (grep clean).

#### RQ1e. Recommended primary + fallback strategy — see "Exact Tcl call shapes" below

1. **Primary: `exec curl`** (blocking for headless/CLI simplicity; `open |curl` + `fileevent` for the GUI dialog). Works for all three sources over HTTPS with `-L` (MemProtMD/SASBDB redirect nothing extra needed — they're https-native; `-L` is belt-and-braces), custom UA, timeout flags, `-sS` for error text, `-w "%{http_code} %{size_download}"` for the integrity gate.
2. **Fallback (curl absent / exec fails): pure-Tcl `::http::geturl` against plain-HTTP `files.rcsb.org` — RCSB-class demos only.** Probe-verified working today. NOT usable for MemProtMD/SASBDB (https-only after redirect). Guard with the `Unsupported URL type "https"` catch for any https attempt so the error message can say "requires curl".
3. **No fallback for MemProtMD/SASBDB without curl** → surface an actionable error: "Fetching this demo needs curl.exe (Windows 10 ≥1803) — HTTPS-only source."

Where to write intermediates: **repo cache dir, not `$env(TEMP)`** — `vmd/data/demos/cache/` is Windows-visible (repo lives under `/mnt/c`), keeps debugging simple, and is gitignored (`cache` + `**/cache/**` in `.gitignore`; verified clean `git status` after probeE wrote there). Wet `.part` files are deleted after the dry file is promoted (probeE-verified). Note a leftover artifact from probeE exists at `vmd/data/demos/cache/3gp6_dry.pdb` (gitignored; `rm` is permission-denied for this agent — delete during plan execution).

### RQ2 — Gzip / compression

#### RQ2a. Can `mol new file.pdb.gz` load gzipped PDB? — PROBE-VERIFIED: **NO (decisive)**

- Extension-only: `Could not determine file type for file 'k8p_ps.pdb.gz' from its extension.` (`.gz` is not a known extension → no plugin mapping).
- Explicit type on a **verified-valid gzip** (magic `1f8b` checked byte-wise in probeB):
  - `mol new k8p_ps.pdb.gz type pdb` → `Unable to load file 'k8p_ps.pdb.gz' using file type 'pdb'.`
  - `mol load pdb k8p_ps.pdb.gz` → `Unable to load structure file k8p_ps.pdb.gz`
  - Large case: `mol new 3gp6_wet.pdb.gz type pdb` → same failure (the gz was a genuine 1,296,053-byte gzip of the 7.5 MB wet file).
- The pdb molfile plugin in this build has **no transparent gzip decompression**. (Same probe round confirmed plain loads work: 555-atom 1k8p and 95,239-atom 3gp6 wet.)

#### RQ2b. Creating .gz from Tcl 8.5 — PROBE-VERIFIED (possible but pointless)

| Option | Result |
|---|---|
| Tcl 8.5 core `zlib` | **Absent** (not in `package names`; zlib is Tcl 8.6) |
| `exec gzip` | **Works on THIS machine only** — `C:\texlive\2021\bin\win32\gzip.exe` (TeXLive side-install, "gzip 1.9"). **Not stock Windows — must not be relied on**; on stock boxes it fails with the POSIX ENOENT shape from RQ1c |
| `exec tar -a -cf x.zip …` | Creates zip container (`tar.exe` = Windows bsdtar, System32). VMD: `Could not determine file type for file 'k8p.zip'` — **VMD can't read tar/zip either** |
| `exec powershell -NoProfile -Command {GzipStream…}` | **WORKS**: valid bare .gz (magic `1f8b` verified); 7.5 MB → 1,296,053 B in **1,556 ms**; exact one-liner in `probeB.tcl` |
| **Verdict** | Compression is **unnecessary**: dry cache sizes are 0.4–2.1 MB (measured). Cache **plain PDB**. Divergence from v1's `.pdb.gz` cache_name entries in the manifest port must be applied (v1 `setup_state.py:47,52,56` `cache_name` values `.pdb.gz` → v2 `.pdb`) |

### RQ3 — Strip water/salt

#### RQ3a. Selection keywords — PROBE-VERIFIED (exact counts on real MemProtMD wet files)

Ground-truth censuses (WSL grep): 3gp6 wet = 95,239 atoms (SOL 75,789, DPP 17,500, NA+CL 229); 1gzm wet = 117,898 atoms (SOL 91,638, DPP 19,200, NA+CL 286 — ion fields are **right-justified with a leading space** (` NA`, ` CL`), which VMD trims correctly).

| Selector (on wet) | 3gp6 | 1gzm | Verdict |
|---|---|---|---|
| `water` | **75,789** | **91,638** | matches SOL exactly — VMD's water list covers GROMACS `SOL` |
| `ions` | **229** | **286** | matches NA+CL exactly |
| `resname SOL` / `resname NA CL` | 75,789 / 229 | — | equivalent to keywords (leading-space fields trimmed) |
| `not water and not ions` | **19,221** | **25,974** | **THE strip selector** ≡ explicit `not resname SOL and not resname NA and not resname CL` (identical counts, probeC2) |
| `solvent` | 93,518 | — | = water+ions+**DPP lipid** (95,239−1,721 protein). **WRONG for MemProtMD — never use `not solvent`** (it would drop the membrane the demo exists to show) |
| `inorganic` | parse error | — | **does not exist** in VMD (that's the PyMOL selector name) |

#### RQ3b. write-back fidelity + >99,999 atoms — PROBE-VERIFIED

- **Beta round-trips**: set `beta -999` via atomselect before `writepdb` → reload `beta < 0` count = 3/3 ✓ (cols 61-66, `-999.00`). (Established sentinel mechanism survives the strip-write path.)
- **segid asymmetry**: writer puts 4-char `GAME` in cols 73-76 (confirmed byte-level), but the **reader truncates to 3 chars** (`segid GAME` count = 0 on reload; read value `GAM`). Same class as the known resname-3-char rule (vmd/AGENTS.md). Consequence: never rely on `segid GAME` surviving a PDB round-trip; sentinels are set via atomselect **after** load (existing architecture is already correct — game selector is `resname GAM and beta < 0`).
- **Element column blank** in VMD-written PDB; reload reports element `X` for name `N`. Cosmetic only (VMD derives radii/appearance from atom names); note for any future tooling that reads element.
- **Serial overflow beyond 99999**: VMD writepdb does **not** error — it silently writes **hex** serials (`ATOM  186a0` = 100,000; last serial `1cc8a` = 117,898) with CRLF endings, then **re-reads its own output correctly** (probeF: `mol new 1gzm_all.pdb` → 117,898 atoms ✓; VMD ignores serials and assigns sequential index). Production dry caches are 19-26k atoms so this never triggers, but the splice/pdb-rebuild path writing >99,999 atoms is *safe-for-VMD*, *non-portable-to-other-tools*.
- **writepdb drops MODEL/ENDMDL wrappers and REMARKs**; output = CRYST1 + ATOM/TER + END (probe census on `1gzm_all.pdb`: 117,898 ATOM + 1 CRYST1 + 1 END).
- **Measured strip pipeline** (probeC2/probeE): load wet 794-1,626 ms → keyword select 45 ms → writepdb dry 175-905 ms → reload 189-247 ms. Whole thing ≈ 1-3 s of VMD work; the 6.7-11 s fetch dominates.

### RQ4 — Performance patterns

- **`after 0` chunking: repo precedent is documentation-only** — grep of `vmd/` finds the pattern only in `vmd/AGENTS.md:140` ("Never block the event loop >200ms … use `after 0 ::gen_chunk`"); no shipped implementation yet (generators are fast enough so far). Probe D **verifies the mechanism headless**: 20-callback `after 0` chain with `vwait` completed in 68 ms in `-dispdev text` mode. Safe to plan on.
- **Non-blocking download for GUI responsiveness: PROBE-VERIFIED** (probeF2): `open |curl` + `fconfigure -blocking 0` + `fileevent readable` + `vwait` → result read from channel (`200 400810`, 2.1 s SASDPG4), event loop pumped throughout. This is the v2 replacement for v1's Python worker thread + QProgressDialog. (Two probe iterations failed on the classic `catch {open …} var` misuse — the final form in `probeF2.tcl` is the correct shape; cf. AGENTS.md "Tcl 8.5 gotchas".)
- **Timings on this machine (8 CPUs, text mode)**:

| Operation | Time | Evidence |
|---|---|---|
| `molinfo $m get numatoms` | **1.1 µs/iter** (×1000) | probeC |
| `atomselect "name CA"` on 117,898 atoms | **2.8 ms** | probeC |
| `atomselect "not water and not ions"` on 117,898 | **22 ms** | probeC |
| load 3gp6 wet (95,239) | 528-1,626 ms | probeB2/C |
| load 1gzm wet (117,898) | 794-963 ms | probeC/C2 |
| writepdb 117,898 atoms | 975 ms (9.4 MB out) | probeC |
| writepdb 25,974-atom dry | 175 ms (2.0 MB out) | probeC2 |
| reload dry cache (19,221) | 190-247 ms | probeC/C2/E |
| curl fetch 7.5 MB (MemProtMD) | 6,708 ms | probeE |
| curl fetch 0.4 MB (SASBDB) | ~0.9-2.1 s | probeD/F2 |

- **>~20k warn threshold**: mechanics are trivial — after cache load, `molinfo $m get numatoms` (free) and `vmdcon -warn` if > 20,000 (existing `vmdcon -warn` idiom used in mutation.tcl:210,336). 1gzm dry (25,974) and 3gp6 dry (19,221) straddle the threshold exactly as the phase brief anticipated.
- **Hider cap**: already implemented and probe-verified in Phase 04/15 — `::biochemeleon::setup_state::hider_count_cap` = `atom_count/50` clamped [1,50] (`vmd/lib/setup_state.tcl:51-61`; saturates at 50 above 2,500 atoms), fed by `::biochemeleon::demos::atom_count` (`vmd/lib/demos.tcl:186-189`, `molinfo … get numatoms` in catch). Phase 21's "cap hider count as a function of atom count" is **already satisfied**; the new work is surfacing the warn + difficulty metadata, not new cap math.

### RQ5 — Cache layout (proposal, informed by verified mechanics)

- **Location**: `vmd/data/demos/cache/` (sibling of the bundled demos; Windows-visible since the repo is under `/mnt/c`; **gitignored** via existing `.gitignore` `cache` + `**/cache/**` — probeE verified clean status while the file existed). Flag for planner: phase text says `data/demos/cache/`; the v2 viewer tree has no root `data/`, so `vmd/data/demos/cache/` is the faithful reading. **[needs planner decision, one line]**
- **Naming**: mirror v1's manifest pattern (`cache_name` per demo id): `1gzm_dry.pdb`, `3gp6_dry.pdb` (MemProtMD `_dry` suffix = the v1/human-established convention for stripped wet `at.pdb` — see 09-RESEARCH-memprotmd.md), `SASDPG4_fit2_model1.pdb` (keep SASBDB source filename). No `.gz` (RQ2a).
- **Cache key**: demo_id → `cache_name` via the extended `DEMO_MANIFEST` (v1 `setup_state.py:36-56` shape: `source`, `source_id`, `fetch_url`, `cache_name`, `citation`, `strip`). **No URL hash**: Tcl 8.5 core has no sha1/md5 (verified absent), and manifest-managed ids already key uniqueness — a hash adds nothing.
- **Atomic write**: write to `<cache_name>.part` then `file rename -force` (probeE-verified on Windows VMD). Also delete wet `.part` after promote.
- **Integrity gate**: parse curl `-w "%{http_code} %{size_download}"` (must match `200 <bytes>`); sanity-check `size >= expected_min` and first-line record (`HEADER|TITLE|ATOM|CRYST1`) before promoting the `.part`. For known sizes (SASDPG4 = 400,810 exact), an exact-size check is possible but brittle (server-side may change) — prefer `>= threshold` + first-line check.

### RQ6 — Network reality — PROBE-VERIFIED

Outbound internet works end-to-end from Windows VMD on this machine (RCSB + MemProtMD + SASBDB all fetched real bytes through both `exec curl` and, for RCSB, pure-Tcl http). All conclusions above are probe-verified today; no doc-only load-bearing claims.

---

## Exact Tcl call shapes for the recommended path

### Fetch — blocking (headless / simple)

```tcl
# Source: tmp/p21probe/probeE.tcl (verified 2026-09-25)
proc ::BCM::fetch::curl_get {url outfile} {
    # returns {"200" "7524042"} or throws with actionable message
    if {[catch {exec curl -sS -L --connect-timeout 15 --max-time 120 \
                 -A bioCHEMeleon/2.0 -o $outfile \
                 -w {%{http_code} %{size_download}} $url} msg]} {
        # msg carries -sS text, e.g. "curl: (6) Could not resolve host: …"
        # ::errorCode = CHILDSTATUS <pid> <exit>  (6=DNS 7=conn 22=http(-f) 28=timeout)
        # or POSIX ENOENT if curl.exe is absent (Windows <10 1803)
        error "demo fetch failed: $msg" "" $::errorCode
    }
    lassign [split $msg " "] code bytes
    if {$code ne "200"} {
        error "demo fetch failed: HTTP $code (source may be down or entry withdrawn)"
    }
    return $bytes   ;# caller: sanity-check size + first line before promote
}
```

### Fetch — non-blocking (GUI dialog stays responsive; replaces v1's worker thread)

```tcl
# Source: tmp/p21probe/probeF2.tcl (verified 2026-09-25)
proc ::BCM::fetch::start {url outfile on_done} {
    variable result ""
    if {[catch {open |[list curl -sS -L --connect-timeout 15 --max-time 120 \
             -A bioCHEMeleon/2.0 -o $outfile \
             -w {%{http_code} %{size_download}} $url] ch} err]} {
        uplevel #0 [list $on_done error $err]; return
    }
    fconfigure $ch -blocking 0 -buffering none
    fileevent $ch readable [list ::BCM::fetch::_read $ch $on_done]
}
proc ::BCM::fetch::_read {ch on_done} {
    variable result
    if {[eof $ch]} {
        fileevent $ch readable {}
        if {[catch {close $ch} cerr]} {
            uplevel #0 [list $on_done error "$cerr"]     ;# child nonzero exit
        } else {
            uplevel #0 [list $on_done ok $::BCM::fetch::result]
        }
        return
    }
    append result [read $ch]
}
# NOTE: no vwait in GUI code — Tk's event loop pumps fileevents naturally;
# vwait is only for headless probes (verified working in text mode, probeF2).
```

### Strip + atomic cache + load

```tcl
# Source: tmp/p21probe/probeE.tcl (verified end-to-end 2026-09-25)
set cache vmd_data_demos_cache                 ;# resolved path, file mkdir'd once
set tmpfile $cache/3gp6_wet.part.pdb
::BCM::fetch::curl_get $fetch_url $tmpfile
set m [mol new $tmpfile]                        ;# ~1.6 s @ 95k atoms
set sel [atomselect $m "not water and not ions"] ;# PROBE: == explicit resname list
$sel writepdb $cache/3gp6_dry.part.pdb          ;# ~0.9 s
$sel delete
mol delete $m
file rename -force $cache/3gp6_dry.part.pdb $cache/3gp6_dry.pdb   ;# atomic promote
file delete $tmpfile
set m [mol new $cache/3gp6_dry.pdb]             ;# 19,221 atoms, 190 ms, 0 residual water
if {[molinfo $m get numatoms] > 20000} {
    vmdcon -warn "Large demo ([molinfo $m get numatoms] atoms): generation may take several seconds"
}
```

### Fallback — pure-Tcl plain-HTTP (RCSB-class only; needs approval)

```tcl
# Source: tmp/p21probe/probeA.tcl (verified 2026-09-25; RCSB plain-HTTP only)
package require http 2.7
set tok [::http::geturl "http://files.rcsb.org/download/1UBQ.pdb" -timeout 20000]
# status=ok ncode=200; ::http::data $tok = body; ALWAYS ::http::cleanup $tok
# NEVER pass https:// here: hard error `Unsupported URL type "https"` (no tls in build)
```

## Error-handling matrix

| Failure | Mechanism | Detection (exact shape) | Suggested user message |
|---|---|---|---|
| curl.exe absent (Windows <10 1803) | `exec` | `couldn't execute "curl": no such file or directory`, `errorCode=POSIX ENOENT` | "This demo needs curl.exe (ships with Windows 10 1803+). Demo can't be fetched on this system." |
| DNS failure | curl exit 6 | `errorCode=CHILDSTATUS <pid> 6`; msg contains `curl: (6) Could not resolve host:` (with `-sS`) | "Could not reach <host> — check your internet connection." |
| Connection refused/reset | curl exit 7 | `CHILDSTATUS <pid> 7` | "Could not connect to <host> — the source may be down." |
| HTTP 404 (entry withdrawn/renamed) | curl exit 22 (with `-f`), or `-w` code ≠ 200 | `CHILDSTATUS <pid> 22` or parse `w` | "HTTP 404 — the demo entry appears to have been withdrawn by the source." |
| Timeout | curl exit 28 | `CHILDSTATUS <pid> 28` | "Timed out fetching the demo (large file) — try again." |
| Truncated/partial body | size/first-line gate | `size_download` small, or first line not `HEADER/TITLE/ATOM/CRYST1` | "Download incomplete — retry." (delete `.part`, never promote) |
| https attempted via Tcl http | no tls in build | `Unsupported URL type "https"`, `errorCode=NONE` | internal guard: route to curl path, never show raw |
| MemProtMD/SASBDB without curl | 301/302 → https → unsupported | `ncode=301/302` from Tcl http | "This source is HTTPS-only; requires curl." |
| `mol pdbload` | upstream 301 → 0 atoms | `pdbload of '<id>' failed.`; stderr `init_atoms … invalid number of atoms: 0` | **Do not use; do not surface** (dead upstream) |
| Gzipped cache offered | VMD can't read .gz | `Could not determine file type … from its extension` / `Unable to load file … using file type 'pdb'` | **Prevent by design**: cache plain PDB only |

## Performance guidance (for the planner's guardrails)

1. **Warn before Start at >20,000 atoms** — one free `molinfo` read + `vmdcon -warn` (1gzm dry 25,974 trips it; 3gp6 dry 19,221 does not — matches the phase's "~20k" intent).
2. **Hider cap**: reuse `hider_count_cap` (atom_count/50, clamp [1,50]) — already wired via `demos::atom_count`; do not write new math.
3. **Chunk anything >200 ms with `after 0`** (headless-verified pattern) — applies to *generators on large demos*, NOT to the fetch/strip pipeline (its longest single VMD step is 1.6 s load / 0.9 s write; show a status label instead — the fetch itself must use the fileevent pipeline to stay responsive).
4. **Narrow selects are cheap at this scale** (2.8 ms `name CA` @ 117k); the standing rule "never `$sel get {x y z}` on all atoms" (vmd/AGENTS.md) remains the real constraint.
5. Budget check vs success criteria: fetch 6.7-11 s + strip ~1-3 s + load ~0.2 s ≈ **8-14 s one-time per demo** (then ~0.2 s cached loads). Comfortably within "Generate on 3GP6 < 30s" once cached.

## v1 → v2 divergences (state of the art, all PROBE-VERIFIED)

| v1 (PyMOL/Python) | v2 (VMD 1.9.3 Tcl) | Why |
|---|---|---|
| `urllib` + SSL `check_hostname=False` fallback | `exec curl -sS -L` (+ plain-HTTP Tcl fallback, RCSB only) | VMD Tcl has no tls; System32 curl is stock Windows |
| Worker thread + QProgressDialog | `open \|curl` + `fileevent` pipeline | Tcl 8.5 single-threaded; event-loop pumping verified |
| `.pdb.gz` cache | **plain `.pdb` cache** | VMD 1.9.3 Windows cannot read gzipped PDB (probe-decisive) |
| Strip by Python line-filter (`SOL/NA/CL`) | `atomselect "not water and not ions"` | VMD keywords match GROMACS names exactly (probe-verified); `solvent` keyword is a trap (includes DPP lipid) |
| `cmd.fetch <id>` | NO equivalent (`mol pdbload` dead upstream) | RCSB now 301s VMD's hardcoded http URL to https → 0 atoms |
| QProgressDialog progress | curl `-w` metrics read at eof; indeterminate status label | No progress events through Tcl exec/fileevent without extra plumbing |

## Open questions for the planner

1. **Cache dir naming** — `vmd/data/demos/cache/` (viewer-tree-faithful, gitignored, probe-verified) vs literal `data/demos/cache/` from the phase text. Recommend the former; one-line decision.
2. **Plain-HTTP Tcl fallback for RCSB** `[HUMAN-APPROVAL-NEEDED]` — works today (probe), but it's a deliberate non-TLS fetch (RCSB advertises HSTS). Options: (a) curl-only, error out without curl (simplest, strictly secure); (b) plain-http Tcl fallback for bundled-RCSB-class fetches only (works on pre-1803 Windows). Recommend (a) for simplicity + (b) only if pre-1803 Windows support matters.
3. **UA string** `[HUMAN-APPROVAL-NEEDED, minor]` — probes used `-A bioCHEMeleon/2.0` (worked on all three hosts). Keep as the polite identifier; v1 noted SASBDB may block bare default UAs (that was python-urllib's; default curl UA untested). Custom UA verified working — recommend keeping it.
4. **1GZM wet fetch through exec curl** not separately timed (3gp6 verified at 6.7 s for 7.5 MB; 1gzm is 9.3 MB → estimate ~9-11 s). Low risk; verify at execution.
5. **SASBDB entry/model choice** (SASDPG4 `fit2_model1`, glycan-bearing) — carried over from 09-RESEARCH-sasbdb.md; sources researcher owns the final URL set + DEMO-04 license table (MemProtMD CC-BY 4.0 per-entry check remains a human step).
6. **Difficulty tiers for large demos** (Challenge / Very challenging labels in the sub-menu) — metadata plumbing is manifest-side (`DEMO_MANIFEST` extension mirroring v1's `difficulty` field); vocabulary choice is UX/sources territory, not mechanics.
7. **Leftover probe artifact** — `vmd/data/demos/cache/3gp6_dry.pdb` from probeE is gitignored and harmless; `rm` is permission-denied for this agent; delete during plan execution (or leave as a warm cache).
8. **`resname NA CL` vs keyword `ions`** — both probe-exact on MemProtMD files; if the strip step must also handle *bundled* RCSB demos with `HOH` water (e.g. future fetched RCSB entries), `water`/`ions` are the safer keywords (they cover HOH/WAT/TIP3 too — DOC-BASED for the non-GROMACS names; SOL/NA/CL coverage is PROBE-VERIFIED).

## Sources

### Primary (PROBE-VERIFIED, HIGH confidence)
- `tmp/p21probe/probeA.log` — http 2.7.2 present; `Unsupported URL type "https"`; plain-HTTP RCSB fetch via Tcl (78,570 B 1UBQ); MemProtMD 301 no-follow; curl 8.13.0 version + real fetch; ENOENT shape; `mol pdbload` failure (+ stderr root-cause lines in `probeA_stdout.log`)
- `tmp/p21probe/probeB.log`, `probeB2.log` — tool census (curl/tar/powershell System32; gzip = TeXLive-only); PS GzipStream valid .gz (magic 1f8b), 7.5 MB→1.3 MB in 1,556 ms; **VMD cannot load .gz** (extension + explicit-type failures); zip unreadable
- `tmp/p21probe/probeC.log`, `probeC2.log` — `water`/`ions`/`resname` exact counts vs census; `inorganic` parse error; `solvent` trap (93,518 = water+ions+DPP); dry 19,221/25,974 exact; beta round-trip ✓; segid 4-char write / 3-char read; element blank; timings
- `tmp/p21probe/probeD.log` — `after 0`+`vwait` chain (20 chunks/68 ms); curl exit taxonomy (0/`-w`, 22, 6, 28); SASBDB 400,810 exact; `mol new <url>` fail; `pdbload 1ubq` fail
- `tmp/p21probe/probeE.log` — end-to-end pipeline: fetch 200/7,524,042 B/6.7 s → strip → writepdb → atomic rename → cached load 19,221/0 water; `-sS` error-text capture; cache dir + gitignore clean
- `tmp/p21probe/probeF2.log` — `open |curl` + `fileevent` + non-blocking read verified (`200 400810`); (probeF.log: hex-serial file reload = 117,898 atoms)

### Secondary (verified baselines)
- WSL `curl` header checks 2026-09-25: `files.rcsb.org` plain-HTTP 200 + HSTS header; `memprotmd…at.pdb` 301→https (Content-Length 9,314,128 on https HEAD); `sasbdb.org` 302→https (Content-Length 400,810)
- `.planning/phases/09-large-demo-fetch-source-attribution/09-RESEARCH-memprotmd.md`, `09-RESEARCH-sasbdb.md` — URLs, entry metadata, license/attribution (Phase 9, human-approved sources)
- `vmd/lib/setup_state.tcl:51-61` (hider_count_cap), `vmd/lib/demos.tcl:186-189` (atom_count), `pymol/biochemeleon/demos.py:304-355` (v1 SSL-fallback shape), `pymol/biochemeleon/setup_state.py:36-56,193` (v1 manifest + strip sets)
- `vmd/AGENTS.md` (Tcl 8.5 gotchas, sentinel rules, performance budget)

## Metadata

**Confidence breakdown:**
- Fetch path: HIGH — every option probed in the real runtime (incl. decisive negatives)
- Compression: HIGH — decisive negative (VMD can't read .gz) + creation-side matrix probed
- Strip/writepdb: HIGH — exact-count matches against independent WSL census + byte-level column inspection
- Performance: HIGH — measured in-runtime; thresholds map directly onto existing cap/warn code
- Cache layout: MEDIUM — mechanics verified; dir naming is a planner decision

**Research date:** 2026-09-25
**Valid until:** probe results are build-anchored (VMD 1.9.3 + this OS image) — stable indefinitely for this environment; the *network* claims (RCSB plain-HTTP, MemProtMD/SASBDB URLs) re-verify cheaply at execution time.
