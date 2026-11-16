import SwiftUI
import TuistGuildCore

/// Noora's semantic colors, the tokens the server's components use, read from
/// the Rust core (`tuist_app_theme`) so every client shares one source. Each
/// color follows the system light/dark appearance.
enum Noora {
    static let backgroundPrimary = color("surface-background-primary")
    static let backgroundSecondary = color("surface-background-secondary")
    static let backgroundTertiary = color("surface-background-tertiary")
    static let labelPrimary = color("surface-label-primary")
    static let labelSecondary = color("surface-label-secondary")
    static let labelDestructive = color("surface-label-destructive")
    static let border = color("surface-border-primary")
    static let primary = color("button-primary-background")
    static let primaryLabel = color("button-primary-label")
    static let neutralHover = color("button-neutral-background-hover")

    private static let tokens: [String: [String: String]] = {
        guard let pointer = tuist_app_theme(),
              let value = try? JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8))
        else { return [:] }
        return value as? [String: [String: String]] ?? [:]
    }()

    private static func color(_ name: String) -> Color {
        let light = rgb(tokens["light"]?[name])
        let dark = rgb(tokens["dark"]?[name])
        #if os(iOS)
            return Color(uiColor: UIColor { traits in
                let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            })
        #else
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let (r, g, b) = isDark ? dark : light
                return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            })
        #endif
    }

    private static func rgb(_ hex: String?) -> (CGFloat, CGFloat, CGFloat) {
        let value = UInt32(hex?.dropFirst() ?? "", radix: 16) ?? 0
        return (CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255)
    }
}
