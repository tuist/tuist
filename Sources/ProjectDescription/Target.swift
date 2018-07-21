import Foundation

// MARK: - Target

public class Target {
    /// Target name.
    let name: String

    /// Product platform.
    let platform: Platform

    /// Product type.
    let product: Product

    /// Bundle identifier.
    let bundleId: String

    /// Relative path to the Info.plist file.
    let infoPlist: String

    /// Relative path to the entitlements file.
    let entitlements: String?

    /// Target settings.
    let settings: Settings?

    /// Target dependencies.
    let dependencies: [TargetDependency]

    /// Relative path to the sources directory.
    let sources: String

    /// Relative path to the resources directory.
    let resources: String?

    /// Headers.
    let headers: Headers?

    /// CoreData models.
    let coreDataModels: [CoreDataModel]

    /// Initializes the target.
    ///
    /// - Parameters:
    ///   - name: target name.
    ///   - platform: product platform.
    ///   - product: product type.
    ///   - bundleId: bundle identifier.
    ///   - infoPlist: relative path to the Info.plist file.
    ///   - sources: relative path to the sources directory.
    ///   - resources: relative path to the resources directory.
    ///   - headers: headers.
    ///   - entitlements: relative path to the entitlements file.
    ///   - dependencies: target dependencies.
    ///   - settings: target settings.
    ///   - coreDataModels: CoreData models.
    public init(name: String,
                platform: Platform,
                product: Product,
                bundleId: String,
                infoPlist: String,
                sources: String,
                resources: String? = nil,
                headers: Headers? = nil,
                entitlements: String? = nil,
                dependencies: [TargetDependency] = [],
                settings: Settings? = nil,
                coreDataModels: [CoreDataModel] = []) {
        self.name = name
        self.platform = platform
        self.bundleId = bundleId
        self.product = product
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.dependencies = dependencies
        self.settings = settings
        self.sources = sources
        self.resources = resources
        self.headers = headers
        self.coreDataModels = coreDataModels
    }
}

// MARK: - Target (JSONConvertible)

extension Target: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["name"] = name.toJSON()
        dictionary["platform"] = platform.toJSON()
        dictionary["product"] = product.toJSON()
        dictionary["bundle_id"] = bundleId.toJSON()
        dictionary["info_plist"] = infoPlist.toJSON()
        if let entitlements = entitlements {
            dictionary["entitlements"] = entitlements.toJSON()
        }
        dictionary["dependencies"] = dependencies.toJSON()
        if let settings = settings {
            dictionary["settings"] = settings.toJSON()
        }
        dictionary["sources"] = sources.toJSON()
        if let resources = resources {
            dictionary["resources"] = resources.toJSON()
        }
        if let headers = headers {
            dictionary["headers"] = headers.toJSON()
        }
        dictionary["core_data_models"] = .array(coreDataModels.map({ $0.toJSON() }))
        return .dictionary(dictionary)
    }
}
