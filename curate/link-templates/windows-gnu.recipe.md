# windows-gnu (llvm-mingw) link recipe (validated all 4 arches, 2026-06-01)

Derived from llvm-mingw-20260224 (UCRT). Validated by compiling + linking the
real C++ test (`std::vector<std::string>` + throw/catch) to a PE executable for
x86_64 / aarch64 / armv7 / i686, each link-clean with the bundled compiler-rt.

## Validated command (what Kairo must reproduce)

    clang --target=<triple> --sysroot=<root> \
      -nostdlibinc -nostdinc++ \
      -isystem <root>/include/c++/v1 -isystem <root>/include \
      -rtlib=compiler-rt -unwindlib=libunwind -fuse-ld=lld \
      t.cpp -o out.exe \
      -L<root>/lib -lc++ -lunwind \
      <driver-supplied system libs>

## crt + libs

- crt: `crt2.o crtbegin.o` ... `crtend.o` these ARE shipped in the sysroot
  `lib/` (unlike musl). Captured in crt_startup / crt_end.
- compiler-rt **builtins** still come from the compiler resource dir
  (`lib/clang/22/lib/windows/libclang_rt.builtins-<arch>.a`), NOT the per-arch
  sysroot same model as musl.
- libc chain (driver-assembled, captured in libc_link): `-lmingw32 -lmoldname
  -lmingwex -lmsvcrt -ladvapi32 -lshell32 -luser32 -lkernel32`.

## Notes
- `libc++.dll.a` bundles libc++abi, so link `-lc++` ONLY adding `-lc++abi`
  causes multiple-definition errors. Unwind is separate: `-lunwind` required.
- The driver ignores `-stdlib=libc++`; libc++/unwind must be explicit.
- `-fuse-ld=lld` required (host GNU ld is x86-only / wrong-format on cross arches).
