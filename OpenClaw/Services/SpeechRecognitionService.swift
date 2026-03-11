import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()

    private(set) var isListening = false
    private(set) var transcribedText = ""
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true && authorizationStatus == .authorized
    }

    var needsPermission: Bool {
        authorizationStatus == .notDetermined
    }

    private init() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let audioGranted: Bool
        if #available(iOS 17.0, *) {
            audioGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            audioGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        await MainActor.run {
            self.authorizationStatus = speechStatus
        }

        return speechStatus == .authorized && audioGranted
    }

    func startListening() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        if recognitionTask != nil {
            stopListening()
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }

            if error != nil || (result?.isFinal == true) {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        transcribedText = ""
        isListening = true
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        transcribedText = ""
    }
}

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case requestCreationFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .requestCreationFailed:
            return "Could not create speech recognition request."
        }
    }
}
