import Foundation

public enum ScheduleApproach: String, Sendable, Codable, CaseIterable, Identifiable {
    case personal
    case solar
    case custom
    case hybrid

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .personal: return "Personal schedule"
        case .solar: return "Solar schedule"
        case .custom: return "Custom schedule"
        case .hybrid: return "Hybrid"
        }
    }

    public var summary: String {
        switch self {
        case .personal:
            return "Follow your wake, wind-down, and bedtime routine."
        case .solar:
            return "Shift with local sunrise and sunset."
        case .custom:
            return "Place your own anchors on a 24-hour timeline."
        case .hybrid:
            return "Use solar events during the day and your routine in the evening. Nearby personal times replace solar ones."
        }
    }
}

public enum AnchorKind: String, Sendable, Codable, CaseIterable {
    case wake
    case windDown
    case bedtime
    case overnight
    case sunrise
    case sunset
    case custom

    public var title: String {
        switch self {
        case .wake: return "Wake"
        case .windDown: return "Wind down"
        case .bedtime: return "Bedtime"
        case .overnight: return "Overnight"
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        case .custom: return "Custom"
        }
    }
}

public enum AnchorTiming: Hashable, Sendable, Codable {
    case clock(TimeOfDay)
    case solar(SolarReference, offsetMinutes: Int)

    public var isSolar: Bool {
        if case .solar = self { return true }
        return false
    }
}

public enum SolarReference: String, Sendable, Codable {
    case sunrise
    case sunset
}

public struct ScheduleAnchor: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var kind: AnchorKind
    public var timing: AnchorTiming
    public var output: DesiredOutput
    public var transitionMinutes: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: AnchorKind,
        timing: AnchorTiming,
        output: DesiredOutput,
        transitionMinutes: Int = 30
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.timing = timing
        self.output = output
        self.transitionMinutes = max(0, transitionMinutes)
    }
}

public struct LocationFix: Hashable, Sendable, Codable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String?

    public init(name: String, latitude: Double, longitude: Double, timeZoneIdentifier: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var resolvedTimeZone: TimeZone {
        if let timeZoneIdentifier, let zone = TimeZone(identifier: timeZoneIdentifier) {
            return zone
        }
        return .current
    }
}

public struct ComfortPreset: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var day: DesiredOutput
    public var evening: DesiredOutput
    public var night: DesiredOutput

    public static let subtle = ComfortPreset(
        id: "subtle",
        name: "Subtle",
        day: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
        evening: DesiredOutput(temperature: ColorTemperature(kelvin: 5000)),
        night: DesiredOutput(temperature: ColorTemperature(kelvin: 4500))
    )

    public static let balanced = ComfortPreset(
        id: "balanced",
        name: "Balanced",
        day: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
        evening: DesiredOutput(temperature: ColorTemperature(kelvin: 4200)),
        night: DesiredOutput(temperature: ColorTemperature(kelvin: 3700))
    )

    public static let extraWarm = ComfortPreset(
        id: "extra-warm",
        name: "Extra Warm",
        day: DesiredOutput(temperature: ColorTemperature(kelvin: 6000)),
        evening: DesiredOutput(temperature: ColorTemperature(kelvin: 3800)),
        night: DesiredOutput(temperature: ColorTemperature(kelvin: 3200))
    )

    public static let all: [ComfortPreset] = [.subtle, .balanced, .extraWarm]
}

public struct DailySchedule: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var approach: ScheduleApproach
    public var location: LocationFix?
    public var sunriseOffsetMinutes: Int
    public var sunsetOffsetMinutes: Int
    public var personalAnchors: [ScheduleAnchor]
    public var customAnchors: [ScheduleAnchor]
    public var defaultTransitionMinutes: Int
    public var hybridConflictWindowMinutes: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        approach: ScheduleApproach,
        location: LocationFix? = nil,
        sunriseOffsetMinutes: Int = 0,
        sunsetOffsetMinutes: Int = 0,
        personalAnchors: [ScheduleAnchor] = [],
        customAnchors: [ScheduleAnchor] = [],
        defaultTransitionMinutes: Int = 30,
        hybridConflictWindowMinutes: Int = 20
    ) {
        self.id = id
        self.name = name
        self.approach = approach
        self.location = location
        self.sunriseOffsetMinutes = sunriseOffsetMinutes
        self.sunsetOffsetMinutes = sunsetOffsetMinutes
        self.personalAnchors = personalAnchors
        self.customAnchors = customAnchors
        self.defaultTransitionMinutes = defaultTransitionMinutes
        self.hybridConflictWindowMinutes = hybridConflictWindowMinutes
    }

    public static func personal(preset: ComfortPreset = .balanced) -> DailySchedule {
        DailySchedule(
            name: "Weekday",
            approach: .personal,
            personalAnchors: [
                ScheduleAnchor(
                    name: "Wake",
                    kind: .wake,
                    timing: .clock(TimeOfDay(hour: 7, minute: 0)),
                    output: preset.day,
                    transitionMinutes: 20
                ),
                ScheduleAnchor(
                    name: "Wind down",
                    kind: .windDown,
                    timing: .clock(TimeOfDay(hour: 21, minute: 0)),
                    output: preset.evening,
                    transitionMinutes: 45
                ),
                ScheduleAnchor(
                    name: "Bedtime",
                    kind: .bedtime,
                    timing: .clock(TimeOfDay(hour: 22, minute: 30)),
                    output: preset.night,
                    transitionMinutes: 30
                ),
                ScheduleAnchor(
                    name: "Overnight",
                    kind: .overnight,
                    timing: .clock(TimeOfDay(hour: 23, minute: 30)),
                    output: preset.night,
                    transitionMinutes: 20
                )
            ]
        )
    }

    public var solarDayOutput: DesiredOutput {
        personalAnchors.first { $0.kind == .wake }?.output ?? ComfortPreset.balanced.day
    }

    public mutating func applyDefaultTransitionMinutes(_ minutes: Int) {
        let value = min(max(minutes, 5), 90)
        defaultTransitionMinutes = value
        for index in personalAnchors.indices {
            personalAnchors[index].transitionMinutes = value
        }
        for index in customAnchors.indices {
            customAnchors[index].transitionMinutes = value
        }
    }

    /// Custom with no remaining times falls back to the personal routine still stored on the schedule.
    public mutating func reconcileAfterRemovingCustomTimes() {
        if customAnchors.isEmpty && approach == .custom {
            approach = .personal
        }
    }

    public var solarEveningOutput: DesiredOutput {
        personalAnchors.first { $0.kind == .windDown }?.output
            ?? personalAnchors.first { $0.kind == .bedtime }?.output
            ?? ComfortPreset.balanced.evening
    }

    public func duplicated(name: String) -> DailySchedule {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = name
        copy.personalAnchors = personalAnchors.map {
            var anchor = $0
            anchor.id = UUID().uuidString
            return anchor
        }
        copy.customAnchors = customAnchors.map {
            var anchor = $0
            anchor.id = UUID().uuidString
            return anchor
        }
        return copy
    }

    public func nextFreeCustomTime(startingAt: Int = 16 * 60, step: Int = 60) -> TimeOfDay {
        var used = Set<Int>()
        for anchor in personalAnchors + customAnchors {
            if case .clock(let time) = anchor.timing {
                used.insert(time.minutes)
            }
        }
        var candidate = startingAt
        for _ in 0..<24 {
            let wrapped = ((candidate % 1440) + 1440) % 1440
            if !used.contains(wrapped) {
                return TimeOfDay(minutesFromMidnight: wrapped)
            }
            candidate += step
        }
        return TimeOfDay(minutesFromMidnight: ((startingAt % 1440) + 1440) % 1440)
    }
}

public struct ResolvedAnchor: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: AnchorKind
    public var date: Date
    public var output: DesiredOutput
    public var transitionMinutes: Int
    public var source: String
    public var suppressedReason: String?
    public var scheduleName: String?
    public var movable: Bool

    public init(
        id: String,
        name: String,
        kind: AnchorKind,
        date: Date,
        output: DesiredOutput,
        transitionMinutes: Int,
        source: String,
        suppressedReason: String? = nil,
        scheduleName: String? = nil,
        movable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.date = date
        self.output = output
        self.transitionMinutes = transitionMinutes
        self.source = source
        self.suppressedReason = suppressedReason
        self.scheduleName = scheduleName
        self.movable = movable
    }
}

public struct TimelineSample: Hashable, Sendable {
    public var date: Date
    public var output: DesiredOutput
    public var inTransition: Bool
}

public struct SolarDay: Hashable, Sendable {
    public var sunrise: Date?
    public var sunset: Date?
    public var solarNoon: Date?
    public var polar: PolarSunState
    public var fallbackUsed: Bool
    public var note: String?

    public init(
        sunrise: Date?,
        sunset: Date?,
        solarNoon: Date?,
        polar: PolarSunState,
        fallbackUsed: Bool,
        note: String? = nil
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.solarNoon = solarNoon
        self.polar = polar
        self.fallbackUsed = fallbackUsed
        self.note = note
    }
}

public enum PolarSunState: String, Sendable, Codable {
    case normal
    case polarDay
    case polarNight
}
