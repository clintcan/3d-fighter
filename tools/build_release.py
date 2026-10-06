"""Builds 3D Fighter release packages for itch.io (run from the project root on Windows).

Usage:
    python tools/build_release.py all                  # Windows + macOS + Linux
    python tools/build_release.py windows linux        # any subset
    python tools/build_release.py all --test           # run the sim tests first, stop on failure
    python tools/build_release.py macos --notarize     # sign + notarize + staple the Mac app
    python tools/build_release.py --version 0.3.0      # bump the version everywhere (no build)
    python tools/build_release.py all --version 0.3.0 --test --notarize   # a full release

Outputs (version from project.godot):
    dist/3DFighter-v<ver>-windows.zip    exe + README.txt          (smoke-tested locally)
    dist/3DFighter-v<ver>-macos.zip      signed .app + README.txt  (Developer ID; --notarize adds
                                         Apple notarization; --no-sign leaves it unsigned)
    dist/3DFighter-v<ver>-linux.tar.gz   x86_64 binary + README.txt (smoke-tested in WSL if present)

Godot is found as `godot_console` on PATH, or set GODOT=path\\to\\godot_console.exe.
Signing uses tools/macos_sign_notarize.py and the secrets in %USERPROFILE%\\AppleDeveloper
(never copied into the project).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BUILD = os.path.join(ROOT, "build")
DIST = os.path.join(ROOT, "dist")
PLATFORMS = ["windows", "macos", "linux"]


# --- Helpers ---------------------------------------------------------------------

def step(message: str) -> None:
    print(f"\n=== {message}", flush=True)


def fail(message: str) -> None:
    print(f"\nFAILED: {message}", flush=True)
    sys.exit(1)


def godot() -> str:
    path = os.environ.get("GODOT") or shutil.which("godot_console") or shutil.which("godot")
    if not path:
        fail("Godot not found: put godot_console on PATH or set GODOT.")
    return path


def read_version() -> str:
    text = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    return re.search(r'config/version="([^"]+)"', text).group(1)


def run(args: list, timeout: int, cwd: str = ROOT) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                              encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired as e:
        # Smoke tests run until killed; keep whatever they printed.
        out = e.stdout.decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return subprocess.CompletedProcess(args, -1, out, "")


def export(preset: str, output: str) -> None:
    os.makedirs(os.path.dirname(output), exist_ok=True)
    if os.path.exists(output):
        os.remove(output)
    result = run([godot(), "--headless", "--path", ROOT, "--export-release", preset, output], timeout=900)
    if not os.path.exists(output):
        print(result.stdout[-3000:], result.stderr[-3000:])
        fail(f"export of '{preset}' produced no file")
    print(f"exported {os.path.relpath(output, ROOT)} ({os.path.getsize(output) // (1024 * 1024)} MB)")


def check_smoke(output: str, label: str) -> None:
    lines = [l for l in output.splitlines() if "SMOKE TEST" in l]
    for line in lines:
        print("  " + line)
    if not any("fight ready" in l for l in lines):
        print(output[-2000:])
        fail(f"{label} smoke test didn't reach a fight")
    if "SCRIPT ERROR" in output:
        fail(f"{label} smoke test printed a script error")


_reference_checksum = None


def determinism_checksum(output: str) -> str:
    match = re.search(r"determinism combined ([0-9a-f]{8})", output)
    return match.group(1) if match else ""


def check_determinism(output: str, label: str) -> None:
    """Online play needs every build to simulate identically: the packaged build must print
    the same --determinism checksum as the editor."""
    global _reference_checksum
    if _reference_checksum is None:
        _reference_checksum = determinism_checksum(
            run([godot(), "--headless", "--path", ROOT, "--", "--smoke-test", "--determinism"], timeout=300).stdout)
        if not _reference_checksum:
            fail("the editor's determinism check printed no checksum")
    got = determinism_checksum(output)
    if got != _reference_checksum:
        fail(f"{label} simulates differently from the editor (determinism {got or 'missing'} vs {_reference_checksum}): online play would desync")
    print(f"  {label} determinism checksum {got} matches the editor")


# --- Version bump ------------------------------------------------------------------

def bump_version(new: str) -> None:
    if not re.fullmatch(r"\d+\.\d+\.\d+", new):
        fail(f"version must look like 1.2.3, got {new}")
    old = read_version()
    step(f"Version {old} -> {new}")
    edits = {
        "project.godot": [(r'config/version="[^"]+"', f'config/version="{new}"')],
        "export_presets.cfg": [
            (r'application/file_version="[^"]+"', f'application/file_version="{new}.0"'),
            (r'application/product_version="[^"]+"', f'application/product_version="{new}.0"'),
            (r'application/short_version="[^"]+"', f'application/short_version="{new}"'),
            (r'application/version="[^"]+"', f'application/version="{new}"'),
            (r'3DFighter-v[\d.]+-macos\.zip', f"3DFighter-v{new}-macos.zip"),
        ],
        # The player's manual: its header and the download file names.
        "dist/manual.html": [
            (r"Player's manual · version [\d.]+", f"Player's manual · version {new}"),
            (r"3DFighter-v[\d.]+-(windows\.zip|macos\.zip|linux\.tar\.gz)", f"3DFighter-v{new}-\\1"),
        ],
        # Upload file names in the itch kit (local only, git-ignored; the devlog history keeps its own versions).
        "dist/itch/page.md": [(r"`3DFighter-v[\d.]+-(windows\.zip|macos\.zip|linux\.tar\.gz)`", f"`3DFighter-v{new}-\\1`")],
    }
    for readme in ["dist/README.txt", "dist/README-macOS.txt", "dist/README-Linux.txt"]:
        edits[readme] = [(r"^(3D FIGHTER  -  )v[\d.]+", f"\\1v{new}")]
    for path, rules in edits.items():
        full = os.path.join(ROOT, path)
        if path.startswith("dist/itch/") and not os.path.exists(full):
            print(f"  skipped {path} (no local itch kit)")
            continue
        text = open(full, encoding="utf-8").read()
        for pattern, replacement in rules:
            text, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
            if count == 0:
                fail(f"version pattern not found in {path}: {pattern}")
        # Keep each README's underline the same length as its title.
        if path.startswith("dist/README"):
            lines = text.split("\n")
            lines[1] = "=" * len(lines[0])
            text = "\n".join(lines)
        open(full, "w", encoding="utf-8", newline="\n").write(text)
        print(f"  updated {path}")


# --- Steps -----------------------------------------------------------------------

def run_tests() -> None:
    step("Simulation tests")
    result = run([godot(), "--headless", "--path", ROOT, "-s", "res://tests/sim_test.gd"], timeout=1500)
    passed = sum(1 for l in result.stdout.splitlines() if l.startswith("PASS"))
    failed = [l for l in result.stdout.splitlines() if l.startswith("FAIL")]
    for line in failed:
        print("  " + line)
    if result.returncode != 0 or failed or "0 failure(s)" not in result.stdout:
        fail(f"tests failed ({passed} passed, {len(failed)} failed)")
    print(f"  {passed} checks passed")


def build_windows(version: str) -> str:
    step("Windows")
    exe = os.path.join(BUILD, "windows", "3DFighter.exe")
    export("Windows Desktop", exe)
    check_smoke(run([exe, "--headless", "--", "--smoke-test"], timeout=40).stdout, "Windows")
    check_determinism(run([exe, "--headless", "--", "--smoke-test", "--determinism"], timeout=300).stdout, "Windows")
    out = os.path.join(DIST, f"3DFighter-v{version}-windows.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(exe, "3DFighter/3DFighter.exe")
        z.write(os.path.join(DIST, "README.txt"), "3DFighter/README.txt")
    print(f"wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out) // (1024 * 1024)} MB)")
    return out


def build_macos(version: str, sign: bool, notarize: bool) -> str:
    step("macOS")
    unsigned = os.path.join(BUILD, "macos", f"3DFighter-v{version}-macos.zip")
    export("macOS", unsigned)
    out = os.path.join(DIST, f"3DFighter-v{version}-macos.zip")
    if not sign:
        shutil.copy(unsigned, out)
        print(f"wrote {os.path.relpath(out, ROOT)} (UNSIGNED: Gatekeeper will block it on other Macs)")
        return out
    args = [sys.executable, os.path.join(ROOT, "tools", "macos_sign_notarize.py"), unsigned, out]
    if notarize:
        args.append("--notarize")
        print("signing + notarizing (Apple's notary service usually takes a few minutes)...", flush=True)
    result = run(args, timeout=3600)
    print("\n".join(result.stdout.splitlines()[-4:]))
    if result.returncode != 0 or not os.path.exists(out):
        print(result.stderr[-3000:])
        fail("macOS signing/notarization failed")
    if not notarize:
        print("(signed but not notarized: add --notarize for a release upload)")
    return out


def build_linux(version: str) -> str:
    step("Linux")
    binary = os.path.join(BUILD, "linux", "3DFighter.x86_64")
    export("Linux", binary)
    out = os.path.join(DIST, f"3DFighter-v{version}-linux.tar.gz")

    def owned_by_root(mode: int):
        def apply(info: tarfile.TarInfo) -> tarfile.TarInfo:
            info.mode, info.uid, info.gid, info.uname, info.gname = mode, 0, 0, "", ""
            return info
        return apply

    with tarfile.open(out, "w:gz", compresslevel=9) as tar:
        # A tarball keeps the executable bit; a zip made on Windows would lose it.
        tar.add(binary, arcname="3DFighter/3DFighter.x86_64", filter=owned_by_root(0o755))
        tar.add(os.path.join(DIST, "README-Linux.txt"), arcname="3DFighter/README.txt", filter=owned_by_root(0o644))
    print(f"wrote {os.path.relpath(out, ROOT)} ({os.path.getsize(out) // (1024 * 1024)} MB)")
    smoke_linux(out)
    return out


def smoke_linux(tarball: str) -> None:
    """Extracts the tarball in WSL like a player would and runs the game headless."""
    if not shutil.which("wsl"):
        print("(WSL not found: skipping the Linux smoke test)")
        return
    drive, rest = os.path.splitdrive(os.path.abspath(tarball))
    wsl_path = f"/mnt/{drive[0].lower()}{rest.replace(os.sep, '/')}"
    # Each WSL call extracts afresh: WSL may shut down between calls, and /tmp goes with it.
    prepare = ("set -e; rm -rf /tmp/3dfighter-smoke && mkdir -p /tmp/3dfighter-smoke && cd /tmp/3dfighter-smoke; "
               f"tar -xzf '{wsl_path}'; cd 3DFighter; ")
    script = prepare + "timeout 40 stdbuf -oL -eL ./3DFighter.x86_64 --headless -- --smoke-test 2>&1 || true"
    result = run(["wsl", "--", "bash", "-c", script], timeout=120)
    if "fight ready" not in result.stdout and result.returncode not in (0, -1):
        print("(WSL couldn't run the Linux build here; skipping)")
        print(result.stdout[-800:])
        return
    check_smoke(result.stdout, "Linux (WSL)")
    determinism = run(["wsl", "--", "bash", "-c", prepare + "timeout 300 stdbuf -oL -eL "
                       "./3DFighter.x86_64 --headless -- --smoke-test --determinism 2>&1 || true"], timeout=360)
    check_determinism(determinism.stdout, "Linux (WSL)")


# --- Main ------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("targets", nargs="*", choices=PLATFORMS + ["all"], help="platforms to build")
    parser.add_argument("--version", help="bump the version (x.y.z) in the project, presets, READMEs and itch notes first")
    parser.add_argument("--test", action="store_true", help="run tests/sim_test.gd before building; stop on failure")
    parser.add_argument("--notarize", action="store_true", help="macOS: submit to Apple's notary service and staple")
    parser.add_argument("--no-sign", action="store_true", help="macOS: skip code signing (local testing only)")
    args = parser.parse_args()

    if args.version:
        bump_version(args.version)
    targets = PLATFORMS if "all" in args.targets else [t for t in PLATFORMS if t in args.targets]
    if not targets and not args.test:
        if not args.version:
            parser.print_help()
        return

    start = time.time()
    version = read_version()
    print(f"3D Fighter v{version}: {', '.join(targets) or 'tests only'}")
    if args.test:
        run_tests()
    outputs = []
    for target in targets:
        if target == "windows":
            outputs.append(build_windows(version))
        elif target == "macos":
            outputs.append(build_macos(version, sign=not args.no_sign, notarize=args.notarize))
        elif target == "linux":
            outputs.append(build_linux(version))
    step(f"Done in {int(time.time() - start)} s")
    for out in outputs:
        print(f"  {os.path.relpath(out, ROOT)}")


if __name__ == "__main__":
    main()
