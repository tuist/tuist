import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The reply field, ported from Atlas's thread composer: one glass pill that
/// switches between text and dictation. While recording it shows measured
/// audio levels between the stop microphone and a separate discard control.
struct ReplyComposer: View {
    @Binding var reply: String
    /// Blocks sending, not editing: the server takes no message while the agent works.
    let disabled: Bool
    let sending: Bool
    @ObservedObject var voice: VoiceInput
    let send: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var recording: Bool { voice.phase != .idle }
    private var canSend: Bool {
        !disabled && !sending && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = voice.errorMessage {
                Text(verbatim: message).font(.caption).foregroundStyle(Noora.labelDestructive)
                    .padding(.horizontal, 12)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Group {
                    if voice.phase == .requesting {
                        Text("Waiting for permission…").font(.callout).foregroundStyle(Noora.labelSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else if voice.phase == .recording {
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(voice.levels.indices, id: \.self) { index in
                                Capsule().fill(Noora.primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 4 + voice.levels[index] * 24)
                            }
                        }
                        .frame(height: 44)
                        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: voice.levels)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recording on this device")
                        .accessibilityHint("Release the microphone or tap stop to add editable text. Nothing is sent automatically.")
                    } else {
                        TextField("Reply", text: $reply, axis: .vertical)
                            // Keep the conversation above the keyboard at accessibility sizes.
                            .lineLimit(1 ... (dynamicTypeSize.isAccessibilitySize ? 2 : 6))
                            .textFieldStyle(.plain)
                            .padding(.vertical, 11).padding(.leading, 12)
                            // Typing stays open while the agent works; only sending waits for it.
                            .disabled(sending)
                            .onSubmit { if canSend { send() } }
                    }
                }
                .padding(.leading, recording ? 52 : 0).padding(.trailing, recording ? 8 : 44)
                if recording {
                    Button { voice.cancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44)
                            .foregroundStyle(Noora.labelSecondary)
                            .background { Circle().fill(.quaternary).padding(4) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard dictation")
                    .accessibilityHint("Keeps your typed reply unchanged.")
                } else {
                    Button(action: send) {
                        Group {
                            if sending {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Send")
                }
            }
            .overlay(alignment: recording ? .bottomLeading : .bottomTrailing) {
                // One native target stays alive as it moves, so a held microphone still receives its release.
                MicrophoneButton(
                    active: recording,
                    start: { voice.begin() },
                    stop: { voice.finish { reply = VoiceInput.appending($0, to: reply) } },
                    cancel: { voice.cancel() }
                )
                // Dictation only edits the reply, so like typing it stays open while the agent works.
                .disabled(sending && !voice.busy)
                .padding(.trailing, recording ? 0 : 48)
            }
            .padding(4)
            .foregroundStyle(Noora.labelPrimary)
            .interactiveGlass(in: RoundedRectangle(cornerRadius: 26))
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Noora.primaryLabel)
            .background { Circle().fill(Noora.primary).padding(4) }
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)
    }
}

private struct MicrophoneButton: View {
    let active: Bool
    let start: () -> Void
    let stop: () -> Void
    let cancel: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack {
            if active {
                Circle().fill(Color.red.opacity(0.12)).padding(4)
            } else {
                Circle().fill(.quaternary).padding(4)
            }
            Image(systemName: active ? "stop.fill" : "mic.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Color.red : Noora.labelSecondary)
                .accessibilityHidden(true)
            MicrophoneTouchTarget(active: active, enabled: enabled, start: start, stop: stop, cancel: cancel)
        }
        .frame(width: 44, height: 44)
        .opacity(enabled ? 1 : 0.4)
    }
}

private enum MicrophoneCopy {
    static func label(active: Bool) -> String {
        active ? String(localized: "Stop dictation") : String(localized: "Transcribe a voice message")
    }

    static func hint(active: Bool) -> String {
        active ? String(localized: "Adds editable text to your reply. Does not send a message.")
            : String(localized: "Hold while speaking and release to add editable text. Tap to start or stop hands-free dictation. Nothing is sent automatically.")
    }
}

#if os(macOS)
    private struct MicrophoneTouchTarget: NSViewRepresentable {
        let active: Bool
        let enabled: Bool
        let start: () -> Void
        let stop: () -> Void
        let cancel: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.tap))
            button.isBordered = false
            let hold = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold))
            hold.minimumPressDuration = 0.5
            hold.allowableMovement = 60
            // Delay button events until the hold fails, so a recognized hold never also clicks.
            hold.delaysPrimaryMouseButtonEvents = true
            button.addGestureRecognizer(hold)
            updateNSView(button, context: context)
            return button
        }

        func updateNSView(_ button: NSButton, context: Context) {
            context.coordinator.parent = self
            if button.isEnabled != enabled {
                button.isEnabled = enabled
                button.gestureRecognizers.forEach { $0.isEnabled = enabled }
            }
            button.setAccessibilityLabel(MicrophoneCopy.label(active: active))
            button.setAccessibilityHelp(MicrophoneCopy.hint(active: active))
        }

        static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
            coordinator.endHold(cancelled: true)
            button.target = nil
        }

        final class Coordinator: NSObject {
            var parent: MicrophoneTouchTarget
            private var holding = false

            init(_ parent: MicrophoneTouchTarget) { self.parent = parent }

            @objc func tap() {
                guard parent.enabled else { return }
                if parent.active { parent.stop() } else { parent.start() }
            }

            @objc func hold(_ recognizer: NSPressGestureRecognizer) {
                switch recognizer.state {
                case .began:
                    guard parent.enabled else { return }
                    if parent.active { parent.stop(); return }
                    holding = true
                    parent.start()
                case .ended: endHold(cancelled: false)
                case .cancelled, .failed: endHold(cancelled: true)
                default: break
                }
            }

            func endHold(cancelled: Bool) {
                guard holding else { return }
                holding = false
                if cancelled { parent.cancel() } else { parent.stop() }
            }
        }
    }
#else
    private struct MicrophoneTouchTarget: UIViewRepresentable {
        let active: Bool
        let enabled: Bool
        let start: () -> Void
        let stop: () -> Void
        let cancel: () -> Void

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
            button.accessibilityLabel = MicrophoneCopy.label(active: active)
            button.accessibilityHint = MicrophoneCopy.hint(active: active)
        }

        final class Coordinator: NSObject {
            var parent: MicrophoneTouchTarget
            private var holding = false

            init(_ parent: MicrophoneTouchTarget) { self.parent = parent }

            @objc func tap() {
                guard parent.enabled else { return }
                if parent.active { parent.stop() } else { parent.start() }
            }

            @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
                switch recognizer.state {
                case .began:
                    guard parent.enabled else { return }
                    if parent.active { parent.stop(); return }
                    holding = true
                    parent.start()
                case .ended: endHold(cancelled: false)
                case .cancelled, .failed: endHold(cancelled: true)
                default: break
                }
            }

            func endHold(cancelled: Bool) {
                guard holding else { return }
                holding = false
                if cancelled { parent.cancel() } else { parent.stop() }
            }
        }
    }
#endif
