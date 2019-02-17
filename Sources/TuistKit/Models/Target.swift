import Basic
import Foundation
import TuistCore

class Target: GraphInitiatable, Equatable {
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
    let dependencies: [JSON]
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
        self.actions = actions
        self.environment = environment
        self.dependencies = dependencies
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling = FileHandler()) throws {
        name = try dictionary.get("name")
        platform = Platform(rawValue: try dictionary.get("platform"))!
        product = Product(rawValue: try dictionary.get("product"))!
        bundleId = try dictionary.get("bundle_id")
        dependencies = try dictionary.get("dependencies")

        // Info.plist
        let infoPlistPath: String = try dictionary.get("info_plist")
        infoPlist = projectPath.appending(RelativePath(infoPlistPath))

        // Entitlements
        let entitlementsPath: String? = try? dictionary.get("entitlements")
        entitlements = entitlementsPath.map({ projectPath.appending(RelativePath($0)) })

        // Settings
        let settingsDictionary: [String: JSONSerializable]? = try? dictionary.get("settings")
        settings = try settingsDictionary.map({ dictionary in
            try Settings(dictionary: JSON(dictionary), projectPath: projectPath, fileHandler: fileHandler)
        })

        // Sources
        if let sources: FileList = try? dictionary.get("sources") {
            self.sources = try sources.globs.flatMap({
                try Target.sources(projectPath: projectPath, sources: $0, fileHandler: fileHandler)
            })
        } else {
            sources = []
        }

        // Resources
        if let resources: FileList = try? dictionary.get("resources") {
            self.resources = try resources.globs.flatMap({
                try Target.resources(projectPath: projectPath, resources: $0, fileHandler: fileHandler)
            })
        } else {
            resources = []
        }

        // Headers
        if let headers: JSON = try? dictionary.get("headers") {
            self.headers = try Headers(dictionary: headers, projectPath: projectPath, fileHandler: fileHandler)
        } else {
            headers = nil
        }

        // Core Data Models
        if let coreDataModels: [JSON] = try? dictionary.get("core_data_models") {
            self.coreDataModels = try coreDataModels.map({
                try CoreDataModel(dictionary: $0, projectPath: projectPath, fileHandler: fileHandler)
            })
        } else {
            coreDataModels = []
        }

        // Actions
        if let actions: [JSON] = try? dictionary.get("actions") {
            self.actions = try actions.map({
                try TargetAction(dictionary: $0, projectPath: projectPath, fileHandler: fileHandler)
            })
        } else {
            actions = []
        }

        // Environment
        if let environment: [String: String] = try? dictionary.get("environment") {
            self.environment = environment
        } else {
            environment = [:]
        }
    }

    func isLinkable() -> Bool {
        return product == .dynamicLibrary || product == .staticLibrary || product == .framework
    }

    var productName: String {
        switch product {
        case .staticLibrary, .dynamicLibrary:
            return "lib\(name).\(product.xcodeValue.fileExtension!)"
        case _:
            return "\(name).\(product.xcodeValue.fileExtension!)"
        }
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
            lhs.dependencies == rhs.dependencies &&
            lhs.environment == rhs.environment
    }
}
