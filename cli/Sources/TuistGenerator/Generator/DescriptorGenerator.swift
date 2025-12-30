import Foundation
import TuistCore
import TuistSupport
import XcodeGraph

/// Descriptor Generator
///
/// This component genertes`XcodeProj` representations of a given graph model.
/// No sideeffects take place as a result of this generation.
///
/// - Seealso: `GraphLoader`
/// - Seealso: `GraphLinter`
/// - Seealso: `XcodeProjWriter`
///
public protocol DescriptorGenerating {
    /// Generate an individual project descriptor
    ///
    /// - Parameters:
    ///   - project: Project model
    ///   - graphTraverser: Graph traverser.
    ///
    /// - Seealso: `GraphLoader`
    func generateProject(project: Project, graphTraverser: GraphTraversing) async throws -> ProjectDescriptor

    /// Generate a workspace descriptor
    ///
    /// - Parameters:
    ///   - graphTraverser: Graph traverser.
    ///
    /// - Seealso: `GraphLoader`
    func generateWorkspace(graphTraverser: GraphTraversing) async throws -> WorkspaceDescriptor
}

// MARK: -

/// Default implementation of `DescriptorGenerating`
public final class DescriptorGenerator: DescriptorGenerating {
    private let workspaceDescriptorGenerator: WorkspaceDescriptorGenerating
    private let projectDescriptorGenerator: ProjectDescriptorGenerating

    public convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let schemeDescriptorsGenerator = SchemeDescriptorsGenerator()
        let workspaceStructureGenerator = WorkspaceStructureGenerator()
        let workspaceSettingsGenerator = WorkspaceSettingsDescriptorGenerator()
        let projectDescriptorGenerator = ProjectDescriptorGenerator(
            targetGenerator: targetGenerator,
            configGenerator: configGenerator,
            schemeDescriptorsGenerator: schemeDescriptorsGenerator
        )
        let workspaceDescriptorGenerator = WorkspaceDescriptorGenerator(
            projectDescriptorGenerator: projectDescriptorGenerator,
            workspaceStructureGenerator: workspaceStructureGenerator,
            schemeDescriptorsGenerator: schemeDescriptorsGenerator,
            workspaceSettingsGenerator: workspaceSettingsGenerator
        )
        self.init(
            workspaceDescriptorGenerator: workspaceDescriptorGenerator,
            projectDescriptorGenerator: projectDescriptorGenerator
        )
    }

    init(
        workspaceDescriptorGenerator: WorkspaceDescriptorGenerating,
        projectDescriptorGenerator: ProjectDescriptorGenerating
    ) {
        self.workspaceDescriptorGenerator = workspaceDescriptorGenerator
        self.projectDescriptorGenerator = projectDescriptorGenerator
    }

    public func generateProject(project: Project, graphTraverser: GraphTraversing) async throws -> ProjectDescriptor {
        try await projectDescriptorGenerator.generate(project: project, graphTraverser: graphTraverser)
    }

    public func generateWorkspace(graphTraverser: GraphTraversing) async throws -> WorkspaceDescriptor {
        try await workspaceDescriptorGenerator.generate(graphTraverser: graphTraverser)
    }
}

#if DEBUG
    public final class MockDescriptorGenerator: DescriptorGenerating {
        public enum MockError: Error {
            case stubNotImplemented
        }

        public init() {}

        public var generateProjectSub: ((Project, GraphTraversing) throws -> ProjectDescriptor)?
        public func generateProject(project: Project, graphTraverser: GraphTraversing) throws -> ProjectDescriptor {
            guard let generateProjectSub else {
                throw MockError.stubNotImplemented
            }

            return try generateProjectSub(project, graphTraverser)
        }

        public var generateWorkspaceStub: ((GraphTraversing) throws -> WorkspaceDescriptor)?
        public func generateWorkspace(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
            guard let generateWorkspaceStub else {
                throw MockError.stubNotImplemented
            }

            return try generateWorkspaceStub(graphTraverser)
        }
    }
#endif
