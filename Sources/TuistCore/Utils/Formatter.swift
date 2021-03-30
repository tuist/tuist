import Foundation
import TSCBasic
import TuistSupport

public final class Formatter: Formatting {
    private let binaryLocator: BinaryLocating

    public init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    public func buildArguments() throws -> [String] {
        let xcbeautifyPath = try binaryLocator.xcbeautifyPath()
        return [xcbeautifyPath.pathString]
    }
}
