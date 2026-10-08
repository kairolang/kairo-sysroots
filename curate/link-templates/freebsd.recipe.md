# freebsd link recipe (validated x86_64 + aarch64, 2026-10-08)

FreeBSD 14.4 base (libc, crt objects, headers), plus LLVM 22 libc++,
libc++abi, libunwind and compiler-rt builtins built from Kairo's LLVM by
`build-bsd-runtimes.sh`, all linked statically. Pipeline: `freebsd.sh` ->
`build-bsd-runtimes.sh` -> `tar-dist.sh`.

## Why not the base C++ runtime

FreeBSD 14.4 ships libc++ 19.1.7 on libcxxrt. Kairo's C++ interop builds
against libc++ 22 on every target. Base `libgcc.a` is compiler-rt 19 and has
no `__trunctfbf2`. The base `usr/include/c++/v1` (libc++ 19) is left in place
for C interop with base C++ libraries; ours is in `libcxx/` and comes first.

## Layout (base tree NOT flattened)

    usr/include, usr/lib, lib                 FreeBSD base, as shipped
    libcxx/include/c++/v1                     libc++ 22 headers
    libcxx/lib/{libc++,libc++abi,libunwind}.a
    compiler-rt/lib/freebsd/libclang_rt.builtins-<arch>.a

`usr/include`, `usr/lib` and `lib` keep their depth because FreeBSD's
`usr/lib` is full of `../../lib/<x>.so.N` relative symlinks.

## Validated (what Kairo produces, `kairo --print-ld-args`)

    ld.lld -m elf_x86_64_fbsd --eh-frame-hdr -static -o out \
      usr/lib/crt1.o usr/lib/crti.o usr/lib/crtbeginT.o <objs> \
      -Llibcxx/lib -Lusr/lib -Llib \
      --start-group -lc++ -lc++abi -lunwind \
        compiler-rt/lib/freebsd/libclang_rt.builtins-x86_64.a -lm -lthr -lc \
      --end-group usr/lib/crtend.o usr/lib/crtn.o

`crtbeginT.o`/`crtend.o` are added by Kairo's linker, not listed in the TOML
(listing them too gives `duplicate symbol: __dso_handle`). Kairo programs
(test.k, f128/i128/f16/bf16 arithmetic, f128 -> bf16) build and link as static
FreeBSD 14.4 executables on x86_64 and aarch64. Not run (no FreeBSD host).

## Build notes

- aarch64: LLVM 22's libunwind calls `getauxval()` whenever `<sys/auxv.h>`
  exists. FreeBSD 14 has only `elf_aux_info()`, so `build-bsd-runtimes.sh`
  force-includes a `getauxval` shim built on it (libunwind's SME check only).
- Base crt objects carry zlib-compressed debug sections; `tar-dist.sh`
  decompresses them (`decompress-debug.sh`) so any lld links them.
