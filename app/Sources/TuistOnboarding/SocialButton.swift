import SwiftUI
import TuistNoora

struct SocialButton: View {
    enum Style {
        case primary
        case secondary
    }

    private let title: String
    private let style: Style
    private let icon: String?
    private let action: () -> Void

    init(
        title: String,
        style: Style = .primary,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Noora.Spacing.spacing1) {
                if let icon {
                    Image(icon)
                        .frame(width: 20, height: 20)
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, Noora.Spacing.spacing2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Noora.Spacing.spacing5)
            .background(backgroundView)
            .foregroundColor(foregroundColor)
            .cornerRadius(Noora.CornerRadius.large)
            .shadow(color: .black.opacity(0.05), radius: 0.5, x: 0, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: Noora.CornerRadius.large)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            ZStack {
                Noora.Colors.buttonPrimaryBackground
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .secondary:
            ZStack {
                Noora.Colors.buttonSecondaryBackground
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.gray.opacity(0.06),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color(hex: 0x5F01E5, alpha: 0.898)
        case .secondary:
            return Color.black.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return Noora.Colors.buttonPrimaryLabel
        case .secondary:
            return Noora.Colors.buttonSecondaryLabel
        }
    }
}

#Preview("Primary Button") {
    VStack(spacing: 16) {
        SocialButton(
            title: "Sign in with Tuist",
            style: .primary,
            icon: "brand-tuist"
        ) {
            print("Primary button tapped")
        }

        SocialButton(
            title: "Primary without icon",
            style: .primary
        ) {
            print("Primary button without icon tapped")
        }
    }
    .padding()
}

#Preview("Secondary Button") {
    VStack(spacing: 16) {
        SocialButton(
            title: "Sign in with Google",
            style: .secondary,
            icon: "brand-google"
        ) {
            print("Secondary button tapped")
        }

        SocialButton(
            title: "Secondary without icon",
            style: .secondary
        ) {
            print("Secondary button without icon tapped")
        }
    }
    .padding()
}
