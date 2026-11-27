import SwiftUI

struct SavedPrompt: Decodable, Identifiable {
    let name: String
    let title: String
    let body: String
    let standard: Bool

    var id: String { name }
}

extension AppClient {
    var promptAccountHandle: String? {
        view.accounts.first {
            $0.profile_id == view.active_profile_id && $0.selected && !$0.personal && !$0.rejected
        }?.handle
    }
}

struct SavedPromptsSection: View {
    let client: AppClient
    let accountHandle: String
    @Binding var sheet: SettingsSheet?

    var body: some View {
        Section {
            Button("Saved Prompts", systemImage: "text.badge.star") {
                sheet = SettingsSheet {
                    SavedPromptsView(client: client, accountHandle: accountHandle)
                }
            }
            .accessibilityIdentifier("manage-saved-prompts")
        } footer: {
            Text("Prompts are shared with this organization and stored in Luft. Only admins can change them.")
        }
    }
}

/// The same library is readable in settings and selectable in thread composers.
struct SavedPromptsView: View {
    let client: AppClient
    let accountHandle: String
    var pick: ((SavedPrompt) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var prompts: [SavedPrompt]?
    @State private var canEdit = false
    @State private var error: String?
    @State private var editing: SettingsSheet?
    @State private var revision = 0
    @State private var generation: UInt64

    init(client: AppClient, accountHandle: String, pick: ((SavedPrompt) -> Void)? = nil) {
        self.client = client
        self.accountHandle = accountHandle
        self.pick = pick
        _generation = State(initialValue: client.view.generation)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let prompts {
                        ForEach(prompts) { prompt in
                            Button {
                                if let pick { pick(prompt); dismiss() }
                                else { edit(prompt) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(verbatim: prompt.title).font(.headline)
                                        Spacer()
                                        if prompt.standard { Text("Standard").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Text(verbatim: "/\(prompt.name)").font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(verbatim: prompt.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(.vertical, 4)
                                .foregroundStyle(Noora.labelPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("saved-prompt-\(prompt.name)")
                        }
                        if prompts.isEmpty { Text("No saved prompts.") }
                    } else if error == nil {
                        ProgressView("Loading prompts…")
                    }
                } header: {
                    Text(verbatim: accountHandle)
                } footer: {
                    if pick != nil {
                        Text("Choose a prompt to add its command to your draft. Nothing is sent automatically.")
                    } else {
                        Text("Prompts are shared with this organization and stored in Luft. Only admins can change them.")
                    }
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
                        Button("Retry") { revision += 1 }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Noora.backgroundPrimary)
            .navigationTitle("Saved Prompts")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    if canEdit, pick == nil {
                        ToolbarItem(placement: .primaryAction) { Button("New Prompt", systemImage: "plus") { edit(nil) } }
                    }
                }
                .sheet(item: $editing) { $0.content }
                .task(id: revision) { await reload() }
                .refreshable { await reload() }
                .onChange(of: client.view.generation) { _, _ in dismiss() }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 460)
        #endif
    }

    private func reload() async {
        guard generation == client.view.generation else { dismiss(); return }
        error = nil
        do {
            let data = try await client.call("prompts", ["account_handle": accountHandle, "if_generation": generation])
            guard !Task.isCancelled, generation == client.view.generation else { return }
            prompts = try JSONDecoder().decode(
                [SavedPrompt].self,
                from: JSONSerialization.data(withJSONObject: data["prompts"] ?? [])
            )
            canEdit = data["can_edit"] as? Bool ?? false
        } catch {
            guard !Task.isCancelled, generation == client.view.generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func edit(_ prompt: SavedPrompt?) {
        let generation = generation
        editing = SettingsSheet {
            SavedPromptEditor(prompt: prompt, canEdit: canEdit, save: { name, title, body in
                guard generation == client.view.generation
                else { throw AppClientError(message: String(localized: "The account changed. Reopen Saved Prompts.")) }
                _ = try await client.call(
                    "save_prompt",
                    ["account_handle": accountHandle, "name": name, "title": title, "body": body, "if_generation": generation]
                )
                if generation == client.view.generation { revision += 1 }
            }, remove: {
                guard generation == client.view.generation,
                      let prompt
                else { throw AppClientError(message: String(localized: "The account changed. Reopen Saved Prompts.")) }
                _ = try await client.call(
                    "delete_prompt",
                    ["account_handle": accountHandle, "name": prompt.name, "if_generation": generation]
                )
                if generation == client.view.generation { revision += 1 }
            })
        }
    }
}

/// A native multiline editor; the core validates and persists changes in Luft.
struct SavedPromptEditor: View {
    let prompt: SavedPrompt?
    let canEdit: Bool
    let save: (String, String, String) async throws -> Void
    let remove: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var title: String
    @State private var text: String
    @State private var busy = false
    @State private var confirmingRemoval = false
    @State private var error: String?

    init(
        prompt: SavedPrompt?,
        canEdit: Bool,
        save: @escaping (String, String, String) async throws -> Void,
        remove: @escaping () async throws -> Void
    ) {
        self.prompt = prompt
        self.canEdit = canEdit
        self.save = save
        self.remove = remove
        _name = State(initialValue: prompt?.name ?? "")
        _title = State(initialValue: prompt?.title ?? "")
        _text = State(initialValue: prompt?.body ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Command name", text: $name).autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                        .disabled(prompt != nil || !canEdit)
                        .accessibilityIdentifier("prompt-name")
                    TextField("Title", text: $title).disabled(!canEdit)
                        .accessibilityIdentifier("prompt-title")
                } footer: {
                    Text("Use lowercase letters, digits and hyphens, starting with a letter. Invoke it with /name.")
                }
                Section("Prompt Text") {
                    if canEdit {
                        TextEditor(text: $text).frame(minHeight: 220)
                            .font(.body)
                            .accessibilityLabel("Prompt Text")
                            .accessibilityIdentifier("prompt-body")
                    } else {
                        Text(verbatim: text).textSelection(.enabled)
                    }
                }
                if canEdit, let prompt {
                    Section {
                        Button(prompt.standard ? "Reset to Standard" : "Delete Prompt", role: .destructive) {
                            confirmingRemoval = true
                        }
                    } footer: {
                        if prompt
                            .standard { Text("Reset restores the original title and text for everyone in the organization.") }
                    }
                }
                if let error { Section { Text(verbatim: error).foregroundStyle(Noora.labelDestructive) } }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Noora.backgroundPrimary)
            .navigationTitle(prompt == nil ? "New Prompt" : "Saved Prompt")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .disabled(busy)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(canEdit ? "Cancel" : "Done") { dismiss() }.disabled(busy)
                    }
                    if canEdit {
                        ToolbarItem(placement: .confirmationAction) {
                            if busy { ProgressView() }
                            else {
                                Button("Save") { change { try await save(name, title, text) } }
                                    .accessibilityIdentifier("save-prompt")
                            }
                        }
                    }
                }
                .confirmationDialog(
                    prompt?.standard == true ? "Reset this prompt?" : "Delete this prompt?",
                    isPresented: $confirmingRemoval,
                    titleVisibility: .visible
                ) {
                    Button(prompt?.standard == true ? "Reset to Standard" : "Delete Prompt", role: .destructive) { change(remove)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This change affects everyone in the organization.")
                }
                .interactiveDismissDisabled(busy)
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 540)
        #endif
    }

    private func change(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await operation(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct SavedPromptPickerButton: View {
    let client: AppClient
    @Binding var text: String
    @State private var showing = false
    @State private var error: String?

    var body: some View {
        if let handle = client.promptAccountHandle {
            Button("Saved Prompts", systemImage: "text.badge.star") { showing = true }
                .labelStyle(.iconOnly)
                .frame(width: ReplyComposer.target, height: ReplyComposer.target)
                .buttonStyle(.plain)
                .help("Saved Prompts")
                .accessibilityIdentifier("pick-saved-prompt")
                .onChange(of: client.view.generation) { _, _ in showing = false }
                .sheet(isPresented: $showing) {
                    let generation = client.view.generation
                    SavedPromptsView(client: client, accountHandle: handle) { prompt in
                        Task {
                            do {
                                let original = text
                                let data = try await client.call("prompt_draft", ["name": prompt.name, "content": original])
                                guard generation == client.view.generation, original == text else { return }
                                if let draft = data["content"] as? String { text = draft }
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                .alert("Could not select prompt", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(verbatim: error ?? "") }
        }
    }
}
