import Foundation
import Security
import TuistServer

public struct StoredProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public let account: Account
    public let server: AppServerConfiguration?
    let credentials: ServerCredentials
    var organization: String?
    var organizations: [String]?
    var organizationsAccessDenied: Bool?

    var canSelectOrganization: Bool { organizationsAccessDenied != true && credentials.rejected != true }
}

public struct StoredOrganization: Equatable, Identifiable {
    public let profileID: UUID
    public let name: String
    public let serverURL: URL
    public var id: String { "\(serverURL.absoluteString)#\(name)" }
}

struct StoredProfiles: Codable, Equatable {
    var profiles: [StoredProfile] = []
    var activeID: UUID?
}

protocol ProfileStoring {
    func read() throws -> StoredProfiles
    func write(_ profiles: StoredProfiles) throws
}

struct ProfileStorageError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Your saved profiles could not be updated. Please try again.")
    }
}

/// One atomic Keychain item keeps inactive credentials out of UserDefaults and app backups.
struct KeychainProfileStore: ProfileStoring {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.tuist.app.profiles",
            kSecAttrAccount as String: "profiles-v1",
            kSecAttrSynchronizable as String: false,
        ]
    }

    func read() throws -> StoredProfiles {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return StoredProfiles() }
        guard status == errSecSuccess, let data = result as? Data else { throw ProfileStorageError() }
        return try JSONDecoder().decode(StoredProfiles.self, from: data)
    }

    func write(_ profiles: StoredProfiles) throws {
        let data = try JSONEncoder().encode(profiles)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ProfileStorageError() }
        } else if status != errSecSuccess {
            throw ProfileStorageError()
        }
    }
}

/// Discovery refreshes one saved login without changing the active credential slots or emitting login events.
@MainActor
final class ProfileCredentialsStore: ServerCredentialsStoring {
    private var credentials: ServerCredentials
    private let serverURL: URL
    private let persist: (ServerCredentials) throws -> Void
    nonisolated let credentialsChanged = AsyncStream<ServerCredentials?> { $0.finish() }

    init(credentials: ServerCredentials, serverURL: URL, persist: @escaping (ServerCredentials) throws -> Void) {
        self.credentials = credentials
        self.serverURL = serverURL
        self.persist = persist
    }

    func store(credentials: ServerCredentials, serverURL: URL) async throws {
        guard serverURL == self.serverURL else { throw ProfileStorageError() }
        try persist(credentials)
        self.credentials = credentials
    }

    func get(serverURL: URL) async throws -> ServerCredentials {
        guard serverURL == self.serverURL else { throw ProfileStorageError() }
        return credentials
    }

    func read(serverURL: URL) async throws -> ServerCredentials? { try await get(serverURL: serverURL) }
    func delete(serverURL _: URL) async throws { throw ProfileStorageError() }
}
