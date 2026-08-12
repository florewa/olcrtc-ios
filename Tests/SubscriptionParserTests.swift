import XCTest

#if SWIFT_PACKAGE
@testable import OlcrtcParsing
#else
@testable import olcRTC
#endif

final class SubscriptionParserTests: XCTestCase {
    func testSubscriptionMetadataAndProfiles() {
        let key = String(repeating: "01", count: 32)
        let text = """
        #name: Моя подписка
        #refresh: 6h

        olcrtc://telemost@r/room?k=\(key)&t=vp8channel&c=one#Основной
        not-a-profile
        olcrtc://wbstream@room/second?key=\(key)&transport=vp8channel&client_id=two#Резерв
        """

        let parsed = SubscriptionParser.parse(text)
        XCTAssertEqual(parsed.name, "Моя подписка")
        XCTAssertEqual(parsed.refreshInterval, "6h")
        XCTAssertEqual(parsed.profiles.count, 2)
        XCTAssertTrue(parsed.rejectedLines.isEmpty)
    }

    func testMalformedOlcrtcLineIsReported() {
        let parsed = SubscriptionParser.parse("olcrtc://telemost@r/room?k=nope")
        XCTAssertTrue(parsed.profiles.isEmpty)
        XCTAssertEqual(parsed.rejectedLines.count, 1)
    }
}
