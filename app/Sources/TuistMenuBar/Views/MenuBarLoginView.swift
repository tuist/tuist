import SwiftUI

struct MenuBarLoginView: View {
    let openLoginWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("TuistIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Tuist")
                        .font(.headline)
                    Text("Sign in to run previews")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: openLoginWindow) {
                Text("Sign in")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(red: 111 / 255, green: 44 / 255, blue: 1))
                    .foregroundStyle(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
