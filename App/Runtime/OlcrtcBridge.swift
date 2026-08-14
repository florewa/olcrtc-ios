import Foundation
import OlcrtcCore

enum OlcrtcBridge {
    static func start(profile: OlcrtcProfile, port: Int, user: String, password: String) throws {
        MobileSetProtector(IOSSocketProtector.shared)
        MobileSetProviders()
        MobileSetDNS(profile.dnsServer)
        MobileSetWBToken(profile.authToken)
        MobileSetVP8Options(profile.vp8FPS, profile.vp8Batch)
        MobileSetDebug(false)
        var startError: NSError?
        let started = MobileStartWithTransport(
            profile.carrier,
            profile.transport,
            profile.roomID,
            profile.clientID,
            profile.keyHex,
            port,
            user,
            password,
            &startError
        )
        guard started else {
            throw startError ?? bridgeError("Не удалось запустить Go-ядро")
        }

        var readyError: NSError?
        let ready = MobileWaitReady(60_000, &readyError)
        guard ready else {
            MobileStop()
            throw readyError ?? bridgeError("SOCKS не перешёл в состояние готовности")
        }
    }

    static func stop() {
        MobileStop()
    }

    static func health() throws -> TunnelHealthSnapshot {
        let data = Data(MobileStatusJSON().utf8)
        return try JSONDecoder().decode(TunnelHealthSnapshot.self, from: data)
    }

    private static func bridgeError(_ message: String) -> NSError {
        NSError(
            domain: "OlcrtcIOS.GoBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
