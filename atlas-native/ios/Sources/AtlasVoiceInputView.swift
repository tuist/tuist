import SwiftUI

struct AtlasVoiceInputView: View {
    let phase: AtlasVoiceInput.Phase
    let transcript: String
    let levels: [CGFloat]
    let cancel: () -> Void
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        switch phase {
        case .requesting: return "Waiting for permission…"
        case .finishing: return "Finishing transcription…"
        case .reviewing: return "Review your transcript"
        default: return "Transcribing on this device"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: cancel) {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Cancel voice input")
                .accessibilityIdentifier("thread-voice-cancel")
                VStack(alignment: .leading, spacing: 4) {
                    Text(status)
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("thread-voice-status")
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(levels.indices, id: \.self) { index in
                            Capsule().fill(.tint)
                                .frame(width: 3, height: 3 + levels[index] * 23)
                        }
                    }
                    .frame(height: 28).frame(maxWidth: .infinity, alignment: .leading)
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: levels)
                    .accessibilityHidden(true)
                }
                Button(action: done) {
                    Group {
                        if phase == .finishing { ProgressView() } else { Image(systemName: "checkmark") }
                    }.frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .modifier(AtlasPrimaryAction())
                .disabled(phase != .recording && phase != .reviewing).accessibilityLabel("Use transcript")
                .accessibilityIdentifier("thread-voice-done")
            }
            if !transcript.isEmpty {
                Text(transcript).font(.callout).lineLimit(6).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-voice-recording")
    }
}

struct AtlasMicrophoneButton: View {
    let active: Bool
    let start: () -> Void
    let review: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack {
            Image(systemName: active ? "mic.fill" : "mic")
                .foregroundStyle(active ? Color.red : Color.accentColor)
                .accessibilityHidden(true)
            AtlasMicrophoneTouchTarget(active: active, enabled: enabled, start: start, review: review)
        }
        .frame(width: 44, height: 44)
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct AtlasMicrophoneTouchTarget: UIViewRepresentable {
    let active: Bool
    let enabled: Bool
    let start: () -> Void
    let review: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold))
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 60
        // Recognition cancels the button's tap, so releasing a hold cannot also restart recording.
        hold.cancelsTouchesInView = true
        button.addGestureRecognizer(hold)
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        if button.isEnabled != enabled {
            button.isEnabled = enabled
            button.gestureRecognizers?.forEach { $0.isEnabled = enabled }
        }
        button.accessibilityLabel = active ? "Stop dictation" : "Transcribe a voice message"
        button.accessibilityHint = "Hold while speaking and release to review. "
            + "Tap to start or stop hands-free dictation. Nothing is sent automatically."
        button.accessibilityIdentifier = "thread-microphone"
    }

    final class Coordinator: NSObject {
        var parent: AtlasMicrophoneTouchTarget
        private var holding = false

        init(_ parent: AtlasMicrophoneTouchTarget) { self.parent = parent }

        @objc func tap() {
            guard parent.enabled else { return }
            if parent.active { parent.review() } else { parent.start() }
        }

        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard parent.enabled else { return }
                holding = true
                parent.start()
            case .ended, .cancelled: endHold()
            default: break
            }
        }

        func endHold() {
            guard holding else { return }
            holding = false
            parent.review()
        }
    }
}
