import Foundation
import KeychainAccess

public protocol CredentialsStoring {
    /// Sotres the given credentials.
    /// - Parameter credentials: Credentials to be stored.
    func store(credentials: Credentials) throws

    /// Reads the credentials from the store and returns them.
    func read() throws -> Credentials?

    /// Deletes any existing credentials.
    func delete() throws
}

public final class CredentialsStore: CredentialsStoring {
    // MARK: - Attributes

    /// Keychain instance.
    let keychain: Keychain
    private let key = "credentials"

    /// Initializes the credentials store with the domain the keys belong to (e.g. CredentialsStore(identifier: "tuist-cloud")
    /// - Parameter domain: A string to identify the app that is storing credentials.
    init(service: String) {
        keychain = Keychain(service: service)
    }

    public func store(credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try keychain.set(data, key: key)
    }

    public func read() throws -> Credentials? {
        guard let data = try keychain.getData(key) else { return nil }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public func delete() throws {
        try keychain.remove(key)
    }
}
