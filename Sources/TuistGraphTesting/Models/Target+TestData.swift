import Foundation
import TSCBasic
@testable import TuistGraph

public extension Target {
    /// Creates a Target with test data
    /// Note: Referenced paths may not exist
    static func test(name: String = "Target",
                     platform: Platform = .iOS,
                     product: Product = .app,
                     productName: String? = nil,
                     bundleId: String? = nil,
                     deploymentTarget: DeploymentTarget? = .iOS("13.1", [.iphone, .ipad]),
                     infoPlist: InfoPlist? = nil,
                     entitlements: AbsolutePath? = nil,
                     settings: Settings? = Settings.test(),
                     sources: [SourceFile] = [],
                     resources: [FileElement] = [],
                     copyFiles: [CopyFilesAction] = [],
                     coreDataModels: [CoreDataModel] = [],
                     headers: Headers? = nil,
                     actions: [TargetAction] = [],
                     environment: [String: String] = [:],
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     dependencies: [Dependency] = [],
                     scripts: [TargetScript] = [],
                     launchArguments: [LaunchArgument] = [],
                     playgrounds: [AbsolutePath] = []) -> Target
    {
        Target(name: name,
               platform: platform,
               product: product,
               productName: productName,
               bundleId: bundleId ?? "com.test.bundle_id.\(Int.random(in: 1 ... 100_000))",
               deploymentTarget: deploymentTarget,
               infoPlist: infoPlist,
               entitlements: entitlements,
               settings: settings,
               sources: sources,
               resources: resources,
               copyFiles: copyFiles,
               headers: headers,
               coreDataModels: coreDataModels,
               actions: actions,
               environment: environment,
               launchArguments: launchArguments,
               filesGroup: filesGroup,
               dependencies: dependencies,
               scripts: scripts,
               playgrounds: playgrounds)
    }

    /// Creates a bare bones Target with as little data as possible
    static func empty(name: String = "Target",
                      platform: Platform = .iOS,
                      product: Product = .app,
                      productName: String? = nil,
                      bundleId: String? = nil,
                      deploymentTarget: DeploymentTarget? = nil,
                      infoPlist: InfoPlist? = nil,
                      entitlements: AbsolutePath? = nil,
                      settings: Settings? = nil,
                      sources: [SourceFile] = [],
                      resources: [FileElement] = [],
                      copyFiles: [CopyFilesAction] = [],
                      coreDataModels: [CoreDataModel] = [],
                      headers: Headers? = nil,
                      actions: [TargetAction] = [],
                      environment: [String: String] = [:],
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      dependencies: [Dependency] = [],
                      scripts: [TargetScript] = []) -> Target
    {
        Target(name: name,
               platform: platform,
               product: product,
               productName: productName,
               bundleId: bundleId ?? "com.test.bundle_id.\(Int.random(in: 1 ... 100_000))",
               deploymentTarget: deploymentTarget,
               infoPlist: infoPlist,
               entitlements: entitlements,
               settings: settings,
               sources: sources,
               resources: resources,
               copyFiles: copyFiles,
               headers: headers,
               coreDataModels: coreDataModels,
               actions: actions,
               environment: environment,
               filesGroup: filesGroup,
               dependencies: dependencies,
               scripts: scripts)
    }
}
