import Foundation

public struct DisplayIdentity: Hashable, Sendable, Codable {
    public var uuid: String?
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var isBuiltin: Bool
    public var productName: String?

    public init(
        uuid: String?,
        vendor: UInt32,
        model: UInt32,
        serial: UInt32,
        isBuiltin: Bool,
        productName: String? = nil
    ) {
        self.uuid = uuid
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltin = isBuiltin
        self.productName = productName
    }

    public var durableKey: String {
        if let uuid, !uuid.isEmpty {
            return "uuid:\(uuid)"
        }
        return "edid:\(vendor)-\(model)-\(serial)-\(isBuiltin ? "builtin" : "external")"
    }

    public var defaultName: String {
        if let productName, !productName.isEmpty {
            return productName
        }
        return isBuiltin ? "Built-in Display" : "External Display"
    }

    public func matchConfidence(against other: DisplayIdentity) -> DisplayMatchConfidence {
        if let uuid, let otherUUID = other.uuid, uuid == otherUUID {
            return .exact
        }
        if vendor != 0, model != 0, vendor == other.vendor, model == other.model, serial == other.serial, serial != 0 {
            return .strong
        }
        if isBuiltin && other.isBuiltin && vendor == other.vendor && model == other.model {
            return .probable
        }
        return .uncertain
    }
}

public enum DisplayMatchConfidence: String, Sendable, Codable {
    case exact
    case strong
    case probable
    case uncertain
}

public enum BrightnessControlKind: String, Sendable, Codable {
    case hardware
    case softwareDimming
    case none

    public var label: String {
        switch self {
        case .hardware: return "Hardware brightness"
        case .softwareDimming: return "Software dimming"
        case .none: return "No brightness control"
        }
    }
}

public enum WarmthControlKind: String, Sendable, Codable {
    case transferTable
    case unsupported
    case simulated

    public var label: String {
        switch self {
        case .transferTable: return "Display transfer table"
        case .unsupported: return "Warmth not supported"
        case .simulated: return "Simulation only"
        }
    }
}

public struct DisplayCapabilities: Hashable, Sendable, Codable {
    public var warmth: WarmthControlKind
    public var brightness: BrightnessControlKind
    public var independentOfOtherDisplays: Bool
    public var sharesControlsWithDisplayKey: String?
    public var notes: [String]

    public init(
        warmth: WarmthControlKind,
        brightness: BrightnessControlKind,
        independentOfOtherDisplays: Bool = true,
        sharesControlsWithDisplayKey: String? = nil,
        notes: [String] = []
    ) {
        self.warmth = warmth
        self.brightness = brightness
        self.independentOfOtherDisplays = independentOfOtherDisplays
        self.sharesControlsWithDisplayKey = sharesControlsWithDisplayKey
        self.notes = notes
    }

    public var canAdjustWarmth: Bool {
        warmth == .transferTable || warmth == .simulated
    }
}

public enum DisplayConnectionState: String, Sendable, Codable {
    case connected
    case inactive
    case disconnected

    public var title: String {
        switch self {
        case .connected: return "Active"
        case .inactive: return "Connected, idle"
        case .disconnected: return "Disconnected"
        }
    }

    public var isPresent: Bool {
        self != .disconnected
    }
}

public struct ConnectedDisplay: Hashable, Sendable, Codable, Identifiable {
    public var identity: DisplayIdentity
    public var transientID: UInt32
    public var name: String
    public var connection: DisplayConnectionState
    public var capabilities: DisplayCapabilities
    public var widthPixels: Int
    public var heightPixels: Int
    public var isMain: Bool
    public var isMirrored: Bool
    public var mirrorsDisplayKey: String?

    public var id: String { identity.durableKey }

    public init(
        identity: DisplayIdentity,
        transientID: UInt32,
        name: String,
        connection: DisplayConnectionState = .connected,
        capabilities: DisplayCapabilities,
        widthPixels: Int,
        heightPixels: Int,
        isMain: Bool,
        isMirrored: Bool,
        mirrorsDisplayKey: String? = nil
    ) {
        self.identity = identity
        self.transientID = transientID
        self.name = name
        self.connection = connection
        self.capabilities = capabilities
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.isMain = isMain
        self.isMirrored = isMirrored
        self.mirrorsDisplayKey = mirrorsDisplayKey
    }
}

public struct DisplayPreferences: Hashable, Sendable, Codable, Identifiable {
    public var identity: DisplayIdentity
    public var customName: String?
    public var groupID: String?
    public var excludedFromAutomation: Bool
    public var limits: DisplayLimits
    public var brightnessOffset: Double
    public var lastSafeOutput: DesiredOutput?

    public var id: String { identity.durableKey }

    public init(
        identity: DisplayIdentity,
        customName: String? = nil,
        groupID: String? = nil,
        excludedFromAutomation: Bool = false,
        limits: DisplayLimits = .conservative,
        brightnessOffset: Double = 0,
        lastSafeOutput: DesiredOutput? = nil
    ) {
        self.identity = identity
        self.customName = customName
        self.groupID = groupID
        self.excludedFromAutomation = excludedFromAutomation
        self.limits = limits
        self.brightnessOffset = brightnessOffset
        self.lastSafeOutput = lastSafeOutput
    }

    public func resolvedName(fallback: String) -> String {
        if let customName, !customName.isEmpty { return customName }
        return fallback
    }
}

public struct DisplayGroup: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var displayKeys: [String]

    public init(id: String = UUID().uuidString, name: String, displayKeys: [String]) {
        self.id = id
        self.name = name
        self.displayKeys = displayKeys
    }
}

public enum WorkspaceKind: String, Sendable, Codable, CaseIterable {
    case automatic
    case home
    case work
    case travel
    case custom

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .home: return "Home"
        case .work: return "Work"
        case .travel: return "Travel"
        case .custom: return "Custom"
        }
    }
}

public struct WorkspaceProfile: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var kind: WorkspaceKind
    public var matchingDisplayKeys: [String]
    public var scheduleID: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: WorkspaceKind,
        matchingDisplayKeys: [String] = [],
        scheduleID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.matchingDisplayKeys = matchingDisplayKeys
        self.scheduleID = scheduleID
    }

    public func matches(connectedKeys: Set<String>) -> Bool {
        guard !matchingDisplayKeys.isEmpty else { return false }
        return Set(matchingDisplayKeys).isSubset(of: connectedKeys)
    }
}
