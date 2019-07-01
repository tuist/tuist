import Basic
import Foundation
import TuistGenerator

final class MockDotGraphGenerator: DotGraphGenerating {
    var generateProjectCallCount: UInt = 0
    var generateWorkspaceCallCount: UInt = 0
    var generateProjectArgs: [AbsolutePath] = []
    var generateWorkspaceArgs: [AbsolutePath] = []
    var generateProjectStub: String = ""
    var generateWorkspaceStub: String = ""

    func generateProject(at path: AbsolutePath) throws -> String {
        generateProjectCallCount += 1
        generateProjectArgs.append(path)
        return generateProjectStub
    }

    func generateWorkspace(at path: AbsolutePath) throws -> String {
        generateWorkspaceCallCount += 1
        generateWorkspaceArgs.append(path)
        return generateWorkspaceStub
    }
}
