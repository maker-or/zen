import os
import AppKit
import SwiftUI
import Combine
import AVFoundation

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Whether the pointer is over the pill itself, rather than the clear rest
/// of its window.
@MainActor
final class PillHover: ObservableObject {
    @Published var isHovering = false
}

/// The small recording widget, and recording driven by the shortcut (see
/// `ShortcutGesture`) or by clicking the widget.
@MainActor
final class PillPanelManager {
    static let shared = PillPanelManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<PillContentView>?
    private var gesture = ShortcutGesture()
    private var secondTapWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []
    private var mouseMonitors: [Any] = []
    /// The pill's frame in the window, top-left origin, as SwiftUI lays it out.
    private var pillFrame: CGRect = .zero
    let hover = PillHover()

    /// Room for every state, so the pill animates freely inside one window
    /// that never resizes. Only the pill itself takes clicks (see `updateHover`).
    private static let panelSize = NSSize(width: 380, height: 56)
    /// From the Dock or menu bar to the window; the pill sits 6 pt further in.
    private static let screenMargin: CGFloat = 12

    private let recorder = AudioRecorder.shared
    private let transcriber = TranscriptionService.shared
    private let state = ZenState.shared

    private init() {}

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func createPanel() {
        if panel != nil { return }

        let hostingView = NSHostingView(rootView: PillContentView(hover: hover))
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]

        let panel = PillPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        // Clicks pass through until the pointer is over the pill.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true

        panel.contentView = hostingView
        position(panel)
        panel.orderOut(nil)

        self.panel = panel
        self.hostingView = hostingView

        // Follow Settings and the widget's own menu as they change.
        state.$showsIdleWidget.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settle() }
            .store(in: &observers)
        state.$widgetPosition.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel else { return }
                self.position(panel)
            }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self, let panel = self.panel else { return }
                self.position(panel)
            }
            .store(in: &observers)

        // Mouse movement needs no permission to watch, unlike key presses.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }) { mouseMonitors.append(local) }

        settle()
    }

    // MARK: Shortcut

    func shortcutPressed() {
        Analytics.recordActive()
        hideWorkItem?.cancel()
        hideWorkItem = nil
        let status: ShortcutGesture.Status
        switch state.transcriptionState {
        case .idle, .done, .error: status = .idle
        case .recording: status = .recording
        case .transcribing: status = .busy
        }
        Log.recording.notice("Shortcut down in state \(String(describing: self.state.transcriptionState), privacy: .public)")
        perform(gesture.press(at: now, status: status))
    }

    func shortcutReleased() {
        perform(gesture.release(at: now, isRecording: state.transcriptionState == .recording,
                                singleKey: state.recordingShortcut.isModifierOnly))
    }

    /// A single-key shortcut was used with another key, like Right Control + C.
    func shortcutInterrupted() {
        perform(gesture.interrupt())
    }

    /// Clicking the widget starts a hands-free recording, or finishes one.
    func widgetClicked() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        switch state.transcriptionState {
        case .idle, .done, .error:
            gesture.startedHandsFree()
            perform(.start)
        case .recording:
            gesture.reset()
            perform(.stop)
        case .transcribing:
            break
        }
    }

    private func perform(_ action: ShortcutGesture.Action) {
        switch action {
        case .none:
            break
        case .start:
            AutoPasteService.shared.captureDestination(enabled: state.autoPasteEnabled)
            bringPanelToFront()
            startRecording()
        case .stop:
            stopAndTranscribe()
        case .cancel:
            Log.recording.notice("Dropping the recording")
            cancelRecording()
        case .waitForSecondTap:
            secondTapWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.perform(self.gesture.secondTapTimedOut())
            }
            secondTapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + ShortcutGesture.doubleTapWindow, execute: workItem)
        }
    }

    // MARK: Recording

    private func startRecording() {
        if panel == nil { createPanel() }

        let micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if micPermission == .denied || micPermission == .restricted {
            fail("Mic access denied in System Settings", hideAfter: 6)
            return
        }

        if micPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.fail("Mic access denied in System Settings", hideAfter: 6)
                    }
                }
            }
            return
        }

        guard recorder.startRecording() else {
            fail("Couldn’t open the microphone", hideAfter: 5)
            return
        }
        state.transcriptionState = .recording
        show()
    }

    private func fail(_ message: String, hideAfter delay: Double) {
        gesture.reset()
        AutoPasteService.shared.discardDestination()
        state.transcriptionState = .error(message)
        show()
        scheduleHide(delay: delay)
    }

    /// Drops the current recording without transcribing or pasting it.
    private func cancelRecording() {
        gesture.reset()
        secondTapWorkItem?.cancel()
        secondTapWorkItem = nil
        AutoPasteService.shared.discardDestination()
        state.transcriptionState = .idle
        settle()
        Task {
            await recorder.stopRecording(tail: 0)
            if let url = recorder.recordedFileURL { try? FileManager.default.removeItem(at: url) }
            recorder.recordedFileURL = nil
        }
    }

    private func stopAndTranscribe() {
        secondTapWorkItem?.cancel()
        secondTapWorkItem = nil
        // Leaves .recording right away so a second hotkey press is ignored during the tail.
        state.transcriptionState = .transcribing
        Task {
            await recorder.stopRecording()
            finishTranscription()
        }
    }

    private func finishTranscription() {
        guard let rawURL = recorder.recordedFileURL else {
            AutoPasteService.shared.discardDestination()
            Log.recording.error("No recording file found")
            state.transcriptionState = .error("No recording")
            scheduleHide(delay: 4.0)
            return
        }

        guard let fileURL = recorder.convertTo16kHzInt16(sourceURL: rawURL) else {
            AutoPasteService.shared.discardDestination()
            Log.recording.error("Audio conversion failed")
            state.transcriptionState = .error("Audio conversion failed")
            scheduleHide(delay: 4.0)
            return
        }

        try? FileManager.default.removeItem(at: rawURL)

        state.transcriptionState = .transcribing
        let model = state.transcriptionModel
        Log.recording.notice("Transcribing with \(model.name, privacy: .public)")

        Task {
            let started = Date()
            await transcriber.transcribe(fileURL: fileURL)
            Log.recording.notice("Transcription finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s: \(self.transcriber.transcript.count) characters, error: \(self.transcriber.error ?? "none", privacy: .public)")

            if !transcriber.transcript.isEmpty {
                await AutoPasteService.shared.pasteIfPossible(transcriber.transcript, enabled: state.autoPasteEnabled)
                state.transcriptionState = .done(transcriber.transcript)
                state.appendHistory(transcriber.transcript)
                scheduleHide(delay: 2.0)
            } else if let errorMsg = transcriber.error {
                AutoPasteService.shared.discardDestination()
                state.transcriptionState = .error(errorMsg)
                scheduleHide(delay: 5.0)
            } else {
                AutoPasteService.shared.discardDestination()
                state.transcriptionState = .error("No speech detected")
                scheduleHide(delay: 4.0)
            }
        }
    }

    // MARK: Showing and hiding

    /// After a result, return to idle: the small widget stays if it's set to.
    private func scheduleHide(delay: Double = 2.0) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.state.transcriptionState = .idle
            self?.settle()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Shows or hides the widget for the current state and settings.
    private func settle() {
        if state.transcriptionState != .idle || state.showsIdleWidget {
            show()
        } else {
            hide()
        }
    }

    /// SwiftUI laid the pill out at a new size or place in the window.
    func pillFrameChanged(_ frame: CGRect) {
        pillFrame = frame
        updateHover()
    }

    /// Lets the window take clicks only while the pointer is over the pill,
    /// and tells the pill whether it's hovered.
    private func updateHover() {
        guard let panel else { return }
        var inside = false
        if panel.isVisible, panel.alphaValue > 0, !pillFrame.isEmpty {
            let window = panel.frame
            let pill = CGRect(x: window.minX + pillFrame.minX, y: window.maxY - pillFrame.maxY,
                              width: pillFrame.width, height: pillFrame.height)
            inside = pill.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if hover.isHovering != inside { hover.isHovering = inside }
    }

    private func position(_ panel: NSPanel) {
        let frame = frame()
        if frame != panel.frame { panel.setFrame(frame, display: false) }
        updateHover()
    }

    /// Centered at the top or bottom of the screen, clear of the menu bar and Dock.
    private func frame() -> CGRect {
        let size = Self.panelSize
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return CGRect(origin: .zero, size: size) }
        let visible = screen.visibleFrame
        let y = state.widgetPosition == .top
            ? visible.maxY - size.height - Self.screenMargin + 8 // The menu bar is closer than the Dock looks.
            : visible.minY + Self.screenMargin
        return CGRect(x: (visible.midX - size.width / 2).rounded(), y: y, width: size.width, height: size.height)
    }

    func show() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        position(panel)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    private func bringPanelToFront() {
        if panel == nil { createPanel() }
        guard let panel else { return }
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Unless it was shown again while fading out.
            if panel.alphaValue == 0 { panel.orderOut(nil) }
            MainActor.assumeIsolated { self.updateHover() }
        }
    }
}
