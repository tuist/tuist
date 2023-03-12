import Foundation
import TSCBasic

// swiftlint:disable:next type_body_length
public struct Target: Equatable, Hashable, Comparable, Codable {
    // MARK: - Static

    // Note: The `.docc` file type is technically both a valid source extension and folder extension
    //       in order to compile the documentation archive (including Tutorials, Articles, etc.)
    public static let validSourceExtensions: [String] = [
        "m", "swift", "mm", "cpp", "cc", "c", "d", "s", "intentdefinition", "xcmappingmodel", "metal", "mlmodel", "docc",
        "playground", "rcproject",
    ]
    public static let validFolderExtensions: [String] = [
        "framework", "bundle", "app", "xcassets", "appiconset", "scnassets",
    ]

    // MARK: - Attributes

    public var name: String
    public var platform: Platform
    public var product: Product
    public var bundleId: String
    public var productName: String
    public var deploymentTarget: DeploymentTarget?

    // An info.plist file is needed for (dynamic) frameworks, applications and executables
    // however is not needed for other products such as static libraries.
    public var infoPlist: InfoPlist?
    public var entitlements: AbsolutePath?
    public var settings: Settings?
    public var dependencies: [TargetDependency]
    public var sources: [SourceFile]
    public var resources: [ResourceFileElement]
    public var copyFiles: [CopyFilesAction]
    public var headers: Headers?
    public var coreDataModels: [CoreDataModel]
    public var scripts: [TargetScript]
    public var environment: [String: String]
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
        platform: Platform,
        product: Product,
        productName: String?,
        bundleId: String,
        deploymentTarget: DeploymentTarget? = nil,
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = nil,
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        headers: Headers? = nil,
        coreDataModels: [CoreDataModel] = [],
        scripts: [TargetScript] = [],
        environment: [String: String] = [:],
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
        self.platform = platform
        self.bundleId = bundleId
        self.productName = productName ?? name.replacingOccurrences(of: "-", with: "_")
        self.deploymentTarget = deploymentTarget
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.settings = settings
        self.sources = sources
        self.resources = resources
        self.copyFiles = copyFiles
        self.headers = headers
        self.coreDataModels = coreDataModels
        self.scripts = scripts
        self.environment = environment
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

    /// Returns target's pre scripts.
    public var preScripts: [TargetScript] {
        scripts.filter { $0.order == .pre }
    }

    /// Returns target's post scripts.
    public var postScripts: [TargetScript] {
        scripts.filter { $0.order == .post }
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
        switch (platform, product) {
        case (.iOS, .bundle), (.iOS, .stickerPackExtension), (.watchOS, .watch2App):
            return false
        default:
            return true
        }
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
             .appClip:
            return true

        case .commandLineTool,
             .dynamicLibrary,
             .staticLibrary,
             .staticFramework,
             .xpc:
            return false
        }
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
        switch (platform, product) {
        case (.watchOS, .watch2App), (.watchOS, .app):
            return true
        default:
            return false
        }
    }

    /// Determines if the target is an embeddable xpc service
    /// i.e. a product that can be bundled with a host macOS application
    public func isEmbeddableXPCService() -> Bool {
        switch (platform, product) {
        case (.macOS, .xpc):
            return true
        default:
            return false
        }
    }

    /// Determines if the target is able to embed a watch application
    /// i.e. a product that can be bundled with a watchOS application
    public func canEmbedWatchApplications() -> Bool {
        switch (platform, product) {
        case (.iOS, .app):
            return true
        default:
            return false
        }
    }

    /// Determines if the target is able to embed an xpc serivce
    /// i.e. a product that can be bundled with a macOS application
    public func canEmbedXPCServices() -> Bool {
        switch (platform, product) {
        case (.macOS, .app):
            return true
        default:
            return false
        }
    }

    /// For iOS targets that support macOS (Catalyst), this value is used
    /// in the generated build files of the target dependency products to
    /// indicate the build system that the dependency should be compiled
    /// with Catalyst compatibility.
    public var targetDependencyBuildFilesPlatformFilter: BuildFilePlatformFilter? {
        switch deploymentTarget {
        case let .iOS(_, devices, _) where devices.contains(.all):
            return nil
        case let .iOS(_, devices, _):
            if devices.contains(.mac) {
                return .catalyst
            } else {
                return .ios
            }
        default:
            return nil
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Target, rhs: Target) -> Bool {
        lhs.name == rhs.name &&
            lhs.platform == rhs.platform &&
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
            lhs.environment == rhs.environment
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(platform)
        hasher.combine(product)
        hasher.combine(bundleId)
        hasher.combine(productName)
        hasher.combine(entitlements)
        hasher.combine(environment)
    }

    /// Returns a new copy of the target with the given InfoPlist set.
    /// - Parameter infoPlist: InfoPlist to be set to the copied instance.
    public func with(infoPlist: InfoPlist) -> Target {
        var copy = self
        copy.infoPlist = infoPlist
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
