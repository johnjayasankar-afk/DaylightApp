import Foundation

/// Software dimming multiplies the transfer table. It is not backlight control,
/// does not reduce panel power in a measured way, and is not equivalent to hardware brightness.
public struct SoftwareDimming: Hashable, Sendable, Codable {
    /// 1.0 leaves the transfer table undimmed. 0.35 is a conservative floor for readability.
    public var factor: Double

    public static let none = SoftwareDimming(factor: 1)
    public static let readableRange = 0.35 ... 1.0

    public init(factor: Double) {
        self.factor = factor
    }

    public var isActive: Bool { factor < 0.999 }
    public var percent: Int { Int((factor * 100).rounded()) }

    public func clamped() -> SoftwareDimming {
        SoftwareDimming(factor: min(max(factor, Self.readableRange.lowerBound), Self.readableRange.upperBound))
    }
}

/// Hardware brightness is a backlight (or equivalent) fraction where the platform supports it.
public struct HardwareBrightness: Hashable, Sendable, Codable {
    public var fraction: Double

    public static let readableRange = 0.08 ... 1.0

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var percent: Int { Int((fraction * 100).rounded()) }

    public func clamped(minimum: Double = readableRange.lowerBound) -> HardwareBrightness {
        let lower = min(max(minimum, Self.readableRange.lowerBound), Self.readableRange.upperBound)
        return HardwareBrightness(fraction: min(max(fraction, lower), Self.readableRange.upperBound))
    }
}

public struct DesiredOutput: Hashable, Sendable, Codable {
    public var temperature: ColorTemperature
    public var hardwareBrightness: HardwareBrightness?
    public var softwareDimming: SoftwareDimming

    public init(
        temperature: ColorTemperature,
        hardwareBrightness: HardwareBrightness? = nil,
        softwareDimming: SoftwareDimming = .none
    ) {
        self.temperature = temperature
        self.hardwareBrightness = hardwareBrightness
        self.softwareDimming = softwareDimming
    }

    public var channelScale: ChannelScale {
        TemperatureAppearance.channelScale(for: temperature)
            .scaled(by: softwareDimming.factor)
    }

    public func applying(limits: DisplayLimits) -> DesiredOutput {
        var next = self
        next.temperature = temperature.clamped(to: limits.temperatureRange)
        if let brightness = hardwareBrightness {
            next.hardwareBrightness = brightness.clamped(minimum: limits.minimumHardwareBrightness)
        }
        next.softwareDimming = softwareDimming.clamped()
        if next.softwareDimming.factor < limits.minimumSoftwareDim {
            next.softwareDimming = SoftwareDimming(factor: limits.minimumSoftwareDim)
        }
        return next
    }
}

public struct AppliedOutput: Hashable, Sendable, Codable {
    public var requested: DesiredOutput
    public var acceptedTemperature: Bool
    public var acceptedHardwareBrightness: Bool
    public var acceptedSoftwareDimming: Bool
    public var readbackTemperatureHint: ColorTemperature?
    public var readbackHardwareBrightness: HardwareBrightness?
    public var wroteTransferTable: Bool
    public var at: Date
    public var notes: [String]

    public init(
        requested: DesiredOutput,
        acceptedTemperature: Bool,
        acceptedHardwareBrightness: Bool,
        acceptedSoftwareDimming: Bool,
        readbackTemperatureHint: ColorTemperature? = nil,
        readbackHardwareBrightness: HardwareBrightness? = nil,
        wroteTransferTable: Bool,
        at: Date,
        notes: [String] = []
    ) {
        self.requested = requested
        self.acceptedTemperature = acceptedTemperature
        self.acceptedHardwareBrightness = acceptedHardwareBrightness
        self.acceptedSoftwareDimming = acceptedSoftwareDimming
        self.readbackTemperatureHint = readbackTemperatureHint
        self.readbackHardwareBrightness = readbackHardwareBrightness
        self.wroteTransferTable = wroteTransferTable
        self.at = at
        self.notes = notes
    }
}

public struct DisplayLimits: Hashable, Sendable, Codable {
    public var temperatureRange: ClosedRange<Double>
    public var minimumHardwareBrightness: Double
    public var minimumSoftwareDim: Double
    public var allowAdvancedRange: Bool

    public static let conservative = DisplayLimits(
        temperatureRange: ColorTemperature.normalRange,
        minimumHardwareBrightness: 0.12,
        minimumSoftwareDim: 0.45,
        allowAdvancedRange: false
    )

    public init(
        temperatureRange: ClosedRange<Double>,
        minimumHardwareBrightness: Double,
        minimumSoftwareDim: Double,
        allowAdvancedRange: Bool
    ) {
        self.temperatureRange = temperatureRange
        self.minimumHardwareBrightness = minimumHardwareBrightness
        self.minimumSoftwareDim = minimumSoftwareDim
        self.allowAdvancedRange = allowAdvancedRange
    }

    public static func range(advanced: Bool) -> ClosedRange<Double> {
        advanced ? ColorTemperature.advancedRange : ColorTemperature.normalRange
    }
}

public enum ExtremeSettingRisk: String, Sendable {
    case veryWarm
    case veryDimHardware
    case veryDimSoftware

    public var message: String {
        switch self {
        case .veryWarm:
            return "This warmth setting can make text and colors harder to read."
        case .veryDimHardware:
            return "This brightness setting may make the display difficult to read."
        case .veryDimSoftware:
            return "Software dimming darkens the image. It does not reduce the backlight."
        }
    }
}

public enum Safety {
    public static func risks(for output: DesiredOutput) -> [ExtremeSettingRisk] {
        var risks: [ExtremeSettingRisk] = []
        if output.temperature.kelvin < 3200 {
            risks.append(.veryWarm)
        }
        if let brightness = output.hardwareBrightness, brightness.fraction < 0.18 {
            risks.append(.veryDimHardware)
        }
        if output.softwareDimming.factor < 0.55 {
            risks.append(.veryDimSoftware)
        }
        return risks
    }
}

/// Hardware writes stay off during setup unless the user starts an explicit live preview.
public enum HardwareWritePolicy: Sendable {
    public static func shouldApply(onboarded: Bool, liveHardwarePreview: Bool) -> Bool {
        onboarded || liveHardwarePreview
    }

    /// Ending a live preview during setup must restore tables, not apply the unfinished schedule.
    public static func shouldRestoreAfterLivePreview(onboarded: Bool) -> Bool {
        !onboarded
    }
}

/// Live hardware preview must not run while Daylight is paused or off.
public enum PreviewPolicy: Sendable {
    public static func allowsLiveHardware(paused: Bool, disabled: Bool) -> Bool {
        !paused && !disabled
    }
}
