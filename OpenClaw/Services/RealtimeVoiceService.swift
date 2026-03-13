import Foundation
import AVFoundation

@Observable
final class RealtimeVoiceService: @unchecked Sendable {

    // MARK: - Public state

    enum SessionState: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
        case toolRunning
        case error(String)

        var statusText: String {
            switch self {
            case .idle:        return "Tap to start"
            case .connecting:  return "Connecting…"
            case .listening:   return "Listening…"
            case .thinking:    return "Thinking…"
            case .speaking:    return "Speaking…"
            case .toolRunning: return "Running task…"
            case .error(let m): return m
            }
        }

        var isActive: Bool {
            switch self {
            case .listening, .thinking, .speaking, .toolRunning: return true
            default: return false
            }
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }

        var isToolRunning: Bool {
            self == .toolRunning
        }
    }

    var state: SessionState = .idle
    private(set) var agentTranscript = ""
    private(set) var userTranscript = ""
    private(set) var inputLevel: Float = 0
    private(set) var outputLevel: Float = 0
    private(set) var isMuted = false
    private(set) var elapsedSeconds = 0
    var maxSessionSeconds = 300

    // MARK: - Private

    private var webSocket: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var audioConverter: AVAudioConverter?
    private var sessionTimer: Timer?
    private var levelTimer: Timer?
    private var agentId: String?
    private var currentResponseId: String?

    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!

    private var pendingAudioBuffers = 0
    private var audioGenerationDone = false
    private var responseFullyDone = false
    private var isInterrupting = false
    private var currentFunctionCallId: String?
    private var currentFunctionName: String?
    private var functionArguments = ""

    private let queue = DispatchQueue(label: "com.openclaw.voice", qos: .userInteractive)

    // MARK: - Session lifecycle

    func startSession(agentId: String) async throws {
        self.agentId = agentId
        state = .connecting

        let tokenResponse: VoiceSessionResponse = try await APIClient.shared.post(
            "/voice/session",
            body: VoiceSessionRequest(agentId: agentId)
        )

        let urlString = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokenResponse.token)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: request)
        self.webSocket = ws
        ws.resume()

        try await configureAudio()
        startReceiving()
        startSessionTimer()
        startInputLevelMonitor()
    }

    func endSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil

        stopAudioEngine()

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        reportUsage()

        state = .idle
        agentTranscript = ""
        userTranscript = ""
        inputLevel = 0
        outputLevel = 0
        elapsedSeconds = 0
        isMuted = false
        pendingAudioBuffers = 0
        audioGenerationDone = false
        responseFullyDone = false
        isInterrupting = false
        currentResponseId = nil
        currentFunctionCallId = nil
        currentFunctionName = nil
        functionArguments = ""
    }

    func toggleMute() {
        isMuted.toggle()
        audioEngine.inputNode.volume = isMuted ? 0 : 1
    }

    // MARK: - Audio setup

    private func configureAudio() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        let player = AVAudioPlayerNode()
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: playbackFormat)
        self.playerNode = player

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        )!
        audioConverter = AVAudioConverter(from: nativeFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4800, format: nativeFormat) { [weak self] buffer, _ in
            self?.processInputAudio(buffer: buffer)
        }

        try audioEngine.start()
        player.play()
    }

    private func stopAudioEngine() {
        playerNode?.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        if let player = playerNode {
            audioEngine.detach(player)
        }
        playerNode = nil
        audioConverter = nil
    }

    // MARK: - Audio capture → WebSocket

    private func processInputAudio(buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter, !isMuted else { return }

        // Don't feed mic audio to the server while the agent is speaking/running a tool.
        // This prevents the speaker output from being picked up by the mic and
        // triggering OpenAI's server-side VAD, which would cause an endless
        // interruption loop (speak → echo detected → interrupt → new response → repeat).
        let currentState = state
        if currentState == .speaking || currentState == .toolRunning {
            return
        }

        let ratio = 24000.0 / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status == .haveData, error == nil else { return }

        let byteCount = Int(outputBuffer.frameLength) * 2
        let data = Data(bytes: outputBuffer.int16ChannelData![0], count: byteCount)
        let base64 = data.base64EncodedString()

        sendEvent([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
    }

    // MARK: - Audio playback ← WebSocket

    private func playAudioDelta(_ base64Audio: String) {
        guard let data = Data(base64Encoded: base64Audio) else { return }

        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            guard let int16Ptr = rawPtr.bindMemory(to: Int16.self).baseAddress else { return }
            guard let floatChannel = pcmBuffer.floatChannelData?[0] else { return }

            for i in 0..<Int(frameCount) {
                floatChannel[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        queue.sync { pendingAudioBuffers += 1 }

        playerNode?.scheduleBuffer(pcmBuffer) { [weak self] in
            guard let self else { return }
            self.queue.sync {
                guard !self.isInterrupting else { return }
                self.pendingAudioBuffers -= 1
            }
            self.checkPlaybackComplete()
        }

        updateOutputLevel(from: pcmBuffer)
    }

    private func checkPlaybackComplete() {
        let pending = queue.sync { pendingAudioBuffers }
        let audioDone = queue.sync { audioGenerationDone }
        let respDone = queue.sync { responseFullyDone }

        if pending <= 0 && audioDone && respDone {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .speaking else { return }
                self.outputLevel = 0
                self.setInputGain(active: true)
                self.state = .listening
            }
        }
    }

    private func stopPlayback() {
        queue.sync { isInterrupting = true }
        playerNode?.stop()
        playerNode?.play()
        queue.sync {
            pendingAudioBuffers = 0
            audioGenerationDone = false
            responseFullyDone = false
            isInterrupting = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.outputLevel = 0
        }
    }

    private func setInputGain(active: Bool) {
        audioEngine.inputNode.volume = active ? 1.0 : 0.15
    }

    // MARK: - WebSocket send

    private func sendEvent(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(string)) { _ in }
    }

    // MARK: - WebSocket receive

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
                self?.startReceiving()

            case .failure(let error):
                DispatchQueue.main.async {
                    if self?.state != .idle {
                        self?.state = .error("Connection lost")
                    }
                }
            }
        }
    }

    // MARK: - Server event handling

    private func handleServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {

        case "session.created", "session.updated":
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.state == .connecting {
                    self.state = .listening
                }
            }

        case "input_audio_buffer.speech_started":
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.state == .speaking {
                    self.stopPlayback()
                    self.agentTranscript = ""
                }
                self.setInputGain(active: true)
                self.state = .listening
                self.userTranscript = ""
            }

        case "input_audio_buffer.speech_stopped":
            DispatchQueue.main.async { [weak self] in
                self?.state = .thinking
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.userTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

        case "response.created":
            if let response = json["response"] as? [String: Any],
               let responseId = response["id"] as? String {
                // Set synchronously so subsequent events on this thread see the
                // correct ID immediately (avoids race with async main-queue dispatch).
                currentResponseId = responseId
                stopPlayback()
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String,
               let responseId = json["response_id"] as? String,
               responseId == currentResponseId {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.state != .speaking && self.state != .toolRunning {
                        self.setInputGain(active: false)
                        self.state = .speaking
                    }
                }
                playAudioDelta(delta)
            }

        case "response.audio.done":
            // Only mark audio done for the current response — stale events from a
            // cancelled/interrupted response must not flip this flag prematurely.
            if let responseId = json["response_id"] as? String,
               responseId == currentResponseId {
                queue.sync { audioGenerationDone = true }
                checkPlaybackComplete()
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.agentTranscript += delta
                }
            }

        case "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.agentTranscript = transcript
                }
            }

        case "response.function_call_arguments.delta":
            if let delta = json["delta"] as? String {
                functionArguments += delta
            }

        case "response.function_call_arguments.done":
            break

        case "response.output_item.done":
            if let item = json["item"] as? [String: Any],
               let itemType = item["type"] as? String,
               itemType == "function_call",
               let callId = item["call_id"] as? String,
               let name = item["name"] as? String {
                let args = (item["arguments"] as? String) ?? functionArguments
                handleFunctionCall(callId: callId, name: name, arguments: args)
                functionArguments = ""
            }

        case "response.done":
            // Filter by response_id — same rationale as response.audio.done above.
            let responseId = json["response_id"] as? String
                ?? (json["response"] as? [String: Any])?["id"] as? String
            if let responseId, responseId == currentResponseId {
                queue.sync { responseFullyDone = true }
                checkPlaybackComplete()
            }

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String
            DispatchQueue.main.async { [weak self] in
                self?.state = .error(errorMsg ?? "Something went wrong")
            }

        default:
            break
        }
    }

    // MARK: - Function calling

    private func handleFunctionCall(callId: String, name: String, arguments: String) {
        guard name == "run_task", let agentId else { return }

        var taskDescription = ""
        if let data = arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = parsed["task_description"] as? String {
            taskDescription = desc
        }

        guard !taskDescription.isEmpty else {
            sendFunctionResult(callId: callId, result: "No task description provided.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.state = .toolRunning
            self?.agentTranscript = "Running task…"
        }

        Task {
            do {
                let response: ToolCallResponse = try await APIClient.shared.post(
                    "/voice/tool-call",
                    body: ToolCallRequest(agentId: agentId, taskDescription: taskDescription)
                )
                sendFunctionResult(callId: callId, result: response.result)
            } catch {
                sendFunctionResult(callId: callId, result: "Task failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendFunctionResult(callId: String, result: String) {
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": result,
            ],
        ])

        sendEvent(["type": "response.create"])

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.agentTranscript = ""
            self.state = .thinking
        }
    }

    // MARK: - Level metering

    private func startInputLevelMonitor() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.audioEngine.isRunning else { return }

            let inputNode = self.audioEngine.inputNode
            guard let channelData = inputNode.lastRenderTime,
                  inputNode.outputFormat(forBus: 0).channelCount > 0 else {
                return
            }
            _ = channelData
        }
    }

    private func updateOutputLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var rms: Float = 0
        for i in 0..<count {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrtf(rms / Float(max(count, 1)))
        let level = min(max(rms * 4, 0), 1)

        DispatchQueue.main.async { [weak self] in
            self?.outputLevel = level
        }
    }

    // MARK: - Session timer

    private func startSessionTimer() {
        elapsedSeconds = 0
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds += 1
            if self.elapsedSeconds >= self.maxSessionSeconds {
                self.endSession()
            }
        }
    }

    // MARK: - Usage tracking

    private func reportUsage() {
        guard elapsedSeconds > 0 else { return }
        let seconds = elapsedSeconds
        Task {
            let _: UsageResponse = try await APIClient.shared.post(
                "/voice/usage",
                body: UsageRequest(durationSeconds: seconds)
            )
        }
    }
}

// MARK: - API Models

private struct VoiceSessionRequest: Encodable {
    let agentId: String
}

private struct VoiceSessionResponse: Decodable {
    let token: String
    let expiresAt: Int?
    let model: String?
}

private struct ToolCallRequest: Encodable {
    let agentId: String
    let taskDescription: String
}

private struct ToolCallResponse: Decodable {
    let result: String
}

private struct UsageRequest: Encodable {
    let durationSeconds: Int
}

private struct UsageResponse: Decodable {
    let recorded: Int?
}
