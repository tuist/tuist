import Foundation

/// Contains individual component hashes that contribute to a target's overall content hash.
/// These subhashes allow for granular cache invalidation analysis by identifying which
/// specific component changed when a target's hash differs between builds.
public struct TargetContentHashSubhashes: Codable, Hashable, Sendable {
    /// Hash of the target's source files.
    public let sources: String?
    /// Hash of the target's resource files.
    public let resources: String?
    /// Hash of the target's copy files build phases.
    public let copyFiles: String?
    /// Hash of the target's Core Data model files.
    public let coreDataModels: String?
    /// Hash of the target's build scripts.
    public let targetScripts: String?
    /// Hash of the target's dependencies.
    public let dependencies: String?
    /// Hash of the target's environment variables.
    public let environment: String?
    /// Hash of the target's header files.
    public let headers: String?
    /// Hash of the target's deployment target configuration.
    public let deploymentTarget: String?
    /// Hash of the target's Info.plist file.
    public let infoPlist: String?
    /// Hash of the target's entitlements file.
    public let entitlements: String?
    /// Hash of the project-level build settings.
    public let projectSettings: String
    /// Hash of the target-level build settings.
    public let targetSettings: String?
    /// Hash of the target's buildable folders.
    public let buildableFolders: String?
    /// Additional strings included in the hash (e.g., xcodebuild arguments).
    public let additionalStrings: [String]
    /// Hash for external project targets (e.g., Swift packages).
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
