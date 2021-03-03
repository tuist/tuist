import Foundation
import TSCBasic

public struct Project: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.path == rhs.path &&
            lhs.sourceRootPath == rhs.sourceRootPath &&
            lhs.xcodeProjPath == rhs.xcodeProjPath &&
            lhs.name == rhs.name &&
            lhs.organizationName == rhs.organizationName &&
            lhs.developmentRegion == rhs.developmentRegion &&
            lhs.targets == rhs.targets &&
            lhs.packages == rhs.packages &&
            lhs.schemes == rhs.schemes &&
            lhs.settings == rhs.settings &&
            lhs.filesGroup == rhs.filesGroup &&
            lhs.additionalFiles == rhs.additionalFiles
    }

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
    ///   - settings: The settings to apply at the project level
    ///   - filesGroup: The root group to place project files within
    ///   - targets: The project targets
    ///   - additionalFiles: The additional files to include in the project
    ///                      *(Those won't be included in any build phases)*
    public init(path: AbsolutePath,
                sourceRootPath: AbsolutePath,
                xcodeProjPath: AbsolutePath,
                name: String,
                organizationName: String?,
                developmentRegion: String?,
                settings: Settings,
                filesGroup: ProjectGroup,
                targets: [Target],
                packages: [Package],
                schemes: [Scheme],
                additionalFiles: [FileElement])
    {
        self.path = path
        self.sourceRootPath = sourceRootPath
        self.xcodeProjPath = xcodeProjPath
        self.name = name
        self.organizationName = organizationName
        self.developmentRegion = developmentRegion
        self.targets = targets
        self.packages = packages
        self.schemes = schemes
        self.settings = settings
        self.filesGroup = filesGroup
        self.additionalFiles = additionalFiles
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
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            additionalFiles: additionalFiles
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
            settings: settings,
            filesGroup: filesGroup,
            targets: targets,
            packages: packages,
            schemes: schemes,
            additionalFiles: additionalFiles
        )
    }

    /// Returns the name of the default configuration.
    public var defaultDebugBuildConfigurationName: String {
        let debugConfiguration = settings.defaultDebugBuildConfiguration()
        let buildConfiguration = debugConfiguration ?? settings.configurations.keys.first
        return buildConfiguration?.name ?? BuildConfiguration.debug.name
    }
}
