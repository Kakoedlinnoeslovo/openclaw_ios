import Foundation
import UniformTypeIdentifiers

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

    enum StreamEventType: String, Codable {
        case progress = "task:progress"
        case complete = "task:complete"
        case error = "task:error"
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
