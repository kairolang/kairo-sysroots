# ksys: build a Kairo sysroot for any triple

Status: design, not implemented (2026-10-08).

`ksys` replaces the per-family bash pipeline in `curate/` with one Python tool
that builds a sysroot for a triple on demand: `ksys ensure aarch64-linux-musl`.
The C library comes from a per-OS *provider*. Everything else is one generic
recipe: compiler-rt, libunwind, libc++abi, libc++, `SYSROOT.toml`,
validation and packing. The per-target differences live in a declarative
*quirks table*.

The model is `zig cc`. Ship libc sources (or an ABI description) instead of
prebuilt sysroots, build what a triple needs, and cache it by content.
Prebuilt release assets stay as the fast path for common targets.

## 1. Goals and non-goals

Goals:
- One command builds a working sysroot from a Linux host. The output is
  byte-for-byte the same shape as today's `staging/<name>/`, so Kairo,
  `tar-dist.sh` and `emit-manifest.sh` don't change.
- glibc: any version is a parameter (`--glibc=2.28`), on any arch glibc
  supports. Stubs are generated, not downloaded as binaries (section 5).
- musl from source. This removes the Alpine dependency and covers every
  Linux arch the fork's LLVM backends support.
- When a triple can't be built, the refusal names the missing piece.
- Adding a provider or a quirk doesn't touch the generic pipeline.

Non-goals:
- Automating Microsoft's or Apple's licence. MSVC and Darwin stay
  user-supplied and local-only. `ksys` never downloads the CRT/SDK, never
  runs `xwin --accept-license`, and never packs `local_only` dirs.
- Kairo-side changes. Kairo keeps taking `--sysroot`. The hook through which
  Kairo calls `ksys` is defined as an interface (section 9) but not
  designed here.
- Enabling more LLVM backends. That is a `Scripts/build_llvm.py`
  (`LLVM_TARGETS`) decision. `ksys` only detects it.

## 2. Names: sysroot name vs clang triple

Two fields, kept apart everywhere:

| field | example | used by |
|---|---|---|
| **name** | `armv7-linux-musl`, `x86_64-linux-gnu-glibc2.31` | dir name, TOML `triple`, manifest key, what Kairo matches `--target` against |
| **clang triple** | `armv7-unknown-linux-musleabihf`, `thumbv7-w64-windows-gnu` | every `--target=` passed to clang/CMake |

The name grammar is the one in use today:
`<arch>-<os>[-<env>][-<libc><ver>]`, with the vendor field dropped
(`unknown`, `pc`, `w64`). For ELF BSDs the vendor is kept, as in
`x86_64-unknown-freebsd`. The clang triple is derived from the name, then
passed through quirk `target_rewrite`s (section 6).

Both open Kairo issues (armv7 musl needs `musleabihf`, armv7 windows-gnu
needs `thumbv7`) are this split leaking out. Because of that, the TOML will
gain an optional `clang_triple` key. Kairo ignores unknown keys today, so
the key is safe to add now and Kairo can start reading it later.

Parsing: `ksys` takes either form. It normalises a clang triple with
`clang --target=X -print-target-triple` and maps it back to a name. An
ambiguous input fails and lists the candidates.

## 3. Pipeline

Each stage is cached on its own (section 7). Only the runtimes stage is
slow, at about 2–5 minutes.

```
parse ─► probe ─► fetch ─► libc headers ─► builtins ─► libc libs/crt ─► runtimes ─► assemble ─► toml ─► validate ─► [pack ─► manifest]
         │                  (provider)       (generic)    (provider)      (generic)
         └─ refuses with a named reason (section 8)
```

The order is forced by bootstrap: compiler-rt builtins only need libc
*headers*, and libc libs (musl, glibc stubs, mingw crt) are built with the
fork clang. Building libunwind, libc++abi and libc++ needs both, because
their CMake link checks use `CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY`
and that only works with headers + builtins in place.

## 4. Provider interface

```python
class Provider(Protocol):
    id: str                       # "musl", "glibc", "mingw", "freebsd", ...
    family: str                   # TOML `family`: "linux-musl", "linux-gnu", ...
    redistributable: bool         # False -> pack refuses (darwin, msvc)
    local_only: tuple[str, ...]   # dirs excluded from pack + leak-checked ("msvc",)

    def supports(self, t: Target) -> Support: ...           # ok | Refuse(reason)
    def versions(self, t: Target) -> Versions: ...          # default, min, max/known list
    def sources(self, t: Target, v: str) -> list[Source]: ...   # pinned url+sha256, or UserInput(path, hint)
    def headers(self, t, v, srcs, ctx, dst) -> None: ...    # stage 1: C headers only
    def libs(self, t, v, srcs, ctx, dst) -> None: ...       # stage 2: libs + crt objects (clang + builtins available)
    def layout(self, t, v) -> LibcLayout: ...               # include_dirs, lib_dirs, crt_*, libc_link, static, extra TOML keys
    def runtimes(self, t, v) -> RuntimesPlan: ...           # which runtimes, CXX ABI, crtbegin/end source, shared?
    def key_extra(self, t, v) -> dict[str, str]: ...        # anything else that must enter the cache key
```

`ctx` carries the fork toolchain (clang, clang++, llvm-ar/ranlib/nm/lib),
`LLVM_SRC`, the quirk set resolved for `t`, and a scratch dir. Providers
don't call CMake for the LLVM runtimes. That is generic and driven by
`RuntimesPlan`.

`RuntimesPlan` fields: `builtins: bool`, `crt: bool` (compiler-rt
crtbegin/end), `unwind`, `cxxabi` (`libcxxabi` | `vcruntime` | `none`),
`cxx`, `static_only: bool`, `os_dir` (`linux`, `freebsd`, `windows`, `wasi`,
...), `per_target_dir: bool`, `builtins_name` (`libclang_rt.builtins.a` vs
`clang_rt.builtins-<arch>.lib`), `driver` (`gnu` | `cl`).

### Mapping today's scripts onto it

| provider | today | `sources` | `headers` / `libs` |
|---|---|---|---|
| musl | `fetch-musl-*.sh`, `musl.sh` (Alpine apks) | musl tarball + Linux tarball (or sabotage kernel-headers) | `make install-headers`; `make headers_install ARCH=` / build `libc.a` + crt with fork clang |
| glibc | `fetch-glibc.sh`, `glibc.sh`, `build-glibc-runtimes.sh` (Ubuntu debs) | glibc source tarball for `v` + committed ABI db | section 5 |
| glibc-deb | same, kept as reference until section 5's acceptance test passes | Ubuntu/Debian debs | as `glibc.sh` |
| mingw | `mingw.sh` (llvm-mingw bundle) | mingw-w64 tarball (later); llvm-mingw bundle (first) | `mingw-w64-headers` / `mingw-w64-crt` with fork clang |
| freebsd | `freebsd.sh` + `build-bsd-runtimes.sh` | `base.txz` for `v` (default pinned; 14.4 today) | unpack, prune / none |
| netbsd | `netbsd.sh` + `build-bsd-runtimes.sh` | `base.tgz`, `comp.tgz` for `v` (10.1 today) | unpack, prune / none |
| wasi | `wasi.sh`, `build-wasi-builtins.sh` | wasi-sdk sysroot (wasi-libc from source later) | copy / none |
| darwin | `darwin.sh` | `UserInput(SDK path)`; `redistributable=False` | copy SDK subset / none |
| msvc | `msvc.sh` | `UserInput(xwin splat)`; `redistributable=False`, `local_only=("msvc",)` | copy splat to `msvc/` / none |

The generic stages absorb `build-builtins.sh`, `build-bsd-runtimes.sh`'s
runtimes half, the runtimes half of `msvc.sh`, and `replay-validate.sh`.
`tar-dist.sh`'s `local_only` exclusion and post-pack leak check become the
generic `pack` stage, unchanged in behaviour.

Possible later providers: android (NDK sysroot), openbsd, dragonfly,
bare-metal (picolibc from source), wasi-libc from source.

## 5. glibc provider: generated stubs

Goal: `--glibc=X.Y` on any glibc arch with no binary downloads. One small
download remains: the glibc source tarball for `X.Y`, which is pinned and
cached. A stub-based sysroot has four parts, and each needs its own source:

| part | source | version-sensitive because |
|---|---|---|
| **(a) headers** | see decision D1 | 2.38 headers redirect `strtol` & co. to `__isoc23_*` under C2x/`_GNU_SOURCE`; 2.28 added `fcntl64` redirects. Headers newer than the target produce references the target doesn't have. |
| **(b) stub DSOs**: `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`, `libutil.so.1`, `ld-linux-*.so.*` | the ABI db below | symbol set, default version, and **which DSO** a symbol lives in |
| **(c) `crt1.o`, `Scrt1.o`, `crti.o`, `crtn.o`** | `sysdeps/<arch>/start.S`, `crti.S`, `crtn.S` from the `X.Y` tarball | before 2.34, `crt1.o` references `__libc_csu_init`/`__libc_csu_fini` |
| **(d) `libc_nonshared.a`** | the `X.Y` tarball's nonshared sources (`elf-init.c` < 2.34, `stat`/`fstat`/... wrappers < 2.33, `atexit.c`, `pthread_atfork.c`, `stack_chk_fail_local.c`, ...) | the list changes by version; read it from `X.Y`'s `csu/Makefile`/`io/Makefile` (`static-only-routines`), never hard-code it |

### ABI database

Input: the `*.abilist` files from glibc source
(`sysdeps/unix/sysv/linux/<arch>/.../libc.abilist`), whose lines look like
`GLIBC_2.2.5 stdin D 0x8` or `GLIBC_2.2.5 malloc F`. They are scanned
**across every release from the floor to latest**, not just the latest one.
One latest tree isn't enough, because 2.34 merged libpthread, libdl and
librt into libc: `pthread_create@GLIBC_2.2.5` must be referenced from
`libpthread.so.0` when targeting 2.31, and from `libc.so.6` at 2.34+. Only
per-release data says which.

Schema, as one compact committed file (`data/glibc-abi.json.zst`; Zig's is a
few hundred KB):

```
arches:    [x86_64, i386, aarch64, arm-hf, riscv64, ...]      # glibc's sysdeps names
releases:  ["2.24", ..., "2.42"]
libs:      [libc.so.6, libm.so.6, libpthread.so.0, ...]
symbols:   [{name, kind: F|D|T (func/object/TLS), size?: int,
             entries: [{lib, version_node, arches: bitset, releases: bitset, default: bool}]}]
```

`kind` and `size` matter. Data objects (`stdin`, `environ`, `_IO_2_1_stdout_`,
`__libc_single_threaded`) need the right `STT_OBJECT` and `st_size`, or
copy relocations come out wrong and lld complains. TLS symbols need
`STT_TLS`.

Generating a stub for (`arch`, `X.Y`, `lib`): emit one assembly file. It
declares every version node ≤ `X.Y` in order, then defines each symbol
present in `X.Y` with `.symver name, name@[@]NODE`. `@@` goes on the newest
node ≤ `X.Y`. The stub is assembled with the fork clang and linked with
`ld.lld -shared --version-script` and the right `-soname`. The default
version is then correct by construction: a link against the 2.31 stub can't
bind to anything newer. That gives the "minimum glibc" guarantee
mechanically, with no post-link symbol-version check needed.

Linker scripts and dev links are needed. lld's `-lc` looks for
`libc.so`/`libc.a`, never `libc.so.6`, and `libc_nonshared.a` only enters
the link through the script. The provider writes them as `glibc.sh`
rewrites Ubuntu's today, with bare names that resolve through `-L`:
`libc.so` = `GROUP ( libc.so.6 libc_nonshared.a AS_NEEDED ( ld-linux-<arch>.so.N ) )`,
and `libm.so`, `libpthread.so`, `libdl.so`, `librt.so` as scripts or
symlinks matching what glibc `X.Y` installs. From 2.34 the last three point
at near-empty stubs.

Floor: glibc 2.24 (libc++'s minimum). Each arch has its own first release
(riscv64 starts at 2.27). Default stays 2.31, matching the current release
assets.

Static linking against glibc: not supported, same as today (`static =
false`).

### Acceptance test (blocks removing `glibc-deb`)

For all 5 current arches at 2.31:
1. Build the stub sysroot and the existing Ubuntu sysroot side by side.
2. Link Kairo's three test programs (`test.k`, `floats.k`, `tfbf.k`)
   against each.
3. `readelf --dyn-syms -V` on the outputs must show the same `DT_NEEDED`
   set and the same version needs, per DSO.
4. The x86_64 and i686 binaries run on the host. aarch64, armv7 and riscv64
   run under `qemu-user` with an Ubuntu 20.04 `-L` root.
5. Then repeat for x86_64 at 2.28 (Debian buster debs) and 2.35 (Ubuntu
   jammy debs), to prove the 2.33/2.34 crossings.

## 6. Quirks table

Data file: `data/quirks.toml`. Each entry is a **predicate** plus ordered
**effects**. All matching entries apply, in file order, and a later scalar
overrides an earlier one. Entries are keyed by triple *components*, never by
a full name.

```toml
[[quirk]]
id      = "short-kebab-id"            # unique; shows up in logs and the cache key
why     = "one line: what breaks without it"
when    = { arch = ["armv7"], os = "linux", env = "musl" }   # all given fields must match
# predicate fields: arch, os, env, vendor, objfmt (elf|coff|macho|wasm),
#                   ptr_bits, driver (gnu|cl), provider, version (">=2.34", "<15")
# effects (all optional):
target_rewrite   = "armv7-unknown-linux-musleabihf"
cflags           = { stages = ["builtins", "runtimes"], add = ["..."] }
cmake            = { stages = ["runtimes"], defs = { KEY = "VAL" } }
force_include    = { stages = ["unwind"], file = "shims/freebsd-getauxval.h" }
builtins_extra   = ["{crt_src}/lib/builtins/{fp_arch}/fp_mode.c"]   # sources compiled into builtins
post_archive     = { stage = "builtins", sources = ["shims/coff-tf-compare.c"], cflags = ["-I{crt_src}/lib/builtins"] }
required_symbols = ["__atomic_load"]                                # added to the base list
toml             = { cc_defines = ["..."] }                         # merged into SYSROOT.toml
```

Variables: `{crt_src}` = `$LLVM_SRC/compiler-rt`, `{fp_arch}` = compiler-rt's
arch dir (`aarch64`, `i386`, `x86_64`, `arm`, `riscv`), `{shims}` = `data/shims/`.
An `@NAME` entry expands to a source list read from compiler-rt's
`lib/builtins/CMakeLists.txt` (e.g. `@BF16_SOURCES`), so it follows the fork
instead of being copied.

### Every existing quirk, written in this schema

This checks the schema against everything we already do. Each row is a fix
from this repo's history.

```toml
[[quirk]]
id = "armv7-musl-hardfloat"
why = "Alpine/musl armv7 is AAPCS-VFP; plain -musl means soft-float, a different call ABI"
when = { arch = ["armv7"], os = "linux", env = "musl" }
target_rewrite = "armv7-unknown-linux-musleabihf"

[[quirk]]
id = "armv7-windows-thumb"
why = "Windows on ARM is Thumb-2 only; CodeView/PE needs thumbv7"
when = { arch = ["armv7"], os = "windows" }
target_rewrite = "thumbv7-w64-windows-gnu"   # env-specific; msvc has no armv7 provider

[[quirk]]
id = "int128-32bit"
why = "clang has no __int128 on 32-bit targets; Kairo i128 lowers to __divti3 & co."
when = { ptr_bits = 32, driver = "gnu" }
cflags = { stages = ["builtins"], add = ["-fforce-enable-int128"] }
cmake  = { stages = ["builtins"], defs = { COMPILER_RT_ENABLE_SOFTWARE_INT128 = "ON" } }

[[quirk]]
id = "int128-cl-spelling"
why = "clang-cl ignores -fforce-enable-int128; TF/int128 sources then compile empty"
when = { driver = "cl" }
cflags = { stages = ["builtins"], add = ["-Xclang", "-fforce-enable-int128"] }
cmake  = { stages = ["builtins"], defs = { COMPILER_RT_ENABLE_SOFTWARE_INT128 = "ON" } }

[[quirk]]
id = "msvc-vcruntime-abi"
why = "MSVC's C++ ABI support (EH, RTTI) is vcruntime; no libc++abi/libunwind"
when = { env = "msvc" }
cmake = { stages = ["runtimes"], defs = { LIBCXX_CXX_ABI = "vcruntime", LIBCXX_ENABLE_SHARED = "OFF" } }
toml  = { cc_defines = ["_CRT_STDIO_ISO_WIDE_SPECIFIERS"] }   # UCRT /failifmismatch

[[quirk]]
id = "coff-tf-compare-aliases"
why = "COMPILER_RT_ALIAS is empty for _WIN32 except MinGW (int_lib.h): __eqtf2/__netf2/__lttf2/__gttf2/__cmptf2 missing"
when = { env = "msvc" }   # not objfmt = "coff": MinGW gets real aliases
post_archive = { stage = "builtins", sources = ["shims/coff-tf-compare.c"], cflags = ["-I{crt_src}/lib/builtins"] }
required_symbols = ["__eqtf2", "__netf2", "__lttf2", "__gttf2", "__cmptf2"]

[[quirk]]
id = "mingw-atomics-in-builtins"
why = "MinGW has no libatomic; llvm-mingw puts __atomic_* in the builtins"
when = { os = "windows", env = "gnu" }
cmake = { stages = ["builtins"], defs = { COMPILER_RT_EXCLUDE_ATOMIC_BUILTIN = "OFF" } }
required_symbols = ["__atomic_load", "__atomic_compare_exchange"]

[[quirk]]
id = "freebsd-aarch64-getauxval"
why = "libunwind's aarch64 PAC probe calls getauxval; FreeBSD 14 only has elf_aux_info"
when = { arch = ["aarch64"], os = "freebsd" }
force_include = { stages = ["unwind"], file = "shims/freebsd-getauxval.h" }

[[quirk]]
id = "darwin-fp-mode-bf16"
why = "Darwin builtins are built per-arch by hand; fp_mode.c (__fe_getround) and bf16 sources were left out"
when = { objfmt = "macho" }
builtins_extra = ["{crt_src}/lib/builtins/{fp_arch}/fp_mode.c", "@BF16_SOURCES"]
required_symbols = ["__fe_getround", "__truncsfbf2"]
```

What *doesn't* go in the table:
- **Probes that hold for every target** become generic. The wasm-only bf16
  `-O0`/`-O2` precheck from `build-wasi-builtins.sh` now runs for every
  target (section 8), and the CMake `COMPILER_RT_HAS_*_BFLOAT16` check
  becomes a generic post-configure assertion.
- **Family layout facts** stay in the provider's `layout()`. Examples: BSD
  drops crtbegin/crtend from the TOML (lld adds them; listing them gave a
  duplicate `__dso_handle`), MSVC's `libc_link` holds `.lib` names, glibc is
  `static = false`.

**Base required symbols**, for every target: `__addtf3 __netf2 __divti3
__extendhfsf2 __truncsfhf2 __truncsfbf2 __truncdfbf2 __trunctfbf2`. The
`nm` output is read to EOF before matching (never `grep -q` under
`pipefail`, which SIGPIPEs `nm` and reads as a miss).

The quirks file's hash is part of the cache key. A quirk's `id` is also
recorded in the sysroot's `.ksys.json`, so a build can be traced back to
the quirks that shaped it.

## 7. Cache

Root: `$KSYS_CACHE` or `${XDG_CACHE_HOME:-~/.cache}/kairo/ksys/`.

```
sources/<sha256>/<filename>            fetched tarballs, verified against data/sources.toml
src/<sha256>/                          extracted (read-only after extract)
stage/<stage>-<key>/                   one dir per (stage, stage key); written to tmp + rename
sysroots/<key>/                        assembled sysroot: SYSROOT.toml + .ksys.json
by-name/<name> -> ../sysroots/<key>    stable name, what `ensure` prints
locks/<key>.lock                       flock; concurrent `ensure` of the same key waits
```

**Key** = sha256 of a canonical JSON object:

```
{ schema: 1,                       # bump when the TOML or layout format changes
  name, clang_triple,
  provider, provider_version, libc_version,
  sources: [sha256...],            # every fetched input
  llvm_src_rev,                    # git -C $LLVM_SRC rev-parse HEAD + hash of `git diff` if dirty
  clang_id,                        # see below
  quirks: [ids applied], quirks_file_sha,
  ksys_version }
```

Every stage key covers only that stage's inputs. A quirk that only touches
`runtimes`, for example, doesn't invalidate the libc stage. `clang_id` is
in the key because the fork changes codegen, which today's
bf16/`trunctfbf2` work showed. The fork's `clang` is a thin driver
dynamically linked to `libclang-cpp.so.22.1` and `libLLVM.so.22.1` (checked
with `ldd`). Codegen changes land in those libraries, so hashing the clang
executable alone would keep the same key across a fork rebuild. That's the
same failure mode as Kairo's stale `libLLVM` copy. `clang_id` is therefore
the sha256 of the clang executable plus every `ldd`-resolved library under
the LLVM build tree, memoised by (path, size, mtime). `llvm_src_rev` covers
the runtimes sources.

`stage/` holds the expensive build trees and can be large. Subcommands:
`ksys cache ls`, `ksys cache gc` (drop entries no `by-name` link points to)
and `ksys cache rm <name>`.

`.ksys.json` in each sysroot holds the full key object, so `ksys verify
<dir>` can say why a sysroot is stale.

The release flow keeps its names. `ksys build --out staging/<name>` writes
the same tree and TOML as today, so `tar-dist.sh` and `emit-manifest.sh`
keep working until they're ported into `ksys pack` and `ksys manifest`.

## 8. Probes and refusal

These run before any fetch, using the fork clang. Each one fails with a
specific, actionable message:

| probe | how | refusal text |
|---|---|---|
| backend | `llc --version` / `clang -print-targets` contains the arch | `backend <X> not built: add it to LLVM_TARGETS in kairo-lang/Scripts/build_llvm.py` |
| f128 | `clang --target=T -dM -E` has `__SIZEOF_FLOAT128__` | `no __float128 for <arch>-<os>: fork TargetInfo patch needed (clang/lib/Basic/Targets/<X>.cpp)` |
| bf16 | compile `__bf16 f(__bf16)` and `(__bf16)float` at -O0 and -O2 | `<X> backend cannot lower bf16 (frontend ok, ISel fails): fork backend patch needed`. The two cases are told apart by re-running with `-fsyntax-only`. |
| int128 | `__SIZEOF_INT128__`, else `int128-32bit` quirk applies | none (quirk covers it) |
| provider | `provider.supports(t)` | provider's reason, e.g. `glibc: <arch> has no glibc port`, `msvc: no xwin splat at <path> (run xwin --accept-license splat yourself)` |
| version | `provider.versions(t)` | `glibc 2.20 < floor 2.24 (libc++ minimum)` |

`ksys probe <triple>` runs these alone. It's how a new arch shows up as a
to-do list instead of a build failure.

Current status of the fork (survey, 2026-10-08):

| target | backend | f128 | bf16 | int128 |
|---|---|---|---|---|
| x86_64 / i686 / aarch64 / armv7 / riscv64 (linux, windows, bsd, darwin) | yes | yes | yes | yes / quirk |
| aarch64 openbsd, x86_64 dragonfly, aarch64 android, riscv64-none-elf | yes | yes | yes | yes |
| armv6 musleabihf, riscv32 | yes | yes | yes | quirk |
| x86_64 illumos | yes | **no** | yes | yes |
| arm-none-eabi (soft-float) | yes | yes | **no** | quirk |
| powerpc64le, s390x, loongarch64, mips64el | **no** | **no** | no | yes |
| powerpc (32) | **no** | **no** | no | quirk |

## 9. CLI and Kairo boundary

```
ksys probe    <target>                       print probe results, exit 1 on refusal
ksys build    <target> [--glibc=X.Y | --libc-version=V] [--out DIR] [--input PATH]
ksys ensure   <target> [...same]             cached build; prints the sysroot path on stdout, logs to stderr
ksys validate <dir>                          section 10
ksys pack     <dir> --out DIST               tar.xz; refuses redistributable=false; excludes + leak-checks local_only
ksys manifest DIST                           regenerates dist/manifest.json (emit-manifest.sh semantics)
ksys cache    ls | gc | rm <name>
ksys verify   <dir>                          recompute key, report staleness
```

`<target>` is a name or a clang triple (section 2). `--input` points at the
user-supplied tree for darwin (SDK) and msvc (xwin splat).

**Kairo hook (interface only).** When `kairo --target T` is given without
`--sysroot`, Kairo can run `ksys ensure T` and use the path from stdout.
Contract:
- exit 0: stdout is one absolute path whose `SYSROOT.toml` `triple` equals
  `T`'s name. Kairo already rejects a mismatch (`Toolchain.k`).
- exit 2: a refusal, with the reason on stderr verbatim.
- On first build, `ksys` prints `building runtimes for <name> (first time
  only, ~3 min)` on stderr.

Lookup order on Kairo's side, to be decided there:
1. `--sysroot`
2. `<kairo>/sysroots/<name>` (an extracted release asset)
3. `ksys ensure`

## 10. Validation

`ksys validate <dir>` runs these, in order:
1. **Symbol check**: the base and quirk `required_symbols` are in the
   builtins archive. Read `nm` to EOF.
2. **Replay**: `replay-validate.sh`'s logic, ported. Build a C and a C++
   program from the TOML alone, the way Kairo reads it, with the MSVC
   `-idirafter` and `cc_defines` handling and `-resource-dir=<root>/compiler-rt`
   for ELF.
3. **Kairo**: if `KAIRO` is set, build the three programs (`test.k`,
   `floats.k` returning 5, `tfbf.k` returning 1).
4. **Run**:
   - host-native arches run directly.
   - Linux non-host arches run under `qemu-<arch>` (musl binaries are
     static; glibc needs an `-L` root, so for glibc this is the acceptance
     environment only).
   - wasm runs under `wasmtime` if present.
   - Windows runs under `wine` if present.
   - BSD and Darwin are link-only.
   Expected exit codes come from the programs.

`ksys build` runs steps 1–2 always, and 3–4 when the tools are present. A
missing tool counts as a skip that is reported, never as a pass.

## 11. Policy

- **Release assets** stay the fast path for the 18 published targets.
  They are produced by `ksys build --out staging/...` + `ksys pack`.
- **On-demand by default** for providers with no licence or size issue:
  musl and glibc (stubs). Their first build is a few minutes and cached
  afterwards.
- **On demand, opt-in**: mingw, freebsd, netbsd, wasi. Their base sets or
  bundles are large downloads (FreeBSD `base.txz` is about 190 MB).
- **Local only**: darwin and msvc. These need `--input`. Packs exclude
  `local_only`, and `redistributable=false` refuses packing outright.

## 12. Implementation layout

Python ≥ 3.11 (`tomllib`), standard library only, runs with `python3 -I`.

```
ksys/
  __main__.py      CLI
  target.py        name <-> clang triple, components, ptr_bits, objfmt
  probe.py
  quirks.py        load + match + resolve; schema validation on load
  cache.py         keys, locks, atomic stage dirs
  fetch.py         data/sources.toml, sha256-verified downloads
  runtimes.py      generic CMake driver (builtins, crt, unwind, cxxabi, cxx)
  toml_emit.py     LibcLayout + RuntimesPlan + quirk toml -> SYSROOT.toml
  validate.py
  pack.py          tar-dist.sh + emit-manifest.sh semantics
  providers/{musl,glibc,glibc_deb,mingw,freebsd,netbsd,wasi,darwin,msvc}.py
  glibc_abi/       abilist scanner (maintainer tool) + stub generator
data/
  quirks.toml  sources.toml  glibc-abi.json.zst
  shims/coff-tf-compare.c  shims/freebsd-getauxval.h
```

The `curate/*.sh` scripts stay working until their provider passes the same
validation and produces the same TOML (`diff` of the `SYSROOT.toml` and the
`tar -t` listing). Each script is removed only after that.

## 13. Slices

1. **Generic core + musl from source.** `target`, `probe`, `quirks`, `cache`,
   `runtimes`, `toml_emit`, `validate` with qemu, and the musl provider.
   Done when all 5 current musl sysroots rebuild from source, match the
   current TOMLs, pass validation (and run under qemu), and one new arch
   (riscv32 or armv6) builds from a name alone.
2. **glibc stubs.** ABI-db scanner, stub generator, crt/nonshared from
   source, and section 5's acceptance test. Done when the test passes at
   2.31, 2.28 and 2.35.
3. **Port the rest** onto the interface: mingw (bundle first), freebsd,
   netbsd, wasi, then msvc and darwin with `--input`. Done when
   `curate/*.sh` can be deleted. Caveat: `darwin.sh` runs on a Mac today,
   and building Darwin runtimes from Linux (ld64.lld against the SDK's
   `.tbd` stubs) has not been tried. See D5.
4. **pack/manifest**, then the Kairo hook.

## 14. Open decisions

- **D1: glibc headers.** (a) Per-version `make install-headers` from each
  `X.Y` tarball. This is exact, but glibc's configure may refuse clang;
  check that first. (b) Latest headers plus version guards, as Zig does.
  This is smaller, but means maintaining patches. Check before choosing:
  install headers for 2.31 and 2.38 and diff them. If the diff is mostly
  redirects/macros that a handful of guards cover, choose (b). Otherwise
  choose (a).
- **D2: BSD base versions.** Keep FreeBSD 14.4 / NetBSD 10.1, move to
  14.5 / 10.2, or move to 15.1 / 11.0. The base release is the compat floor
  for static binaries, so newer means fewer hosts. This becomes
  `provider.versions().default` and isn't a code decision.
- **D3: kernel headers for musl.** `make headers_install` from a Linux
  tarball (big download, exact version) or sabotage `kernel-headers`
  (small, what musl-cross-make uses, lags upstream).
- **D4: Kairo hook.** Whether Kairo calls `ksys` at all, or whether users
  run `ksys ensure` themselves and pass `--sysroot`. Is the `clang_triple`
  TOML key adopted?
- **D5: Darwin from Linux.** Try a cross build of the Darwin runtimes from
  Linux against a user-supplied SDK. If it fails, the darwin provider stays
  "run on a Mac".
- **D6: cache sharing.** Is the cache per user only, or is there an
  optional shared/CI cache (a read-only `KSYS_CACHE_RO` path checked
  first)?
