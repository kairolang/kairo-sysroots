# netbsd link recipe (validated x86_64, 2026-06-01)

C interop only (`has_libcxx=false`). Same structure-preserving layout as FreeBSD.
The C test link-clean.

## Validated command (what Kairo must reproduce)

    clang --target=x86_64-unknown-netbsd --sysroot=<root> \
      -nostdlibinc -fuse-ld=lld \
      t.c -o out \
      -L<root>/usr/lib -L<root>/lib -lc

## crt + notes
- Startup object is `crt0.o` (NOT crt1.o), then `crti.o` ... `crtn.o` shipped in
  the sysroot `usr/lib/`.
- Default link is just `-lc`.
- usr/include + usr/lib + lib preserved at depth to keep relative `.so` symlinks
  resolving.
