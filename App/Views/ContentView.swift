import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: ProxyManager
    @State private var showAddProfile = false
    @State private var showAddSubscription = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                profilesSection
                subscriptionsSection
                socksSection
                limitationsSection
            }
            .navigationTitle("olcRTC")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Добавить конфигурацию", systemImage: "link") {
                            showAddProfile = true
                        }
                        Button("Добавить подписку", systemImage: "list.bullet.rectangle") {
                            showAddSubscription = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddProfile) {
                AddProfileView()
            }
            .sheet(isPresented: $showAddSubscription) {
                AddSubscriptionView()
            }
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
    }

    private var statusSection: some View {
        Section("Подключение") {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                Spacer()
                if manager.status == .connecting {
                    ProgressView()
                }
            }

            if manager.status == .connected || manager.status == .connecting {
                Button("Остановить", role: .destructive) { manager.disconnect() }
            } else {
                Button("Запустить туннель") { manager.connect() }
                    .disabled(manager.profiles.isEmpty)
            }
        }
    }

    private var profilesSection: some View {
        Section("Конфигурации") {
            if manager.profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.title)
                    Text("Конфигураций пока нет")
                        .font(.headline)
                    Text("После установки сервера вставьте olcrtc:// ссылку или добавьте подписку.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            } else {
                Picker("Активная", selection: $manager.selectedProfileID) {
                    ForEach(manager.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }

                if let profile = manager.selectedProfile {
                    LabeledContent("Провайдер", value: profile.carrier)
                    LabeledContent("Транспорт", value: profile.transport)
                    LabeledContent("Комната", value: abbreviated(profile.roomID))
                    LabeledContent("Клиент", value: abbreviated(profile.clientID))
                }

                ForEach(manager.state.manualProfiles) { profile in
                    HStack {
                        Label(profile.name, systemImage: "link")
                        Spacer()
                        Button(role: .destructive) {
                            manager.removeManualProfile(id: profile.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var subscriptionsSection: some View {
        Section("Подписки") {
            if manager.state.subscriptions.isEmpty {
                Text("Подписок пока нет")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.state.subscriptions) { subscription in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(subscription.name, systemImage: "list.bullet.rectangle")
                        Spacer()
                        Text("\(subscription.profiles.count)")
                            .foregroundStyle(.secondary)
                    }
                    Text(subscription.url.host ?? subscription.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
            }
        }
    }

    private var socksSection: some View {
        Section {
            TextField("SOCKS-порт", value: $manager.socksPort, format: .number)
                .keyboardType(.numberPad)
            Text(manager.socksURL)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Button("Скопировать конфигурацию для Happ") { manager.copyForHapp() }
            Button("Открыть Happ в App Store") { manager.openHappStore() }
        } header: {
            Text("Happ")
        } footer: {
            Text("Сначала запустите olcRTC, затем импортируйте скопированную SOCKS-ссылку в Happ и включите VPN там.")
        }
    }

    private var limitationsSection: some View {
        Section("Важно") {
            Text("Текущая версия olcRTC передаёт TCP. Звонки, игры и приложения, которым обязателен UDP/QUIC, могут не работать.")
            Text("iOS может остановить sideload-приложение после звонка, смены аудиосессии или при нехватке памяти. В таком случае откройте olcRTC и запустите туннель снова.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch manager.status {
        case .stopped: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch manager.status {
        case .stopped: return "Остановлен"
        case .connecting: return "Подключение…"
        case .connected: return "SOCKS готов"
        case let .failed(message): return "Ошибка: \(message)"
        }
    }

    private func abbreviated(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(8))…\(value.suffix(6))"
    }
}
