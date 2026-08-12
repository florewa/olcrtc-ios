import SwiftUI
import UIKit

struct AddProfileView: View {
    @EnvironmentObject private var manager: ProxyManager
    @Environment(\.dismiss) private var dismiss
    @State private var uri = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("olcrtc:// ссылка") {
                    TextEditor(text: $uri)
                        .font(.caption.monospaced())
                        .frame(minHeight: 150)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Вставить") {
                        uri = UIPasteboard.general.string ?? ""
                    }
                }
                Section {
                    Text("Ссылка содержит ключ и client_id. Она будет сохранена в Keychain только на этом устройстве.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Конфигурация")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        manager.addProfile(uri: uri)
                        dismiss()
                    }
                    .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
