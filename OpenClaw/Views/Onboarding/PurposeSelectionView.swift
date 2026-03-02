import SwiftUI

struct PurposeSelectionView: View {
    @Environment(AppTheme.self) private var theme
    let onContinue: () -> Void

    @State private var selected: Set<String> = []

    private let purposes: [(icon: String, label: String)] = [
        ("briefcase.fill", "Work"),
        ("paintpalette.fill", "Creative"),
        ("magnifyingglass", "Research"),
        ("doc.text.fill", "Writing"),
        ("chevron.left.forwardslash.chevron.right", "Code"),
        ("person.fill", "Personal"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("What brings you here?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Select all that apply")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(purposes, id: \.label) { purpose in
                    purposeChip(icon: purpose.icon, label: purpose.label)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    theme.purposes = selected
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selected.isEmpty
                                ? AnyShapeStyle(Color.gray.opacity(0.4))
                                : AnyShapeStyle(theme.buttonGradient)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(selected.isEmpty)

                pageIndicator(current: 2, total: 3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func purposeChip(icon: String, label: String) -> some View {
        let isActive = selected.contains(label)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isActive {
                    selected.remove(label)
                } else {
                    selected.insert(label)
                }
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(isActive ? .white : theme.accent)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isActive ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                isActive
                    ? AnyShapeStyle(
                        LinearGradient(colors: theme.accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                      )
                    : AnyShapeStyle(Color(.secondarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? theme.accent.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
    }
}
