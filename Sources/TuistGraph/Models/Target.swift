import Foundation
import TSCBasic

// swiftlint:disable:next type_body_length
public struct Target: Equatable, Hashable, Comparable, Codable {
    // MARK: - Static

    // Note: The `.docc` file type is technically both a valid source extension and folder extension
    //       in order to compile the documentation archive (including Tutorials, Articles, etc.)
    public static let validSourceExtensions: [String] = [
        "m", "swift", "mm", "cpp", "cc", "c", "d", "s", "intentdefinition", "xcmappingmodel", "metal", "mlmodel", "docc",
        "playground", "rcproject", "mlpackage",
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
    public var resources: [ResourceFileElement]
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
    public var prune: Bool

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
        resources: [ResourceFileElement] = [],
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
        prune: Bool = false
    ) {
        self.name = name
        self.product = product
        self.destinations = destinations
        self.bundleId = bundleId
        self.productName = productName ?? name.replacingOccurrences(of: "-", with: "_")
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
    }

    /// Target can be included in the link phase of other targets
    public func isLinkable() -> Bool {
        [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Returns whether a target is exclusive to a single platform
    public func isExclusiveTo(_ platform: Platform) -> Bool {
        destinations.map(\.platform).allSatisfy { $0 == platform }
    }

    /// Returns whether a target supports a platform
    public func supports(_ platform: Platform) -> Bool {
        destinations.map(\.platform).contains(platform)
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
             .extensionKitExtension:
            return true

        case .commandLineTool,
             .dynamicLibrary,
             .staticLibrary,
             .staticFramework,
             .xpc:
            return false
        }
    }

    public var legacyPlatform: Platform {
        destinations.first?.platform ?? .iOS
    }

    /// Returns true if the target is an AppClip
    public var isAppClip: Bool {
        if case .appClip = product {
            return true
        }
        return false
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

    /// Determines if the target is an embeddable system extension
    /// i.e. a product that can be bundled with a host macOS application
    public func isEmbeddableSystemExtension() -> Bool {
        product == .systemExtension
    }

    /// Determines if the target is able to embed a watch application
    /// i.e. a product that can be bundled with a watchOS application
    public func canEmbedWatchApplications() -> Bool {
        isExclusiveTo(.iOS) && product == .app
    }

    /// Determines if the target is able to embed an system extension
    /// i.e. a product that can be bundled with a macOS application
    public func canEmbedSystemExtensions() -> Bool {
        isExclusiveTo(.macOS) && product == .app
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
            lhs.environmentVariables == rhs.environmentVariables
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(destinations)
        hasher.combine(product)
        hasher.combine(bundleId)
        hasher.combine(productName)
        hasher.combine(environmentVariables)
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

extension Sequence where Element == Target {
    /// Filters and returns only the targets that are test bundles.
    var testBundles: [Target] {
        filter(\.product.testsBundle)
    }

    /// Filters and returns only the targets that are apps and app clips.
    var apps: [Target] {
        filter { $0.product == .app || $0.product == .appClip }
    }
}
