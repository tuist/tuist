import Basic
import Foundation

final class MockResourceLocator: ResourceLocating {
    var projectDescriptionCount: UInt = 0
    var projectDescriptionStub: (() throws -> AbsolutePath)?
    var cliPathCount: UInt = 0
    var cliPathStub: (() throws -> AbsolutePath)?

    func projectDescription() throws -> AbsolutePath {
        projectDescriptionCount += 1
        return try projectDescriptionStub?() ?? AbsolutePath("/")
    }

    func cliPath() throws -> AbsolutePath {
        cliPathCount += 1
        return try cliPathStub?() ?? AbsolutePath("/")
    }
}
