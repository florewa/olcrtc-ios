import Foundation
import UIKit

@MainActor
final class ProxyManager: ObservableObject {
    enum Status: Equatable {
        case stopped
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state = PersistedState()
    @Published var selectedProfileID: UUID?
    @Published private(set) var status: Status = .stopped
    @Published private(set) var notice: String?
    @Published var socksPort = 10_808 {
        didSet {
            state.socksPort = socksPort
            try? persist()
        }
    }

    private let keychain = KeychainStore()
    private let keepAlive = BackgroundKeepAlive()
    private var socksUser = ""
    private var socksPassword = ""
    private var refreshingAll = false

    var profiles: [OlcrtcProfile] {
        state.manualProfiles + state.subscriptions.flatMap(\.profiles)
    }

    var selectedProfile: OlcrtcProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == selectedProfileID })
    }

    var socksURL: String {
        "socks5://\(socksUser):\(socksPassword)@127.0.0.1:\(socksPort)"
    }

    init() {
        do {
            state = try keychain.load()
            socksUser = state.socksUser ?? Self.randomCredential(length: 16)
            socksPassword = state.socksPassword ?? Self.randomCredential(length: 24)
            socksPort = state.socksPort ?? 10_808
            state.socksUser = socksUser
            state.socksPassword = socksPassword
            state.socksPort = socksPort
            try keychain.save(state)
            selectedProfileID = profiles.first?.id
        } catch {
            socksUser = Self.randomCredential(length: 16)
            socksPassword = Self.randomCredential(length: 24)
            notice = error.localizedDescription
        }
    }

    func addProfile(uri: String) {
        do {
            let profile = try OlcrtcURIParser.parse(uri)
            state.manualProfiles.removeAll { $0.sourceURI == profile.sourceURI }
            state.manualProfiles.append(profile)
            selectedProfileID = profile.id
            try persist()
            notice = "Конфигурация добавлена"
        } catch {
            notice = error.localizedDescription
        }
    }

    func removeManualProfile(id: UUID) {
        state.manualProfiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = profiles.first?.id }
        try? persist()
    }

    func addSubscription(name: String, urlString: String) async {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            notice = "Подписка должна использовать HTTPS с действительным сертификатом"
            return
        }
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = state.subscriptions.first(where: { $0.url == url })
            ?? SubscriptionRecord(
                name: requestedName.isEmpty ? (url.host ?? "Подписка") : requestedName,
                url: url
            )
        if !requestedName.isEmpty { record.name = requestedName }
        do {
            record = try await loadSubscription(record)
            state.subscriptions.removeAll { $0.url == url }
            state.subscriptions.append(record)
            selectedProfileID = record.profiles.first?.id ?? selectedProfileID
            try persist()
            notice = "Подписка обновлена: \(record.profiles.count) конфигураций"
        } catch {
            notice = error.localizedDescription
        }
    }

    func refreshSubscription(id: UUID) async {
        guard let index = state.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        do {
            let refreshed = try await loadSubscription(state.subscriptions[index])
            state.subscriptions[index] = refreshed
            try persist()
            notice = "Подписка обновлена"
        } catch {
            notice = error.localizedDescription
        }
    }

    func refreshAllSubscriptionsIfNeeded() async {
        guard !refreshingAll, !state.subscriptions.isEmpty else { return }
        let now = Date()
        guard state.subscriptions.contains(where: { isStale($0, at: now) }) else {
            return
        }

        refreshingAll = true
        defer { refreshingAll = false }
        var updated = state.subscriptions
        var changed = false
        for index in updated.indices where isStale(updated[index], at: now) {
            if let refreshed = try? await loadSubscription(updated[index]) {
                updated[index] = refreshed
                changed = true
            }
        }
        if changed {
            state.subscriptions = updated
            try? persist()
        }
    }

    func resumeBackgroundModeIfConnected() {
        guard status == .connected else { return }
        try? keepAlive.start()
    }

    func removeSubscription(id: UUID) {
        state.subscriptions.removeAll { $0.id == id }
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        try? persist()
    }

    func connect() {
        guard status != .connecting, status != .connected else { return }
        guard let profile = selectedProfile else {
            notice = "Сначала добавьте конфигурацию или подписку"
            return
        }
        guard (1...65_535).contains(socksPort) else {
            notice = "Некорректный SOCKS-порт"
            return
        }

        status = .connecting
        let port = socksPort
        let user = socksUser
        let password = socksPassword
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try OlcrtcBridge.start(profile: profile, port: port, user: user, password: password)
                try await self?.activateBackgroundMode()
                await self?.markConnected()
            } catch {
                await self?.markFailed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        status = .stopped
        keepAlive.stop()
        Task.detached { OlcrtcBridge.stop() }
    }

    func copyForHapp() {
        let credentials = Data("\(socksUser):\(socksPassword)".utf8).base64EncodedString()
        UIPasteboard.general.string = "socks://\(credentials)@127.0.0.1:\(socksPort)#olcRTC"
        notice = "SOCKS-конфигурация скопирована. Добавьте её в Happ"
    }

    func openHappStore() {
        guard let url = URL(string: "https://apps.apple.com/app/id6504287215") else { return }
        UIApplication.shared.open(url)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "olcrtc" else { return }
        if url.host?.lowercased() == "subscription" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let items = (components?.queryItems ?? []).reduce(into: [String: String]()) {
                $0[$1.name] = $1.value ?? ""
            }
            guard let source = items["url"] else {
                notice = "В ссылке отсутствует URL подписки"
                return
            }
            Task { await addSubscription(name: items["name"] ?? "", urlString: source) }
            return
        }
        addProfile(uri: url.absoluteString)
    }

    func clearNotice() {
        notice = nil
    }

    private func loadSubscription(_ source: SubscriptionRecord) async throws -> SubscriptionRecord {
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "OlcrtcIOS.Subscription",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Подписка должна быть в UTF-8"]
            )
        }
        let parsed = SubscriptionParser.parse(text)
        guard !parsed.profiles.isEmpty else {
            let suffix = parsed.rejectedLines.isEmpty
                ? ""
                : " (отклонено строк: \(parsed.rejectedLines.count))"
            throw NSError(
                domain: "OlcrtcIOS.Subscription",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "В подписке нет подходящих конфигураций\(suffix)"]
            )
        }
        var refreshed = source
        refreshed.name = parsed.name ?? source.name
        refreshed.profiles = parsed.profiles.map { incoming in
            var profile = incoming
            if let existing = source.profiles.first(where: { $0.sourceURI == incoming.sourceURI }) {
                profile.id = existing.id
            }
            return profile
        }
        refreshed.lastUpdated = Date()
        if let interval = parsed.refreshInterval.flatMap(parseRefreshInterval) {
            refreshed.refreshIntervalSeconds = interval
        }
        return refreshed
    }

    private func isStale(_ subscription: SubscriptionRecord, at date: Date) -> Bool {
        guard let lastUpdated = subscription.lastUpdated else { return true }
        return date.timeIntervalSince(lastUpdated) >= subscription.refreshIntervalSeconds
    }

    private func parseRefreshInterval(_ raw: String) -> TimeInterval? {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suffix = normalized.last else { return nil }
        let numberPart = normalized.dropLast()
        guard let amount = Double(numberPart), amount > 0 else { return nil }
        let multiplier: TimeInterval
        switch suffix {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3_600
        case "d": multiplier = 86_400
        default: return nil
        }
        return min(max(amount * multiplier, 60), 7 * 86_400)
    }

    private func persist() throws {
        try keychain.save(state)
    }

    private func activateBackgroundMode() throws {
        try keepAlive.start()
    }

    private func markConnected() {
        status = .connected
        notice = "Туннель готов. Теперь добавьте SOCKS в Happ"
    }

    private func markFailed(_ message: String) {
        keepAlive.stop()
        status = .failed(message)
        notice = message
    }

    private static func randomCredential(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
