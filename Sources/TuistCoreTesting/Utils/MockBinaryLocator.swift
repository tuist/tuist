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
}
