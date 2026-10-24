import Combine
import Foundation

struct AtlasNativeProfile: Decodable {
    struct User: Decodable {
        let name: String
        let email: String
        let description: String

        private enum CodingKeys: String, CodingKey { case name, email, description }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            email = try values.decode(String.self, forKey: .email)
            description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        }
    }
    struct PushNotifications: Decodable {
        let ios: Bool
        let android: Bool
    }
    let user: User
    let serverVersion: String
    let pushNotifications: PushNotifications?
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
