# linux-gnu link recipe (validated on all 5 arches, 2026-10-07)

glibc 2.31 (Ubuntu 20.04 focal) linked dynamically; libc++, libc++abi,
libunwind and compiler-rt built from llvm-project 22.1.0 and linked
statically. Pipeline: `fetch-glibc.sh` -> `build-glibc-runtimes.sh` ->
`glibc.sh` -> `tar-dist.sh`.

## Why 2.31

The oldest glibc every target ships with: Ubuntu 18.04 (2.27) has no
riscv64. libc++ itself supports glibc >= 2.24. Binaries run on any glibc
>= 2.31; in practice they need less (see below).

## Validated

A C++ program (std::thread, a 64-bit std::atomic, throw/catch through
libunwind + libc++abi, iostream) compiled with

    clang++ --target=<triple> -nostdlibinc -nostdinc++ \
      -isystem <root>/include/c++/v1 -isystem <root>/include/<multiarch> \
      -isystem <root>/include -fPIC -c t.cpp

and linked with the exact argv `kairo --print-ld-args` emits for the sysroot
(PIE: Scrt1.o crti.o clang_rt.crtbegin.o <objs> -lc++ -lc++abi -lunwind
builtins -lm -lpthread -ldl -lc builtins clang_rt.crtend.o crtn.o).

| target                 | newest GLIBC_ symbol needed | ran        |
|------------------------|-----------------------------|------------|
| x86_64-linux-gnu       | 2.16                        | yes        |
| i686-linux-gnu         | 2.16                        | yes        |
| aarch64-linux-gnu      | 2.17                        | no (qemu)  |
| armv7-linux-gnueabihf  | 2.16                        | no (qemu)  |
| riscv64-linux-gnu      | 2.27 (riscv64's first glibc)| no (qemu)  |

Kairo programs build and link for all five (2026-10-07, with Kairo's
driver-derived target flags and the clang __float128 patch): `hello.k`
through std::io, and a program computing in i128, f128, f16 and bf16 whose
exit code checks each. Both run correctly on x86_64 and i686.

compiler-rt is built with COMPILER_RT_ENABLE_SOFTWARE_INT128 by Kairo's own
clang, so the 32-bit sysroots carry the __int128 (__divti3, ...) and
quad-float (__addtf3, __multf3, ...) routines that i128 and f128 lower to.

## Notes
- `libc_link` carries -lpthread and -ldl: in 2.31 they are still separate
  libraries, and libc++ / libunwind use both.
- libc.so / libm.so are rewritten to bare names; lld resolves a bare name in
  a linker script through -L.
- glibc's stub `.so.6` files are only link inputs; the target's own glibc
  is what runs.
