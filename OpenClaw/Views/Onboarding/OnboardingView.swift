import SwiftUI

struct OnboardingView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppTheme.self) private var theme

    @AppStorage("onboarding.preferred_name") private var preferredName = ""
    @State private var step = 0
    @State private var useCases: Set<String> = []
    @State private var interests: Set<String> = []

    var body: some View {
        ZStack {
            OnboardingPalette.background.ignoresSafeArea()
            OnboardingSpiralBackground(focal: spiralFocal(for: step))
                .ignoresSafeArea()

            Group {
                switch step {
                case 0:
                    OnboardingWelcomeStep { step = 1 }
                case 1:
                    OnboardingNameStep(
                        name: $preferredName,
                        onContinue: { step = 2 },
                        onSkip: { step = 2 }
                    )
                case 2:
                    OnboardingUseCasesStep(
                        selection: $useCases,
                        onContinue: { step = 3 },
                        onSkip: { step = 3 }
                    )
                case 3:
                    OnboardingInterestsStep(
                        selection: $interests,
                        onContinue: { step = 4 },
                        onSkip: { step = 4 }
                    )
                case 4:
                    OnboardingLoadingSocialStep { step = 5 }
                case 5:
                    OnboardingAllSetStep { step = 6 }
                case 6:
                    OnboardingAppleSignInStep(preferredDisplayName: preferredName) {
                        step = 7
                    }
                default:
                    PaywallView(
                        embeddedInFunnel: true,
                        onFunnelFinished: {
                            OnboardingFunnel.isComplete = true
                            theme.hasSeenTrialPaywall = true
                        }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if auth.isAuthenticated {
                step = 7
            }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth, step == 6 {
                step = 7
            }
        }
    }

    private func spiralFocal(for step: Int) -> OnboardingSpiralFocal {
        switch step {
        case 4, 5, 6: return .center
        default: return .upper
        }
    }
}
