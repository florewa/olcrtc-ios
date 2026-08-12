import Foundation

struct ParsedSubscription: Equatable {
    var name: String?
    var refreshInterval: String?
    var profiles: [OlcrtcProfile]
    var rejectedLines: [String]
}

enum SubscriptionParser {
    static func parse(_ text: String) -> ParsedSubscription {
        var name: String?
        var refresh: String?
        var profiles: [OlcrtcProfile] = []
        var rejected: [String] = []

        for sourceLine in text.components(separatedBy: .newlines) {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.lowercased().hasPrefix("#name:") {
                name = metadataValue(line)
                continue
            }
            if line.lowercased().hasPrefix("#refresh:") {
                refresh = metadataValue(line)
                continue
            }
            if line.hasPrefix("#") { continue }
            guard line.lowercased().hasPrefix("olcrtc://") else { continue }

            do {
                profiles.append(try OlcrtcURIParser.parse(line))
            } catch {
                rejected.append(line)
            }
        }

        return ParsedSubscription(
            name: name,
            refreshInterval: refresh,
            profiles: profiles,
            rejectedLines: rejected
        )
    }

    private static func metadataValue(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let value = String(line[line.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
