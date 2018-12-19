import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockPlaygrounds: Playgrounding {
    var pathsStub: ((AbsolutePath) -> [AbsolutePath])?

    func paths(path: AbsolutePath) -> [AbsolutePath] {
        return pathsStub?(path) ?? []
    }
}
