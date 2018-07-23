import Basic
import Foundation
@testable import TuistKit
import XCTest

final class MockGraphModuleLoader: GraphModuleLoading {
    var loadCount: UInt = 0
    var loadStub: ((AbsolutePath) -> [AbsolutePath])?

    func load(_ path: AbsolutePath) throws -> [AbsolutePath] {
        loadCount += 1
        return loadStub?(path) ?? []
    }
}
