import Foundation
import Path

// swiftlint:disable:next type_body_length
public struct Target: Equatable, Hashable, Comparable, Codable, Sendable {
    // MARK: - Static

    /// Note: The `.docc` file type is technically both a valid source extension and folder extension
    ///       in order to compile the documentation archive (including Tutorials, Articles, etc.)
    public static let validSourceCompatibleFolderExtensions: [String] = [
        "playground", "rcproject", "mlpackage", "docc",
    ]
    public static let validSourceExtensions: [String] = [
        "m", "swift", "mm", "cpp", "c++", "cc", "c", "d", "s", "intentdefinition", "metal", "mlmodel", "clp",
    ]
    public static let validResourceExtensions: [String] = [
        // Resource
        "md", "xcstrings", "plist", "rtf", "tutorial", "sks", "xcprivacy", "gpx", "strings", "stringsdict",
        "geojson", "txt", "json", "js",

        // User interface
        "storyboard", "xib",
        // Other
        "xcfilelist", "xcconfig",
    ]
    public static let validResourceCompatibleFolderExtensions: [String] = [
        "xcassets", "scnassets", "bundle", "xcstickers", "app", "xcmappingmodel", "xcdatamodeld",
    ]
    public static let validFolderExtensions: [String] = [
        "framework", "bundle", "app", "xcassets", "appiconset", "scnassets",
    ]

    // MARK: - Attributes

    public var name: String
    public var destinations: Destinations
    public var product: Product
    public var bundleId: String
    public var productName: String
    public var deploymentTargets: DeploymentTargets

    // An info.plist file is needed for (dynamic) frameworks, applications and executables
    // however is not needed for other products such as static libraries.
    public var infoPlist: InfoPlist?
    public var entitlements: Entitlements?
    public var settings: Settings?
    public var dependencies: [TargetDependency]
    public var sources: [SourceFile]
    public var resources: ResourceFileElements
    public var copyFiles: [CopyFilesAction]
    public var headers: Headers?
    public var coreDataModels: [CoreDataModel]
    public var scripts: [TargetScript]
    public var environmentVariables: [String: EnvironmentVariable]
    public var launchArguments: [LaunchArgument]
    public var filesGroup: ProjectGroup
    public var rawScriptBuildPhases: [RawScriptBuildPhase]
    public var playgrounds: [AbsolutePath]
    public let additionalFiles: [FileElement]
    public var buildRules: [BuildRule]
    @available(*, deprecated, message: """
    The prune attribute coupled XcodeGraph to a particular use-case of Tuist and therefore
    we removed it in favor of using metadata as an in-memory context holder that can be leveraged
    using conventional tags.
    """)
    public var prune: Bool
    public let mergedBinaryType: MergedBinaryType
    public let mergeable: Bool
    public let onDemandResourcesTags: OnDemandResourcesTags?
    public var metadata: TargetMetadata
    public let type: TargetType
    public let packages: [AbsolutePath]
    public var buildableFolders: [BuildableFolder]
    public var foreignBuild: ForeignBuild?

    // MARK: - Init

    public init(
        name: String,
        destinations: Destinations,
        product: Product,
        productName: String?,
        bundleId: String,
        deploymentTargets: DeploymentTargets = DeploymentTargets(),
        infoPlist: InfoPlist? = nil,
        entitlements: Entitlements? = nil,
        settings: Settings? = nil,
        sources: [SourceFile] = [],
        resources: ResourceFileElements = .init([]),
        copyFiles: [CopyFilesAction] = [],
        headers: Headers? = nil,
        coreDataModels: [CoreDataModel] = [],
        scripts: [TargetScript] = [],
        environmentVariables: [String: EnvironmentVariable] = [:],
        launchArguments: [LaunchArgument] = [],
        filesGroup: ProjectGroup,
        dependencies: [TargetDependency] = [],
        rawScriptBuildPhases: [RawScriptBuildPhase] = [],
        playgrounds: [AbsolutePath] = [],
        additionalFiles: [FileElement] = [],
        buildRules: [BuildRule] = [],
        prune: Bool = false,
        mergedBinaryType: MergedBinaryType = .disabled,
        mergeable: Bool = false,
        onDemandResourcesTags: OnDemandResourcesTags? = nil,
        metadata: TargetMetadata = .metadata(tags: []),
        type: TargetType = .local,
        packages: [AbsolutePath] = [],
        buildableFolders: [BuildableFolder] = [],
        foreignBuild: ForeignBuild? = nil
    ) {
        self.name = name
        self.product = product
        self.destinations = destinations
        self.bundleId = bundleId
        self.productName = productName ?? Target.sanitizedProductNameFrom(targetName: name)
        self.deploymentTargets = deploymentTargets
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.settings = settings
        self.sources = sources
        self.resources = resources
        self.copyFiles = copyFiles
        self.headers = headers
        self.coreDataModels = coreDataModels
        self.scripts = scripts
        self.environmentVariables = environmentVariables
        self.launchArguments = launchArguments
        self.filesGroup = filesGroup
        self.dependencies = dependencies
        self.rawScriptBuildPhases = rawScriptBuildPhases
        self.playgrounds = playgrounds
        self.additionalFiles = additionalFiles
        self.buildRules = buildRules
        self.prune = prune
        self.mergedBinaryType = mergedBinaryType
        self.mergeable = mergeable
        self.onDemandResourcesTags = onDemandResourcesTags
        self.metadata = metadata
        self.type = type
        self.packages = packages
        self.buildableFolders = buildableFolders
        self.foreignBuild = foreignBuild
    }

    /// Given a target name, it obtains the product name by turning "-" characters into "_" and "/" into "_"
    /// - Parameter targetName: The target name.
    /// - Returns: The sanitized produdct name.
    public static func sanitizedProductNameFrom(targetName: String) -> String {
        targetName.replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    public var isAggregate: Bool {
        foreignBuild != nil
    }

    /// Target can be included in the link phase of other targets
    public func isLinkable() -> Bool {
        [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Returns whether a target is exclusive to a single platform
    public func isExclusiveTo(_ platform: Platform) -> Bool {
        destinations.allSatisfy { $0.platform == platform }
    }

    /// Returns whether a target supports a platform
    public func supports(_ platform: Platform) -> Bool {
        destinations.contains { $0.platform == platform }
    }

    /// List of platforms this target deploys to
    public var supportedPlatforms: Set<Platform> {
        Set(destinations.map(\.platform))
    }

    /// Returns target's pre scripts.
    public var preScripts: [TargetScript] {
        scripts.filter { $0.order == .pre }
    }

    /// Returns target's post scripts.
    public var postScripts: [TargetScript] {
        scripts.filter { $0.order == .post }
    }

    /// Returns true if the target supports Mac Catalyst
    public var supportsCatalyst: Bool {
        destinations.contains(.macCatalyst)
    }

    /// Target can link static products (e.g. an app can link a staticLibrary)
    public func canLinkStaticProducts() -> Bool {
        [
            .framework,
            .app,
            .commandLineTool,
            .xpc,
            .unitTests,
            .uiTests,
            .appExtension,
            .watch2Extension,
            .messagesExtension,
            .appClip,
            .tvTopShelfExtension,
            .systemExtension,
            .extensionKitExtension,
            .macro,
        ].contains(product)
    }

    /// Returns true if the target supports having a headers build phase..
    public var shouldIncludeHeadersBuildPhase: Bool {
        switch product {
        case .framework, .staticFramework, .staticLibrary, .dynamicLibrary:
            return true
        default:
            return false
        }
    }

    /// Returns true if the target supports having sources.
    @available(*, deprecated, message: """
    Whether a target supports sources or not is not as binary decision as we originally assumed and codified in this getter.
    Because it's something that depends on other variables, we decided to pull this logic out of tuist/XcodeGraph into tuist/tuist.
    If you are interested in having a similar logic in your XcodeGraph-dependent project, you might want to check out tuist/tuist.
    """)
    public var supportsSources: Bool {
        switch product {
        case .stickerPackExtension, .watch2App:
            return false
        case .bundle:
            // Bundles only support source when targetting macOS only
            return isExclusiveTo(.macOS)
        default:
            return true
        }
    }

    /// Returns true if the target deploys to more then one platform
    public var isMultiplatform: Bool {
        supportedPlatforms.count > 1
    }

    /// Returns true if the target supports hosting resources
    public var supportsResources: Bool {
        switch product {
        case .app,
             .framework,
             .staticFramework,
             .unitTests,
             .uiTests,
             .bundle,
             .appExtension,
             .watch2App,
             .watch2Extension,
             .tvTopShelfExtension,
             .messagesExtension,
             .stickerPackExtension,
             .appClip,
             .systemExtension,
             .extensionKitExtension,
             .commandLineTool,
             .macro,
             .xpc:
            return true

        case .dynamicLibrary,
             .staticLibrary:
            return false
        }
    }

    public var legacyPlatform: Platform {
        destinations.first?.platform ?? .iOS
    }

    /// Returns true if the target is an AppClip
    public var isAppClip: Bool {
        product == .appClip
    }

    /// Determines if the target is an embeddable watch application
    /// i.e. a product that can be bundled with a host iOS application
    public func isEmbeddableWatchApplication() -> Bool {
        let isWatchOS = isExclusiveTo(.watchOS)
        let isApp = (product == .watch2App || product == .app)
        return isWatchOS && isApp
    }

    /// Determines if the target is an embeddable xpc service
    /// i.e. a product that can be bundled with a host macOS application
    public func isEmbeddableXPCService() -> Bool {
        product == .xpc
    }

    /// Determines if the target is an embeddable plugin
    /// i.e. a product that can be bundled with a host macOS application or a Mac Catalyst application
    public func isEmbeddablePlugin() -> Bool {
        supports(.macOS) && product == .bundle
    }

    /// Determines if the target is an embeddable system extension
    /// i.e. a product that can be bundled with a host macOS application
    public func isEmbeddableSystemExtension() -> Bool {
        product == .systemExtension
    }

    /// Determines if the target is able to embed a watch application
    /// i.e. a product that can be bundled with a watchOS application
    public func canEmbedWatchApplications() -> Bool {
        supports(.iOS) && product == .app
    }

    /// Determines if the target is able to embed an system extension
    /// i.e. a product that can be bundled with a macOS application
    public func canEmbedSystemExtensions() -> Bool {
        supports(.macOS) && product == .app
    }

    /// Determines if the target is able to embed a plugin
    /// i.e. a product that can be bundled with a macOS application or a Mac Catalyst application
    public func canEmbedPlugins() -> Bool {
        (supports(.macOS) || supportsCatalyst) && product == .app
    }

    /// Return the a set of PlatformFilters to control linking based on what platform is being compiled
    /// This allows a target to link against a dependency conditionally when it is being compiled for a compatible platform
    /// E.g. An app linking against CarPlay only when built for iOS.
    public var dependencyPlatformFilters: PlatformFilters {
        Set(destinations.map(\.platformFilter))
    }

    // MARK: - Equatable

    public static func == (lhs: Target, rhs: Target) -> Bool {
        lhs.name == rhs.name &&
            lhs.destinations == rhs.destinations &&
            lhs.product == rhs.product &&
            lhs.bundleId == rhs.bundleId &&
            lhs.productName == rhs.productName &&
            lhs.infoPlist == rhs.infoPlist &&
            lhs.entitlements == rhs.entitlements &&
            lhs.settings == rhs.settings &&
            lhs.sources == rhs.sources &&
            lhs.resources == rhs.resources &&
            lhs.headers == rhs.headers &&
            lhs.coreDataModels == rhs.coreDataModels &&
            lhs.scripts == rhs.scripts &&
            lhs.dependencies == rhs.dependencies &&
            lhs.mergedBinaryType == rhs.mergedBinaryType &&
            lhs.mergeable == rhs.mergeable &&
            lhs.environmentVariables == rhs.environmentVariables &&
            lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(destinations)
        hasher.combine(product)
        hasher.combine(bundleId)
        hasher.combine(productName)
        hasher.combine(environmentVariables)
        hasher.combine(type)
    }

    /// Returns a new copy of the target with the given InfoPlist set.
    /// - Parameter infoPlist: InfoPlist to be set to the copied instance.
    public func with(infoPlist: InfoPlist) -> Target {
        var copy = self
        copy.infoPlist = infoPlist
        return copy
    }

    /// Returns a new copy of the target with the given entitlements set.
    /// - Parameter entitlements: entitlements to be set to the copied instance.
    public func with(entitlements: Entitlements) -> Target {
        var copy = self
        copy.entitlements = entitlements
        return copy
    }

    /// Returns a new copy of the target with the given scripts.
    /// - Parameter scripts: Actions to be set to the copied instance.
    public func with(scripts: [TargetScript]) -> Target {
        var copy = self
        copy.scripts = scripts
        return copy
    }

    /// Returns a new copy of the target with the given additional settings
    /// - Parameter additionalSettings: settings to be added.
    public func with(additionalSettings: SettingsDictionary) -> Target {
        var copy = self
        if let oldSettings = copy.settings {
            copy.settings = Settings(
                base: oldSettings.base.merging(additionalSettings, uniquingKeysWith: { $1 }),
                configurations: oldSettings.configurations,
                defaultSettings: oldSettings.defaultSettings
            )
        } else {
            copy.settings = Settings(
                base: additionalSettings,
                configurations: [:]
            )
        }
        return copy
    }

    // MARK: - Comparable

    public static func < (lhs: Target, rhs: Target) -> Bool {
        lhs.name < rhs.name
    }
}

extension Sequence<Target> {
    /// Filters and returns only the targets that are test bundles.
    var testBundles: [Target] {
        filter(\.product.testsBundle)
    }

    /// Filters and returns only the targets that are apps and app clips.
    var apps: [Target] {
        filter { $0.product == .app || $0.product == .appClip }
    }
}

#if DEBUG
    extension Target {
        /// Creates a Target with test data
        /// Note: Referenced paths may not exist
        public static func test(
            name: String = "Target",
            destinations: Destinations = [.iPhone, .iPad],
            product: Product = .app,
            productName: String? = nil,
            bundleId: String? = nil,
            deploymentTargets: DeploymentTargets = .iOS("13.1"),
            infoPlist: InfoPlist? = nil,
            entitlements: Entitlements? = nil,
            settings: Settings? = Settings.test(),
            sources: [SourceFile] = [],
            resources: ResourceFileElements = .init([]),
            copyFiles: [CopyFilesAction] = [],
            coreDataModels: [CoreDataModel] = [],
            headers: Headers? = nil,
            scripts: [TargetScript] = [],
            environmentVariables: [String: EnvironmentVariable] = [:],
            filesGroup: ProjectGroup = .group(name: "Project"),
            dependencies: [TargetDependency] = [],
            rawScriptBuildPhases: [RawScriptBuildPhase] = [],
            launchArguments: [LaunchArgument] = [],
            playgrounds: [AbsolutePath] = [],
            additionalFiles: [FileElement] = [],
            prune: Bool = false,
            mergedBinaryType: MergedBinaryType = .disabled,
            mergeable: Bool = false,
            metadata: TargetMetadata = .test(),
            buildableFolders: [BuildableFolder] = [],
            foreignBuild: ForeignBuild? = nil
        ) -> Target {
            Target(
                name: name,
                destinations: destinations,
                product: product,
                productName: productName,
                bundleId: bundleId ?? "io.tuist.\(name)",
                deploymentTargets: deploymentTargets,
                infoPlist: infoPlist,
                entitlements: entitlements,
                settings: settings,
                sources: sources,
                resources: resources,
                copyFiles: copyFiles,
                headers: headers,
                coreDataModels: coreDataModels,
                scripts: scripts,
                environmentVariables: environmentVariables,
                launchArguments: launchArguments,
                filesGroup: filesGroup,
                dependencies: dependencies,
                rawScriptBuildPhases: rawScriptBuildPhases,
                playgrounds: playgrounds,
                additionalFiles: additionalFiles,
                prune: prune,
                mergedBinaryType: mergedBinaryType,
                mergeable: mergeable,
                metadata: metadata,
                buildableFolders: buildableFolders,
                foreignBuild: foreignBuild
            )
        }

        /// Creates a Target with test data
        /// Note: Referenced paths may not exist
        public static func test(
            name: String = "Target",
            platform: Platform,
            product: Product = .app,
            productName: String? = nil,
            bundleId: String? = nil,
            deploymentTarget: DeploymentTargets = .iOS("13.1"),
            infoPlist: InfoPlist? = nil,
            entitlements: Entitlements? = nil,
            settings: Settings? = Settings.test(),
            sources: [SourceFile] = [],
            resources: ResourceFileElements = .init([]),
            copyFiles: [CopyFilesAction] = [],
            coreDataModels: [CoreDataModel] = [],
            headers: Headers? = nil,
            scripts: [TargetScript] = [],
            environmentVariables: [String: EnvironmentVariable] = [:],
            filesGroup: ProjectGroup = .group(name: "Project"),
            dependencies: [TargetDependency] = [],
            rawScriptBuildPhases: [RawScriptBuildPhase] = [],
            launchArguments: [LaunchArgument] = [],
            playgrounds: [AbsolutePath] = [],
            additionalFiles: [FileElement] = [],
            prune: Bool = false,
            mergedBinaryType: MergedBinaryType = .disabled,
            mergeable: Bool = false,
            metadata: TargetMetadata = .test(),
            buildableFolders: [BuildableFolder] = [],
            foreignBuild: ForeignBuild? = nil
        ) -> Target {
            Target(
                name: name,
                destinations: destinationsFrom(platform),
                product: product,
                productName: productName,
                bundleId: bundleId ?? "io.tuist.\(name)",
                deploymentTargets: deploymentTarget,
                infoPlist: infoPlist,
                entitlements: entitlements,
                settings: settings,
                sources: sources,
                resources: resources,
                copyFiles: copyFiles,
                headers: headers,
                coreDataModels: coreDataModels,
                scripts: scripts,
                environmentVariables: environmentVariables,
                launchArguments: launchArguments,
                filesGroup: filesGroup,
                dependencies: dependencies,
                rawScriptBuildPhases: rawScriptBuildPhases,
                playgrounds: playgrounds,
                additionalFiles: additionalFiles,
                prune: prune,
                mergedBinaryType: mergedBinaryType,
                mergeable: mergeable,
                metadata: metadata,
                buildableFolders: buildableFolders,
                foreignBuild: foreignBuild
            )
        }

        /// Creates a bare bones Target with as little data as possible
        public static func empty(
            name: String = "Target",
            destinations: Destinations = [.iPhone, .iPad],
            product: Product = .app,
            productName: String? = nil,
            bundleId: String? = nil,
            deploymentTargets: DeploymentTargets = .init(),
            infoPlist: InfoPlist? = nil,
            entitlements: Entitlements? = nil,
            settings: Settings? = nil,
            sources: [SourceFile] = [],
            resources: ResourceFileElements = .init([]),
            copyFiles: [CopyFilesAction] = [],
            coreDataModels: [CoreDataModel] = [],
            headers: Headers? = nil,
            scripts: [TargetScript] = [],
            environmentVariables: [String: EnvironmentVariable] = [:],
            filesGroup: ProjectGroup = .group(name: "Project"),
            dependencies: [TargetDependency] = [],
            rawScriptBuildPhases: [RawScriptBuildPhase] = [],
            onDemandResourcesTags: OnDemandResourcesTags? = nil,
            buildableFolders: [BuildableFolder] = []
        ) -> Target {
            Target(
                name: name,
                destinations: destinations,
                product: product,
                productName: productName,
                bundleId: bundleId ?? "io.tuist.\(name)",
                deploymentTargets: deploymentTargets,
                infoPlist: infoPlist,
                entitlements: entitlements,
                settings: settings,
                sources: sources,
                resources: resources,
                copyFiles: copyFiles,
                headers: headers,
                coreDataModels: coreDataModels,
                scripts: scripts,
                environmentVariables: environmentVariables,
                filesGroup: filesGroup,
                dependencies: dependencies,
                rawScriptBuildPhases: rawScriptBuildPhases,
                onDemandResourcesTags: onDemandResourcesTags,
                buildableFolders: buildableFolders
            )
        }

        /// Maps a platform to a set of Destinations.  For migration purposes
        private static func destinationsFrom(_ platform: Platform) -> Destinations {
            switch platform {
            case .iOS:
                return .iOS
            case .macOS:
                return .macOS
            case .tvOS:
                return .tvOS
            case .watchOS:
                return .watchOS
            case .visionOS:
                return .visionOS
            }
        }
    }
#endif
