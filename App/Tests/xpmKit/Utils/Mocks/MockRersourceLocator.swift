import Basic
import Foundation

@testable import xpmKit

final class MockResourceLocator: ResourceLocating {
    var projectDescriptionCount: UInt = 0
    var projectDescriptionStub: (() throws -> AbsolutePath)?
    var cliPathCount: UInt = 0
    var cliPathStub: (() throws -> AbsolutePath)?
    var embedPathCount: UInt = 0
    var embedPathStub: (() throws -> AbsolutePath)?
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

    func embedPath() throws -> AbsolutePath {
        embedPathCount += 1
        return try embedPathStub?() ?? AbsolutePath("/")
    }

    func appPath() throws -> AbsolutePath {
        appPathCount += 1
        return try appPathStub?() ?? AbsolutePath("/")
    }
}
