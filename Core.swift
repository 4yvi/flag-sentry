import Foundation
import Network

// Pure, UI-free logic. Kept separate from AppDelegate so it can be unit tested.

// MARK: - IP lookup model

/// Raw JSON shape returned by the lookup service.
struct IPInfo: Decodable {
    let status: String
    let country: String?
    let countryCode: String?
    let query: String?
}

/// A validated and sanitized lookup result, safe to show in the UI.
struct IPLookup: Equatable {
    let ip: String
    let country: String?
    let countryCode: String?
}

enum LookupError: Error, Equatable {
    case httpStatus(Int)
    case rateLimited
    case serviceReportedFailure
    case invalidIP
    case malformedJSON
}

enum ResponseParser {
    static let maxCountryLength = 64

    /// Validates the HTTP status and the payload. The service is queried over plain HTTP,
    /// so every field is treated as untrusted input.
    static func parse(data: Data, statusCode: Int) throws -> IPLookup {
        guard statusCode == 200 else {
            throw statusCode == 429 ? LookupError.rateLimited : LookupError.httpStatus(statusCode)
        }
        let info: IPInfo
        do {
            info = try JSONDecoder().decode(IPInfo.self, from: data)
        } catch {
            throw LookupError.malformedJSON
        }
        guard info.status == "success" else { throw LookupError.serviceReportedFailure }
        guard let ip = info.query, isValidIP(ip) else { throw LookupError.invalidIP }

        let code = info.countryCode.flatMap { Flag.isValidCountryCode($0) ? $0.uppercased() : nil }
        return IPLookup(ip: ip, country: sanitize(info.country), countryCode: code)
    }

    static func isValidIP(_ string: String) -> Bool {
        IPv4Address(string) != nil || IPv6Address(string) != nil
    }

    /// Removes control characters, trims whitespace and caps the length.
    static func sanitize(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxCountryLength))
    }
}

// MARK: - Flag

enum Flag {
    static func isValidCountryCode(_ code: String) -> Bool {
        let scalars = Array(code.uppercased().unicodeScalars)
        return scalars.count == 2 && scalars.allSatisfy { (65...90).contains($0.value) }
    }

    /// Converts an ISO 3166-1 alpha-2 code to a flag emoji; returns "" for invalid input.
    static func emoji(for code: String) -> String {
        guard isValidCountryCode(code) else { return "" }
        var result = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let s = UnicodeScalar(127397 + scalar.value) else { return "" }
            result.unicodeScalars.append(s)
        }
        return result
    }
}

// MARK: - Change detection

struct IPChangeTracker {
    private(set) var lastIP: String?

    /// Records a successful lookup. Returns the previous IP if it changed, otherwise nil.
    /// Failed lookups are simply not recorded, so a failure never resets the state.
    mutating func record(_ ip: String) -> String? {
        defer { lastIP = ip }
        guard let old = lastIP, old != ip else { return nil }
        return old
    }
}

// MARK: - Rate limiting

enum RateLimiter {
    /// Seconds to wait before the next request is allowed (0 if it can start now).
    static func delay(lastStart: Date?, now: Date, minGap: TimeInterval) -> TimeInterval {
        guard let last = lastStart else { return 0 }
        let elapsed = now.timeIntervalSince(last)
        return elapsed < minGap ? minGap - elapsed : 0
    }
}

// MARK: - Notification text

struct NotificationText: Equatable {
    let title: String
    let body: String

    /// Describes what happened only; never contains the app name.
    static func ipChanged(old: String, new: String, country: String?) -> NotificationText {
        let title = country.map { "IP changed to \($0)" } ?? "IP changed"
        return NotificationText(title: title, body: "\(old) → \(new) (\(country ?? "—"))")
    }
}
