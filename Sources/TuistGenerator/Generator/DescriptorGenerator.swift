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
    ///   - project: Workspace model
    ///   - graph: Graph model
    ///
    /// - Seealso: `GraphLoader`
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> WorkspaceDescriptor
}

// MARK: -

/// Default implementation of `DescriptorGenerating`
public final class DescriptorGenerator: DescriptorGenerating {
    private let workspaceDescriptorGenerator: WorkspaceDescriptorGenerating
    private let projectGenerator: ProjectGenerating
    
    public convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let schemesGenerator = SchemesGenerator()
        let workspaceStructureGenerator = WorkspaceStructureGenerator()
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator,
                                                schemesGenerator: schemesGenerator)
        let workspaceDescriptorGenerator = WorkspaceDescriptorGenerator(projectGenerator: projectGenerator,
                                                                        workspaceStructureGenerator: workspaceStructureGenerator,
                                                                        schemesGenerator: schemesGenerator)
        self.init(workspaceDescriptorGenerator: workspaceDescriptorGenerator,
                  projectGenerator: projectGenerator)
    }
    
    init(workspaceDescriptorGenerator: WorkspaceDescriptorGenerating,
         projectGenerator: ProjectGenerating)
    {
        self.workspaceDescriptorGenerator = workspaceDescriptorGenerator
        self.projectGenerator = projectGenerator
    }
    
    public func generateProject(project: Project, graph: Graph) throws -> ProjectDescriptor {
        try projectGenerator.generate(project: project, graph: graph)
    }
    
    public func generateWorkspace(workspace: Workspace, graph: Graph) throws -> WorkspaceDescriptor {
        try workspaceDescriptorGenerator.generate(workspace: workspace,
                                                  path: workspace.path,
                                                  graph: graph)
    }
}
