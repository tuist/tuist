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
    var generateWithGraphStub: ((AbsolutePath, Bool) throws -> (AbsolutePath, ValueGraph))?
    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, ValueGraph) {
        guard let generateWithGraphStub = generateWithGraphStub else {
            throw MockError.stubNotImplemented
        }
        generateWithGraphCalls.append((path, projectOnly))
        return try generateWithGraphStub(path, projectOnly)
    }

    var invokedGenerateProjectWorkspace = false
    var invokedGenerateProjectWorkspaceCount = 0
    var invokedGenerateProjectWorkspaceParameters: (path: AbsolutePath, Void)?
    var invokedGenerateProjectWorkspaceParametersList = [(path: AbsolutePath, Void)]()
    var stubbedGenerateProjectWorkspaceError: Error?
    var stubbedGenerateProjectWorkspaceResult: (AbsolutePath, ValueGraph)!

    func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, ValueGraph) {
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
    var loadStub: ((AbsolutePath) throws -> ValueGraph)?
    func load(path: AbsolutePath) throws -> ValueGraph {
        invokedLoadParameterPath = path
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return ValueGraph.test()
        }
    }

    var loadProjectStub: ((AbsolutePath) throws -> (Project, ValueGraph, [SideEffectDescriptor]))?
    func loadProject(path: AbsolutePath) throws -> (Project, ValueGraph, [SideEffectDescriptor]) {
        if let loadProjectStub = loadProjectStub {
            return try loadProjectStub(path)
        } else {
            return (Project.test(), ValueGraph.test(), [])
        }
    }
}
