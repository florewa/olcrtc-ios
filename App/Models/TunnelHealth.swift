import Foundation

struct TunnelHealthSnapshot: Codable, Equatable {
    var running: Bool
    var ready: Bool
    var sessionID: String
    var startedAtMillis: Int64
    var readyAtMillis: Int64
    var lastPongMillis: Int64
    var lastRTTMillis: Int64
    var missedPongs: Int
    var reconnects: UInt64
    var unhealthyEvents: UInt64
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case running
        case ready
        case sessionID = "session_id"
        case startedAtMillis = "started_at_millis"
        case readyAtMillis = "ready_at_millis"
        case lastPongMillis = "last_pong_millis"
        case lastRTTMillis = "last_rtt_millis"
        case missedPongs = "missed_pongs"
        case reconnects
        case unhealthyEvents = "unhealthy_events"
        case lastError = "last_error"
    }

    var lastPongDate: Date? {
        guard lastPongMillis > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastPongMillis) / 1_000)
    }

    func watchdogVerdict(
        at now: Date = Date(),
        startupGrace: TimeInterval = 90,
        staleAfter: TimeInterval = 75
    ) -> WatchdogVerdict {
        guard running else {
            return .unhealthy(lastError ?? "ядро olcRTC остановлено")
        }
        guard ready else {
            let started = Date(timeIntervalSince1970: TimeInterval(startedAtMillis) / 1_000)
            return now.timeIntervalSince(started) <= startupGrace
                ? .warmingUp
                : .unhealthy(lastError ?? "SOCKS не перешёл в состояние готовности")
        }
        if missedPongs >= 4 {
            return .unhealthy("сервер не отвечает на контрольные ping")
        }
        guard let lastPongDate else {
            let readyAt = Date(timeIntervalSince1970: TimeInterval(readyAtMillis) / 1_000)
            return now.timeIntervalSince(readyAt) <= startupGrace
                ? .warmingUp
                : .unhealthy("не получен первый контрольный pong")
        }
        if now.timeIntervalSince(lastPongDate) > staleAfter {
            return .unhealthy("контрольный канал не отвечает более (Int(staleAfter)) секунд")
        }
        return .healthy
    }
}

enum WatchdogVerdict: Equatable {
    case healthy
    case warmingUp
    case unhealthy(String)
}

struct TunnelEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String
}
