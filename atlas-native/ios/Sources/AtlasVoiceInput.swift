import AVFoundation
import Combine
import Speech

/// Audio stays in Apple's on-device recognizer. Only an explicitly accepted,
/// editable transcript enters the ordinary text draft, never an audio upload.
@MainActor
final class AtlasVoiceInput: ObservableObject {
    enum Phase { case idle, requesting, recording, reviewing, finishing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 24)
    @Published private(set) var errorMessage: String?
    var busy: Bool { phase != .idle }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var hasTap = false
    private var audioActive = false
    private var accepted: ((String) -> Void)?

    func start() async {
        guard !busy else { return }
        generation = UUID()
        let attempt = generation
        phase = .requesting
        transcript = ""
        levels = Array(repeating: 0, count: 24)
        errorMessage = nil
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == attempt else { return }
        guard speech == .authorized else { fail("Allow speech recognition in Settings to transcribe on this device."); return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == attempt else { return }
        guard microphone else { fail("Allow microphone access in Settings to record a message."); return }
        beginRecording(attempt: attempt)
    }

    private func beginRecording(attempt: UUID) {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("On-device transcription is unavailable for this language or device. You can still type your message.")
            return
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            audioActive = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("The microphone is unavailable. Try again when your audio device is connected.")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(buffer)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == attempt, self.phase == .recording else { return }
                    self.levels.removeFirst()
                    self.levels.append(CGFloat(level))
                }
            }
            hasTap = true
            observe(recognizer, request: request, attempt: attempt)
            engine.prepare()
            try engine.start()
            phase = .recording
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.stopAudio()
                self?.phase = .reviewing
            }
        } catch { fail("Could not start the microphone. Your typed draft is unchanged.") }
    }

    private func observe(_ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest, attempt: UUID) {
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == attempt else { return }
                if let text { self.transcript = text }
                if final {
                    if self.phase == .finishing { self.commit() } else { self.stopAudio(); self.phase = .reviewing }
                } else if failed {
                    self.interrupted()
                }
            }
        }
    }

    private func interrupted() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("Transcription stopped. Your typed draft is unchanged; please try again.")
            return
        }
        if phase == .finishing {
            commit()
        } else {
            stopAudio()
            phase = .reviewing
            errorMessage = "Transcription stopped. You can use the captured text or cancel; your typed draft is unchanged."
        }
    }

    private nonisolated static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var energy: Float = 0
        for index in 0..<count { energy += samples[index] * samples[index] }
        return min(1, sqrt(energy / Float(count)) * 8)
    }

    func finish(accepted: @escaping (String) -> Void) {
        guard phase == .recording || phase == .reviewing else { return }
        let alreadyFinal = phase == .reviewing
        self.accepted = accepted
        phase = .finishing
        stopAudio()
        if alreadyFinal { commit(); return }
        // A local model may not send a final result after an interruption. Keep
        // the last visible transcript rather than waiting with the mic active.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.commit()
        }
    }

    func cancel() {
        generation = UUID()
        accepted = nil
        stopAudio()
        recognition?.cancel()
        recognition = nil
        recognizer = nil
        request = nil
        phase = .idle
        transcript = ""
        errorMessage = nil
    }

    private func stopAudio() {
        timeout?.cancel()
        timeout = nil
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        if audioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }

    private func commit() {
        let text = transcript
        let callback = accepted
        cancel()
        callback?(text)
    }

    private func fail(_ message: String) {
        cancel()
        errorMessage = message
    }

    static func appending(_ transcript: String, to draft: String) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return draft }
        return draft + (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + text
    }
}
