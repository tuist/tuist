import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

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
    func generateProject(project: Project, graphTraverser: GraphTraversing) throws -> ProjectDescriptor

    /// Generate a workspace descriptor
    ///
    /// - Parameters:
    ///   - graphTraverser: Graph traverser.
    ///
    /// - Seealso: `GraphLoader`
    func generateWorkspace(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor
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

    public func generateProject(project: Project, graphTraverser: GraphTraversing) throws -> ProjectDescriptor {
        try projectDescriptorGenerator.generate(project: project, graphTraverser: graphTraverser)
    }

    public func generateWorkspace(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
        try workspaceDescriptorGenerator.generate(graphTraverser: graphTraverser)
    }
}
