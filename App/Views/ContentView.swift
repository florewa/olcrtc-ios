import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: ProxyManager
    @State private var showAddProfile = false
    @State private var showAddSubscription = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        statusCard
                        profileCard
                        happCard
                        subscriptionsCard
                        diagnosticsCard
                        limitationsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("olcRTC")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { addMenu }
            .sheet(isPresented: $showAddProfile) { AddProfileView() }
            .sheet(isPresented: $showAddSubscription) { AddSubscriptionView() }
            .alert(
                "olcRTC",
                isPresented: Binding(
                    get: { manager.notice != nil },
                    set: { if !$0 { manager.clearNotice() } }
                )
            ) {
                Button("OK") { manager.clearNotice() }
            } message: {
                Text(manager.notice ?? "")
            }
        }
        .tint(.cyan)
    }

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.20),
                    Color.cyan.opacity(0.09),
                    Color(.systemGroupedBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 150, y: -330)
            Circle()
                .fill(Color.purple.opacity(0.14))
                .frame(width: 300, height: 300)
                .blur(radius: 85)
                .offset(x: -180, y: 300)
        }
    }

    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Добавить конфигурацию", systemImage: "link.badge.plus") {
                    showAddProfile = true
                }
                Button("Добавить подписку", systemImage: "text.badge.plus") {
                    showAddSubscription = true
                }
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Добавить")
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.17))
                            .frame(width: 52, height: 52)
                        Image(systemName: statusSymbol)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.title3.weight(.semibold))
                        Text(statusSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let health = manager.lastHealth, manager.status.keepsTunnelActive {
                    HStack(spacing: 10) {
                        HealthChip(
                            icon: "waveform.path.ecg",
                            text: health.lastRTTMillis > 0 ? "\(health.lastRTTMillis) мс" : "проверка"
                        )
                        HealthChip(icon: "arrow.triangle.2.circlepath", text: "\(health.reconnects)")
                        HealthChip(icon: "network", text: health.missedPongs == 0 ? "стабильно" : "сбои: \(health.missedPongs)")
                    }
                }

                if manager.status.canStop {
                    Button(role: .destructive) { manager.disconnect() } label: {
                        Label("Остановить туннель", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button { manager.connect() } label: {
                        Label("Запустить туннель", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(manager.profiles.isEmpty)
                }
            }
        }
    }

    private var profileCard: some View {
        GlassCard(title: "Активная конфигурация", symbol: "point.3.connected.trianglepath.dotted") {
            if manager.profiles.isEmpty {
                EmptyCardRow(
                    symbol: "network.slash",
                    title: "Конфигураций пока нет",
                    subtitle: "Добавьте olcrtc:// ссылку или подписку кнопкой «+»."
                )
            } else {
                Picker("Конфигурация", selection: $manager.selectedProfileID) {
                    ForEach(manager.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(manager.status.canStop)

                if let profile = manager.selectedProfile {
                    Divider().opacity(0.5)
                    VStack(spacing: 10) {
                        DetailRow(label: "Провайдер", value: profile.carrier.uppercased())
                        DetailRow(label: "Транспорт", value: profile.transport)
                        DetailRow(label: "Комната", value: abbreviated(profile.roomID))
                        DetailRow(label: "Клиент", value: abbreviated(profile.clientID))
                    }
                }

                if !manager.state.manualProfiles.isEmpty {
                    Divider().opacity(0.5)
                    ForEach(manager.state.manualProfiles) { profile in
                        HStack {
                            Label(profile.name, systemImage: "link")
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                manager.removeManualProfile(id: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(manager.status.canStop)
                        }
                    }
                }
            }
        }
    }

    private var happCard: some View {
        GlassCard(title: "Happ", symbol: "switch.2") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: manager.needsHappImport ? "arrow.down.doc.fill" : "checkmark.circle.fill")
                        .foregroundStyle(manager.needsHappImport ? .orange : .green)
                    Text(manager.needsHappImport ? "Нужен однократный импорт" : "Конфигурация уже импортировалась")
                        .font(.subheadline.weight(.medium))
                }

                TextField("SOCKS-порт", value: $manager.socksPort, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .disabled(manager.status.canStop)

                if manager.needsHappImport {
                    Button { manager.copyForHapp() } label: {
                        Label("Скопировать для ИМПОРТА", systemImage: "doc.on.doc.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button { manager.openHapp() } label: {
                        Label("Перейти в Happ", systemImage: "arrow.up.forward.app.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Скопировать конфигурацию заново") { manager.copyForHapp() }
                        .font(.footnote)
                }

                Text(
                    manager.needsHappImport
                        ? "Сначала запустите olcRTC, затем вставьте ссылку через «+» в Happ и выберите импорт из буфера."
                        : "При следующих запусках импортировать ничего не нужно: запустите olcRTC и включите сохранённый туннель в Happ."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var subscriptionsCard: some View {
        GlassCard(title: "Подписки", symbol: "list.bullet.rectangle.portrait") {
            if manager.state.subscriptions.isEmpty {
                EmptyCardRow(
                    symbol: "tray",
                    title: "Подписок пока нет",
                    subtitle: "Можно продолжать использовать добавленные вручную конфигурации."
                )
            } else {
                VStack(spacing: 14) {
                    ForEach(manager.state.subscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(subscription.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(subscription.profiles.count)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(.secondary.opacity(0.12), in: Capsule())
                            }
                            Text(subscription.url.host ?? subscription.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if subscription.mirror != nil {
                                Label("Зашифрованное зеркало Yandex Disk", systemImage: "lock.shield")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Обновить") {
                                    Task { await manager.refreshSubscription(id: subscription.id) }
                                }
                                Button("Удалить", role: .destructive) {
                                    manager.removeSubscription(id: subscription.id)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        if subscription.id != manager.state.subscriptions.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var diagnosticsCard: some View {
        if manager.lastHealth != nil || !manager.recentEvents.isEmpty {
            GlassCard(title: "Диагностика", symbol: "stethoscope") {
                VStack(alignment: .leading, spacing: 12) {
                    if let health = manager.lastHealth {
                        if let lastPong = health.lastPongDate {
                            HStack {
                                Text("Последний ответ")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lastPong, style: .relative)
                            }
                            .font(.subheadline)
                        }
                        DetailRow(label: "Переподключений ядра", value: "\(health.reconnects)")
                    }
                    if let reason = manager.lastRecoveryReason {
                        Label(reason, systemImage: "wrench.and.screwdriver")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    ForEach(manager.recentEvents.prefix(4)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.date, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(event.message)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var limitationsCard: some View {
        GlassCard(title: "Важно", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: 9) {
                Label("TCP и UDP/QUIC поддерживаются.", systemImage: "checkmark.circle")
                Label(
                    "Watchdog проверяет настоящий контрольный канал и сам перезапускает ядро после устойчивого обрыва.",
                    systemImage: "heart.text.square"
                )
                Label(
                    "iOS всё равно может выгрузить sideload-приложение при нехватке памяти. После полного закрытия приложения запустите его снова.",
                    systemImage: "iphone.and.arrow.forward"
                )
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch manager.status {
        case .stopped: return .secondary
        case .connecting, .checking: return .orange
        case .connected: return .green
        case .recovering: return .cyan
        case .failed: return .red
        }
    }

    private var statusSymbol: String {
        switch manager.status {
        case .stopped: return "circle"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .connected: return "checkmark"
        case .checking: return "waveform.path.ecg"
        case .recovering: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark"
        }
    }

    private var statusTitle: String {
        switch manager.status {
        case .stopped: return "Туннель остановлен"
        case .connecting: return "Подключаемся…"
        case .connected: return "Соединение защищено"
        case .checking: return "Проверяем связь…"
        case let .recovering(attempt): return "Восстанавливаем · попытка \(attempt)"
        case .failed: return "Не удалось подключиться"
        }
    }

    private var statusSubtitle: String {
        switch manager.status {
        case .stopped:
            return manager.selectedProfile?.name ?? "Выберите конфигурацию"
        case .connecting:
            return manager.selectedProfile?.name ?? "Создаём RTC-канал"
        case .connected:
            return "SOCKS 127.0.0.1:\(manager.socksPort) готов"
        case .checking:
            return "Watchdog ждёт ответ сервера"
        case .recovering:
            return manager.lastRecoveryReason ?? "Пересоздаём RTC-канал"
        case let .failed(message):
            return message
        }
    }

    private var showsProgress: Bool {
        switch manager.status {
        case .connecting, .checking, .recovering: return true
        case .stopped, .connected, .failed: return false
        }
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(8))…\(value.suffix(6))"
    }
}

private struct GlassCard<Content: View>: View {
    private let title: String?
    private let symbol: String?
    private let content: Content

    init(
        title: String? = nil,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let title {
                Label(title, systemImage: symbol ?? "circle")
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .olcrtcGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct HealthChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.secondary.opacity(0.10), in: Capsule())
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct EmptyCardRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func olcrtcGlass<S: InsettableShape>(in shape: S) -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            fallbackGlass(in: shape)
        }
#else
        fallbackGlass(in: shape)
#endif
    }

    func fallbackGlass<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}
