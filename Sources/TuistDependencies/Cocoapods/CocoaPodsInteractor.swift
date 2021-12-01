import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol CocoaPodsInteracting {}

final class CocoaPodsInteractor {
    private let binaryLocator: BinaryLocating

    init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    func run() throws {
        let path = try binaryLocator.cocoapodsInteractorPath()
        try System.shared.runAndPrint(path.pathString)
    }
}
