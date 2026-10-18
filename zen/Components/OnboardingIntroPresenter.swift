import AppKit
import AVFoundation
import Combine
import QuartzCore
import SwiftUI

/// The transparent host lets the desktop show around the initial bloom. The
/// actual app window stays hidden until the bloom has become its exact frame.
@MainActor
final class OnboardingIntroPresenter: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isMuted = false
    private var panel: IntroPanel?
    private var player: AVAudioPlayer?
    private var completionTask: Task<Void, Never>?
    private var completion: (() -> Void)?
    private var sessionID: UUID?
    private var startTime: CFTimeInterval?
    private(set) var targetFrame: CGRect?

    var elapsed: TimeInterval {
        guard let startTime, CACurrentMediaTime() >= startTime else { return 0 }
        // Follow the audio playhead, including its actual playback start. The
        // monotonic clock keeps silent or unavailable-audio playback working.
        if let player, player.isPlaying { return player.currentTime }
        return max(0, CACurrentMediaTime() - startTime)
    }

    func start(on screen: NSScreen, preferredFrame: CGRect? = nil, onComplete: @escaping () -> Void) {
        cancel()
        let sessionID = UUID()
        self.sessionID = sessionID
        completion = onComplete

        let visible = screen.visibleFrame
        let size = CGSize(width: min(860, visible.width * 0.9), height: min(660, visible.height * 0.9))
        let frame = preferredFrame ?? CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                             width: size.width, height: size.height)
        targetFrame = frame
        let padding = OnboardingIntroTiming.canvasPadding
        let panel = IntroPanel(contentRect: frame.insetBy(dx: -padding, dy: -padding),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // A cold Dock launch can still be transferring activation to Zen.
        // NSPanel otherwise hides itself while its playback clock keeps going.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]
        panel.setAccessibilityLabel("Zen introduction")
        panel.onClose = { [weak self] in self?.skip() }
        self.panel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion,
           let url = Bundle.main.url(forResource: "OnboardingIntro", withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            self.player = player
            player.delegate = self
            player.volume = isMuted ? 0 : 0.4
            player.prepareToPlay()
        }
        let lead = 0.08
        let duration = reduceMotion ? OnboardingIntroTiming.reducedMotionHandoff : OnboardingIntroTiming.handoff
        panel.contentView = NSHostingView(rootView: OnboardingIntroPlaybackView(presenter: self,
                                                                              reduceMotion: reduceMotion))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()

        completionTask = Task { [weak self, weak panel] in
            guard let self, let panel else { return }
            // Being ordered front is not enough during application launch:
            // wait for the Window Server to report that the intro is onscreen.
            while !panel.isVisible || !panel.occlusionState.contains(.visible) {
                guard self.sessionID == sessionID else { return }
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
            guard self.sessionID == sessionID else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()

            // Prepare the first frame before starting either clock. Launch or
            // first-use rendering must not consume the unseen opening beats.
            let startTime = CACurrentMediaTime() + lead
            self.startTime = startTime
            if let player = self.player {
                player.play(atTime: player.deviceCurrentTime + max(0, startTime - CACurrentMediaTime()))
            }

            while self.sessionID == sessionID {
                let remaining = duration - self.elapsed
                if remaining <= 0 {
                    self.finishIntro()
                    return
                }
                do { try await Task.sleep(for: .seconds(min(remaining, 0.1))) }
                catch { return }
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.setVolume(isMuted ? 0 : 0.4, fadeDuration: 0.12)
    }

    func skip() {
        player?.stop()
        finishIntro()
    }

    private func finishIntro() {
        completionTask?.cancel()
        completionTask = nil
        let completion = self.completion
        self.completion = nil
        completion?()
    }

    /// Called after the real onboarding view has mounted underneath the panel.
    func revealOnboarding() {
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OnboardingIntroTiming.handoffFade
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.close()
        }
    }

    func cancel() {
        completionTask?.cancel()
        completionTask = nil
        completion = nil
        sessionID = nil
        startTime = nil
        player?.stop()
        player = nil
        panel?.close()
        panel = nil
        targetFrame = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.player === player else { return }
            self?.player = nil
        }
    }
}

private final class IntroPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performClose(_ sender: Any?) { onClose?() }
}

private struct OnboardingIntroPlaybackView: View {
    @ObservedObject var presenter: OnboardingIntroPresenter
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
            let elapsed = presenter.elapsed
            ZStack {
                OnboardingIntroArtwork(elapsed: elapsed, reduceMotion: reduceMotion)
                VStack {
                    Spacer()
                    HStack {
                        Button(action: presenter.toggleMute) {
                            Image(systemName: presenter.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel(presenter.isMuted ? "Unmute introduction" : "Mute introduction")
                        Spacer()
                        Button("Skip intro", action: presenter.skip)
                            .keyboardShortcut(.cancelAction)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(OnboardingPalette.accent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .opacity(reduceMotion ? 0 : min(1, max(0, (elapsed - 1.9) / 0.3)) * 0.75)
                    .allowsHitTesting(!reduceMotion && elapsed >= 1.9)
                    .accessibilityHidden(reduceMotion || elapsed < 1.9)
                }
                .padding(OnboardingIntroTiming.canvasPadding)
            }
        }
        .onExitCommand(perform: presenter.skip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Opening Zen")
    }
}
