# kairo-sysroots

Hermetic, pre-built sysroots for cross-compiling with **Kairo** (Clang-as-a-library, forked from LLVM 22.1.0), and the scripts that build them.

A sysroot here is a self-contained directory holding a target's C library headers and archives, a static libc++ (where the target has one), the compiler-rt builtins, and a `SYSROOT.toml` that tells Kairo how to compile and link against it. Kairo never uses the host's headers or libraries, so a build gives the same result on any machine.

- **Release assets** (tarballs plus `manifest.json`) are on GitHub Releases under the tag `v1-llvm22`.
- **This repository** holds only the curation pipeline (`curate/`) and provenance (`DOWNLOADS.md`). Tarballs are never committed.

---

## Contents

1. [Targets](#targets)
2. [Using a sysroot](#using-a-sysroot)
3. [Repository layout](#repository-layout)
4. [SYSROOT.toml reference](#sysroottoml-reference)
5. [manifest.json reference](#manifestjson-reference)
6. [Building sysroots from source](#building-sysroots-from-source)
7. [Local-only targets: MSVC and Darwin](#local-only-targets-msvc-and-darwin)
8. [Validating a sysroot](#validating-a-sysroot)
9. [Cutting a release](#cutting-a-release)
10. [Licensing](#licensing)
11. [Known gaps](#known-gaps)

---

## Targets

### Shipped in the release

| Sysroot (`--target`) | Clang triple | libc | libc++ | Linking |
|---|---|---|---|---|
| `x86_64-linux-musl` | `x86_64-unknown-linux-musl` | musl 1.2.6 | yes | fully static |
| `aarch64-linux-musl` | `aarch64-unknown-linux-musl` | musl 1.2.6 | yes | fully static |
| `armv7-linux-musl` | `armv7-unknown-linux-musl` | musl 1.2.6 | yes | fully static |
| `i686-linux-musl` | `i686-unknown-linux-musl` | musl 1.2.6 | yes | fully static |
| `riscv64-linux-musl` | `riscv64-unknown-linux-musl` | musl 1.2.6 | yes | fully static |
| `x86_64-linux-gnu-glibc2.31` | `x86_64-linux-gnu` | glibc 2.31 | yes | glibc dynamic, libc++ static |
| `aarch64-linux-gnu-glibc2.31` | `aarch64-linux-gnu` | glibc 2.31 | yes | glibc dynamic, libc++ static |
| `armv7-linux-gnueabihf-glibc2.31` | `armv7-linux-gnueabihf` | glibc 2.31 | yes | glibc dynamic, libc++ static |
| `i686-linux-gnu-glibc2.31` | `i686-linux-gnu` | glibc 2.31 | yes | glibc dynamic, libc++ static |
| `riscv64-linux-gnu-glibc2.31` | `riscv64-linux-gnu` | glibc 2.31 | yes | glibc dynamic, libc++ static |
| `x86_64-windows-gnu` | `x86_64-pc-windows-gnu` | mingw-w64 (UCRT) | yes | PE/COFF |
| `aarch64-windows-gnu` | `aarch64-pc-windows-gnu` | mingw-w64 (UCRT) | yes | PE/COFF |
| `armv7-windows-gnu` | `armv7-pc-windows-gnu` | mingw-w64 (UCRT) | yes | PE/COFF |
| `i686-windows-gnu` | `i686-pc-windows-gnu` | mingw-w64 (UCRT) | yes | PE/COFF |
| `x86_64-unknown-freebsd` | `x86_64-unknown-freebsd14.4` | FreeBSD 14.4 base | yes | fully static |
| `aarch64-unknown-freebsd` | `aarch64-unknown-freebsd14.4` | FreeBSD 14.4 base | yes | fully static |
| `x86_64-unknown-netbsd` | `x86_64-unknown-netbsd10.1` | NetBSD 10.1 base | yes | fully static |
| `wasm32-wasi` | `wasm32-unknown-wasi` | wasi-libc (wasi-sdk 33) | yes | exception-enabled (`-fwasm-exceptions`) |

A binary built against the glibc 2.31 sysroots runs on any distribution with glibc 2.31 or newer (Ubuntu 20.04+, Debian 11+, RHEL 9+, Fedora 32+).

### Built locally, never shipped

| Sysroot | Why it is local only | Script | Runs on |
|---|---|---|---|
| `x86_64-windows-msvc`, `aarch64-windows-msvc` (ARM64), `i686-windows-msvc` (x86) | Microsoft CRT and Windows SDK license forbids redistribution | `curate/msvc.sh` | Linux, using an `xwin` splat |
| `arm64-apple-macosx`, `arm64e-apple-macosx`, `x86_64-apple-macosx` | Apple SDK license forbids redistribution | `curate/darwin.sh` | macOS with Xcode |

See [Local-only targets](#local-only-targets-msvc-and-darwin).

---

## Using a sysroot

1. **Download** the tarball for your target and `manifest.json` from the `v1-llvm22` release.
2. **Verify** it against the manifest:
   ```sh
   jq -r '.targets["x86_64-linux-musl"].sha256' manifest.json
   sha256sum x86_64-linux-musl-llvm22.tar.xz
   ```
3. **Extract** it anywhere. Every tarball's root directory is the sysroot name:
   ```sh
   tar -xJf x86_64-linux-musl-llvm22.tar.xz -C ~/kairo-sysroots/   # -> ~/kairo-sysroots/x86_64-linux-musl/
   ```
4. **Point Kairo at it** with `--sysroot`. `--resource-dir` names Kairo's clang resource directory, where clang's builtin headers such as `stddef.h` live:
   ```sh
   kairo --sysroot=$HOME/kairo-sysroots/x86_64-linux-musl \
         --resource-dir=<kairo>/build/llvm/lib/clang/22 \
         --target x86_64-linux-musl  main.k -o main
   ```

Kairo reads the sysroot's `SYSROOT.toml` to find include and library directories, startup objects, link libraries and compiler-rt. Nothing else needs configuring.

---

## Repository layout

```
curate/                    the pipeline: one script per family, plus packaging
  fetch-*.sh               download upstream packages into extract/
  build-glibc-runtimes.sh  build libc++/libunwind/compiler-rt for the glibc targets
  build-builtins.sh        build compiler-rt builtins for linux-musl and windows-gnu
  build-bsd-runtimes.sh    build libc++/libc++abi/libunwind + builtins for FreeBSD/NetBSD
  build-wasi-builtins.sh   build compiler-rt builtins for wasm32-wasi
  <family>.sh              stage extract/ -> staging/<sysroot>/ and write SYSROOT.toml
  decompress-debug.sh      decompress zlib debug sections (so any lld can link)
  tar-dist.sh              staging/<sysroot>/ -> dist/<sysroot>-llvm22.tar.xz
  emit-manifest.sh         dist/*.tar.xz -> dist/manifest.json
  replay-validate.sh       compile and link a test program from SYSROOT.toml alone
  link-templates/          validated link recipe per family (the source of truth)
DOWNLOADS.md               every upstream URL and version used
dist/manifest.json         the release manifest (committed; tarballs are not)

extract/        (gitignored) unpacked upstream inputs
runtimes-build/ (gitignored) CMake build trees for the LLVM runtimes
runtimes-out/   (gitignored) installed runtimes, before staging
staging/        (gitignored) finished sysroots, one directory each
```

Not every script is executable in git, so this README runs them all as `bash curate/<script>`.

---

## SYSROOT.toml reference

Every sysroot has a flat `SYSROOT.toml` at its root. All paths are relative to the sysroot directory.

| Key | Type | Meaning | Read by Kairo |
|---|---|---|---|
| `triple` | string | Sysroot name (matches the `--target` spelling) | yes |
| `llvm_version` | string | LLVM version the C++ runtimes were built with | yes |
| `family` | string | `linux-musl`, `linux-gnu`, `windows-gnu`, `windows-msvc`, `freebsd`, `netbsd`, `wasi`, `darwin` | yes |
| `sysroot` | string | Root for the paths below (always `.`) | yes |
| `include_dirs` | string[] | Header search dirs. Dirs containing `/c++/` go first, then clang's resource headers, then the rest | yes |
| `lib_dirs` | string[] | Library search dirs | yes |
| `has_libcxx` | bool | Whether a static libc++ is present (needed for Kairo programs) | yes |
| `static` | bool | ELF: fully static link. windows-msvc: static CRT (`/MT`) | yes |
| `crt_startup` / `crt_end` | string[] | Startup/teardown objects in link order | yes |
| `libc_link` | string[] | C library inputs, in the linker's own syntax (`-lc` for ELF, `libcmt.lib` for lld-link) | yes |
| `libcxx_link` | string[] | C++ runtime inputs, same syntax | yes |
| `rtlib` / `unwindlib` | string | `compiler-rt`, `libunwind` | yes |
| `linker` | string | `lld` or `lld-link` | yes |
| `resource_dir` | string | Sysroot-relative dir holding compiler-rt (`compiler-rt/lib/<triple>/` or `compiler-rt/lib/windows/`) | yes |
| `cc_isolation` | string[] | Flags that cut off host headers (`-nostdlibinc -nostdinc++`) | no (Kairo hard-codes them) |
| `glibc_version` | string | linux-gnu only: the glibc floor | no |
| `cc_defines` | string[] | Macros every C/C++ TU must define (windows-msvc: `_CRT_STDIO_ISO_WIDE_SPECIFIERS`) | **not yet** |
| `local_only` | string[] | Dirs holding vendor files that must never ship. `tar-dist.sh` excludes them | no |
| `redistributable` | bool | `false`: `tar-dist.sh` refuses to pack the sysroot (darwin) | no |
| `msvc_crt` | string | windows-msvc: `static` | no |

"Read by Kairo" is current as of `kairo-lang/Linker/API/SysrootManifest.k`, which ignores unknown keys. The exact link line each family needs is in `curate/link-templates/<family>.recipe.md`.

---

## manifest.json reference

`dist/manifest.json` is what Kairo downloads to find and verify sysroots. `curate/emit-manifest.sh` generates it from the tarballs in `dist/` and each sysroot's `SYSROOT.toml`. Never edit it by hand.

```json
{
  "release": "v1-llvm22",
  "llvm_version": "22.1.0",
  "targets": {
    "x86_64-linux-gnu-glibc2.31": {
      "asset": "x86_64-linux-gnu-glibc2.31-llvm22.tar.xz",
      "url": "https://github.com/kairolang/kairo-sysroots/releases/download/v1-llvm22/...",
      "sha256": "…",
      "size": 5616196,
      "family": "linux-gnu",
      "has_libcxx": true,
      "glibc_version": "2.31",
      "resource_dir": "compiler-rt"
    }
  }
}
```

Optional per-target keys: `glibc_version`, `resource_dir`, `local_only`. The download base URL is `BASE` in `emit-manifest.sh`.

---

## Building sysroots from source

### Prerequisites

- Linux x86_64 host with `bash`, `cmake`, `ninja`, `tar`/`xz`, `curl`, `jq`, `llvm-objcopy`, `llvm-readobj`.
- A kairo-lang checkout next to this repo (`../kairo-lang`) with:
  - the LLVM fork source at `Lib/llvm-runtimes`,
  - its built clang at `build/llvm/bin/clang` (and `clang++`, `clang-cl`, `lld-link`). Build them with `ninja -C build/llvm clang lld`, plus `ln -sf clang build/llvm/bin/clang++`.

  The fork's clang is required wherever runtimes are built from source. It carries the `__float128` patches, without which compiler-rt's quad-float routines silently compile to nothing.
- For MSVC: `xwin` (`cargo install xwin --locked`).

Every staging script writes `staging/<sysroot>/` and replaces anything already there.

### Per-family pipelines

Upstream URLs and exact versions for every input are in `DOWNLOADS.md`.

**linux-gnu (glibc 2.31)**: fully scripted.
```sh
bash curate/fetch-glibc.sh              # Ubuntu 20.04 debs -> extract/<name>/
bash curate/build-glibc-runtimes.sh     # libc++, libc++abi, libunwind, compiler-rt from source
bash curate/glibc.sh                    # -> staging/<arch>-linux-gnu*-glibc2.31/
```

**linux-musl**: download the Alpine `musl-dev`, `linux-headers`, `libc++-static` and `llvm-libunwind-static` apks listed in `DOWNLOADS.md`, and unpack each arch's set into `extract/<arch>-linux-musl/`. Then:
```sh
bash curate/fetch-musl-libcxx.sh        # grafts libc++ headers into extract/
bash curate/fetch-musl-compiler-rt.sh   # Alpine crtbegin/crtend -> staging/compiler-rt-musl/
bash curate/musl.sh                     # -> staging/<arch>-linux-musl/
bash curate/build-builtins.sh           # compiler-rt builtins from the fork (f128, i128, bf16)
```

**windows-gnu**: unpack `llvm-mingw-20260224-ucrt-ubuntu-22.04-x86_64.tar.xz` into `extract/mingw/`, then run `bash curate/mingw.sh` and `bash curate/build-builtins.sh`. The builtins are built from the fork rather than taken from llvm-mingw. llvm-mingw's were built by a stock clang and lack f128 and the 32-bit i128 routines.

**FreeBSD / NetBSD**: unpack FreeBSD `base.txz` into `extract/<arch>-unknown-freebsd/`, and NetBSD `base.tar.xz` plus `comp.tar.xz` into `extract/x86_64-unknown-netbsd/`. Then run `bash curate/freebsd.sh` or `bash curate/netbsd.sh`, then `bash curate/build-bsd-runtimes.sh`. The staging scripts keep `usr/include`, `usr/lib` and `lib` as they are, so the base system's relative symlinks still resolve. `build-bsd-runtimes.sh` adds LLVM 22 libc++/libc++abi/libunwind (`libcxx/`) and compiler-rt builtins (`compiler-rt/lib/<os>/`) built from the fork. FreeBSD's base libc++ is 19, and NetBSD's base has only libstdc++.

**wasm32-wasi**: unpack `wasi-sysroot-33.0+m.tar.gz` into `extract/wasm32-wasi/`, then `bash curate/wasi.sh`. Then run `bash curate/build-wasi-builtins.sh` to build the compiler-rt builtins (including bf16) from the fork's source into `compiler-rt/lib/wasm32-unknown-wasi/`.

**windows-msvc / darwin**: see the next section.

---

## Local-only targets: MSVC and Darwin

Microsoft's and Apple's licenses allow using their SDKs but not redistributing them. This repository therefore ships only **instructions and our own compiled code**, never vendor files. **You accept the vendor license yourself, on your own machine.**

### windows-msvc (x86_64, aarch64/ARM64, i686/x86)

1. **Fetch the CRT and SDK.** This step accepts [Microsoft's license terms](https://go.microsoft.com/fwlink/?LinkId=2086102); read them first:
   ```sh
   xwin --accept-license --arch x86_64,aarch64,x86 \
        --cache-dir extract/xwin-cache splat --output extract/xwin
   ```
   That's about 1.6 GB. It writes `extract/xwin/{crt,sdk}` with lowercase symlinks, so `#include <Windows.h>` resolves on a case-sensitive filesystem.
2. **Build the sysroots:**
   ```sh
   bash curate/msvc.sh ../kairo-lang                  # all three
   bash curate/msvc.sh ../kairo-lang arm64 i386       # aliases accepted
   ```
   For each arch, this copies the splat into `staging/<arch>-windows-msvc/msvc/` and builds libc++ (vcruntime ABI, static CRT `/MT`) and the compiler-rt builtins with the fork's `clang-cl`. It writes `SYSROOT.toml`, then links a C++ test program twice: once directly and once replayed from the TOML.

Resulting layout:
```
<arch>-windows-msvc/
  SYSROOT.toml
  include/c++/v1/                                   ours
  lib/libc++.lib                                    ours
  compiler-rt/lib/windows/clang_rt.builtins-<arch>.lib   ours
  msvc/                                             Microsoft, local_only
```
Binaries are fully static: an x86_64 test binary imports only `KERNEL32.dll` and needs no VC++ redistributable.

**What a consumer must do** (details in `curate/link-templates/windows-msvc.recipe.md`):
- Search the CRT/SDK headers *after* clang's resource headers.
- Define `_CRT_STDIO_ISO_WIDE_SPECIFIERS`. libc++ is built with it, and the UCRT's `/failifmismatch` rejects a mismatch at link time.
- Compile in MS language mode (`-fms-extensions -fms-compatibility`).

`tar-dist.sh` packs these sysroots **without** `msvc/`. The result is about 1.4 MB of LLVM-licensed code, and the user supplies their own splat in `msvc/`.

### darwin (arm64, arm64e, x86_64)

Run on a Mac with Xcode installed. Apple's license only allows the SDK on Apple-branded hardware.
```sh
bash curate/darwin.sh <kairo-repo> arm64 x86_64 arm64e
```
This stages the local Apple SDK (`xcrun --sdk macosx --show-sdk-path`), with Apple's libc++ replaced by ours and compiler-rt quad-float builtins added. Its `SYSROOT.toml` says `redistributable = false`, and `tar-dist.sh` refuses to pack it.

---

## Validating a sysroot

`replay-validate.sh` reads only `SYSROOT.toml`, rebuilds the clang command from it, and compiles and links a C++ program that throws and catches (or a C program when `has_libcxx = false`). If the target matches the host, it also runs the result; wasi runs under `node`.

```sh
# ELF targets: point -resource-dir at the sysroot's compiler-rt
bash curate/replay-validate.sh staging/x86_64-linux-musl ../kairo-lang/build/llvm/bin/clang \
     -resource-dir=staging/x86_64-linux-musl/compiler-rt

# windows-msvc: builtins are found through resource_dir automatically
bash curate/replay-validate.sh staging/x86_64-windows-msvc ../kairo-lang/build/llvm/bin/clang \
     -B../kairo-lang/build/llvm/bin
```

The strongest test is building a real Kairo program against the sysroot. From the kairo-lang checkout:
```sh
build/x86_64-linux-gnu/debug/bin/kairo --sysroot=<sysroot-dir> \
  --resource-dir=$PWD/build/llvm/lib/clang/22 \
  --builtins-dir=$PWD/Lib/builtin --std-dir=$PWD/Lib/std \
  test.k --cache-dir=/tmp/kais -o test --target <sysroot-name>
```

---

## Cutting a release

```sh
bash curate/tar-dist.sh                  # every sysroot in staging/ (darwin skipped, msvc/ excluded)
bash curate/tar-dist.sh x86_64-linux-musl   # or specific ones
bash curate/emit-manifest.sh                # regenerate dist/manifest.json; checks it is valid JSON
gh release upload v1-llvm22 dist/* --clobber
```

- `tar-dist.sh` runs `decompress-debug.sh` first, so no tarball contains zlib-compressed debug sections, which an lld built without zlib refuses to link. It then packs with sorted names and zero owner, keeping symlinks as symlinks.
- **License guard:** `tar-dist.sh` refuses any sysroot whose TOML says `redistributable = false`, excludes every `local_only` dir, and deletes the tarball if a `local_only` path still slipped in.
- Commit the regenerated `dist/manifest.json`. Kairo pins sysroots by its sha256 values.

---

## Licensing

| Part | License |
|---|---|
| Scripts in this repository | as stated in the repository |
| libc++, libc++abi, libunwind, compiler-rt (built here or by upstream) | Apache-2.0 WITH LLVM-exception |
| musl | MIT |
| glibc | LGPL-2.1-or-later (dynamically linked; the target system supplies the real `.so`) |
| mingw-w64 / llvm-mingw | ZPL-2.1 and public domain (see llvm-mingw) |
| FreeBSD / NetBSD base | BSD |
| wasi-libc / wasi-sdk | Apache-2.0 WITH LLVM-exception, MIT, CC0 |
| Microsoft CRT + Windows SDK | Microsoft license. **Never redistributed**: you fetch it with `xwin` and accept the terms yourself |
| Apple macOS SDK | Apple Xcode/SDK license. **Never redistributed**: use your local Xcode on Apple hardware |

---

## Known gaps

- **compiler-rt builtins need the fork's clang.** Every builtins archive is built from Kairo's LLVM. The fork carries `__float128` on every target, bf16 lowering for WebAssembly, and `__trunctfbf2` beyond x86_64. A stock LLVM 22 builds archives without f128 on most targets, without bf16 on wasm, and without the 32-bit i128 routines unless `-fforce-enable-int128` reaches the compiler. The build scripts check for these symbols and stop if any is missing.
- **COFF has no symbol aliases.** compiler-rt defines `__eqtf2`, `__netf2`, `__lttf2`, `__gttf2` and `__cmptf2` as aliases, and they vanish on windows-msvc. `msvc.sh` adds them as forwarding functions. windows-gnu is unaffected: MinGW's COFF supports aliases through weak externals.
- **Kairo on windows-msvc.** The sysroots link correctly through the clang driver, but Kairo can't build for them until kairo-lang:
  1. passes the MS language-mode flags on its cc1 line (`ClangBackend.k`, `_driver_target_args`),
  2. stops importing `unistd.h` unconditionally (`Lib/std/io.k`),
  3. reads `cc_defines` from `SYSROOT.toml`.
- **FreeBSD/NetBSD and base C++ libraries.** Kairo binaries link LLVM 22 libc++ statically. A system C++ library built against the base runtime (libc++ 19/libcxxrt on FreeBSD, libstdc++ on NetBSD) can still be linked, but C++ objects can't cross between the two runtimes. Plain C libraries are unaffected.
