import Foundation

@Observable
final class WebSocketManager {
    static let shared = WebSocketManager()

    var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var pingTask: Task<Void, Never>?

    private init() {
        self.session = URLSession(configuration: .default)
    }

    func connect(agentId: String) {
        guard let token = Keychain.loadString(forKey: AppConstants.accessTokenKey),
              let url = URL(string: "\(AppConstants.wsBaseURL)/agents/\(agentId)?token=\(token)") else {
            return
        }

        disconnect()

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
        startPing()
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()
            case .failure:
                Task { @MainActor in
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let event = try? decoder.decode(TaskStreamEvent.self, from: data) else { return }

        Task { @MainActor in
            switch event.type {
            case .progress:
                TaskService.shared.updateTaskFromStream(
                    taskId: event.taskId,
                    content: event.content,
                    status: .running
                )
            case .complete:
                TaskService.shared.updateTaskFromStream(
                    taskId: event.taskId,
                    content: event.content,
                    status: .completed
                )
            case .error:
                TaskService.shared.updateTaskFromStream(
                    taskId: event.taskId,
                    content: event.error,
                    status: .failed
                )
            case .toolStart:
                TaskService.shared.handleToolStart(
                    taskId: event.taskId,
                    toolName: event.toolName ?? "unknown"
                )
            case .toolEnd:
                TaskService.shared.handleToolEnd(
                    taskId: event.taskId,
                    toolName: event.toolName ?? "unknown"
                )
            }
        }
    }

    private func startPing() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.webSocketTask?.sendPing { error in
                    if error != nil {
                        Task { @MainActor in
                            self?.isConnected = false
                        }
                    }
                }
            }
        }
    }
}
