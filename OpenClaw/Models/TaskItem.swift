import Foundation
import UniformTypeIdentifiers

struct ToolStep: Equatable {
    let name: String
    var isDone: Bool

    var displayName: String {
        switch name {
        case "exec", "shell": return "Running command"
        case "web_search": return "Searching the web"
        case "web_fetch": return "Reading webpage"
        case "browser_navigate": return "Navigating browser"
        case "browser_snapshot": return "Capturing page"
        case "browser_click": return "Clicking element"
        case "browser_type", "browser_fill": return "Typing in browser"
        case "read_file", "file_read": return "Reading file"
        case "write_file", "file_write": return "Writing file"
        case "list_files", "file_list": return "Listing files"
        case "edit_file", "file_edit": return "Editing file"
        case "search_files", "file_search": return "Searching files"
        default:
            return name
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var iconName: String {
        switch name {
        case "exec", "shell": return "terminal"
        case "web_search": return "magnifyingglass"
        case "web_fetch": return "globe"
        case let n where n.hasPrefix("browser"): return "safari"
        case "read_file", "file_read": return "doc.text"
        case "write_file", "file_write": return "square.and.pencil"
        case "list_files", "file_list": return "folder"
        case "edit_file", "file_edit": return "pencil.line"
        case "search_files", "file_search": return "doc.text.magnifyingglass"
        default: return "gearshape"
        }
    }
}

struct TaskItem: Codable, Identifiable, Equatable {
    let id: String
    let agentId: String
    let input: String
    var output: String?
    var status: TaskStatus
    let createdAt: Date
    var completedAt: Date?
    var tokensUsed: Int?
    var fileIds: [String]?

    var toolSteps: [ToolStep] = []

    enum CodingKeys: String, CodingKey {
        case id, agentId, input, output, status, createdAt, completedAt, tokensUsed, fileIds
    }
}

enum TaskStatus: String, Codable {
    case queued
    case running
    case completed
    case failed
}

struct TaskSubmitRequest: Codable {
    let input: String
    var imageData: String?
    var webSearch: Bool?
    var fileIds: [String]?
}

struct TaskSubmitResponse: Codable {
    let taskId: String
    let status: TaskStatus
}

struct TaskStreamEvent: Codable {
    let type: StreamEventType
    let taskId: String
    let content: String?
    let error: String?
    let toolName: String?
    let toolCallId: String?

    enum StreamEventType: String, Codable {
        case progress = "task:progress"
        case complete = "task:complete"
        case error = "task:error"
        case toolStart = "task:tool_start"
        case toolEnd = "task:tool_end"
    }
}

// MARK: - File Attachments

struct FileUploadResponse: Codable {
    let fileId: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
}

struct FileAttachment: Identifiable, Equatable {
    let id: String
    let filename: String
    let mimeType: String
    let data: Data
    var uploadedFileId: String?
    var isUploading: Bool = false
    var uploadFailed: Bool = false

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var iconName: String {
        if isImage { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType == "text/csv" || mimeType.contains("spreadsheet") { return "tablecells" }
        if mimeType.contains("word") || mimeType.contains("document") { return "doc.text" }
        if mimeType.hasPrefix("text/") { return "doc.plaintext" }
        return "doc"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
