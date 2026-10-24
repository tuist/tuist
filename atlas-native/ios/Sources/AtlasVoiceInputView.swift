import SwiftUI

struct AtlasThreadComposer: View {
    @Binding var draft: String
    let placeholder: String
    let saving: Bool
    let phase: AtlasVoiceInput.Phase
    let levels: [CGFloat]
    var hasAttachments = false
    var addPhotos: (() -> Void)?
    var addFiles: (() -> Void)?
    let start: () -> Void
    let stop: () -> Void
    let cancel: () -> Void
    let send: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var recording: Bool { phase != .idle }
    private var canSubmit: Bool {
        !saving && (hasAttachments || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        let palette = contrast == .increased ? nil : theme?.palette(scheme)
        let shape = RoundedRectangle(cornerRadius: 28)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                if !recording, let addPhotos, let addFiles {
                    Menu {
                        Button("Photo Library", systemImage: "photo.on.rectangle", action: addPhotos)
                        Button("Choose Files", systemImage: "doc", action: addFiles)
                    } label: {
                        Image(systemName: "plus").font(.title3).frame(width: 44, height: 44)
                    }
                    .disabled(saving).accessibilityLabel("Attach images or files")
                    .accessibilityIdentifier("thread-attach")
                }
                Group {
                    if phase == .requesting {
                        Text("Waiting for permission…").font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("thread-voice-status")
                    } else if phase == .recording {
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(levels.indices, id: \.self) { index in
                                Capsule().fill(.tint)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 4 + levels[index] * 24)
                            }
                        }
                        .frame(height: 44)
                        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: levels)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recording on this device")
                        .accessibilityHint("Release the microphone or tap stop to add editable text. Nothing is sent automatically.")
                        .accessibilityIdentifier("thread-voice-recording")
                    } else {
                        TextField(placeholder, text: $draft, axis: .vertical)
                            .lineLimit(1...6).textFieldStyle(.plain).padding(.vertical, 11)
                            .accessibilityIdentifier("thread-composer")
                    }
                }
                .padding(.leading, recording ? 52 : 12).padding(.trailing, recording ? 8 : 44)
                if recording {
                    Button(action: cancel) {
                        Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard dictation")
                    .accessibilityHint("Keeps your existing typed draft unchanged.")
                    .accessibilityIdentifier("thread-voice-cancel")
                } else {
                    Button(action: send) {
                        Group {
                            if saving { ProgressView() } else { Image(systemName: "arrow.up").font(.title3.bold()) }
                        }.frame(width: 44, height: 44)
                    }
                    .buttonStyle(AtlasComposerSendStyle())
                    .disabled(!canSubmit)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("thread-send")
                }
            }
            .overlay(alignment: recording ? .bottomLeading : .bottomTrailing) {
                // Keep one UIKit target alive as it moves, so a held microphone still receives its release.
                AtlasMicrophoneButton(active: recording, start: start, stop: stop, cancel: cancel)
                    .disabled(saving)
                    .padding(.trailing, recording ? 0 : 48)
            }
            .padding(4)
            .foregroundStyle(palette.map { Color(atlasHex: $0.text) } ?? Color.primary)
            .background(palette.map { Color(atlasHex: $0.surface) } ?? Color(uiColor: .systemBackground), in: shape)
            .overlay { shape.strokeBorder(palette.map { Color(atlasHex: $0.border) } ?? Color(uiColor: .separator), lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.06), radius: 12, y: 4)
        }
        .accessibilityElement(children: .contain)
    }
}

struct AtlasComposerSendStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let onAccent = contrast == .increased ? Color(uiColor: .systemBackground)
            : theme.map { Color(atlasHex: $0.palette(scheme).onAccent) } ?? AtlasSettingsStyle.onTint
        configuration.label
            .foregroundStyle(onAccent)
            .background { Circle().fill(.tint).padding(4) }
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.3)
    }
}

private struct AtlasMicrophoneButton: View {
    let active: Bool
    let start: () -> Void
    let stop: () -> Void
    let cancel: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack {
            Circle().fill(active ? Color.red.opacity(0.1) : Color(uiColor: .tertiarySystemFill)).padding(4)
            Image(systemName: active ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Color.red : Color.secondary)
                .accessibilityHidden(true)
            AtlasMicrophoneTouchTarget(active: active, enabled: enabled, start: start, stop: stop, cancel: cancel)
        }
        .frame(width: 44, height: 44)
        .opacity(enabled ? 1 : 0.4)
    }
}

private struct AtlasMicrophoneTouchTarget: UIViewRepresentable {
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
        button.accessibilityLabel = active ? "Stop dictation" : "Transcribe a voice message"
        button.accessibilityHint = active ? "Adds editable text to your draft. Does not send a message."
            : "Hold while speaking and release to add editable text. "
                + "Tap to start or stop hands-free dictation. Nothing is sent automatically."
        button.accessibilityIdentifier = "thread-microphone"
    }

    final class Coordinator: NSObject {
        var parent: AtlasMicrophoneTouchTarget
        private var holding = false

        init(_ parent: AtlasMicrophoneTouchTarget) { self.parent = parent }

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
