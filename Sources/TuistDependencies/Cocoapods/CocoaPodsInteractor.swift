import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol CocoaPodsInteracting {
    func install(path: AbsolutePath) throws
    func update(path: AbsolutePath) throws
}

final class CocoaPodsInteractor: CocoaPodsInteracting {
    private let binaryLocator: BinaryLocating

    init(binaryLocator: BinaryLocating = BinaryLocator()) {
        self.binaryLocator = binaryLocator
    }

    func install(path: AbsolutePath) throws {
        let executablePath = try binaryLocator.cocoapodsInteractorPath()
        try System.shared.runAndPrint([executablePath.pathString, "install", path.pathString])
    }

    func update(path: AbsolutePath) throws {
        let executablePath = try binaryLocator.cocoapodsInteractorPath()
        try System.shared.runAndPrint([executablePath.pathString, "update", path.pathString])
    }
}
