import Foundation
import TSCBasic

public struct Target: Equatable, Hashable, Comparable {
    // MARK: - Static

    public static let validSourceExtensions: [String] = ["m", "swift", "mm", "cpp", "c", "d", "s", "intentdefinition", "xcmappingmodel", "metal"]
    public static let validFolderExtensions: [String] = ["framework", "bundle", "app", "xcassets", "appiconset", "scnassets"]

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
    public var dependencies: [Dependency]
    public var sources: [SourceFile]
    public var resources: [FileElement]
    public var copyFiles: [CopyFilesAction]
    public var headers: Headers?
    public var coreDataModels: [CoreDataModel]
    public var actions: [TargetAction]
    public var environment: [String: String]
    public var launchArguments: [LaunchArgument]
    public var filesGroup: ProjectGroup
    public var scripts: [TargetScript]
    public var playgrounds: [AbsolutePath]

    /// When true it indicates that the target should be stripped from the graph when tree-shaking the project.
    public var prune: Bool = false

    // MARK: - Init

    public init(name: String,
                platform: Platform,
                product: Product,
                productName: String?,
                bundleId: String,
                deploymentTarget: DeploymentTarget? = nil,
                infoPlist: InfoPlist? = nil,
                entitlements: AbsolutePath? = nil,
                settings: Settings? = nil,
                sources: [SourceFile] = [],
                resources: [FileElement] = [],
                copyFiles: [CopyFilesAction] = [],
                headers: Headers? = nil,
                coreDataModels: [CoreDataModel] = [],
                actions: [TargetAction] = [],
                environment: [String: String] = [:],
                launchArguments: [LaunchArgument] = [],
                filesGroup: ProjectGroup,
                dependencies: [Dependency] = [],
                scripts: [TargetScript] = [],
                playgrounds: [AbsolutePath] = [])
    {
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
        self.actions = actions
        self.environment = environment
        self.launchArguments = launchArguments
        self.filesGroup = filesGroup
        self.dependencies = dependencies
        self.scripts = scripts
        self.playgrounds = playgrounds
    }

    /// Target can be included in the link phase of other targets
    public func isLinkable() -> Bool {
        [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Returns target's pre actions.
    public var preActions: [TargetAction] {
        actions.filter { $0.order == .pre }
    }

    /// Returns target's post actions.
    public var postActions: [TargetAction] {
        actions.filter { $0.order == .post }
    }

    /// Target can link static products (e.g. an app can link a staticLibrary)
    public func canLinkStaticProducts() -> Bool {
        [
            .framework,
            .app,
            .commandLineTool,
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
        case .dynamicLibrary, .staticLibrary, .staticFramework:
            return false
        default:
            return true
        }
    }

    /// Returns true if the target is an AppClip
    public var isAppClip: Bool {
        if case .appClip = product {
            return true
        }
        return false
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
            lhs.actions == rhs.actions &&
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

    /// Returns a new copy of the target with the given actions.
    /// - Parameter actions: Actions to be set to the copied instance.
    public func with(actions: [TargetAction]) -> Target {
        var copy = self
        copy.actions = actions
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
        filter { $0.product.testsBundle }
    }

    /// Filters and returns only the targets that are apps and app clips.
    var apps: [Target] {
        filter { $0.product == .app || $0.product == .appClip }
    }
}
