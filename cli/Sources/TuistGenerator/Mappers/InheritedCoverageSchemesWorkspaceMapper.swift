import Foundation
import Logging
import TuistCore
import XcodeGraph

/// Turns on coverage in the test actions of user-defined schemes that leave `coverage` unset, when `Tuist.swift`'s
/// `coverage.enabled` (as the command resolved it) is on.
///
/// A scheme that sets `coverage` keeps its value, so `coverage: false` opts a scheme out. Test actions driven by
/// test plans are left alone: the plans decide coverage themselves. External packages' schemes are never touched.
public struct InheritedCoverageSchemesWorkspaceMapper: WorkspaceMapping {
    private let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        guard enabled else { return (workspace, []) }
        Logger.current.debug("Transforming workspace \(workspace.workspace.name): Turning on inherited scheme coverage")

        var workspace = workspace
        workspace.workspace.schemes = workspace.workspace.schemes.map(Self.inheritingCoverage)
        workspace.projects = workspace.projects.map { project in
            guard project.externalHash == nil else { return project }
            var project = project
            project.schemes = project.schemes.map(Self.inheritingCoverage)
            return project
        }
        return (workspace, [])
    }

    private static func inheritingCoverage(_ scheme: Scheme) -> Scheme {
        guard var testAction = scheme.testAction, testAction.inheritsCoverage,
              testAction.testPlans?.isEmpty ?? true
        else { return scheme }
        testAction.coverage = true
        var scheme = scheme
        scheme.testAction = testAction
        return scheme
    }
}
