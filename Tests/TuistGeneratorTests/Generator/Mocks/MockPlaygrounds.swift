import Basic
import Foundation
import TuistSupport
@testable import TuistGenerator

final class MockPlaygrounds: Playgrounding {
    var pathsStub: ((AbsolutePath) -> [AbsolutePath])?

    func paths(path: AbsolutePath) -> [AbsolutePath] {
        pathsStub?(path) ?? []
    }
}
