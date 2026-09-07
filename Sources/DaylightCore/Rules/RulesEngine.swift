import Foundation

public enum RulePriority: Int, Sendable, Codable, CaseIterable, Comparable {
    case emergencyRestore = 0
    case userPause = 1
    case temporaryOverride = 2
    case applicationRule = 3
    case workspaceProfile = 4
    case baseSchedule = 5

    public static func < (lhs: RulePriority, rhs: RulePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .emergencyRestore: return "Emergency restore or global off"
        case .userPause: return "User pause"
        case .temporaryOverride: return "Temporary override"
        case .applicationRule: return "Application or activity rule"
        case .workspaceProfile: return "Workspace profile"
        case .baseSchedule: return "Base schedule"
        }
    }
}

public enum ControlDomain: String, Sendable, Codable, CaseIterable {
    case temperature
    case hardwareBrightness
    case softwareDimming
    case reminders
}

public struct RuleAction: Hashable, Sendable, Codable {
    public var pauseWarmth: Bool
    public var profileID: String?
    public var output: DesiredOutput?
    public var excludeDisplayKeys: [String]
    public var silenceReminders: Bool

    public init(
        pauseWarmth: Bool = false,
        profileID: String? = nil,
        output: DesiredOutput? = nil,
        excludeDisplayKeys: [String] = [],
        silenceReminders: Bool = false
    ) {
        self.pauseWarmth = pauseWarmth
        self.profileID = profileID
        self.output = output
        self.excludeDisplayKeys = excludeDisplayKeys
        self.silenceReminders = silenceReminders
    }
}

public struct LightingRule: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var priority: RulePriority
    public var action: RuleAction
    public var note: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        enabled: Bool = true,
        priority: RulePriority,
        action: RuleAction,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.action = action
        self.note = note
    }
}

public struct ControllerDecision: Sendable, Equatable {
    public var output: DesiredOutput
    public var winningPriority: RulePriority
    public var winningName: String
    public var explanation: String
    public var automation: AutomationState
    public var restoreToBaseline: Bool
    public var silenceReminders: Bool
    public var excludedDisplayKeys: Set<String>
    public var nextWake: Date?
    public var schedule: ScheduleEvaluation?

    public init(
        output: DesiredOutput,
        winningPriority: RulePriority,
        winningName: String,
        explanation: String,
        automation: AutomationState,
        restoreToBaseline: Bool,
        silenceReminders: Bool,
        excludedDisplayKeys: Set<String>,
        nextWake: Date?,
        schedule: ScheduleEvaluation?
    ) {
        self.output = output
        self.winningPriority = winningPriority
        self.winningName = winningName
        self.explanation = explanation
        self.automation = automation
        self.restoreToBaseline = restoreToBaseline
        self.silenceReminders = silenceReminders
        self.excludedDisplayKeys = excludedDisplayKeys
        self.nextWake = nextWake
        self.schedule = schedule
    }
}

public struct RulesEngine: Sendable {
    public init() {}

    public func decide(
        at date: Date,
        settings: AppSettings,
        schedule: ScheduleEvaluation,
        emergencyRestore: Bool,
        disabled: Bool
    ) -> ControllerDecision {
        if emergencyRestore || disabled {
            return ControllerDecision(
                output: DesiredOutput(temperature: .daylightReference),
                winningPriority: .emergencyRestore,
                winningName: emergencyRestore ? "Emergency restore" : "Daylight is off",
                explanation: emergencyRestore
                    ? "Emergency restore is active. Daylight is removing its own adjustments."
                    : "Daylight is off and is not changing display lighting.",
                automation: .disabled,
                restoreToBaseline: true,
                silenceReminders: true,
                excludedDisplayKeys: [],
                nextWake: nil,
                schedule: schedule
            )
        }

        if settings.pause.isActive(at: date) {
            return ControllerDecision(
                output: schedule.output,
                winningPriority: .userPause,
                winningName: "Paused",
                explanation: pauseExplanation(settings.pause, at: date),
                automation: .paused,
                restoreToBaseline: true,
                silenceReminders: true,
                excludedDisplayKeys: [],
                nextWake: settings.pause.expiresAt,
                schedule: schedule
            )
        }

        if let override = settings.override, override.isActive(at: date) {
            let output = resolvedOverrideOutput(override, schedule: schedule, settings: settings)
            let restore = override.mode == .colorWork
            return ControllerDecision(
                output: output,
                winningPriority: .temporaryOverride,
                winningName: override.displayName,
                explanation: overrideExplanation(override, at: date, schedule: schedule),
                automation: override.mode == .colorWork ? .colorWork : .override,
                restoreToBaseline: restore,
                silenceReminders: override.silencesReminders || override.mode == .presentation,
                excludedDisplayKeys: Set(override.appliesToDisplayKeys),
                nextWake: override.expiresAt,
                schedule: schedule
            )
        }

        let excluded = Set(settings.displays.filter(\.excludedFromAutomation).map(\.id))
        return ControllerDecision(
            output: schedule.output,
            winningPriority: .baseSchedule,
            winningName: schedule.periodName,
            explanation: schedule.explanation,
            automation: .automatic,
            restoreToBaseline: false,
            silenceReminders: false,
            excludedDisplayKeys: excluded,
            nextWake: schedule.nextChangeAt,
            schedule: schedule
        )
    }

    private func resolvedOverrideOutput(
        _ override: TemporaryOverride,
        schedule: ScheduleEvaluation,
        settings: AppSettings
    ) -> DesiredOutput {
        if override.mode == .colorWork {
            return DesiredOutput(temperature: .daylightReference, softwareDimming: .none)
        }
        if let output = override.output {
            return output
        }
        if let profile = settings.profiles.first(where: { $0.mode == override.mode }) {
            return profile.output
        }
        return schedule.output
    }

    private func pauseExplanation(_ pause: PauseState, at date: Date) -> String {
        if let remaining = pause.expiresAt?.timeIntervalSince(date), remaining > 0 {
            return "Automation is paused. Your schedule resumes \(Self.relative(remaining))."
        }
        return "Automation is paused until you resume it."
    }

    private func overrideExplanation(
        _ override: TemporaryOverride,
        at date: Date,
        schedule: ScheduleEvaluation
    ) -> String {
        let until: String
        if let remaining = override.remaining(at: date) {
            until = "until \(ScheduleEngine.shortTime(override.expiresAt ?? date)). Your schedule resumes afterward (\(Self.relative(remaining)))."
        } else {
            until = "until you resume automation."
        }
        if override.mode == .colorWork {
            return "Color Work is active \(until) Daylight’s own transformations are removed. This does not make the display color-accurate."
        }
        return "\(override.displayName) \(override.isManualAdjustment ? "adjustment" : "mode") \(until)"
    }

    public static func relative(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        if minutes < 1 { return "in less than a minute" }
        if minutes == 1 { return "in 1 minute" }
        if minutes < 60 { return "in \(minutes) minutes" }
        let hours = minutes / 60
        let rem = minutes % 60
        if rem == 0 {
            return hours == 1 ? "in 1 hour" : "in \(hours) hours"
        }
        return "in \(hours)h \(rem)m"
    }

    public static func compact(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded(.down)), 0)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        if rem == 0 { return hours == 1 ? "1h" : "\(hours)h" }
        return "\(hours)h \(rem)m"
    }
}
