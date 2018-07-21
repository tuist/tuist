import Basic
import Foundation
import XCTest
@testable import xpmkit

final class MockGraphModuleLoader: GraphModuleLoading {
    var loadCount: UInt = 0
    var loadStub: ((AbsolutePath) -> [AbsolutePath])?

    func load(_ path: AbsolutePath) throws -> [AbsolutePath] {
        loadCount += 1
        return loadStub?(path) ?? []
    }
}
