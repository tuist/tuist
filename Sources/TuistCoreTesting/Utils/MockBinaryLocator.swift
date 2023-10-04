import Foundation
import TSCBasic
@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    public var invokedSwiftLintPath = false
    public var invokedSwiftLintPathCount = 0
    public var stubbedSwiftLintPathError: Error?
    public var stubbedSwiftLintPathResult: AbsolutePath!

    public func swiftLintPath() throws -> AbsolutePath {
        invokedSwiftLintPath = true
        invokedSwiftLintPathCount += 1
        if let error = stubbedSwiftLintPathError {
            throw error
        }
        return stubbedSwiftLintPathResult
    }

    public var xcbeautifyStub: (() throws -> AbsolutePath)?
    public var invokedXcbeautifyPath = false
    public var invokedXcbeautifyPathCount = 0
    public var stubbedXcbeautifyPathError: Error?
    public var stubbedXcbeautifyPathResult: String!

    public func xcbeautifyCommand() throws -> String {
        invokedXcbeautifyPath = true
        invokedXcbeautifyPathCount += 1
        if let error = stubbedXcbeautifyPathError {
            throw error
        }
        return stubbedXcbeautifyPathResult
    }
}
