import Foundation
import TSCBasic

public struct Project: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Codable {
    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    public var path: AbsolutePath

    /// Path to the root of the project sources.
    public var sourceRootPath: AbsolutePath

    /// Path to the Xcode project that will be generated.
    public var xcodeProjPath: AbsolutePath

    /// Project name.
    public var name: String

    /// Organization name.
    public var organizationName: String?

    /// Development region code e.g. `en`.
    public var developmentRegion: String?
    
    /// Additional project options
    public var options: [Options]

    /// Project targets.
    public var targets: [Target]

    /// Project swift packages.
    public var packages: [Package]

    /// Project schemes
    public var schemes: [Scheme]

    /// Project settings.
    public var settings: Settings

    /// The group to place project files within
    public var filesGroup: ProjectGroup

    /// Additional files to include in the project
    public var additionalFiles: [FileElement]

    /// IDE template macros that represent content of IDETemplateMacros.plist
    public var ideTemplateMacros: IDETemplateMacros?

    /// `ResourceSynthesizers` that will be applied on individual target's resources
    public let resourceSynthesizers: [ResourceSynthesizer]

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - sourceRootPath: Path to the directory where the Xcode project will be generated.
    ///   - xcodeProjPath: Path to the Xcode project that will be generated.
    ///   - name: Project name.
    ///   - organizationName: Organization name.
    ///   - developmentRegion: Development region.
    ///   - options: Additional project options.
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///   - additionalFiles: The additional files to include in the project
    ///                      *(Those won't be included in any build phases)*
    public init(
        path: AbsolutePath,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        name: String,
        organizationName: String?,
        developmentRegion: String?,
        options: [Options],
        settings: Settings,
        filesGroup: ProjectGroup,
        targets: [Target],
        packages: [Package],
        schemes: [Scheme],
        ideTemplateMacros: IDETemplateMacros?,
        additionalFiles: [FileElement],
        resourceSynthesizers: [ResourceSynthesizer]
    ) {
        self.path = path
        self.sourceRootPath = sourceRootPath
        self.xcodeProjPath = xcodeProjPath
        self.name = name
        self.organizationName = organizationName
        self.developmentRegion = developmentRegion
        self.options = options
        self.targets = targets
        self.packages = packages
        self.schemes = schemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.ideTemplateMacros = ideTemplateMacros
        self.additionalFiles = additionalFiles
        self.resourceSynthesizers = resourceSynthesizers
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        name
    }

    // MARK: - CustomDebugStringConvertible

    public var debugDescription: String {
        name
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    // MARK: - Public

    /// Returns a copy of the project with the given targets set.
    /// - Parameter targets: Targets to be set to the copy.
    public func with(targets: [Target]) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
            developmentRegion: developmentRegion,
            options: options,
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers
        )
    }

    /// Returns a copy of the project with the given schemes set.
    /// - Parameter schemes: Schemes to be set to the copy.
    public func with(schemes: [Scheme]) -> Project {
        Project(
            path: path,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: xcodeProjPath,
            name: name,
            organizationName: organizationName,
            developmentRegion: developmentRegion,
            options: options,
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            resourceSynthesizers: resourceSynthesizers
        )
    }

    /// Returns the name of the default configuration.
    public var defaultDebugBuildConfigurationName: String {
        let debugConfiguration = settings.defaultDebugBuildConfiguration()
        let buildConfiguration = debugConfiguration ?? settings.configurations.keys.first
        return buildConfiguration?.name ?? BuildConfiguration.debug.name
    }
}

// MARK: - Options

extension Project {
    /// Additional options related to the `Project`
    public enum Options: Codable {
        /// Text settings to override user ones for currecnt project
        case textSettings(TextSettings)
        
        /// Option name
        public var name: String {
            switch self {
            case .textSettings:
                return "textSettings"
            }
        }
    }
}

// MARK: - TextSettings

extension Project.Options {
    /// Text settings for Xcode project
    public struct TextSettings: Codable {
        /// Use tabs over spaces
        public let usesTabs: Bool?
        /// Indent width
        public let indentWidth: UInt?
        /// Tab width
        public let tabWidth: UInt?
        /// Wrap lines
        public let wrapsLines: Bool?
        
        public init(
            usesTabs: Bool?,
            indentWidth: UInt?,
            tabWidth: UInt?,
            wrapsLines: Bool?
        ) {
            self.usesTabs = usesTabs
            self.indentWidth = indentWidth
            self.tabWidth = tabWidth
            self.wrapsLines = wrapsLines
        }
    }
}

// MARK: - Options + Hashable

extension Project.Options: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    public static func == (lhs: Project.Options, rhs: Project.Options) -> Bool {
        switch (lhs, rhs) {
        case (.textSettings, .textSettings):
            return true
        }
    }
}

// MARK: - Options + Codable

extension Project.Options {
    enum CodingKeys: String, CodingKey {
        case textSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.allKeys.contains(.textSettings), try container.decodeNil(forKey: .textSettings) == false {
            var associatedValues = try container.nestedUnkeyedContainer(forKey: .textSettings)
            let textSettings = try associatedValues.decode(TextSettings.self)
            self = .textSettings(textSettings)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown enum case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .textSettings(textSettings):
            var associatedValues = container.nestedUnkeyedContainer(forKey: .textSettings)
            try associatedValues.encode(textSettings)
        }
    }
}
