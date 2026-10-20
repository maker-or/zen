import Foundation

/// Turns the recording shortcut going down and up into what recording should
/// do next:
///
/// - Hold it to talk; releasing it transcribes and pastes.
/// - Double-tap it to talk hands-free; the next press finishes.
/// - A key combination like ⌥ Space also starts hands-free on a single tap,
///   as it always has. A single key like Right Control needs the double tap,
///   so a stray tap of it is dropped.
///
/// Recording starts the moment the shortcut goes down, so nothing said while
/// deciding between holding and tapping is lost.
nonisolated struct ShortcutGesture {
    enum Status { case idle, recording, busy }

    enum Action: Equatable {
        case none, start, stop, cancel
        /// Call `secondTapTimedOut()` after `doubleTapWindow`.
        case waitForSecondTap
    }

    /// Held at least this long, a press is hold-to-talk.
    static let holdThreshold: TimeInterval = 0.35
    /// A second tap within this window makes a double tap.
    static let doubleTapWindow: TimeInterval = 0.4

    private enum Phase {
        /// Down and recording; its release decides hold or tap.
        case pressed(at: TimeInterval)
        /// A single key tapped once; waiting to see if a second tap follows.
        case awaitingSecondTap
        /// The second tap of a double tap is down; its release changes nothing.
        case secondTap
        /// Recording hands-free since the given time, until the next press.
        case handsFree(since: TimeInterval)
        /// This press stopped the recording; its release changes nothing.
        case stopping
    }

    private var phase: Phase?

    mutating func press(at time: TimeInterval, status: Status) -> Action {
        // Whatever was in progress has ended, e.g. after an error.
        if status != .recording { phase = nil }

        switch phase {
        case .awaitingSecondTap:
            phase = .secondTap
            return .none
        case .handsFree(let since) where time - since < Self.doubleTapWindow:
            phase = .secondTap
            return .none
        case .handsFree:
            phase = .stopping
            return .stop
        default:
            break
        }

        switch status {
        case .idle:
            phase = .pressed(at: time)
            return .start
        case .recording:
            // Started some other way, like clicking the widget.
            phase = .stopping
            return .stop
        case .busy:
            phase = nil
            return .none
        }
    }

    mutating func release(at time: TimeInterval, isRecording: Bool, singleKey: Bool) -> Action {
        switch phase {
        case .pressed(let pressedAt):
            guard isRecording else {
                phase = nil // The recording never started, e.g. no microphone.
                return .none
            }
            if time - pressedAt >= Self.holdThreshold {
                phase = nil
                return .stop
            }
            if singleKey {
                phase = .awaitingSecondTap
                return .waitForSecondTap
            }
            phase = .handsFree(since: time)
            return .none
        case .secondTap:
            phase = .handsFree(since: -.infinity)
            return .none
        case .stopping:
            phase = nil
            return .none
        default:
            return .none
        }
    }

    mutating func secondTapTimedOut() -> Action {
        guard case .awaitingSecondTap = phase else { return .none }
        phase = nil
        return .cancel
    }

    /// A single-key shortcut became part of another one, like Right Control + C.
    mutating func interrupt() -> Action {
        guard case .pressed = phase else { return .none }
        phase = nil
        return .cancel
    }

    /// A recording started without the shortcut; its next press finishes it.
    mutating func startedHandsFree() { phase = .handsFree(since: -.infinity) }

    mutating func reset() { phase = nil }
}
