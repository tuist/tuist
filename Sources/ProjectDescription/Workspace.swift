import Foundation

// MARK: - Workspace

public struct Workspace: Codable, Equatable {
    /// Contains options related to the workspace generation.
    public struct GenerationOptions: Codable, Equatable {
        /// Represents the behavior Xcode will apply to the workspace regarding
        /// schema generation using the `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded` key.
        /// - seealso: `WorkspaceSettingsDescriptor`
        public enum AutomaticSchemeMode: String, Codable, Equatable {
            /// Will not add the key to the settings file.
            case `default`

            /// Will add the key with the value set to `false`.
            case disabled

            /// Will add the key with the value set to `true`.
            case enabled
        }

        /// Tuist generates a WorkspaceSettings.xcsettings file, setting the related key to the associated value.
        public let automaticXcodeSchemes: AutomaticSchemeMode

        public static func options(automaticXcodeSchemes: AutomaticSchemeMode) -> Self {
            GenerationOptions(automaticXcodeSchemes: automaticXcodeSchemes)
        }
    }

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
    public let generationOptions: GenerationOptions?

    /// Workspace
    ///
    /// This can be used to customize the generated workspace.
    ///
    /// - Parameters:
    ///   - name: Name of the workspace.
    ///   - projects: List of project relative paths (or glob patterns) to generate and include.
    ///   - additionalFiles: List of files to include in the workspace (e.g. Documentation)
    public init(
        name: String,
        projects: [Path],
        schemes: [Scheme] = [],
        fileHeaderTemplate: FileHeaderTemplate? = nil,
        additionalFiles: [FileElement] = [],
        generationOptions: GenerationOptions? = nil
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
