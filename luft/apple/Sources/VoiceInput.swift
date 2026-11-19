import AVFoundation
import Combine
import Speech

/// The capture boundary keeps hardware and permissions apart from the lifecycle.
@MainActor
protocol VoiceCapturing: AnyObject {
    func start(update: @escaping @MainActor (VoiceCaptureUpdate) -> Void) throws
    func stop()
}

enum VoiceCaptureUpdate {
    case level(CGFloat)
    case transcript(String, final: Bool)
    case failed
}

/// Dictation into the reply field, ported from Atlas. Audio stays in Apple's
/// on-device recognizer, never a cloud fallback or an upload. Release/stop
/// accepts a snapshot into the editable draft synchronously; recognition can
/// never edit it later, and nothing is sent automatically.
@MainActor
final class VoiceInput: ObservableObject {
    enum Phase { case idle, requesting, recording }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 24)
    @Published private(set) var errorMessage: String?
    var busy: Bool { phase != .idle }

    private let capture: any VoiceCapturing
    private var timeout: Task<Void, Never>?
    private var starting: Task<Void, Never>?
    private var generation = UUID()
    private var captureEnded = false
    private let speechPermission: () async -> SFSpeechRecognizerAuthorizationStatus
    private let microphonePermission: () async -> Bool

    init(
        capture: (any VoiceCapturing)? = nil,
        speechPermission: @escaping () async -> SFSpeechRecognizerAuthorizationStatus = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        },
        microphonePermission: @escaping () async -> Bool = {
            await withCheckedContinuation { continuation in
                #if os(macOS)
                    AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
                #else
                    AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
                #endif
            }
        }
    ) {
        self.capture = capture ?? OnDeviceVoiceCapture()
        self.speechPermission = speechPermission
        self.microphonePermission = microphonePermission
    }

    /// Starts dictation from a control. A release, discard or departure before
    /// the queued start runs cancels it, so the microphone never opens afterwards.
    func begin() {
        starting?.cancel()
        starting = Task { await start() }
    }

    func start() async {
        guard !busy, !Task.isCancelled else { return }
        generation = UUID()
        let attempt = generation
        phase = .requesting
        transcript = ""
        levels = Array(repeating: 0, count: 24)
        errorMessage = nil
        guard await requestPermissions(attempt: attempt) else { return }
        do {
            phase = .recording
            try capture.start { [weak self] update in
                self?.receive(update, attempt: attempt)
            }
            guard generation == attempt, phase == .recording else { return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.generation == attempt else { return }
                self.fail(String(localized: "Dictation reached its time limit. Your typed reply is unchanged; please try again."))
            }
        } catch {
            fail((error as? VoiceCaptureError)?.message
                ?? String(localized: "Could not start the microphone. Your typed reply is unchanged."))
        }
    }

    private func requestPermissions(attempt: UUID) async -> Bool {
        let speech = await speechPermission()
        guard generation == attempt else { return false }
        guard !Task.isCancelled else { cancel(); return false }
        guard speech == .authorized else {
            fail(String(localized: "Allow speech recognition in Settings to transcribe on this device."))
            return false
        }
        let microphone = await microphonePermission()
        guard generation == attempt else { return false }
        guard !Task.isCancelled else { cancel(); return false }
        guard microphone else {
            fail(String(localized: "Allow microphone access in Settings to record a message."))
            return false
        }
        return true
    }

    private func receive(_ update: VoiceCaptureUpdate, attempt: UUID) {
        guard generation == attempt, phase == .recording, !captureEnded else { return }
        switch update {
        case let .level(level):
            levels.removeFirst()
            levels.append(level.isFinite ? min(1, max(0, level)) : 0)
        case let .transcript(text, final):
            transcript = text
            // A recognizer may finish before the person releases the mic.
            // Retain the snapshot for that explicit acceptance, never auto-append it.
            if final {
                captureEnded = true
                capture.stop()
                levels = Array(repeating: 0, count: 24)
            }
        case .failed:
            fail(String(localized: "Transcription stopped. Your typed reply is unchanged; please try again."))
        }
    }

    /// Ends dictation and hands the transcript to `accepted`, which adds it to the draft.
    func finish(accepted: (String) -> Void) {
        if phase != .recording {
            cancel()
            return
        }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        guard !text.isEmpty else {
            errorMessage = String(localized: "No speech was captured. Your typed reply is unchanged; please try again.")
            return
        }
        accepted(text)
    }

    func cancel() {
        let awaitingPermission = phase == .requesting
        generation = UUID()
        starting?.cancel()
        starting = nil
        timeout?.cancel()
        timeout = nil
        capture.stop()
        phase = .idle
        transcript = ""
        captureEnded = false
        levels = Array(repeating: 0, count: 24)
        errorMessage = awaitingPermission
            ? String(localized: "Dictation did not start. After allowing permissions, tap or hold the microphone again.")
            : nil
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
        for channel in 0 ..< channelCount {
            let samples = buffer.format.isInterleaved ? channels[0] + channel : channels[channel]
            for frame in 0 ..< Int(buffer.frameLength) {
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

private struct VoiceCaptureError: Error {
    let message: String
}

@MainActor
private final class OnDeviceVoiceCapture: VoiceCapturing {
    /// Created when recording starts, so constructing the view model stays cheap.
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var hasTap = false
    #if os(iOS)
        private var audioActive = false
    #endif

    func start(update: @escaping @MainActor (VoiceCaptureUpdate) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else {
            throw VoiceCaptureError(message: String(localized:
                "On-device transcription is unavailable for this language or device. You can still type your reply."))
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            audioActive = true
        #endif
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceCaptureError(message: String(localized:
                "The microphone is unavailable. Try again when your audio device is connected."))
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let level = VoiceInput.level(in: buffer)
            Task { @MainActor in update(.level(level)) }
        }
        hasTap = true
        recognition = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor in
                if let text { update(.transcript(text, final: final)) }
                if failed, !final { update(.failed) }
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        engine = nil
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        recognizer = nil
        request = nil
        #if os(iOS)
            if audioActive {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                audioActive = false
            }
        #endif
    }
}
