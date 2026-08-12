import SwiftUI

@main
struct OlcrtcIOSApp: App {
    @StateObject private var manager = ProxyManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .onOpenURL { manager.handleDeepLink($0) }
                .task { await manager.refreshAllSubscriptionsIfNeeded() }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    manager.resumeBackgroundModeIfConnected()
                    Task { await manager.refreshAllSubscriptionsIfNeeded() }
                }
        }
    }
}
