import Basic
import Foundation
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
}

class MockDetailedProjectGenerator: DetailedProjectGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateCalls: [(path: AbsolutePath, projectOnly: Bool)] = []
    var generateStub: ((AbsolutePath, Bool) throws -> (AbsolutePath, Graphing))?
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graphing) {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }
        generateCalls.append((path, projectOnly))
        return try generateStub(path, projectOnly)
    }
}
