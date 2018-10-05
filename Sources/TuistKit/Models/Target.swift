import Basic
import Foundation
import TuistCore

class Target: GraphJSONInitiatable, Equatable {
    // MARK: - Static

    static let validSourceExtensions: [String] = ["m", "swift", "mm"]
    static let validFolderExtensions: [String] = ["framework", "bundle", "app", "appiconset"]

    // MARK: - Attributes

    let name: String
    let platform: Platform
    let product: Product
    let bundleId: String
    let infoPlist: AbsolutePath
    let entitlements: AbsolutePath?
    let settings: Settings?
    let dependencies: [JSON]
    let sources: [AbsolutePath]
    let resources: [AbsolutePath]
    let headers: Headers?
    let coreDataModels: [CoreDataModel]
    let actions: [TargetAction]

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
         dependencies: [JSON] = []) {
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
        self.dependencies = dependencies
        self.actions = actions
    }

    required init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling = FileHandler()) throws {
        name = try json.get("name")
        platform = Platform(rawValue: try json.get("platform"))!
        product = Product(rawValue: try json.get("product"))!
        bundleId = try json.get("bundle_id")
        dependencies = try json.get("dependencies")

        // Info.plist
        let infoPlistPath: String = try json.get("info_plist")
        infoPlist = projectPath.appending(RelativePath(infoPlistPath))

        // Entitlements
        let entitlementsPath: String? = try? json.get("entitlements")
        entitlements = entitlementsPath.map({ projectPath.appending(RelativePath($0)) })

        // Settings
        let settingsDictionary: [String: JSONSerializable]? = try? json.get("settings")
        settings = try settingsDictionary.map({ dictionary in
            try Settings(json: JSON(dictionary), projectPath: projectPath, fileHandler: fileHandler)
        })

        // Sources
        let sources: String = try json.get("sources")
        self.sources = try Target.sources(projectPath: projectPath, sources: sources, fileHandler: fileHandler)

        // Resources
        if let resources: String = try? json.get("resources") {
            self.resources = try Target.resources(projectPath: projectPath, resources: resources, fileHandler: fileHandler)
        } else {
            resources = []
        }

        // Headers
        if let headers: JSON = try? json.get("headers") {
            self.headers = try Headers(json: headers, projectPath: projectPath, fileHandler: fileHandler)
        } else {
            headers = nil
        }

        // Core Data Models
        if let coreDataModels: [JSON] = try? json.get("core_data_models") {
            self.coreDataModels = try coreDataModels.map({
                try CoreDataModel(json: $0, projectPath: projectPath, fileHandler: fileHandler)
            })
        } else {
            coreDataModels = []
        }

        // Actions
        if let actions: [JSON] = try? json.get("actions") {
            self.actions = try actions.map({
                try TargetAction(json: $0, projectPath: projectPath, fileHandler: fileHandler)
            })
        } else {
            actions = []
        }
    }

    func isLinkable() -> Bool {
        return product == .dynamicLibrary || product == .staticLibrary || product == .framework
    }

    var productName: String {
        return "\(name).\(product.xcodeValue.fileExtension!)"
    }

    // MARK: - Fileprivate

    fileprivate static func sources(projectPath: AbsolutePath, sources: String, fileHandler _: FileHandling) throws -> [AbsolutePath] {
        return projectPath.glob(sources).filter { path in
            if let `extension` = path.extension, Target.validSourceExtensions.contains(`extension`) {
                return true
            }
            return false
        }
    }

    fileprivate static func resources(projectPath: AbsolutePath, resources: String, fileHandler: FileHandling) throws -> [AbsolutePath] {
        return projectPath.glob(resources).filter { path in
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
            lhs.dependencies == rhs.dependencies
    }
}
