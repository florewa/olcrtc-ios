import Foundation
import XCTest
@testable import OlcrtcParsing

final class TunnelHealthTests: XCTestCase {
    func testDecodesMobileStatusAndReportsHealthy() throws {
        let json = """
        {
          "running": true,
          "ready": true,
          "session_id": "abc",
          "started_at_millis": 199000,
          "ready_at_millis": 200000,
          "last_pong_millis": 250000,
          "last_rtt_millis": 42,
          "missed_pongs": 0,
          "reconnects": 2,
          "unhealthy_events": 1
        }
        """
        let health = try JSONDecoder().decode(TunnelHealthSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(health.sessionID, "abc")
        XCTAssertEqual(health.lastRTTMillis, 42)
        XCTAssertEqual(health.watchdogVerdict(at: Date(timeIntervalSince1970: 300)), .healthy)
    }

    func testReportsStoppedAndStaleTunnel() {
        var health = snapshot()
        health.running = false
        XCTAssertEqual(health.watchdogVerdict(at: Date(timeIntervalSince1970: 300)), .unhealthy("ядро olcRTC остановлено"))

        health = snapshot()
        health.lastPongMillis = 200_000
        XCTAssertEqual(
            health.watchdogVerdict(at: Date(timeIntervalSince1970: 300)),
            .unhealthy("контрольный канал не отвечает более 75 секунд")
        )
    }

    func testAllowsWarmupBeforeFirstPong() {
        var health = snapshot()
        health.lastPongMillis = 0
        health.readyAtMillis = 250_000

        XCTAssertEqual(health.watchdogVerdict(at: Date(timeIntervalSince1970: 300)), .warmingUp)
    }

    private func snapshot() -> TunnelHealthSnapshot {
        TunnelHealthSnapshot(
            running: true,
            ready: true,
            sessionID: "session",
            startedAtMillis: 190_000,
            readyAtMillis: 200_000,
            lastPongMillis: 250_000,
            lastRTTMillis: 10,
            missedPongs: 0,
            reconnects: 0,
            unhealthyEvents: 0,
            lastError: nil
        )
    }
}
