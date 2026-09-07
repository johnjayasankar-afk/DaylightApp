import Foundation

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public final class ControllableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    public init(now instant: Date) {
        self.instant = instant
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    public func set(_ instant: Date) {
        lock.lock()
        self.instant = instant
        lock.unlock()
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        instant.addTimeInterval(interval)
        lock.unlock()
    }
}

public enum TimeOfDay: Hashable, Sendable, Codable, Comparable {
    case minutesFromMidnight(Int)

    public var minutes: Int {
        switch self {
        case .minutesFromMidnight(let value):
            return ((value % 1440) + 1440) % 1440
        }
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public init(hour: Int, minute: Int) {
        self = .minutesFromMidnight(hour * 60 + minute)
    }

    public init(minutesFromMidnight minutes: Int) {
        self = .minutesFromMidnight(minutes)
    }

    public func date(on day: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.nanosecond = 0
        if let exact = calendar.date(from: components) {
            return exact
        }
        components.hour = min(hour + 1, 23)
        components.minute = 0
        return calendar.date(from: components)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutes < rhs.minutes
    }

    public func formatted(locale: Locale = .current) -> String {
        var calendar = Calendar.current
        calendar.locale = locale
        var components = DateComponents()
        components.year = calendar.component(.year, from: Date())
        components.month = 1
        components.day = 15
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let date = calendar.date(from: components) {
            return ClockFormat.shortTime(date, locale: locale)
        }
        if let date = date(on: Date(), calendar: .current) {
            return ClockFormat.shortTime(date, locale: locale)
        }
        let hours = hour
        let mins = minute
        let period = hours >= 12 ? "PM" : "AM"
        let twelve = hours % 12 == 0 ? 12 : hours % 12
        return String(format: "%d:%02d %@", twelve, mins, period)
    }

    public var formatted: String { formatted() }
}

public enum ClockFormat: Sendable {
    public static func uses24HourClock(locale: Locale = .current) -> Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("H") == true
    }

    public static func shortTime(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    public static func shortStamp(
        _ date: Date,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        calendar.locale = locale
        let time = shortTime(date, timeZone: timeZone, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return time
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func compactHour(_ hour: Int, locale: Locale = .current) -> String {
        let wrapped = hour == 24 ? 0 : hour
        if uses24HourClock(locale: locale) {
            return "\(wrapped)"
        }
        if wrapped == 0 { return "12a" }
        if wrapped == 12 { return "12p" }
        return wrapped > 12 ? "\(wrapped - 12)p" : "\(wrapped)a"
    }
}

public enum DayKind: String, Sendable, Codable, CaseIterable {
    case weekday
    case weekend

    public static func kind(for date: Date, calendar: Calendar = .current) -> DayKind {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }

    /// The nearest Saturday when `date` is a weekday, otherwise `date`.
    /// Used so weekend-schedule editing is previewed on a weekend day.
    public static func nearbyWeekend(from date: Date, calendar: Calendar = .current) -> Date {
        if kind(for: date, calendar: calendar) == .weekend { return date }
        let weekday = calendar.component(.weekday, from: date)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: date) ?? date
    }

    /// The nearest Friday when `date` is Saturday, or Monday when it is Sunday.
    /// Used so weekday-schedule editing on a weekend day is previewed on a weekday.
    public static func nearbyWeekday(from date: Date, calendar: Calendar = .current) -> Date {
        if kind(for: date, calendar: calendar) == .weekday { return date }
        let weekday = calendar.component(.weekday, from: date)
        let delta = weekday == 1 ? 1 : -1
        return calendar.date(byAdding: .day, value: delta, to: date) ?? date
    }

    /// The day the timeline should show. Living surfaces use `now`. Schedule editing maps onto a matching weekday or weekend.
    public static func scheduleCanvasDate(
        now: Date = Date(),
        editingWeekend: Bool,
        useWeekendSchedule: Bool,
        preferEditorDay: Bool,
        calendar: Calendar = .current
    ) -> Date {
        guard preferEditorDay else { return now }
        if editingWeekend {
            return nearbyWeekend(from: now, calendar: calendar)
        }
        if useWeekendSchedule, kind(for: now, calendar: calendar) == .weekend {
            return nearbyWeekday(from: now, calendar: calendar)
        }
        return now
    }
}

/// Maps a 0...1 day-preview progress onto a calendar date, including the next midnight.
public enum DayPreviewClock: Sendable {
    public static func date(progress t: Double, startOfDay: Date, calendar: Calendar = .current) -> Date {
        let clamped = min(max(t, 0), 1)
        if clamped >= 1, let next = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
            return next
        }
        let minutes = min(max(Int((clamped * 1440).rounded()), 0), 1439)
        return TimeOfDay(minutesFromMidnight: minutes).date(on: startOfDay, calendar: calendar)
            ?? startOfDay.addingTimeInterval(clamped * 86_400)
    }
}
