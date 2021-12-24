import Foundation
import KeychainAccess

public protocol CredentialsStoring {
    /// It stores the credentials for the server with the given URL.
    /// - Parameters:
    ///   - credentials: Credentials to be stored.
    ///   - serverURL: Server URL (without path).
    func store(credentials: Credentials, serverURL: URL) throws

    /// Reads the credentials to authenticate the user against the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func read(serverURL: URL) throws -> Credentials?

    /// Deletes the credentials for the server with the given URL.
    /// - Parameter serverURL: Server URL (without path).
    func delete(serverURL: URL) throws
}

public final class CredentialsStore: CredentialsStoring {
    /// Default initializer.
    public init() {}

    // MARK: - CredentialsStoring

    public func store(credentials: Credentials, serverURL: URL) throws {
        try keychain(serverURL: serverURL)
            .comment("Token to authenticate the \(credentials.account) against \(serverURL.absoluteString)")
            .set(credentials.account, key: credentials.token)
    }

    public func read(serverURL: URL) throws -> Credentials? {
        let keychain = keychain(serverURL: serverURL)
        guard let token = keychain.allKeys().first else { return nil }
        guard let account = try keychain.get(token) else { return nil }
        return Credentials(token: token, account: account)
    }

    public func delete(serverURL: URL) throws {
        let keychain = keychain(serverURL: serverURL)
        try keychain.allKeys().forEach { account in
            try keychain.remove(account)
        }
    }

    // MARK: - Fileprivate

    fileprivate func keychain(serverURL: URL) -> Keychain {
        Keychain(server: serverURL, protocolType: .https, authenticationType: .default)
            .synchronizable(false)
            .label("\(serverURL.absoluteString)")
    }
}
