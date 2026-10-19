#!/usr/bin/env python3
"""Replace a compiled-in path cstring in a Mach-O file with a shorter one.

sane-backends bakes an absolute backend directory and config directory into
libsane.1.dylib, and the config directory into each backend .so. There is no
environment override for the backend directory, so to ship a self-contained
SANE we rewrite those strings in place (the replacement must be no longer than
the original) and ad-hoc re-sign the binaries afterwards.

Usage: patchpath.py <file> <old-path> <new-path>
Exits non-zero if <old-path> is not present, so a build fails loudly.
"""
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
    ob, nb = old.encode(), new.encode()
    if len(nb) > len(ob):
        print(f"  !! new path longer than original in {path} ({len(nb)} > {len(ob)})")
        return 1
    data = bytearray(open(path, "rb").read())
    n = data.count(ob)
    if n == 0:
        print(f"  !! not found in {path}: {old}")
        return 1
    data = data.replace(ob, nb + b"\0" * (len(ob) - len(nb)))
    open(path, "wb").write(data)
    print(f"  {path}: {n}x {old} -> {new}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
