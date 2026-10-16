import SwiftUI
import UIKit

enum AtlasBrand {
    static let accent = Color(red: 8 / 255, green: 124 / 255, blue: 170 / 255)
    static let primaryBorder = Color(red: 6 / 255, green: 97 / 255, blue: 133 / 255)
    static let label = adaptive(light: 0x171A1C, dark: 0xFDFDFD)
    static let tertiaryLabel = adaptive(light: 0x9DA6AF, dark: 0x696C72)
    static let secondaryBackground = adaptive(light: 0xFDFDFD, dark: 0x1F2126)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct AtlasSignInButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if primary {
                    Image("AtlasMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "server.rack")
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                ZStack {
                    primary ? AtlasBrand.accent : AtlasBrand.secondaryBackground
                    LinearGradient(
                        colors: primary ? [.white.opacity(0.16), .clear] : [.clear, .gray.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .foregroundStyle(primary ? Color.white : AtlasBrand.label)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.05), radius: 0.5, x: 0, y: 1)
            .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(primary ? AtlasBrand.primaryBorder.opacity(0.898) : .black.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
