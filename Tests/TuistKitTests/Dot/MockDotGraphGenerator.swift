import Foundation
import TSCBasic
import TuistGenerator

final class MockDotGraphGenerator: DotGraphGenerating {
    var generateProjectArgs: [AbsolutePath] = []
    var generateWorkspaceArgs: [AbsolutePath] = []
    var generateProjectStub: String = ""
    var generateWorkspaceStub: String = ""

    func generateProject(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String {
        generateProjectArgs.append(path)
        return generateProjectStub
    }

    func generateWorkspace(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String {
        generateWorkspaceArgs.append(path)
        return generateWorkspaceStub
    }
}
