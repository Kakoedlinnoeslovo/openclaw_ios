import SwiftUI

struct VoiceOrbView: View {
    let state: RealtimeVoiceService.SessionState
    let inputLevel: Float
    let outputLevel: Float
    let accentColors: [Color]

    @State private var breatheScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var pulseOpacity: Double = 0.3

    private let baseSize: CGFloat = 160

    var body: some View {
        ZStack {
            outerRings
            innerOrb
        }
        .frame(width: baseSize * 1.6, height: baseSize * 1.6)
        .onChange(of: state) { _, newState in
            updateAnimations(for: newState)
        }
        .onAppear {
            updateAnimations(for: state)
        }
    }

    // MARK: - Outer Rings

    private var outerRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: accentColors.map { $0.opacity(0.15 - Double(ring) * 0.04) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: baseSize + CGFloat(ring) * 36,
                           height: baseSize + CGFloat(ring) * 36)
                    .scaleEffect(ringScale(for: ring))
                    .opacity(ringOpacity(for: ring))
            }
        }
    }

    // MARK: - Inner Orb

    private var innerOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentColors.first?.opacity(0.4) ?? .blue.opacity(0.4),
                            accentColors.last?.opacity(0.15) ?? .purple.opacity(0.15),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: baseSize / 2
                    )
                )
                .frame(width: baseSize, height: baseSize)
                .scaleEffect(breatheScale)

            Circle()
                .fill(
                    LinearGradient(
                        colors: accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: baseSize * 0.55, height: baseSize * 0.55)
                .scaleEffect(coreScale)
                .shadow(color: accentColors.first?.opacity(0.5) ?? .blue.opacity(0.5),
                        radius: 20, y: 4)

            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: baseSize * 0.25, height: baseSize * 0.25)
                .offset(x: -baseSize * 0.08, y: -baseSize * 0.08)
                .scaleEffect(coreScale)

            if state == .connecting {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }

            if state.isToolRunning {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: true)
            }

            if state.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
        }
        .rotationEffect(.degrees(rotationAngle))
    }

    // MARK: - Computed scales

    private var coreScale: CGFloat {
        switch state {
        case .idle:
            return breatheScale
        case .connecting:
            return breatheScale * 0.9
        case .listening:
            return 1.0 + CGFloat(inputLevel) * 0.35
        case .thinking:
            return breatheScale * 0.95
        case .speaking:
            return 1.0 + CGFloat(outputLevel) * 0.4
        case .toolRunning:
            return breatheScale * 0.98
        case .error:
            return 0.85
        }
    }

    private func ringScale(for ring: Int) -> CGFloat {
        let base: CGFloat = 1.0
        switch state {
        case .listening:
            let offset = CGFloat(ring) * 0.05
            return base + CGFloat(inputLevel) * (0.12 + offset)
        case .speaking:
            let offset = CGFloat(ring) * 0.06
            return base + CGFloat(outputLevel) * (0.15 + offset)
        case .thinking, .toolRunning:
            return breatheScale + CGFloat(ring) * 0.01
        default:
            return base
        }
    }

    private func ringOpacity(for ring: Int) -> Double {
        switch state {
        case .idle, .error:
            return 0.1
        case .connecting:
            return pulseOpacity - Double(ring) * 0.05
        case .listening:
            return 0.2 + Double(inputLevel) * 0.4 - Double(ring) * 0.06
        case .speaking:
            return 0.25 + Double(outputLevel) * 0.5 - Double(ring) * 0.08
        case .thinking, .toolRunning:
            return pulseOpacity - Double(ring) * 0.04
        }
    }

    // MARK: - Animations

    private func updateAnimations(for newState: RealtimeVoiceService.SessionState) {
        switch newState {
        case .idle:
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breatheScale = 1.05
            }
            withAnimation(.linear(duration: 0)) {
                rotationAngle = 0
                pulseOpacity = 0.3
            }

        case .connecting:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                breatheScale = 1.08
                pulseOpacity = 0.5
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }

        case .listening:
            withAnimation(.linear(duration: 0.1)) {
                breatheScale = 1.0
                pulseOpacity = 0.3
            }

        case .thinking:
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breatheScale = 1.06
                pulseOpacity = 0.45
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotationAngle += 360
            }

        case .speaking:
            withAnimation(.linear(duration: 0.1)) {
                breatheScale = 1.0
                pulseOpacity = 0.4
            }

        case .toolRunning:
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breatheScale = 1.08
                pulseOpacity = 0.5
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                rotationAngle += 360
            }

        case .error:
            withAnimation(.easeInOut(duration: 0.3)) {
                breatheScale = 0.92
                pulseOpacity = 0.15
            }
        }
    }
}
