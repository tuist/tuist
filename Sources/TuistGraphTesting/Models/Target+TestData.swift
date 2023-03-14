import Foundation
import TSCBasic
@testable import TuistGraph

extension Target {
    /// Creates a Target with test data
    /// Note: Referenced paths may not exist
    public static func test(
        name: String = "Target",
        platform: Platform = .iOS,
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTarget: DeploymentTarget? = .iOS("13.1", [.iphone, .ipad], supportsMacDesignedForIOS: true),
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = Settings.test(),
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environment: [String: String] = [:],
        filesGroup: ProjectGroup = .group(name: "Project"),
        dependencies: [TargetDependency] = [],
        rawScriptBuildPhases: [RawScriptBuildPhase] = [],
        launchArguments: [LaunchArgument] = [],
        playgrounds: [AbsolutePath] = [],
        additionalFiles: [FileElement] = [],
        prune: Bool = false
    ) -> Target {
        Target(
            name: name,
            platform: platform,
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environment: environment,
            launchArguments: launchArguments,
            filesGroup: filesGroup,
            dependencies: dependencies,
            rawScriptBuildPhases: rawScriptBuildPhases,
            playgrounds: playgrounds,
            additionalFiles: additionalFiles,
            prune: prune
        )
    }

    /// Creates a bare bones Target with as little data as possible
    public static func empty(
        name: String = "Target",
        platform: Platform = .iOS,
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTarget: DeploymentTarget? = nil,
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = nil,
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environment: [String: String] = [:],
        filesGroup: ProjectGroup = .group(name: "Project"),
        dependencies: [TargetDependency] = [],
        rawScriptBuildPhases: [RawScriptBuildPhase] = []
    ) -> Target {
        Target(
            name: name,
            platform: platform,
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environment: environment,
            filesGroup: filesGroup,
            dependencies: dependencies,
            rawScriptBuildPhases: rawScriptBuildPhases
        )
    }
}
