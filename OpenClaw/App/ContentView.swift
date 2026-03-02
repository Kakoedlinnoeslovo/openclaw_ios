import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppTheme.self) private var theme
    @State private var showTrialPaywall = false

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: auth.isAuthenticated)
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth && !theme.hasSeenTrialPaywall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showTrialPaywall = true
                }
            }
        }
        .sheet(isPresented: $showTrialPaywall) {
            theme.hasSeenTrialPaywall = true
        } content: {
            PaywallView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppTheme.self) private var theme
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            SkillBrowserView()
                .tabItem {
                    Label("Skills", systemImage: "puzzlepiece.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(theme.accent)
    }
}
