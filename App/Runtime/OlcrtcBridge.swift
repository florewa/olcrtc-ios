import Foundation
import Mobile

enum OlcrtcBridge {
    static func start(profile: OlcrtcProfile, port: Int, user: String, password: String) throws {
        MobileSetProtector(IOSSocketProtector.shared)
        MobileSetProviders()
        MobileSetDNS(profile.dnsServer)
        MobileSetWBToken(profile.authToken)
        MobileSetVP8Options(profile.vp8FPS, profile.vp8Batch)
        MobileSetDebug(false)
        let started = try MobileStartWithTransport(
            profile.carrier,
            profile.transport,
            profile.roomID,
            profile.clientID,
            profile.keyHex,
            port,
            user,
            password
        )
        guard started else { throw bridgeError("Не удалось запустить Go-ядро") }
        do {
            let ready = try MobileWaitReady(60_000)
            guard ready else { throw bridgeError("SOCKS не перешёл в состояние готовности") }
        } catch {
            MobileStop()
            throw error
        }
    }

    static func stop() {
        MobileStop()
    }

    private static func bridgeError(_ message: String) -> NSError {
        NSError(
            domain: "OlcrtcIOS.GoBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
