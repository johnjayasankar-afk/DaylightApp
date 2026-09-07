import Foundation

/// Approximate display color-temperature target in Kelvin.
/// This is a software target for the transfer table, not a measurement of emitted spectrum.
public struct ColorTemperature: Hashable, Sendable, Codable, Comparable {
    public var kelvin: Double

    public static let daylightReference = ColorTemperature(kelvin: 6500)
    public static let normalRange = 3500.0 ... 6500.0
    public static let advancedRange = 2700.0 ... 7000.0
    public static let defaultDay = ColorTemperature(kelvin: 6500)
    public static let defaultEvening = ColorTemperature(kelvin: 4200)
    public static let defaultNight = ColorTemperature(kelvin: 3700)

    public init(kelvin: Double) {
        self.kelvin = kelvin
    }

    public var mireds: Double {
        1_000_000.0 / max(kelvin, 1)
    }

    public static func fromMireds(_ mireds: Double) -> ColorTemperature {
        ColorTemperature(kelvin: 1_000_000.0 / max(mireds, 1))
    }

    public func clamped(to range: ClosedRange<Double>) -> ColorTemperature {
        ColorTemperature(kelvin: min(max(kelvin, range.lowerBound), range.upperBound))
    }

    public static func < (lhs: ColorTemperature, rhs: ColorTemperature) -> Bool {
        lhs.kelvin < rhs.kelvin
    }

    public var roundedLabel: String {
        "\(Int(kelvin.rounded())) K"
    }

    /// Plain-language band for the current target. Not a measurement of the room or the panel.
    public var comfortPhrase: String {
        switch kelvin {
        case 6000...: return "Cool daylight"
        case 5200..<6000: return "Neutral"
        case 4500..<5200: return "Soft white"
        case 3900..<4500: return "Warm"
        default: return "Very warm"
        }
    }
}

public struct ChannelScale: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public static let identity = ChannelScale(red: 1, green: 1, blue: 1)

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public func scaled(by factor: Double) -> ChannelScale {
        ChannelScale(red: red * factor, green: green * factor, blue: blue * factor)
    }

    public var isApproximatelyIdentity: Bool {
        abs(red - 1) < 0.004 && abs(green - 1) < 0.004 && abs(blue - 1) < 0.004
    }
}

/// Blackbody-inspired RGB multipliers used to shape a display transfer table.
/// These are approximate channel weights, not a spectral measurement.
public enum TemperatureAppearance {
    public static func channelScale(
        for temperature: ColorTemperature,
        reference: ColorTemperature = .daylightReference
    ) -> ChannelScale {
        let target = rgb(for: temperature.kelvin)
        let base = rgb(for: reference.kelvin)
        return ChannelScale(
            red: clamp(target.r / max(base.r, 0.0001)),
            green: clamp(target.g / max(base.g, 0.0001)),
            blue: clamp(target.b / max(base.b, 0.0001))
        )
    }

    /// Tanner Helland / blackbody approximation, normalized to 0...1.
    public static func rgb(for kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let temp = min(max(kelvin, 1000), 40_000) / 100.0

        let red: Double
        if temp <= 66 {
            red = 1
        } else {
            red = clamp((329.698727446 * pow(temp - 60, -0.1332047592)) / 255.0)
        }

        let green: Double
        if temp <= 66 {
            green = clamp((99.4708025861 * log(temp) - 161.1195681661) / 255.0)
        } else {
            green = clamp((288.1221695283 * pow(temp - 60, -0.0755148492)) / 255.0)
        }

        let blue: Double
        if temp >= 66 {
            blue = 1
        } else if temp <= 19 {
            blue = 0
        } else {
            blue = clamp((138.5177312231 * log(temp - 10) - 305.0447927307) / 255.0)
        }

        return (red, green, blue)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
