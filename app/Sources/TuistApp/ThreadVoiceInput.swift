#if os(iOS)
    import AVFoundation
    import Speech
    import SwiftUI

    @MainActor
    final class ThreadVoiceInput: ObservableObject {
        @Published private(set) var isRecording = false
        @Published private(set) var levels = Array(repeating: CGFloat.zero, count: 24)
        @Published private(set) var errorMessage: String?

        private let engine = AVAudioEngine()
        private var recognitionTask: SFSpeechRecognitionTask?
        private var request: SFSpeechAudioBufferRecognitionRequest?
        private var hasTap = false
        private var transcript = ""
        private var generation = UUID()

        func start() async {
            guard !isRecording else { return }
            let attempt = UUID()
            generation = attempt
            errorMessage = nil
            transcript = ""
            levels = Array(repeating: 0, count: 24)

            isRecording = true
            guard await requestPermissions(), generation == attempt else {
                isRecording = false
                return
            }
            do {
                try startRecognition(attempt: attempt)
            } catch {
                stopRecording()
                errorMessage = "Could not start dictation. Your typed draft is unchanged."
            }
        }

        func finish(accept: (String) -> Void) {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            generation = UUID()
            stopRecording()
            guard !text.isEmpty else {
                errorMessage = "No speech was captured. Your typed draft is unchanged."
                return
            }
            accept(text)
        }

        func cancel() {
            generation = UUID()
            stopRecording()
            transcript = ""
        }

        static func appending(_ transcript: String, to draft: String) -> String {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return draft }
            return draft + (draft.isEmpty || draft.last?.isWhitespace == true ? "" : " ") + text
        }

        private func requestPermissions() async -> Bool {
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard speech == .authorized else {
                errorMessage = "Allow speech recognition in Settings to transcribe on this device."
                return false
            }
            let microphone = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard microphone else {
                errorMessage = "Allow microphone access in Settings to record a message."
                return false
            }
            return true
        }

        private func startRecognition(attempt: UUID) throws {
            guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { throw CancellationError() }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            self.request = request

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CancellationError() }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.level(in: buffer)
                Task { @MainActor in
                    guard self?.generation == attempt else { return }
                    self?.levels.removeFirst()
                    self?.levels.append(level)
                }
            }
            hasTap = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil { self.stopRecording() }
                }
            }
            engine.prepare()
            try engine.start()
        }

        private func stopRecording() {
            engine.stop()
            if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
            request?.endAudio()
            recognitionTask?.cancel()
            recognitionTask = nil
            request = nil
            isRecording = false
            levels = Array(repeating: 0, count: 24)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        private static func level(in buffer: AVAudioPCMBuffer) -> CGFloat {
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
            var energy = 0.0
            for index in 0 ..< Int(buffer.frameLength) {
                let sample = Double(channel[index])
                if sample.isFinite { energy += sample * sample }
            }
            let meanSquare = energy / Double(buffer.frameLength)
            guard meanSquare > 0 else { return 0 }
            return CGFloat(min(1, max(0, (10 * log10(meanSquare) + 60) / 48)))
        }
    }

    struct ThreadVoiceLevels: View {
        let levels: [CGFloat]
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            HStack(spacing: 3) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule().fill(.tint).frame(maxWidth: .infinity).frame(height: 4 + levels[index] * 24)
                }
            }
            .frame(height: 28)
            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: levels)
        }
    }
#endif
