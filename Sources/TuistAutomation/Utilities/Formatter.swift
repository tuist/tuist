import Foundation
import TuistCore
import TuistSupport

public protocol Formatting {
    func buildArguments() throws -> [String]
}

final class Formatter: Formatting {
    private let binaryLocator: BinaryLocating

    init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    func buildArguments() throws -> [String] {
        let xcbeautifyPath = try binaryLocator.xcbeautifyPath()
        return [xcbeautifyPath.pathString]
    }
}
