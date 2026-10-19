#!/usr/bin/env python3
"""Check shortcuts, memo history and storage migration without registering hotkeys."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    "zen/model/RecordingShortcut.swift", "zen/model/ZenStorage.swift", "zen/model/Memo.swift",
    "zen/model/TranscriptionModel.swift", "zen/Components/ZenState.swift",
    "Tests/StateChecks.swift",
]
with tempfile.TemporaryDirectory(prefix="zen-state-checks-") as scratch:
    binary = Path(scratch) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-O", "-parse-as-library", "-swift-version", "5",
        "-target", f"{platform.machine()}-apple-macos26.5",
        "-module-cache-path", str(root / "build/StateChecksModuleCache"),
        "-framework", "AppKit", "-framework", "Carbon",
        *(str(root / source) for source in sources), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
