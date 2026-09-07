import Foundation

public struct TransitionPlan: Sendable, Equatable {
    public var current: DesiredOutput
    public var target: DesiredOutput
    public var shouldWrite: Bool
    public var nextTick: Date?
    public var remaining: TimeInterval
}

public struct TransitionEngine: Sendable {
    public var minimumWriteInterval: TimeInterval
    public var temperatureThreshold: Double

    public init(minimumWriteInterval: TimeInterval = 0.75, temperatureThreshold: Double = 18) {
        self.minimumWriteInterval = minimumWriteInterval
        self.temperatureThreshold = temperatureThreshold
    }

    public func plan(
        applied: DesiredOutput?,
        target: DesiredOutput,
        lastWrite: Date?,
        now: Date,
        transitionRemaining: TimeInterval,
        force: Bool = false
    ) -> TransitionPlan {
        let origin = applied ?? target
        let changed = Interpolation.isMaterialChange(
            from: origin,
            to: target,
            temperatureThreshold: temperatureThreshold
        )
        let due: Bool
        if force || lastWrite == nil {
            due = true
        } else if let lastWrite {
            due = now.timeIntervalSince(lastWrite) >= minimumWriteInterval
        } else {
            due = true
        }

        let shouldWrite = (changed && due) || (force && changed) || (applied == nil && due)
        var nextTick: Date?
        if changed {
            nextTick = now.addingTimeInterval(minimumWriteInterval)
        }
        if transitionRemaining > minimumWriteInterval {
            let candidate = now.addingTimeInterval(minimumWriteInterval)
            nextTick = min(nextTick ?? candidate, candidate)
        }

        return TransitionPlan(
            current: origin,
            target: target,
            shouldWrite: shouldWrite,
            nextTick: nextTick,
            remaining: transitionRemaining
        )
    }

    public func nextIdleWake(from now: Date, candidates: [Date?]) -> Date? {
        candidates.compactMap { $0 }.filter { $0 > now }.min()
    }
}
