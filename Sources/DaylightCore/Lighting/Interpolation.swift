import Foundation

public enum Interpolation {
    /// Reciprocal-temperature (mired) interpolation looks more evenly paced than linear Kelvin.
    public static func temperature(from: ColorTemperature, to: ColorTemperature, t: Double) -> ColorTemperature {
        let clamped = min(max(t, 0), 1)
        let mired = from.mireds + (to.mireds - from.mireds) * clamped
        return .fromMireds(mired)
    }

    public static func linear(_ from: Double, _ to: Double, t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return from + (to - from) * clamped
    }

    public static func output(from: DesiredOutput, to: DesiredOutput, t: Double) -> DesiredOutput {
        let temperature = temperature(from: from.temperature, to: to.temperature, t: t)
        let dim = SoftwareDimming(factor: linear(from.softwareDimming.factor, to.softwareDimming.factor, t: t))
        let brightness: HardwareBrightness?
        switch (from.hardwareBrightness, to.hardwareBrightness) {
        case let (origin?, destination?):
            brightness = HardwareBrightness(fraction: linear(origin.fraction, destination.fraction, t: t))
        case let (nil, destination?):
            brightness = destination
        case let (origin?, nil):
            brightness = t >= 1 ? nil : origin
        case (nil, nil):
            brightness = nil
        }
        return DesiredOutput(temperature: temperature, hardwareBrightness: brightness, softwareDimming: dim)
    }

    public static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }

    public static func temperatureDelta(_ a: ColorTemperature, _ b: ColorTemperature) -> Double {
        abs(a.kelvin - b.kelvin)
    }

    public static func isMaterialChange(
        from: DesiredOutput,
        to: DesiredOutput,
        temperatureThreshold: Double = 18,
        brightnessThreshold: Double = 0.006,
        dimThreshold: Double = 0.006
    ) -> Bool {
        if temperatureDelta(from.temperature, to.temperature) >= temperatureThreshold {
            return true
        }
        if abs(from.softwareDimming.factor - to.softwareDimming.factor) >= dimThreshold {
            return true
        }
        switch (from.hardwareBrightness, to.hardwareBrightness) {
        case let (a?, b?):
            return abs(a.fraction - b.fraction) >= brightnessThreshold
        case (nil, nil):
            return false
        default:
            return true
        }
    }
}
