import SwiftUI
import TuistAuthentication
import TuistErrorHandling
import TuistNoora
import TuistServer

/// Lists the user's personal Claude and ChatGPT subscriptions and connects or disconnects them.
/// Shown only to users with the `ai` feature flag.
struct AISubscriptionsSection: View {
    @EnvironmentObject private var errorHandler: ErrorHandling
    @State private var subscriptions: [ServerAISubscription] = []
    @State private var isLoading = true
    @State private var isConnectingClaude = false
    @State private var chatGPTLogin: ServerChatGPTLogin?
    @State private var subscriptionToDisconnect: ServerAISubscription?

    private let service: AISubscriptionsServicing
    private let serverEnvironmentService: ServerEnvironmentServicing

    init(
        service: AISubscriptionsServicing = AISubscriptionsService(),
        serverEnvironmentService: ServerEnvironmentServicing = AppServerEnvironmentService()
    ) {
        self.service = service
        self.serverEnvironmentService = serverEnvironmentService
    }

    var body: some View {
        Section {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            ForEach(subscriptions) { subscription in
                row(subscription)
            }
        } header: {
            // Presentations hang off the header because modifiers on a Section apply to each of its rows.
            Text("AI subscriptions")
                .task {
                    await perform { try await service.listAISubscriptions(serverURL: serverURL) }
                }
                .sheet(isPresented: $isConnectingClaude) {
                    ClaudeTokenSheet { token in
                        try await service.connectClaudeSubscription(token: token, serverURL: serverURL)
                    } onConnected: { subscriptions = $0 }
                }
                .sheet(item: $chatGPTLogin) { login in
                    ChatGPTLoginSheet(login: login, service: service, serverURL: serverURL) {
                        await perform { try await service.listAISubscriptions(serverURL: serverURL) }
                    }
                }
                .confirmationDialog(
                    "Disconnect subscription",
                    isPresented: Binding(
                        get: { subscriptionToDisconnect != nil },
                        set: { if !$0 { subscriptionToDisconnect = nil } }
                    ),
                    presenting: subscriptionToDisconnect
                ) { subscription in
                    Button("Disconnect", role: .destructive) {
                        Task {
                            await perform {
                                try await service.disconnectAISubscription(provider: subscription.provider, serverURL: serverURL)
                            }
                        }
                    }
                } message: { subscription in
                    Text("Tuist will delete the saved \(Self.name(of: subscription)) credentials.")
                }
        } footer: {
            Text("Connect your personal Claude and ChatGPT subscriptions to use them with Tuist's AI features.")
        }
    }

    private func row(_ subscription: ServerAISubscription) -> some View {
        HStack {
            Text(verbatim: Self.name(of: subscription))
                .font(.body)
                .foregroundColor(Noora.Colors.surfaceLabelPrimary)
            Spacer()
            if subscription.isConnected {
                Button("Disconnect") { subscriptionToDisconnect = subscription }
                    .foregroundColor(Noora.Colors.surfaceLabelDestructive)
            } else if subscription.isLoginAvailable {
                Button("Connect") { connect(subscription) }
                    .foregroundColor(Noora.Colors.accent)
            } else {
                Text("Unavailable")
                    .foregroundColor(Noora.Colors.surfaceLabelSecondary)
            }
        }
    }

    private func connect(_ subscription: ServerAISubscription) {
        switch subscription.provider {
        case .claude:
            isConnectingClaude = true
        case .chatgpt:
            Task {
                do {
                    chatGPTLogin = try await service.startChatGPTSubscriptionLogin(serverURL: serverURL)
                } catch {
                    errorHandler.handle(error: error)
                }
            }
        }
    }

    private func perform(_ action: () async throws -> [ServerAISubscription]) async {
        defer { isLoading = false }
        do {
            subscriptions = try await action()
        } catch {
            errorHandler.handle(error: error)
        }
    }

    private var serverURL: URL {
        serverEnvironmentService.url()
    }

    static func name(of subscription: ServerAISubscription) -> String {
        switch subscription.provider {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        }
    }
}

private struct ClaudeTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let connect: (String) async throws -> [ServerAISubscription]
    let onConnected: ([ServerAISubscription]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Subscription token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .foregroundColor(Noora.Colors.surfaceLabelDestructive)
                    } else {
                        Text("Run claude setup-token in a terminal and paste the token it prints.")
                    }
                }
            }
            .navigationTitle("Connect Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Connect") { save() }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                onConnected(try await connect(token.trimmingCharacters(in: .whitespacesAndNewlines)))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ChatGPTLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isConnected = false

    let login: ServerChatGPTLogin
    let service: AISubscriptionsServicing
    let serverURL: URL
    let onFinished: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: login.userCode)
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                    Button("Copy code") { UIPasteboard.general.string = login.userCode }
                    Link("Open the OpenAI sign-in page", destination: login.verificationURL)
                } footer: {
                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .foregroundColor(Noora.Colors.surfaceLabelDestructive)
                    } else {
                        Text("Enter the code on the OpenAI sign-in page. This screen closes once you approve it.")
                    }
                }
            }
            .navigationTitle("Connect ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await poll() }
        .onDisappear {
            Task {
                if !isConnected, errorMessage == nil {
                    try? await service.cancelChatGPTSubscriptionLogin(loginID: login.loginID, serverURL: serverURL)
                }
                await onFinished()
            }
        }
    }

    private func poll() async {
        while !Task.isCancelled, Date() < login.expiresAt {
            try? await Task.sleep(for: .seconds(max(login.interval, 1)))
            guard !Task.isCancelled else { return }
            do {
                if try await service.pollChatGPTSubscriptionLogin(loginID: login.loginID, serverURL: serverURL) {
                    isConnected = true
                    dismiss()
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        if !Task.isCancelled {
            errorMessage = String(localized: "The sign-in expired. Close this screen and connect again.")
        }
    }
}
