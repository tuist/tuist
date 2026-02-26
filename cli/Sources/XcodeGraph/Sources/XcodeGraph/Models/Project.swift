import Foundation
import Path

public enum ProjectType: Hashable, Equatable, Codable, CustomStringConvertible, Sendable {
    /// A project is a local project managed by the user.
    case local
    /// A project is external (e.g. represents a Swift Package project). In those cases,
    /// a hash can be provided, from example from the resolved ref of the represented package,
    /// to skip the file-system-based hashing.
    case external(hash: String? = nil)

    public var description: String {
        switch self {
        case .local: "local project"
        case .external: "external project"
        }
    }
}

public struct Project: Hashable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, Codable, Sendable {
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

    /// Class prefix.
    public var classPrefix: String?

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

    /// It represents the type of project.
    public var type: ProjectType

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
    ///   - type: The type of project, either local or external. This attribute supersedes `isExternal`
    public init(
        path: AbsolutePath,
        sourceRootPath: AbsolutePath,
        xcodeProjPath: AbsolutePath,
        name: String,
        organizationName: String?,
        classPrefix: String?,
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
        type: ProjectType
    ) {
        self.path = path
        self.sourceRootPath = sourceRootPath
        self.xcodeProjPath = xcodeProjPath
        self.name = name
        self.organizationName = organizationName
        self.classPrefix = classPrefix
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
        self.type = type
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

#if DEBUG
    extension Project {
        public static func test(
            path: AbsolutePath = try! AbsolutePath(validating: "/Project"), // swiftlint:disable:this force_try
            sourceRootPath: AbsolutePath = try! AbsolutePath(validating: "/Project"), // swiftlint:disable:this force_try
            // swiftlint:disable:next force_try
            xcodeProjPath: AbsolutePath = try! AbsolutePath(validating: "/Project/Project.xcodeproj"),
            name: String = "Project",
            organizationName: String? = nil,
            classPrefix: String? = nil,
            defaultKnownRegions: [String]? = nil,
            developmentRegion: String? = nil,
            options: Options = .test(automaticSchemesOptions: .disabled),
            settings: Settings = Settings.test(),
            filesGroup: ProjectGroup = .group(name: "Project"),
            targets: [Target] = [Target.test()],
            packages: [Package] = [],
            schemes: [Scheme] = [],
            ideTemplateMacros: IDETemplateMacros? = nil,
            additionalFiles: [FileElement] = [],
            resourceSynthesizers: [ResourceSynthesizer] = [],
            lastUpgradeCheck: Version? = nil,
            type: ProjectType = .local
        ) -> Project {
            Project(
                path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                classPrefix: classPrefix,
                defaultKnownRegions: defaultKnownRegions,
                developmentRegion: developmentRegion,
                options: options,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                ideTemplateMacros: ideTemplateMacros,
                additionalFiles: additionalFiles,
                resourceSynthesizers: resourceSynthesizers,
                lastUpgradeCheck: lastUpgradeCheck,
                type: type
            )
        }

        public static func empty(
            path: AbsolutePath = try! AbsolutePath(validating: "/test/"), // swiftlint:disable:this force_try
            sourceRootPath: AbsolutePath = try! AbsolutePath(validating: "/test/"), // swiftlint:disable:this force_try
            // swiftlint:disable:next force_try
            xcodeProjPath: AbsolutePath = try! AbsolutePath(validating: "/test/text.xcodeproj"),
            name: String = "Project",
            organizationName: String? = nil,
            classPrefix: String? = nil,
            defaultKnownRegions: [String]? = nil,
            developmentRegion: String? = nil,
            options: Options = .test(automaticSchemesOptions: .disabled),
            settings: Settings = .default,
            filesGroup: ProjectGroup = .group(name: "Project"),
            targets: [Target] = [],
            packages: [Package] = [],
            schemes: [Scheme] = [],
            ideTemplateMacros: IDETemplateMacros? = nil,
            additionalFiles: [FileElement] = [],
            resourceSynthesizers: [ResourceSynthesizer] = [],
            lastUpgradeCheck: Version? = nil,
            type: ProjectType = .external(hash: "project-hash")
        ) -> Project {
            Project(
                path: path,
                sourceRootPath: sourceRootPath,
                xcodeProjPath: xcodeProjPath,
                name: name,
                organizationName: organizationName,
                classPrefix: classPrefix,
                defaultKnownRegions: defaultKnownRegions,
                developmentRegion: developmentRegion,
                options: options,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                ideTemplateMacros: ideTemplateMacros,
                additionalFiles: additionalFiles,
                resourceSynthesizers: resourceSynthesizers,
                lastUpgradeCheck: lastUpgradeCheck,
                type: type
            )
        }
    }

    extension Project.Options {
        public static func test(
            automaticSchemesOptions: AutomaticSchemesOptions = .enabled(
                targetSchemesGrouping: .byNameSuffix(
                    build: ["Implementation", "Interface", "Mocks", "Testing"],
                    test: ["Tests", "IntegrationTests", "UITests", "SnapshotTests"],
                    run: ["App", "Demo"]
                ),
                codeCoverageEnabled: false,
                testingOptions: []
            ),
            disableBundleAccessors: Bool = false,
            disableShowEnvironmentVarsInScriptPhases: Bool = false,
            disableSynthesizedResourceAccessors: Bool = false,
            textSettings: TextSettings = .init(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        ) -> Self {
            .init(
                automaticSchemesOptions: automaticSchemesOptions,
                disableBundleAccessors: disableBundleAccessors,
                disableShowEnvironmentVarsInScriptPhases: disableShowEnvironmentVarsInScriptPhases,
                disableSynthesizedResourceAccessors: disableSynthesizedResourceAccessors,
                textSettings: textSettings
            )
        }
    }

    extension Project.Options.TextSettings {
        public static func test(
            usesTabs: Bool? = true,
            indentWidth: UInt? = 2,
            tabWidth: UInt? = 2,
            wrapsLines: Bool? = true
        ) -> Self {
            .init(
                usesTabs: usesTabs,
                indentWidth: indentWidth,
                tabWidth: tabWidth,
                wrapsLines: wrapsLines
            )
        }
    }
#endif
