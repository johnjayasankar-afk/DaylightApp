import CoreGraphics
import DaylightCore
import Foundation

public struct ProbeReport: Sendable {
    public var environment: PlatformEnvironment
    public var displays: [ConnectedDisplay]
    public var results: [DisplayProbeResult]
    public var restored: Bool
}

public struct DisplayProbeResult: Sendable {
    public var display: ConnectedDisplay
    public var requested: DesiredOutput
    public var setError: Int32
    public var baselineMean: ChannelScale
    public var afterWriteMean: ChannelScale?
    public var afterRestoreMean: ChannelScale?
    public var readbackChanged: Bool
    public var restoredCloseToBaseline: Bool
    public var brightnessBefore: HardwareBrightness?
    public var brightnessSource: String?
    public var notes: [String]
}

public final class MacDisplayAdapter: @unchecked Sendable {
    public struct Session {
        public var display: ConnectedDisplay
        public var baseline: TransferTable
        public var lastWritten: TransferTable?
        public var baselineBrightness: HardwareBrightness?
        public var brightnessSource: String?
        public var lastOutput: DesiredOutput?
        public var lastWriteAt: Date?
        public var foreignChangeDetected: Bool
    }

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    public var simulationMode = false
    public var environment: PlatformEnvironment

    public init(environment: PlatformEnvironment = .current, simulationMode: Bool = false) {
        self.environment = environment
        self.simulationMode = simulationMode
    }

    public func enumerateDisplays() -> [ConnectedDisplay] {
        if simulationMode {
            return [SimulatedDisplayAdapter.previewDisplay]
        }
        return DisplayEnumerator.connectedDisplays(environment: environment)
    }

    public func session(for display: ConnectedDisplay) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[display.id]
    }

    @discardableResult
    public func ensureBaseline(for display: ConnectedDisplay) -> Session? {
        if simulationMode { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[display.id] {
            return existing
        }
        guard let table = TransferTableBridge.read(displayID: display.transientID) else {
            return nil
        }
        let brightness = BrightnessController.read(displayID: display.transientID, identity: display.identity)
        let session = Session(
            display: display,
            baseline: table,
            lastWritten: table,
            baselineBrightness: brightness?.value,
            brightnessSource: brightness?.source,
            lastOutput: nil,
            lastWriteAt: nil,
            foreignChangeDetected: false
        )
        sessions[display.id] = session
        return session
    }

    public func apply(
        output: DesiredOutput,
        to display: ConnectedDisplay,
        limits: DisplayLimits,
        now: Date = Date()
    ) -> AppliedOutput {
        let limited = output.applying(limits: limits)
        if simulationMode {
            return AppliedOutput(
                requested: limited,
                acceptedTemperature: true,
                acceptedHardwareBrightness: false,
                acceptedSoftwareDimming: true,
                readbackTemperatureHint: limited.temperature,
                wroteTransferTable: false,
                at: now,
                notes: ["Simulation mode is on. No hardware was changed."]
            )
        }

        guard var session = ensureBaseline(for: display) else {
            return AppliedOutput(
                requested: limited,
                acceptedTemperature: false,
                acceptedHardwareBrightness: false,
                acceptedSoftwareDimming: false,
                wroteTransferTable: false,
                at: now,
                notes: ["Could not read the current transfer table for this display."]
            )
        }

        var notes: [String] = []
        if let current = TransferTableBridge.read(displayID: display.transientID),
           let lastWritten = session.lastWritten,
           current.maxAbsoluteDelta(from: lastWritten) > 0.04 {
            session.foreignChangeDetected = true
            notes.append("Another display utility may be changing this setting. Daylight did not adopt that table as a new baseline.")
        }

        let targetTable = session.baseline.applying(limited.channelScale)
        let setError = TransferTableBridge.write(displayID: display.transientID, table: targetTable)
        let accepted = setError == .success
        var readbackHint: ColorTemperature?
        if accepted, let read = TransferTableBridge.read(displayID: display.transientID) {
            session.lastWritten = read
            readbackHint = read.estimatedTemperature(baseline: session.baseline)
            if read.maxAbsoluteDelta(from: targetTable) > 0.08 {
                notes.append("The operating system accepted the write, but readback does not match the requested table.")
            } else if read.maxAbsoluteDelta(from: session.baseline) < 0.01 && !limited.channelScale.isApproximatelyIdentity {
                notes.append("Readback is still close to the baseline. The panel may not have changed even though the API returned success.")
            }
        } else if !accepted {
            notes.append("The transfer-table write did not succeed (CGError \(setError.rawValue)).")
        }

        var acceptedBrightness = false
        var brightnessReadback: HardwareBrightness?
        if let brightness = limited.hardwareBrightness {
            let result = BrightnessController.write(
                displayID: display.transientID,
                identity: display.identity,
                value: brightness
            )
            acceptedBrightness = result.0
            notes.append(acceptedBrightness ? "Hardware brightness write used \(result.1)." : result.1)
            brightnessReadback = BrightnessController.read(displayID: display.transientID, identity: display.identity)?.value
        } else if session.lastOutput?.hardwareBrightness != nil, let baseline = session.baselineBrightness {
            let result = BrightnessController.write(
                displayID: display.transientID,
                identity: display.identity,
                value: baseline
            )
            acceptedBrightness = result.0
            if result.0 {
                notes.append("Restored the brightness captured before Daylight changed it.")
            }
            brightnessReadback = baseline
        }

        if accepted || acceptedBrightness {
            session.lastOutput = limited
            session.lastWriteAt = now
        }
        session.display = display
        lock.lock()
        sessions[display.id] = session
        lock.unlock()

        return AppliedOutput(
            requested: limited,
            acceptedTemperature: accepted,
            acceptedHardwareBrightness: acceptedBrightness,
            acceptedSoftwareDimming: accepted && limited.softwareDimming.isActive,
            readbackTemperatureHint: readbackHint,
            readbackHardwareBrightness: brightnessReadback,
            wroteTransferTable: accepted,
            at: now,
            notes: notes
        )
    }

    @discardableResult
    public func restoreRemembered(id: String) -> Bool {
        lock.lock()
        let display = sessions[id]?.display
        lock.unlock()
        guard let display else { return false }
        return restore(display)
    }

    @discardableResult
    public func restore(_ display: ConnectedDisplay) -> Bool {
        if simulationMode { return true }
        lock.lock()
        let session = sessions[display.id]
        lock.unlock()
        guard let session else {
            return false
        }
        let error = TransferTableBridge.write(displayID: display.transientID, table: session.baseline)
        if let brightness = session.baselineBrightness {
            _ = BrightnessController.write(displayID: display.transientID, identity: display.identity, value: brightness)
        }
        lock.lock()
        sessions[display.id]?.lastWritten = session.baseline
        sessions[display.id]?.lastOutput = nil
        lock.unlock()
        return error == .success
    }

    @discardableResult
    public func restoreAll(useColorSync: Bool = false) -> Bool {
        let wasSimulating = simulationMode
        simulationMode = false
        defer { simulationMode = wasSimulating }

        lock.lock()
        let known = Array(sessions.values.map(\.display))
        lock.unlock()
        var ok = true
        var seen = Set<String>()
        for display in known {
            seen.insert(display.id)
            if !restore(display) { ok = false }
        }
        if !wasSimulating {
            for display in enumerateDisplays() where !seen.contains(display.id) {
                if !restore(display) { ok = false }
            }
        }
        if useColorSync {
            TransferTableBridge.restoreColorSync()
            lock.lock()
            sessions.removeAll()
            lock.unlock()
            return true
        }
        return ok
    }

    /// Restores every remembered session, then ColorSync, so a disconnected display cannot stay warm after Quit.
    public func restoreAllOnQuit() {
        let wasSimulating = simulationMode
        simulationMode = false
        lock.lock()
        let known = Array(sessions.values.map(\.display))
        lock.unlock()
        for display in known {
            _ = restore(display)
        }
        TransferTableBridge.restoreColorSync()
        lock.lock()
        sessions.removeAll()
        lock.unlock()
        simulationMode = wasSimulating
    }

    public func probeRealDisplays() -> [ConnectedDisplay] {
        DisplayEnumerator.connectedDisplays(environment: environment)
    }

    /// Keeps the captured baseline when a display’s durable key changes (EDID → UUID).
    public func adoptSession(from oldKey: String, to newKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard oldKey != newKey, let session = sessions[oldKey] else { return }
        sessions[newKey] = session
        sessions[oldKey] = nil
    }

    public func forgetDisconnected(current: [ConnectedDisplay]) {
        // Keep baselines across dock/undock so a reconnect cannot stack warmth
        // on a newly captured table that still contains Daylight’s last write.
        lock.lock()
        for display in current {
            if var session = sessions[display.id] {
                session.display = display
                sessions[display.id] = session
            }
        }
        lock.unlock()
    }

    public func ownershipRecord(now: Date = Date()) -> OwnershipRecord {
        lock.lock()
        defer { lock.unlock() }
        let items = sessions.map { key, session in
            DisplayOwnership(
                displayKey: key,
                capturedBaseline: true,
                applyingTransform: session.lastOutput != nil,
                lastRequestedKelvin: session.lastOutput?.temperature.kelvin,
                lastWriteSucceeded: session.lastWritten != nil,
                notes: session.foreignChangeDetected ? ["Possible foreign transfer-table change"] : []
            )
        }
        return OwnershipRecord(updatedAt: now, displays: items)
    }

    public func probe(
        temperature: ColorTemperature = ColorTemperature(kelvin: 4200),
        hold: TimeInterval = 0,
        restoreAfter: Bool = true
    ) -> ProbeReport {
        let displays = enumerateDisplays()
        var results: [DisplayProbeResult] = []
        for display in displays where display.connection == .connected {
            results.append(probe(display: display, temperature: temperature, hold: hold, restoreAfter: restoreAfter))
        }
        return ProbeReport(
            environment: environment,
            displays: displays,
            results: results,
            restored: restoreAfter
        )
    }

    public func probe(
        display: ConnectedDisplay,
        temperature: ColorTemperature,
        hold: TimeInterval,
        restoreAfter: Bool
    ) -> DisplayProbeResult {
        var notes: [String] = display.capabilities.notes
        guard let baseline = TransferTableBridge.read(displayID: display.transientID) else {
            return DisplayProbeResult(
                display: display,
                requested: DesiredOutput(temperature: temperature),
                setError: -1,
                baselineMean: .identity,
                afterWriteMean: nil,
                afterRestoreMean: nil,
                readbackChanged: false,
                restoredCloseToBaseline: false,
                brightnessBefore: nil,
                brightnessSource: nil,
                notes: ["Could not read the transfer table."]
            )
        }
        let brightness = BrightnessController.read(displayID: display.transientID, identity: display.identity)
        let requested = DesiredOutput(temperature: temperature)
        let target = baseline.applying(requested.channelScale)
        let error = TransferTableBridge.write(displayID: display.transientID, table: target)
        let afterWrite = TransferTableBridge.read(displayID: display.transientID)
        if hold > 0 {
            Thread.sleep(forTimeInterval: hold)
        }
        var afterRestore: TransferTable?
        if restoreAfter {
            _ = TransferTableBridge.write(displayID: display.transientID, table: baseline)
            afterRestore = TransferTableBridge.read(displayID: display.transientID)
        }
        let changed = (afterWrite?.maxAbsoluteDelta(from: baseline) ?? 0) > 0.015
        let restored = (afterRestore?.maxAbsoluteDelta(from: baseline) ?? 1) < 0.02
        if error == .success && !changed {
            notes.append("API success with no meaningful readback change. Treat visual change as unverified.")
        } else if changed {
            notes.append("Readback changed after the write. Visual confirmation on the physical panel is still separate.")
        }
        if restoreAfter && !restored {
            notes.append("Restore did not fully match the captured baseline.")
            TransferTableBridge.restoreColorSync()
        }
        return DisplayProbeResult(
            display: display,
            requested: requested,
            setError: error.rawValue,
            baselineMean: baseline.mean(),
            afterWriteMean: afterWrite?.mean(),
            afterRestoreMean: afterRestore?.mean(),
            readbackChanged: changed,
            restoredCloseToBaseline: restored,
            brightnessBefore: brightness?.value,
            brightnessSource: brightness?.source,
            notes: notes
        )
    }
}
