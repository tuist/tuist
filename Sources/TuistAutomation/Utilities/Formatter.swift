import Foundation
import TuistCore
import TuistSupport

protocol Formatting {
    func formatterExecutable() throws -> SwiftPackageExecutable
}

final class Formatter: Formatting {
    private let binaryLocator: BinaryLocating

    init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    func formatterExecutable() throws -> SwiftPackageExecutable {
        try binaryLocator.xcbeautifyExecutable()
    }
}
