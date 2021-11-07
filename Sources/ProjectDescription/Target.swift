import Foundation

// MARK: - Target

public struct Target: Codable, Equatable {
    /// Target name.
    public let name: String

    /// Product platform.
    public let platform: Platform

    /// Product type.
    public let product: Product

    /// Bundle identifier.
    public let bundleId: String

    /// The name of the product output by this target.
    /// passing nil in the initialiser will default
    /// this value to the name of the target.
    public let productName: String?

    /// Deployment target.
    public let deploymentTarget: DeploymentTarget?

    /// Relative path to the Info.plist file.
    public let infoPlist: InfoPlist

    /// Relative path to the entitlements file.
    public let entitlements: Path?

    /// Target settings.
    public let settings: Settings?

    /// Target dependencies.
    public let dependencies: [TargetDependency]

    /// Relative paths to the sources directory.
    public let sources: SourceFilesList?

    /// Relative paths to the resources directory.
    public let resources: ResourceFileElements?

    /// Copy files actions.
    public let copyFiles: [CopyFilesAction]?

    /// Headers.
    public let headers: Headers?

    /// Target scripts.
    public let scripts: [TargetScript]

    /// CoreData models.
    public let coreDataModels: [CoreDataModel]

    /// Environment variables to be exposed to the target.
    public let environment: [String: String]

    /// Launch argument to be exposed to the target.
    public let launchArguments: [LaunchArgument]

    /// The additional files to include in the target (won't be included in a build phase)
    public let additionalFiles: [FileElement]

    public enum CodingKeys: String, CodingKey {
        case name
        case platform
        case product
        case productName = "product_name"
        case bundleId = "bundle_id"
        case infoPlist = "info_plist"
        case entitlements
        case settings
        case dependencies
        case sources
        case resources
        case copyFiles
        case headers
        case coreDataModels = "core_data_models"
        case scripts
        case environment
        case launchArguments
        case deploymentTarget
        case additionalFiles
    }

    /// Initializes the target.
    ///
    /// - Parameters:
    ///   - name: target name.
    ///   - platform: product platform.
    ///   - product: product type.
    ///   - bundleId: bundle identifier.
    ///   - infoPlist: relative path to the Info.plist file.
    ///   - sources: relative paths to the sources directory.
    ///   - resources: relative paths to the resources directory.
    ///   - copyFiles: copy files phases.
    ///   - headers: headers.
    ///   - entitlements: relative path to the entitlements file.
    ///   - scripts: target scripts.
    ///   - dependencies: target dependencies.
    ///   - settings: target settings.
    ///   - coreDataModels: CoreData models.
    ///   - environment: Environment variables to be exposed to the target.
    ///   - launchArguments: Launch arguments that are passwd to target.
    ///   - additionalFiles: The additional files to include in the target (won't be included in a build phase).
    public init(
        name: String,
        platform: Platform,
        product: Product,
        productName: String? = nil,
        bundleId: String,
        deploymentTarget: DeploymentTarget? = nil,
        infoPlist: InfoPlist = .default,
        sources: SourceFilesList? = nil,
        resources: ResourceFileElements? = nil,
        copyFiles: [CopyFilesAction]? = nil,
        headers: Headers? = nil,
        entitlements: Path? = nil,
        scripts: [TargetScript] = [],
        dependencies: [TargetDependency] = [],
        settings: Settings? = nil,
        coreDataModels: [CoreDataModel] = [],
        environment: [String: String] = [:],
        launchArguments: [LaunchArgument] = [],
        additionalFiles: [FileElement] = []
    ) {
        self.name = name
        self.platform = platform
        self.bundleId = bundleId
        self.productName = productName
        self.product = product
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.dependencies = dependencies
        self.settings = settings
        self.sources = sources
        self.resources = resources
        self.copyFiles = copyFiles
        self.headers = headers
        self.scripts = scripts
        self.coreDataModels = coreDataModels
        self.environment = environment
        self.launchArguments = launchArguments
        self.deploymentTarget = deploymentTarget
        self.additionalFiles = additionalFiles
    }
}
