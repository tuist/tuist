import Foundation
@testable import TuistSupport

public final class MockCredentialsStore: CredentialsStoring {
    public init() {}
    public var credentials: [URL: Credentials] = [:]

    public func store(credentials: Credentials, serverURL: URL) throws {
        self.credentials[serverURL] = credentials
    }

    public func read(serverURL: URL) throws -> Credentials? {
        credentials[serverURL]
    }

    public func delete(serverURL: URL) throws {
        credentials.removeValue(forKey: serverURL)
    }
}
