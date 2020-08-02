import Foundation
import TSCBasic
import TuistGenerator

final class MockDotGraphGenerator: DotGraphGenerating {
    var generateProjectArgs: [AbsolutePath] = []
    var generateWorkspaceArgs: [AbsolutePath] = []
    var generateProjectStub: String = ""
    var generateWorkspaceStub: String = ""

    func generateProject(at path: AbsolutePath, skipTestTargets _: Bool, skipExternalDependencies _: Bool) throws -> Data {
        generateProjectArgs.append(path)
        return generateProjectStub.data(using: .utf8)!
    }

    func generateWorkspace(at path: AbsolutePath, skipTestTargets _: Bool, skipExternalDependencies _: Bool) throws -> Data {
        generateWorkspaceArgs.append(path)
        return generateWorkspaceStub.data(using: .utf8)!
    }
}
