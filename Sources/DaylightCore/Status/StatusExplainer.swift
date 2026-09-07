import Foundation

public struct StatusSnapshot: Hashable, Sendable {
    public var headline: String
    public var explanation: String
    public var nextChange: String
    public var kelvinLabel: String
    public var modeTitle: String
    public var automation: AutomationState
    public var displaySummary: String

    public init(
        headline: String,
        explanation: String,
        nextChange: String,
        kelvinLabel: String,
        modeTitle: String,
        automation: AutomationState,
        displaySummary: String
    ) {
        self.headline = headline
        self.explanation = explanation
        self.nextChange = nextChange
        self.kelvinLabel = kelvinLabel
        self.modeTitle = modeTitle
        self.automation = automation
        self.displaySummary = displaySummary
    }
}

public struct StatusExplainer: Sendable {
    public init() {}

    public func snapshot(
        decision: ControllerDecision,
        displays: [ConnectedDisplay],
        settings: AppSettings,
        at date: Date
    ) -> StatusSnapshot {
        let kelvin = Int(decision.output.temperature.kelvin.rounded())
        let active = displays.filter { $0.connection == .connected }.count
        let idle = displays.filter { $0.connection == .inactive }.count
        var displaySummary: String
        switch (active, idle) {
        case (0, 0):
            displaySummary = "No displays detected."
        case (1, 0):
            displaySummary = "One display."
        case (let count, 0):
            displaySummary = "\(count) displays."
        case (0, _):
            displaySummary = idle == 1
                ? "One connected display is idle."
                : "\(idle) connected displays are idle."
        default:
            displaySummary = "\(active) active, \(idle) idle."
        }

        if decision.winningPriority == .temporaryOverride {
            let keys = settings.override?.appliesToDisplayKeys ?? []
            if !keys.isEmpty {
                let held = displays.filter { keys.contains($0.id) && $0.connection == .connected }
                if held.count == 1, let display = held.first {
                    let name = settings.preferences(for: display.identity).resolvedName(fallback: display.name)
                    displaySummary = "Holding on \(name)."
                } else if held.count > 1 {
                    displaySummary = "Holding on \(held.count) displays."
                }
            }
        }

        let next = Self.nextChangeLine(wake: decision.nextWake, automation: decision.automation, at: date)
        let phrase = decision.output.temperature.comfortPhrase
        if decision.restoreToBaseline {
            let native = "Native output"
            let keys = settings.override?.appliesToDisplayKeys ?? []
            let scoped = decision.winningPriority == .temporaryOverride && !keys.isEmpty
            return StatusSnapshot(
                headline: scoped
                    ? "\(decision.winningName) · native on held displays"
                    : "\(decision.winningName) · \(native.lowercased())",
                explanation: decision.explanation,
                nextChange: next,
                kelvinLabel: native,
                modeTitle: decision.winningName,
                automation: decision.automation,
                displaySummary: displaySummary
            )
        }
        let headline = "\(decision.winningName) · \(kelvin) K"
        return StatusSnapshot(
            headline: headline,
            explanation: decision.explanation,
            nextChange: next,
            kelvinLabel: "\(kelvin) K · \(phrase)",
            modeTitle: decision.winningName,
            automation: decision.automation,
            displaySummary: displaySummary
        )
    }

    public static func nextChangeLine(wake: Date?, automation: AutomationState, at date: Date) -> String {
        if let wake {
            return "Next change \(RulesEngine.relative(wake.timeIntervalSince(date))) (\(ScheduleEngine.shortTime(wake)))."
        }
        if automation == .paused {
            return "Automation stays paused until you resume it."
        }
        if automation == .override || automation == .colorWork {
            return "Held until you resume automation."
        }
        return "No further scheduled change right now."
    }
}

public enum HistoryRecording: Sendable {
    public static func shouldRecord(_ reason: String) -> Bool {
        let skip: Set<String> = [
            "Launch",
            "Displays changed",
            "The computer woke.",
            "The clock or time zone changed.",
            "The screen unlocked.",
            "Environment changed",
            "Accessibility display options changed."
        ]
        return !skip.contains(reason)
    }
}

public enum FeatureStatus: String, Sendable, Codable, CaseIterable {
    case implemented
    case tested
    case experimental
    case blocked
    case planned

    public var title: String {
        rawValue.capitalized
    }
}

public struct FeatureItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var status: FeatureStatus
    public var note: String

    public init(id: String, name: String, status: FeatureStatus, note: String) {
        self.id = id
        self.name = name
        self.status = status
        self.note = note
    }

    public static let releaseOne: [FeatureItem] = [
        FeatureItem(id: "warmth", name: "Display warmth via transfer tables", status: .implemented, note: "Public Core Graphics API. Visual confirmation depends on hardware."),
        FeatureItem(id: "schedule", name: "Daily scheduling engine", status: .tested, note: "Personal, solar, custom, and hybrid with deterministic tests."),
        FeatureItem(id: "modes", name: "Manual and automatic modes", status: .implemented, note: "Includes temporary overrides with expiration."),
        FeatureItem(id: "menubar", name: "Menu bar controls", status: .implemented, note: "Primary compact control surface."),
        FeatureItem(id: "per-display", name: "Per-display settings", status: .implemented, note: "Independent where the backend allows."),
        FeatureItem(id: "restore", name: "Safe preview and restore", status: .implemented, note: "Quit, disable, and emergency restore remove Daylight’s tables."),
        FeatureItem(id: "onboarding", name: "Onboarding", status: .implemented, note: "No extra permissions required."),
        FeatureItem(id: "hw-brightness", name: "Hardware brightness", status: .experimental, note: "Built-in displays via IOKit / DisplayServices. External DDC is planned."),
        FeatureItem(id: "app-rules", name: "Application-specific rules", status: .planned, note: "Release 2."),
        FeatureItem(id: "ambient", name: "Ambient-light adaptation", status: .planned, note: "Release 2, only with a meaningful sensor."),
        FeatureItem(id: "lights", name: "Desk lights and RGB", status: .planned, note: "Release 3. Not shown as working controls."),
        FeatureItem(id: "night-shift-api", name: "Night Shift private API", status: .blocked, note: "Not used. Private and not required for the public transfer-table path.")
    ]
}
