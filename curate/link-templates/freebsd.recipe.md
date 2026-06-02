# freebsd link recipe (validated x86_64 + aarch64, 2026-06-01)

C interop only (`has_libcxx=false`): base libc++ is not LLVM 22, so its ABI
would clash with the Kairo compiler. The C test (`strcpy`/`strlen`) link-clean
on both arches.

## Validated command (what Kairo must reproduce)

    clang --target=<triple> --sysroot=<root> \
      -nostdlibinc -rtlib=libgcc -fuse-ld=lld \
      t.c -o out \
      -L<root>/usr/lib -L<root>/lib -lc

## Layout (NOT flattened)

usr/include + usr/lib + lib are preserved at the same depth, because FreeBSD's
`usr/lib` is full of `../../lib/<x>.so.N` relative symlinks. Flattening would
break them; the split keeps every symlink resolving with zero rewriting.

## crt + runtime
- crt: `crt1.o crti.o` ... `crtn.o` plus `crtbegin.o`/`crtend.o` ALL shipped in
  the sysroot `usr/lib/` (FreeBSD uses its own libgcc, not compiler-rt).
- `-rtlib=libgcc` (libgcc shipped in usr/lib), NOT compiler-rt.

## FORK GAP (flagged)
Both system and fork `ld.lld` are "not built with zlib support"; FreeBSD's crt
objects carry `ELFCOMPRESS_ZLIB` debug sections, so a direct link aborts.
Soundness was proven by linking against `llvm-objcopy --decompress-debug-sections`
COPIES (artifact left pristine). The Kairo lld must be built WITH zlib to link
FreeBSD directly.
