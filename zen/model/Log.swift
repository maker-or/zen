import os

/// Unified-log channels. Read them with:
///   log show --last 15m --predicate 'subsystem == "pipper.dev.zen"' --info
nonisolated enum Log {
    static let hotkey = Logger(subsystem: "pipper.dev.zen", category: "hotkey")
    static let recording = Logger(subsystem: "pipper.dev.zen", category: "recording")
    static let models = Logger(subsystem: "pipper.dev.zen", category: "models")
}
