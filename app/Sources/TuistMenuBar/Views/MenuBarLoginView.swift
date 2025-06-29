import SwiftUI
import TuistAuthentication

struct MenuBarLoginView: View {
    @EnvironmentObject var errorHandling: ErrorHandling
    @EnvironmentObject var authenticationService: AuthenticationService

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

            Text("Sign in to run previews")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Button(action: {
                errorHandling.fireAndHandleError {
                    try await authenticationService.signIn()
                }
            }) {
                Text("Sign in")
                    .frame(width: 168)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 42)
                    .background(Color(red: 111 / 255, green: 44 / 255, blue: 1.0))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            .padding(.horizontal, 12)
        }
    }
}
