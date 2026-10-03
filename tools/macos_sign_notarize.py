"""Sign (and optionally notarize + staple) the macOS build from Windows with rcodesign.

Godot's built-in rcodesign integration mangles Windows paths (the drive letter in
the entitlements path), so signing happens here instead:

  1. Export the macOS preset from Godot with code signing disabled.
  2. python tools/macos_sign_notarize.py build/macos/3DFighter-v0.1.0-macos.zip dist/3DFighter-v0.1.0-macos.zip [--notarize]

Secrets are never stored in the repo. Everything is read from the signing folder
(default %USERPROFILE%\\AppleDeveloper, override with APPLE_SIGNING_DIR):
  developer_id_application.p12   Developer ID Application certificate + key
  p12_password.txt               password for the .p12 (single line, no newline)
  3DFighter.entitlements         entitlements plist (empty dict is fine for Godot)
  app_store_connect_key.json     App Store Connect API key, created with
                                 `rcodesign encode-app-store-connect-api-key` (for --notarize)
  rcodesign/rcodesign.exe        https://github.com/indygreg/apple-platform-rs
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

SIGNING_DIR = os.environ.get("APPLE_SIGNING_DIR", os.path.expandvars(r"%USERPROFILE%\AppleDeveloper"))
RCODESIGN = os.path.join(SIGNING_DIR, "rcodesign", "rcodesign.exe")
EXTRA_README = os.path.join(os.path.dirname(__file__), "..", "dist", "README-macOS.txt")


def run(args: list[str]) -> None:
    print("> rcodesign", " ".join(a for a in args[1:] if "password" not in a))
    # Run inside the signing folder and pass file names relatively: rcodesign reads a
    # "prefix:path" syntax for some options, so Windows drive letters would break them.
    subprocess.run(args, cwd=SIGNING_DIR, check=True)


def extract(src_zip: str, dest: str) -> str:
    with zipfile.ZipFile(src_zip) as z:
        z.extractall(dest)
    apps = [d for d in os.listdir(dest) if d.endswith(".app")]
    if len(apps) != 1:
        sys.exit(f"expected one .app in {src_zip}, found {apps}")
    return os.path.join(dest, apps[0])


def rezip(app_dir: str, out_zip: str, readme: str | None) -> None:
    """Zip the bundle with Unix permissions so macOS keeps the executable bit."""
    root = os.path.dirname(app_dir)
    os.makedirs(os.path.dirname(os.path.abspath(out_zip)), exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for folder, dirs, files in os.walk(app_dir):
            rel_folder = os.path.relpath(folder, root).replace(os.sep, "/")
            info = zipfile.ZipInfo(rel_folder + "/")
            info.create_system = 3
            info.external_attr = (0o40755 << 16) | 0x10
            z.writestr(info, b"")
            for name in files:
                path = os.path.join(folder, name)
                rel = f"{rel_folder}/{name}"
                executable = "/Contents/MacOS/" in f"/{rel}" or name.endswith(".dylib")
                info = zipfile.ZipInfo.from_file(path, rel)
                info.create_system = 3
                info.external_attr = ((0o100755 if executable else 0o100644) << 16)
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(path, "rb") as f:
                    z.writestr(info, f.read())
        if readme and os.path.exists(readme):
            info = zipfile.ZipInfo("README.txt")
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, open(readme, "rb").read())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input_zip", help="unsigned macOS zip exported by Godot")
    parser.add_argument("output_zip", help="signed zip to write")
    parser.add_argument("--notarize", action="store_true", help="submit to Apple, wait, and staple the ticket")
    parser.add_argument("--readme", default=EXTRA_README, help="README to add at the zip root")
    args = parser.parse_args()

    work = tempfile.mkdtemp(prefix="macos_sign_")
    try:
        app = extract(os.path.abspath(args.input_zip), work)
        run([RCODESIGN, "sign",
             "--p12-file", "developer_id_application.p12",
             "--p12-password-file", "p12_password.txt",
             "--code-signature-flags", "runtime",
             "--entitlements-xml-path", "3DFighter.entitlements",
             "--for-notarization",
             app])
        # `verify` checks Mach-O binaries (not bundles): verify the main executable.
        executable = os.path.join(app, "Contents", "MacOS", os.path.splitext(os.path.basename(app))[0])
        run([RCODESIGN, "verify", executable])
        if args.notarize:
            run([RCODESIGN, "notary-submit",
                 "--api-key-file", "app_store_connect_key.json",
                 "--wait", "--staple",
                 app])
        rezip(app, os.path.abspath(args.output_zip), args.readme)
        print(f"wrote {args.output_zip} ({os.path.getsize(args.output_zip) // 1048576} MB)")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
