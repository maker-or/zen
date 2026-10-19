#!/usr/bin/env python3
"""Run model preference/segment checks, optionally transcribing a reference clip.

First build Release with derived data in ./build. Pass a recording containing
"yellow lamps" (the official Phonon-2 reference clip) to also smoke-test both
engines. This downloads any missing models to the normal app cache.
"""
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
products = root / "build/Build/Products/Release"
if not (products / "PhononCoreML.o").is_file():
    sys.exit("Build Release first: xcodebuild -project zen.xcodeproj -scheme zen -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO")
sources = [
    "zen/model/TranscriptionModel.swift", "zen/model/Transcript.swift",
    "zen/model/RecordingShortcut.swift", "zen/model/ZenStorage.swift", "zen/model/Memo.swift",
    "zen/model/Log.swift",
    "zen/Components/ZenState.swift", "zen/Components/PhononEngine.swift",
    "zen/Components/AudioRecorder.swift",
    "zen/Components/TranscriptionService.swift", "Tests/TranscriptionChecks.swift",
]
with tempfile.TemporaryDirectory(prefix="zen-transcription-checks-") as scratch:
    binary = Path(scratch) / "checks"
    command = [
        "xcrun", "swiftc", "-O", "-parse-as-library", "-swift-version", "5",
        "-target", f"{platform.machine()}-apple-macos26.5",
        "-module-cache-path", str(root / "build/TranscriptionChecksModuleCache"),
        "-I", str(products), "-I", str(root / "build/SourcePackages/checkouts/phonon-coreml/Binaries/PhononTDT.xcframework/macos-arm64_x86_64/Headers"),
        "-L", str(products), "-lPhononTDT", "-lc++",
    ]
    for framework in ["Accelerate", "CoreML", "AVFoundation", "AppKit", "Carbon"]:
        command.extend(["-framework", framework])
    command.extend(str(root / source) for source in sources)
    command.extend(str(obj) for obj in products.glob("*.o"))
    command.extend(["-o", str(binary)])
    subprocess.run(command, check=True)
    result = subprocess.run([str(binary), *sys.argv[1:]])
    sys.exit(result.returncode)
