import Foundation

@testable import TuistCloud

public final class MockCloudSessionController: CloudSessionControlling {
    public init() {}

    public var authenticateArgs: [URL] = []
    public func authenticate(serverURL: URL) throws {
        authenticateArgs.append(serverURL)
    }

    public var printSessionArgs: [URL] = []
    public func printSession(serverURL: URL) throws {
        printSessionArgs.append(serverURL)
    }

    public var logoutArgs: [URL] = []
    public func logout(serverURL: URL) throws {
        logoutArgs.append(serverURL)
    }
}
