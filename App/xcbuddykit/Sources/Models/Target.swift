import Foundation
import Basic

class Target: JSONMappable {
    let name: String
    let platform: Platform
    let product: Product
    let infoPlist: Path
    let entitlements: Path?
    let settings: Settings?
    let buildPhases: [BuildPhase]
    let dependencies: [String: Any]

    required init(json: JSON) throws {
        name = try unboxer.unbox(key: "name")
        platform = try unboxer.unbox(key: "platform")
        product = try unboxer.unbox(key: "product")
        infoPlist = try unboxer.unbox(key: "info_pliast")
        try infoPlist.assertRelative()
        entitlements = unboxer.unbox(key: "entitlements")
        try entitlements?.assertRelative()
        settings = unboxer.unbox(key: "settings")
        buildPhases = try unboxer.unbox(key: "build_phases")
        dependencies = try unboxer.unbox(key: "dependencies")
    }
}
