import Foundation
import TSCBasic
@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    public var invokedXcbeautifyExecutable = false
    public var invokedXcbeautifyExecutableCount = 0
    public var stubbedXcbeautifyExecutableError: Error?
    public var stubbedXcbeautifyExecutableResult: SwiftPackageExecutable!

    public func xcbeautifyExecutable() throws -> SwiftPackageExecutable {
        invokedXcbeautifyExecutable = true
        invokedXcbeautifyExecutableCount += 1
        if let error = stubbedXcbeautifyExecutableError {
            throw error
        }
        return stubbedXcbeautifyExecutableResult
    }
}
