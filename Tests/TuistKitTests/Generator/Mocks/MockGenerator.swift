import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
import TuistGraphTesting
@testable import TuistKit

final class MockGenerator: Generating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateCalls: [AbsolutePath] = []
    var generateStub: ((AbsolutePath) throws -> AbsolutePath)?
    func generate(path: AbsolutePath) throws -> AbsolutePath {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }

        generateCalls.append(path)
        return try generateStub(path)
    }

    var generateWithGraphCalls: [AbsolutePath] = []
    var generateWithGraphStub: ((AbsolutePath) throws -> (AbsolutePath, Graph))?
    func generateWithGraph(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        guard let generateWithGraphStub = generateWithGraphStub else {
            throw MockError.stubNotImplemented
        }
        generateWithGraphCalls.append(path)
        return try generateWithGraphStub(path)
    }

    var invokedGenerateProjectWorkspace = false
    var invokedGenerateProjectWorkspaceCount = 0
    var invokedGenerateProjectWorkspaceParameters: (path: AbsolutePath, Void)?
    var invokedGenerateProjectWorkspaceParametersList = [(path: AbsolutePath, Void)]()
    var stubbedGenerateProjectWorkspaceError: Error?
    var stubbedGenerateProjectWorkspaceResult: (AbsolutePath, Graph)!

    func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        invokedGenerateProjectWorkspace = true
        invokedGenerateProjectWorkspaceCount += 1
        invokedGenerateProjectWorkspaceParameters = (path, ())
        invokedGenerateProjectWorkspaceParametersList.append((path, ()))
        if let error = stubbedGenerateProjectWorkspaceError {
            throw error
        }
        return stubbedGenerateProjectWorkspaceResult
    }

    var invokedLoadParameterPath: AbsolutePath?
    var loadStub: ((AbsolutePath) throws -> Graph)?
    func load(path: AbsolutePath) throws -> Graph {
        invokedLoadParameterPath = path
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return Graph.test()
        }
    }

    var loadProjectStub: ((AbsolutePath) throws -> (Project, Graph, [SideEffectDescriptor]))?
    func loadProject(path: AbsolutePath) throws -> (Project, Graph, [SideEffectDescriptor]) {
        if let loadProjectStub = loadProjectStub {
            return try loadProjectStub(path)
        } else {
            return (Project.test(), Graph.test(), [])
        }
    }
}
