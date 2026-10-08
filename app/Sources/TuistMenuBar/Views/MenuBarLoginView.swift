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

            primaryButton(authenticationService.isSigningIn ? "Signing in…" : "Sign in") {
                errorHandling.fireAndHandleError {
                    try await authenticationService.signIn()
                }
            }
            .padding(.bottom, 8)

            if authenticationService.selfHostedServerURL == nil {
                secondaryButton("Self-hosted server") {
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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
