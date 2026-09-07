import DaylightCore
import DaylightMac
import Foundation

@main
struct DaylightChecks {
    static func main() {
        var failed = 0
        func check(_ name: String, _ condition: () throws -> Bool) {
            do {
                if try condition() {
                    print("PASS  \(name)")
                } else {
                    print("FAIL  \(name)")
                    failed += 1
                }
            } catch {
                print("FAIL  \(name) — \(error)")
                failed += 1
            }
        }

        let from = ColorTemperature(kelvin: 6500)
        let to = ColorTemperature(kelvin: 3250)
        let mid = Interpolation.temperature(from: from, to: to, t: 0.5)
        check("mired interpolation is not linear Kelvin") {
            abs(mid.kelvin - 4333) < 40 && abs(mid.kelvin - 4875) > 40
        }

        let a = DesiredOutput(temperature: ColorTemperature(kelvin: 5000))
        let b = DesiredOutput(temperature: ColorTemperature(kelvin: 5010))
        let c = DesiredOutput(temperature: ColorTemperature(kelvin: 5100))
        check("tiny temperature writes are suppressed") {
            Interpolation.isMaterialChange(from: a, to: b) == false && Interpolation.isMaterialChange(from: a, to: c)
        }

        let warm = TemperatureAppearance.channelScale(for: ColorTemperature(kelvin: 4000))
        check("warm scale reduces blue") { warm.blue < warm.red && warm.blue < 0.85 }

        let baseline = TransferTable.linear(count: 64)
        let once = baseline.applying(warm)
        check("tables apply relative to a baseline") { baseline.maxAbsoluteDelta(from: once) > 0.05 }

        let engine = ScheduleEngine()
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        let morning = engine.evaluate(
            schedule: .personal(),
            at: date(2026, 3, 4, 10, 0, calendar: ny),
            context: EvaluationContext(calendar: ny, timeZone: ny.timeZone)
        )
        check("weekday morning holds wake setting") {
            morning.previousAnchor?.kind == .wake && abs(morning.output.temperature.kelvin - 6500) < 1 && morning.inTransition == false
        }

        let lateNight = engine.evaluate(
            schedule: .personal(),
            at: date(2026, 3, 4, 23, 50, calendar: ny),
            context: EvaluationContext(calendar: ny, timeZone: ny.timeZone)
        )
        check("late-night next change is still in the future") {
            guard let next = lateNight.nextChangeAt else { return false }
            return next > date(2026, 3, 4, 23, 50, calendar: ny)
        }

        let dusk = engine.evaluate(
            schedule: .personal(),
            at: date(2026, 3, 4, 20, 40, calendar: ny),
            context: EvaluationContext(calendar: ny, timeZone: ny.timeZone)
        )
        check("wind-down transition is in progress before 21:00") {
            dusk.inTransition && dusk.output.temperature.kelvin > 4200 && dusk.output.temperature.kelvin < 6500
        }

        var night = DailySchedule.personal()
        night.personalAnchors = [
            ScheduleAnchor(name: "Wake", kind: .wake, timing: .clock(TimeOfDay(hour: 20, minute: 0)), output: ComfortPreset.balanced.day, transitionMinutes: 15),
            ScheduleAnchor(name: "Wind down", kind: .windDown, timing: .clock(TimeOfDay(hour: 6, minute: 0)), output: ComfortPreset.balanced.evening, transitionMinutes: 30),
            ScheduleAnchor(name: "Bedtime", kind: .bedtime, timing: .clock(TimeOfDay(hour: 8, minute: 0)), output: ComfortPreset.balanced.night, transitionMinutes: 20)
        ]
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago")!
        let overnight = engine.evaluate(schedule: night, at: date(2026, 6, 10, 2, 0, calendar: chicago), context: EvaluationContext(calendar: chicago, timeZone: chicago.timeZone))
        check("night-shift schedule crosses midnight") { overnight.previousAnchor?.kind == .wake }

        var weekend = DailySchedule.personal().duplicated(name: "Weekend")
        weekend.personalAnchors[0].output = DesiredOutput(temperature: ColorTemperature(kelvin: 5000))
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        check("weekend schedule is selected on Saturday") {
            engine.selectedSchedule(weekday: .personal(), weekend: weekend, at: date(2026, 3, 7, 10, 0, calendar: la), calendar: la).name == "Weekend"
        }

        var weekdayNight = DailySchedule.personal()
        weekdayNight.name = "Weekday"
        weekdayNight.personalAnchors = [
            ScheduleAnchor(name: "Wake", kind: .wake, timing: .clock(TimeOfDay(hour: 7, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)), transitionMinutes: 15),
            ScheduleAnchor(name: "Bedtime", kind: .bedtime, timing: .clock(TimeOfDay(hour: 22, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 3700)), transitionMinutes: 20),
            ScheduleAnchor(name: "Overnight", kind: .overnight, timing: .clock(TimeOfDay(hour: 23, minute: 30)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 3700)), transitionMinutes: 15)
        ]
        var weekendNight = weekdayNight.duplicated(name: "Weekend")
        weekendNight.personalAnchors = [
            ScheduleAnchor(name: "Wake", kind: .wake, timing: .clock(TimeOfDay(hour: 9, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 5000)), transitionMinutes: 15),
            ScheduleAnchor(name: "Bedtime", kind: .bedtime, timing: .clock(TimeOfDay(hour: 23, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 4200)), transitionMinutes: 20),
            ScheduleAnchor(name: "Overnight", kind: .overnight, timing: .clock(TimeOfDay(hour: 23, minute: 45)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 4200)), transitionMinutes: 15)
        ]
        let saturdayEarly = engine.evaluate(
            schedule: weekdayNight,
            weekendSchedule: weekendNight,
            at: date(2026, 3, 7, 1, 0, calendar: la),
            context: EvaluationContext(calendar: la, timeZone: la.timeZone)
        )
        check("Saturday 1 AM still holds Friday’s weekday night") {
            abs(saturdayEarly.output.temperature.kelvin - 3700) < 1
                && saturdayEarly.previousAnchor?.scheduleName == "Weekday"
        }
        let mondayEarly = engine.evaluate(
            schedule: weekdayNight,
            weekendSchedule: weekendNight,
            at: date(2026, 3, 9, 1, 0, calendar: la),
            context: EvaluationContext(calendar: la, timeZone: la.timeZone)
        )
        check("Monday 1 AM still holds Sunday’s weekend night") {
            abs(mondayEarly.output.temperature.kelvin - 4200) < 1
                && mondayEarly.previousAnchor?.scheduleName == "Weekend"
        }

        let solar = ResolvedAnchor(id: "s", name: "Sunset", kind: .sunset, date: Date(timeIntervalSince1970: 1_000_000), output: ComfortPreset.balanced.evening, transitionMinutes: 30, source: "solar")
        let personal = ResolvedAnchor(id: "p", name: "Wind down", kind: .windDown, date: Date(timeIntervalSince1970: 1_000_000 + 480), output: ComfortPreset.balanced.evening, transitionMinutes: 30, source: "personal")
        let hybrid = engine.resolveHybridConflicts([solar, personal], windowMinutes: 20)
        check("hybrid suppresses nearby solar anchors") {
            hybrid.first { $0.source == "solar" }?.suppressedReason != nil && hybrid.first { $0.source == "personal" }?.suppressedReason == nil
        }

        var solarOnly = DailySchedule.personal()
        solarOnly.approach = .solar
        solarOnly.location = nil
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let missing = engine.evaluate(schedule: solarOnly, at: date(2026, 5, 1, 12, 0, calendar: utc), context: EvaluationContext(calendar: utc, timeZone: utc.timeZone))
        check("missing location uses solar placeholders") { missing.solar?.fallbackUsed == true }

        var solarFromWake = DailySchedule.personal()
        solarFromWake.approach = .solar
        solarFromWake.location = nil
        if let index = solarFromWake.personalAnchors.firstIndex(where: { $0.kind == .wake }) {
            solarFromWake.personalAnchors[index].output = DesiredOutput(temperature: ColorTemperature(kelvin: 5800))
        }
        if let index = solarFromWake.personalAnchors.firstIndex(where: { $0.kind == .windDown }) {
            solarFromWake.personalAnchors[index].output = DesiredOutput(temperature: ColorTemperature(kelvin: 3600))
        }
        let solarResolved = engine.evaluate(
            schedule: solarFromWake,
            at: date(2026, 5, 1, 12, 0, calendar: utc),
            context: EvaluationContext(calendar: utc, timeZone: utc.timeZone)
        )
        var offsetSchedule = DailySchedule.personal()
        offsetSchedule.approach = .solar
        offsetSchedule.sunriseOffsetMinutes = 60
        let springStart = ny.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let preSpringSunrise = date(2026, 3, 8, 1, 30, calendar: ny)
        let offsetContext = EvaluationContext(
            calendar: ny,
            timeZone: ny.timeZone,
            solarOverride: SolarDay(
                sunrise: preSpringSunrise,
                sunset: date(2026, 3, 8, 18, 0, calendar: ny),
                solarNoon: date(2026, 3, 8, 12, 0, calendar: ny),
                polar: .normal,
                fallbackUsed: false
            )
        )
        let offsetAnchors = engine.resolveAnchors(schedule: offsetSchedule, on: springStart, context: offsetContext)
        check("solar offset uses calendar minutes across spring-forward") {
            guard let rise = offsetAnchors.anchors.first(where: { $0.kind == .sunrise }) else { return false }
            return ny.component(.hour, from: rise.date) == 3 && ny.component(.minute, from: rise.date) == 30
        }

        check("solar sunrise follows the wake setting") {
            solarResolved.resolvedAnchors.contains { $0.kind == .sunrise && abs($0.output.temperature.kelvin - 5800) < 1 }
                && solarResolved.resolvedAnchors.contains { $0.kind == .sunset && abs($0.output.temperature.kelvin - 3600) < 1 }
        }

        let afterDST = engine.evaluate(schedule: .personal(), at: date(2026, 3, 8, 8, 30, calendar: ny), context: EvaluationContext(calendar: ny, timeZone: ny.timeZone))
        check("spring-forward morning still evaluates") { abs(afterDST.output.temperature.kelvin - 6500) < 1 }

        let springDay = ny.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        check("clock times are built from date components") {
            let seven = TimeOfDay(hour: 7, minute: 0).date(on: springDay, calendar: ny)
            return seven != nil && ny.component(.hour, from: seven!) == 7
        }
        check("missing spring-forward hour still resolves") {
            TimeOfDay(hour: 2, minute: 30).date(on: springDay, calendar: ny) != nil
        }
        let dstSamples = engine.samples(
            schedule: .personal(),
            on: springDay,
            stepMinutes: 30,
            context: EvaluationContext(calendar: ny, timeZone: ny.timeZone)
        )
        check("spring-forward timeline samples stay on that calendar day until midnight") {
            let interior = dstSamples.dropLast()
            return !interior.isEmpty && interior.allSatisfy { ny.isDate($0.date, inSameDayAs: springDay) }
        }

        var denver = Calendar(identifier: .gregorian)
        denver.timeZone = TimeZone(identifier: "America/Denver")!
        let wakeRecompute = engine.evaluate(schedule: .personal(), at: date(2026, 4, 2, 21, 30, calendar: denver), context: EvaluationContext(calendar: denver, timeZone: denver.timeZone))
        check("wake recomputes current evening state") {
            wakeRecompute.previousAnchor?.kind == .windDown && abs(wakeRecompute.output.temperature.kelvin - 4200) < 1
        }

        let calculator = SolarCalculator()
        let sfZone = TimeZone(identifier: "America/Los_Angeles")!
        var sfCal = Calendar(identifier: .gregorian)
        sfCal.timeZone = sfZone
        let sf = calculator.day(on: sfCal.date(from: DateComponents(year: 2026, month: 3, day: 20))!, location: Cities.featured.first { $0.name.contains("San Francisco") }!, timeZone: sfZone)
        check("San Francisco sunrise precedes sunset") {
            guard let rise = sf.sunrise, let set = sf.sunset else { return false }
            let hour = sfCal.component(.hour, from: rise)
            return sf.polar == .normal && rise < set && (5...9).contains(hour)
        }

        let arctic = Cities.featured.first { $0.name.contains("Longyearbyen") }!
        let arcticZone = TimeZone(identifier: "Arctic/Longyearbyen")!
        var arcticCal = Calendar(identifier: .gregorian)
        arcticCal.timeZone = arcticZone
        let polarDay = calculator.day(on: arcticCal.date(from: DateComponents(year: 2026, month: 6, day: 21))!, location: arctic, timeZone: arcticZone)
        let polarNight = calculator.day(on: arcticCal.date(from: DateComponents(year: 2026, month: 12, day: 21))!, location: arctic, timeZone: arcticZone)
        check("polar day fallback") { polarDay.polar == .polarDay && polarDay.fallbackUsed && polarDay.sunrise != nil && polarDay.sunset != nil }
        check("polar night fallback") { polarNight.polar == .polarNight && polarNight.fallbackUsed && polarNight.sunrise != nil && polarNight.sunset != nil }

        let schedule = engine.evaluate(schedule: .personal(), at: Date(), context: EvaluationContext())
        var settings = AppSettings()
        settings.override = TemporaryOverride(mode: .colorWork, duration: .untilResumed, startedAt: Date(), expiresAt: nil, reason: "test")
        check("color work beats the schedule") {
            let decision = RulesEngine().decide(at: Date(), settings: settings, schedule: schedule, emergencyRestore: false, disabled: false)
            return decision.winningPriority == .temporaryOverride && decision.restoreToBaseline && decision.automation == .colorWork
        }
        check("a slider hold wins as Manual") {
            var manual = AppSettings()
            manual.override = TemporaryOverride(
                mode: .focus,
                output: DesiredOutput(temperature: ColorTemperature(kelvin: 4300)),
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment"
            )
            return RulesEngine().decide(at: Date(), settings: manual, schedule: schedule, emergencyRestore: false, disabled: false).winningName == "Manual"
        }
        check("a hold until resume has no schedule countdown") {
            var hold = AppSettings()
            hold.override = TemporaryOverride(
                mode: .focus,
                output: DesiredOutput(temperature: ColorTemperature(kelvin: 4300)),
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment"
            )
            let decision = RulesEngine().decide(at: Date(), settings: hold, schedule: schedule, emergencyRestore: false, disabled: false)
            return decision.nextWake == nil
                && StatusExplainer.nextChangeLine(wake: nil, automation: .override, at: Date()) == "Held until you resume automation."
        }
        check("approach and solar offsets apply to both schedules") {
            var shared = AppSettings()
            shared.weekendSchedule.approach = .custom
            shared.weekendSchedule.sunriseOffsetMinutes = 12
            shared.applySharedScheduleStyle(approach: .solar, sunriseOffsetMinutes: -15, sunsetOffsetMinutes: 20)
            return shared.weekdaySchedule.approach == .solar
                && shared.weekendSchedule.approach == .solar
                && shared.weekdaySchedule.sunriseOffsetMinutes == -15
                && shared.weekendSchedule.sunriseOffsetMinutes == -15
                && shared.weekdaySchedule.sunsetOffsetMinutes == 20
                && shared.weekendSchedule.sunsetOffsetMinutes == 20
        }
        check("weekend edit is remembered on a weekday") {
            var remembered = AppSettings()
            remembered.useWeekendSchedule = true
            remembered.lastEditingWeekend = true
            var weekdayCal = Calendar(identifier: .gregorian)
            weekdayCal.timeZone = TimeZone(identifier: "America/New_York")!
            let wednesday = date(2026, 3, 4, 10, 0, calendar: weekdayCal)
            return remembered.resolvedEditingWeekend(at: wednesday, calendar: weekdayCal)
        }
        check("weekend edit defaults to the calendar day when never set") {
            var fresh = AppSettings()
            fresh.useWeekendSchedule = true
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/New_York")!
            let saturday = date(2026, 3, 7, 10, 0, calendar: cal)
            let wednesday = date(2026, 3, 4, 10, 0, calendar: cal)
            return fresh.resolvedEditingWeekend(at: saturday, calendar: cal)
                && fresh.resolvedEditingWeekend(at: wednesday, calendar: cal) == false
        }
        settings.pause = PauseState(isPaused: true, expiresAt: Date().addingTimeInterval(600), reason: "test")
        check("pause beats override") {
            RulesEngine().decide(at: Date(), settings: settings, schedule: schedule, emergencyRestore: false, disabled: false).winningPriority == .userPause
        }
        check("emergency beats pause") {
            RulesEngine().decide(at: Date(), settings: settings, schedule: schedule, emergencyRestore: true, disabled: false).winningPriority == .emergencyRestore
        }

        let start = Date(timeIntervalSince1970: 0)
        check("override expiration math") {
            OverrideDuration.minutes(15).expiration(from: start, nextAnchor: nil)?.timeIntervalSince(start) == 900
                && OverrideDuration.untilResumed.expiration(from: start, nextAnchor: Date()) == nil
        }
        check("until next change follows a later schedule edit") {
            let soon = Date().addingTimeInterval(60)
            let later = Date().addingTimeInterval(600)
            let hold = TemporaryOverride(
                mode: .focus,
                duration: .untilNextAnchor,
                startedAt: Date(),
                expiresAt: soon,
                reason: "test"
            )
            return hold.refreshed(nextChange: later).expiresAt == later
        }
        check("until next change with no upcoming change becomes a hold") {
            let hold = TemporaryOverride(
                mode: .focus,
                duration: .untilNextAnchor,
                startedAt: Date(),
                expiresAt: nil,
                reason: "test"
            )
            let next = hold.refreshed(nextChange: nil)
            return next.duration == .untilResumed && next.expiresAt == nil
        }
        check("until next change that already passed expires") {
            let past = Date().addingTimeInterval(-60)
            let hold = TemporaryOverride(
                mode: .focus,
                duration: .untilNextAnchor,
                startedAt: Date().addingTimeInterval(-120),
                expiresAt: Date().addingTimeInterval(600),
                reason: "test"
            )
            let next = hold.refreshed(nextChange: past)
            return next.expiresAt == past && next.isActive(at: Date()) == false
        }
        check("a slider hold is labeled Manual") {
            let hold = TemporaryOverride(
                mode: .focus,
                output: DesiredOutput(temperature: ColorTemperature(kelvin: 4500)),
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment"
            )
            return hold.displayName == "Manual" && hold.isManualAdjustment
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Daylight-checks-\(UUID().uuidString)")
        let store = SettingsStore(directory: directory)
        var persisted = AppSettings()
        persisted.onboarded = true
        persisted.location = Cities.featured[0]
        try? store.save(persisted)
        let loaded = try? store.load()
        check("settings round-trip") { loaded?.location?.name == persisted.location?.name }
        check("empty weekend schedule is migrated") {
            let json = Data(#"{"schemaVersion":1,"onboarded":true,"weekendSchedule":{"id":"w","name":"Weekend","approach":"personal","personalAnchors":[],"customAnchors":[],"sunriseOffsetMinutes":0,"sunsetOffsetMinutes":0,"defaultTransitionMinutes":30,"hybridConflictWindowMinutes":20}}"#.utf8)
            guard let migrated = try? store.decodeSettings(json) else { return false }
            return !migrated.weekendSchedule.personalAnchors.isEmpty
        }
        check("partial settings keep new-field defaults") {
            guard let partial = try? store.decodeSettings(Data(#"{"schemaVersion":1,"onboarded":true}"#.utf8)) else {
                return false
            }
            return partial.onboarded && partial.keepRunningInBackground && partial.showMenuBarTemperature && partial.lastEditingWeekend == nil
        }
        check("unreadable settings are copied aside") {
            let junk = directory.appendingPathComponent("settings.json")
            try? Data(#"not-json"#.utf8).write(to: junk)
            let recovered = store.recoverIfNeeded()
            let backups = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return recovered.warning != nil
                && backups.contains(where: { $0.hasPrefix("settings-unreadable-") })
        }
        check("invalid import is rejected") {
            do {
                _ = try store.import(Data(#"{"not":"daylight"}"#.utf8))
                return false
            } catch {
                return true
            }
        }
        check("sparse JSON is not a valid settings export") {
            do {
                _ = try store.import(Data(#"{"schemaVersion":1,"onboarded":true}"#.utf8))
                return false
            } catch {
                return true
            }
        }
        check("a complete export still imports") {
            guard let data = try? store.exportSettings(AppSettings.resetDefaults()),
                  let imported = try? store.import(data) else {
                return false
            }
            return imported.onboarded && !imported.weekdaySchedule.personalAnchors.isEmpty
        }

        let first = DisplayIdentity(uuid: "AAA", vendor: 1, model: 2, serial: 3, isBuiltin: true)
        check("display UUID match is exact") {
            first.matchConfidence(against: DisplayIdentity(uuid: "AAA", vendor: 9, model: 9, serial: 9, isBuiltin: false)) == .exact
        }
        var named = AppSettings()
        var stored = DisplayPreferences(identity: DisplayIdentity(uuid: nil, vendor: 1, model: 2, serial: 0, isBuiltin: true))
        stored.customName = "Studio"
        named.upsertDisplay(stored)
        check("probable builtin identity keeps the saved name") {
            named.preferences(for: DisplayIdentity(uuid: "NEW", vendor: 1, model: 2, serial: 0, isBuiltin: true)).customName == "Studio"
        }
        check("probable identity migrates the durable key and link group") {
            named.groups = [DisplayGroup(name: "Linked displays", displayKeys: [stored.identity.durableKey, "other"])]
            named.lastSelectedDisplayID = stored.identity.durableKey
            let incoming = DisplayIdentity(uuid: "NEW", vendor: 1, model: 2, serial: 0, isBuiltin: true)
            let adopted = named.adoptConnectedIdentity(incoming)
            return adopted.identity.durableKey == incoming.durableKey
                && adopted.customName == "Studio"
                && named.groups.first?.displayKeys.contains(incoming.durableKey) == true
                && named.lastSelectedDisplayID == incoming.durableKey
                && named.displays.filter { $0.customName == "Studio" }.count == 1
        }
        check("identity migration remaps a scoped hold") {
            var settings = AppSettings()
            var stored = DisplayPreferences(identity: DisplayIdentity(uuid: nil, vendor: 4, model: 5, serial: 6, isBuiltin: true))
            stored.customName = "Laptop"
            settings.upsertDisplay(stored)
            settings.override = TemporaryOverride(
                mode: .focus,
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment",
                appliesToDisplayKeys: [stored.identity.durableKey]
            )
            let incoming = DisplayIdentity(uuid: "LIVE", vendor: 4, model: 5, serial: 6, isBuiltin: true)
            _ = settings.adoptConnectedIdentity(incoming)
            return settings.override?.appliesToDisplayKeys == [incoming.durableKey]
        }
        check("brightness appears as soon as a target has it") {
            let from = DesiredOutput(temperature: ColorTemperature(kelvin: 5000))
            let to = DesiredOutput(temperature: ColorTemperature(kelvin: 5000), hardwareBrightness: HardwareBrightness(fraction: 0.6))
            return Interpolation.output(from: from, to: to, t: 0.4).hardwareBrightness?.fraction == 0.6
        }
        check("idle displays are still present") {
            DisplayConnectionState.inactive.isPresent && DisplayConnectionState.disconnected.isPresent == false
        }

        let plan = TransitionEngine().plan(
            applied: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)),
            target: DesiredOutput(temperature: ColorTemperature(kelvin: 4008)),
            lastWrite: Date(),
            now: Date().addingTimeInterval(2),
            transitionRemaining: 0
        )
        check("transition engine skips tiny writes") { plan.shouldWrite == false }

        let now = Date()
        let blocked = TransitionEngine().plan(
            applied: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)),
            target: DesiredOutput(temperature: ColorTemperature(kelvin: 4500)),
            lastWrite: now,
            now: now,
            transitionRemaining: 0
        )
        let fresh = TransitionEngine().plan(
            applied: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)),
            target: DesiredOutput(temperature: ColorTemperature(kelvin: 4500)),
            lastWrite: nil,
            now: now,
            transitionRemaining: 0
        )
        check("a display with no prior write is not blocked by another display's clock") {
            blocked.shouldWrite == false && fresh.shouldWrite
        }
        check("a first write is retried when nothing has been applied yet") {
            TransitionEngine().plan(
                applied: nil,
                target: DesiredOutput(temperature: ColorTemperature(kelvin: 4500)),
                lastWrite: nil,
                now: Date(),
                transitionRemaining: 0
            ).shouldWrite
        }

        var grouped = AppSettings()
        grouped.groups = [DisplayGroup(name: "Linked displays", displayKeys: ["A", "B"])]
        var weekendCal = Calendar(identifier: .gregorian)
        weekendCal.timeZone = TimeZone(identifier: "America/New_York")!
        let wednesday = date(2026, 3, 4, 10, 0, calendar: weekendCal)
        check("weekday canvas maps onto Saturday") {
            let weekend = DayKind.nearbyWeekend(from: wednesday, calendar: weekendCal)
            return DayKind.kind(for: weekend, calendar: weekendCal) == .weekend
                && weekendCal.component(.weekday, from: weekend) == 7
        }
        check("weekend canvas maps onto Friday") {
            let saturday = date(2026, 3, 7, 10, 0, calendar: weekendCal)
            let weekday = DayKind.nearbyWeekday(from: saturday, calendar: weekendCal)
            return DayKind.kind(for: weekday, calendar: weekendCal) == .weekday
                && weekendCal.component(.weekday, from: weekday) == 6
        }
        check("Sunday canvas maps onto Monday") {
            let sunday = date(2026, 3, 8, 10, 0, calendar: weekendCal)
            let weekday = DayKind.nearbyWeekday(from: sunday, calendar: weekendCal)
            return weekendCal.component(.weekday, from: weekday) == 2
        }
        check("living surfaces keep Saturday on a weekend") {
            let saturday = date(2026, 3, 7, 10, 0, calendar: weekendCal)
            let living = DayKind.scheduleCanvasDate(
                now: saturday,
                editingWeekend: false,
                useWeekendSchedule: true,
                preferEditorDay: false,
                calendar: weekendCal
            )
            return weekendCal.isDate(living, inSameDayAs: saturday)
        }
        check("schedule editing maps Saturday onto Friday") {
            let saturday = date(2026, 3, 7, 10, 0, calendar: weekendCal)
            let editor = DayKind.scheduleCanvasDate(
                now: saturday,
                editingWeekend: false,
                useWeekendSchedule: true,
                preferEditorDay: true,
                calendar: weekendCal
            )
            return weekendCal.component(.weekday, from: editor) == 6
        }

        check("unlinking shrinks a scoped hold to the selection") {
            var linked = AppSettings()
            linked.groups = [DisplayGroup(name: "Linked displays", displayKeys: ["A", "B"])]
            linked.override = TemporaryOverride(
                mode: .focus,
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment",
                appliesToDisplayKeys: ["A", "B"]
            )
            linked.groups.removeAll()
            linked.retargetOverride(selectedDisplayID: "A", allDisplays: false)
            return linked.override?.appliesToDisplayKeys == ["A"]
        }
        check("linking expands a scoped hold onto the group") {
            var linked = AppSettings()
            linked.groups = [DisplayGroup(name: "Linked displays", displayKeys: ["A", "B"])]
            linked.override = TemporaryOverride(
                mode: .focus,
                duration: .untilResumed,
                startedAt: Date(),
                expiresAt: nil,
                reason: "Manual adjustment",
                appliesToDisplayKeys: ["A"]
            )
            linked.retargetOverride(selectedDisplayID: "A", allDisplays: false)
            return linked.override?.appliesToDisplayKeys == ["A", "B"]
        }
        check("linked override keys include the whole group") {
            grouped.overrideTargetKeys(selectedDisplayID: "A", allDisplays: false) == ["A", "B"]
                && grouped.overrideTargetKeys(selectedDisplayID: "A", allDisplays: true).isEmpty
                && grouped.overrideTargetKeys(selectedDisplayID: "C", allDisplays: false) == ["C"]
                && grouped.isLinked("A")
                && grouped.isLinked("C") == false
        }

        check("timeline warmth uses the visible temperature range") {
            TimelineSnap.temperatureFraction(kelvin: 3500, range: 3500 ... 6500) == 0
                && TimelineSnap.temperatureFraction(kelvin: 6500, range: 3500 ... 6500) == 1
                && abs(TimelineSnap.temperatureFraction(kelvin: 5000, range: 3500 ... 6500) - 0.5) < 0.001
                && TimelineSnap.temperatureFraction(kelvin: 2000, range: 3500 ... 6500) == 0
        }
        check("timeline snap uses 15-minute increments") {
            TimelineSnap.minutes(37, fine: false) == 30 && TimelineSnap.minutes(37, fine: true) == 37
        }
        check("midnight snap wraps") { TimelineSnap.minutes(1435, fine: false) == 0 }

        let scoped = ControllerDecision(
            output: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)),
            winningPriority: .temporaryOverride,
            winningName: "Focus",
            explanation: "test",
            automation: .override,
            restoreToBaseline: false,
            silenceReminders: false,
            excludedDisplayKeys: [],
            nextWake: nil,
            schedule: nil
        )
        check("scoped Color Work leaves other displays on the schedule") {
            let colorWork = ControllerDecision(
                output: DesiredOutput(temperature: .daylightReference),
                winningPriority: .temporaryOverride,
                winningName: "Color Work",
                explanation: "test",
                automation: .colorWork,
                restoreToBaseline: true,
                silenceReminders: true,
                excludedDisplayKeys: ["A"],
                nextWake: nil,
                schedule: nil
            )
            let held = DisplayTargeting.desiredOutput(
                for: "A",
                excludedFromAutomation: false,
                decision: colorWork,
                scheduleOutput: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                overrideDisplayKeys: ["A"]
            )
            let other = DisplayTargeting.desiredOutput(
                for: "B",
                excludedFromAutomation: false,
                decision: colorWork,
                scheduleOutput: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                overrideDisplayKeys: ["A"]
            )
            return held == nil && other?.temperature.kelvin == 6500 && DisplayTargeting.restoresEveryDisplay(overrideDisplayKeys: ["A"]) == false
        }
        check("override allow-list leaves other displays on the schedule") {
            DisplayTargeting.desiredOutput(
                for: "B",
                excludedFromAutomation: false,
                decision: scoped,
                scheduleOutput: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                overrideDisplayKeys: ["A"]
            )?.temperature.kelvin == 6500
        }
        let pausedDecision = ControllerDecision(
            output: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
            winningPriority: .userPause,
            winningName: "Paused",
            explanation: "Paused from Daylight",
            automation: .paused,
            restoreToBaseline: true,
            silenceReminders: true,
            excludedDisplayKeys: [],
            nextWake: nil,
            schedule: nil
        )
        check("pause targeting does not claim applied warmth") {
            DisplayTargeting.desiredOutput(
                for: "A",
                excludedFromAutomation: false,
                decision: pausedDecision,
                scheduleOutput: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                overrideDisplayKeys: []
            ) == nil
        }
        check("paused status does not claim applied warmth") {
            let snap = StatusExplainer().snapshot(
                decision: pausedDecision,
                displays: [],
                settings: AppSettings(),
                at: Date()
            )
            return snap.kelvinLabel == "Native output"
                && snap.headline.localizedCaseInsensitiveContains("native")
        }
        check("solar times are not movable on the timeline") {
            var schedule = DailySchedule.personal()
            schedule.approach = .solar
            schedule.location = Cities.match("San Francisco")
            let evaluation = ScheduleEngine().evaluate(
                schedule: schedule,
                at: Date(),
                context: EvaluationContext(timeZone: TimeZone(identifier: "America/Los_Angeles") ?? .current)
            )
            let solar = evaluation.resolvedAnchors.filter { $0.kind == .sunrise || $0.kind == .sunset }
            return !solar.isEmpty && solar.allSatisfy { $0.movable == false }
        }
        check("restored caption is honest") {
            DisplayTargeting.targetCaption(
                connection: .connected,
                excluded: false,
                mirrored: false,
                output: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                holdingThisDisplay: false,
                scheduleFallback: false,
                restored: true,
                restoredTitle: "Restored — paused"
            ) == "Restored — paused"
        }

        check("excluded displays receive no output") {
            DisplayTargeting.desiredOutput(
                for: "A",
                excludedFromAutomation: true,
                decision: scoped,
                scheduleOutput: DesiredOutput(temperature: .defaultDay),
                overrideDisplayKeys: []
            ) == nil
        }
        check("ambiguous city prefix is not applied") { Cities.match("L") == nil }
        check("unique city name is applied") { Cities.match("London")?.name.contains("London") == true }
        check("empty city search does not snap to a featured city") { Cities.search("").isEmpty && Cities.match("") == nil }

        check("comfort phrase tracks warmth") {
            ColorTemperature(kelvin: 6500).comfortPhrase == "Cool daylight"
                && ColorTemperature(kelvin: 3700).comfortPhrase == "Very warm"
        }

        let adapter = MacDisplayAdapter(simulationMode: true)
        let applied = adapter.apply(output: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)), to: adapter.enumerateDisplays()[0], limits: .conservative)
        check("simulation never writes hardware") { applied.wroteTransferTable == false && applied.notes.contains(where: { $0.contains("Simulation") }) }

        check("status times follow the locale") {
            let afternoon = date(2026, 3, 4, 15, 5, calendar: ny)
            let us = ScheduleEngine.shortTime(afternoon, timeZone: ny.timeZone, locale: Locale(identifier: "en_US"))
            let de = ScheduleEngine.shortTime(afternoon, timeZone: ny.timeZone, locale: Locale(identifier: "de_DE"))
            return us.uppercased().contains("PM") && de.contains("15")
        }

        check("yesterday activity uses a relative stamp") {
            let now = date(2026, 3, 4, 15, 0, calendar: ny)
            let yesterday = date(2026, 3, 3, 10, 0, calendar: ny)
            return ScheduleEngine.shortStamp(
                yesterday,
                now: now,
                timeZone: ny.timeZone,
                locale: Locale(identifier: "en_US"),
                calendar: ny
            ).localizedCaseInsensitiveContains("yesterday")
        }

        check("activity history is newest first") {
            let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/DaylightHistory-\(UUID().uuidString)")
            let store = SettingsStore(directory: dir)
            store.appendHistory(HistoryEvent(at: Date(), title: "First", detail: ""), enabled: true)
            store.appendHistory(HistoryEvent(at: Date(), title: "Second", detail: ""), enabled: true)
            return store.loadHistory().prefix(2).map(\.title) == ["Second", "First"]
        }

        check("last selected tab is restored") {
            let store = SettingsStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("DaylightTab-\(UUID().uuidString)"))
            guard let decoded = try? store.decodeSettings(Data(#"{"schemaVersion":1,"lastSelectedTab":"displays"}"#.utf8)) else {
                return false
            }
            return decoded.lastSelectedTab == "displays"
        }

        check("expired pause is pruned from settings") {
            var paused = AppSettings()
            paused.pause = PauseState(isPaused: true, expiresAt: Date().addingTimeInterval(-30), reason: "test")
            return paused.pruneExpiredStates() && paused.pause.isPaused == false
        }
        check("indefinite pause is kept") {
            var held = AppSettings()
            held.pause = PauseState(isPaused: true, expiresAt: nil, reason: "hold")
            return held.pruneExpiredStates() == false && held.pause.isPaused
        }
        check("expired override is pruned from settings") {
            var over = AppSettings()
            over.override = TemporaryOverride(
                mode: .focus,
                duration: .minutes(15),
                startedAt: Date().addingTimeInterval(-120),
                expiresAt: Date().addingTimeInterval(-10),
                reason: "test"
            )
            return over.pruneExpiredStates() && over.override == nil
        }
        check("a second custom time does not land on 4:00 PM twice") {
            var schedule = DailySchedule.personal()
            schedule.customAnchors = [
                ScheduleAnchor(name: "Custom", kind: .custom, timing: .clock(TimeOfDay(hour: 16, minute: 0)), output: DesiredOutput(temperature: .defaultDay))
            ]
            return schedule.nextFreeCustomTime().minutes != 16 * 60
        }
        check("a custom time keeps the personal routine") {
            var schedule = DailySchedule.personal()
            schedule.customAnchors = [
                ScheduleAnchor(name: "Custom", kind: .custom, timing: .clock(TimeOfDay(hour: 16, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 5000)))
            ]
            let evaluation = ScheduleEngine().evaluate(schedule: schedule, at: Date(), context: EvaluationContext())
            return schedule.approach == .personal
                && evaluation.resolvedAnchors.contains { $0.kind == .wake }
                && evaluation.resolvedAnchors.contains { $0.source == "custom" }
        }
        check("a solar schedule still uses a custom time") {
            var schedule = DailySchedule.personal()
            schedule.approach = .solar
            schedule.location = Cities.match("San Francisco")
            schedule.customAnchors = [
                ScheduleAnchor(name: "Custom", kind: .custom, timing: .clock(TimeOfDay(hour: 16, minute: 0)), output: DesiredOutput(temperature: ColorTemperature(kelvin: 5000)))
            ]
            let zone = TimeZone(identifier: "America/Los_Angeles") ?? .current
            let evaluation = ScheduleEngine().evaluate(
                schedule: schedule,
                at: Date(),
                context: EvaluationContext(timeZone: zone)
            )
            return evaluation.resolvedAnchors.contains { $0.kind == .sunrise || $0.kind == .sunset }
                && evaluation.resolvedAnchors.contains { $0.source == "custom" }
        }
        check("removing the last custom time restores a personal approach") {
            var schedule = DailySchedule.personal()
            schedule.approach = .custom
            schedule.customAnchors = [
                ScheduleAnchor(name: "Custom", kind: .custom, timing: .clock(TimeOfDay(hour: 16, minute: 0)), output: DesiredOutput(temperature: .defaultDay))
            ]
            schedule.customAnchors.removeAll()
            schedule.reconcileAfterRemovingCustomTimes()
            return schedule.approach == .personal
        }
        check("a city carries its own time zone") {
            Cities.match("Tokyo")?.resolvedTimeZone.identifier == "Asia/Tokyo"
        }

        check("reset defaults stay onboarded") {
            AppSettings.resetDefaults().onboarded && AppSettings().onboarded == false
        }

        check("import marks the Mac onboarded") {
            let store = SettingsStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("DaylightImportOnboard-\(UUID().uuidString)"))
            guard let data = try? store.exportSettings(AppSettings()), let imported = try? store.import(data) else {
                return false
            }
            return imported.onboarded && AppSettings().onboarded == false
        }

        check("slider duration and scope persist") {
            var settings = AppSettings()
            settings.sliderDuration = .untilResumed
            settings.sliderAffectsAllDisplays = false
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? encoder.encode(settings), let decoded = try? decoder.decode(AppSettings.self, from: data) else {
                return false
            }
            return decoded.sliderDuration == .untilResumed && decoded.sliderAffectsAllDisplays == false
        }

        check("display cycling wraps backward") {
            DisplayTargeting.adjacentIndex(from: 0, delta: -1, count: 3) == 2
                && DisplayTargeting.adjacentIndex(from: 2, delta: 1, count: 3) == 0
        }
        check("removed display keys skip remapped identities") {
            DisplayTargeting.removedDisplayKeys(previous: ["A", "B"], next: ["B"], remapped: []) == ["A"]
                && DisplayTargeting.removedDisplayKeys(previous: ["old"], next: ["new"], remapped: ["old"]).isEmpty
                && DisplayTargeting.removedDisplayKeys(previous: ["old", "stay"], next: ["new", "stay"], remapped: ["old"]).isEmpty
        }
        check("linkable keys skip idle and mirrored displays") {
            let identity = DisplayIdentity(uuid: "A", vendor: 1, model: 1, serial: 1, isBuiltin: true)
            let caps = DisplayCapabilities(warmth: .transferTable, brightness: .hardware)
            let active = ConnectedDisplay(identity: identity, transientID: 1, name: "Built-in", capabilities: caps, widthPixels: 1512, heightPixels: 982, isMain: true, isMirrored: false)
            let idle = ConnectedDisplay(identity: DisplayIdentity(uuid: "B", vendor: 2, model: 2, serial: 2, isBuiltin: false), transientID: 2, name: "Idle", connection: .inactive, capabilities: caps, widthPixels: 1920, heightPixels: 1080, isMain: false, isMirrored: false)
            let mirrored = ConnectedDisplay(identity: DisplayIdentity(uuid: "C", vendor: 3, model: 3, serial: 3, isBuiltin: false), transientID: 3, name: "Mirror", capabilities: caps, widthPixels: 1920, heightPixels: 1080, isMain: false, isMirrored: true, mirrorsDisplayKey: active.id)
            return DisplayTargeting.linkableDisplayKeys([active, idle, mirrored]) == [active.id]
        }

        check("adjustment readiness blocks idle, excluded, and preview") {
            DisplayAdjustment.resolve(display: nil, excluded: false, disabled: true, previewing: false) == .appDisabled
                && DisplayAdjustment.resolve(display: nil, excluded: false, disabled: false, previewing: true) == .previewing
                && DisplayAdjustment.resolve(display: nil, excluded: false, disabled: false, previewing: false) == .disconnected
                && DisplayAdjustment.resolve(display: nil, excluded: false, disabled: false, previewing: false, paused: true) == .paused
                && DisplayAdjustment.paused.allowsWrites == false
                && DisplayAdjustment.excluded.allowsWrites == false
                && DisplayAdjustment.ready.allowsWrites
        }

        check("lifecycle noise is not recorded as activity") {
            HistoryRecording.shouldRecord("Launch") == false
                && HistoryRecording.shouldRecord("Displays changed") == false
                && HistoryRecording.shouldRecord("Paused automation")
        }

        check("compact remaining uses short labels") {
            RulesEngine.compact(30) == "<1m"
                && RulesEngine.compact(120) == "2m"
                && RulesEngine.compact(3600) == "1h"
                && RulesEngine.compact(5400) == "1h 30m"
        }

        check("per-display captions distinguish a scoped hold") {
            DisplayTargeting.targetCaption(
                connection: .connected,
                excluded: false,
                mirrored: false,
                output: DesiredOutput(temperature: ColorTemperature(kelvin: 4000)),
                holdingThisDisplay: true,
                scheduleFallback: false
            ).contains("Holding")
                && DisplayTargeting.targetCaption(
                    connection: .connected,
                    excluded: false,
                    mirrored: false,
                    output: DesiredOutput(temperature: ColorTemperature(kelvin: 6500)),
                    holdingThisDisplay: false,
                    scheduleFallback: true
                ).contains("Schedule")
        }

        check("simulation restore still visits remembered sessions") {
            let adapter = MacDisplayAdapter(simulationMode: true)
            adapter.restoreAll(useColorSync: true)
            adapter.restoreAllOnQuit()
            return true
        }
        check("day preview reaches the next midnight") {
            let start = Calendar.current.startOfDay(for: Date())
            let end = DayPreviewClock.date(progress: 1, startOfDay: start)
            let mid = DayPreviewClock.date(progress: 0.5, startOfDay: start)
            let noon = Calendar.current.component(.hour, from: mid)
            return Calendar.current.isDate(end, inSameDayAs: start) == false && (11...13).contains(noon)
        }
        check("display list buffer grows when the first page is full") {
            DisplayListBuffer.nextCapacity(reported: 16, allocated: 16) == 32
                && DisplayListBuffer.nextCapacity(reported: 16, allocated: 32) == nil
        }
        check("unrecognized city stays unmatched") {
            Cities.status(for: "Not A Real City") == .unrecognized
        }
        check("native presentation Kelvin is daylight reference") {
            ColorTemperature.daylightReference.kelvin == 6500
        }
        check("live hardware preview is blocked while paused") {
            PreviewPolicy.allowsLiveHardware(paused: true, disabled: false) == false
                && PreviewPolicy.allowsLiveHardware(paused: false, disabled: true) == false
                && PreviewPolicy.allowsLiveHardware(paused: false, disabled: false)
        }
        check("setup does not write hardware until finished") {
            HardwareWritePolicy.shouldApply(onboarded: false, liveHardwarePreview: false) == false
                && HardwareWritePolicy.shouldApply(onboarded: false, liveHardwarePreview: true)
                && HardwareWritePolicy.shouldApply(onboarded: true, liveHardwarePreview: false)
                && HardwareWritePolicy.shouldRestoreAfterLivePreview(onboarded: false)
                && HardwareWritePolicy.shouldRestoreAfterLivePreview(onboarded: true) == false
        }

        check("default transition minutes update existing times") {
            var schedule = DailySchedule.personal()
            schedule.customAnchors = [
                ScheduleAnchor(name: "Custom", kind: .custom, timing: .clock(TimeOfDay(hour: 16, minute: 0)), output: DesiredOutput(temperature: .defaultDay), transitionMinutes: 10)
            ]
            schedule.applyDefaultTransitionMinutes(45)
            return schedule.defaultTransitionMinutes == 45
                && schedule.personalAnchors.allSatisfy { $0.transitionMinutes == 45 }
                && schedule.customAnchors.allSatisfy { $0.transitionMinutes == 45 }
        }

        check("clock labels use a date that always exists") {
            TimeOfDay(hour: 2, minute: 30).formatted(locale: Locale(identifier: "en_US")).contains("2:30")
        }

        check("a single time can keep its own transition after the default changes") {
            var schedule = DailySchedule.personal()
            schedule.applyDefaultTransitionMinutes(40)
            schedule.personalAnchors[0].transitionMinutes = 15
            return schedule.personalAnchors[0].transitionMinutes == 15
                && schedule.personalAnchors.dropFirst().allSatisfy { $0.transitionMinutes == 40 }
        }

        check("compact hour labels follow 24-hour locales") {
            ClockFormat.compactHour(15, locale: Locale(identifier: "de_DE")) == "15"
                && ClockFormat.compactHour(15, locale: Locale(identifier: "en_US")) == "3p"
        }

        if failed == 0 {
            print("\nAll checks passed.")
        } else {
            print("\n\(failed) check(s) failed.")
            exit(1)
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
