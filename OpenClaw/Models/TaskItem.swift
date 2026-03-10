import Foundation

struct TaskItem: Codable, Identifiable, Equatable {
    let id: String
    let agentId: String
    let input: String
    var output: String?
    var status: TaskStatus
    let createdAt: Date
    var completedAt: Date?
    var tokensUsed: Int?
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
