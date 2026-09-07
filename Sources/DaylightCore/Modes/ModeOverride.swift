import Foundation

public enum LightingMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case automatic
    case focus
    case reading
    case windDown
    case colorWork
    case presentation
    case gaming
    case nightDesk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .focus: return "Focus"
        case .reading: return "Reading"
        case .windDown: return "Wind Down"
        case .colorWork: return "Color Work"
        case .presentation: return "Presentation"
        case .gaming: return "Gaming"
        case .nightDesk: return "Night Desk"
        }
    }

    public var summary: String {
        switch self {
        case .automatic:
            return "Follow the active schedule."
        case .focus:
            return "Hold a stable lighting profile."
        case .reading:
            return "Use your reading warmth and brightness."
        case .windDown:
            return "Move toward your evening preferences."
        case .colorWork:
            return "Remove Daylight’s own transformations. This does not calibrate the display."
        case .presentation:
            return "Use a chosen profile and keep the interface quiet."
        case .gaming:
            return "Use a compatible, less aggressive configuration."
        case .nightDesk:
            return "Use restrained settings across enabled displays."
        }
    }

    public var pausesAutomation: Bool {
        self != .automatic
    }

    public var symbolName: String {
        switch self {
        case .automatic: return "circle.lefthalf.filled"
        case .focus: return "dot.viewfinder"
        case .reading: return "book"
        case .windDown: return "moon.stars"
        case .colorWork: return "eyedropper"
        case .presentation: return "rectangle.on.rectangle"
        case .gaming: return "gamecontroller"
        case .nightDesk: return "lamp.desk"
        }
    }

    public static let compactCases: [LightingMode] = [
        .automatic, .reading, .focus, .windDown, .colorWork
    ]
}

public enum OverrideDuration: Hashable, Sendable, Codable {
    case minutes(Int)
    case untilNextAnchor
    case untilTime(Date)
    case untilResumed

    public var title: String {
        switch self {
        case .minutes(15): return "15 minutes"
        case .minutes(30): return "30 minutes"
        case .minutes(60): return "1 hour"
        case .minutes(let value): return "\(value) minutes"
        case .untilNextAnchor: return "Until the next schedule change"
        case .untilTime: return "Until a chosen time"
        case .untilResumed: return "Until I resume automation"
        }
    }

    public var shortTitle: String {
        switch self {
        case .minutes(15): return "15m"
        case .minutes(30): return "30m"
        case .minutes(60): return "1h"
        case .minutes(let value): return "\(value)m"
        case .untilNextAnchor: return "Next"
        case .untilTime: return "Time"
        case .untilResumed: return "Hold"
        }
    }

    public static let menuCases: [OverrideDuration] = [
        .minutes(15), .minutes(30), .minutes(60), .untilNextAnchor, .untilResumed
    ]

    public func expiration(
        from start: Date,
        nextAnchor: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .minutes(let value):
            return start.addingTimeInterval(TimeInterval(value * 60))
        case .untilNextAnchor:
            return nextAnchor
        case .untilTime(let date):
            return date
        case .untilResumed:
            return nil
        }
    }
}

public struct TemporaryOverride: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var mode: LightingMode
    public var output: DesiredOutput?
    public var duration: OverrideDuration
    public var startedAt: Date
    public var expiresAt: Date?
    public var reason: String
    public var silencesReminders: Bool
    public var appliesToDisplayKeys: [String]

    public init(
        id: String = UUID().uuidString,
        mode: LightingMode,
        output: DesiredOutput? = nil,
        duration: OverrideDuration,
        startedAt: Date,
        expiresAt: Date?,
        reason: String,
        silencesReminders: Bool = false,
        appliesToDisplayKeys: [String] = []
    ) {
        self.id = id
        self.mode = mode
        self.output = output
        self.duration = duration
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.reason = reason
        self.silencesReminders = silencesReminders
        self.appliesToDisplayKeys = appliesToDisplayKeys
    }

    public var isManualAdjustment: Bool {
        reason == "Manual adjustment"
    }

    public var displayName: String {
        isManualAdjustment ? "Manual" : mode.title
    }

    public func isActive(at date: Date) -> Bool {
        if let expiresAt {
            return date < expiresAt
        }
        return true
    }

    public func remaining(at date: Date) -> TimeInterval? {
        guard let expiresAt else { return nil }
        return expiresAt.timeIntervalSince(date)
    }

    /// “Until the next schedule change” follows live nextChange, not the expiry captured at start.
    /// A past nextChange expires the hold. No upcoming change becomes a hold until resume.
    public func refreshed(nextChange: Date?, at date: Date = Date()) -> TemporaryOverride {
        guard duration == .untilNextAnchor else { return self }
        var next = self
        if let nextChange {
            next.expiresAt = nextChange
        } else {
            next.duration = .untilResumed
            next.expiresAt = nil
        }
        return next
    }
}

public struct LightingProfile: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var mode: LightingMode
    public var output: DesiredOutput

    public init(id: String = UUID().uuidString, name: String, mode: LightingMode, output: DesiredOutput) {
        self.id = id
        self.name = name
        self.mode = mode
        self.output = output
    }

    public static func defaults(from preset: ComfortPreset) -> [LightingProfile] {
        [
            LightingProfile(name: "Focus", mode: .focus, output: preset.day),
            LightingProfile(name: "Reading", mode: .reading, output: DesiredOutput(temperature: ColorTemperature(kelvin: 4800))),
            LightingProfile(name: "Wind Down", mode: .windDown, output: preset.evening),
            LightingProfile(name: "Presentation", mode: .presentation, output: DesiredOutput(temperature: .daylightReference)),
            LightingProfile(name: "Gaming", mode: .gaming, output: DesiredOutput(temperature: ColorTemperature(kelvin: 6200))),
            LightingProfile(name: "Night Desk", mode: .nightDesk, output: preset.night)
        ]
    }
}

public struct PauseState: Hashable, Sendable, Codable {
    public var isPaused: Bool
    public var expiresAt: Date?
    public var reason: String

    public static let inactive = PauseState(isPaused: false, expiresAt: nil, reason: "")

    public init(isPaused: Bool, expiresAt: Date?, reason: String) {
        self.isPaused = isPaused
        self.expiresAt = expiresAt
        self.reason = reason
    }

    public func isActive(at date: Date) -> Bool {
        guard isPaused else { return false }
        if let expiresAt {
            return date < expiresAt
        }
        return true
    }
}

public enum AutomationState: String, Sendable, Codable {
    case automatic
    case paused
    case override
    case colorWork
    case disabled
    case preview
}
