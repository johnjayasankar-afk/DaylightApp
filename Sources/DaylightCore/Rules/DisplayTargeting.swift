import Foundation

/// Resolves what a single display should receive for a decision.
/// Override display keys are an allow-list. Empty means every eligible display.
public enum DisplayTargeting: Sendable {
    public static func desiredOutput(
        for displayID: String,
        excludedFromAutomation: Bool,
        decision: ControllerDecision,
        scheduleOutput: DesiredOutput,
        overrideDisplayKeys: [String]
    ) -> DesiredOutput? {
        if excludedFromAutomation {
            return nil
        }
        if decision.restoreToBaseline {
            if !overrideDisplayKeys.isEmpty, !overrideDisplayKeys.contains(displayID) {
                return scheduleOutput
            }
            return nil
        }
        if decision.winningPriority == .temporaryOverride,
           !overrideDisplayKeys.isEmpty,
           !overrideDisplayKeys.contains(displayID) {
            return scheduleOutput
        }
        return decision.output
    }

    /// Pause, Off, and unscoped Color Work restore every eligible display.
    /// A scoped Color Work hold restores only the listed keys.
    public static func restoresEveryDisplay(overrideDisplayKeys: [String]) -> Bool {
        overrideDisplayKeys.isEmpty
    }

    public static func adjacentIndex(from index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    /// Keys that left the live set and were not remapped (EDID → UUID).
    public static func removedDisplayKeys(previous: [String], next: [String], remapped: Set<String> = []) -> [String] {
        let live = Set(next).union(remapped)
        return previous.filter { !live.contains($0) }
    }

    public static func linkableDisplayKeys(_ displays: [ConnectedDisplay]) -> [String] {
        displays
            .filter { $0.connection == .connected && $0.mirrorsDisplayKey == nil }
            .map(\.id)
    }

    public static func targetCaption(
        connection: DisplayConnectionState,
        excluded: Bool,
        mirrored: Bool,
        output: DesiredOutput?,
        holdingThisDisplay: Bool?,
        scheduleFallback: Bool,
        restored: Bool = false,
        restoredTitle: String? = nil
    ) -> String {
        if excluded {
            return "Excluded — Daylight is not writing to this display"
        }
        if mirrored {
            return "Mirrored — follows the primary display"
        }
        switch connection {
        case .inactive:
            return "Idle — Daylight is not writing while this display is idle"
        case .disconnected:
            return "Disconnected"
        case .connected:
            break
        }
        if restored {
            return restoredTitle ?? "Restored — Daylight is not writing to this display"
        }
        guard let output else { return "No target" }
        let kelvin = output.temperature.roundedLabel
        if holdingThisDisplay == true {
            return "Holding \(kelvin)"
        }
        if scheduleFallback {
            return "Schedule \(kelvin)"
        }
        return "Target \(kelvin)"
    }
}

public enum DisplayAdjustment: String, Sendable, Equatable {
    case ready
    case appDisabled
    case previewing
    case excluded
    case idle
    case disconnected
    case mirrored
    case paused

    public var allowsWrites: Bool { self == .ready }

    public var message: String? {
        switch self {
        case .ready:
            return nil
        case .appDisabled:
            return "Daylight is off."
        case .previewing:
            return "Stop the preview to change lighting."
        case .paused:
            return "Resume automation to change lighting."
        case .excluded:
            return "This display is excluded from automation."
        case .idle:
            return "This display is connected but idle, so Daylight is not writing to it."
        case .disconnected:
            return "This display is not available."
        case .mirrored:
            return "This display is mirrored and follows the primary."
        }
    }

    public static func resolve(
        display: ConnectedDisplay?,
        excluded: Bool,
        disabled: Bool,
        previewing: Bool,
        paused: Bool = false
    ) -> DisplayAdjustment {
        if disabled { return .appDisabled }
        if previewing { return .previewing }
        if paused { return .paused }
        guard let display else { return .disconnected }
        if excluded { return .excluded }
        if display.mirrorsDisplayKey != nil { return .mirrored }
        switch display.connection {
        case .connected: return .ready
        case .inactive: return .idle
        case .disconnected: return .disconnected
        }
    }
}

public enum TimelineSnap: Sendable {
    public static func temperatureFraction(kelvin: Double, range: ClosedRange<Double>) -> Double {
        let span = max(range.upperBound - range.lowerBound, 1)
        return min(max((kelvin - range.lowerBound) / span, 0), 1)
    }

    public static func minutes(_ raw: Int, fine: Bool) -> Int {
        let clamped = min(max(raw, 0), 1439)
        if fine { return clamped }
        let snapped = Int((Double(clamped) / 15.0).rounded()) * 15
        if snapped >= 1440 { return 0 }
        return snapped
    }
}
