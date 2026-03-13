import SwiftUI
import AVFoundation

struct VoiceModeView: View {
    let agent: Agent
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme
    @Environment(SubscriptionService.self) private var subscription
    @State private var voiceService = RealtimeVoiceService()
    @State private var hasStarted = false
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                Spacer()
                agentInfo
                Spacer()
                orbSection
                Spacer()
                statusSection
                Spacer()
                transcriptSection
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .alert("Microphone Access Required",
               isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("OpenClaw needs microphone access for voice conversations. Please enable it in Settings.")
        }
        .task {
            await beginSession()
        }
        .onDisappear {
            voiceService.endSession()
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black

            RadialGradient(
                colors: [
                    theme.accent.opacity(backgroundGlow),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }

    private var backgroundGlow: Double {
        switch voiceService.state {
        case .speaking: 0.12
        case .listening: 0.06
        case .thinking: 0.08
        case .toolRunning: 0.10
        case .error: 0.03
        default: 0.04
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                voiceService.endSession()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()

            timerLabel

            Spacer()

            muteButton
        }
    }

    private var timerLabel: some View {
        let remaining = voiceService.maxSessionSeconds - voiceService.elapsedSeconds
        let minutes = voiceService.elapsedSeconds / 60
        let seconds = voiceService.elapsedSeconds % 60
        let isLow = remaining <= 60 && remaining > 0

        return Text(String(format: "%d:%02d", minutes, seconds))
            .font(.system(size: 15, weight: .medium).monospacedDigit())
            .foregroundStyle(isLow ? .red.opacity(0.8) : .white.opacity(0.5))
            .opacity(voiceService.state.isActive ? 1 : 0)
    }

    private var muteButton: some View {
        Button {
            voiceService.toggleMute()
        } label: {
            Image(systemName: voiceService.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(voiceService.isMuted ? .red : .white.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(voiceService.isMuted ? .red.opacity(0.2) : .white.opacity(0.1))
                .clipShape(Circle())
        }
        .opacity(voiceService.state.isActive ? 1 : 0)
        .disabled(!voiceService.state.isActive)
    }

    // MARK: - Agent info

    private var agentInfo: some View {
        VStack(spacing: 8) {
            Image(systemName: agent.persona.icon)
                .font(.system(size: 24))
                .foregroundStyle(theme.accent)

            Text(agent.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text(agent.model.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    // MARK: - Orb

    private var orbSection: some View {
        VoiceOrbView(
            state: voiceService.state,
            inputLevel: voiceService.inputLevel,
            outputLevel: voiceService.outputLevel,
            accentColors: theme.accentGradient
        )
        .animation(.easeOut(duration: 0.08), value: voiceService.inputLevel)
        .animation(.easeOut(duration: 0.08), value: voiceService.outputLevel)
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 8) {
            if voiceService.state == .connecting {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .scaleEffect(0.8)
            }

            Text(statusText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .animation(.easeInOut(duration: 0.3), value: voiceService.state)
    }

    private var statusText: String {
        if voiceService.isMuted && voiceService.state.isActive {
            return "Muted"
        }
        return voiceService.state.statusText
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(spacing: 12) {
            if !voiceService.agentTranscript.isEmpty {
                Text(voiceService.agentTranscript)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !voiceService.userTranscript.isEmpty {
                Text(voiceService.userTranscript)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 80)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: voiceService.agentTranscript)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            if voiceService.state.isError {
                Button {
                    hasStarted = false
                    Task { await beginSession() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Button {
                voiceService.endSession()
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.red)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.4), radius: 12, y: 4)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Session management

    private func beginSession() async {
        guard !hasStarted else { return }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micGranted else {
            showPermissionAlert = true
            return
        }

        hasStarted = true
        voiceService.maxSessionSeconds = subscription.currentTier == .free ? 300 : 900

        do {
            try await voiceService.startSession(agentId: agent.id)
        } catch {
            voiceService.state = .error(error.localizedDescription)
        }
    }
}
