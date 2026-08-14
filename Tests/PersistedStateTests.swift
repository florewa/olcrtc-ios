import Foundation
import XCTest
@testable import OlcrtcParsing

final class PersistedStateTests: XCTestCase {
    func testDecodesStateWrittenBeforeSelectionAndHappFlags() throws {
        let oldJSON = """
        {
          "manualProfiles": [],
          "subscriptions": [],
          "socksUser": "user",
          "socksPassword": "pass",
          "socksPort": 18080
        }
        """

        let state = try JSONDecoder().decode(PersistedState.self, from: Data(oldJSON.utf8))

        XCTAssertNil(state.selectedProfileID)
        XCTAssertNil(state.hasImportedHappConfiguration)
        XCTAssertEqual(state.socksPort, 18_080)
    }
}
