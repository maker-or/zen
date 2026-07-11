import AppKit
import SwiftUI
import Combine

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PillPanelManager {
    static let shared = PillPanelManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<PillContentView>?

    private let recorder = AudioRecorder.shared
    private let transcriber = TranscriptionService.shared
    private let state = ZenState.shared

    private init() {}

    func createPanel() {
        let content = PillContentView()
        let controller = NSHostingController(rootView: content)
        controller.view.autoresizingMask = [.width, .height]

        let panel = PillPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0

        panel.contentView = controller.view
        panel.setContentSize(NSSize(width: 480, height: 60))

        centerPanel(panel)
        panel.orderOut(nil)

        self.panel = panel
        self.hostingController = controller
    }

    func handleHotkey() {
        print("[PillPanel] Hotkey pressed, current state: \(state.transcriptionState)")
        switch state.transcriptionState {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            print("[PillPanel] Already transcribing, ignoring")
        }
    }

    private func startRecording() {
        guard let panel else { return }

        recorder.startRecording()

        if recorder.isRecording {
            print("[PillPanel] Recording started")
            state.transcriptionState = .recording
            centerPanel(panel)
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1.0
            }
        }
    }

    private func stopAndTranscribe() {
        recorder.stopRecording()

        guard let rawURL = recorder.recordedFileURL else {
            print("[PillPanel] No recording file found")
            state.transcriptionState = .error("No recording")
            scheduleHide()
            return
        }

        guard let fileURL = recorder.convertTo16kHzInt16(sourceURL: rawURL) else {
            print("[PillPanel] Audio conversion failed")
            state.transcriptionState = .error("Audio conversion failed")
            scheduleHide()
            return
        }

        try? FileManager.default.removeItem(at: rawURL)

        print("[PillPanel] Transcribing \(fileURL.lastPathComponent)")
        state.transcriptionState = .transcribing

        Task {
            await transcriber.transcribe(fileURL: fileURL)

            if !transcriber.transcript.isEmpty {
                state.transcriptionState = .done(transcriber.transcript)
                state.appendHistory(transcriber.transcript)
            } else if let errorMsg = transcriber.error {
                state.transcriptionState = .error(errorMsg)
            } else {
                state.transcriptionState = .error("Empty transcription")
            }

            scheduleHide()
        }
    }

    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hide()
            self?.state.transcriptionState = .idle
        }
    }

    private func centerPanel(_ panel: NSPanel) {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = (screenFrame.width - panel.frame.width) / 2
            let y = screenFrame.origin.y + screenFrame.height - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func show() {
        guard let panel, !panel.isVisible else { return }
        centerPanel(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}
