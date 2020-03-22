import Foundation
@testable import TuistSupport

public final class MockCredentialsStore: CredentialsStoring {
    var credentials: Credentials?

    public func store(credentials: Credentials) throws {
        self.credentials = credentials
    }

    public func read() throws -> Credentials? {
        credentials
    }

    public func delete() throws {
        credentials = nil
    }
}
