#!/usr/bin/env python3
"""Check shortcut capture with real key events: saving, rejection, focus loss, Escape."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    "zen/model/RecordingShortcut.swift", "zen/model/ZenStorage.swift", "zen/model/Memo.swift",
    "zen/model/TranscriptionModel.swift", "zen/model/Log.swift", "zen/Components/ZenState.swift",
    "zen/Components/HotkeyManager.swift", "zen/Components/ShortcutCapture.swift",
    "Tests/ShortcutCaptureChecks.swift",
]
with tempfile.TemporaryDirectory(prefix="zen-capture-checks-") as scratch:
    binary = Path(scratch) / "checks"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
        "-target", f"{platform.machine()}-apple-macos26.5",
        "-module-cache-path", str(root / "build/CaptureChecksModuleCache"),
        "-framework", "AppKit", "-framework", "Carbon",
        *(str(root / source) for source in sources), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
