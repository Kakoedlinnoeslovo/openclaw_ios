import SwiftUI

struct StylePreferenceView: View {
    @Environment(AppTheme.self) private var theme
    let onContinue: () -> Void

    @State private var selected: AppTheme.Style?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Choose your vibe")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("We'll personalize the experience for you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                styleCard(
                    style: .soft,
                    title: "Soft & Elegant",
                    subtitle: "Warm tones, refined feel",
                    colors: [Color(red: 0.82, green: 0.52, blue: 0.56), Color(red: 0.92, green: 0.68, blue: 0.62)],
                    icon: "heart.fill",
                    bgColor: Color(red: 0.98, green: 0.95, blue: 0.94)
                )

                styleCard(
                    style: .bold,
                    title: "Bold & Precise",
                    subtitle: "Dark tones, sharp lines",
                    colors: [.blue, .indigo],
                    icon: "diamond.fill",
                    bgColor: Color(red: 0.10, green: 0.10, blue: 0.14)
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if let selected {
                        theme.style = selected
                        onContinue()
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selected != nil
                                ? AnyShapeStyle(buttonGradient)
                                : AnyShapeStyle(Color.gray.opacity(0.4))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(selected == nil)

                pageIndicator(current: 1, total: 3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var buttonGradient: LinearGradient {
        if let selected {
            switch selected {
            case .soft:
                return LinearGradient(
                    colors: [Color(red: 0.82, green: 0.52, blue: 0.56), Color(red: 0.92, green: 0.68, blue: 0.62)],
                    startPoint: .leading, endPoint: .trailing
                )
            case .bold:
                return LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
        return LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
    }

    private func styleCard(
        style: AppTheme.Style,
        title: String,
        subtitle: String,
        colors: [Color],
        icon: String,
        bgColor: Color
    ) -> some View {
        let isSelected = selected == style
        let textColor: Color = style == .bold ? .white : Color(red: 0.25, green: 0.2, blue: 0.2)
        let subtitleColor: Color = style == .bold ? .white.opacity(0.6) : Color(red: 0.5, green: 0.4, blue: 0.4)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selected = style
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(textColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color(colors[0]) : (style == .bold ? .white.opacity(0.2) : .gray.opacity(0.3)))
            }
            .padding(20)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(colors[0]) : .clear, lineWidth: 2.5)
            )
        }
    }
}

// MARK: - Shared Page Indicator

func pageIndicator(current: Int, total: Int) -> some View {
    HStack(spacing: 6) {
        ForEach(0..<total, id: \.self) { i in
            Capsule()
                .fill(i == current ? Color.primary : Color.gray.opacity(0.25))
                .frame(width: i == current ? 20 : 8, height: 8)
        }
    }
    .padding(.top, 8)
}
