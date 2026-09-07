import AppKit
import ColorSync
import CoreGraphics
import DaylightCore
import Foundation

public enum DisplayListBuffer: Sendable {
    public static let limit: UInt32 = 256

    public static func nextCapacity(reported: UInt32, allocated: UInt32, limit: UInt32 = limit) -> UInt32? {
        if reported < allocated || allocated >= limit { return nil }
        return min(allocated * 2, limit)
    }
}

public enum DisplayEnumerator {
    public static func connectedDisplays(environment: PlatformEnvironment = .current) -> [ConnectedDisplay] {
        let online = displayIDs(using: CGGetOnlineDisplayList)
        let active = displayIDs(using: CGGetActiveDisplayList)
        let activeSet = Set(active)
        let mainID = CGMainDisplayID()

        return online.map { id in
            makeDisplay(id: id, isActive: activeSet.contains(id), isMain: id == mainID, environment: environment)
        }
    }

    private static func displayIDs(
        using getter: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var allocated: UInt32 = 16
        while true {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(allocated))
            var count: UInt32 = 0
            _ = getter(allocated, &ids, &count)
            if DisplayListBuffer.nextCapacity(reported: count, allocated: allocated) == nil {
                return Array(ids.prefix(Int(count)))
            }
            allocated = DisplayListBuffer.nextCapacity(reported: count, allocated: allocated) ?? allocated
        }
    }

    public static func makeDisplay(
        id: CGDirectDisplayID,
        isActive: Bool,
        isMain: Bool,
        environment: PlatformEnvironment
    ) -> ConnectedDisplay {
        let identity = identity(for: id)
        let mirrored = CGDisplayIsInMirrorSet(id) != 0
        let mirrorSource = CGDisplayMirrorsDisplay(id)
        let name = screenName(for: id) ?? identity.defaultName
        var notes: [String] = []
        if let warning = environment.gammaWarning {
            notes.append(warning)
        }
        if mirrored {
            notes.append("This display is in a mirror set. Warmth may be shared with the primary display.")
        }

        let brightnessAvailable = BrightnessController.canChange(displayID: id, identity: identity)
        let capabilities = DisplayCapabilities(
            warmth: .transferTable,
            brightness: brightnessAvailable ? .hardware : .softwareDimming,
            independentOfOtherDisplays: !mirrored,
            sharesControlsWithDisplayKey: mirrorSource == 0 ? nil : identityKey(for: mirrorSource),
            notes: notes
        )

        return ConnectedDisplay(
            identity: identity,
            transientID: id,
            name: name,
            connection: isActive ? .connected : .inactive,
            capabilities: capabilities,
            widthPixels: Int(CGDisplayPixelsWide(id)),
            heightPixels: Int(CGDisplayPixelsHigh(id)),
            isMain: isMain,
            isMirrored: mirrored,
            mirrorsDisplayKey: mirrorSource == 0 ? nil : identityKey(for: mirrorSource)
        )
    }

    public static func identity(for id: CGDirectDisplayID) -> DisplayIdentity {
        DisplayIdentity(
            uuid: uuidString(for: id),
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            productName: screenName(for: id)
        )
    }

    public static func identityKey(for id: CGDirectDisplayID) -> String {
        identity(for: id).durableKey
    }

    public static func screenName(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == id
        }?.localizedName
    }

    public static func uuidString(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
