import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
@testable import TuistKit

final class MockProjectGenerator: ProjectGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateCalls: [(path: AbsolutePath, projectOnly: Bool)] = []
    var generateStub: ((AbsolutePath, Bool) throws -> AbsolutePath)?
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }

        generateCalls.append((path, projectOnly))
        return try generateStub(path, projectOnly)
    }

    var generateWithGraphCalls: [(path: AbsolutePath, projectOnly: Bool)] = []
    var generateWithGraphStub: ((AbsolutePath, Bool) throws -> (AbsolutePath, Graph))?
    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graph) {
        guard let generateWithGraphStub = generateWithGraphStub else {
            throw MockError.stubNotImplemented
        }
        generateWithGraphCalls.append((path, projectOnly))
        return try generateWithGraphStub(path, projectOnly)
    }
}
