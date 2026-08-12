import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import OlcrtcParsing
#else
@testable import olcRTC
#endif

final class SubscriptionMirrorTests: XCTestCase {
    func testDecryptsGoCompatibleAESGCMEnvelope() throws {
        let json = #"{"type":"olcrtc-sub-mirror","v":1,"alg":"AES-256-GCM","nonce":"ICEiIyQlJicoKSor","ciphertext":"vVbFAhj7ICE1CCeipHWbiqQJnrP17wyDU51RIni6bzlEvtQ0vxUE6iXNX6JpOS740xrdvqsMHFH_Uk4tfYI77ekW_Dunp9SmulrYF4ptCFHkpwI0hsu3Lv5_8wx5IfezcXdjP7o28YHDjZpPEq4ICSNkYlr2uhaX1g"}"#
        let text = try SubscriptionMirrorLoader.decrypt(
            Data(json.utf8),
            key: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        )

        XCTAssertEqual(
            text,
            "olcrtc://telemost@r/room?k=\(String(repeating: "01", count: 32))&c=ios#Mirror\n"
        )
    }

    func testRejectsNonYandexMirrorURL() {
        XCTAssertThrowsError(
            try SubscriptionMirror.validated(
                type: "yandex_disk",
                urlString: "https://example.com/sub.json",
                key: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
            )
        ) { error in
            XCTAssertEqual(error as? SubscriptionMirrorError, .invalidURL)
        }
    }
}
