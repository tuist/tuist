import Basic
import Foundation

final class MockResourceLocator: ResourceLocating {
    var projectDescriptionCount: UInt = 0
    var projectDescriptionStub: ((Contexting) throws -> AbsolutePath)?
    var cliPathCount: UInt = 0
    var cliPathStub: ((Contexting) throws -> AbsolutePath)?

    func projectDescription(context: Contexting) throws -> AbsolutePath {
        projectDescriptionCount += 1
        return try projectDescriptionStub?(context) ?? AbsolutePath("/")
    }

    func cliPath(context: Contexting) throws -> AbsolutePath {
        cliPathCount += 1
        return try cliPathStub?(context) ?? AbsolutePath("/")
    }
}
