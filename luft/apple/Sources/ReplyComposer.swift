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
    /// Only agent-thread composers offer the organization's saved prompts.
    var promptClient: AppClient?
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
        !disabled && !sending && !importing && !recording
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
            if let promptClient, !recording {
                SavedPromptPickerButton(client: promptClient, text: $reply)
                    .disabled(sending)
            }
            if let attachments, !recording {
                Menu {
                    Section("Up to 4 files, 1 MiB each") {
                        Button("Photos", systemImage: "photo") { pickingPhotos = true }
                        Button("Files", systemImage: "doc") { pickingFiles = true }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Noora.labelPrimary)
                        .frame(width: Self.target, height: Self.target)
                        .contentShape(Circle())
                }
                .menuStyle(.button).buttonStyle(.plain)
                // Matches the field's height; the tap target stays 44 points.
                .background { Color.clear.frame(width: Self.field, height: Self.field).glass(in: Circle()) }
                .padding(-2)
                .accessibilityLabel("Add attachments")
                .disabled(sending || importing || attachments.wrappedValue.count >= 4)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Group {
                    if voice.phase == .requesting {
                        Text("Waiting for permission…").font(.callout).foregroundStyle(Noora.labelSecondary)
                            .frame(maxWidth: .infinity, minHeight: Self.field, alignment: .leading)
                    } else if voice.phase == .recording {
                        HStack(alignment: .center, spacing: 3) {
                            ForEach(voice.levels.indices, id: \.self) { index in
                                Capsule().fill(Noora.primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 4 + voice.levels[index] * 22)
                            }
                        }
                        .frame(height: Self.field)
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
                            .padding(.vertical, 9)
                            // Typing stays open while the agent works; only sending waits for it.
                            .disabled(sending)
                            .onSubmit { if canSend { send() } }
                    }
                }
                // Leaves room for the overlaid microphone.
                .padding(.leading, recording ? Self.field : 14).padding(.trailing, recording ? 0 : Self.field)
                if recording {
                    Button { voice.cancel() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                            .frame(width: Self.target, height: Self.target)
                            .foregroundStyle(Noora.labelSecondary)
                            .background { Circle().fill(.quaternary).padding(Self.inset) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(-2)
                    .accessibilityLabel("Discard dictation")
                    .accessibilityHint("Keeps your typed reply unchanged.")
                }
            }
            .frame(minHeight: Self.field)
            .overlay(alignment: recording ? .bottomLeading : .bottomTrailing) {
                // Like Amp's, the microphone lives in the field and Send sits beside it.
                // Keep the native touch target alive while a held microphone moves.
                MicrophoneButton(
                    active: recording,
                    start: { voice.begin() },
                    stop: { voice.finish { reply = VoiceInput.appending($0, to: reply) } },
                    cancel: { voice.cancel() }
                )
                .disabled(sending && !voice.busy)
                // The 44-point target overhangs the 40-point field so the visible circle sits 4 points in.
                .padding(-2)
            }
            .foregroundStyle(Noora.labelPrimary)
            .interactiveGlass(in: RoundedRectangle(cornerRadius: Self.field / 2))
            sendButton.padding(-2)
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            ZStack {
                // As big as the field, like Amp's send button.
                Circle().fill(Noora.primary).padding((Self.target - Self.field) / 2)
                if sending {
                    ProgressView().controlSize(.small).tint(Noora.primaryLabel)
                } else {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Noora.primaryLabel)
                }
            }
            .frame(width: Self.target, height: Self.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend || sending ? 1 : 0.35)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send")
    }

    /// The field's minimum height; it grows with multi-line text.
    static let field: CGFloat = 40
    /// The tap target of the buttons in and beside the field.
    static let target: CGFloat = 44
    /// Insets a 32-point circle in the tap target.
    static let inset: CGFloat = 6

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
                Circle().fill(Color.red.opacity(0.12)).padding(ReplyComposer.inset)
            }
            Image(systemName: active ? "stop.fill" : "mic")
                .font(.system(size: active ? 15 : 18, weight: .regular))
                .foregroundStyle(active ? Color.red : Noora.labelSecondary)
                .accessibilityHidden(true)
            MicrophoneTouchTarget(active: active, enabled: enabled, start: start, stop: stop, cancel: cancel)
        }
        .frame(width: ReplyComposer.target, height: ReplyComposer.target)
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
