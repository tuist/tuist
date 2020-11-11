import Foundation
import TSCBasic
import TuistCore

@testable import TuistLoader

final class MockSetupLoader: SetupLoading {
    private(set) var meetCount: UInt8 = 0
    var meetStub: ((AbsolutePath, Plugins) throws -> Void)?

    func meet(at path: AbsolutePath, plugins: Plugins) throws {
        meetCount += 1
        try meetStub?(path, plugins)
    }
}
