import AppKit
import SwiftUI
import Combine
import AVFoundation

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PillPanelManager {
    static let shared = PillPanelManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<PillContentView>?

    private let recorder = AudioRecorder.shared
    private let transcriber = TranscriptionService.shared
    private let state = ZenState.shared
    private var lastHotkeyPress: Date = .distantPast

    private init() {}

    private var hideWorkItem: DispatchWorkItem?

    func createPanel() {
        if panel != nil { return }

        let content = PillContentView()
        let controller = NSHostingController(rootView: content)
        controller.view.autoresizingMask = [.width, .height]

        let panel = PillPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0

        panel.contentView = controller.view
        panel.setContentSize(NSSize(width: 540, height: 60))

        centerPanel(panel)
        panel.orderOut(nil)

        self.panel = panel
        self.hostingController = controller
    }

    func handleHotkey() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let now = Date()
        guard now.timeIntervalSince(lastHotkeyPress) > 0.3 else {
            print("[PillPanel] Ignoring rapid hotkey retrigger")
            return
        }
        lastHotkeyPress = now

        print("[PillPanel] Hotkey pressed, current state: \(state.transcriptionState)")

        bringPanelToFront()

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
        if panel == nil { createPanel() }

        let micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if micPermission == .denied || micPermission == .restricted {
            state.transcriptionState = .error("Mic access denied in System Settings")
            show()
            scheduleHide(delay: 6.0)
            return
        }

        if micPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.state.transcriptionState = .error("Mic access denied in System Settings")
                        self?.show()
                        self?.scheduleHide(delay: 6.0)
                    }
                }
            }
            return
        }

        recorder.startRecording()
        state.transcriptionState = .recording
        show()
    }

    private func stopAndTranscribe() {
        // Leaves .recording right away so a second hotkey press is ignored during the tail.
        state.transcriptionState = .transcribing
        Task {
            await recorder.stopRecording()
            finishTranscription()
        }
    }

    private func finishTranscription() {
        guard let rawURL = recorder.recordedFileURL else {
            print("[PillPanel] No recording file found")
            state.transcriptionState = .error("No recording")
            scheduleHide(delay: 4.0)
            return
        }

        guard let fileURL = recorder.convertTo16kHzInt16(sourceURL: rawURL) else {
            print("[PillPanel] Audio conversion failed")
            state.transcriptionState = .error("Audio conversion failed")
            scheduleHide(delay: 4.0)
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
                scheduleHide(delay: 2.0)
            } else if let errorMsg = transcriber.error {
                state.transcriptionState = .error(errorMsg)
                scheduleHide(delay: 5.0)
            } else {
                state.transcriptionState = .error("No speech detected")
                scheduleHide(delay: 4.0)
            }
        }
    }

    private func scheduleHide(delay: Double = 2.0) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
            self?.state.transcriptionState = .idle
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func centerPanel(_ panel: NSPanel) {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        centerPanel(panel)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    private func bringPanelToFront() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        centerPanel(panel)
        panel.orderFrontRegardless()
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
