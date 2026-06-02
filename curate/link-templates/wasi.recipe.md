# wasi link recipe (validated wasm32-wasi, RAN via node, 2026-06-01)

From wasi-sdk-33 (LLVM 22.1.0, git 4434dabb6991 the EXACT commit the Kairo fork
clang-22 is built from, so libc++ ABI matches). The C++ test compiled, linked via
wasm-ld, and RAN under `node --experimental-wasm-exnref` returning exit 12.

## Validated command (what Kairo must reproduce)

    clang --target=wasm32-wasi --sysroot=<root> \
      -fwasm-exceptions -nostdlibinc -nostdinc++ \
      -isystem <root>/include/wasm32-wasi/eh/c++/v1 \
      -isystem <root>/include/wasm32-wasi \
      t.cpp -o out.wasm \
      -L<root>/lib/wasm32-wasi/eh -L<root>/lib/wasm32-wasi \
      -lc++ -lc++abi -lunwind

## Layout + variants
- wasi ships an EH / noEH libc++ split. We use the **eh** (exception-enabled)
  variant: headers in `include/wasm32-wasi/eh/c++/v1`, archives in
  `lib/wasm32-wasi/eh`. Requires `-fwasm-exceptions` (captured in extra_cflags).
- crt: `crt1-command.o` (from sysroot lib/wasm32-wasi); no crtn/end.
- Linker is wasm-ld (driver auto-selects; no `linker` field needed).
- compiler-rt **builtins** come from the compiler resource dir
  (`lib/wasm32-unknown-wasi/libclang_rt.builtins.a`), NOT the sysroot.

## Notes
- `--target=wasm32-wasi` warns deprecated (favors wasm32-wasip1) but links+runs.
  Asset/triple kept as wasm32-wasi to match sysroot dir names; Kairo can remap.
- Running needs an exnref-capable runtime (the wasm exception-handling proposal).
  node >= 24 with `--experimental-wasm-exnref`. Link-only otherwise.
