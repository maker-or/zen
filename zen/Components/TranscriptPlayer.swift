import AVFoundation
import AppKit
import Combine
import Observation
import SwiftUI

/// Plays the transcribed file and tracks which segment is being spoken.
///
/// `@Observable` rather than `ObservableObject` so the transcript list, which
/// only reads `activeSegment`, isn't re-rendered on every 0.1 s time tick.
@Observable
final class TranscriptPlayer {
    let player: AVPlayer
    let segments: [TranscriptSegment]
    let hasVideo: Bool

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval
    private(set) var isPlaying = false
    private(set) var activeSegment: Int?
    /// Width over height of the video as displayed (rotation applied).
    private(set) var videoAspect: CGFloat = 16 / 9
    var rate: Float = 1 {
        didSet { if isPlaying { player.rate = rate } }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(url: URL, duration: TimeInterval, hasVideo: Bool, segments: [TranscriptSegment]) {
        self.player = AVPlayer(url: url)
        self.duration = duration
        self.hasVideo = hasVideo
        self.segments = segments

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.update(time: time.seconds) }
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
            .store(in: &cancellables)

        if hasVideo {
            Task { [weak self] in await self?.loadVideoAspect(url: url) }
        }

        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.seek(to: 0, play: false) }
            .store(in: &cancellables)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.playImmediately(atRate: rate)
        }
    }

    func seek(to seconds: TimeInterval, play: Bool = true) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        update(time: clamped)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        if play && !isPlaying {
            player.playImmediately(atRate: rate)
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds, play: isPlaying)
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        cancellables.removeAll()
    }

    private func loadVideoAspect(url: URL) async {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        guard rect.width > 0, rect.height > 0 else { return }
        videoAspect = abs(rect.width) / abs(rect.height)
    }

    private func update(time: TimeInterval) {
        guard time.isFinite else { return }
        currentTime = time
        if duration <= 0, let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }
        let index = segments.lastIndex { $0.start <= time + 0.05 }
        if index != activeSegment {
            activeSegment = index
        }
    }
}

/// Renders the player's video frames.
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = videoGravity
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let layer = nsView.layer as? AVPlayerLayer else { return }
        layer.player = player
        layer.videoGravity = videoGravity
    }
}
