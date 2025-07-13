import CryptoKit
import Foundation
import NukeUI
import SwiftUI

public enum NooraAvatarSize {
    case xxlarge
    case xlarge
    case large
    case medium
    case small
    case xsmall
    case xxsmall
}

public struct NooraAvatar: View {
    private let email: String
    private let avatarSize: NooraAvatarSize

    public init(
        email: String,
        size: NooraAvatarSize
    ) {
        self.email = email
        avatarSize = size
    }

    public var body: some View {
        LazyImage(url: gravatarURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: Noora.CornerRadius.xlarge))
            } else {
                RoundedRectangle(cornerRadius: Noora.CornerRadius.xlarge)
                    .fill(backgroundAvatarColor(for: avatarColor))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initialLetter)
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundColor(labelAvatarColor(for: avatarColor))
                    )
            }
        }
    }

    private var size: CGFloat {
        switch avatarSize {
        case .xxlarge:
            64
        case .xlarge:
            56
        case .large:
            46
        case .medium:
            40
        case .small:
            32
        case .xsmall:
            24
        case .xxsmall:
            20
        }
    }

    private var fontSize: CGFloat {
        switch avatarSize {
        case .xxlarge:
            24
        case .xlarge:
            20
        case .large:
            18
        case .medium:
            16
        case .small:
            14
        case .xsmall:
            14
        case .xxsmall:
            14
        }
    }

    private var initialLetter: String {
        String(email.prefix(1)).uppercased()
    }

    private var avatarColor: AvatarColor {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let emailData = Data(trimmedEmail.utf8)
        let hash = Insecure.MD5.hash(data: emailData)

        let colorIndex = abs(Int(hash.hashValue)) % AvatarColor.allCases.count
        return AvatarColor.allCases[colorIndex]
    }

    private enum AvatarColor: CaseIterable {
        case purple
        case pink
        case red
        case orange
        case yellow
        case azure
        case blue
        case gray
    }

    private func backgroundAvatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .purple:
            return Color(light: Noora.Colors.purple100, dark: Noora.Colors.purple800)
        case .pink:
            return Color(light: Noora.Colors.pink100, dark: Noora.Colors.pink800)
        case .red:
            return Color(light: Noora.Colors.red100, dark: Noora.Colors.red800)
        case .orange:
            return Color(light: Noora.Colors.orange100, dark: Noora.Colors.orange800)
        case .yellow:
            return Color(light: Noora.Colors.yellow100, dark: Noora.Colors.yellow800)
        case .azure:
            return Color(light: Noora.Colors.azure100, dark: Noora.Colors.azure800)
        case .blue:
            return Color(light: Noora.Colors.blue100, dark: Noora.Colors.blue800)
        case .gray:
            return Color(light: Noora.Colors.neutralLight300, dark: Noora.Colors.neutralDark900)
        }
    }

    private func labelAvatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .purple:
            return Color(light: Noora.Colors.purple800, dark: Noora.Colors.purple100)
        case .pink:
            return Color(light: Noora.Colors.pink800, dark: Noora.Colors.pink100)
        case .red:
            return Color(light: Noora.Colors.red800, dark: Noora.Colors.red100)
        case .orange:
            return Color(light: Noora.Colors.orange800, dark: Noora.Colors.orange100)
        case .yellow:
            return Color(light: Noora.Colors.yellow800, dark: Noora.Colors.yellow100)
        case .azure:
            return Color(light: Noora.Colors.azure800, dark: Noora.Colors.azure100)
        case .blue:
            return Color(light: Noora.Colors.blue800, dark: Noora.Colors.blue100)
        case .gray:
            return Color(light: Noora.Colors.neutralLight1200, dark: Noora.Colors.neutralDark50)
        }
    }

    private var gravatarURL: URL? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let emailData = Data(trimmedEmail.utf8)
        let hash = Insecure.MD5.hash(data: emailData)
        let hashString = hash.map { String(format: "%02hhx", $0) }.joined()

        return URL(string: "https://www.gravatar.com/avatar/\(hashString)?s=\(Int(size * 2))&d=404")
    }
}
