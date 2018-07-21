import Basic
import Foundation
import xpmcore

class Target: GraphJSONInitiatable, Equatable {

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
    }

    required init(json: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws {
        name = try json.get("name")
        let platformString: String = try json.get("platform")
        platform = Platform(rawValue: platformString)!
        let productString: String = try json.get("product")
        product = Product(rawValue: productString)!
        bundleId = try json.get("bundle_id")
        let infoPlistPath: String = try json.get("info_plist")
        infoPlist = projectPath.appending(RelativePath(infoPlistPath))
        if !fileHandler.exists(infoPlist) {
            throw GraphLoadingError.missingFile(infoPlist)
        }
        let entitlementsPath: String? = try? json.get("entitlements")
        entitlements = entitlementsPath.map({ projectPath.appending(RelativePath($0)) })
        if let entitlements = entitlements, !fileHandler.exists(entitlements) {
            throw GraphLoadingError.missingFile(entitlements)
        }
        let settingsDictionary: [String: JSONSerializable]? = try? json.get("settings")
        settings = try settingsDictionary.map({ dictionary in
            try Settings(json: JSON(dictionary), projectPath: projectPath, fileHandler: fileHandler)
        })

        let sources: String = try json.get("sources")
        self.sources = try Target.sources(projectPath: projectPath, sources: sources, fileHandler: fileHandler)

        if let resources: String = try? json.get("resources") {
            self.resources = try Target.resources(projectPath: projectPath, sources: resources, fileHandler: fileHandler)
        } else {
            resources = []
        }
        if let headers: JSON = try? json.get("headers") {
            self.headers = try Headers(json: headers, projectPath: projectPath, fileHandler: fileHandler)
        } else {
            headers = nil
        }
        // TODO: CoreDataModels
        dependencies = try json.get("dependencies")
    }

    func isLinkable() -> Bool {
        return product == .dynamicLibrary || product == .staticLibrary || product == .framework
    }

    var productName: String {
        return "\(name).\(product.xcodeValue.fileExtension!)"
    }

    // MARK: - Fileprivate

    fileprivate static func sources(projectPath _: AbsolutePath, sources _: String, fileHandler _: FileHandling) throws -> [AbsolutePath] {
        // static let validExtensions: [String] = ["m", "swift", "mm"]
        // TODO:
        return []
    }

    fileprivate static func resources(projectPath _: AbsolutePath, sources _: String, fileHandler _: FileHandling) throws -> [AbsolutePath] {
        // TODO:
        return []
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
