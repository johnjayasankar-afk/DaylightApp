import Foundation

public struct TransferTable: Hashable, Sendable {
    public var red: [Double]
    public var green: [Double]
    public var blue: [Double]

    public init(red: [Double], green: [Double], blue: [Double]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var sampleCount: Int { min(red.count, green.count, blue.count) }

    public static func linear(count: Int) -> TransferTable {
        guard count > 1 else {
            return TransferTable(red: [0], green: [0], blue: [0])
        }
        let values = (0..<count).map { Double($0) / Double(count - 1) }
        return TransferTable(red: values, green: values, blue: values)
    }

    public func applying(_ scale: ChannelScale) -> TransferTable {
        TransferTable(
            red: red.map { min(max($0 * scale.red, 0), 1) },
            green: green.map { min(max($0 * scale.green, 0), 1) },
            blue: blue.map { min(max($0 * scale.blue, 0), 1) }
        )
    }

    public func mean() -> ChannelScale {
        func average(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
        return ChannelScale(red: average(red), green: average(green), blue: average(blue))
    }

    public func maxAbsoluteDelta(from other: TransferTable) -> Double {
        let count = min(sampleCount, other.sampleCount)
        guard count > 0 else { return 1 }
        var maxDelta = 0.0
        for index in 0..<count {
            maxDelta = max(maxDelta, abs(red[index] - other.red[index]))
            maxDelta = max(maxDelta, abs(green[index] - other.green[index]))
            maxDelta = max(maxDelta, abs(blue[index] - other.blue[index]))
        }
        return maxDelta
    }

    /// Estimate an approximate Kelvin target from channel means relative to a baseline.
    /// This is a hint from software tables, not a measurement of panel output.
    public func estimatedTemperature(
        baseline: TransferTable,
        reference: ColorTemperature = .daylightReference
    ) -> ColorTemperature? {
        let current = mean()
        let base = baseline.mean()
        let blueRatio = (current.blue / max(base.blue, 0.0001)) / max(current.red / max(base.red, 0.0001), 0.0001)
        if blueRatio > 0.98 && abs((current.green / max(base.green, 0.0001)) - 1) < 0.03 {
            return reference
        }
        var best = reference
        var bestError = Double.greatestFiniteMagnitude
        for kelvin in stride(from: 2700.0, through: 7000.0, by: 50) {
            let scale = TemperatureAppearance.channelScale(for: ColorTemperature(kelvin: kelvin), reference: reference)
            let error = abs(scale.blue / max(scale.red, 0.0001) - blueRatio)
            if error < bestError {
                bestError = error
                best = ColorTemperature(kelvin: kelvin)
            }
        }
        return best
    }
}

public protocol DisplayAdapter: Sendable {
    func enumerateDisplays() -> [ConnectedDisplay]
    func apply(output: DesiredOutput, to display: ConnectedDisplay, limits: DisplayLimits) -> AppliedOutput
    func restore(_ display: ConnectedDisplay) -> Bool
    func restoreAll() -> Bool
}

public struct SimulatedDisplayAdapter: DisplayAdapter {
    public var displays: [ConnectedDisplay]
    public var lastOutputs: [String: DesiredOutput]

    public init(displays: [ConnectedDisplay] = [Self.previewDisplay]) {
        self.displays = displays
        self.lastOutputs = [:]
    }

    public static let previewDisplay = ConnectedDisplay(
        identity: DisplayIdentity(uuid: "sim-builtin", vendor: 1, model: 1, serial: 1, isBuiltin: true, productName: "Simulated Display"),
        transientID: 1,
        name: "Simulated Display",
        capabilities: DisplayCapabilities(warmth: .simulated, brightness: .softwareDimming, notes: ["Simulation mode. Changes are not applied to hardware."]),
        widthPixels: 1920,
        heightPixels: 1080,
        isMain: true,
        isMirrored: false
    )

    public func enumerateDisplays() -> [ConnectedDisplay] {
        displays
    }

    public mutating func applyMutable(output: DesiredOutput, to display: ConnectedDisplay, limits: DisplayLimits) -> AppliedOutput {
        let limited = output.applying(limits: limits)
        lastOutputs[display.id] = limited
        return AppliedOutput(
            requested: limited,
            acceptedTemperature: true,
            acceptedHardwareBrightness: false,
            acceptedSoftwareDimming: true,
            readbackTemperatureHint: limited.temperature,
            wroteTransferTable: false,
            at: Date(),
            notes: ["Simulation accepted the request. No hardware was changed."]
        )
    }

    public func apply(output: DesiredOutput, to display: ConnectedDisplay, limits: DisplayLimits) -> AppliedOutput {
        let limited = output.applying(limits: limits)
        return AppliedOutput(
            requested: limited,
            acceptedTemperature: true,
            acceptedHardwareBrightness: display.capabilities.brightness == .hardware,
            acceptedSoftwareDimming: true,
            readbackTemperatureHint: limited.temperature,
            wroteTransferTable: false,
            at: Date(),
            notes: ["Simulation accepted the request. No hardware was changed."]
        )
    }

    public func restore(_ display: ConnectedDisplay) -> Bool { true }
    public func restoreAll() -> Bool { true }
}
