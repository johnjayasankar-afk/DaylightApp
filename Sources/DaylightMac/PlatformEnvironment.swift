import Darwin
import Foundation

public struct PlatformEnvironment: Sendable {
    public var osMajor: Int
    public var chipBrand: String
    public var isAppleSilicon: Bool
    public var isKnownBrokenGammaChip: Bool

    public static var current: PlatformEnvironment {
        let os = operatingSystemVersion()
        var brand = sysctlString("machdep.cpu.brand_string")
        if brand.isEmpty {
            brand = utsnameMachine()
        }
        #if arch(arm64)
        let apple = true
        #else
        let apple = brand.contains("Apple")
        #endif
        // Public reports isolate silent transfer-table no-ops to 2026 high-end chips (M5 Pro/Max),
        // not to earlier Pro/Max parts such as M1 Max. We still verify by readback on every machine.
        let knownBroken = apple && os.majorVersion >= 26 && brand.contains("M5") &&
            (brand.contains("Pro") || brand.contains("Max") || brand.contains("Ultra"))
        return PlatformEnvironment(
            osMajor: os.majorVersion,
            chipBrand: brand.isEmpty ? "Unknown" : brand,
            isAppleSilicon: apple,
            isKnownBrokenGammaChip: knownBroken
        )
    }

    public var gammaWarning: String? {
        if isKnownBrokenGammaChip {
            return "This chip generation has public reports that CGSetDisplayTransferByTable can return success without changing the panel. Daylight will still attempt the public API and report readback honestly."
        }
        return nil
    }

    private static func operatingSystemVersion() -> OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
    }

    private static func utsnameMachine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
    }
}
