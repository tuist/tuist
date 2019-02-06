@testable import TuistKit
import Basic
import Foundation

final class MockSetupLoader: SetupLoading {

    private(set) var meetCount: UInt8 = 0
    var meetStub: ((AbsolutePath) throws -> Void)?

    func meet(at path: AbsolutePath) throws {
        meetCount += 1
        try meetStub?(path)
    }
}
