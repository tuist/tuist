import AuthenticationServices
import SwiftUI

public struct LogInView: View {
    @StateObject private var viewModel = LoginViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Tuist")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in to access your projects and collaborate with your team")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: { viewModel.signIn() }) {
                HStack {
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                    Text(viewModel.isAuthenticating ? "Signing in..." : "Sign in with Tuist")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isAuthenticating)

            Button(action: { viewModel.signInWithGitHub() }) {
                HStack {
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    Text(viewModel.isAuthenticating ? "Signing in..." : "Sign in with GitHub")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isAuthenticating)

            Button(action: { viewModel.signInWithGoogle() }) {
                HStack {
                    if viewModel.isAuthenticating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "globe")
                    }
                    Text(viewModel.isAuthenticating ? "Signing in..." : "Sign in with Google")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isAuthenticating)

            if let error = viewModel.authenticationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

#Preview {
    LogInView()
}
