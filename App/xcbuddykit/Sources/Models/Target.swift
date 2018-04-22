import Basic
import Foundation

/// Project target.
class Target: GraphJSONInitiatable, Equatable {
    /// Target name.
    let name: String

    /// Platform
    let platform: Platform

    /// Target product type.
    let product: Product

    /// Target info plist path.
    let infoPlist: AbsolutePath

    /// Target entitlements path.
    let entitlements: AbsolutePath?

    /// Target build settings.
    let settings: Settings?

    /// Target build phases.
    let buildPhases: [BuildPhase]

    /// List of dependencies (JSON representations)
    let dependencies: [JSON]

    /// Initializes the target with its properties.
    ///
    /// - Parameters:
    ///   - name: target name.
    ///   - platform: target platform.
    ///   - product: target product type.
    ///   - infoPlist: info plist absolute path.
    ///   - entitlements: entitlements absolute path.
    ///   - settings: target settings.
    ///   - buildPhases: target build phases.
    ///   - dependencies: target dependencies.
    init(name: String,
         platform: Platform,
         product: Product,
         infoPlist: AbsolutePath,
         entitlements: AbsolutePath? = nil,
         settings: Settings? = nil,
         buildPhases: [BuildPhase] = [],
         dependencies: [JSON] = []) {
        self.name = name
        self.product = product
        self.platform = platform
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.settings = settings
        self.buildPhases = buildPhases
        self.dependencies = dependencies
    }

    /// Initializes the target from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: target JSON representation.
    ///   - projectPath: path to the folder that contains the project's manifest.
    ///   - context: graph loader  context.
    /// - Throws: an error if build files cannot be parsed.
    required init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        name = try json.get("name")
        let platformString: String = try json.get("platform")
        platform = Platform(rawValue: platformString)!
        let productString: String = try json.get("product")
        product = Product(rawValue: productString)!
        let infoPlistPath: String = try json.get("info_plist")
        infoPlist = projectPath.appending(RelativePath(infoPlistPath))
        if !context.fileHandler.exists(infoPlist) {
            throw GraphLoadingError.missingFile(infoPlist)
        }
        let entitlementsPath: String? = try? json.get("entitlements")
        entitlements = entitlementsPath.map({ projectPath.appending(RelativePath($0)) })
        if let entitlements = entitlements, !context.fileHandler.exists(entitlements) {
            throw GraphLoadingError.missingFile(entitlements)
        }
        let settingsDictionary: [String: JSONSerializable]? = try? json.get("settings")
        settings = try settingsDictionary.map({ dictionary in
            try Settings(json: JSON(dictionary), projectPath: projectPath, context: context)
        })
        let buildPhasesJSONs: [JSON] = try json.get("build_phases")
        buildPhases = try buildPhasesJSONs.map({ try BuildPhase.parse(from: $0, projectPath: projectPath, context: context) })
        dependencies = try json.get("dependencies")
    }

    /// Compares two targets.
    ///
    /// - Parameters:
    ///   - lhs: first target to be compared.
    ///   - rhs: second target to be compared.
    /// - Returns: true if the two targets are the same.
    static func == (lhs: Target, rhs: Target) -> Bool {
        return lhs.name == rhs.name &&
            lhs.platform == rhs.platform &&
            lhs.product == rhs.product &&
            lhs.infoPlist == rhs.infoPlist &&
            lhs.entitlements == rhs.entitlements &&
            lhs.settings == rhs.settings &&
            lhs.buildPhases == rhs.buildPhases &&
            lhs.dependencies == rhs.dependencies
    }
}
