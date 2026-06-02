# linux-musl link recipe (validated on x86_64-linux-musl, 2026-06-01)

Derived from `clang-22 -###` (fork 22.1.0) against `staging/x86_64-linux-musl`,
then confirmed by compiling + static-linking + **running** a real C++ program
(`std::vector<std::string>` + `throw`/`catch std::runtime_error`) exit code
matched expected `what()` length.

## Validated command (what Kairo must reproduce)

    clang --target=<triple> --sysroot=<root> -static \
      -nostdlibinc -nostdinc++ \
      -isystem <root>/include/c++/v1 -isystem <root>/include \
      -rtlib=compiler-rt -unwindlib=libunwind \
      t.cpp -o out \
      -L<root>/lib -lc++ -lc++abi -lunwind

## crt ordering (from -###)

    crt1.o  crti.o  <clang_rt.crtbegin>  <objs>  <libs>  <clang_rt.crtend>  crtn.o

- `crt1.o crti.o` ... `crtn.o`  -> shipped in sysroot `lib/`
- `clang_rt.crtbegin-<arch>.o` / `clang_rt.crtend-<arch>.o` -> from the
  compiler's compiler-rt **resource dir**, NOT the sysroot (hence absent from
  crt_startup / crt_end).

## Notes
- The driver does NOT auto-add `-lc++ -lc++abi`; they must be explicit
  (captured in `libcxx_link`).
- Unwinder is `-l:libunwind.a` (llvm-libunwind static), not libgcc_eh.
- Builtins are compiler-rt (`-rtlib=compiler-rt`), not libgcc.
- `-nostdlibinc` keeps compiler builtin headers (stddef.h etc.) but drops host
  system headers; `-nostdinc++` drops the host libc++ (which is glibc-built and
  fails with "unknown rune table" against musl).
