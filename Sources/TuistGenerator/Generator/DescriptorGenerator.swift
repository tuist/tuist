import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj

public struct GeneratedSchemeDescriptor {
    public var scheme: XCScheme
    public var shared: Bool
}

public enum GeneratedSideEffect {
    case file(GeneratedFile)
    case delete(AbsolutePath)
    case command(GeneratedCommand)
}

public struct GeneratedFile {
    public var path: AbsolutePath
    public var contents: Data
}

public struct GeneratedCommand {
    public var command: [String]
}

public struct GeneratedProjectDescriptor {
    public var path: AbsolutePath
    public var xcodeProj: XcodeProj
    public var schemes: [GeneratedSchemeDescriptor]
    public var sideEffects: [GeneratedSideEffect]
}

public struct GeneratedWorkspaceDescriptor {
    public var path: AbsolutePath
    public var xcworkspace: XCWorkspace
    public var projects: [GeneratedProjectDescriptor]
    public var schemes: [GeneratedSchemeDescriptor]
    public var sideEffects: [GeneratedSideEffect]
}

/// Descriptor Generator
///
/// Produces a side effect free representation of a generated project or workspace
///
///
public protocol DescriptorGenerating {
    func generateProject(project: Project, graph: Graph) throws -> GeneratedProjectDescriptor
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> GeneratedWorkspaceDescriptor
}

// MARK: -

public final class DescriptorGenerator: DescriptorGenerating {
    private let workspaceGenerator: WorkspaceGenerating
    private let projectGenerator: ProjectGenerating

    public convenience init(defaultSettingsProvider: DefaultSettingsProviding = DefaultSettingsProvider()) {
        let configGenerator = ConfigGenerator(defaultSettingsProvider: defaultSettingsProvider)
        let targetGenerator = TargetGenerator(configGenerator: configGenerator)
        let projectGenerator = ProjectGenerator(targetGenerator: targetGenerator,
                                                configGenerator: configGenerator)
        let workspaceGenerator = WorkspaceGenerator(defaultSettingsProvider: defaultSettingsProvider)
        self.init(workspaceGenerator: workspaceGenerator, projectGenerator: projectGenerator)
    }

    init(workspaceGenerator: WorkspaceGenerating,
         projectGenerator: ProjectGenerating) {
        self.workspaceGenerator = workspaceGenerator
        self.projectGenerator = projectGenerator
    }

    public func generateProject(project: Project, graph: Graph) throws -> GeneratedProjectDescriptor {
        try projectGenerator.generateDescriptor(project: project,
                                                graph: graph,
                                                sourceRootPath: nil,
                                                xcodeprojPath: nil)
    }

    public func generateWorkspace(workspace: Workspace, graph: Graph) throws -> GeneratedWorkspaceDescriptor {
        try workspaceGenerator.generateDescriptor(workspace: workspace,
                                                  path: workspace.path,
                                                  graph: graph)
    }
}
