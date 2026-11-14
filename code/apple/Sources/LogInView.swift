import SwiftUI

/// The shipping app's `LogInView` (`app/Sources/TuistOnboarding`), adapted to the Rust
/// core's browser sign-in. Social providers always use Tuist-hosted; the self-hosted
/// prompt is the only way to pick another server.
struct LogInView: View {
    @ObservedObject var client: AppClient
    @State private var selfHosted = false
    @State private var server = ""

    var body: some View {
        Group {
            #if os(iOS)
                // Scrolls when landscape phones or large text sizes leave too little height; the
                // card still reaches the bottom edge, padded by the safe area like the original.
                GeometryReader { geometry in
                    ScrollView {
                        content(bottomInset: geometry.safeAreaInsets.bottom)
                            .frame(minHeight: geometry.size.height + geometry.safeAreaInsets.bottom)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            #else
                // The macOS window's minimum size always fits the content.
                content(bottomInset: 0)
            #endif
        }
        .disabled(client.signingIn)
        .background(
            Image("LaunchScreenBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .alert("Self-hosted", isPresented: $selfHosted) {
            TextField(text: $server, prompt: Text(verbatim: "https://example.com")) { Text("Server URL") }
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            Button("Sign in") { signIn(server: server.trimmingCharacters(in: .whitespaces), provider: "tuist") }
                .disabled(URL(string: server.trimmingCharacters(in: .whitespaces))?.scheme != "https")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use the root address of your Tuist server")
        }
    }

    private func content(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Image("TuistRoundedIcon")
                .resizable()
                .frame(width: 60, height: 60)
                .padding(.bottom, 32)
            Text("Welcome to Tuist Code")
                .font(.title.weight(.medium))
                .foregroundStyle(LogInColors.labelPrimary)
                .padding(.bottom, 12)
            Text("Sign in to access your projects and\ncollaborate with your team")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(LogInColors.labelPrimary)
                .padding(.bottom, 80)
            if client.signingIn { ProgressView() }
            Spacer()
            providers(bottomInset: bottomInset)
        }
        .frame(maxWidth: .infinity)
    }

    private func providers(bottomInset: CGFloat) -> some View {
        VStack(spacing: 12) {
            SocialButton(title: "Sign in with Tuist", icon: "TuistLogo", primary: true) {
                signIn(server: "https://tuist.dev", provider: "tuist")
            }
            SocialButton(title: "Sign in with Apple", icon: "AppleLogo") {
                signIn(server: "https://tuist.dev", provider: "apple")
            }
            SocialButton(title: "Sign in with Google", icon: "GoogleLogo") {
                signIn(server: "https://tuist.dev", provider: "google")
            }
            SocialButton(title: "Sign in with GitHub", icon: "GitHubLogo") {
                signIn(server: "https://tuist.dev", provider: "github")
            }
            HStack(spacing: 8) {
                divider
                Text("or").font(.footnote).foregroundStyle(LogInColors.labelTertiary)
                divider
            }
            .accessibilityHidden(true)
            SocialButton(title: "Self-hosted server", icon: "ServerIcon") {
                // Like the shipping app, prefill the last self-hosted server the user signed in to.
                server = client.view.profiles.map(\.server).last { !$0.hasPrefix("https://tuist.dev") } ?? ""
                selfHosted = true
            }
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        #if os(macOS)
            .padding(.bottom, 32)
        #else
            .padding(.bottom, 8 + bottomInset)
        #endif
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(LogInColors.cardBackground)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                        .stroke(LogInColors.cardBorder, lineWidth: 2)
                )
        )
    }

    private var divider: some View {
        Rectangle().fill(LogInColors.labelTertiary.opacity(0.3)).frame(height: 1)
    }

    private func signIn(server: String, provider: String) {
        Task { await client.signIn(server: server, provider: provider) }
    }
}

private struct SocialButton: View {
    let title: LocalizedStringKey
    let icon: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(icon).renderingMode(icon == "ServerIcon" ? .template : .original).frame(width: 20, height: 20)
                Text(title).font(.body.weight(.medium)).padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    primary ? LogInColors.primaryBackground : LogInColors.secondaryBackground
                    LinearGradient(
                        colors: primary ? [.white.opacity(0.16), .clear] : [.clear, .gray.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            )
            .foregroundStyle(primary ? LogInColors.primaryLabel : LogInColors.labelPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.05), radius: 0.5, x: 0, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(primary ? Color(hex: 0x5F01E5, alpha: 0.898) : .black.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The Noora tokens the shipping `LogInView` uses.
private enum LogInColors {
    static let labelPrimary = Color(light: Color(hex: 0x171A1C), dark: Color(hex: 0xFDFDFD))
    static let labelTertiary = Color(light: Color(hex: 0x9DA6AF), dark: Color(hex: 0x696C72))
    static let primaryBackground = Color(light: Color(hex: 0x6F2CFF), dark: Color(hex: 0x5F00E5))
    static let primaryLabel = Color(hex: 0xFDFDFD)
    static let secondaryBackground = Color(light: Color(hex: 0xFDFDFD), dark: Color(hex: 0x1F2126))
    static let cardBackground = Color(light: .white.opacity(0.6), dark: Color(hex: 0x0E0E0E, alpha: 0.8))
    static let cardBorder = Color(light: .white, dark: Color(hex: 0x1F1F1F))
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(light: Color, dark: Color) {
        #if os(iOS)
            self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
            self.init(NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
            })
        #endif
    }
}
