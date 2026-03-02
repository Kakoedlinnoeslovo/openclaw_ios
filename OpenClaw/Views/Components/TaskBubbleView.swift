import SwiftUI

struct TaskBubbleView: View {
    @Environment(AppTheme.self) private var theme
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            userBubble

            if let output = task.output, !output.isEmpty {
                agentBubble(output)
            } else if task.status == .running || task.status == .queued {
                loadingBubble
            } else if task.status == .failed {
                errorBubble
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)

            Text(task.input)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: theme.accentGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(ChatBubbleShape(isUser: true))
        }
    }

    private func agentBubble(_ text: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .textSelection(.enabled)

                if let tokens = task.tokensUsed {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                        Text("\(tokens) tokens")
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(ChatBubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
    }

    private var loadingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                TypingIndicator()
                Text(task.status == .queued ? "Queued" : "Thinking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(ChatBubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
    }

    private var errorBubble: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(task.output ?? "Task failed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.red.opacity(0.08))
            .clipShape(ChatBubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Chat Bubble Shape

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailRadius: CGFloat = 6

        var path = Path()

        if isUser {
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailRadius, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            path.move(to: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - tailRadius - 4, y: rect.maxY),
                control: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY)
            )
        } else {
            path.addRoundedRect(
                in: CGRect(x: tailRadius, y: rect.minY, width: rect.width - tailRadius, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            path.move(to: CGPoint(x: tailRadius, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.maxY),
                control: CGPoint(x: tailRadius, y: rect.maxY)
            )
            path.addQuadCurve(
                to: CGPoint(x: tailRadius + 4, y: rect.maxY),
                control: CGPoint(x: tailRadius, y: rect.maxY)
            )
        }

        return path
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @Environment(AppTheme.self) private var theme
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(theme.accent.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .offset(y: animationOffset(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func animationOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        return sin((phase + delay) * .pi) * -4
    }
}
