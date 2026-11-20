import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Draft attachments stay on content surfaces, above the glass control layer.
/// The input switches between text and dictation without replacing its native touch target.
struct ReplyComposer: View {
    @Binding var reply: String
    /// Blocks sending, not editing: the server takes no message while the agent works.
    let disabled: Bool
    let sending: Bool
    @ObservedObject var voice: VoiceInput
    /// Suggests people after `@` and says what mentioning them does; nil offers no mentions.
    var mentions: Mentions?
    /// The lounge's title, for the invite note.
    var place: String?
    var placeholder: LocalizedStringKey = "Reply"
    /// Lets the caller raise or hide the keyboard.
    var focus: FocusState<Bool>.Binding?
    /// Nil keeps lounge/DM composers text-only.
    var attachments: Binding<[PromptAttachment]>?
    let send: () -> Void
    @State private var pickingFiles = false
    @State private var pickingPhotos = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var attachmentError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var recording: Bool { voice.phase != .idle }
    private var canSend: Bool {
        !disabled && !sending && !importing
            && (!reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachments?.wrappedValue.isEmpty == false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attachments, !attachments.wrappedValue.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments.wrappedValue) { file in
                            HStack(spacing: 0) {
                                AttachmentLabel(file: file)
                                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 240 : 156, alignment: .leading)
                                Button {
                                    attachments.wrappedValue.removeAll { $0.id == file.id }
                                } label: {
                                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(sending)
                                .accessibilityLabel(Text("Remove attachment: \(file.name)"))
                            }
                            .padding(.leading, 8).padding(.vertical, 4)
                            .background(Noora.neutralHover, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }
            if importing { ProgressView("Adding attachments…").font(.caption) }
            if let attachmentError {
                Text(verbatim: attachmentError).font(.caption).foregroundStyle(Noora.labelDestructive)
                    .padding(.horizontal, 12)
            }
            if let mentions, !recording {
                MentionBar(mentions: mentions, text: $reply, place: place)
            }
            if let message = voice.errorMessage {
                Text(verbatim: message).font(.caption).foregroundStyle(Noora.labelDestructive)
                    .padding(.horizontal, 12)
            }
            if #available(iOS 26, macOS 26, *) {
                GlassEffectContainer(spacing: 8) { composerControls }
            } else {
                composerControls
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: reply) { _, text in mentions?.update(text) }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls):
                guard urls.count + (attachments?.wrappedValue.count ?? 0) <= 4 else {
                    attachmentError = String(localized: "Attach up to four files.")
                    return
                }
                importFiles { try urls.map { try PromptAttachment.read($0) } }
            case let .failure(error): attachmentError = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $photos, maxSelectionCount: max(1, 4 - (attachments?.wrappedValue.count ?? 0)), matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            importFiles {
                var files: [PromptAttachment] = []
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw AppClientError(message: String(localized: "Could not read this image."))
                    }
                    files.append(try PromptAttachment.photo(data))
                }
                return files
            }
            photos = []
        }
    }

    private var composerControls: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let attachments, !recording {
                Menu {
                    Section("Up to 4 files, 1 MiB each") {
                        Button("Photos", systemImage: "photo") { pickingPhotos = true }
                        Button("Files", systemImage: "doc") { pickingFiles = true }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 18)).frame(width: 20, height: 20)
                }
                .glassButtonStyle().buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel("Add attachments")
                .disabled(sending || importing || attachments.wrappedValue.count >= 4)
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
                        TextField(placeholder, text: $reply, axis: .vertical)
                            .focused(given: focus)
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
                }
            }
            .overlay(alignment: recording ? .bottomLeading : .bottomTrailing) {
                // Keep the native touch target alive while a held microphone moves.
                MicrophoneButton(
                    active: recording,
                    start: { voice.begin() },
                    stop: { voice.finish { reply = VoiceInput.appending($0, to: reply) } },
                    cancel: { voice.cancel() }
                )
                .disabled(sending && !voice.busy)
            }
            .padding(4)
            .foregroundStyle(Noora.labelPrimary)
            .interactiveGlass(in: RoundedRectangle(cornerRadius: 26))
            if !recording {
                Button(action: send) {
                    Group {
                        if sending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .prominentGlassButtonStyle().tint(Noora.primary)
                .buttonBorderShape(.circle).controlSize(.large)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Send")
            }
        }
    }

    private func importFiles(_ load: @escaping @Sendable () async throws -> [PromptAttachment]) {
        guard !importing, !sending else { return }
        importing = true
        attachmentError = nil
        Task {
            defer { importing = false }
            do {
                let files = try await Task.detached { try await load() }.value
                guard let attachments, attachments.wrappedValue.count + files.count <= 4 else {
                    throw AppClientError(message: String(localized: "Attach up to four files."))
                }
                attachments.wrappedValue.append(contentsOf: files)
            } catch { attachmentError = error.localizedDescription }
        }
    }
}

private extension View {
    @ViewBuilder func focused(given focus: FocusState<Bool>.Binding?) -> some View {
        if let focus { focused(focus) } else { self }
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
