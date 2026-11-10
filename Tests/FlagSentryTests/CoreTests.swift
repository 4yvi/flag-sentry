import XCTest
@testable import FlagSentryCore

final class FlagTests: XCTestCase {
    func testValidCodes() {
        XCTAssertEqual(Flag.emoji(for: "US"), "🇺🇸")
        XCTAssertEqual(Flag.emoji(for: "DE"), "🇩🇪")
    }

    func testLowercaseIsAccepted() {
        XCTAssertEqual(Flag.emoji(for: "gb"), "🇬🇧")
    }

    func testInvalidInputReturnsEmpty() {
        for code in ["", "U", "USA", "1A", "A1", "Ü", "  ", "🇺🇸"] {
            XCTAssertEqual(Flag.emoji(for: code), "", "code: \(code)")
        }
    }
}

final class ResponseParserTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testSuccess() throws {
        let data = json(#"{"status":"success","country":"Germany","countryCode":"DE","query":"1.2.3.4"}"#)
        let result = try ResponseParser.parse(data: data, statusCode: 200)
        XCTAssertEqual(result, IPLookup(ip: "1.2.3.4", country: "Germany", countryCode: "DE"))
    }

    func testIPv6IsAccepted() throws {
        let data = json(#"{"status":"success","country":"Germany","countryCode":"DE","query":"2001:db8::1"}"#)
        XCTAssertEqual(try ResponseParser.parse(data: data, statusCode: 200).ip, "2001:db8::1")
    }

    func testServiceFailure() {
        let data = json(#"{"status":"fail"}"#)
        XCTAssertThrowsError(try ResponseParser.parse(data: data, statusCode: 200)) {
            XCTAssertEqual($0 as? LookupError, .serviceReportedFailure)
        }
    }

    func testMissingQuery() {
        let data = json(#"{"status":"success","country":"Germany","countryCode":"DE"}"#)
        XCTAssertThrowsError(try ResponseParser.parse(data: data, statusCode: 200)) {
            XCTAssertEqual($0 as? LookupError, .invalidIP)
        }
    }

    func testRejectsNonIPQuery() {
        let data = json(#"{"status":"success","country":"X","countryCode":"DE","query":"<script>alert(1)</script>"}"#)
        XCTAssertThrowsError(try ResponseParser.parse(data: data, statusCode: 200)) {
            XCTAssertEqual($0 as? LookupError, .invalidIP)
        }
    }

    func testHTTPStatuses() {
        XCTAssertThrowsError(try ResponseParser.parse(data: Data(), statusCode: 500)) {
            XCTAssertEqual($0 as? LookupError, .httpStatus(500))
        }
        XCTAssertThrowsError(try ResponseParser.parse(data: Data(), statusCode: 429)) {
            XCTAssertEqual($0 as? LookupError, .rateLimited)
        }
    }

    func testMalformedJSON() {
        XCTAssertThrowsError(try ResponseParser.parse(data: json("not json"), statusCode: 200)) {
            XCTAssertEqual($0 as? LookupError, .malformedJSON)
        }
    }

    func testInvalidCountryCodeIsDropped() throws {
        let data = json(#"{"status":"success","country":"Germany","countryCode":"DEU","query":"1.2.3.4"}"#)
        XCTAssertNil(try ResponseParser.parse(data: data, statusCode: 200).countryCode)
    }

    func testCountryIsSanitized() throws {
        let data = json(#"{"status":"success","country":"Ger\nmany\u0007","countryCode":"de","query":"1.2.3.4"}"#)
        let result = try ResponseParser.parse(data: data, statusCode: 200)
        XCTAssertEqual(result.country, "Germany")
        XCTAssertEqual(result.countryCode, "DE")
    }

    func testLongCountryIsTruncated() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(ResponseParser.sanitize(long)?.count, ResponseParser.maxCountryLength)
    }

    func testEmptyCountryBecomesNil() {
        XCTAssertNil(ResponseParser.sanitize("  \n "))
        XCTAssertNil(ResponseParser.sanitize(nil))
    }
}

final class IPChangeTrackerTests: XCTestCase {
    func testFirstIPIsNotAChange() {
        var tracker = IPChangeTracker()
        XCTAssertNil(tracker.record("1.1.1.1"))
        XCTAssertEqual(tracker.lastIP, "1.1.1.1")
    }

    func testSameIPIsNotAChange() {
        var tracker = IPChangeTracker()
        _ = tracker.record("1.1.1.1")
        XCTAssertNil(tracker.record("1.1.1.1"))
    }

    func testChangeReturnsOldIP() {
        var tracker = IPChangeTracker()
        _ = tracker.record("1.1.1.1")
        XCTAssertEqual(tracker.record("2.2.2.2"), "1.1.1.1")
        XCTAssertEqual(tracker.lastIP, "2.2.2.2")
    }

    func testChangeBackIsReported() {
        var tracker = IPChangeTracker()
        _ = tracker.record("1.1.1.1")
        _ = tracker.record("2.2.2.2")
        XCTAssertEqual(tracker.record("1.1.1.1"), "2.2.2.2")
    }
}

final class RateLimiterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testNoPreviousRequest() {
        XCTAssertEqual(RateLimiter.delay(lastStart: nil, now: now, minGap: 2), 0)
    }

    func testGapElapsed() {
        XCTAssertEqual(RateLimiter.delay(lastStart: now.addingTimeInterval(-2), now: now, minGap: 2), 0)
        XCTAssertEqual(RateLimiter.delay(lastStart: now.addingTimeInterval(-10), now: now, minGap: 2), 0)
    }

    func testWithinGapReturnsRemaining() {
        XCTAssertEqual(RateLimiter.delay(lastStart: now.addingTimeInterval(-0.5), now: now, minGap: 2), 1.5, accuracy: 0.0001)
    }
}

final class NotificationTextTests: XCTestCase {
    func testFormatWithCountry() {
        let text = NotificationText.ipChanged(old: "1.1.1.1", new: "2.2.2.2", country: "Germany")
        XCTAssertEqual(text.title, "IP changed to Germany")
        XCTAssertEqual(text.body, "1.1.1.1 → 2.2.2.2 (Germany)")
    }

    func testFormatWithoutCountry() {
        let text = NotificationText.ipChanged(old: "1.1.1.1", new: "2.2.2.2", country: nil)
        XCTAssertEqual(text.title, "IP changed")
        XCTAssertEqual(text.body, "1.1.1.1 → 2.2.2.2 (—)")
    }

    func testNoAppName() {
        let text = NotificationText.ipChanged(old: "1.1.1.1", new: "2.2.2.2", country: "France")
        XCTAssertFalse((text.title + text.body).localizedCaseInsensitiveContains("flagsentry"))
    }
}
