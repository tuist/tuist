import Foundation

// MARK: - Workspace

public struct Workspace: Codable, Equatable {
    /// Name of the workspace
    public let name: String

    /// List of project relative paths (or glob patterns) to generate and include
    public let projects: [Path]

    /// List of custom schemes
    public let schemes: [Scheme]

    /// Default file header template used for Xcode file templates
    public let fileHeaderTemplate: FileHeaderTemplate?

    /// List of files to include in the workspace (e.g. Documentation)
    public let additionalFiles: [FileElement]

    /// Generation options.
    public let generationOptions: GenerationOptions

    /// Workspace
    ///
    /// This can be used to customize the generated workspace.
    ///
    /// - Parameters:
    ///   - name: Name of the workspace.
    ///   - projects: List of project relative paths (or glob patterns) to generate and include.
    ///   - schemes: List of workspace schemes.
    ///   - fileHeaderTemplate: File header template.
    ///   - additionalFiles: List of files to include in the workspace (e.g. Documentation).
    ///   - generationOptions: Workspace generation options.
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
