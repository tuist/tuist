import Foundation
import SwiftUI

public enum Noora {
    public enum Colors {
        // MARK: - Chromatic Palette

        // MARK: Purple

        public static let purple50 = Color(hex: 0xF4F4FF)
        public static let purple100 = Color(hex: 0xD5D3FF)
        public static let purple200 = Color(hex: 0xB7B1FF)
        public static let purple300 = Color(hex: 0x9B8EFF)
        public static let purple400 = Color(hex: 0x8366FF)
        public static let purple500 = Color(hex: 0x6F2CFF)
        public static let purple600 = Color(hex: 0x5F00E5)
        public static let purple700 = Color(hex: 0x4600AE)
        public static let purple800 = Color(hex: 0x2E0078)
        public static let purple900 = Color(hex: 0x1A004B)

        // MARK: Pink

        public static let pink50 = Color(hex: 0xFFF1F3)
        public static let pink100 = Color(hex: 0xFFCBD4)
        public static let pink200 = Color(hex: 0xFFA3B4)
        public static let pink300 = Color(hex: 0xFF7494)
        public static let pink400 = Color(hex: 0xF44277)
        public static let pink500 = Color(hex: 0xD81B60)
        public static let pink600 = Color(hex: 0xB8004E)
        public static let pink700 = Color(hex: 0x890038)
        public static let pink800 = Color(hex: 0x5B0022)
        public static let pink900 = Color(hex: 0x350011)

        // MARK: Red

        public static let red50 = Color(hex: 0xFCEAE6)
        public static let red100 = Color(hex: 0xFFCFC6)
        public static let red200 = Color(hex: 0xFFAA9A)
        public static let red300 = Color(hex: 0xFF806B)
        public static let red400 = Color(hex: 0xFF462F)
        public static let red500 = Color(hex: 0xE51C01)
        public static let red600 = Color(hex: 0xBF1500)
        public static let red700 = Color(hex: 0x8D0D00)
        public static let red800 = Color(hex: 0x5D0500)
        public static let red900 = Color(hex: 0x350200)

        // MARK: Orange

        public static let orange50 = Color(hex: 0xFFF2EC)
        public static let orange100 = Color(hex: 0xFFDCCB)
        public static let orange200 = Color(hex: 0xFFC6A8)
        public static let orange300 = Color(hex: 0xFFAE83)
        public static let orange400 = Color(hex: 0xFF9458)
        public static let orange500 = Color(hex: 0xFD791C)
        public static let orange600 = Color(hex: 0xD15F00)
        public static let orange700 = Color(hex: 0x954200)
        public static let orange800 = Color(hex: 0x5B2500)
        public static let orange900 = Color(hex: 0x2C0E00)

        // MARK: Yellow

        public static let yellow50 = Color(hex: 0xFFF4DD)
        public static let yellow100 = Color(hex: 0xFFEBC0)
        public static let yellow200 = Color(hex: 0xFFE2A1)
        public static let yellow300 = Color(hex: 0xFFD880)
        public static let yellow400 = Color(hex: 0xFFCE58)
        public static let yellow500 = Color(hex: 0xFFC300)
        public static let yellow600 = Color(hex: 0xCD9C00)
        public static let yellow700 = Color(hex: 0x8E6B00)
        public static let yellow800 = Color(hex: 0x513C00)
        public static let yellow900 = Color(hex: 0x211600)

        // MARK: Green

        public static let green50 = Color(hex: 0xE0FFE2)
        public static let green100 = Color(hex: 0xACF5B3)
        public static let green200 = Color(hex: 0x75E785)
        public static let green300 = Color(hex: 0x5FD170)
        public static let green400 = Color(hex: 0x47BC5C)
        public static let green500 = Color(hex: 0x28A745)
        public static let green600 = Color(hex: 0x00852C)
        public static let green700 = Color(hex: 0x006420)
        public static let green800 = Color(hex: 0x003E10)
        public static let green900 = Color(hex: 0x001F05)

        // MARK: Azure

        public static let azure50 = Color(hex: 0xECF7FF)
        public static let azure100 = Color(hex: 0xB6E1FF)
        public static let azure200 = Color(hex: 0x7BCBFF)
        public static let azure300 = Color(hex: 0x53B2EC)
        public static let azure400 = Color(hex: 0x3699D1)
        public static let azure500 = Color(hex: 0x0280B9)
        public static let azure600 = Color(hex: 0x006A9A)
        public static let azure700 = Color(hex: 0x004E73)
        public static let azure800 = Color(hex: 0x00324B)
        public static let azure900 = Color(hex: 0x001B2B)

        // MARK: Blue

        public static let blue50 = Color(hex: 0xF0F6FF)
        public static let blue100 = Color(hex: 0xCCE0FF)
        public static let blue200 = Color(hex: 0xA9CAFF)
        public static let blue300 = Color(hex: 0x85B4FF)
        public static let blue400 = Color(hex: 0x5F9CFF)
        public static let blue500 = Color(hex: 0x3F85F5)
        public static let blue600 = Color(hex: 0x0F67E6)
        public static let blue700 = Color(hex: 0x0049AD)
        public static let blue800 = Color(hex: 0x002C6F)
        public static let blue900 = Color(hex: 0x00153D)

        // MARK: - Neutral Palette

        // MARK: Neutral Light

        public static let neutralLight50 = Color(hex: 0xFDFDFD)
        public static let neutralLight100 = Color(hex: 0xF9FAFA)
        public static let neutralLight200 = Color(hex: 0xF1F2F4)
        public static let neutralLight300 = Color(hex: 0xE6E8EA)
        public static let neutralLight400 = Color(hex: 0xD8DBDF)
        public static let neutralLight500 = Color(hex: 0xC7CCD1)
        public static let neutralLight600 = Color(hex: 0xB3BAC1)
        public static let neutralLight700 = Color(hex: 0x9DA6AF)
        public static let neutralLight800 = Color(hex: 0x848F9A)
        public static let neutralLight900 = Color(hex: 0x6A7581)
        public static let neutralLight1000 = Color(hex: 0x4E575F)
        public static let neutralLight1100 = Color(hex: 0x2E3338)
        public static let neutralLight1200 = Color(hex: 0x171A1C)

        // MARK: Neutral Dark

        public static let neutralDark50 = Color(hex: 0xDFE3EA)
        public static let neutralDark100 = Color(hex: 0xCACED4)
        public static let neutralDark200 = Color(hex: 0x9EA2A8)
        public static let neutralDark300 = Color(hex: 0x85888E)
        public static let neutralDark400 = Color(hex: 0x73767C)
        public static let neutralDark500 = Color(hex: 0x696C72)
        public static let neutralDark600 = Color(hex: 0x5D6066)
        public static let neutralDark700 = Color(hex: 0x4E5157)
        public static let neutralDark800 = Color(hex: 0x45484D)
        public static let neutralDark900 = Color(hex: 0x3A3D43)
        public static let neutralDark1000 = Color(hex: 0x2F3237)
        public static let neutralDark1100 = Color(hex: 0x1F2126)
        public static let neutralDark1200 = Color(hex: 0x16181C)

        // MARK: - Alpha Colors

        public static let blackAlpha = Color(hex: 0x000000, alpha: 0.8)
        public static let neutralGray50Alpha = Color(hex: 0x3A3D43, alpha: 0.5)
        public static let neutralGray24Alpha = Color(hex: 0x2E3338, alpha: 0.24)
        public static let neutralGray16Alpha = Color(hex: 0x45484D, alpha: 0.16)
        public static let redAlpha = Color(hex: 0xE51C01, alpha: 0.2)
        public static let orangeAlpha = Color(hex: 0xFD791C, alpha: 0.16)
        public static let yellowAlpha = Color(hex: 0xFFC300, alpha: 0.16)
        public static let greenAlpha = Color(hex: 0x28A745, alpha: 0.16)
        public static let azureAlpha = Color(hex: 0x0280B9, alpha: 0.16)
        public static let blueAlpha = Color(hex: 0x3F85F5, alpha: 0.24)
        public static let purpleAlpha = Color(hex: 0x6F2CFF, alpha: 0.24)
        public static let pinkAlpha = Color(hex: 0xD81B60, alpha: 0.24)

        // MARK: - Semantic Colors

        // MARK: Surface

        public static let surfaceOverlay = Color(light: neutralGray24Alpha, dark: neutralGray16Alpha)
        public static let surfaceBackgroundPrimary = Color(light: neutralLight50, dark: neutralDark1200)
        public static let surfaceBackgroundSecondary = Color(light: neutralLight200, dark: neutralDark1100)
        public static let surfaceBackgroundTertiary = Color(light: neutralLight100, dark: neutralDark1100)

        // MARK: Label

        public static let surfaceLabelPrimary = Color(light: neutralLight1200, dark: neutralLight50)
        public static let surfaceLabelSecondary = Color(light: neutralLight800, dark: neutralLight500)
        public static let surfaceLabelTertiary = Color(light: neutralLight700, dark: neutralDark500)
        public static let surfaceLabelDestructive = Color(light: red500, dark: red300)
        public static let surfaceLabelSuccess = Color(light: green500, dark: green400)
        public static let surfaceLabelDisabled = Color(light: neutralLight600, dark: neutralDark300)

        // MARK: Table

        public static let surfaceTableHeader = Color(light: neutralLight200, dark: neutralDark1000)

        // MARK: Button

        public static let buttonPrimaryBackground = Color(light: purple500, dark: purple600)
        public static let buttonPrimaryLabel = Color(light: neutralLight50, dark: neutralLight50)
        public static let buttonSecondaryBackground = Color(light: neutralLight50, dark: neutralDark1100)
        public static let buttonSecondaryLabel = Color(light: neutralLight1200, dark: neutralLight50)
        public static let buttonEnabledLabel = Color(light: purple500, dark: purple400)
        public static let buttonEnabledBackground = Color(light: purple500.opacity(0.15), dark: purple500.opacity(0.20))
        public static let buttonDisabledLabel = Color(
            light: Color(hex: 0x3C3C43, alpha: 0.3),
            dark: Color(hex: 0x696C72, alpha: 0.6)
        )
        public static let buttonDisabledBackground = Color(
            light: Color(hex: 0x787880, alpha: 0.12),
            dark: Color(hex: 0x787880, alpha: 0.24)
        )

        // MARK: Badge

        public static let badgeInformationLabel = Color(light: azure700, dark: azure400)
        public static let badgeInformationBackground = Color(light: azure50, dark: azureAlpha)

        // MARK: Accent

        public static let accent = Color(light: purple500, dark: purple400)
    }

    public enum Spacing {
        public static let spacing0: CGFloat = 0
        public static let spacing1: CGFloat = 2
        public static let spacing2: CGFloat = 4
        public static let spacing3: CGFloat = 6
        public static let spacing4: CGFloat = 8
        public static let spacing5: CGFloat = 12
        public static let spacing6: CGFloat = 16
        public static let spacing7: CGFloat = 20
        public static let spacing8: CGFloat = 24
        public static let spacing9: CGFloat = 32
        public static let spacing10: CGFloat = 40
        public static let spacing11: CGFloat = 48
        public static let spacing12: CGFloat = 56
        public static let spacing13: CGFloat = 64
        public static let spacing14: CGFloat = 72
        public static let spacing15: CGFloat = 80
        public static let spacing16: CGFloat = 96
    }

    public enum CornerRadius {
        public static let none: CGFloat = 0
        public static let xsmall: CGFloat = 2
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 6
        public static let large: CGFloat = 8
        public static let xlarge: CGFloat = 12
        public static let xxlarge: CGFloat = 16
        public static let max: CGFloat = 9999
    }
}

// MARK: - Color Extension

extension Color {
    public init(hex: Int, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    public init(
        light: Color,
        dark: Color
    ) {
        self.init(
            uiColor: UIColor(
                light: UIColor(light),
                dark: UIColor(dark)
            )
        )
    }
}

extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light, .unspecified:
                return light
            case .dark:
                return dark
            @unknown default:
                return light
            }
        }
    }
}
