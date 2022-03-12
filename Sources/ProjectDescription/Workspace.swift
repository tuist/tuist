import Foundation

// MARK: - Workspace

/// A `Workspace.swift` should initialize a variable of type `Workspace`. It can take any name, although we recommend to stick to workspace. A workspace accepts the following attributes:
public struct Workspace: Codable, Equatable {
    /// Name of the workspace. It’s used to determine the name of the generated Xcode workspace.
    public let name: String

    /// List of paths (or glob patterns) to projects to generate and include within the generated Xcode workspace.
    public let projects: [Path]

    /// List of custom schemes to include in the workspace
    public let schemes: [Scheme]

    /// Custom file header template macro for built-in Xcode file templates.
    public let fileHeaderTemplate: FileHeaderTemplate?

    /// List of files to include in the workspace - these won't be included in any of the projects or their build phases.
    public let additionalFiles: [FileElement]

    /// Options to configure the generation of the Xcode workspace.
    public let generationOptions: GenerationOptions

    /// Workspace
    ///
    /// This can be used to customize the generated workspace.
    ///
    /// - Parameters:
    ///   - name: Name of the workspace. It’s used to determine the name of the generated Xcode workspace.
    ///   - projects: List of paths (or glob patterns) to projects to generate and include within the generated Xcode workspace.
    ///   - schemes: List of custom schemes to include in the workspace
    ///   - fileHeaderTemplate: Custom file header template macro for built-in Xcode file templates.
    ///   - additionalFiles: List of files to include in the workspace - these won't be included in any of the projects or their build phases.
    ///   - generationOptions: Options to configure the generation of the Xcode workspace.
    public init(
        name: String,
        projects: [Path],
        schemes: [Scheme] = [],
        fileHeaderTemplate: FileHeaderTemplate? = nil,
        additionalFiles: [FileElement] = [],
        generationOptions: GenerationOptions = .options()
    ) {
        self.name = name
        self.projects = projects
        self.schemes = schemes
        self.fileHeaderTemplate = fileHeaderTemplate
        self.additionalFiles = additionalFiles
        self.generationOptions = generationOptions
        dumpIfNeeded(self)
    }
}
