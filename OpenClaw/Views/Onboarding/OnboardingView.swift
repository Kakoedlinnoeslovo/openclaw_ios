import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomeView {
                withAnimation { currentPage = 1 }
            }
            .tag(0)

            StylePreferenceView {
                withAnimation { currentPage = 2 }
            }
            .tag(1)

            PurposeSelectionView {
                withAnimation { currentPage = 3 }
            }
            .tag(2)

            SignUpView()
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}
