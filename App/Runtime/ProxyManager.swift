import Foundation
import UIKit

@MainActor
final class ProxyManager: ObservableObject {
    enum Status: Equatable {
        case stopped
        case connecting
        case connected
        case checking
        case recovering(Int)
        case failed(String)

        var keepsTunnelActive: Bool {
            switch self {
            case .connected, .checking, .recovering:
                return true
            case .stopped, .connecting, .failed:
                return false
            }
        }

        var canStop: Bool {
            switch self {
            case .connecting, .connected, .checking, .recovering:
                return true
            case .stopped, .failed:
                return false
            }
        }
    }

    @Published private(set) var state = PersistedState()
    @Published var selectedProfileID: UUID? {
        didSet {
            guard !restoringState, selectedProfileID != oldValue else { return }
            state.selectedProfileID = selectedProfileID
            try? persist()
        }
    }
    @Published private(set) var status: Status = .stopped
    @Published private(set) var notice: String?
    @Published private(set) var lastHealth: TunnelHealthSnapshot?
    @Published private(set) var lastRecoveryReason: String?
    @Published private(set) var recentEvents: [TunnelEvent] = []
    @Published var socksPort = 18_080 {
        didSet {
            guard !restoringState else { return }
            state.socksPort = socksPort
            try? persist()
        }
    }

    private let keychain = KeychainStore()
    private let keepAlive = BackgroundKeepAlive()
    private var socksUser = ""
    private var socksPassword = ""
    private var refreshingAll = false
    private var restoringState = true
    private var watchdogTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var connectionGeneration = UUID()
    private var activeProfile: OlcrtcProfile?
    private var consecutiveHealthFailures = 0

    private let watchdogInterval: Duration = .seconds(12)
    private let watchdogFailureThreshold = 2

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

    var needsHappImport: Bool {
        state.hasImportedHappConfiguration != true
    }

    init() {
        do {
            state = try keychain.load()
            socksUser = state.socksUser ?? Self.randomCredential(length: 16)
            socksPassword = state.socksPassword ?? Self.randomCredential(length: 24)
            // Happ/Xray reserves 10808 for its own local SOCKS inbound. Older
            // olcRTC builds used the same port, so migrate persisted values.
            socksPort = state.socksPort == 10_808 ? 18_080 : (state.socksPort ?? 18_080)
            state.socksUser = socksUser
            state.socksPassword = socksPassword
            state.socksPort = socksPort

            if let saved = state.selectedProfileID,
               profiles.contains(where: { $0.id == saved }) {
                selectedProfileID = saved
            } else {
                selectedProfileID = profiles.first?.id
                state.selectedProfileID = selectedProfileID
            }
            try keychain.save(state)
        } catch {
            socksUser = Self.randomCredential(length: 16)
            socksPassword = Self.randomCredential(length: 24)
            notice = error.localizedDescription
        }
        restoringState = false
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

    func addSubscription(name: String, urlString: String, mirror: SubscriptionMirror? = nil) async {
        let normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bootstrapURL = URL(string: normalizedURL),
           bootstrapURL.scheme?.lowercased() == "olcrtc",
           bootstrapURL.host?.lowercased() == "subscription" {
            await addSubscription(from: bootstrapURL, fallbackName: name)
            return
        }

        guard let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            notice = "Введите HTTPS-ссылку или bootstrap-ссылку olcrtc://subscription"
            return
        }
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = state.subscriptions.first(where: { $0.url == url })
            ?? SubscriptionRecord(
                name: requestedName.isEmpty ? (url.host ?? "Подписка") : requestedName,
                url: url
            )
        if !requestedName.isEmpty { record.name = requestedName }
        if let mirror { record.mirror = mirror }
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
            if !profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = refreshed.profiles.first?.id ?? profiles.first?.id
            }
            try persist()
            notice = "Подписка обновлена"
        } catch {
            notice = error.localizedDescription
        }
    }

    func refreshAllSubscriptionsIfNeeded() async {
        guard !refreshingAll, !state.subscriptions.isEmpty else { return }
        let now = Date()
        guard state.subscriptions.contains(where: { isStale($0, at: now) }) else { return }

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
            if !profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = profiles.first?.id
            }
            try? persist()
        }
    }

    func resumeBackgroundModeIfConnected() {
        guard status.keepsTunnelActive else { return }
        try? keepAlive.start()
        evaluateHealth(source: "возврат из фона")
    }

    func removeSubscription(id: UUID) {
        state.subscriptions.removeAll { $0.id == id }
        if !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        try? persist()
    }

    func connect() {
        guard status != .connecting, !status.keepsTunnelActive else { return }
        guard let profile = selectedProfile else {
            notice = "Сначала добавьте конфигурацию или подписку"
            return
        }
        guard (1...65_535).contains(socksPort) else {
            notice = "Некорректный SOCKS-порт"
            return
        }

        activeProfile = profile
        selectedProfileID = profile.id
        startCore(profile: profile, recovered: false)
    }

    func disconnect() {
        connectionGeneration = UUID()
        watchdogTask?.cancel()
        watchdogTask = nil
        operationTask?.cancel()
        operationTask = nil
        consecutiveHealthFailures = 0
        activeProfile = nil
        lastHealth = nil
        status = .stopped
        keepAlive.stop()
        appendEvent("Туннель остановлен пользователем")
        Task.detached { OlcrtcBridge.stop() }
    }

    func copyForHapp() {
        let credentials = Data("\(socksUser):\(socksPassword)".utf8).base64EncodedString()
        UIPasteboard.general.string = "socks://\(credentials)@127.0.0.1:\(socksPort)#olcRTC"

        if needsHappImport {
            state.hasImportedHappConfiguration = true
            try? persist()
            notice = "Ссылка скопирована. Откройте Happ, нажмите «+» и именно ИМПОРТИРУЙТЕ конфигурацию из буфера. Это требуется только один раз."
        } else {
            notice = "Ссылка скопирована заново. Повторный импорт нужен только после удаления конфигурации в Happ или смены SOCKS-порта."
        }
    }

    func openHapp() {
        if let appURL = URL(string: "happ://"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
            return
        }
        guard let storeURL = URL(string: "https://apps.apple.com/app/id6504287215") else { return }
        UIApplication.shared.open(storeURL)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "olcrtc" else { return }
        if url.host?.lowercased() == "subscription" {
            Task { await addSubscription(from: url) }
            return
        }
        addProfile(uri: url.absoluteString)
    }

    func clearNotice() {
        notice = nil
    }

    private func startCore(profile: OlcrtcProfile, recovered: Bool) {
        watchdogTask?.cancel()
        watchdogTask = nil
        consecutiveHealthFailures = 0
        status = recovered ? .recovering(1) : .connecting
        let generation = UUID()
        connectionGeneration = generation
        let port = socksPort
        let user = socksUser
        let password = socksPassword
        appendEvent(recovered ? "Перезапуск ядра olcRTC" : "Подключение: \(profile.name)")

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try OlcrtcBridge.start(profile: profile, port: port, user: user, password: password)
                await self?.connectionSucceeded(generation: generation, recovered: recovered)
            } catch {
                await self?.connectionFailed(error.localizedDescription, generation: generation)
            }
        }
    }

    private func connectionSucceeded(generation: UUID, recovered: Bool) {
        guard connectionGeneration == generation else {
            Task.detached { OlcrtcBridge.stop() }
            return
        }
        operationTask = nil
        do {
            try keepAlive.start()
        } catch {
            connectionFailed(error.localizedDescription, generation: generation)
            return
        }
        status = .connected
        consecutiveHealthFailures = 0
        appendEvent(recovered ? "Соединение восстановлено автоматически" : "Туннель готов")
        startWatchdog()

        if recovered {
            notice = "Соединение восстановлено автоматически. Happ должен переподключиться; если трафик не пошёл, выключите и снова включите туннель в Happ."
        } else if needsHappImport {
            notice = "Туннель готов. Скопируйте конфигурацию ниже и именно ИМПОРТИРУЙТЕ её в Happ — это потребуется только один раз."
        } else {
            notice = "Туннель готов. Перейдите в Happ и включите сохранённую конфигурацию olcRTC."
        }
    }

    private func connectionFailed(_ message: String, generation: UUID) {
        guard connectionGeneration == generation else { return }
        operationTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        keepAlive.stop()
        status = .failed(message)
        appendEvent("Ошибка подключения: \(message)")
        notice = message
        Task.detached { OlcrtcBridge.stop() }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.watchdogInterval ?? .seconds(12))
                guard !Task.isCancelled, let self else { return }
                self.evaluateHealth(source: "watchdog")
            }
        }
    }

    private func evaluateHealth(source: String) {
        guard status == .connected || status == .checking else { return }
        do {
            let health = try OlcrtcBridge.health()
            lastHealth = health
            switch health.watchdogVerdict() {
            case .healthy, .warmingUp:
                consecutiveHealthFailures = 0
                if status == .checking { status = .connected }
            case let .unhealthy(reason):
                registerHealthFailure(reason: reason, source: source)
            }
        } catch {
            registerHealthFailure(reason: "не удалось прочитать состояние ядра", source: source)
        }
    }

    private func registerHealthFailure(reason: String, source: String) {
        consecutiveHealthFailures += 1
        status = .checking
        if consecutiveHealthFailures == 1 {
            appendEvent("Проверка связи (\(source)): \(reason)")
        }
        guard consecutiveHealthFailures >= watchdogFailureThreshold else { return }
        recover(reason: reason)
    }

    private func recover(reason: String) {
        guard let profile = activeProfile else {
            status = .failed(reason)
            return
        }
        watchdogTask?.cancel()
        watchdogTask = nil
        lastRecoveryReason = reason
        consecutiveHealthFailures = 0
        let generation = UUID()
        connectionGeneration = generation
        let port = socksPort
        let user = socksUser
        let password = socksPassword
        appendEvent("Автовосстановление: \(reason)")

        operationTask = Task.detached(priority: .userInitiated) { [weak self] in
            var lastError = reason
            for attempt in 1...3 {
                guard !Task.isCancelled else { return }
                await self?.markRecoveryAttempt(attempt, generation: generation)
                OlcrtcBridge.stop()
                try? await Task.sleep(for: .seconds(attempt == 1 ? 1 : attempt * 2))
                do {
                    try OlcrtcBridge.start(profile: profile, port: port, user: user, password: password)
                    await self?.connectionSucceeded(generation: generation, recovered: true)
                    return
                } catch {
                    lastError = error.localizedDescription
                    await self?.appendRecoveryFailure(attempt: attempt, message: lastError, generation: generation)
                }
            }
            await self?.connectionFailed("Автовосстановление не удалось: \(lastError)", generation: generation)
        }
    }

    private func markRecoveryAttempt(_ attempt: Int, generation: UUID) {
        guard connectionGeneration == generation else { return }
        status = .recovering(attempt)
    }

    private func appendRecoveryFailure(attempt: Int, message: String, generation: UUID) {
        guard connectionGeneration == generation else { return }
        appendEvent("Попытка \(attempt) не удалась: \(message)")
    }

    private func appendEvent(_ message: String) {
        recentEvents.insert(TunnelEvent(date: Date(), message: message), at: 0)
        if recentEvents.count > 12 {
            recentEvents.removeLast(recentEvents.count - 12)
        }
    }

    private func loadSubscription(_ source: SubscriptionRecord) async throws -> SubscriptionRecord {
        do {
            return try refreshedSubscription(source, text: try await loadPlainSubscription(source.url))
        } catch {
            guard let mirror = source.mirror else { throw error }
            return try refreshedSubscription(source, text: try await SubscriptionMirrorLoader.load(mirror))
        }
    }

    private func addSubscription(from bootstrapURL: URL, fallbackName: String = "") async {
        let components = URLComponents(url: bootstrapURL, resolvingAgainstBaseURL: false)
        let items = (components?.queryItems ?? []).reduce(into: [String: String]()) {
            $0[$1.name] = $1.value ?? ""
        }
        guard let source = items["url"], !source.isEmpty else {
            notice = "В bootstrap-ссылке отсутствует URL подписки"
            return
        }
        do {
            let mirror: SubscriptionMirror?
            if let mirrorURL = items["mirror_url"], let mirrorKey = items["mirror_key"] {
                mirror = try SubscriptionMirror.validated(
                    type: items["mirror_type"] ?? "yandex_disk",
                    urlString: mirrorURL,
                    key: mirrorKey
                )
            } else {
                mirror = nil
            }
            let requestedName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
            await addSubscription(
                name: requestedName.isEmpty ? (items["name"] ?? "") : requestedName,
                urlString: source,
                mirror: mirror
            )
        } catch {
            notice = error.localizedDescription
        }
    }

    private func refreshedSubscription(_ source: SubscriptionRecord, text: String) throws -> SubscriptionRecord {
        let parsed = SubscriptionParser.parse(text)
        guard !parsed.profiles.isEmpty else {
            let suffix = parsed.rejectedLines.isEmpty ? "" : " (отклонено строк: \(parsed.rejectedLines.count))"
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

    private func loadPlainSubscription(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
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
        return text
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

    private static func randomCredential(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
