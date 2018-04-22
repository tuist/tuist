import Foundation

// MARK: - Target

public class Target {
    public let name: String
    public let platform: Platform
    public let product: Product
    public let infoPlist: String
    public let entitlements: String?
    public let settings: Settings?
    public let buildPhases: [BuildPhase]
    public let dependencies: [TargetDependency]
    public init(name: String,
                platform: Platform,
                product: Product,
                infoPlist: String,
                entitlements: String? = nil,
                dependencies: [TargetDependency] = [],
                settings: Settings? = nil,
                buildPhases: [BuildPhase] = []) {
        self.name = name
        self.platform = platform
        self.product = product
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.dependencies = dependencies
        self.settings = settings
        self.buildPhases = buildPhases
    }
}

// MARK: - Target (JSONConvertible)

extension Target: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["name"] = name.toJSON()
        dictionary["platform"] = platform.toJSON()
        dictionary["product"] = product.toJSON()
        dictionary["info_plist"] = infoPlist.toJSON()
        if let entitlements = entitlements {
            dictionary["entitlements"] = entitlements.toJSON()
        }
        dictionary["dependencies"] = dependencies.toJSON()
        if let settings = settings {
            dictionary["settings"] = settings.toJSON()
        }  else {
            dictionary["settings"] = .null
        }
        dictionary["build_phases"] = .array(buildPhases.compactMap({ $0 as? JSONConvertible }).map({ $0.toJSON() }))
        return .dictionary(dictionary)
    }
}
