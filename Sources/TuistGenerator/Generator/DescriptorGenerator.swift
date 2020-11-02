import Foundation
import TSCBasic
import TuistCore
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
    ///   - graph: Graph model
    ///
    /// - Seealso: `GraphLoader`
    func generateProject(project: Project, graph: Graph) throws -> ProjectDescriptor

    /// Generate a workspace descriptor
    ///
    /// - Parameters:
    ///   - graph: Graph model
    ///
    /// - Seealso: `GraphLoader`
    func generateWorkspace(graph: Graph) throws -> WorkspaceDescriptor
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
        let projectDescriptorGenerator = ProjectDescriptorGenerator(targetGenerator: targetGenerator,
                                                                    configGenerator: configGenerator,
                                                                    schemeDescriptorsGenerator: schemeDescriptorsGenerator)
        let workspaceDescriptorGenerator = WorkspaceDescriptorGenerator(projectDescriptorGenerator: projectDescriptorGenerator,
                                                                        workspaceStructureGenerator: workspaceStructureGenerator,
                                                                        schemeDescriptorsGenerator: schemeDescriptorsGenerator)
        self.init(workspaceDescriptorGenerator: workspaceDescriptorGenerator,
                  projectDescriptorGenerator: projectDescriptorGenerator)
    }

    init(workspaceDescriptorGenerator: WorkspaceDescriptorGenerating,
         projectDescriptorGenerator: ProjectDescriptorGenerating)
    {
        self.workspaceDescriptorGenerator = workspaceDescriptorGenerator
        self.projectDescriptorGenerator = projectDescriptorGenerator
    }

    public func generateProject(project: Project, graph: Graph) throws -> ProjectDescriptor {
        try projectDescriptorGenerator.generate(project: project, graph: graph)
    }

    public func generateWorkspace(graph: Graph) throws -> WorkspaceDescriptor {
        try workspaceDescriptorGenerator.generate(graph: graph)
    }
}
