import Foundation

// MARK: - Target

/// The target of a project
public struct Target: Codable, Equatable {
    /// The name of the target. The Xcode project target and the derivated product take the same name.
    public let name: String

    /// The platform the target product is built for.
    public let platform: Platform

    /// The type of build product this target will output.
    public let product: Product

    /// The built product name. If nil, it will be equal to `name`.
    public let productName: String?

    /// The product bundle identifier.
    public let bundleId: String

    /// The minimum deployment target your product will support.
    public let deploymentTarget: DeploymentTarget?

    /// Relative path to the Info.plist file.
    public let infoPlist: InfoPlist

    /// Source files that are compiled by the target. Any playgrounds matched by the globs used in this property will be automatically added.
    public let sources: SourceFilesList?

    /// List of files to include in the resources build phase. Note that localizable files, `*.lproj`, are supported.
    public let resources: ResourceFileElements?

    /// Copy files actions allow defining copy files build phases.
    public let copyFiles: [CopyFilesAction]?

    /// The target headers.
    public let headers: Headers?

    /// Relative path to the entitlements file.
    public let entitlements: Path?

    /// Target scripts allow defining extra script build phases.
    public let scripts: [TargetScript]

    /// Target dependencies.
    public let dependencies: [TargetDependency]

    /// Target settings.
    public let settings: Settings?

    /// CoreData models.
    public let coreDataModels: [CoreDataModel]

    /// List of variables that will be set to the scheme that Tuist automatically generates for the target.
    public let environment: [String: String]

    /// List of launch arguments that will be set to the scheme that Tuist automatically generates for the target.
    public let launchArguments: [LaunchArgument]

    /// List of target related files to include in the project - these won't be included in any of the build phases. For project related files, use the corresponding `Project.additionalFiles` parameter.
    public let additionalFiles: [FileElement]

    /// The target of a project
    /// - Parameters:
    ///   - name: The name of the target. The Xcode project target and the derivated product take the same name.
    ///   - platform: The platform the target product is built for.
    ///   - product: The type of build product this target will output.
    ///   - productName: The built product name. If nil, it will be equal to `name`.
    ///   - bundleId: The product bundle identifier.
    ///   - deploymentTarget: The minimum deployment target your product will support.
    ///   - infoPlist: Relative path to the Info.plist file.
    ///   - sources: Source files that are compiled by the target. Any playgrounds matched by the globs used in this property will be automatically added.
    ///   - resources: List of files to include in the resources build phase. Note that localizable files, `*.lproj`, are supported.
    ///   - copyFiles: Copy files actions allow defining copy files build phases.
    ///   - headers: The target headers.
    ///   - entitlements: Relative path to the entitlements file.
    ///   - scripts: Target scripts allow defining extra script build phases.
    ///   - dependencies: Target dependencies.
    ///   - settings: Target settings.
    ///   - coreDataModels: CoreData models.
    ///   - environment: List of variables that will be set to the scheme that Tuist automatically generates for the target.
    ///   - launchArguments: List of launch arguments that will be set to the scheme that Tuist automatically generates for the target.
    ///   - additionalFiles: List of target related files to include in the project - these won't be included in any of the build phases. For project related files, use the corresponding `Project.additionalFiles` parameter.
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
