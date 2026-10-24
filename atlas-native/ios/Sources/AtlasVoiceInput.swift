import AVFoundation
import Combine
import Speech

/// The capture boundary keeps hardware and permission-free lifecycle tests separate.
@MainActor
protocol AtlasVoiceCapturing: AnyObject {
    func start(update: @escaping @MainActor (AtlasVoiceCaptureUpdate) -> Void) throws
    func stop()
}

enum AtlasVoiceCaptureUpdate {
    case level(CGFloat)
    case transcript(String, final: Bool)
    case failed
}

/// Audio stays in Apple's on-device recognizer. Release/stop accepts a snapshot
/// into the editable draft synchronously; recognition can never edit it later.
@MainActor
final class AtlasVoiceInput: ObservableObject {
    enum Phase { case idle, requesting, recording }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 24)
    @Published private(set) var errorMessage: String?
    var busy: Bool { phase != .idle }

    private let capture: any AtlasVoiceCapturing
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var captureEnded = false
    private let speechPermission: () async -> SFSpeechRecognizerAuthorizationStatus
    private let microphonePermission: () async -> Bool

    init(
        capture: (any AtlasVoiceCapturing)? = nil,
        speechPermission: @escaping () async -> SFSpeechRecognizerAuthorizationStatus = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        },
        microphonePermission: @escaping () async -> Bool = {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
    ) {
        self.capture = capture ?? AtlasOnDeviceVoiceCapture()
        self.speechPermission = speechPermission
        self.microphonePermission = microphonePermission
    }

    func start() async {
        guard !busy, !Task.isCancelled else { return }
        generation = UUID()
        let attempt = generation
        phase = .requesting
        transcript = ""
        levels = Array(repeating: 0, count: 24)
        errorMessage = nil
        let speech = await speechPermission()
        guard generation == attempt else { return }
        guard !Task.isCancelled else { cancel(); return }
        guard speech == .authorized else { fail("Allow speech recognition in Settings to transcribe on this device."); return }
        let microphone = await microphonePermission()
        guard generation == attempt else { return }
        guard !Task.isCancelled else { cancel(); return }
        guard microphone else { fail("Allow microphone access in Settings to record a message."); return }
        do {
            phase = .recording
            try capture.start { [weak self] update in
                guard let self, self.generation == attempt, self.phase == .recording, !self.captureEnded else { return }
                switch update {
                case .level(let level):
                    self.levels.removeFirst()
                    self.levels.append(level.isFinite ? min(1, max(0, level)) : 0)
                case .transcript(let text, let final):
                    self.transcript = text
                    // A recognizer may finish before the person releases the mic.
                    // Retain the snapshot for that explicit acceptance, never auto-append it.
                    if final {
                        self.captureEnded = true
                        self.capture.stop()
                        self.levels = Array(repeating: 0, count: 24)
                    }
                case .failed:
                    self.fail("Transcription stopped. Your typed draft is unchanged; please try again.")
                }
            }
            guard generation == attempt, phase == .recording else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.generation == attempt else { return }
                self.fail("Dictation reached its time limit. Your typed draft is unchanged; please try again.")
            }
        } catch {
            fail((error as? AtlasVoiceCaptureError)?.message ?? "Could not start the microphone. Your typed draft is unchanged.")
        }
    }

    func finish(accepted: (String) -> Void) {
        if phase == .requesting {
            cancel()
            return
        }
        guard phase == .recording else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        guard !text.isEmpty else { errorMessage = "No speech was captured. Your typed draft is unchanged; please try again."; return }
        accepted(text)
    }

    func cancel() {
        let awaitingPermission = phase == .requesting
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        capture.stop()
        phase = .idle
        transcript = ""
        captureEnded = false
        levels = Array(repeating: 0, count: 24)
        errorMessage = awaitingPermission ? "Dictation did not start. After allowing permissions, tap or hold the microphone again." : nil
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

    nonisolated static func level(in buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return 0 }
        var energy: Double = 0
        for channel in 0..<channelCount {
            let samples = buffer.format.isInterleaved ? channels[0] + channel : channels[channel]
            for frame in 0..<Int(buffer.frameLength) {
                let sample = Double(samples[frame * buffer.stride])
                guard sample.isFinite else { continue }
                energy += sample * sample
            }
        }
        let meanSquare = energy / Double(Int(buffer.frameLength) * channelCount)
        guard meanSquare > 0 else { return 0 }
        // A linear RMS multiplier hides normal, quiet speech. Map measured power
        // from a -60 dB noise floor to -12 dB full scale, without invented motion.
        return CGFloat(min(1, max(0, (10 * log10(meanSquare) + 60) / 48)))
    }
}

private struct AtlasVoiceCaptureError: Error {
    let message: String
}

@MainActor
private final class AtlasOnDeviceVoiceCapture: AtlasVoiceCapturing {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    private var audioActive = false

    func start(update: @escaping @MainActor (AtlasVoiceCaptureUpdate) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw AtlasVoiceCaptureError(message: "On-device transcription is unavailable for this language or device. "
                + "You can still type your message.")
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
        audioActive = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AtlasVoiceCaptureError(message: "The microphone is unavailable. Try again when your audio device is connected.")
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
            let level = AtlasVoiceInput.level(in: buffer)
            Task { @MainActor in update(.level(level)) }
        }
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                if let text { update(.transcript(text, final: final)) }
                if failed && !final { update(.failed) }
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        recognizer = nil
        request = nil
        if audioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }
}
