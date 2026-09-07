import CoreGraphics
import DaylightCore
import Foundation

enum TransferTableBridge {
    static func read(displayID: CGDirectDisplayID) -> TransferTable? {
        let capacity = max(CGDisplayGammaTableCapacity(displayID), 256)
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var count: UInt32 = 0
        let error = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &count)
        guard error == .success, count > 1 else { return nil }
        return TransferTable(
            red: red.prefix(Int(count)).map(Double.init),
            green: green.prefix(Int(count)).map(Double.init),
            blue: blue.prefix(Int(count)).map(Double.init)
        )
    }

    static func write(displayID: CGDirectDisplayID, table: TransferTable) -> CGError {
        var red = table.red.map(CGGammaValue.init)
        var green = table.green.map(CGGammaValue.init)
        var blue = table.blue.map(CGGammaValue.init)
        return CGSetDisplayTransferByTable(displayID, UInt32(table.sampleCount), &red, &green, &blue)
    }

    static func restoreColorSync() {
        CGDisplayRestoreColorSyncSettings()
    }
}
