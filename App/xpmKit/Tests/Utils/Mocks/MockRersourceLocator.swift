import Basic
import Foundation

final class MockResourceLocator: ResourceLocating {
    var projectDescriptionCount: UInt = 0
    var projectDescriptionStub: (() throws -> AbsolutePath)?
    var cliPathCount: UInt = 0
    var cliPathStub: (() throws -> AbsolutePath)?
    var appPathCount: UInt = 0
    var appPathStub: (() throws -> AbsolutePath)?

    func projectDescription() throws -> AbsolutePath {
        projectDescriptionCount += 1
        return try projectDescriptionStub?() ?? AbsolutePath("/")
    }

    func cliPath() throws -> AbsolutePath {
        cliPathCount += 1
        return try cliPathStub?() ?? AbsolutePath("/")
    }

    func appPath() throws -> AbsolutePath {
        appPathCount += 1
        return try appPathStub?() ?? AbsolutePath("/")
    }
}
