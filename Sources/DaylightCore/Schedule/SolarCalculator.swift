import Foundation

/// Approximate civil sunrise and sunset from coordinates (suncalc / Meeus-style).
/// These are calculated event times, not a measurement of local daylight quality.
public struct SolarCalculator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func day(
        on date: Date,
        location: LocationFix,
        timeZone: TimeZone
    ) -> SolarDay {
        var calendar = calendar
        calendar.timeZone = timeZone
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: date)) else {
            return SolarDay(sunrise: nil, sunset: nil, solarNoon: nil, polar: .normal, fallbackUsed: true, note: "Could not read the local date.")
        }

        let lw = -location.longitude * .pi / 180
        let phi = location.latitude * .pi / 180
        let days = toDays(start)
        let n = (days - 0.0009 - lw / (2 * .pi)).rounded()
        let approx = 0.0009 + lw / (2 * .pi) + n
        let mean = 357.5291 * .pi / 180 + 0.98560028 * .pi / 180 * approx
        let center = (1.9148 * sin(mean) + 0.02 * sin(2 * mean) + 0.0003 * sin(3 * mean)) * .pi / 180
        let lambda = mean + center + 102.9372 * .pi / 180 + .pi
        let declination = asin(sin(lambda) * sin(23.4397 * .pi / 180))
        let transitDays = approx + 0.0053 * sin(mean) - 0.0069 * sin(2 * lambda)
        let noon = fromJulian(2_451_545 + transitDays)

        let sinHorizon = sin(-0.833 * .pi / 180)
        let cosOmega = (sinHorizon - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        if cosOmega > 1 {
            return polarFallback(.polarNight, on: start, timeZone: timeZone)
        }
        if cosOmega < -1 {
            return polarFallback(.polarDay, on: start, timeZone: timeZone)
        }

        let omega = acos(min(max(cosOmega, -1), 1))
        let setApprox = 0.0009 + (omega + lw) / (2 * .pi) + n
        let setDays = setApprox + 0.0053 * sin(mean) - 0.0069 * sin(2 * lambda)
        let sunset = fromJulian(2_451_545 + setDays)
        let sunrise = Date(timeIntervalSince1970: noon.timeIntervalSince1970 - (sunset.timeIntervalSince1970 - noon.timeIntervalSince1970))
        return SolarDay(sunrise: sunrise, sunset: sunset, solarNoon: noon, polar: .normal, fallbackUsed: false)
    }

    private func polarFallback(_ polar: PolarSunState, on start: Date, timeZone: TimeZone) -> SolarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if polar == .polarDay {
            return SolarDay(
                sunrise: TimeOfDay(hour: 2, minute: 0).date(on: start, calendar: calendar),
                sunset: TimeOfDay(hour: 22, minute: 0).date(on: start, calendar: calendar),
                solarNoon: TimeOfDay(hour: 12, minute: 0).date(on: start, calendar: calendar),
                polar: .polarDay,
                fallbackUsed: true,
                note: "The sun does not set at this latitude today. Daylight uses a long-day placeholder so the schedule can still run."
            )
        }
        return SolarDay(
            sunrise: TimeOfDay(hour: 11, minute: 0).date(on: start, calendar: calendar),
            sunset: TimeOfDay(hour: 13, minute: 0).date(on: start, calendar: calendar),
            solarNoon: TimeOfDay(hour: 12, minute: 0).date(on: start, calendar: calendar),
            polar: .polarNight,
            fallbackUsed: true,
            note: "The sun does not rise at this latitude today. Daylight uses a short-day placeholder so the schedule can still run."
        )
    }

    private func toDays(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 0.5 + 2_440_588 - 2_451_545
    }

    private func fromJulian(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian + 0.5 - 2_440_588) * 86_400)
    }
}
