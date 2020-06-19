import Foundation
import TSCBasic
@testable import TuistCore

final class MockProjectMapper: ProjectMapping {
    var mapStub: ((Project) throws -> (Project, [SideEffectDescriptor]))?
    func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        try mapStub?(project) ?? (project, [])
    }
}
