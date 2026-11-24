import Observation
import SwiftUI
import LuftCore

/// The themes the Rust core offers (`tuist_app_theme`): Noora, the tokens the
/// server's components use, then Omarchy's palettes mapped to the same tokens.
/// Profile picks one; the choice stays on this device.
@Observable
final class Themes {
    struct Theme: Identifiable {
        let id: String
        let name: String
        /// The appearance an Omarchy theme imposes; nil follows the system.
        let appearance: ColorScheme?
        fileprivate let light: [String: String]
        fileprivate let dark: [String: String]
        /// NSH theme override files for cards, by appearance ("light", "dark").
        fileprivate let card: [String: Any]

        /// The NSH theme overrides that give a card this theme's colors.
        func cardOverrides(dark isDark: Bool) -> String? {
            card[isDark ? "dark" : "light"]
                .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
        }

        fileprivate func hex(_ token: String, dark isDark: Bool) -> String? {
            (isDark ? dark : light)[token]
        }

        /// A token's color in this theme for an appearance, for previews.
        func color(_ token: String, dark isDark: Bool) -> Color {
            let (r, g, b) = Noora.rgb(hex(token, dark: isDark))
            return Color(red: r, green: g, blue: b)
        }
    }

    static let shared = Themes()

    /// The catalog's themes, then the custom one the agent made, if any.
    var all: [Theme] { catalog + [custom].compactMap { $0 } }
    var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.key) }
    }

    /// The chosen theme, or the default when a saved one no longer exists.
    var selected: Theme {
        all.first { $0.id == selectedID } ?? all[0]
    }

    private let catalog: [Theme]
    /// The theme a thread's agent made with `set_theme` (`id` `custom`); it
    /// stays on this device and in Profile as Custom.
    private var custom: Theme?

    private static let key = "theme"
    private static let customKey = "custom_theme"

    private init() {
        let catalog = tuist_app_theme()
            .flatMap { try? JSONSerialization.jsonObject(with: Data(String(cString: $0).utf8)) } as? [String: Any]
        let themes = (catalog?["themes"] as? [[String: Any]] ?? []).map(Self.theme)
        self.catalog = themes.isEmpty ? [Theme(id: "noora", name: "Tuist", appearance: nil, light: [:], dark: [:], card: [:])] : themes
        custom = UserDefaults.standard.dictionary(forKey: Self.customKey).map(Self.theme)
        selectedID = UserDefaults.standard.string(forKey: Self.key) ?? catalog?["default"] as? String ?? "noora"
    }

    /// Applies and selects a custom theme the core built from the agent's
    /// `set_theme` call. Every view drawing with `Noora` redraws at once.
    func apply(custom value: [String: Any]) {
        UserDefaults.standard.set(value, forKey: Self.customKey)
        custom = Self.theme(value)
        selectedID = custom!.id
    }

    private static func theme(_ theme: [String: Any]) -> Theme {
        Theme(
            id: theme["id"] as? String ?? "",
            // Profile shows the custom theme under its localized name.
            name: theme["id"] as? String == "custom" ? String(localized: "Custom") : theme["name"] as? String ?? "",
            appearance: (theme["appearance"] as? String).map { $0 == "dark" ? .dark : .light },
            light: theme["light"] as? [String: String] ?? [:],
            dark: theme["dark"] as? [String: String] ?? [:],
            card: theme["card"] as? [String: Any] ?? [:]
        )
    }
}

/// Noora's semantic colors in the selected theme. Each color follows the
/// system light/dark appearance, and views redraw when the theme changes.
enum Noora {
    static var backgroundPrimary: Color { color("surface-background-primary") }
    static var backgroundSecondary: Color { color("surface-background-secondary") }
    static var backgroundTertiary: Color { color("surface-background-tertiary") }
    static var labelPrimary: Color { color("surface-label-primary") }
    static var labelSecondary: Color { color("surface-label-secondary") }
    static var labelDestructive: Color { color("surface-label-destructive") }
    static var border: Color { color("surface-border-primary") }
    static var primary: Color { color("button-primary-background") }
    static var primaryLabel: Color { color("button-primary-label") }
    static var neutralHover: Color { color("button-neutral-background-hover") }

    private static func color(_ name: String) -> Color {
        let theme = Themes.shared.selected
        let light = rgb(theme.hex(name, dark: false))
        let dark = rgb(theme.hex(name, dark: true))
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

    fileprivate static func rgb(_ hex: String?) -> (CGFloat, CGFloat, CGFloat) {
        let value = UInt32(hex?.dropFirst() ?? "", radix: 16) ?? 0
        return (CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255)
    }
}

/// Profile's theme choice: each theme's name beside a preview of its colors.
struct ThemePicker: View {
    @Bindable var themes = Themes.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Picker("Theme", selection: $themes.selectedID) {
            ForEach(themes.all) { theme in
                Label {
                    Text(verbatim: theme.name)
                } icon: {
                    swatch(theme)
                }
                .tag(theme.id)
            }
        }
        #if os(iOS)
        .pickerStyle(.navigationLink)
        #endif
    }

    private func swatch(_ theme: Themes.Theme) -> some View {
        let dark = theme.appearance.map { $0 == .dark } ?? (colorScheme == .dark)
        return ZStack {
            Circle().fill(theme.color("surface-background-primary", dark: dark))
            Circle().strokeBorder(theme.color("surface-border-primary", dark: dark), lineWidth: 1)
            Circle().fill(theme.color("button-primary-background", dark: dark)).padding(6)
        }
        .frame(width: 22, height: 22)
    }
}
