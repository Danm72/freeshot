import Foundation

/// Auto-close countdown for one Quick Access card. Time is injected so it is testable.
/// Hover pauses the countdown; leaving the card starts a fresh full countdown.
public struct QuickAccessAutoClose: Equatable, Sendable {
    public let duration: TimeInterval
    public private(set) var deadline: Date?
    public private(set) var isPaused: Bool = false

    /// `duration` <= 0 means never auto-close.
    public init(duration: TimeInterval, now: Date) {
        self.duration = duration
        self.deadline = duration > 0 ? now.addingTimeInterval(duration) : nil
    }

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume(now: Date) {
        isPaused = false
        deadline = duration > 0 ? now.addingTimeInterval(duration) : nil
    }

    public func isExpired(now: Date) -> Bool {
        guard !isPaused, let deadline else { return false }
        return now >= deadline
    }

    /// Seconds left, or nil when paused or disabled.
    public func remaining(now: Date) -> TimeInterval? {
        guard !isPaused, let deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }
}
