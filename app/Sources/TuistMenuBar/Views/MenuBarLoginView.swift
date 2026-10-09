import SwiftUI
import TuistAuthentication

struct MenuBarLoginView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @EnvironmentObject var authenticationService: AuthenticationService
    @State private var step: Step = .signIn
    @State private var serverURL = ""

    private enum Step {
        case signIn
        case selfHosted
    }

    private var invalidServerURL: Bool {
        (try? AppServerEnvironmentService.validatedURL(serverURL)) == nil
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack {
                Spacer()
                Image("TuistIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Text("Welcome to Tuist")
                .font(.title2)
                .fontWeight(.medium)
                .padding(.bottom, 6)

            switch step {
            case .signIn:
                signIn
            case .selfHosted:
                selfHosted
            }
        }
        .disabled(authenticationService.isSigningIn)
    }

    private var selfHosted: some View {
        VStack(spacing: 0) {
            caption("Use the root address of your Tuist server")

            TextField("https://example.com", text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { selectSelfHostedServer() }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            primaryButton("Save & Continue") {
                selectSelfHostedServer()
            }
            .disabled(invalidServerURL)
            .padding(.bottom, 8)

            secondaryButton("Cancel") {
                step = .signIn
            }
            .padding(.bottom, 16)
        }
    }

    private var signIn: some View {
        VStack(spacing: 0) {
            caption("Sign in to run previews")

            if let selfHostedServerURL = authenticationService.selfHostedServerURL {
                Button {
                    editSelfHostedServer()
                } label: {
                    Label(selfHostedServerURL, image: "ServerIcon")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Change the self-hosted server address")
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }

            primaryButton("Sign in with Tuist", icon: "TuistLogo") {
                errorHandling.fireAndHandleError {
                    try await authenticationService.signIn()
                }
            }
            .padding(.bottom, 8)

            secondaryButton("Sign in with Google", icon: "GoogleLogo") {
                errorHandling.fireAndHandleError {
                    try await authenticationService.signInWithGoogle()
                }
            }
            .padding(.bottom, 8)

            secondaryButton("Sign in with GitHub", icon: "GitHubLogo") {
                errorHandling.fireAndHandleError {
                    try await authenticationService.signInWithGitHub()
                }
            }
            .padding(.bottom, 12)

            divider
                .padding(.bottom, 12)

            if authenticationService.selfHostedServerURL == nil {
                secondaryButton("Self-hosted server", icon: "ServerIcon") {
                    editSelfHostedServer()
                }
                .padding(.bottom, 16)
            } else {
                secondaryButton("Use Tuist-hosted") {
                    errorHandling.fireAndHandleError {
                        try await authenticationService.selectServer(nil)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 8) {
            line
            Text("or")
                .font(.caption)
                .foregroundColor(.secondary)
            line
        }
        .padding(.horizontal, 24)
        .accessibilityHidden(true)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
    }

    private func buttonLabel(_ title: String, icon: String?) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            Text(title)
        }
    }

    private func primaryButton(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buttonLabel(title, icon: icon)
                .frame(width: 168)
                .padding(.vertical, 6)
                .padding(.horizontal, 42)
                .background(Color(red: 111 / 255, green: 44 / 255, blue: 1.0))
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    private func secondaryButton(
        _ title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            buttonLabel(title, icon: icon)
                .frame(width: 168)
                .padding(.vertical, 6)
                .padding(.horizontal, 42)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    private func editSelfHostedServer() {
        serverURL = authenticationService.selfHostedServerURL ?? ""
        step = .selfHosted
    }

    private func selectSelfHostedServer() {
        guard !invalidServerURL else { return }
        errorHandling.fireAndHandleError {
            try await authenticationService.selectServer(serverURL)
            step = .signIn
        }
    }
}
