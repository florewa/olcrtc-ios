import XCTest
@testable import OlcrtcIOS

final class OlcrtcURIParserTests: XCTestCase {
    private let key = String(repeating: "ab", count: 32)

    func testCompactPanelURI() throws {
        let profile = try OlcrtcURIParser.parse(
            "olcrtc://telemost@r/room%2Fpart?k=\(key)&t=vp8channel&f=120&b=64&c=device-1&d=77.88.8.8%3A53#Main"
        )

        XCTAssertEqual(profile.carrier, "telemost")
        XCTAssertEqual(profile.roomID, "room/part")
        XCTAssertEqual(profile.transport, "vp8channel")
        XCTAssertEqual(profile.clientID, "device-1")
        XCTAssertEqual(profile.vp8FPS, 120)
        XCTAssertEqual(profile.vp8Batch, 64)
        XCTAssertEqual(profile.dnsServer, "77.88.8.8:53")
        XCTAssertEqual(profile.name, "Main")
    }

    func testLongPanelURI() throws {
        let profile = try OlcrtcURIParser.parse(
            "olcrtc://wbstream@room/room-id?key=\(key)&transport=vp8channel&vp8_fps=60&vp8_batch=8&client_id=client#WB"
        )

        XCTAssertEqual(profile.carrier, "wbstream")
        XCTAssertEqual(profile.roomID, "room-id")
        XCTAssertEqual(profile.keyHex, key)
        XCTAssertEqual(profile.clientID, "client")
        XCTAssertEqual(profile.vp8FPS, 60)
        XCTAssertEqual(profile.vp8Batch, 8)
    }

    func testOmittedTransportMeansDataChannel() throws {
        let profile = try OlcrtcURIParser.parse(
            "olcrtc://jitsi@r/https%3A%2F%2Fmeet.example%2Froom?k=\(key)&c=client#Jitsi"
        )
        XCTAssertEqual(profile.transport, "datachannel")
        XCTAssertEqual(profile.roomID, "https://meet.example/room")
    }

    func testMissingClientIDIsRejectedBeforeRuntime() {
        XCTAssertThrowsError(
            try OlcrtcURIParser.parse("olcrtc://telemost@r/room?k=\(key)&t=vp8channel")
        ) { error in
            XCTAssertEqual(error as? OlcrtcURIError, .missingField("client_id"))
        }
    }

    func testInvalidKeyIsRejected() {
        XCTAssertThrowsError(
            try OlcrtcURIParser.parse("olcrtc://telemost@r/room?k=bad&c=client")
        ) { error in
            XCTAssertEqual(error as? OlcrtcURIError, .invalidKey)
        }
    }
}
