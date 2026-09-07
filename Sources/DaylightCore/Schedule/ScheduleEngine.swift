import Foundation

public struct EvaluationContext: Sendable {
    public var calendar: Calendar
    public var timeZone: TimeZone
    public var solarOverride: SolarDay?

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current, solarOverride: SolarDay? = nil) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
        self.solarOverride = solarOverride
    }
}

public struct ScheduleEvaluation: Sendable, Equatable {
    public var output: DesiredOutput
    public var resolvedAnchors: [ResolvedAnchor]
    public var previousAnchor: ResolvedAnchor?
    public var nextAnchor: ResolvedAnchor?
    public var inTransition: Bool
    public var transitionProgress: Double
    public var solar: SolarDay?
    public var explanation: String
    public var periodName: String
    public var nextChangeAt: Date?

    public init(
        output: DesiredOutput,
        resolvedAnchors: [ResolvedAnchor],
        previousAnchor: ResolvedAnchor?,
        nextAnchor: ResolvedAnchor?,
        inTransition: Bool,
        transitionProgress: Double,
        solar: SolarDay?,
        explanation: String,
        periodName: String,
        nextChangeAt: Date? = nil
    ) {
        self.output = output
        self.resolvedAnchors = resolvedAnchors
        self.previousAnchor = previousAnchor
        self.nextAnchor = nextAnchor
        self.inTransition = inTransition
        self.transitionProgress = transitionProgress
        self.solar = solar
        self.explanation = explanation
        self.periodName = periodName
        self.nextChangeAt = nextChangeAt
    }
}

public struct ScheduleEngine: Sendable {
    public var calculator: SolarCalculator

    public init(calculator: SolarCalculator = SolarCalculator()) {
        self.calculator = calculator
    }

    public func evaluate(
        schedule: DailySchedule,
        weekendSchedule: DailySchedule? = nil,
        at date: Date,
        context: EvaluationContext
    ) -> ScheduleEvaluation {
        let active = selectedSchedule(weekday: schedule, weekend: weekendSchedule, at: date, calendar: context.calendar)
        let window = resolveWindow(weekday: schedule, weekend: weekendSchedule, around: date, context: context)
        let activeAnchors = window.anchors.filter { $0.suppressedReason == nil }.sorted { $0.date < $1.date }

        guard let first = activeAnchors.first else {
            let fallback = DesiredOutput(temperature: .defaultDay)
            return ScheduleEvaluation(
                output: fallback,
                resolvedAnchors: window.anchors,
                previousAnchor: nil,
                nextAnchor: nil,
                inTransition: false,
                transitionProgress: 1,
                solar: window.solarToday,
                explanation: "No schedule anchors are available, so Daylight is holding a neutral daytime setting.",
                periodName: "Unscheduled",
                nextChangeAt: nil
            )
        }

        let previous = activeAnchors.last { $0.date <= date } ?? activeAnchors.last ?? first
        let next = activeAnchors.first { $0.date > date } ?? first
        let held = previous

        let transitionDuration = TimeInterval(max(next.transitionMinutes, 0) * 60)
        let nextDate = upcomingDate(of: next, after: date, among: activeAnchors, calendar: context.calendar)
        let transitionStart = nextDate.addingTimeInterval(-transitionDuration)
        let inTransition = date >= transitionStart && date < nextDate && transitionDuration > 0

        let output: DesiredOutput
        let progress: Double
        if inTransition {
            let elapsed = date.timeIntervalSince(transitionStart)
            progress = Interpolation.progress(elapsed: elapsed, duration: max(nextDate.timeIntervalSince(transitionStart), 1))
            output = Interpolation.output(from: held.output, to: next.output, t: progress)
        } else {
            progress = 1
            output = held.output
        }

        let period = periodName(for: held)
        let explanation = explain(
            schedule: active,
            held: held,
            next: next,
            nextDate: nextDate,
            inTransition: inTransition,
            solar: window.solarToday
        )

        return ScheduleEvaluation(
            output: output,
            resolvedAnchors: window.anchors,
            previousAnchor: previous,
            nextAnchor: next as ResolvedAnchor?,
            inTransition: inTransition,
            transitionProgress: progress,
            solar: window.solarToday,
            explanation: explanation,
            periodName: period,
            nextChangeAt: nextDate
        )
    }

    public func samples(
        schedule: DailySchedule,
        weekendSchedule: DailySchedule? = nil,
        on day: Date,
        stepMinutes: Int = 5,
        context: EvaluationContext
    ) -> [TimelineSample] {
        guard let start = context.calendar.startOfDay(for: day) as Date? else { return [] }
        var samples: [TimelineSample] = []
        let step = max(stepMinutes, 1)
        samples.reserveCapacity((24 * 60) / step + 2)
        for minute in stride(from: 0, to: 24 * 60, by: step) {
            guard let date = TimeOfDay(minutesFromMidnight: minute).date(on: day, calendar: context.calendar) else { continue }
            let evaluation = evaluate(schedule: schedule, weekendSchedule: weekendSchedule, at: date, context: context)
            samples.append(TimelineSample(date: date, output: evaluation.output, inTransition: evaluation.inTransition))
        }
        if let close = context.calendar.date(byAdding: .day, value: 1, to: start) {
            let evaluation = evaluate(schedule: schedule, weekendSchedule: weekendSchedule, at: close, context: context)
            samples.append(TimelineSample(date: close, output: evaluation.output, inTransition: evaluation.inTransition))
        }
        return samples
    }

    public func selectedSchedule(
        weekday: DailySchedule,
        weekend: DailySchedule?,
        at date: Date,
        calendar: Calendar
    ) -> DailySchedule {
        guard let weekend else { return weekday }
        return DayKind.kind(for: date, calendar: calendar) == .weekend ? weekend : weekday
    }

    public func resolveAnchors(
        schedule: DailySchedule,
        on day: Date,
        context: EvaluationContext
    ) -> (anchors: [ResolvedAnchor], solar: SolarDay?) {
        let solar = solarDay(for: schedule, on: day, context: context)
        var candidates: [ResolvedAnchor] = []

        func append(anchor: ScheduleAnchor, date: Date?, source: String) {
            guard let date else { return }
            candidates.append(
                ResolvedAnchor(
                    id: "\(source)-\(anchor.id)-\(Int(date.timeIntervalSince1970))",
                    name: anchor.name,
                    kind: anchor.kind,
                    date: date,
                    output: anchor.output,
                    transitionMinutes: anchor.transitionMinutes,
                    source: source,
                    scheduleName: schedule.name,
                    movable: source != "solar" && !anchor.timing.isSolar
                )
            )
        }

        if schedule.approach == .personal || schedule.approach == .hybrid {
            for anchor in schedule.personalAnchors {
                if case .clock(let time) = anchor.timing {
                    append(anchor: anchor, date: time.date(on: day, calendar: context.calendar), source: "personal")
                }
            }
        }

        if schedule.approach == .solar || schedule.approach == .hybrid, let solar {
            let sunriseAnchor = ScheduleAnchor(
                name: "Sunrise",
                kind: .sunrise,
                timing: .solar(.sunrise, offsetMinutes: schedule.sunriseOffsetMinutes),
                output: schedule.solarDayOutput,
                transitionMinutes: schedule.defaultTransitionMinutes
            )
            let sunsetAnchor = ScheduleAnchor(
                name: "Sunset",
                kind: .sunset,
                timing: .solar(.sunset, offsetMinutes: schedule.sunsetOffsetMinutes),
                output: schedule.solarEveningOutput,
                transitionMinutes: schedule.defaultTransitionMinutes
            )
            append(
                anchor: sunriseAnchor,
                date: shifted(solar.sunrise, byMinutes: schedule.sunriseOffsetMinutes, calendar: context.calendar),
                source: "solar"
            )
            append(
                anchor: sunsetAnchor,
                date: shifted(solar.sunset, byMinutes: schedule.sunsetOffsetMinutes, calendar: context.calendar),
                source: "solar"
            )
        }

        if !schedule.customAnchors.isEmpty || schedule.approach == .custom || schedule.approach == .hybrid {
            for anchor in schedule.customAnchors {
                switch anchor.timing {
                case .clock(let time):
                    append(anchor: anchor, date: time.date(on: day, calendar: context.calendar), source: "custom")
                case .solar(let reference, let offset):
                    let base = reference == .sunrise ? solar?.sunrise : solar?.sunset
                    append(anchor: anchor, date: shifted(base, byMinutes: offset, calendar: context.calendar), source: "custom")
                }
            }
        }

        let hasSolar = candidates.contains { $0.source == "solar" }
        let hasClock = candidates.contains { $0.source != "solar" }
        if schedule.approach == .hybrid || (hasSolar && hasClock) {
            candidates = resolveHybridConflicts(candidates, windowMinutes: schedule.hybridConflictWindowMinutes)
        }

        return (candidates.sorted { $0.date < $1.date }, solar)
    }

    /// Personal and custom anchors replace solar anchors that fall inside the conflict window.
    public func resolveHybridConflicts(_ anchors: [ResolvedAnchor], windowMinutes: Int) -> [ResolvedAnchor] {
        let window = TimeInterval(max(windowMinutes, 0) * 60)
        var result = anchors
        let preferred = anchors.filter { $0.source != "solar" }
        for index in result.indices {
            guard result[index].source == "solar" else { continue }
            if preferred.contains(where: { abs($0.date.timeIntervalSince(result[index].date)) <= window }) {
                result[index].suppressedReason = "A personal or custom time is nearby, so this solar event is not used."
            }
        }
        return result
    }

    private struct Window {
        var anchors: [ResolvedAnchor]
        var solarToday: SolarDay?
    }

    private func resolveWindow(weekday: DailySchedule, weekend: DailySchedule?, around date: Date, context: EvaluationContext) -> Window {
        let today = context.calendar.startOfDay(for: date)
        let yesterday = context.calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let tomorrow = context.calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)

        func resolve(_ day: Date) -> (anchors: [ResolvedAnchor], solar: SolarDay?) {
            let schedule = selectedSchedule(weekday: weekday, weekend: weekend, at: day, calendar: context.calendar)
            return resolveAnchors(schedule: schedule, on: day, context: context)
        }

        let y = resolve(yesterday)
        let t = resolve(today)
        let n = resolve(tomorrow)
        return Window(anchors: y.anchors + t.anchors + n.anchors, solarToday: t.solar)
    }

    private func solarDay(for schedule: DailySchedule, on day: Date, context: EvaluationContext) -> SolarDay? {
        if let override = context.solarOverride { return override }
        guard let location = schedule.location else {
            if schedule.approach == .solar || schedule.approach == .hybrid {
                return SolarDay(
                    sunrise: TimeOfDay(hour: 7, minute: 0).date(on: day, calendar: context.calendar),
                    sunset: TimeOfDay(hour: 19, minute: 0).date(on: day, calendar: context.calendar),
                    solarNoon: TimeOfDay(hour: 13, minute: 0).date(on: day, calendar: context.calendar),
                    polar: .normal,
                    fallbackUsed: true,
                    note: "No location is set, so Daylight is using \(TimeOfDay(hour: 7, minute: 0).formatted) and \(TimeOfDay(hour: 19, minute: 0).formatted) placeholders."
                )
            }
            return nil
        }
        return calculator.day(on: day, location: location, timeZone: location.resolvedTimeZone)
    }

    private func shifted(_ date: Date?, byMinutes minutes: Int, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: date)
            ?? date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func upcomingDate(of anchor: ResolvedAnchor, after date: Date, among anchors: [ResolvedAnchor], calendar: Calendar) -> Date {
        if anchor.date > date { return anchor.date }
        if let later = anchors.first(where: {
            $0.kind == anchor.kind
                && $0.source == anchor.source
                && $0.name == anchor.name
                && $0.date > date
                && $0.suppressedReason == nil
        }) {
            return later.date
        }
        return calendar.date(byAdding: .day, value: 1, to: anchor.date) ?? anchor.date.addingTimeInterval(86_400)
    }

    private func periodName(for anchor: ResolvedAnchor) -> String {
        switch anchor.kind {
        case .wake: return "Morning"
        case .windDown: return "Evening"
        case .bedtime, .overnight: return "Night"
        case .sunrise: return "Day"
        case .sunset: return "Dusk"
        case .custom: return anchor.name
        }
    }

    private func explain(
        schedule: DailySchedule,
        held: ResolvedAnchor,
        next: ResolvedAnchor?,
        nextDate: Date,
        inTransition: Bool,
        solar: SolarDay?
    ) -> String {
        var parts: [String] = []
        parts.append("Following your \(schedule.approach.title.lowercased()) (\(schedule.name)).")
        if inTransition, let next {
            let from = crossScheduleNote(held, current: schedule)
            parts.append("Transitioning from \(held.name.lowercased())\(from) toward \(next.name.lowercased()).")
        } else if let name = held.scheduleName, name != schedule.name {
            parts.append("Holding the \(held.name.lowercased()) setting from your \(name.lowercased()) schedule.")
        } else {
            parts.append("Holding the \(held.name.lowercased()) setting.")
        }
        if let next {
            parts.append("Next change: \(next.name) at \(Self.shortTime(nextDate)).")
        }
        if let note = solar?.note {
            parts.append(note)
        }
        return parts.joined(separator: " ")
    }

    private func crossScheduleNote(_ held: ResolvedAnchor, current: DailySchedule) -> String {
        guard let name = held.scheduleName, name != current.name else { return "" }
        return " (\(name.lowercased()))"
    }

    public static func shortTime(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        ClockFormat.shortTime(date, timeZone: timeZone, locale: locale)
    }

    public static func shortStamp(
        _ date: Date,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        ClockFormat.shortStamp(date, now: now, timeZone: timeZone, locale: locale, calendar: calendar)
    }
}
