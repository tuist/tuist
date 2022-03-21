import Foundation
import TuistCloud

public final class MockCloudAuthenticationController: CloudAuthenticationControlling {
    public init() {}

    public var authenticationTokenStub: ((URL) throws -> String?)?
    public func authenticationToken(serverURL: URL) throws -> String? {
        try authenticationTokenStub?(serverURL)
    }
}
