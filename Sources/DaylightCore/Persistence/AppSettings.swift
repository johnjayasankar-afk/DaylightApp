import Foundation

public struct AppSettings: Hashable, Sendable, Codable {
    public var schemaVersion: Int
    public var onboarded: Bool
    public var launchAtLogin: Bool
    public var keepRunningInBackground: Bool
    public var useAdvancedTemperatureRange: Bool
    public var reduceMotion: Bool
    public var historyEnabled: Bool
    public var selectedPresetID: String
    public var weekdaySchedule: DailySchedule
    public var weekendSchedule: DailySchedule
    public var useWeekendSchedule: Bool
    public var profiles: [LightingProfile]
    public var displays: [DisplayPreferences]
    public var groups: [DisplayGroup]
    public var workspaces: [WorkspaceProfile]
    public var pause: PauseState
    public var override: TemporaryOverride?
    public var disabled: Bool
    public var defaultTransitionMinutes: Int
    public var writeIntervalMilliseconds: Int
    public var temperatureWriteThreshold: Double
    public var location: LocationFix?
    public var appearance: AppearancePreference
    public var lastWorkspaceID: String?
    public var showMenuBarTemperature: Bool
    public var lastSelectedTab: String?
    public var lastSelectedDisplayID: String?
    public var sliderDuration: OverrideDuration
    public var sliderAffectsAllDisplays: Bool
    public var restoreOnSleep: Bool
    public var lastEditingWeekend: Bool?

    public static let currentSchemaVersion = 1

    /// Factory defaults for an already-set-up Mac. First launch still uses `AppSettings()`.
    public static func resetDefaults() -> AppSettings {
        var settings = AppSettings()
        settings.onboarded = true
        return settings
    }

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        onboarded: Bool = false,
        launchAtLogin: Bool = false,
        keepRunningInBackground: Bool = true,
        useAdvancedTemperatureRange: Bool = false,
        reduceMotion: Bool = false,
        historyEnabled: Bool = false,
        selectedPresetID: String = ComfortPreset.balanced.id,
        weekdaySchedule: DailySchedule = .personal(),
        weekendSchedule: DailySchedule = DailySchedule.personal().duplicated(name: "Weekend"),
        useWeekendSchedule: Bool = false,
        profiles: [LightingProfile] = LightingProfile.defaults(from: .balanced),
        displays: [DisplayPreferences] = [],
        groups: [DisplayGroup] = [],
        workspaces: [WorkspaceProfile] = [],
        pause: PauseState = .inactive,
        override: TemporaryOverride? = nil,
        disabled: Bool = false,
        defaultTransitionMinutes: Int = 30,
        writeIntervalMilliseconds: Int = 750,
        temperatureWriteThreshold: Double = 18,
        location: LocationFix? = nil,
        appearance: AppearancePreference = .system,
        lastWorkspaceID: String? = nil,
        showMenuBarTemperature: Bool = true,
        lastSelectedTab: String? = nil,
        lastSelectedDisplayID: String? = nil,
        sliderDuration: OverrideDuration = .minutes(30),
        sliderAffectsAllDisplays: Bool = true,
        restoreOnSleep: Bool = true,
        lastEditingWeekend: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.onboarded = onboarded
        self.launchAtLogin = launchAtLogin
        self.keepRunningInBackground = keepRunningInBackground
        self.useAdvancedTemperatureRange = useAdvancedTemperatureRange
        self.reduceMotion = reduceMotion
        self.historyEnabled = historyEnabled
        self.selectedPresetID = selectedPresetID
        self.weekdaySchedule = weekdaySchedule
        self.weekendSchedule = weekendSchedule
        self.useWeekendSchedule = useWeekendSchedule
        self.profiles = profiles
        self.displays = displays
        self.groups = groups
        self.workspaces = workspaces
        self.pause = pause
        self.override = override
        self.disabled = disabled
        self.defaultTransitionMinutes = defaultTransitionMinutes
        self.writeIntervalMilliseconds = writeIntervalMilliseconds
        self.temperatureWriteThreshold = temperatureWriteThreshold
        self.location = location
        self.appearance = appearance
        self.lastWorkspaceID = lastWorkspaceID
        self.showMenuBarTemperature = showMenuBarTemperature
        self.lastSelectedTab = lastSelectedTab
        self.lastSelectedDisplayID = lastSelectedDisplayID
        self.sliderDuration = sliderDuration
        self.sliderAffectsAllDisplays = sliderAffectsAllDisplays
        self.restoreOnSleep = restoreOnSleep
        self.lastEditingWeekend = lastEditingWeekend
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? defaults.schemaVersion
        onboarded = try container.decodeIfPresent(Bool.self, forKey: .onboarded) ?? defaults.onboarded
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        keepRunningInBackground = try container.decodeIfPresent(Bool.self, forKey: .keepRunningInBackground) ?? defaults.keepRunningInBackground
        useAdvancedTemperatureRange = try container.decodeIfPresent(Bool.self, forKey: .useAdvancedTemperatureRange) ?? defaults.useAdvancedTemperatureRange
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? defaults.reduceMotion
        historyEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? defaults.historyEnabled
        selectedPresetID = try container.decodeIfPresent(String.self, forKey: .selectedPresetID) ?? defaults.selectedPresetID
        weekdaySchedule = try container.decodeIfPresent(DailySchedule.self, forKey: .weekdaySchedule) ?? defaults.weekdaySchedule
        weekendSchedule = try container.decodeIfPresent(DailySchedule.self, forKey: .weekendSchedule) ?? defaults.weekendSchedule
        useWeekendSchedule = try container.decodeIfPresent(Bool.self, forKey: .useWeekendSchedule) ?? defaults.useWeekendSchedule
        profiles = try container.decodeIfPresent([LightingProfile].self, forKey: .profiles) ?? defaults.profiles
        displays = try container.decodeIfPresent([DisplayPreferences].self, forKey: .displays) ?? defaults.displays
        groups = try container.decodeIfPresent([DisplayGroup].self, forKey: .groups) ?? defaults.groups
        workspaces = try container.decodeIfPresent([WorkspaceProfile].self, forKey: .workspaces) ?? defaults.workspaces
        pause = try container.decodeIfPresent(PauseState.self, forKey: .pause) ?? defaults.pause
        override = try container.decodeIfPresent(TemporaryOverride.self, forKey: .override)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? defaults.disabled
        defaultTransitionMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultTransitionMinutes) ?? defaults.defaultTransitionMinutes
        writeIntervalMilliseconds = try container.decodeIfPresent(Int.self, forKey: .writeIntervalMilliseconds) ?? defaults.writeIntervalMilliseconds
        temperatureWriteThreshold = try container.decodeIfPresent(Double.self, forKey: .temperatureWriteThreshold) ?? defaults.temperatureWriteThreshold
        location = try container.decodeIfPresent(LocationFix.self, forKey: .location)
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? defaults.appearance
        lastWorkspaceID = try container.decodeIfPresent(String.self, forKey: .lastWorkspaceID)
        showMenuBarTemperature = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarTemperature) ?? defaults.showMenuBarTemperature
        lastSelectedTab = try container.decodeIfPresent(String.self, forKey: .lastSelectedTab)
        lastSelectedDisplayID = try container.decodeIfPresent(String.self, forKey: .lastSelectedDisplayID)
        sliderDuration = try container.decodeIfPresent(OverrideDuration.self, forKey: .sliderDuration) ?? defaults.sliderDuration
        sliderAffectsAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .sliderAffectsAllDisplays) ?? defaults.sliderAffectsAllDisplays
        restoreOnSleep = try container.decodeIfPresent(Bool.self, forKey: .restoreOnSleep) ?? defaults.restoreOnSleep
        lastEditingWeekend = try container.decodeIfPresent(Bool.self, forKey: .lastEditingWeekend)
    }

    /// Weekend-edit mode remembered from the last session, or Saturday/Sunday if never set.
    public func resolvedEditingWeekend(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard useWeekendSchedule else { return false }
        return lastEditingWeekend ?? (DayKind.kind(for: date, calendar: calendar) == .weekend)
    }

    public var preset: ComfortPreset {
        ComfortPreset.all.first { $0.id == selectedPresetID } ?? .balanced
    }

    public var temperatureRange: ClosedRange<Double> {
        DisplayLimits.range(advanced: useAdvancedTemperatureRange)
    }

    /// Approach and solar offsets are one product choice, even when weekend times differ.
    public mutating func applySharedScheduleStyle(
        approach: ScheduleApproach? = nil,
        sunriseOffsetMinutes: Int? = nil,
        sunsetOffsetMinutes: Int? = nil
    ) {
        if let approach {
            weekdaySchedule.approach = approach
            weekendSchedule.approach = approach
        }
        if let sunriseOffsetMinutes {
            weekdaySchedule.sunriseOffsetMinutes = sunriseOffsetMinutes
            weekendSchedule.sunriseOffsetMinutes = sunriseOffsetMinutes
        }
        if let sunsetOffsetMinutes {
            weekdaySchedule.sunsetOffsetMinutes = sunsetOffsetMinutes
            weekendSchedule.sunsetOffsetMinutes = sunsetOffsetMinutes
        }
    }

    public mutating func applyPreset(_ preset: ComfortPreset) {
        selectedPresetID = preset.id
        func restyle(_ schedule: inout DailySchedule) {
            for index in schedule.personalAnchors.indices {
                switch schedule.personalAnchors[index].kind {
                case .wake:
                    schedule.personalAnchors[index].output = preset.day
                case .windDown:
                    schedule.personalAnchors[index].output = preset.evening
                case .bedtime, .overnight:
                    schedule.personalAnchors[index].output = preset.night
                default:
                    break
                }
            }
        }
        restyle(&weekdaySchedule)
        restyle(&weekendSchedule)
        profiles = LightingProfile.defaults(from: preset)
        weekdaySchedule.location = location
        weekendSchedule.location = location
    }

    public mutating func upsertDisplay(_ preferences: DisplayPreferences) {
        if let index = displays.firstIndex(where: { $0.id == preferences.id }) {
            displays[index] = preferences
        } else {
            displays.append(preferences)
        }
    }

    public func preferences(for identity: DisplayIdentity) -> DisplayPreferences {
        if let match = matchExistingIdentity(identity) {
            return match.0
        }
        return DisplayPreferences(identity: identity)
    }

    /// Moves saved names, exclusions, and link keys onto the live identity when a UUID changes.
    public mutating func adoptConnectedIdentity(_ incoming: DisplayIdentity) -> DisplayPreferences {
        guard let (existing, _) = matchExistingIdentity(incoming) else {
            let created = DisplayPreferences(identity: incoming)
            displays.append(created)
            return created
        }
        let oldKey = existing.identity.durableKey
        let newKey = incoming.durableKey
        guard oldKey != newKey else { return existing }
        var updated = existing
        updated.identity = incoming
        if let index = displays.firstIndex(where: { $0.identity.durableKey == oldKey }) {
            displays[index] = updated
        } else {
            displays.append(updated)
        }
        for index in groups.indices {
            groups[index].displayKeys = groups[index].displayKeys.map { $0 == oldKey ? newKey : $0 }
        }
        if lastSelectedDisplayID == oldKey {
            lastSelectedDisplayID = newKey
        }
        if var override, !override.appliesToDisplayKeys.isEmpty {
            override.appliesToDisplayKeys = override.appliesToDisplayKeys.map { $0 == oldKey ? newKey : $0 }
            self.override = override
        }
        return updated
    }

    public mutating func retargetOverride(selectedDisplayID: String?, allDisplays: Bool, at date: Date = Date()) {
        guard var override, override.isActive(at: date) else { return }
        override.appliesToDisplayKeys = overrideTargetKeys(selectedDisplayID: selectedDisplayID, allDisplays: allDisplays)
        self.override = override
    }

    public func overrideTargetKeys(selectedDisplayID: String?, allDisplays: Bool) -> [String] {
        if allDisplays { return [] }
        guard let selectedDisplayID else { return [] }
        if let group = groups.first(where: { $0.displayKeys.contains(selectedDisplayID) && $0.displayKeys.count > 1 }) {
            return group.displayKeys
        }
        return [selectedDisplayID]
    }

    public func isLinked(_ displayID: String?) -> Bool {
        guard let displayID else { return false }
        return groups.contains { $0.displayKeys.contains(displayID) && $0.displayKeys.count > 1 }
    }

    /// Drops pause/override records whose expiration is already in the past.
    /// Uses wall-clock time, never a preview playhead.
    @discardableResult
    public mutating func pruneExpiredStates(at date: Date = Date()) -> Bool {
        var changed = false
        if pause.isPaused, !pause.isActive(at: date) {
            pause = .inactive
            changed = true
        }
        if let override, !override.isActive(at: date) {
            self.override = nil
            changed = true
        }
        return changed
    }

    public func matchExistingIdentity(_ incoming: DisplayIdentity) -> (DisplayPreferences, DisplayMatchConfidence)? {
        var best: (DisplayPreferences, DisplayMatchConfidence)?
        for item in displays {
            let confidence = item.identity.matchConfidence(against: incoming)
            if confidence == .uncertain { continue }
            if best == nil || confidence == .exact || (confidence == .strong && best?.1 != .exact) {
                best = (item, confidence)
            }
        }
        return best
    }
}

public enum AppearancePreference: String, Sendable, Codable, CaseIterable {
    case system
    case light
    case dark

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public struct OwnershipRecord: Hashable, Sendable, Codable {
    public var updatedAt: Date
    public var displays: [DisplayOwnership]

    public init(updatedAt: Date, displays: [DisplayOwnership]) {
        self.updatedAt = updatedAt
        self.displays = displays
    }
}

public struct DisplayOwnership: Hashable, Sendable, Codable {
    public var displayKey: String
    public var capturedBaseline: Bool
    public var applyingTransform: Bool
    public var lastRequestedKelvin: Double?
    public var lastWriteSucceeded: Bool
    public var notes: [String]

    public init(
        displayKey: String,
        capturedBaseline: Bool,
        applyingTransform: Bool,
        lastRequestedKelvin: Double? = nil,
        lastWriteSucceeded: Bool,
        notes: [String] = []
    ) {
        self.displayKey = displayKey
        self.capturedBaseline = capturedBaseline
        self.applyingTransform = applyingTransform
        self.lastRequestedKelvin = lastRequestedKelvin
        self.lastWriteSucceeded = lastWriteSucceeded
        self.notes = notes
    }
}

public struct HistoryEvent: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var at: Date
    public var title: String
    public var detail: String

    public init(id: String = UUID().uuidString, at: Date, title: String, detail: String) {
        self.id = id
        self.at = at
        self.title = title
        self.detail = detail
    }
}
