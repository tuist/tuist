import SwiftUI
import TuistAuthentication

struct DesktopLoginView: View {
    @EnvironmentObject private var authenticationService: AuthenticationService
    @EnvironmentObject private var errorHandling: ErrorHandling
    @State private var showsSelfHostedSheet = false
    @State private var serverURL = ""

    var body: some View {
        VStack(spacing: 20) {
            Image("TuistIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("Welcome to Tuist")
                .font(.largeTitle.bold())
            Text("Your projects and previews, together on your desktop.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button("Sign in with Tuist") { signIn { try await authenticationService.signIn() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Sign in with Google") { signIn { try await authenticationService.signInWithGoogle() } }
                Button("Sign in with GitHub") { signIn { try await authenticationService.signInWithGitHub() } }
                Divider()
                Button("Self-hosted Server…") {
                    serverURL = authenticationService.selfHostedServerURL ?? ""
                    showsSelfHostedSheet = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(authenticationService.isSigningIn)
            .frame(width: 280)

            if authenticationService.isSigningIn {
                ProgressView("Signing in…").controlSize(.small)
            }
        }
        .padding(48)
        .sheet(isPresented: $showsSelfHostedSheet) {
            Form {
                Text("Self-hosted Server")
                    .font(.headline)
                TextField("Server URL", text: $serverURL, prompt: Text("https://example.com"))
                    .onSubmit { signInToSelfHostedServer() }
                Text("Use the HTTPS root address of your Tuist server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showsSelfHostedSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Sign In", action: signInToSelfHostedServer)
                        .keyboardShortcut(.defaultAction)
                        .disabled((try? AppServerEnvironmentService.validatedURL(serverURL)) == nil)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
    }

    private func signIn(_ action: @escaping () async throws -> Void) {
        errorHandling.fireAndHandleError {
            try await authenticationService.selectServer(nil)
            try await action()
        }
    }

    private func signInToSelfHostedServer() {
        guard (try? AppServerEnvironmentService.validatedURL(serverURL)) != nil else { return }
        showsSelfHostedSheet = false
        errorHandling.fireAndHandleError {
            try await authenticationService.selectServer(serverURL)
            try await authenticationService.signIn()
        }
    }
}
