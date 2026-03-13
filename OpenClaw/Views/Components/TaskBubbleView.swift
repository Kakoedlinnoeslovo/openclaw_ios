import SwiftUI
import QuickLook

struct TaskBubbleView: View {
    @Environment(AppTheme.self) private var theme
    let task: TaskItem

    @State private var fullScreenImage: URL?
    @State private var previewFileURL: URL?
    @State private var isDownloading: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            userBubble

            if let fileIds = task.fileIds, !fileIds.isEmpty {
                userFileBadges(fileIds)
            }

            if let output = task.output, !output.isEmpty {
                agentBubble(output)
            } else if task.status == .running || task.status == .queued {
                loadingBubble
            } else if task.status == .failed {
                errorBubble
            }
        }
        .fullScreenCover(item: $fullScreenImage) { url in
            ImageViewerOverlay(url: url) {
                fullScreenImage = nil
            }
        }
        .quickLookPreview($previewFileURL)
    }

    // MARK: - User Bubble

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

    private func userFileBadges(_ fileIds: [String]) -> some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 4) {
                Image(systemName: "paperclip")
                    .font(.system(size: 10))
                Text("\(fileIds.count) file\(fileIds.count == 1 ? "" : "s") attached")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
        }
    }

    // MARK: - Agent Bubble

    private func agentBubble(_ text: String) -> some View {
        let parsed = parseContent(text)

        return HStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parsed.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let str):
                        if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MarkdownTextView(text: str)
                                .textSelection(.enabled)
                        }
                    case .image(let url):
                        imageBlock(url: url)
                    case .file(let fileId, let filename):
                        fileCard(fileId: fileId, filename: filename)
                    }
                }

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
            .contextMenu {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                ShareLink(
                    item: text,
                    subject: Text("Agent Response"),
                    message: Text("")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    saveResponseAsFile(text)
                } label: {
                    Label("Save as File", systemImage: "square.and.arrow.down")
                }
            }

            Spacer(minLength: 60)
        }
    }

    private func saveResponseAsFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "response_\(task.id.prefix(8)).md"
        let fileURL = tempDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)
        previewFileURL = fileURL
    }

    // MARK: - Image Block

    private func imageBlock(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)

            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        fullScreenImage = url
                    }
                    .contextMenu {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            fullScreenImage = url
                        } label: {
                            Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }

            case .failure:
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Link(url.absoluteString, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }

            @unknown default:
                EmptyView()
            }
        }
    }

    // MARK: - File Card

    private func fileCard(fileId: String, filename: String) -> some View {
        Button {
            downloadAndPreview(fileId: fileId, filename: filename)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconForFilename(filename))
                    .font(.system(size: 20))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text("Tap to open")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloading[fileId] == true {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func iconForFilename(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "csv", "xlsx", "xls": return "tablecells"
        case "doc", "docx": return "doc.text"
        case "txt", "md": return "doc.plaintext"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "json", "xml": return "doc.text.magnifyingglass"
        default: return "doc"
        }
    }

    private func downloadAndPreview(fileId: String, filename: String) {
        guard isDownloading[fileId] != true else { return }
        isDownloading[fileId] = true

        Task {
            do {
                let (data, resolvedName, _) = try await APIClient.shared.downloadFile(fileId: fileId)
                let name = resolvedName == "download" ? filename : resolvedName
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(name)
                try data.write(to: fileURL)
                previewFileURL = fileURL
            } catch {
                print("Download failed: \(error.localizedDescription)")
            }
            isDownloading[fileId] = false
        }
    }

    // MARK: - Content Parsing

    private enum ContentBlock {
        case text(String)
        case image(URL)
        case file(fileId: String, filename: String)
    }

    private func parseContent(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var remaining = text

        let mdPattern = /!\[([^\]]*)\]\(([^)]+)\)/

        while let match = remaining.firstMatch(of: mdPattern) {
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
            if !before.isEmpty {
                blocks.append(contentsOf: parseTextAndFiles(before))
            }
            let urlStr = String(match.output.2)
            if let url = URL(string: urlStr) {
                blocks.append(.image(url))
            } else {
                blocks.append(.text(String(match.output.0)))
            }
            remaining = String(remaining[match.range.upperBound...])
        }

        let lines = remaining.split(separator: "\n", omittingEmptySubsequences: false)
        var textBuffer = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let url = extractImageURL(from: trimmed) {
                if !textBuffer.isEmpty {
                    blocks.append(contentsOf: parseTextAndFiles(textBuffer))
                    textBuffer = ""
                }
                blocks.append(.image(url))
            } else {
                if !textBuffer.isEmpty { textBuffer += "\n" }
                textBuffer += String(line)
            }
        }

        if !textBuffer.isEmpty {
            blocks.append(contentsOf: parseTextAndFiles(textBuffer))
        }

        if blocks.isEmpty {
            blocks.append(.text(text))
        }

        return blocks
    }

    // Pattern: [FILE:uuid:filename.ext]
    private static let filePattern = /\[FILE:([a-f0-9\-]{36}):([^\]]+)\]/

    private func parseTextAndFiles(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var remaining = text

        while let match = remaining.firstMatch(of: Self.filePattern) {
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
            if !before.isEmpty {
                blocks.append(.text(before))
            }
            let fileId = String(match.output.1)
            let filename = String(match.output.2)
            blocks.append(.file(fileId: fileId, filename: filename))
            remaining = String(remaining[match.range.upperBound...])
        }

        if !remaining.isEmpty {
            blocks.append(.text(remaining))
        }

        return blocks
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]
    private static let imageHosts: Set<String> = [
        "oaidalleapiprodscus.blob.core.windows.net",
        "images.openai.com",
        "cdn.openai.com",
        "replicate.delivery",
        "pbxt.replicate.delivery",
    ]

    private func extractImageURL(from text: String) -> URL? {
        guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return nil }
        guard let url = URL(string: text) else { return nil }

        let pathExt = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(pathExt) { return url }
        if let host = url.host(), Self.imageHosts.contains(host) { return url }

        return nil
    }

    // MARK: - Loading / Error

    private var loadingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if !task.toolSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(task.toolSteps.enumerated()), id: \.offset) { _, step in
                            HStack(spacing: 7) {
                                if step.isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 11, height: 11)
                                }

                                Image(systemName: step.iconName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(step.isDone ? .secondary : theme.accent)

                                Text(step.displayName)
                                    .font(.system(size: 12, weight: step.isDone ? .regular : .medium))
                                    .foregroundStyle(step.isDone ? .secondary : .primary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                HStack(spacing: 8) {
                    TypingIndicator()
                    Text(currentActivityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, task.toolSteps.isEmpty ? 12 : 8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(ChatBubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
    }

    private var currentActivityLabel: String {
        if task.status == .queued { return "Queued" }
        if let active = task.toolSteps.last(where: { !$0.isDone }) {
            return active.displayName + "…"
        }
        if task.elapsedSeconds > 0 {
            return "Thinking (\(formattedElapsed))…"
        }
        return "Thinking"
    }

    private var formattedElapsed: String {
        let seconds = task.elapsedSeconds
        if seconds < 60 {
            return "\(seconds)s"
        }
        let m = seconds / 60
        let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
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

// MARK: - Full Screen Image Viewer

private struct ImageViewerOverlay: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = value.magnification
                                }
                                .onEnded { _ in
                                    withAnimation { scale = max(1, scale) }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2
                            }
                        }
                case .empty:
                    ProgressView()
                        .tint(.white)
                default:
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.2))
                        .clipShape(Circle())
                }

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(16)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
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
