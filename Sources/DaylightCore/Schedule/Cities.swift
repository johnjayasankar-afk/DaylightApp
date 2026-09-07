import Foundation

public enum Cities {
    public static let featured: [LocationFix] = [
        LocationFix(name: "San Francisco, US", latitude: 37.7749, longitude: -122.4194, timeZoneIdentifier: "America/Los_Angeles"),
        LocationFix(name: "New York, US", latitude: 40.7128, longitude: -74.0060, timeZoneIdentifier: "America/New_York"),
        LocationFix(name: "Chicago, US", latitude: 41.8781, longitude: -87.6298, timeZoneIdentifier: "America/Chicago"),
        LocationFix(name: "Denver, US", latitude: 39.7392, longitude: -104.9903, timeZoneIdentifier: "America/Denver"),
        LocationFix(name: "Los Angeles, US", latitude: 34.0522, longitude: -118.2437, timeZoneIdentifier: "America/Los_Angeles"),
        LocationFix(name: "Seattle, US", latitude: 47.6062, longitude: -122.3321, timeZoneIdentifier: "America/Los_Angeles"),
        LocationFix(name: "Toronto, CA", latitude: 43.6532, longitude: -79.3832, timeZoneIdentifier: "America/Toronto"),
        LocationFix(name: "London, UK", latitude: 51.5074, longitude: -0.1278, timeZoneIdentifier: "Europe/London"),
        LocationFix(name: "Paris, FR", latitude: 48.8566, longitude: 2.3522, timeZoneIdentifier: "Europe/Paris"),
        LocationFix(name: "Berlin, DE", latitude: 52.5200, longitude: 13.4050, timeZoneIdentifier: "Europe/Berlin"),
        LocationFix(name: "Stockholm, SE", latitude: 59.3293, longitude: 18.0686, timeZoneIdentifier: "Europe/Stockholm"),
        LocationFix(name: "Helsinki, FI", latitude: 60.1699, longitude: 24.9384, timeZoneIdentifier: "Europe/Helsinki"),
        LocationFix(name: "Reykjavik, IS", latitude: 64.1466, longitude: -21.9426, timeZoneIdentifier: "Atlantic/Reykjavik"),
        LocationFix(name: "Tromsø, NO", latitude: 69.6492, longitude: 18.9553, timeZoneIdentifier: "Europe/Oslo"),
        LocationFix(name: "Madrid, ES", latitude: 40.4168, longitude: -3.7038, timeZoneIdentifier: "Europe/Madrid"),
        LocationFix(name: "Rome, IT", latitude: 41.9028, longitude: 12.4964, timeZoneIdentifier: "Europe/Rome"),
        LocationFix(name: "Dubai, AE", latitude: 25.2048, longitude: 55.2708, timeZoneIdentifier: "Asia/Dubai"),
        LocationFix(name: "Mumbai, IN", latitude: 19.0760, longitude: 72.8777, timeZoneIdentifier: "Asia/Kolkata"),
        LocationFix(name: "Bengaluru, IN", latitude: 12.9716, longitude: 77.5946, timeZoneIdentifier: "Asia/Kolkata"),
        LocationFix(name: "Singapore, SG", latitude: 1.3521, longitude: 103.8198, timeZoneIdentifier: "Asia/Singapore"),
        LocationFix(name: "Hong Kong, HK", latitude: 22.3193, longitude: 114.1694, timeZoneIdentifier: "Asia/Hong_Kong"),
        LocationFix(name: "Tokyo, JP", latitude: 35.6762, longitude: 139.6503, timeZoneIdentifier: "Asia/Tokyo"),
        LocationFix(name: "Seoul, KR", latitude: 37.5665, longitude: 126.9780, timeZoneIdentifier: "Asia/Seoul"),
        LocationFix(name: "Sydney, AU", latitude: -33.8688, longitude: 151.2093, timeZoneIdentifier: "Australia/Sydney"),
        LocationFix(name: "Melbourne, AU", latitude: -37.8136, longitude: 144.9631, timeZoneIdentifier: "Australia/Melbourne"),
        LocationFix(name: "Auckland, NZ", latitude: -36.8509, longitude: 174.7645, timeZoneIdentifier: "Pacific/Auckland"),
        LocationFix(name: "São Paulo, BR", latitude: -23.5505, longitude: -46.6333, timeZoneIdentifier: "America/Sao_Paulo"),
        LocationFix(name: "Mexico City, MX", latitude: 19.4326, longitude: -99.1332, timeZoneIdentifier: "America/Mexico_City"),
        LocationFix(name: "Cape Town, ZA", latitude: -33.9249, longitude: 18.4241, timeZoneIdentifier: "Africa/Johannesburg"),
        LocationFix(name: "Nairobi, KE", latitude: -1.2921, longitude: 36.8219, timeZoneIdentifier: "Africa/Nairobi"),
        LocationFix(name: "Longyearbyen, SJ", latitude: 78.2232, longitude: 15.6267, timeZoneIdentifier: "Arctic/Longyearbyen"),
        LocationFix(name: "McMurdo Station, AQ", latitude: -77.8419, longitude: 166.6863, timeZoneIdentifier: "Antarctica/McMurdo")
    ]

    public static func search(_ query: String) -> [LocationFix] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return featured.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Apply a typed city only when the match is unambiguous.
    public enum QueryStatus: Equatable, Sendable {
        case empty
        case matched(LocationFix)
        case unrecognized
    }

    public static func status(for query: String) -> QueryStatus {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if let match = match(trimmed) { return .matched(match) }
        return .unrecognized
    }

    public static func match(_ query: String) -> LocationFix? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = featured.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }
        let lower = trimmed.lowercased()
        let prefixed = featured.filter { $0.name.lowercased().hasPrefix(lower) }
        if prefixed.count == 1 { return prefixed[0] }
        let contained = search(trimmed)
        if contained.count == 1 { return contained[0] }
        return nil
    }
}
