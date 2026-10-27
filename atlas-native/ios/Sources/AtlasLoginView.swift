import SwiftUI

struct AtlasLoginView: View {
    @ObservedObject var authentication: AtlasAuthentication
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSelfHosted = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)
                    Image("AtlasMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(width: 60, height: 60)
                        .background(AtlasBrand.accent, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                        .padding(.bottom, 32)

                    Text("Welcome to Atlas")
                        .font(.title.weight(.medium))
                        .foregroundStyle(AtlasBrand.label)
                        .padding(.bottom, 12)
                        .accessibilityAddTraits(.isHeader)

                    Text("Sign in to access your workspace and\ncollaborate with your team")
                        .font(.subheadline.weight(.regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AtlasBrand.label)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 80)

                    Spacer(minLength: 32)
                    signIn(bottomInset: geometry.safeAreaInsets.bottom)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
        .background {
            Image("AtlasLoginBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        }
        .tint(AtlasBrand.accent)
        .alert("Self-hosted server", isPresented: $showingSelfHosted) {
            TextField("https://atlas.example.com", text: $authentication.selfHostedAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Sign in") { Task { await authentication.signIn(selfHosted: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the HTTPS address of your Atlas server.")
        }
    }

    private func signIn(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            if authentication.busy {
                ProgressView("Signing in…")
                    .font(.footnote)
            }
            if let message = authentication.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            AtlasSignInButton(title: "Sign in with Atlas", primary: true, image: "AtlasMark") {
                Task { await authentication.signIn() }
            }
            AtlasSignInButton(title: "Sign in with Google", image: "GoogleLogo") {
                Task { await authentication.signIn(provider: .google) }
            }
            .accessibilityIdentifier("atlas.sign-in.google")
            HStack(spacing: 8) {
                line
                Text("or")
                    .font(.footnote)
                    .foregroundStyle(AtlasBrand.tertiaryLabel)
                line
            }
            .accessibilityHidden(true)
            AtlasSignInButton(title: "Self-hosted server") { showingSelfHosted = true }
        }
        .disabled(authentication.busy)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(colorScheme == .dark ? Color(white: 14 / 255).opacity(0.8) : .white.opacity(0.6))
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                        .stroke(colorScheme == .dark ? Color(white: 31 / 255) : .white, lineWidth: 2)
                }
                .padding(.bottom, -bottomInset)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(AtlasBrand.tertiaryLabel.opacity(0.3))
            .frame(height: 1)
    }
}
