import Foundation
import SwiftUI
import UIKit

enum AtlasSettingsStyle {
    static let tint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 102 / 255, green: 199 / 255, blue: 232 / 255, alpha: 1)
            : UIColor(red: 8 / 255, green: 124 / 255, blue: 170 / 255, alpha: 1)
    })
    static let onTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
}

struct AtlasThemeCatalog: Codable {
    let schemaVersion: Int
    let revision: String
    let defaultThemeId: String
    let themes: [AtlasTheme]
}

struct AtlasTheme: Codable, Identifiable {
    struct Palette: Codable {
        let background: String
        let surface: String
        let text: String
        let secondaryText: String
        let border: String
        let accent: String
        let onAccent: String
        let tint: String
    }

    let id: String
    let name: String
    let description: String
    let typography: String
    let buttonRadius: Double
    let cardRadius: Double
    let light: Palette
    let dark: Palette

    func palette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }
}

@MainActor
final class AtlasAppearance: ObservableObject {
    enum Mode: String, CaseIterable {
        case system, light, dark
        var title: String { rawValue.capitalized }
        var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    }

    @Published private(set) var server: URL?
    @Published private(set) var catalog: AtlasThemeCatalog?
    @Published private(set) var selection = "server-default"
    @Published private(set) var mode = Mode.system
    private let preferences: UserDefaults
    private let request: ([String: Any]) async throws -> Data
    private var generation = UUID()
    private var refreshedAt: Date?
    private var loading = false

    init(preferences: UserDefaults = .standard,
         request: @escaping ([String: Any]) async throws -> Data = AtlasAppearance.bridge) {
        self.preferences = preferences
        self.request = request
    }

    var activeSelection: String {
        catalog?.themes.contains(where: { $0.id == selection }) == true ? selection : "server-default"
    }

    var theme: AtlasTheme? {
        guard let catalog else { return nil }
        return catalog.themes.first { $0.id == activeSelection }
            ?? catalog.themes.first { $0.id == catalog.defaultThemeId }
    }

    func configure(server: URL?) async {
        guard self.server != server || (catalog == nil && !loading) else { await refresh(); return }
        self.server = server
        generation = UUID()
        let identity = generation
        catalog = nil
        refreshedAt = nil
        loading = true
        selection = server.flatMap { preferences.string(forKey: key("theme", server: $0)) } ?? "server-default"
        mode = server.flatMap { preferences.string(forKey: key("mode", server: $0)) }.flatMap(Mode.init) ?? .system
        if let data = try? await request(["operation": "default_themes"]), identity == generation {
            catalog = try? decode(data)
        }
        guard identity == generation else { return }
        guard let server else { loading = false; return }
        if let cached = preferences.data(forKey: key("catalog", server: server)), cached.count <= 65_536,
           let value = try? JSONSerialization.jsonObject(with: cached),
           let validated = try? await request(["operation": "validate_themes", "catalog": value]),
           identity == generation, let catalog = try? decode(validated) {
            self.catalog = catalog
        }
        guard identity == generation else { return }
        loading = false
        await refresh()
    }

    func refresh() async {
        guard let server, !loading, refreshedAt.map({ Date().timeIntervalSince($0) >= 300 }) ?? true else { return }
        let identity = generation
        loading = true
        defer { if identity == generation { loading = false; refreshedAt = .now } }
        guard let data = try? await request(["operation": "themes", "server": server.absoluteString]),
              identity == generation, let catalog = try? decode(data) else { return }
        self.catalog = catalog
        preferences.set(data, forKey: key("catalog", server: server))
    }

    func choose(theme: String) {
        guard let server, theme == "server-default" || catalog?.themes.contains(where: { $0.id == theme }) == true else { return }
        selection = theme
        preferences.set(theme, forKey: key("theme", server: server))
    }

    func choose(mode: Mode) {
        guard let server else { return }
        self.mode = mode
        preferences.set(mode.rawValue, forKey: key("mode", server: server))
    }

    private func key(_ field: String, server: URL) -> String { "atlas.appearance.\(server.absoluteString).\(field)" }

    private func decode(_ data: Data) throws -> AtlasThemeCatalog {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AtlasThemeCatalog.self, from: data)
    }

    nonisolated static func bridge(_ action: [String: Any]) async throws -> Data {
        let input = try JSONSerialization.data(withJSONObject: action)
        let output = try await AtlasAuthBridge.execute(String(decoding: input, as: UTF8.self))
        let envelope = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        guard let value = envelope?["ok"] else { throw CancellationError() }
        return try JSONSerialization.data(withJSONObject: value)
    }
}

private struct AtlasThemeKey: EnvironmentKey {
    static let defaultValue: AtlasTheme? = nil
}

extension EnvironmentValues {
    var atlasTheme: AtlasTheme? {
        get { self[AtlasThemeKey.self] }
        set { self[AtlasThemeKey.self] = newValue }
    }
}

struct AtlasPrimaryAction: ViewModifier {
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if contrast == .increased {
            content
        } else {
            let palette = theme?.palette(scheme)
            content
                .tint(palette.map { Color(atlasHex: $0.accent) } ?? AtlasSettingsStyle.tint)
                .foregroundStyle(palette.map { Color(atlasHex: $0.onAccent) } ?? AtlasSettingsStyle.onTint)
        }
    }
}

extension Color {
    init(atlasHex: String) {
        let value = UInt32(atlasHex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct AtlasThemeScope: ViewModifier {
    @ObservedObject var appearance: AtlasAppearance
    let server: URL?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let active = server != nil && server == appearance.server
        let theme = active ? appearance.theme : nil
        let palette = theme?.palette(appearance.mode.scheme ?? scheme)
        let tint = contrast == .increased ? Color(uiColor: .systemBlue) : palette.map { Color(atlasHex: $0.tint) } ?? AtlasSettingsStyle.tint
        content
            .environmentObject(appearance)
            .environment(\.atlasTheme, contrast == .increased ? nil : theme)
            .preferredColorScheme(active ? appearance.mode.scheme : nil)
            .tint(tint)
            .accentColor(tint)
    }
}

struct AtlasThemedContent: ViewModifier {
    @Environment(\.atlasTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if let theme {
            content.scrollContentBackground(.hidden)
                .background(Color(atlasHex: theme.palette(scheme).background))
        } else {
            content
        }
    }
}
