import Foundation

@Observable
final class TaskService {
    static let shared = TaskService()

    var tasks: [TaskItem] = []
    var isLoading = false

    private init() {}

    func fetchTasks(agentId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        struct TasksResponse: Codable { let tasks: [TaskItem] }
        let response: TasksResponse = try await APIClient.shared.get("/agents/\(agentId)/tasks")
        tasks = response.tasks
    }

    func submitTask(
        agentId: String,
        input: String,
        imageData: Data? = nil,
        webSearch: Bool = false,
        fileIds: [String]? = nil
    ) async throws -> TaskSubmitResponse {
        var request = TaskSubmitRequest(input: input)
        if let imageData {
            request.imageData = imageData.base64EncodedString()
        }
        if webSearch {
            request.webSearch = true
        }
        if let fileIds, !fileIds.isEmpty {
            request.fileIds = fileIds
        }

        let response: TaskSubmitResponse = try await APIClient.shared.post(
            "/agents/\(agentId)/tasks",
            body: request
        )

        let newTask = TaskItem(
            id: response.taskId,
            agentId: agentId,
            input: input,
            output: nil,
            status: response.status,
            createdAt: Date(),
            completedAt: nil,
            tokensUsed: nil,
            fileIds: fileIds
        )
        tasks.insert(newTask, at: 0)
        return response
    }

    func getTask(agentId: String, taskId: String) async throws -> TaskItem {
        try await APIClient.shared.get("/agents/\(agentId)/tasks/\(taskId)")
    }

    func clearHistory(agentId: String) async throws -> Int {
        struct ClearResponse: Codable { let deleted: Int }
        let response: ClearResponse = try await APIClient.shared.delete("/agents/\(agentId)/tasks")
        tasks.removeAll()
        return response.deleted
    }

    func updateTaskFromStream(taskId: String, content: String?, status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        switch status {
        case .running:
            if let content {
                tasks[index].output = (tasks[index].output ?? "") + content
            }
        case .completed:
            tasks[index].completedAt = Date()
        case .failed:
            if let content {
                tasks[index].output = content
            }
        default:
            break
        }
        tasks[index].status = status
    }
}
