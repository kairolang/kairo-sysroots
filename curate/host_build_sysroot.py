#!/usr/bin/env python3
"""Build a HOST-BUILD sysroot: a glibc target sysroot plus what building the
Kairo toolchain itself against it needs (Kairo's KAIRO_HOST_SYSROOT).

The shipped target sysroots are for compiling Kairo programs and stay exactly
as released. Building LLVM / kairo against the glibc floor needs more than a
program does:
  - zlib and zstd headers + libraries (LLVM is configured ZLIB/ZSTD=FORCE_ON
    and kairo links -lz -lzstd), from the same Ubuntu release as the libc so
    their symbol versions stay at the floor;
  - a shared libc++.so.1, because the toolchain ships ONE libc++.so.1 that
    kairo, libLLVM and libclang-cpp all link. The sysroot's libc++.a and
    libc++abi.a are PIC, so it is linked from them.
The result is a copy; the target sysroot is never modified.

  python3 curate/host_build_sysroot.py --from <target-sysroot> --out <dir>
      [--clang <clang++>] [--suite focal] [--mirror URL] [--cache <debs dir>]

Then: KAIRO_HOST_SYSROOT=<dir> (see kairo-lang Scripts/host_sysroot.py).
"""
import argparse, os, shutil, subprocess, sys, tempfile, urllib.request, pathlib

# Ubuntu 20.04 (focal) updates, matching the glibc 2.31 sysroot's libc6.
PKGS = {
    "x86_64": [
        "pool/main/z/zlib/zlib1g_1.2.11.dfsg-2ubuntu1.5_amd64.deb",
        "pool/main/z/zlib/zlib1g-dev_1.2.11.dfsg-2ubuntu1.5_amd64.deb",
        "pool/main/libz/libzstd/libzstd1_1.4.4+dfsg-3ubuntu0.1_amd64.deb",
        "pool/main/libz/libzstd/libzstd-dev_1.4.4+dfsg-3ubuntu0.1_amd64.deb",
    ],
}
MULTIARCH = {"x86_64": "x86_64-linux-gnu"}


def die(msg):
    sys.exit(f"host_build_sysroot: {msg}")


def fetch(mirror, rel, cache):
    dst = cache / os.path.basename(rel)
    if not dst.is_file():
        url = f"{mirror}/{rel}"
        print(f"fetch {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=120) as r, open(dst, "wb") as f:
            shutil.copyfileobj(r, f)
    return dst


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="src", required=True, help="target sysroot to start from")
    ap.add_argument("--out", required=True, help="output directory (replaced)")
    ap.add_argument("--arch", default="x86_64")
    ap.add_argument("--clang", default=shutil.which("clang++") or "clang++")
    ap.add_argument("--mirror", default="http://archive.ubuntu.com/ubuntu")
    ap.add_argument("--cache", default=None, help="where .debs are kept (default: <out>.debs)")
    a = ap.parse_args()

    src, out = pathlib.Path(a.src).resolve(), pathlib.Path(a.out).resolve()
    if a.arch not in PKGS:
        die(f"no package list for {a.arch}")
    if not (src / "SYSROOT.toml").is_file():
        die(f"{src} is not a sysroot (no SYSROOT.toml)")
    if shutil.which("dpkg-deb") is None:
        die("dpkg-deb not found")
    cache = pathlib.Path(a.cache) if a.cache else out.with_name(out.name + ".debs")
    cache.mkdir(parents=True, exist_ok=True)

    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(src, out, symlinks=True)
    lib, inc = out / "lib", out / "include"
    ma = MULTIARCH[a.arch]

    with tempfile.TemporaryDirectory() as tmp:
        x = pathlib.Path(tmp)
        for rel in PKGS[a.arch]:
            subprocess.run(["dpkg-deb", "-x", str(fetch(a.mirror, rel, cache)), str(x)], check=True)
        # Headers: usr/include/{zlib.h,zconf.h,zstd*.h,...} and any multiarch ones.
        for d in (x / "usr/include", x / "usr/include" / ma):
            if d.is_dir():
                for p in d.iterdir():
                    if p.is_file():
                        shutil.copy2(p, inc / p.name)
        # Libraries: the debs split them between /lib/<ma> and /usr/lib/<ma>.
        # Copy every file and symlink, then repoint absolute symlinks (the
        # -dev package's libz.so -> /lib/<ma>/libz.so.1.x) at the copy.
        for d in (x / "lib" / ma, x / "usr/lib" / ma):
            if not d.is_dir():
                continue
            for p in d.iterdir():
                if p.is_dir():
                    continue
                dst = lib / p.name
                if dst.exists() or dst.is_symlink():
                    dst.unlink()
                if p.is_symlink():
                    os.symlink(os.path.basename(os.readlink(p)), dst)
                else:
                    shutil.copy2(p, dst)

    # libc++.so.1 from the PIC archives. libc++abi and the LLVM unwinder go
    # in whole, so the one shared object carries the C++ runtime entire, as
    # the bundled toolchain's does; the sysroot has no libgcc_s, so the
    # runtime builtins are its compiler-rt.
    so = lib / "libc++.so.1"
    builtins = out / "compiler-rt" / "lib" / ma / "libclang_rt.builtins.a"
    if not builtins.is_file():
        die(f"no compiler-rt builtins at {builtins}")
    cmd = [a.clang, f"--target={ma}", f"--sysroot={out}", "-shared", "-fuse-ld=lld",
           "-nostdlib", str(lib / "crti.o"), "-o", str(so), "-Wl,-soname,libc++.so.1",
           "-Wl,--whole-archive", str(lib / "libc++.a"), str(lib / "libc++abi.a"), str(lib / "libunwind.a"),
           "-Wl,--no-whole-archive", f"-L{lib}", "-lm", "-lpthread", "-ldl", "-lc", str(builtins),
           str(lib / "crtn.o")]
    print("link", " ".join(cmd), file=sys.stderr)
    subprocess.run(cmd, check=True)
    if not (lib / "libc++.so").exists():
        os.symlink("libc++.so.1", lib / "libc++.so")
    print(out)


if __name__ == "__main__":
    main()
