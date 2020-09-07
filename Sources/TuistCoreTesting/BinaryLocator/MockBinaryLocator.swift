import TSCBasic

@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    public init() {}

    public var swiftDocPathStub: (() throws -> AbsolutePath)?
    public func swiftDocPath() throws -> AbsolutePath {
        if let swiftDocPathStub = swiftDocPathStub {
            return try swiftDocPathStub()
        } else {
            throw BinaryLocatorError.swiftDocNotFound
        }
    }
}
