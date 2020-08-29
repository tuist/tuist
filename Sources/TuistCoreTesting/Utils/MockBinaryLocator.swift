import Foundation
import TSCBasic
@testable import TuistCore

public final class MockBinaryLocator: BinaryLocating {
    public init() {}

    public var swiftLintPathStub: (() throws -> AbsolutePath)?

    public func swiftLintPath() throws -> AbsolutePath {
        try swiftLintPathStub?() ?? ""
    }
}
