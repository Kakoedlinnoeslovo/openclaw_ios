import SwiftUI

struct SkillBrowserView: View {
    @Environment(AppTheme.self) private var theme
    var agentId: String? = nil

    @State private var skillService = SkillService.shared
    @State private var searchText = ""
    @State private var selectedCategory: SkillCategory?
    @State private var selectedSkill: Skill?
    @State private var showClawHub = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryPicker

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        clawHubBanner

                        ForEach(filteredSkills) { skill in
                            SkillCardView(skill: skill, agentId: agentId)
                                .onTapGesture { selectedSkill = skill }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Skills")
            .searchable(text: $searchText, prompt: "Search skills")
            .sheet(item: $selectedSkill) { skill in
                SkillDetailView(skill: skill, agentId: agentId)
            }
            .sheet(isPresented: $showClawHub) {
                ClawHubView()
            }
            .overlay {
                if skillService.isLoading && skillService.skills.isEmpty {
                    ProgressView()
                }
            }
            .task {
                try? await skillService.fetchCatalog()
            }
            .onChange(of: searchText) {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    try? await skillService.fetchCatalog(
                        category: selectedCategory,
                        search: searchText.isEmpty ? nil : searchText
                    )
                }
            }
        }
    }

    // MARK: - ClawHub Banner

    private var clawHubBanner: some View {
        Button { showClawHub = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Community Skills")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("ClawHub")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange)
                            .clipShape(Capsule())
                    }

                    Text("Browse & install open-source skills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.orange.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(nil, label: "All")
                ForEach(SkillCategory.allCases) { cat in
                    categoryChip(cat, label: cat.rawValue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private func categoryChip(_ category: SkillCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
            Task {
                try? await skillService.fetchCatalog(
                    category: category,
                    search: searchText.isEmpty ? nil : searchText
                )
            }
        } label: {
            HStack(spacing: 5) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    private var filteredSkills: [Skill] {
        skillService.skills
    }
}

extension Skill: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.id == rhs.id
    }
}
