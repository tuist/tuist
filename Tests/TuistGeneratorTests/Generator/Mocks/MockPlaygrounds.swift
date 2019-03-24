import Basic
import Foundation
import TuistCore
@testable import TuistGenerator

final class MockPlaygrounds: Playgrounding {
    var pathsStub: ((AbsolutePath) -> [AbsolutePath])?

    func paths(path: AbsolutePath) -> [AbsolutePath] {
        return pathsStub?(path) ?? []
    }
}
