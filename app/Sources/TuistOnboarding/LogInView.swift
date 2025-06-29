import AuthenticationServices
import SwiftUI
import TuistAuthentication
import TuistErrorHandling

public struct LogInView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @StateObject private var authenticationService = AuthenticationService()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Tuist")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in to access your projects and collaborate with your team")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: { errorHandling.fireAndHandleError { try await authenticationService.signIn() } }) {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text("Sign in with Tuist")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Button(action: { errorHandling.fireAndHandleError { try await authenticationService.signInWithGitHub() } }) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("Sign in with GitHub")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Button(action: { errorHandling.fireAndHandleError { try await authenticationService.signInWithGoogle() } }) {
                HStack {
                    Image(systemName: "globe")
                    Text("Sign in with Google")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
}

#Preview {
    LogInView()
}
