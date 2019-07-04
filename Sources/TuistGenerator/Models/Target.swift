import Basic
import Foundation
import TuistCore

public class Target: Equatable, Hashable {
    public typealias SourceFile = (path: AbsolutePath, compilerFlags: String?)

    // MARK: - Static

    static let validSourceExtensions: [String] = ["m", "swift", "mm", "cpp", "c", "d"]
    static let validFolderExtensions: [String] = ["framework", "bundle", "app", "xcassets", "appiconset"]

    // MARK: - Attributes

    public let name: String
    public let platform: Platform
    public let product: Product
    public let bundleId: String
    public let productName: String

    // An info.plist file is needed for (dynamic) frameworks, applications and executables
    // however is not needed for other products such as static libraries.
    public let infoPlist: InfoPlist?
    public let entitlements: AbsolutePath?
    public let settings: Settings?
    public let dependencies: [Dependency]
    public let sources: [SourceFile]
    public let resources: [FileElement]
    public let headers: Headers?
    public let coreDataModels: [CoreDataModel]
    public let actions: [TargetAction]
    public let environment: [String: String]
    public let filesGroup: ProjectGroup

    // MARK: - Init

    public init(name: String,
                platform: Platform,
                product: Product,
                productName: String,
                bundleId: String,
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
        self.productName = productName
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
    func isLinkable() -> Bool {
        return [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Target can link staitc products (e.g. an app can link a staticLibrary)
    func canLinkStaticProducts() -> Bool {
        return [.framework, .app, .unitTests, .uiTests].contains(product)
    }

    /// Returns the product name including the extension.
    var productNameWithExtension: String {
        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(productName).\(product.xcodeValue.fileExtension!)"
        case _:
            return "\(productName).\(product.xcodeValue.fileExtension!)"
        }
    }

    var supportsSources: Bool {
        switch (platform, product) {
        case (.iOS, .bundle):
            return false
        default:
            return true
        }
    }

    public static func sources(projectPath: AbsolutePath, sources: [(glob: String, compilerFlags: String?)]) throws -> [Target.SourceFile] {
        var sourceFiles: [AbsolutePath: Target.SourceFile] = [:]
        sources.forEach { source in
            projectPath.glob(source.glob).filter { path in
                if let `extension` = path.extension, Target.validSourceExtensions.contains(`extension`) {
                    return true
                }
                return false
            }.forEach { sourceFiles[$0] = (path: $0, compilerFlags: source.compilerFlags) }
        }
        return Array(sourceFiles.values)
    }

    public static func isResource(path: AbsolutePath, fileHandler: FileHandling) -> Bool {
        if !fileHandler.isFolder(path) {
            return true
            // We filter out folders that are not Xcode supported bundles such as .app or .framework.
        } else if let `extension` = path.extension, Target.validFolderExtensions.contains(`extension`) {
            return true
        } else {
            return false
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.name == rhs.name &&
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
//        hasher.combine(infoPlist)
        hasher.combine(entitlements)
//        hasher.combine(settings)
//        hasher.combine(sources)
//        hasher.combine(resources)
//        hasher.combine(headers)
//        hasher.combine(coreDataModels)
//        hasher.combine(dependencies)
        hasher.combine(environment)
    }
}

extension Sequence where Element == Target {
    /// Filters and returns only the targets that are test bundles.
    var testBundles: [Target] {
        return filter { $0.product.testsBundle }
    }

    /// Filters and returns only the targets that are apps.
    var apps: [Target] {
        return filter { $0.product == .app }
    }
}
