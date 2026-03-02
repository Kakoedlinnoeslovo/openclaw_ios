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

    func submitTask(agentId: String, input: String) async throws -> TaskSubmitResponse {
        let response: TaskSubmitResponse = try await APIClient.shared.post(
            "/agents/\(agentId)/tasks",
            body: TaskSubmitRequest(input: input)
        )

        let newTask = TaskItem(
            id: response.taskId,
            agentId: agentId,
            input: input,
            output: nil,
            status: response.status,
            createdAt: Date(),
            completedAt: nil,
            tokensUsed: nil
        )
        tasks.insert(newTask, at: 0)
        return response
    }

    func getTask(agentId: String, taskId: String) async throws -> TaskItem {
        try await APIClient.shared.get("/agents/\(agentId)/tasks/\(taskId)")
    }

    func updateTaskFromStream(taskId: String, content: String?, status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        if let content {
            tasks[index].output = (tasks[index].output ?? "") + content
        }
        tasks[index].status = status
        if status == .completed {
            tasks[index].completedAt = Date()
        }
    }
}
