import Foundation

public struct TargetContentHashSubhashes: Codable, Hashable, Sendable {
    public let sources: String?
    public let resources: String?
    public let copyFiles: String?
    public let coreDataModels: String?
    public let targetScripts: String?
    public let dependencies: String?
    public let environment: String?
    public let headers: String?
    public let deploymentTarget: String?
    public let infoPlist: String?
    public let entitlements: String?
    public let projectSettings: String
    public let targetSettings: String?
    public let buildableFolders: String?
    public let additionalStrings: [String]
    public let external: String?

    public init(
        sources: String? = nil,
        resources: String? = nil,
        copyFiles: String? = nil,
        coreDataModels: String? = nil,
        targetScripts: String? = nil,
        dependencies: String? = nil,
        environment: String? = nil,
        headers: String? = nil,
        deploymentTarget: String? = nil,
        infoPlist: String? = nil,
        entitlements: String? = nil,
        projectSettings: String,
        targetSettings: String? = nil,
        buildableFolders: String? = nil,
        additionalStrings: [String] = [],
        external: String? = nil
    ) {
        self.sources = sources
        self.resources = resources
        self.copyFiles = copyFiles
        self.coreDataModels = coreDataModels
        self.targetScripts = targetScripts
        self.dependencies = dependencies
        self.environment = environment
        self.headers = headers
        self.deploymentTarget = deploymentTarget
        self.infoPlist = infoPlist
        self.entitlements = entitlements
        self.projectSettings = projectSettings
        self.targetSettings = targetSettings
        self.buildableFolders = buildableFolders
        self.additionalStrings = additionalStrings
        self.external = external
    }
}

#if DEBUG
    extension TargetContentHashSubhashes {
        public static func test(
            sources: String? = nil,
            resources: String? = nil,
            copyFiles: String? = nil,
            coreDataModels: String? = nil,
            targetScripts: String? = nil,
            dependencies: String? = nil,
            environment: String? = nil,
            headers: String? = nil,
            deploymentTarget: String? = nil,
            infoPlist: String? = nil,
            entitlements: String? = nil,
            projectSettings: String = "test-project-settings",
            targetSettings: String? = nil,
            buildableFolders: String? = nil,
            additionalStrings: [String] = [],
            external: String? = nil
        ) -> TargetContentHashSubhashes {
            TargetContentHashSubhashes(
                sources: sources,
                resources: resources,
                copyFiles: copyFiles,
                coreDataModels: coreDataModels,
                targetScripts: targetScripts,
                dependencies: dependencies,
                environment: environment,
                headers: headers,
                deploymentTarget: deploymentTarget,
                infoPlist: infoPlist,
                entitlements: entitlements,
                projectSettings: projectSettings,
                targetSettings: targetSettings,
                buildableFolders: buildableFolders,
                additionalStrings: additionalStrings,
                external: external
            )
        }
    }
#endif
