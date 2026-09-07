import DaylightCore
import DaylightMac
import Foundation

@main
struct DaylightProbeMain {
    static func main() {
        let args = Set(CommandLine.arguments.dropFirst())
        let hold = holdDuration(from: CommandLine.arguments)
        let restore = !args.contains("--no-restore")
        if args.contains("--restore-only") {
            MacDisplayAdapter().restoreAll(useColorSync: true)
            print("Requested ColorSync restore for all displays.")
            print("Requested state: restore. Accepted by API: ColorSync restore has no status. Visual confirmation is separate.")
            return
        }
        let apply = args.contains("--apply") || !args.contains("--list-only")

        print("\(Brand.name) display probe")
        print("Version \(Brand.marketingVersion) (\(Brand.buildNumber))")
        print("")

        let adapter = MacDisplayAdapter()
        let environment = adapter.environment
        print("Environment")
        print("  chip: \(environment.chipBrand)")
        print("  macOS major: \(environment.osMajor)")
        print("  Apple silicon: \(environment.isAppleSilicon)")
        print("  known-broken gamma chip: \(environment.isKnownBrokenGammaChip)")
        if let warning = environment.gammaWarning {
            print("  warning: \(warning)")
        }
        print("")

        let displays = adapter.enumerateDisplays()
        print("Detected displays: \(displays.count)")
        for display in displays {
            printDisplay(display)
        }

        guard apply else { return }
        guard let target = displays.first(where: { $0.connection == .connected && $0.isMain }) ?? displays.first else {
            print("No connected display was available.")
            return
        }

        print("")
        print("Applying a conservative 4200 K transfer-table adjustment to \(target.name).")
        print("This is a requested approximate target, not a spectral measurement.")
        if hold > 0 {
            print("Holding for \(Int(hold)) seconds so the panel can be looked at, then restoring.")
        }

        let result = adapter.probe(display: target, temperature: ColorTemperature(kelvin: 4200), hold: hold, restoreAfter: restore)
        print("")
        print("Result for \(result.display.name)")
        print("  requested: \(result.requested.temperature.roundedLabel)")
        print("  CGSetDisplayTransferByTable: \(result.setError == 0 ? "success" : "error \(result.setError)")")
        print("  baseline mean RGB: \(format(result.baselineMean))")
        if let after = result.afterWriteMean {
            print("  after-write mean RGB: \(format(after))")
        }
        if let restored = result.afterRestoreMean {
            print("  after-restore mean RGB: \(format(restored))")
        }
        print("  readback changed: \(result.readbackChanged)")
        print("  restored close to baseline: \(result.restoredCloseToBaseline)")
        if let brightness = result.brightnessBefore {
            print("  hardware brightness readback: \(brightness.percent)% via \(result.brightnessSource ?? "unknown")")
        } else {
            print("  hardware brightness readback: unavailable")
        }
        for note in result.notes {
            print("  note: \(note)")
        }
        print("")
        print("Evidence classes")
        print("  requested state: \(result.requested.temperature.roundedLabel)")
        print("  state accepted by API: \(result.setError == 0 ? "yes" : "no")")
        print("  state available through readback: \(result.readbackChanged ? "changed" : "unchanged or unavailable")")
        print("  state visually confirmed on hardware: unverified by this tool")
        print("")
        if result.readbackChanged && result.restoredCloseToBaseline {
            print("Hardware path looks usable on this machine. Visual confirmation is still recommended.")
        } else if result.setError == 0 && !result.readbackChanged {
            print("The API succeeded but readback did not change. Do not treat this as working hardware support.")
        } else {
            print("The hardware path is incomplete or failed. Simulation remains available for development.")
        }
    }

    private static func printDisplay(_ display: ConnectedDisplay) {
        print("  - \(display.name)")
        print("      key: \(display.id)")
        print("      transient id: \(display.transientID)")
        print("      built-in: \(display.identity.isBuiltin)")
        print("      main: \(display.isMain)  mirrored: \(display.isMirrored)")
        print("      pixels: \(display.widthPixels)x\(display.heightPixels)")
        print("      warmth: \(display.capabilities.warmth.label)")
        print("      brightness: \(display.capabilities.brightness.label)")
        if let uuid = display.identity.uuid {
            print("      uuid: \(uuid)")
        }
        print("      vendor/model/serial: \(display.identity.vendor)/\(display.identity.model)/\(display.identity.serial)")
        for note in display.capabilities.notes {
            print("      note: \(note)")
        }
    }

    private static func format(_ scale: ChannelScale) -> String {
        String(format: "R %.3f  G %.3f  B %.3f", scale.red, scale.green, scale.blue)
    }

    private static func holdDuration(from arguments: [String]) -> TimeInterval {
        if let index = arguments.firstIndex(of: "--hold"), arguments.indices.contains(index + 1) {
            return TimeInterval(arguments[index + 1]) ?? 3
        }
        return 3
    }
}
