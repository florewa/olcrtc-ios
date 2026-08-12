import CryptoKit
import Foundation

struct SubscriptionMirror: Codable, Equatable {
    var type: String
    var url: URL
    var key: String

    static func validated(type: String, urlString: String, key: String) throws -> SubscriptionMirror {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedType == "yandex_disk" else {
            throw SubscriptionMirrorError.unsupportedType
        }
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              Self.isYandexHost(url.host) else {
            throw SubscriptionMirrorError.invalidURL
        }
        guard let decodedKey = Data(base64URLEncoded: key), decodedKey.count == 32 else {
            throw SubscriptionMirrorError.invalidKey
        }
        return SubscriptionMirror(type: normalizedType, url: url, key: key)
    }

    fileprivate static func isYandexHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "yandex.ru" || host.hasSuffix(".yandex.ru")
            || host == "yandex.net" || host.hasSuffix(".yandex.net")
            || host == "yadi.sk" || host.hasSuffix(".yadi.sk")
    }
}

enum SubscriptionMirrorError: LocalizedError, Equatable {
    case unsupportedType
    case invalidURL
    case invalidKey
    case invalidEnvelope
    case responseTooLarge
    case invalidPlaintext

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "Поддерживается только зеркало Yandex Disk"
        case .invalidURL: return "Некорректный URL зеркала Yandex Disk"
        case .invalidKey: return "Некорректный 256-битный ключ зеркала"
        case .invalidEnvelope: return "Некорректный формат зашифрованного зеркала"
        case .responseTooLarge: return "Ответ зеркала превышает допустимый размер"
        case .invalidPlaintext: return "Расшифрованная подписка не является UTF-8 текстом"
        }
    }
}

enum SubscriptionMirrorLoader {
    private static let maximumResponseSize = 2 * 1_024 * 1_024

    private struct DownloadResponse: Decodable {
        let href: String
    }

    private struct Envelope: Decodable {
        let type: String
        let v: Int
        let alg: String
        let nonce: String
        let ciphertext: String
    }

    static func load(_ mirror: SubscriptionMirror) async throws -> String {
        var components = URLComponents(string: "https://cloud-api.yandex.net/v1/disk/public/resources/download")
        components?.queryItems = [URLQueryItem(name: "public_key", value: mirror.url.absoluteString)]
        guard let resolveURL = components?.url else { throw SubscriptionMirrorError.invalidURL }

        let resolutionData = try await fetch(resolveURL)
        let resolution = try JSONDecoder().decode(DownloadResponse.self, from: resolutionData)
        guard let downloadURL = URL(string: resolution.href),
              downloadURL.scheme?.lowercased() == "https",
              SubscriptionMirror.isYandexHost(downloadURL.host) else {
            throw SubscriptionMirrorError.invalidURL
        }
        return try decrypt(try await fetch(downloadURL), key: mirror.key)
    }

    static func decrypt(_ data: Data, key: String) throws -> String {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw SubscriptionMirrorError.invalidEnvelope
        }
        guard envelope.type == "olcrtc-sub-mirror",
              envelope.v == 1,
              envelope.alg == "AES-256-GCM",
              let keyData = Data(base64URLEncoded: key), keyData.count == 32,
              let nonceData = Data(base64URLEncoded: envelope.nonce), nonceData.count == 12,
              let sealedData = Data(base64URLEncoded: envelope.ciphertext), sealedData.count >= 16 else {
            throw SubscriptionMirrorError.invalidEnvelope
        }

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let ciphertext = sealedData.dropLast(16)
            let tag = sealedData.suffix(16)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: keyData))
            guard let text = String(data: plaintext, encoding: .utf8) else {
                throw SubscriptionMirrorError.invalidPlaintext
            }
            return text
        } catch let error as SubscriptionMirrorError {
            throw error
        } catch {
            throw SubscriptionMirrorError.invalidEnvelope
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              http.url?.scheme?.lowercased() == "https",
              SubscriptionMirror.isYandexHost(http.url?.host) else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= maximumResponseSize else {
            throw SubscriptionMirrorError.responseTooLarge
        }
        return data
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: normalized)
    }
}
