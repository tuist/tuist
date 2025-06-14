import Foundation
import Path
import TuistSupport

public final class MockDerivedDataLocator: DerivedDataLocating {
    public init() {}

    public enum MockDerivedDataLocatorError: Error {
        case noStub
    }

    public var locateStub: ((AbsolutePath) throws -> AbsolutePath)?
    public func locate(for projectPath: AbsolutePath) throws -> AbsolutePath {
        guard let locateStub else { throw MockDerivedDataLocatorError.noStub }
        return try locateStub(projectPath)
    }
}
