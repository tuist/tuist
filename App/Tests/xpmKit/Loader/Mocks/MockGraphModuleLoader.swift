import Basic
import Foundation
import XCTest
@testable import xpmKit

final class MockGraphModuleLoader: GraphModuleLoading {
    var loadCount: UInt = 0
    var loadStub: ((AbsolutePath, Contexting) -> [AbsolutePath])?

    func load(_ path: AbsolutePath,
              context: Contexting) throws -> [AbsolutePath] {
        loadCount += 1
        return loadStub?(path, context) ?? []
    }
}
