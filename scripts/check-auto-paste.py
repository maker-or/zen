#!/usr/bin/env python3
"""Check dictation delivery without controlling another app or requesting access."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="zen-auto-paste-checks-") as scratch:
    binary = Path(scratch) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-O", "-parse-as-library", "-swift-version", "5",
        "-target", f"{platform.machine()}-apple-macos26.5",
        "-module-cache-path", str(root / "build/AutoPasteChecksModuleCache"),
        "-framework", "AppKit", "-framework", "ApplicationServices",
        str(root / "zen/Components/AutoPasteService.swift"),
        str(root / "Tests/AutoPasteChecks.swift"), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
