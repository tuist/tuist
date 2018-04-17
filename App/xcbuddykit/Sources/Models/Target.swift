import Foundation
import Basic

class Target {
    let name: String
    let platform: Platform
    let product: Product
    let infoPlist: AbsolutePath
    let entitlements: AbsolutePath?
    let settings: Settings?
    let buildPhases: [BuildPhase]
    let dependencies: [JSON]

    required init(json: JSON, context: GraphLoaderContexting) throws {
        name = try json.get("name")
        let platformString: String = try json.get("platform")
        platform = Platform(rawValue: platformString)!
        let productString: String = try json.get("product")
        product = Product(rawValue: productString)!
        let infoPlistPath: String = try json.get("info_plist")
        infoPlist = context.projectPath.appending(component: infoPlistPath)
        let entitlementsPath: String? = json.get("entitlements")
        entitlements = entitlementsPath.map({context.projectPath.appending(component: $0)})
        let settingsJSON: JSON? = try json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, context: context)})
        let buildPhasesJSONs: [JSON] = try json.get("build_phases")
        buildPhases = try buildPhasesJSONs.map({ try BuildPhase.from(json: $0, context: context) })
        dependencies = try json.get("dependencies")
    }
}
