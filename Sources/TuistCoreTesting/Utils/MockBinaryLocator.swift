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
    public var stubbedXcbeautifyPathResult: AbsolutePath!

    public func xcbeautifyPath() throws -> AbsolutePath {
        invokedXcbeautifyPath = true
        invokedXcbeautifyPathCount += 1
        if let error = stubbedXcbeautifyPathError {
            throw error
        }
        return stubbedXcbeautifyPathResult
    }

    public var invokedCocoapodsInteractorPath = false
    public var invokedCocoapodsInteractorPathCount = 0
    public var stubbedCocoapodsInteractorPathError: Error?
    public var stubbedCocoapodsInteractorPathResult: AbsolutePath!

    public func cocoapodsInteractorPath() throws -> AbsolutePath {
        invokedCocoapodsInteractorPath = true
        invokedCocoapodsInteractorPathCount += 1
        if let error = stubbedCocoapodsInteractorPathError {
            throw error
        }
        return stubbedCocoapodsInteractorPathResult
    }
}
