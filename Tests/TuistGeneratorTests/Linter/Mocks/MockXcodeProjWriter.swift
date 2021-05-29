import Foundation
@testable import TuistGenerator

class MockXcodeProjWriter: XcodeProjWriting {
    var writeProjectCalls: [ProjectDescriptor] = []
    func write(project: ProjectDescriptor) throws {
        writeProjectCalls.append(project)
    }

    var writeworkspaceCalls: [WorkspaceDescriptor] = []
    func write(workspace: WorkspaceDescriptor) throws {
        writeworkspaceCalls.append(workspace)
    }
}
