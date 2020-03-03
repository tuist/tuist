import Basic
import Foundation
import TuistCore
import TuistGenerator
@testable import TuistKit

class MockProjectGenerator: ProjectGenerating {
    var generateCalls: [(path: AbsolutePath, projectOnly: Bool)] = []
    var generateStub: ((AbsolutePath, Bool) throws -> AbsolutePath)?
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath {
        generateCalls.append((path, projectOnly))
        return try generateStub?(path, projectOnly) ?? AbsolutePath("/Test")
    }
}

class MockDetailedProjectGenerator: DetailedProjectGenerating {
    var generateCalls: [(path: AbsolutePath, projectOnly: Bool)] = []
    var generateStub: ((AbsolutePath, Bool) throws -> (AbsolutePath, Graphing))?
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graphing) {
        generateCalls.append((path, projectOnly))
        return try generateStub?(path, projectOnly) ?? (AbsolutePath("/Test"), Graph.test())
    }
}
