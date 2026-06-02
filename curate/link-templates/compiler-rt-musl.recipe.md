# musl compiler-rt (resolves the fork-build gap, 2026-06-01)

The Kairo fork clang-22 resource dir lacks per-target compiler-rt, so cross-arch
musl links failed with `cannot open crtend.o`. Fixed by sourcing Alpine's prebuilt
`compiler-rt-22.1.3-r0` (LLVM 22.1.x, ABI-compatible) for all 5 arches.

## What ships (per arch, the ONLY 3 files a link needs)

    lib/clang/22/lib/<effective-triple>/
        libclang_rt.builtins.a    # compiler builtins (__udivti3, etc.)
        clang_rt.crtbegin.o       # C++ static init/teardown frame
        clang_rt.crtend.o

Effective triples (from `clang --target=<t> -print-effective-triple`):
x86_64/aarch64/armv7/i686/riscv64-unknown-linux-musl. The sanitizer/xray/profile
archives in the apk are dropped not needed to link.

## This is the COMPILER's resource dir, NOT a sysroot
Kairo unpacks `compiler-rt-musl-llvm22.tar.xz` into its clang install
(`<clang>/lib/clang/22/...`), then links with `-resource-dir` pointing there (or
it's the default resource dir). The sysroot tarballs stay unchanged.

## Validated
All 5 musl targets link clean with `-resource-dir=<bundle>/lib/clang/22`:
x86_64 RUNS (exit 12); aarch64/armv7/riscv64/i686 link-only here (cross-arch,
no qemu) each produces a correct static ELF for its arch.

Provenance: see DOWNLOADS.md `[musl compiler-rt]`. Staged by
`curate/fetch-musl-compiler-rt.sh`. Note the i686 apk's internal dir is
`i586-alpine-linux-musl`; armv7's is `armv7-alpine-linux-musleabihf` (builtins
suffix `-armhf`).
