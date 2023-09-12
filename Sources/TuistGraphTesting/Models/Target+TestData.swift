import Foundation
import TSCBasic
@testable import TuistGraph

extension Target {
    /// Creates a Target with test data
    /// Note: Referenced paths may not exist
    public static func test(
        name: String = "Target",
        destinations: Destinations = [.iPhone, .iPad],
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTargets: DeploymentTargets = .iOS("13.1"),
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = Settings.test(),
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environmentVariables: [String: EnvironmentVariable] = [:],
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
            destinations: destinations,
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTargets: deploymentTargets,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environmentVariables: environmentVariables,
            launchArguments: launchArguments,
            filesGroup: filesGroup,
            dependencies: dependencies,
            rawScriptBuildPhases: rawScriptBuildPhases,
            playgrounds: playgrounds,
            additionalFiles: additionalFiles,
            prune: prune
        )
    }

    /// Creates a Target with test data
    /// Note: Referenced paths may not exist
    //
    public static func test(
        name: String = "Target",
        platform: Platform,
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTarget: DeploymentTargets = .iOS("13.1"),
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = Settings.test(),
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environmentVariables: [String: EnvironmentVariable] = [:],
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
            destinations: destinationsFrom(platform),
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTargets: deploymentTarget,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environmentVariables: environmentVariables,
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
        destinations: Destinations = [.iPhone, .iPad],
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTargets: DeploymentTargets = .init(),
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = nil,
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environmentVariables: [String: EnvironmentVariable] = [:],
        filesGroup: ProjectGroup = .group(name: "Project"),
        dependencies: [TargetDependency] = [],
        rawScriptBuildPhases: [RawScriptBuildPhase] = []
    ) -> Target {
        Target(
            name: name,
            destinations: destinations,
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTargets: deploymentTargets,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environmentVariables: environmentVariables,
            filesGroup: filesGroup,
            dependencies: dependencies,
            rawScriptBuildPhases: rawScriptBuildPhases
        )
    }

    /// Creates a bare bones Target with as little data as possible
    //  @available(*, deprecated, renamed: "empty(name:destinations:...)", message: "Please use the `destinations:` factory method")
    public static func empty(
        name: String = "Target",
        platform: Platform,
        product: Product = .app,
        productName: String? = nil,
        bundleId: String? = nil,
        deploymentTargets: DeploymentTargets = .empty(),
        infoPlist: InfoPlist? = nil,
        entitlements: AbsolutePath? = nil,
        settings: Settings? = nil,
        sources: [SourceFile] = [],
        resources: [ResourceFileElement] = [],
        copyFiles: [CopyFilesAction] = [],
        coreDataModels: [CoreDataModel] = [],
        headers: Headers? = nil,
        scripts: [TargetScript] = [],
        environmentVariables: [String: EnvironmentVariable] = [:],
        filesGroup: ProjectGroup = .group(name: "Project"),
        dependencies: [TargetDependency] = [],
        rawScriptBuildPhases: [RawScriptBuildPhase] = []
    ) -> Target {
        Target(
            name: name,
            destinations: destinationsFrom(platform),
            product: product,
            productName: productName,
            bundleId: bundleId ?? "io.tuist.\(name)",
            deploymentTargets: deploymentTargets,
            infoPlist: infoPlist,
            entitlements: entitlements,
            settings: settings,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            coreDataModels: coreDataModels,
            scripts: scripts,
            environmentVariables: environmentVariables,
            filesGroup: filesGroup,
            dependencies: dependencies,
            rawScriptBuildPhases: rawScriptBuildPhases
        )
    }

    // Maps a platform to a set of Destinations.  For migration purposes
    private static func destinationsFrom(_ platform: Platform) -> Destinations {
        switch platform {
        case .iOS:
            return .iOS
        case .macOS:
            return .macOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        }
    }
}
