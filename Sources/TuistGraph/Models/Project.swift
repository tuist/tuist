import Foundation
import TSCBasic
import TSCUtility

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

    /// Default known regions
    public var defaultKnownRegions: [String]?

    /// Development region code e.g. `en`.
    public var developmentRegion: String?

    /// Additional project options.
    public var options: Options

    /// Project targets.
    public var targets: [String: Target]

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
    public var resourceSynthesizers: [ResourceSynthesizer]

    /// The version in which a check happened related to recommended settings after updating Xcode.
    public var lastUpgradeCheck: Version?

    /// Indicates whether the project is imported through `Package.swift`.
    public var isExternal: Bool

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - sourceRootPath: Path to the directory where the Xcode project will be generated.
    ///   - xcodeProjPath: Path to the Xcode project that will be generated.
    ///   - name: Project name.
    ///   - organizationName: Organization name.
    ///   - defaultKnownRegions: Default known regions.
    ///   - developmentRegion: Development region.
    ///   - options: Additional project options.
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///                      *(Those won't be included in any build phases)*
    ///   - packages: Project swift packages.
    ///   - schemes: Project schemes.
    ///   - ideTemplateMacros: IDE template macros that represent content of IDETemplateMacros.plist.
    ///   - additionalFiles: The additional files to include in the project
    ///   - resourceSynthesizers: `ResourceSynthesizers` that will be applied on individual target's resources
    ///   - lastUpgradeCheck: The version in which a check happened related to recommended settings after updating Xcode.
    ///   - isExternal: Indicates whether the project is imported through `Package.swift`.
    public init(
        path: AbsolutePath,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        name: String,
        organizationName: String?,
        defaultKnownRegions: [String]?,
        developmentRegion: String?,
        options: Options,
        settings: Settings,
        filesGroup: ProjectGroup,
        targets: [Target],
        packages: [Package],
        schemes: [Scheme],
        ideTemplateMacros: IDETemplateMacros?,
        additionalFiles: [FileElement],
        resourceSynthesizers: [ResourceSynthesizer],
        lastUpgradeCheck: Version?,
        isExternal: Bool
    ) {
        self.path = path
        self.sourceRootPath = sourceRootPath
        self.xcodeProjPath = xcodeProjPath
        self.name = name
        self.organizationName = organizationName
        self.defaultKnownRegions = defaultKnownRegions
        self.developmentRegion = developmentRegion
        self.options = options
        self.targets = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        self.packages = packages
        self.schemes = schemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.ideTemplateMacros = ideTemplateMacros
        self.additionalFiles = additionalFiles
        self.resourceSynthesizers = resourceSynthesizers
        self.lastUpgradeCheck = lastUpgradeCheck
        self.isExternal = isExternal
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

    /// Returns the name of the default configuration.
    public var defaultDebugBuildConfigurationName: String {
        let debugConfiguration = settings.defaultDebugBuildConfiguration()
        let buildConfiguration = debugConfiguration ?? settings.configurations.keys.first
        return buildConfiguration?.name ?? BuildConfiguration.debug.name
    }
}
