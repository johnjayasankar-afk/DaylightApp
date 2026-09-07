import CoreGraphics
import Darwin
import DaylightCore
import Foundation
import IOKit
import IOKit.graphics

struct BrightnessReadback: Sendable {
    var value: HardwareBrightness
    var source: String
}

enum BrightnessController {
    static func read(displayID: CGDirectDisplayID, identity: DisplayIdentity) -> BrightnessReadback? {
        if let iokit = readIOKit(identity: identity) {
            return BrightnessReadback(value: HardwareBrightness(fraction: Double(iokit)), source: "IOKit")
        }
        if let services = DisplayServicesBridge.getBrightness(displayID) {
            return BrightnessReadback(value: HardwareBrightness(fraction: Double(services)), source: "DisplayServices (experimental)")
        }
        return nil
    }

    static func write(displayID: CGDirectDisplayID, identity: DisplayIdentity, value: HardwareBrightness) -> (Bool, String) {
        if writeIOKit(identity: identity, value: Float(value.fraction)) {
            return (true, "IOKit")
        }
        if DisplayServicesBridge.setBrightness(displayID, Float(value.fraction)) {
            return (true, "DisplayServices (experimental)")
        }
        return (false, "No brightness backend accepted the write")
    }

    static func canChange(displayID: CGDirectDisplayID, identity: DisplayIdentity) -> Bool {
        read(displayID: displayID, identity: identity) != nil || DisplayServicesBridge.canChange(displayID)
    }

    private static func readIOKit(identity: DisplayIdentity) -> Float? {
        guard let service = findService(matching: identity) else { return nil }
        defer { IOObjectRelease(service) }
        var value: Float = 0
        let status = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
        return status == KERN_SUCCESS ? value : nil
    }

    private static func writeIOKit(identity: DisplayIdentity, value: Float) -> Bool {
        guard let service = findService(matching: identity) else { return false }
        defer { IOObjectRelease(service) }
        let status = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, value)
        return status == KERN_SUCCESS
    }

    private static func findService(matching identity: DisplayIdentity) -> io_service_t? {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IODisplayConnect")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] {
                let vendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value ?? 0
                let model = (info[kDisplayProductID] as? NSNumber)?.uint32Value ?? 0
                let serial = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value ?? 0
                if vendor == identity.vendor && model == identity.model && (serial == 0 || identity.serial == 0 || serial == identity.serial) {
                    return service
                }
                if identity.isBuiltin, vendor == identity.vendor, model == identity.model {
                    return service
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}

private enum DisplayServicesBridge {
    typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool

    nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
            ?? dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    }()

    static func getBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(symbol, to: GetFn.self)
        var value: Float = 0
        return fn(displayID, &value) == 0 ? value : nil
    }

    static func setBrightness(_ displayID: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return false }
        let fn = unsafeBitCast(symbol, to: SetFn.self)
        return fn(displayID, value) == 0
    }

    static func canChange(_ displayID: CGDirectDisplayID) -> Bool {
        guard let symbol = dlsym(handle, "DisplayServicesCanChangeBrightness") else {
            return getBrightness(displayID) != nil
        }
        let fn = unsafeBitCast(symbol, to: CanFn.self)
        return fn(displayID)
    }
}
