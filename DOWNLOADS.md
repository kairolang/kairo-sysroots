[aarch64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/libc++-static-22.1.3-r0.apk
[aarch64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/llvm-libunwind-static-22.1.3-r0.apk
[aarch64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/musl-dev-1.2.6-r2.apk
[aarch64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/linux-headers-7.0.0-r1.apk
[armv7-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/libc++-static-22.1.3-r0.apk
[armv7-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/llvm-libunwind-static-22.1.3-r0.apk
[armv7-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/musl-dev-1.2.6-r2.apk
[armv7-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/linux-headers-7.0.0-r1.apk
[riscv64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/libc++-static-22.1.3-r0.apk
[riscv64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/llvm-libunwind-static-22.1.3-r0.apk
[riscv64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/musl-dev-1.2.6-r2.apk
[riscv64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/linux-headers-7.0.0-r1.apk
[i686-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/libc++-static-22.1.3-r0.apk
[i686-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/llvm-libunwind-static-22.1.3-r0.apk
[i686-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/musl-dev-1.2.6-r2.apk
[i686-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/linux-headers-7.0.0-r1.apk
[x86_64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/libc++-static-22.1.3-r0.apk
[x86_64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/llvm-libunwind-static-22.1.3-r0.apk
[x86_64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/musl-dev-1.2.6-r2.apk
[x86_64-linux-musl]
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/linux-headers-7.0.0-r1.apk
[amd64-freebsd]
https://download.freebsd.org/releases/amd64/14.4-RELEASE/base.txz
[aarch64-freebsd]
https://download.freebsd.org/releases/arm64/aarch64/14.4-RELEASE/base.txz
[amd64-netbsd]
https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.1/amd64/binary/sets/base.tar.xz
[amd64-netbsd]
https://cdn.netbsd.org/pub/NetBSD/NetBSD-10.1/amd64/binary/sets/comp.tar.xz
[wasm]
https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-33/wasi-sysroot-33.0+m.tar.gz
https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-33/libclang_rt-33.0+m.tar.gz
[libc++-dev headers] (pulled by curate/fetch-musl-libcxx.sh; arch x86 == i686)
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/libc++-dev-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/libc++-dev-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/libc++-dev-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/libc++-dev-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/libc++-dev-22.1.3-r0.apk
[windows-gnu] (llvm-mingw bundle: ucrt, all 4 arches + bundled compiler-rt)
https://github.com/mstorsjo/llvm-mingw/releases/download/20260224/llvm-mingw-20260224-ucrt-ubuntu-22.04-x86_64.tar.xz
[musl compiler-rt] (builtins + crtbegin/crtend; staged by curate/fetch-musl-compiler-rt.sh; arch x86==i686 dir is i586)
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/compiler-rt-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/aarch64/compiler-rt-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/armv7/compiler-rt-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/x86/compiler-rt-22.1.3-r0.apk
https://dl-cdn.alpinelinux.org/alpine/edge/main/riscv64/compiler-rt-22.1.3-r0.apk
[linux-gnu glibc 2.31] (Ubuntu 20.04 focal-updates; pulled by curate/fetch-glibc.sh; i686 == i386, armv7 == armhf)
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6-dev_2.31-0ubuntu9.18_arm64.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_arm64.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-libc-dev_5.4.0-216.236_arm64.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6-dev_2.31-0ubuntu9.18_armhf.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_armhf.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-libc-dev_5.4.0-216.236_armhf.deb
http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6-dev_2.31-0ubuntu9.18_i386.deb
http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_i386.deb
http://archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-libc-dev_5.4.0-216.236_i386.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6-dev_2.31-0ubuntu9.18_riscv64.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_riscv64.deb
http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-libc-dev_5.4.0-216.236_riscv64.deb
http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6-dev_2.31-0ubuntu9.18_amd64.deb
http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_amd64.deb
http://archive.ubuntu.com/ubuntu/pool/main/l/linux/linux-libc-dev_5.4.0-216.236_amd64.deb
[linux-gnu runtimes] built from source by curate/build-glibc-runtimes.sh: llvm-project 22.1.0 (kairo-lang/Lib/llvm-runtimes) compiler-rt, libunwind, libc++abi, libc++
[windows-msvc] (LOCAL ONLY, never redistributed: Microsoft license. Fetched by the user with xwin 0.10.0, which takes the license acceptance)
xwin --accept-license --arch x86_64,aarch64,x86 --cache-dir extract/xwin-cache splat --output extract/xwin
  Microsoft.VC.14.44.17.14.CRT (headers + x64/arm64/x86 Desktop libs)
  Win11SDK_10.0.26100 (headers, ucrt + um libs for x86_64/aarch64/x86)
[windows-msvc runtimes] built from source by curate/msvc.sh: llvm-project 22.1.0 (kairo-lang/Lib/llvm-runtimes) compiler-rt builtins, libc++ (vcruntime ABI, /MT)
