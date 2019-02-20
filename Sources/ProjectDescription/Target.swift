import Foundation

// MARK: - Target

public class Target: Codable {
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
    let settings: TargetSettings?

    /// Target dependencies.
    let dependencies: [TargetDependency]

    /// Relative path to the sources directory.
    let sources: String

    /// Relative path to the resources directory.
    let resources: String?

    /// Headers.
    let headers: Headers?

    /// Target actions.
    let actions: [TargetAction]

    /// CoreData models.
    let coreDataModels: [CoreDataModel]

    /// Environment variables to be exposed to the target.
    let environment: [String: String]

    public enum CodingKeys: String, CodingKey {
        case name
        case platform
        case product
        case bundleId = "bundle_id"
        case infoPlist = "info_plist"
        case entitlements
        case settings
        case dependencies
        case sources
        case resources
        case headers
        case coreDataModels = "core_data_models"
        case actions
        case environment
    }

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
    ///   - actions: target actions.
    ///   - dependencies: target dependencies.
    ///   - settings: target settings.
    ///   - coreDataModels: CoreData models.
    ///   - environment: Environment variables to be exposed to the target.
    public init(name: String,
                platform: Platform,
                product: Product,
                bundleId: String,
                infoPlist: String,
                sources: String,
                resources: String? = nil,
                headers: Headers? = nil,
                entitlements: String? = nil,
                actions: [TargetAction] = [],
                dependencies: [TargetDependency] = [],
                settings: TargetSettings? = nil,
                coreDataModels: [CoreDataModel] = [],
                environment: [String: String] = [:]) {
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
        self.actions = actions
        self.coreDataModels = coreDataModels
        self.environment = environment
    }
}
