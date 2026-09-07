import Foundation

public enum SettingsStoreError: Error, Sendable, Equatable {
    case unreadable
    case invalid
    case io
}

public struct SettingsStore: @unchecked Sendable {
    public var directory: URL
    public var fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func applicationSupportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root.appendingPathComponent(Brand.supportFolderName, isDirectory: true)
    }

    public var settingsURL: URL {
        directory.appendingPathComponent(Brand.settingsFileName)
    }

    public var ownershipURL: URL {
        directory.appendingPathComponent(Brand.ownershipFileName)
    }

    public var historyURL: URL {
        directory.appendingPathComponent(Brand.historyFileName)
    }

    public func load() throws -> AppSettings {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            let decoded = try decodeSettings(data)
            return decoded
        } catch {
            throw SettingsStoreError.invalid
        }
    }

    /// Loads settings, or returns defaults after copying an unreadable file aside.
    public func recoverIfNeeded() -> (settings: AppSettings, warning: String?) {
        do {
            try ensureDirectory()
        } catch {
            return (AppSettings(), "Daylight could not create its settings folder on this Mac.")
        }
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return (AppSettings(), nil)
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            return (try decodeSettings(data), nil)
        } catch {
            let backup = directory.appendingPathComponent("settings-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.copyItem(at: settingsURL, to: backup)
            return (
                AppSettings(),
                "The saved settings file could not be read. Daylight started with defaults and kept a copy of the previous file."
            )
        }
    }

    public func save(_ settings: AppSettings) throws {
        try ensureDirectory()
        var record = settings
        record.schemaVersion = AppSettings.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try atomicWrite(data, to: settingsURL)
    }

    public func saveOwnership(_ record: OwnershipRecord) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try atomicWrite(try encoder.encode(record), to: ownershipURL)
    }

    public func loadOwnership() -> OwnershipRecord? {
        guard let data = try? Data(contentsOf: ownershipURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnershipRecord.self, from: data)
    }

    public func clearOwnership() {
        try? fileManager.removeItem(at: ownershipURL)
    }

    public func exportSettings(_ settings: AppSettings) throws -> Data {
        var exported = settings
        exported.pause = .inactive
        exported.override = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exported)
    }

    public func `import`(_ data: Data) throws -> AppSettings {
        guard looksLikeExport(data) else { throw SettingsStoreError.invalid }
        var settings = try decodeSettings(data)
        settings.pause = .inactive
        settings.override = nil
        settings.onboarded = true
        return settings
    }

    public func decodeSettings(_ data: Data) throws -> AppSettings {
        guard looksLikeSettings(data) else { throw SettingsStoreError.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var settings = try decoder.decode(AppSettings.self, from: data)
            settings = migrate(settings)
            return settings
        } catch {
            throw SettingsStoreError.invalid
        }
    }

    private func looksLikeSettings(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let recognized: Set<String> = [
            "schemaVersion", "onboarded", "weekdaySchedule", "weekendSchedule",
            "useWeekendSchedule", "keepRunningInBackground", "launchAtLogin",
            "selectedPresetID", "profiles", "displays", "groups", "location",
            "appearance", "disabled", "pause", "override", "showMenuBarTemperature",
            "defaultTransitionMinutes", "historyEnabled", "restoreOnSleep"
        ]
        return !recognized.isDisjoint(with: Set(object.keys))
    }

    /// Exports always include a weekday schedule object. A lone schema/onboarded key is not enough.
    private func looksLikeExport(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["weekdaySchedule"] is [String: Any]
    }

    public func migrate(_ settings: AppSettings) -> AppSettings {
        var next = settings
        if next.schemaVersion < 1 {
            next.schemaVersion = 1
        }
        if next.weekdaySchedule.personalAnchors.isEmpty {
            next.weekdaySchedule = .personal()
        }
        if next.weekendSchedule.personalAnchors.isEmpty {
            next.weekendSchedule = DailySchedule.personal().duplicated(name: "Weekend")
        }
        return next
    }

    public func appendHistory(_ event: HistoryEvent, enabled: Bool, limit: Int = 200) {
        guard enabled else { return }
        try? ensureDirectory()
        var events = loadHistory()
        events.insert(event, at: 0)
        if events.count > limit {
            events = Array(events.prefix(limit))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? atomicWrite(data, to: historyURL)
        }
    }

    public func loadHistory() -> [HistoryEvent] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEvent].self, from: data)) ?? []
    }

    public func clearHistory() {
        try? fileManager.removeItem(at: historyURL)
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: temp, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: url)
            }
        } catch {
            throw SettingsStoreError.io
        }
    }
}
