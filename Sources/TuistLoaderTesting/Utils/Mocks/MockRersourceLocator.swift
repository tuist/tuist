import Basic
import Foundation
@testable import TuistLoader

public final class MockResourceLocator: ResourceLocating {
    public var projectDescriptionCount: UInt = 0
    public var projectDescriptionStub: (() throws -> AbsolutePath)?
    public var templateDescriptionCount: UInt = 0
    public var templateDescriptionStub: (() throws -> AbsolutePath)?
    public var cliPathCount: UInt = 0
    public var cliPathStub: (() throws -> AbsolutePath)?
    public var embedPathCount: UInt = 0
    public var embedPathStub: (() throws -> AbsolutePath)?

    public func projectDescription() throws -> AbsolutePath {
        projectDescriptionCount += 1
        return try projectDescriptionStub?() ?? AbsolutePath("/")
    }
    
    public func templateDescription() throws -> AbsolutePath {
        templateDescriptionCount += 1
        return try templateDescriptionStub?() ?? AbsolutePath("/")
    }

    public func cliPath() throws -> AbsolutePath {
        cliPathCount += 1
        return try cliPathStub?() ?? AbsolutePath("/")
    }

    public func embedPath() throws -> AbsolutePath {
        embedPathCount += 1
        return try embedPathStub?() ?? AbsolutePath("/")
    }
}
