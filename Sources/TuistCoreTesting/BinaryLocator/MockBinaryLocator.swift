import TSCBasic

@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    var absolutePath: AbsolutePath?

    public init() {}

    public func swiftDocPath() throws -> AbsolutePath {
        if let absolutePath = absolutePath {
            return absolutePath
        } else {
            throw BinaryLocatorError.swiftDocNotFound
        }
    }
}
