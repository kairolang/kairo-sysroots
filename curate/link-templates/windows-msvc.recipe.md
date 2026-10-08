# windows-msvc link recipe (validated on all 3 arches, 2026-10-08)

Microsoft CRT 14.44.17.14 + Windows SDK 10.0.26100 (from an xwin splat),
static CRT (/MT), with libc++ and compiler-rt builtins built from
llvm-project 22.1.0 against it. Pipeline: `xwin splat` (run by the user,
who accepts Microsoft's license) -> `msvc.sh` -> `tar-dist.sh` (ships only
our layer).

Arches: x86_64, aarch64 (Microsoft's "ARM64"), i686 (Microsoft's "x86").
32-bit ARM is not built: Microsoft's tooling for it is deprecated.

## Layout

    <root>/SYSROOT.toml
    <root>/include/c++/v1/                        ours: libc++ headers
    <root>/lib/libc++.lib                         ours: static libc++ (vcruntime ABI)
    <root>/compiler-rt/lib/windows/clang_rt.builtins-<arch>.lib   ours
    <root>/msvc/crt/{include,lib/<xa>}            Microsoft: local only
    <root>/msvc/sdk/include/{ucrt,um,shared,winrt}
    <root>/msvc/sdk/lib/{um,ucrt}/<xa>            Microsoft: local only

`<xa>` is xwin's arch name: `x86_64`, `aarch64`, `x86`. `msvc/` is listed in
`local_only`. `tar-dist.sh` excludes it and fails if any of it slips into the
tarball, so a published asset holds only our layer (about 1.4 MB). To use a
published tarball, the user drops their own xwin splat into `<root>/msvc/`.

## Validated

A C++ program (std::vector<std::string>, throw/catch via vcruntime) built
with the GNU-style driver from the sysroot alone:

    clang --target=<arch>-pc-windows-msvc -nostdlibinc -nostdinc++ \
      -isystem   <root>/include/c++/v1 \
      -idirafter <root>/msvc/crt/include -idirafter <root>/msvc/sdk/include/ucrt \
      -idirafter <root>/msvc/sdk/include/um -idirafter <root>/msvc/sdk/include/shared \
      -D_CRT_STDIO_ISO_WIDE_SPECIFIERS \
      -fms-runtime-lib=static -fexceptions -fcxx-exceptions -fuse-ld=lld \
      t.cpp -o t.exe \
      -L<root>/lib -L<root>/msvc/crt/lib/<xa> \
      -L<root>/msvc/sdk/lib/um/<xa> -L<root>/msvc/sdk/lib/ucrt/<xa> \
      -llibc++ <root>/compiler-rt/lib/windows/clang_rt.builtins-<arch>.lib

`replay-validate.sh <root>` reproduces this from SYSROOT.toml, and `msvc.sh`
runs both for every arch. Output: PE32+ x86-64 / PE32+ ARM64 / PE32 i386. The
x86_64 binary imports only KERNEL32.dll, so it needs no VC++ redistributable.
None of the binaries were run (no wine on the build host).

## Rules a consumer must follow

- **Header order**: libc++, then clang's resource headers, then the CRT/SDK
  dirs. The UCRT's `stddef.h` has no `max_align_t`, and if it is searched
  before clang's it hides the one libc++ needs. clang-cl gets this order
  from `-imsvc`. Kairo's C interop already orders `include_dirs` this way
  (`/c++/` dirs, resource dir, the rest).
- **`_CRT_STDIO_ISO_WIDE_SPECIFIERS`** (TOML `cc_defines`): libc++'s CMake
  compiles it with this define, and the UCRT stamps every object with
  `/failifmismatch` on it. A TU that includes `<stdio.h>` without the define
  fails the link:
  `lld-link: error: /failifmismatch: mismatch detected for '_CRT_STDIO_ISO_WIDE_SPECIFIERS'`.
- **MS language mode**: the CRT/SDK headers need `-fms-extensions
  -fms-compatibility` (for `#pragma pack(push)`, `__declspec`, `__unaligned`).
  The clang driver adds these for an msvc triple. A cc1-direct consumer must
  add them itself.
- `libc_link` / `libcxx_link` are lld-link inputs (`libcmt.lib`), which is how
  Kairo's COFF flavor passes them. Through the clang driver, spell them
  `-llibcmt`.
- `static = true` means the static CRT (`-fms-runtime-lib=static`), not
  `-static`.
- No libc++abi and no libunwind: exceptions and RTTI come from vcruntime, and
  unwinding is SEH.

## Known gaps

- **f128 / i128 / f16 / bf16** are supported (2026-10-08, after the fork's
  MSVC `__float128` patch). A C program doing arithmetic in all four links on
  all three arches with no undefined symbols. `msvc.sh` refuses to stage
  without `__float128` and checks that the builtins define `__addtf3`. On
  i686, `-fforce-enable-int128` has to reach clang-cl as `-Xclang
  -fforce-enable-int128`, because clang-cl ignores the plain spelling and the
  int128/TF routines then compile empty.
- **Kairo (2026-10-08)**: `kairo --target x86_64-windows-msvc` finds this
  sysroot, but its cc1 line leaves out the MS language-mode flags
  (ClangBackend.k `_driver_target_args`), and `Lib/std/io.k` imports
  `unistd.h`. Both have to change in kairo-lang before Kairo programs build
  for this target.
