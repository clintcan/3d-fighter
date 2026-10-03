"""Packages the exported Linux build for distribution.

Run after:  godot_console --headless --path . --export-release "Linux" build/linux/3DFighter.x86_64
Then:       python tools/package_linux.py

Writes dist/3DFighter-v<version>-linux.tar.gz containing 3DFighter/3DFighter.x86_64
(mode 755, so it stays executable; a zip made on Windows would lose that) and
3DFighter/README.txt (dist/README-Linux.txt). The version comes from project.godot.
"""
import os
import re
import sys
import tarfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BINARY = os.path.join(ROOT, "build", "linux", "3DFighter.x86_64")
README = os.path.join(ROOT, "dist", "README-Linux.txt")


def main() -> int:
    if not os.path.exists(BINARY):
        print("Missing", BINARY, "- export the Linux preset first.")
        return 1
    project = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    version = re.search(r'config/version="([^"]+)"', project).group(1)
    out = os.path.join(ROOT, "dist", f"3DFighter-v{version}-linux.tar.gz")

    def executable(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.mode = 0o755
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info

    def regular(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.mode = 0o644
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info

    with tarfile.open(out, "w:gz", compresslevel=9) as tar:
        tar.add(BINARY, arcname="3DFighter/3DFighter.x86_64", filter=executable)
        tar.add(README, arcname="3DFighter/README.txt", filter=regular)
    print(f"wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out) // (1024 * 1024)} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
