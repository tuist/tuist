
import Foundation
@testable import TuistGenerator

class MockXcodeProjWriter: XcodeProjWriting {
    var writeProjectCalls: [GeneratedProjectDescriptor] = []
    func write(project: GeneratedProjectDescriptor) throws {
        writeProjectCalls.append(project)
    }

    var writeworkspaceCalls: [GeneratedWorkspaceDescriptor] = []
    func write(workspace: GeneratedWorkspaceDescriptor) throws {
        writeworkspaceCalls.append(workspace)
    }
}
