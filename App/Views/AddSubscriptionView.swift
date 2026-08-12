import SwiftUI
import UIKit

struct AddSubscriptionView: View {
    @EnvironmentObject private var manager: ProxyManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название (необязательно)", text: $name)
                TextField("https://server.example/sub/name", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Вставить URL") {
                    url = UIPasteboard.general.string ?? ""
                }
            }
            .navigationTitle("Подписка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        loading = true
                        Task {
                            await manager.addSubscription(name: name, urlString: url)
                            loading = false
                            dismiss()
                        }
                    }
                    .disabled(loading || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay { if loading { ProgressView() } }
        }
    }
}
