# netbsd link recipe (validated x86_64, 2026-10-08)

NetBSD 10.1 base (libc, crt objects, headers), plus LLVM 22 libc++,
libc++abi, libunwind and compiler-rt builtins built from Kairo's LLVM by
`build-bsd-runtimes.sh`, all linked statically. Pipeline: `netbsd.sh` ->
`build-bsd-runtimes.sh` -> `tar-dist.sh`.

## Why not the base C++ runtime

NetBSD's base toolchain is GCC 10: it ships libstdc++ and libsupc++, no
libc++. Its `libgcc.a` is GCC's and has no f16 or bf16 routines.

## Layout

Same as FreeBSD: base `usr/include`, `usr/lib`, `lib` at their depth (relative
`.so` symlinks), plus `libcxx/` and `compiler-rt/lib/netbsd/`.

## Validated

Startup is `crt0.o crti.o`, then `crtbeginT.o` (added by Kairo's linker for
-static) ... `crtend.o crtn.o`. Libraries: `-lc++ -lc++abi -lunwind
<builtins> -lm -lpthread -lc` in one group. Kairo programs (test.k,
f128/i128/f16/bf16 arithmetic, f128 -> bf16) build and link as static NetBSD
10.1 executables. Not run (no NetBSD host).
