import Foundation
import Testing

@MainActor
struct AtlasAppearanceTests {
    private let first = URL(string: "https://first.example.org")!
    private let second = URL(string: "https://second.example.org")!

    @Test func olderServersKeepAtlasAndSelectionsAreLocalToTheirServer() async throws {
        let suite = "atlas.appearance.tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let catalog = try await companyCatalog()
        var unavailable = false
        let request: ([String: Any]) async throws -> Data = { action in
            if action["operation"] as? String == "themes" {
                if unavailable { throw CancellationError() }
                return catalog
            }
            return try await AtlasAppearance.bridge(action)
        }
        let model = AtlasAppearance(preferences: preferences, request: request)
        await model.configure(server: first)
        model.choose(theme: "berlin")
        model.choose(mode: .dark)
        unavailable = true

        let restored = AtlasAppearance(preferences: preferences, request: request)
        await restored.configure(server: first)
        #expect(restored.theme?.id == "berlin" && restored.mode == .dark)
        await restored.configure(server: second)
        #expect(restored.theme?.id == "atlas" && restored.mode == .system)
        #expect(restored.activeSelection == "server-default")
        await restored.configure(server: first)
        #expect(restored.theme?.id == "berlin" && restored.mode == .dark)
        restored.choose(theme: "unpublished")
        #expect(restored.theme?.id == "berlin")
    }

    @Test func removedThemesFallBackWithoutLosingTheLocalChoice() async throws {
        let suite = "atlas.appearance.tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let catalog = try await companyCatalog()
        var removed = false
        let request: ([String: Any]) async throws -> Data = { action in
            guard action["operation"] as? String == "themes" else { return try await AtlasAppearance.bridge(action) }
            if !removed { return catalog }
            return try await AtlasAppearance.bridge(["operation": "default_themes"])
        }
        let model = AtlasAppearance(preferences: preferences, request: request)
        await model.configure(server: first)
        model.choose(theme: "berlin")
        removed = true
        let restored = AtlasAppearance(preferences: preferences, request: request)
        await restored.configure(server: first)
        #expect(restored.activeSelection == "server-default" && restored.theme?.id == "atlas")
        #expect(restored.selection == "berlin")
        removed = false
        let returned = AtlasAppearance(preferences: preferences, request: request)
        await returned.configure(server: first)
        #expect(returned.theme?.id == "berlin")
    }

    @Test func lateCatalogCannotReplaceANewerServerOrItsPreferences() async throws {
        let suite = "atlas.appearance.tests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var pending: CheckedContinuation<Data, Never>?
        let catalog = try await companyCatalog()
        let model = AtlasAppearance(preferences: preferences) { action in
            if action["operation"] as? String == "themes" {
                if action["server"] as? String == first.absoluteString {
                    return await withCheckedContinuation { pending = $0 }
                }
                return try await AtlasAppearance.bridge(["operation": "default_themes"])
            }
            return try await AtlasAppearance.bridge(action)
        }
        let old = Task { await model.configure(server: first) }
        while pending == nil { await Task.yield() }
        await model.configure(server: second)
        model.choose(mode: .light)
        pending?.resume(returning: catalog)
        await old.value
        #expect(model.server == second && model.theme?.id == "atlas" && model.mode == .light)
        await model.configure(server: nil)
        #expect(model.server == nil && model.mode == .system && model.selection == "server-default")
    }

    private func companyCatalog() async throws -> Data {
        let data = try await AtlasAppearance.bridge(["operation": "default_themes"])
        var catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var theme = try #require((catalog["themes"] as? [[String: Any]])?.first)
        theme["id"] = "berlin"
        theme["name"] = "Berlin"
        catalog["themes"] = [theme]
        catalog["default_theme_id"] = "berlin"
        return try await AtlasAppearance.bridge(["operation": "validate_themes", "catalog": catalog])
    }
}
