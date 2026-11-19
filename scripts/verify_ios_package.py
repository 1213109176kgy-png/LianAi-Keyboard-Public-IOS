#!/usr/bin/env python3
"""Verify every signed bundle explicitly; a root --deep check can miss extensions."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def verify_app(app: Path) -> None:
    bundles = {app}
    for suffix in ("*.appex", "*.framework", "*.bundle", "*.dylib"):
        bundles.update(app.rglob(suffix))
    for bundle in sorted(bundles, key=lambda p: (-len(p.parts), str(p))):
        # Resource-only bundles may intentionally be unsigned. Their contents
        # are still sealed by their enclosing app or extension.
        if bundle.suffix == ".bundle" and not (bundle / "_CodeSignature").exists():
            continue
        result = subprocess.run(
            ["codesign", "--verify", "--strict", "--verbose=2", str(bundle)],
            capture_output=True, text=True,
        )
        label = str(bundle.relative_to(app.parent))
        if result.returncode:
            raise SystemExit(f"FAIL {label}\n{result.stderr}")
        print(f"OK {label}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Signed .app or exported .ipa")
    package = parser.parse_args().package.resolve()
    if package.suffix == ".app" and package.is_dir():
        verify_app(package)
    elif package.suffix == ".ipa" and package.is_file():
        with tempfile.TemporaryDirectory(prefix="lianai-ipa-verify-") as directory:
            subprocess.run(["ditto", "-x", "-k", str(package), directory], check=True)
            apps = list((Path(directory) / "Payload").glob("*.app"))
            if len(apps) != 1:
                raise SystemExit("Expected exactly one main app in IPA/Payload")
            verify_app(apps[0])
    else:
        parser.error("package must be an existing .app directory or .ipa file")


if __name__ == "__main__":
    main()
