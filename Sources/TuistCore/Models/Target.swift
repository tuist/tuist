import Basic
import Foundation
import TuistSupport

public struct Target: Equatable, Hashable {
    public typealias SourceFile = (path: AbsolutePath, compilerFlags: String?)
    public typealias SourceFileGlob = (glob: String, excluding: [String], compilerFlags: String?)

    // MARK: - Static

    public static let validSourceExtensions: [String] = ["m", "swift", "mm", "cpp", "c", "d", "intentdefinition", "xcmappingmodel", "metal"]
    public static let validFolderExtensions: [String] = ["framework", "bundle", "app", "xcassets", "appiconset"]

    // MARK: - Attributes

    public let name: String
    public let platform: Platform
    public let product: Product
    public let bundleId: String
    public let productName: String
    public let deploymentTarget: DeploymentTarget?

    // An info.plist file is needed for (dynamic) frameworks, applications and executables
    // however is not needed for other products such as static libraries.
    public private(set) var infoPlist: InfoPlist?
    public let entitlements: AbsolutePath?
    public let settings: Settings?
    public let dependencies: [Dependency]
    public let sources: [SourceFile]
    public private(set) var resources: [FileElement]
    public let headers: Headers?
    public let coreDataModels: [CoreDataModel]
    public let actions: [TargetAction]
    public let environment: [String: String]
    public let filesGroup: ProjectGroup

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
                headers: Headers? = nil,
                coreDataModels: [CoreDataModel] = [],
                actions: [TargetAction] = [],
                environment: [String: String] = [:],
                filesGroup: ProjectGroup,
                dependencies: [Dependency] = []) {
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
        self.headers = headers
        self.coreDataModels = coreDataModels
        self.actions = actions
        self.environment = environment
        self.filesGroup = filesGroup
        self.dependencies = dependencies
    }

    /// Target can be included in the link phase of other targets
    public func isLinkable() -> Bool {
        [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Target can link staitc products (e.g. an app can link a staticLibrary)
    public func canLinkStaticProducts() -> Bool {
        [
            .framework,
            .app,
            .unitTests,
            .uiTests,
            .appExtension,
            .watch2Extension,
        ].contains(product)
    }

    /// Returns the product name including the extension.
    public var productNameWithExtension: String {
        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(productName).\(product.xcodeValue.fileExtension!)"
        case _:
            return "\(productName).\(product.xcodeValue.fileExtension!)"
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

    /// Returns true if the file at the given path is a resource.
    /// - Parameter path: Path to the file to be checked.
    public static func isResource(path: AbsolutePath) -> Bool {
        if !FileHandler.shared.isFolder(path) {
            return true
            // We filter out folders that are not Xcode supported bundles such as .app or .framework.
        } else if let `extension` = path.extension, Target.validFolderExtensions.contains(`extension`) {
            return true
        } else {
            return false
        }
    }

    /// This method unfolds the source file globs subtracting the paths that are excluded and ignoring
    /// the files that don't have a supported source extension.
    /// - Parameter sources: List of source file glob to be unfolded.
    public static func sources(sources: [SourceFileGlob]) throws -> [TuistCore.Target.SourceFile] {
        var sourceFiles: [AbsolutePath: TuistCore.Target.SourceFile] = [:]
        sources.forEach { source in
            let sourcePath = AbsolutePath(source.glob)
            let base = AbsolutePath(sourcePath.dirname)

            // Paths that should be excluded from sources
            var excluded: [AbsolutePath] = []
            source.excluding.forEach { path in
                let absolute = AbsolutePath(path)
                let globs = AbsolutePath(absolute.dirname).glob(absolute.basename)
                excluded.append(contentsOf: globs)
            }

            Set(base.glob(sourcePath.basename))
                .subtracting(excluded)
                .filter { path in
                    if let `extension` = path.extension, Target.validSourceExtensions.contains(`extension`) {
                        return true
                    }
                    return false
                }.forEach { sourceFiles[$0] = (path: $0, compilerFlags: source.compilerFlags) }
        }
        return Array(sourceFiles.values)
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

    /// Returns a copy of the target with the given resources.
    /// - Parameter resources: Resources to be set to the copy.
    /// - Returns: Copy of the target with the given resources.
    public func with(resources: [FileElement]) -> Target {
        var copy = self
        copy.resources = resources
        return copy
    }
}

extension Sequence where Element == Target {
    /// Filters and returns only the targets that are test bundles.
    var testBundles: [Target] {
        filter { $0.product.testsBundle }
    }

    /// Filters and returns only the targets that are apps.
    var apps: [Target] {
        filter { $0.product == .app }
    }
}
