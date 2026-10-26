import AVFoundation
import Foundation
import Testing

@MainActor
struct AtlasThreadPresentationTests {
    @Test func voiceTranscriptPreservesTypedDraftAndRequiresNonemptyText() {
        #expect(AtlasVoiceInput.appending(" local words ", to: "Typed draft") == "Typed draft local words")
        #expect(AtlasVoiceInput.appending(" words ", to: "Typed\n") == "Typed\nwords")
        #expect(AtlasVoiceInput.appending(" \n ", to: "Unchanged") == "Unchanged")
        #expect(AtlasVoiceInput.appending(" words ", to: "") == "words")
    }

    @Test func releasedHoldCannotStartAQueuedMicrophoneRequest() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: {
            Issue.record("Permission requested after release")
            return .denied
        })
        let start = Task { await voice.start() }
        start.cancel()
        voice.finish { _ in Issue.record("A queued start must not change the draft") }
        await start.value
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(voice.errorMessage == nil)
        #expect(capture.startCount == 0)
    }

    @Test(arguments: [false, true]) func releasedPermissionPromptCannotActivateMicrophoneLater(waitingForMicrophone: Bool) async {
        var resumePermission: (() -> Void)?
        var microphoneRequested = false
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: {
            if waitingForMicrophone { return .authorized }
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: .authorized) }
            }
        }, microphonePermission: {
            microphoneRequested = true
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: true) }
            }
        })
        let pending = Task { await voice.start() }
        while resumePermission == nil { await Task.yield() }
        #expect(voice.phase == .requesting)
        voice.finish { _ in Issue.record("Releasing a permission prompt must not accept text") }
        resumePermission?()
        await pending.value
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(voice.errorMessage?.contains("After allowing permissions") == true)
        #expect(microphoneRequested == waitingForMicrophone)
        #expect(capture.startCount == 0)
    }

    @Test(arguments: [false, true]) func cancelledPermissionTaskCannotActivateMicrophone(waitingForMicrophone: Bool) async {
        var resumePermission: (() -> Void)?
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: {
            if waitingForMicrophone { return .authorized }
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: .authorized) }
            }
        }, microphonePermission: {
            guard waitingForMicrophone else { Issue.record("Cancelled speech permission requested microphone"); return false }
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: true) }
            }
        })
        let pending = Task { await voice.start() }
        while resumePermission == nil { await Task.yield() }
        pending.cancel()
        resumePermission?()
        await pending.value
        #expect(voice.phase == .idle)
        #expect(capture.startCount == 0)
    }

    @Test func supersededPermissionResultCannotStopANewerRecording() async {
        var resumePermission: (() -> Void)?
        var speechRequests = 0
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: {
            speechRequests += 1
            if speechRequests > 1 { return .authorized }
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: .denied) }
            }
        }, microphonePermission: { true })
        let pending = Task { await voice.start() }
        while resumePermission == nil { await Task.yield() }
        voice.cancel()
        await voice.start()
        resumePermission?()
        await pending.value
        #expect(capture.startCount == 1)
        #expect(capture.running)
        #expect(voice.phase == .recording)
        #expect(voice.errorMessage == nil)
        voice.cancel()
    }

    @Test func stopImmediatelyAppendsOnceAndLateRecognitionCannotOverwriteEdits() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        var draft = "Existing draft."
        var acceptCount = 0
        await voice.start()
        capture.emit(.transcript(" dictated words ", final: false))
        #expect(draft == "Existing draft.")
        draft = "A newer typed draft."
        voice.finish { text in
            acceptCount += 1
            draft = AtlasVoiceInput.appending(text, to: draft)
        }
        #expect(draft == "A newer typed draft. dictated words")
        #expect(voice.phase == .idle)
        #expect(!capture.running)
        draft += " More editing."
        capture.emit(.transcript("late final replacement", final: true))
        capture.emit(.failed)
        capture.emit(.level(1))
        voice.finish { _ in acceptCount += 1 }
        #expect(draft == "A newer typed draft. dictated words More editing.")
        #expect(acceptCount == 1)
        #expect(voice.transcript.isEmpty)
        #expect(voice.levels.allSatisfy { $0 == 0 })
        #expect(voice.errorMessage == nil)
    }

    @Test func cancelDiscardsPartialsAndFencesOldCaptureAfterRestart() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        await voice.start()
        capture.emit(.transcript("unaccepted words", final: false))
        voice.cancel() // Same discard contract used for background, navigation and interruption.
        voice.finish { _ in Issue.record("Cancellation accepted an unfinished transcript") }
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(!capture.running)
        await voice.start()
        capture.emit(.transcript("old final", final: true), session: 0)
        capture.emit(.failed, session: 0)
        capture.emit(.level(1), session: 0)
        #expect(voice.phase == .recording)
        #expect(voice.transcript.isEmpty)
        #expect(voice.levels.allSatisfy { $0 == 0 })
        capture.emit(.transcript("new capture", final: false), session: 1)
        var accepted = ""
        voice.finish { accepted = $0 }
        #expect(accepted == "new capture")
    }

    @Test func finalRecognitionWaitsForReleaseAndDoesNotAutoAccept() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        await voice.start()
        capture.emit(.transcript("final words", final: true))
        #expect(voice.phase == .recording)
        #expect(!capture.running)
        capture.emit(.failed)
        capture.emit(.transcript("older partial", final: false))
        var accepted = ""
        voice.finish { accepted = $0 }
        #expect(accepted == "final words")
        #expect(voice.phase == .idle)
    }

    @Test func recognitionFailureDiscardsEvenANonemptyPartial() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        await voice.start()
        capture.emit(.transcript("unfinished words", final: false))
        capture.emit(.failed)
        capture.emit(.transcript("late final", final: true))
        voice.finish { _ in Issue.record("Interrupted transcription must not change the draft") }
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(voice.errorMessage?.contains("typed draft is unchanged") == true)
        #expect(!capture.running)
    }

    @Test func emptyRecordingStopsWithoutChangingDraft() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        await voice.start()
        capture.emit(.transcript(" \n ", final: false))
        voice.finish { _ in Issue.record("Empty dictation must not change the draft") }
        #expect(voice.phase == .idle)
        #expect(!capture.running)
        #expect(voice.errorMessage?.contains("No speech was captured") == true)
    }

    @Test func waveformUsesRollingMeasuredLevelsAndClearsOnCancel() async {
        let capture = VoiceCapture()
        let voice = AtlasVoiceInput(capture: capture, speechPermission: { .authorized }, microphonePermission: { true })
        await voice.start()
        for index in 0..<40 { capture.emit(.level(CGFloat(index) / 100)) }
        #expect(voice.levels == (16..<40).map { CGFloat($0) / 100 })
        voice.cancel()
        capture.emit(.level(1))
        #expect(voice.levels == Array(repeating: 0, count: 24))
    }

    @Test func microphoneMeterRespondsToQuietSpeechAndClipsLoudAudio() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        let samples = try #require(buffer.floatChannelData?[0])
        buffer.frameLength = 64
        var measured: [CGFloat] = []
        for amplitude in [Float(0), 0.0001, 0.01, 0.1, 1] {
            for frame in 0..<64 { samples[frame] = amplitude }
            measured.append(AtlasVoiceInput.level(in: buffer))
        }
        #expect(measured[0] == 0)
        #expect(measured[1] == 0)
        #expect(measured[2] > 0.4 && measured[2] < 0.5)
        #expect(measured[3] > measured[2])
        #expect(measured[4] == 1)
        buffer.frameLength = 0
        #expect(AtlasVoiceInput.level(in: buffer) == 0)
    }

    @Test(arguments: [false, true]) func microphoneMeterMeasuresEveryChannel(interleaved: Bool) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                               channels: 2, interleaved: interleaved))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        let channels = try #require(buffer.floatChannelData)
        buffer.frameLength = 64
        for channel in 0..<2 {
            let samples = interleaved ? channels[0] + channel : channels[channel]
            for frame in 0..<64 { samples[frame * buffer.stride] = channel == 0 ? 0 : 0.1 }
        }
        let level = AtlasVoiceInput.level(in: buffer)
        #expect(level > 0.7 && level < 0.8)
    }

    @Test func markdownRendersStructureAndKeepsCodeLiteral() {
        let source = "# Heading\n\n**Bold** and [a link](https://example.org)\n\n- first\n1. second\n> quote\n\n"
            + "```swift\nlet x = \"**literal**\"\n```\n\n| Name | Value |\n| --- | ---: |\n| Count | 12 |"
        #expect(AtlasMarkdownBlock.parse(source) == [
            .heading(1, "Heading"), .paragraph("**Bold** and [a link](https://example.org)"),
            .list("•", "first"), .list("1.", "second"), .quote("quote"),
            .code("swift", "let x = \"**literal**\""), .table([["Name", "Value"], ["Count", "12"]])
        ])
        #expect(String(AtlasMarkdown.inline("**Bold** and `code`").characters) == "Bold and code")
    }

    @Test func markdownNeverExecutesLinksOrLoadsImages() {
        let unsafe = AtlasMarkdown.inline("[Open](dev.tuist.atlas://navigate/accounts)")
        #expect(unsafe.runs.allSatisfy { $0.link == nil })
        let safe = AtlasMarkdown.inline("[Open](https://example.org)")
        #expect(safe.runs.contains { $0.link?.scheme == "https" })
        #expect(AtlasMarkdownBlock.parse("```\nunclosed **code**") == [.code("", "unclosed **code**")])
        #expect(AtlasMarkdownBlock.parse(String(repeating: "x", count: 20_000)) == [.paragraph(String(repeating: "x", count: 16_000))])
    }
}

extension AtlasThreadPresentationTests {
    @Test func bottomFollowingSurvivesLayoutCorrectionsButStopsForUserHistoryScrolling() {
        let state = AtlasThreadScrollState()
        let update = { (metrics: AtlasThreadScrollMetrics) in state.update(metrics) }
        state.userScrolling = false
        #expect(!update(.init(height: 2000, bottom: 600, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 840, viewport: 600)))
        // A later lazy-row correction can change offset without changing the new content height.
        #expect(update(.init(height: 2200, bottom: 880, viewport: 600)))
        #expect(state.following)
        #expect(!update(.init(height: 2200, bottom: 600, viewport: 600)))
        state.userScrolling = true
        #expect(!update(.init(height: 2200, bottom: 645, viewport: 600)))
        state.userScrolling = false
        #expect(!update(.init(height: 2500, bottom: 945, viewport: 600)))
        #expect(!state.following)
        #expect(!update(.init(height: 2500, bottom: 600, viewport: 600)))
        #expect(state.following)
        #expect(update(.init(height: 2500, bottom: 760, viewport: 400, inset: 200)))
        #expect(state.following)
        // Lazy estimates can leave every message above the viewport, not at its bottom edge.
        #expect(update(.init(height: 2500, bottom: 50, viewport: 400, inset: 200)))
        #expect(update(.init(height: 2500, bottom: -30, viewport: 400, inset: 200)))
        #expect(!update(.init(height: 2500, bottom: 400, viewport: 400, inset: 200)))
    }

    @Test func fallbackScrollAccumulatesSlowMovementAndRebasesContentGrowth() {
        let state = AtlasThreadScrollState()
        let update = { (metrics: AtlasThreadScrollMetrics) in state.update(metrics) }
        #expect(!update(.init(height: 2000, bottom: 600, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 840, viewport: 600)))
        #expect(update(.init(height: 2200, bottom: 880, viewport: 600)))
        #expect(state.following)
        #expect(!update(.init(height: 2200, bottom: 600, viewport: 600)))
        for step in 1...50 { _ = state.update(.init(height: 2200, bottom: 600 + CGFloat(step) / 2, viewport: 600)) }
        #expect(!state.following)
    }
}

/// A per-test capture adapter delivers hardware events, including deliberately late callbacks.
@MainActor
private final class VoiceCapture: AtlasVoiceCapturing {
    private var updates: [@MainActor (AtlasVoiceCaptureUpdate) -> Void] = []
    private(set) var startCount = 0
    private(set) var running = false

    func start(update: @escaping @MainActor (AtlasVoiceCaptureUpdate) -> Void) throws {
        updates.append(update)
        startCount += 1
        running = true
    }

    func stop() { running = false }

    func emit(_ update: AtlasVoiceCaptureUpdate, session: Int = 0) {
        updates[session](update)
    }
}
