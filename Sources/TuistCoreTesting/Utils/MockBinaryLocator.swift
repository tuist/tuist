import Foundation
import TSCBasic
@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    var invokedSwiftLintPath = false
    var invokedSwiftLintPathCount = 0
    var stubbedSwiftLintPathError: Error?
    var stubbedSwiftLintPathResult: AbsolutePath!

    public func swiftLintPath() throws -> AbsolutePath {
        invokedSwiftLintPath = true
        invokedSwiftLintPathCount += 1
        if let error = stubbedSwiftLintPathError {
            throw error
        }
        return stubbedSwiftLintPathResult
    }

    public var swiftDocPathStub: (() throws -> AbsolutePath)?
    public func swiftDocPath() throws -> AbsolutePath {
        if let swiftDocPathStub = swiftDocPathStub {
            return try swiftDocPathStub()
        } else {
            throw BinaryLocatorError.swiftDocNotFound
        }
    }
}
