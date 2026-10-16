import SwiftUI
import TuistAuthentication

public struct DesktopLoginView: View {
    private let applicationModel: MacApplicationModel
    @ObservedObject private var authenticationService: AuthenticationService
    @State private var showsSelfHostedSheet = false
    @State private var serverURL = ""

    public init(applicationModel: MacApplicationModel) {
        self.applicationModel = applicationModel
        authenticationService = applicationModel.authenticationService
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            Image("TuistRoundedIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
                .padding(.bottom, 24)
            Text("Welcome to Tuist")
                .font(.title.weight(.medium))
                .padding(.bottom, 12)
            Text("Sign in to access your projects and\ncollaborate with your team")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Spacer(minLength: 32)
            signInOptions
        }
        .frame(width: 420, height: 580)
        .background {
            Image("LaunchScreenBackground")
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        }
        .clipped()
        .sheet(isPresented: $showsSelfHostedSheet) {
            selfHostedServer
        }
    }

    private var signInOptions: some View {
        VStack(spacing: 12) {
            Group {
                Button {
                    signIn { try await authenticationService.signIn() }
                } label: {
                    signInLabel("Sign in with Tuist", icon: "TuistLogo", renderingMode: .template)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.39, green: 0, blue: 0.94))
                .keyboardShortcut(.defaultAction)

                Button {
                    signIn { try await authenticationService.signInWithGoogle() }
                } label: {
                    signInLabel("Sign in with Google", icon: "GoogleLogo")
                }
                Button {
                    signIn { try await authenticationService.signInWithGitHub() }
                } label: {
                    signInLabel("Sign in with GitHub", icon: "GitHubLogo")
                }
                HStack(spacing: 12) {
                    Rectangle().fill(.tertiary).frame(height: 1)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().fill(.tertiary).frame(height: 1)
                }
                .accessibilityHidden(true)
                Button {
                    serverURL = authenticationService.selfHostedServerURL ?? ""
                    showsSelfHostedSheet = true
                } label: {
                    Label("Self-hosted server…", systemImage: "server.rack")
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
            }
            .disabled(authenticationService.isSigningIn)
            if authenticationService.isSigningIn {
                ProgressView("Signing in…")
                    .controlSize(.small)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }

    private func signInLabel(
        _ title: String,
        icon: String,
        renderingMode: Image.TemplateRenderingMode = .original
    ) -> some View {
        HStack(spacing: 8) {
            Image(icon)
                .renderingMode(renderingMode)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(title)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }

    private var selfHostedServer: some View {
        Form {
            Text("Self-hosted Server")
                .font(.headline)
            TextField("Server URL", text: $serverURL, prompt: Text("https://example.com"))
                .accessibilityIdentifier("self-hosted-server-url")
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

    private func signIn(_ action: @escaping () async throws -> Void) {
        applicationModel.errorHandling.fireAndHandleError {
            try await authenticationService.selectServer(nil)
            try await action()
        }
    }

    private func signInToSelfHostedServer() {
        guard (try? AppServerEnvironmentService.validatedURL(serverURL)) != nil else { return }
        showsSelfHostedSheet = false
        applicationModel.errorHandling.fireAndHandleError {
            try await authenticationService.selectServer(serverURL)
            try await authenticationService.signIn()
        }
    }
}
