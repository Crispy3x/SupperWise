#if canImport(SwiftUI) && canImport(Speech) && os(iOS)
import Foundation
import AVFoundation
import Speech
import Observation

/// Tap to talk: turns speech into text for the assistant. The words appear in the message box so they can be checked
/// before sending. It uses on-device recognition when the phone supports it, so audio stays on the phone.
@MainActor @Observable
final class SpeechInput {
    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var problem: String?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        problem = nil
        transcript = ""
        guard let recognizer, recognizer.isAvailable else { problem = "Speech is not available right now."; return }
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { problem = "Allow Speech Recognition for this app in Settings to talk to the assistant."; return }
        guard await AVAudioApplication.requestRecordPermission() else { problem = "Allow the microphone for this app in Settings to talk to the assistant."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = req
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            isListening = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            stop()
            problem = "Could not start listening."
        }
    }

    func stop() {
        guard isListening || engine.isRunning else { isListening = false; return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
