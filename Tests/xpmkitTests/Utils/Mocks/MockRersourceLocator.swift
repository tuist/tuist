import Basic
import Foundation
@testable import xpmkit

final class MockResourceLocator: ResourceLocating {
    var projectDescriptionCount: UInt = 0
    var projectDescriptionStub: (() throws -> AbsolutePath)?
    var cliPathCount: UInt = 0
    var cliPathStub: (() throws -> AbsolutePath)?
    var embedPathCount: UInt = 0
    var embedPathStub: (() throws -> AbsolutePath)?

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
}
