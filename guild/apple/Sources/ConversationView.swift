import SwiftUI

struct AppMessage: Decodable, Identifiable {
    let id: String
    /// `user`, `assistant`, `tool` or `system`.
    let role: String
    let content: String
}

struct AppConversation: Decodable {
    let id: String
    let title: String?
    let goal: String?
    /// The server is still answering, decided by the Rust core.
    let working: Bool
    let state: String?
    let messages: [AppMessage]
}

struct ThreadRoute: Hashable, Identifiable {
    let id: String
}

extension AppClient {
    func conversation(_ operation: String, _ args: [String: Any]) async throws -> AppConversation {
        let data = try await call(operation, args)
        return try JSONDecoder().decode(AppConversation.self, from: JSONSerialization.data(withJSONObject: data))
    }
}

/// Asks what to talk about and starts a conversation on the server. There is
/// no repository, machine or model to choose: the core picks what runs it.
struct StartConversationView: View {
    let client: AppClient
    let started: () -> Void
    @State private var content = ""
    @State private var starting = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("What do you want to talk about?", text: $content, axis: .vertical)
                    .lineLimit(4 ... 12)
                    .focused($focused)
                    .disabled(starting)
            } footer: {
                Text("Tuist answers on its servers. You don't need a repository or a machine.")
            }
            if let error {
                Text(verbatim: error).foregroundStyle(Noora.labelDestructive)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        #endif
        .navigationTitle("New conversation")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(starting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { request = Task { await start() } }
                        .disabled(starting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(starting)
            .onAppear { focused = true }
            .onDisappear { request?.cancel() }
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let generation = client.view.generation
        let revision = client.view.navigation.revision
        do {
            let thread = try await client.conversation("start_thread", ["content": content])
            guard !Task.isCancelled, generation == client.view.generation,
                  revision == client.view.navigation.revision else { return }
            // The core also checks these versions when this queued call executes.
            _ = try await client.call("navigate", [
                "url": "/threads/\(thread.id)", "if_generation": generation, "if_revision": revision,
            ])
            guard !Task.isCancelled else { return }
            started()
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

/// One conversation, kept current while the server is answering.
struct ConversationView: View {
    let client: AppClient
    let id: String
    @State private var thread: AppConversation?
    @State private var reply = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(thread?.messages ?? []) { message in
                        MessageRow(message: message).id(message.id)
                    }
                    if thread?.working == true {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").foregroundStyle(Noora.labelSecondary)
                        }
                        .id("working")
                    }
                    if let error {
                        Text(verbatim: error).font(.callout).foregroundStyle(Noora.labelDestructive)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread?.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(thread?.working == true ? "working" : thread?.messages.last?.id) }
            }
        }
        .background(Noora.backgroundPrimary)
        .overlay { if thread == nil, error == nil { ProgressView() } }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(Text(verbatim: thread?.title ?? thread?.goal ?? ""))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
        #endif
            .task(id: id) { await follow() }
    }

    /// Floats over the conversation, like the system's own message fields.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply", text: $reply, axis: .vertical)
                .lineLimit(1 ... 6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .interactiveGlass(in: RoundedRectangle(cornerRadius: 22))
                .disabled(sending || thread?.working != false)
                .onSubmit { Task { await send() } }
            Button { Task { await send() } } label: {
                Label("Send", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .prominentGlassButtonStyle()
            .buttonBorderShape(.circle)
            .disabled(sending || thread?.working != false
                || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .glassGroup(spacing: 8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Loads the conversation, then polls while the server is answering.
    private func follow() async {
        while !Task.isCancelled {
            do {
                thread = try await client.conversation("thread", ["id": id])
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            try? await Task.sleep(for: thread?.working == true ? .seconds(2) : .seconds(15))
        }
    }

    private func send() async {
        let text = reply
        guard !sending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            thread = try await client.conversation("send_message", ["id": id, "content": text])
            reply = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MessageRow: View {
    let message: AppMessage

    var body: some View {
        switch message.role {
        case "user":
            HStack {
                Spacer(minLength: 48)
                Text(verbatim: message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(Noora.labelPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Noora.neutralHover, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Noora.border, lineWidth: 1))
            }
        case "assistant":
            Text(markdown(message.content)).textSelection(.enabled).foregroundStyle(Noora.labelPrimary)
        default:
            Text(verbatim: message.content).font(.caption).foregroundStyle(Noora.labelSecondary)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
