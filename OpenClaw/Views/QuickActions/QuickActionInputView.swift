import PhotosUI
import SwiftUI

struct QuickActionInputView: View {
    @Environment(AppTheme.self) private var theme

    let action: QuickAction
    let onSubmit: (String) -> Void

    @State private var researchTopic = ""
    @State private var researchDepth = 0

    @State private var emailRecipient = ""
    @State private var emailSubject = ""
    @State private var emailTone = 0
    @State private var emailPoints = ""

    @State private var writeType = 0
    @State private var writeTopic = ""
    @State private var writeNotes = ""

    @State private var webQuery = ""
    @State private var webAction = 0

    @State private var visionMode = 0
    @State private var visionPrompt = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?

    @State private var voiceText = ""

    private let writingTypes = ["Blog Post", "Essay", "Story", "Report", "Social Post", "Docs"]
    private let emailTones = ["Professional", "Casual", "Friendly"]
    private let webActions = ["Summarize", "Key Info", "Analyze"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                formContent
                submitButton
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.system(size: 32))
                .foregroundStyle(action.color(accent: theme.accent))
                .frame(width: 72, height: 72)
                .background(action.color(accent: theme.accent).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(action.headerTitle)
                .font(.title3.weight(.semibold))

            Text(action.headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Form Router

    @ViewBuilder
    private var formContent: some View {
        switch action {
        case .research: researchForm
        case .email: emailForm
        case .write: writeForm
        case .web: webForm
        case .vision: visionForm
        case .voice: voiceForm
        default: EmptyView()
        }
    }

    // MARK: - Research

    private var researchForm: some View {
        VStack(spacing: 16) {
            inputField("What would you like to research?", text: $researchTopic, multiline: true)

            labeledSection("Depth") {
                Picker("Depth", selection: $researchDepth) {
                    Text("Quick Overview").tag(0)
                    Text("In-Depth").tag(1)
                }
                .pickerStyle(.segmented)
            }

            suggestionsRow([
                "Latest AI trends",
                "Climate solutions",
                "Market analysis",
            ])
        }
    }

    // MARK: - Email

    private var emailForm: some View {
        VStack(spacing: 16) {
            inputField("Recipient (optional)", text: $emailRecipient)
            inputField("Subject", text: $emailSubject)

            labeledSection("Tone") {
                Picker("Tone", selection: $emailTone) {
                    ForEach(0 ..< emailTones.count, id: \.self) { i in
                        Text(emailTones[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }

            inputField("Key points to include...", text: $emailPoints, multiline: true)
        }
    }

    // MARK: - Write

    private var writeForm: some View {
        VStack(spacing: 16) {
            labeledSection("Type") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(0 ..< writingTypes.count, id: \.self) { i in
                        Button { writeType = i } label: {
                            Text(writingTypes[i])
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(writeType == i ? theme.accent : Color(.tertiarySystemGroupedBackground))
                                .foregroundStyle(writeType == i ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            inputField("What do you want to write about?", text: $writeTopic, multiline: true)
            inputField("Additional notes (optional)", text: $writeNotes, multiline: true)
        }
    }

    // MARK: - Web

    private var webForm: some View {
        VStack(spacing: 16) {
            inputField("URL or topic to look up", text: $webQuery, multiline: true)

            labeledSection("Action") {
                Picker("Action", selection: $webAction) {
                    ForEach(0 ..< webActions.count, id: \.self) { i in
                        Text(webActions[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }

            suggestionsRow([
                "Latest tech news",
                "Compare products",
                "Find tutorials",
            ])
        }
    }

    // MARK: - Vision

    private var visionForm: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $visionMode) {
                Text("Analyze Image").tag(0)
                Text("Generate Image").tag(1)
            }
            .pickerStyle(.segmented)

            if visionMode == 0 {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Tap to select an image")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .onChange(of: selectedPhoto) {
                    Task {
                        if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                        }
                    }
                }

                inputField("What would you like to know about this image?", text: $visionPrompt, multiline: true)
            } else {
                inputField("Describe the image you want to generate...", text: $visionPrompt, multiline: true)

                suggestionsRow([
                    "A sunset over mountains",
                    "Logo for my brand",
                    "Product mockup",
                ])
            }
        }
    }

    // MARK: - Voice

    private var voiceForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 4)

            inputField("Tap here and use keyboard dictation, or type your request...", text: $voiceText, multiline: true)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text("Tap the microphone button on your keyboard to dictate")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Shared Components

    private func inputField(_ placeholder: String, text: Binding<String>, multiline: Bool = false) -> some View {
        TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .lineLimit(multiline ? 3 ... 8 : 1 ... 1)
            .padding(14)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func labeledSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
            content()
        }
    }

    private func suggestionsRow(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            applysuggestion(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                        .tint(.primary)
                    }
                }
            }
        }
    }

    private func applysuggestion(_ text: String) {
        switch action {
        case .research: researchTopic = text
        case .web: webQuery = text
        case .vision: visionPrompt = text
        default: break
        }
    }

    // MARK: - Validation & Submit

    private var isValid: Bool {
        switch action {
        case .research: !researchTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .email: !emailSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !emailPoints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .write: !writeTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .web: !webQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vision: !visionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voice: !voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: false
        }
    }

    private var submitButton: some View {
        Button {
            onSubmit(buildMessage())
        } label: {
            Label(action.submitLabel, systemImage: action.icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(action.color(accent: theme.accent))
        .disabled(!isValid)
        .padding(.top, 8)
    }

    private func buildMessage() -> String {
        switch action {
        case .research:
            let depth = researchDepth == 0
                ? "a quick overview of"
                : "an in-depth research analysis of"
            return """
            Research the following topic and provide \(depth) it. \
            Include key findings, relevant data, and credible sources.

            Topic: \(researchTopic.trimmingCharacters(in: .whitespacesAndNewlines))
            """

        case .email:
            let tone = emailTones[emailTone].lowercased()
            var parts = ["Draft a \(tone) email"]
            let recipient = emailRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = emailSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            let points = emailPoints.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recipient.isEmpty { parts.append("to \(recipient)") }
            if !subject.isEmpty { parts.append("about: \(subject)") }
            var msg = parts.joined(separator: " ")
            if !points.isEmpty { msg += "\n\nKey points to include:\n\(points)" }
            return msg

        case .write:
            let type = writingTypes[writeType].lowercased()
            let topic = writeTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = writeNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            var msg = "Write a \(type) about: \(topic)"
            if !notes.isEmpty { msg += "\n\nAdditional instructions: \(notes)" }
            return msg

        case .web:
            let actionName = webActions[webAction].lowercased()
            let query = webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            Search the web and \(actionName) the following. \
            Provide comprehensive, up-to-date results with sources.

            Query: \(query)
            """

        case .vision:
            let prompt = visionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if visionMode == 0 {
                return "Analyze the following image and respond to this request: \(prompt)"
            } else {
                return "Generate an image based on this description: \(prompt)"
            }

        case .voice:
            return voiceText.trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            return ""
        }
    }
}
