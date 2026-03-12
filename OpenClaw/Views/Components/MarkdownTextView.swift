import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block Model

    private enum Block {
        case paragraph(String)
        case heading(Int, String)
        case listItem(indent: Int, bullet: String, text: String)
        case codeBlock(String)
    }

    // MARK: - Parser

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeBuffer = ""
        var textBuffer = ""

        func flushText() {
            let t = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                blocks.append(.paragraph(t))
            }
            textBuffer = ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeBuffer))
                    codeBuffer = ""
                    inCodeBlock = false
                } else {
                    flushText()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                if !codeBuffer.isEmpty { codeBuffer += "\n" }
                codeBuffer += line
                continue
            }

            if trimmed.isEmpty {
                flushText()
                continue
            }

            if let m = trimmed.wholeMatch(of: /^(#{1,6})\s+(.+)/) {
                flushText()
                blocks.append(.heading(m.output.1.count, String(m.output.2)))
                continue
            }

            if let m = trimmed.wholeMatch(of: /^[-•]\s+(.+)/) {
                flushText()
                let spaces = line.prefix(while: { $0 == " " }).count
                blocks.append(.listItem(indent: spaces / 2, bullet: "•", text: String(m.output.1)))
                continue
            }

            if let m = trimmed.wholeMatch(of: /^(\d+)[.)]\s+(.+)/) {
                flushText()
                let spaces = line.prefix(while: { $0 == " " }).count
                blocks.append(.listItem(indent: spaces / 2, bullet: "\(m.output.1).", text: String(m.output.2)))
                continue
            }

            if !textBuffer.isEmpty { textBuffer += "\n" }
            textBuffer += trimmed
        }

        if inCodeBlock && !codeBuffer.isEmpty {
            blocks.append(.codeBlock(codeBuffer))
        }
        flushText()

        return blocks
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let str):
            inlineMarkdown(str)
                .font(.subheadline)

        case .heading(let level, let str):
            inlineMarkdown(str)
                .font(level <= 1 ? .title3 : level == 2 ? .headline : .subheadline)
                .fontWeight(.semibold)
                .padding(.top, 2)

        case .listItem(let indent, let bullet, let str):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bullet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                inlineMarkdown(str)
                    .font(.subheadline)
            }
            .padding(.leading, CGFloat(indent) * 16)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.vertical, 2)
        }
    }

    // MARK: - Inline Markdown

    private func inlineMarkdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}
