import Foundation

enum OlcrtcURIError: LocalizedError, Equatable {
    case invalidScheme
    case unsupportedShape
    case missingField(String)
    case invalidKey
    case invalidNumber(String)
    case unsupportedCarrier(String)
    case unsupportedTransport(String)

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "Ссылка должна начинаться с olcrtc://"
        case .unsupportedShape:
            return "Неизвестный формат olcrtc-ссылки"
        case let .missingField(field):
            return "В ссылке отсутствует поле: \(field)"
        case .invalidKey:
            return "Ключ должен содержать 64 шестнадцатеричных символа"
        case let .invalidNumber(field):
            return "Некорректное числовое поле: \(field)"
        case let .unsupportedCarrier(carrier):
            return "Этот провайдер пока не поддерживается на iOS: \(carrier)"
        case let .unsupportedTransport(transport):
            return "Этот транспорт пока не поддерживается на iOS: \(transport)"
        }
    }
}

enum OlcrtcURIParser {
    private static let supportedCarriers = Set(["telemost", "wbstream", "jitsi"])
    private static let supportedTransports = Set(["vp8channel", "datachannel"])

    static func parse(_ rawValue: String) throws -> OlcrtcProfile {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.lowercased().hasPrefix("olcrtc://") else {
            throw OlcrtcURIError.invalidScheme
        }
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "olcrtc" else {
            throw OlcrtcURIError.unsupportedShape
        }

        let carrier = (components.user ?? "").lowercased()
        guard !carrier.isEmpty else { throw OlcrtcURIError.missingField("carrier") }
        guard supportedCarriers.contains(carrier) else {
            throw OlcrtcURIError.unsupportedCarrier(carrier)
        }

        let shape = components.host?.lowercased() ?? ""
        guard shape == "room" || shape == "r" else {
            throw OlcrtcURIError.unsupportedShape
        }

        let roomID = String(components.path.drop(while: { $0 == "/" }))
            .removingPercentEncoding ?? ""
        guard !roomID.isEmpty else { throw OlcrtcURIError.missingField("room") }

        let query = (components.queryItems ?? []).reduce(into: [String: String]()) {
            $0[$1.name.lowercased()] = $1.value ?? ""
        }
        let compact = shape == "r"
        let keyHex = value(query, compact: "k", long: "key").lowercased()
        guard !keyHex.isEmpty else { throw OlcrtcURIError.missingField("key") }
        let asciiHex = keyHex.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
        guard keyHex.utf8.count == 64, asciiHex else {
            throw OlcrtcURIError.invalidKey
        }

        let clientID = value(query, compact: "c", long: "client_id")
        guard !clientID.isEmpty else { throw OlcrtcURIError.missingField("client_id") }

        let transportValue = value(query, compact: "t", long: "transport")
        let transport = transportValue.isEmpty ? "datachannel" : transportValue.lowercased()
        guard supportedTransports.contains(transport) else {
            throw OlcrtcURIError.unsupportedTransport(transport)
        }

        let fps = try positiveInt(
            value(query, compact: "f", long: "vp8_fps"),
            fallback: transport == "vp8channel" ? 120 : 1,
            field: "vp8_fps"
        )
        let batch = try positiveInt(
            value(query, compact: "b", long: "vp8_batch"),
            fallback: transport == "vp8channel" ? 64 : 1,
            field: "vp8_batch"
        )
        let dns = value(query, compact: "d", long: "dns")
        let authToken = query["a"] ?? query["auth_token"] ?? query["auth.token"] ?? ""
        let decodedName = (components.fragment ?? "").removingPercentEncoding ?? ""
        let name = decodedName.isEmpty ? "\(carrier)-\(roomID.prefix(8))" : decodedName

        return OlcrtcProfile(
            name: name,
            carrier: carrier,
            transport: transport,
            roomID: roomID,
            clientID: clientID,
            keyHex: keyHex,
            dnsServer: dns.isEmpty ? "8.8.8.8:53" : dns,
            vp8FPS: fps,
            vp8Batch: batch,
            authToken: authToken,
            sourceURI: raw
        )
    }

    private static func value(
        _ query: [String: String],
        compact: String,
        long: String
    ) -> String {
        query[compact] ?? query[long] ?? ""
    }

    private static func positiveInt(
        _ raw: String,
        fallback: Int,
        field: String
    ) throws -> Int {
        guard !raw.isEmpty else { return fallback }
        guard let number = Int(raw), number > 0 else {
            throw OlcrtcURIError.invalidNumber(field)
        }
        return number
    }
}
