import SwiftUI

@main
struct OpenClawApp: App {
    @State private var authService = AuthService.shared
    @State private var subscriptionService = SubscriptionService.shared
    @State private var appTheme = AppTheme.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(subscriptionService)
                .environment(appTheme)
                .task {
                    await subscriptionService.loadProducts()
                    await subscriptionService.updateSubscriptionStatus()
                }
        }
    }
}
