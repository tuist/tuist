import Basic
import Foundation

/// Project target.
class Target: GraphJSONInitiatable {
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
        infoPlist = projectPath.appending(component: infoPlistPath)
        if !context.fileHandler.exists(infoPlist) {
            throw GraphLoadingError.missingFile(infoPlist)
        }
        let entitlementsPath: String? = json.get("entitlements")
        entitlements = entitlementsPath.map({ projectPath.appending(component: $0) })
        if let entitlements = entitlements, !context.fileHandler.exists(entitlements) {
            throw GraphLoadingError.missingFile(entitlements)
        }
        let settingsJSON: JSON? = try json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, projectPath: projectPath, context: context) })
        let buildPhasesJSONs: [JSON] = try json.get("build_phases")
        buildPhases = try buildPhasesJSONs.map({ try BuildPhase.from(json: $0, projectPath: projectPath, context: context) })
        dependencies = try json.get("dependencies")
    }
}
