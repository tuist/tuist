import Foundation

// MARK: - Workspace

public struct Workspace: Codable, Equatable {
    /// Contains options related to the workspace generation.
    public enum GenerationOptions: Codable, Equatable {
        /// Represents the behavior Xcode will apply to the workspace regarding
        /// schema generation using the `IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded` key.
        /// - seealso: `WorkspaceSettingsDescriptor`
        public enum AutomaticSchemaGeneration: String, Codable, Equatable {
            /// Will not add the key to the settings file.
            case `default`

            /// Will add the key with the value set to `false`.
            case disabled

            /// Will add the key with the value set to `true`.
            case enabled
        }

        /// Tuist generates a WorkspaceSettings.xcsettings file, setting the related key to the associated value.
        case automaticSchemaGeneration(AutomaticSchemaGeneration)
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
    public let generationOptions: [GenerationOptions]

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
        generationOptions: [GenerationOptions] = []
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

extension Workspace.GenerationOptions {
    private enum CodingKeys: String, CodingKey {
        case automaticSchemaGeneration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.automaticSchemaGeneration) {
            let mode = try container.decode(
                Workspace.GenerationOptions.AutomaticSchemaGeneration.self,
                forKey: .automaticSchemaGeneration
            )
            self = .automaticSchemaGeneration(mode)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .automaticSchemaGeneration(value):
            try container.encode(value, forKey: .automaticSchemaGeneration)
        }
    }
}
