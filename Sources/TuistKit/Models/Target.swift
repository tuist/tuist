import Basic
import Foundation
import TuistCore

class Target: Equatable {
    // MARK: - Static

    static let validSourceExtensions: [String] = ["m", "swift", "mm", "cpp", "c"]
    static let validFolderExtensions: [String] = ["framework", "bundle", "app", "xcassets", "appiconset"]

    // MARK: - Attributes

    let name: String
    let platform: Platform
    let product: Product
    let bundleId: String
    let infoPlist: AbsolutePath
    let entitlements: AbsolutePath?
    let settings: Settings?
    let dependencies: [Dependency]
    let sources: [AbsolutePath]
    let resources: [AbsolutePath]
    let headers: Headers?
    let coreDataModels: [CoreDataModel]
    let actions: [TargetAction]
    let environment: [String: String]

    // MARK: - Init

    init(name: String,
         platform: Platform,
         product: Product,
         bundleId: String,
         infoPlist: AbsolutePath,
         entitlements: AbsolutePath? = nil,
         settings: Settings? = nil,
         sources: [AbsolutePath] = [],
         resources: [AbsolutePath] = [],
         headers: Headers? = nil,
         coreDataModels: [CoreDataModel] = [],
         actions: [TargetAction] = [],
         environment: [String: String] = [:],
         dependencies: [Dependency] = []) {
        self.name = name
        self.product = product
        self.platform = platform
        self.bundleId = bundleId
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.settings = settings
        self.sources = sources
        self.resources = resources
        self.headers = headers
        self.coreDataModels = coreDataModels
        self.actions = actions
        self.environment = environment
        self.dependencies = dependencies
    }

    func isLinkable() -> Bool {
        return [.dynamicLibrary, .staticLibrary, .framework, .staticFramework].contains(product)
    }

    /// Returns the product name including the extension.
    var productName: String {
        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(name).\(product.xcodeValue.fileExtension!)"
        case _:
            return "\(name).\(product.xcodeValue.fileExtension!)"
        }
    }

    // MARK: - Fileprivate

    static func sources(projectPath: AbsolutePath, sources: [String], fileHandler _: FileHandling) throws -> [AbsolutePath] {
        return sources.flatMap { source in
            projectPath.glob(source).filter { path in
                if let `extension` = path.extension, Target.validSourceExtensions.contains(`extension`) {
                    return true
                }
                return false
            }
        }
    }

    static func resources(projectPath: AbsolutePath, resources: [String], fileHandler: FileHandling) throws -> [AbsolutePath] {
        return resources.flatMap { source in
            projectPath.glob(source).filter { path in
                if !fileHandler.isFolder(path) {
                    return true
                    // We filter out folders that are not Xcode supported bundles such as .app or .framework.
                } else if let `extension` = path.extension, Target.validFolderExtensions.contains(`extension`) {
                    return true
                } else {
                    return false
                }
            }
        }
    }

    // MARK: - Equatable

    static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.name == rhs.name &&
            lhs.platform == rhs.platform &&
            lhs.product == rhs.product &&
            lhs.bundleId == rhs.bundleId &&
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
}

extension Sequence where Element == Target {
    /// Filters and returns only the targets that are test bundles.
    var testBundles: [Target] {
        return filter({ $0.product.testsBundle })
    }

    /// Filters and returns only the targets that are apps.
    var apps: [Target] {
        return filter({ $0.product == .app })
    }
}
