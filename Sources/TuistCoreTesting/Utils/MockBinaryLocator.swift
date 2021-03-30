import Foundation
import TSCBasic
@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    var invokedSwiftLintPath = false
    var invokedSwiftLintPathCount = 0
    var stubbedSwiftLintPathError: Error?
    var stubbedSwiftLintPathResult: AbsolutePath!

    public init() {}

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

    public var xcbeautifyStub: (() throws -> AbsolutePath)?
    public func xcbeautifyPath() throws -> AbsolutePath {
        if let xcbeautifyPath = xcbeautifyStub {
            return try xcbeautifyPath()
        } else {
            throw BinaryLocatorError.xcbeautifyNotFound
        }
    }
}
