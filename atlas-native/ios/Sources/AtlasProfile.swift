import Combine
import Foundation

struct AtlasNativeProfile: Decodable {
    struct User: Decodable {
        let name: String
        let email: String
        let description: String
    }
    struct PushNotifications: Decodable {
        let ios: Bool
        let android: Bool
        let macos: Bool
    }
    let user: User
    let serverVersion: String
    let pushNotifications: PushNotifications?
    var cached: Bool?
}

extension AtlasNativeProfile.PushNotifications {
    private enum CodingKeys: String, CodingKey { case ios, android, macos }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ios = try values.decode(Bool.self, forKey: .ios)
        android = try values.decode(Bool.self, forKey: .android)
        macos = try values.decodeIfPresent(Bool.self, forKey: .macos) ?? false
    }

    var supportsCurrentPlatform: Bool {
        #if os(iOS)
        ios
        #else
        macos
        #endif
    }
}

extension AtlasNativeProfile.User {
    private enum CodingKeys: String, CodingKey { case name, email, description }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        email = try values.decode(String.self, forKey: .email)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

@MainActor
final class AtlasProfile: ObservableObject {
    @Published private(set) var profile: AtlasNativeProfile?
    @Published private(set) var errorMessage: String?
    private var generation = 0

    func beginEditing() { generation += 1 }

    func accept(_ profile: AtlasNativeProfile) {
        generation += 1
        self.profile = profile
        errorMessage = nil
    }

    func invalidate() {
        generation += 1
        profile = nil
        errorMessage = nil
    }

    func load(request: ([String: Any]) async throws -> Data, cachedRead: AtlasReadCache.Request?) async {
        generation += 1
        let identity = generation
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if profile == nil, let data = await cachedRead?(["operation": "business", "resource": "profile", "action": "list"]),
           identity == generation, !Task.isCancelled {
            profile = try? decoder.decode(AtlasNativeProfile.self, from: data)
        }
        do {
            let data = try await request(["resource": "profile", "action": "list"])
            let loaded = try decoder.decode(AtlasNativeProfile.self, from: data)
            guard identity == generation, !Task.isCancelled else { return }
            profile = loaded
            errorMessage = nil
        } catch is CancellationError {} catch {
            guard identity == generation, !Task.isCancelled else { return }
            if AtlasReadCache.accessDenied(error) { profile = nil }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class AtlasProfileEditorModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var draft: String
    @Published private(set) var saving = false
    @Published private(set) var errorMessage: String?
    private let original: String
    private let request: ([String: Any]) async throws -> Data

    init(description: String, request: @escaping ([String: Any]) async throws -> Data) {
        draft = description
        original = description
        self.request = request
    }

    var dirty: Bool { draft != original }
    var valid: Bool { draft.unicodeScalars.count <= 4000 && draft.utf8.count <= 16000 && !draft.contains("\0") }

    func save() async -> AtlasNativeProfile? {
        guard !saving, valid else { return nil }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let data = try await request(["resource": "profile", "action": "update_profile", "description": draft])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AtlasNativeProfile.self, from: data)
        } catch let error as AtlasAuthenticationError {
            errorMessage = error.message
            return nil
        } catch {
            errorMessage = "Could not read your saved Atlas profile. Your draft is kept; try again."
            return nil
        }
    }
}
