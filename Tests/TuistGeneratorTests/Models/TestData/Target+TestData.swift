import Basic
import Foundation
@testable import TuistGenerator

extension Target {
    /// Creates a Target with test data
    /// Note: Referenced paths may not exist
    static func test(name: String = "Target",
                     platform: Platform = .iOS,
                     product: Product = .app,
                     bundleId: String = "com.test.bundle_id",
                     infoPlist: InfoPlist? = .file(path: AbsolutePath("/Info.plist")),
                     entitlements: AbsolutePath? = AbsolutePath("/Test.entitlements"),
                     settings: Settings? = Settings.test(),
                     sources: [Target.SourceFile] = [],
                     resources: [FileElement] = [],
                     coreDataModels: [CoreDataModel] = [],
                     headers: Headers? = nil,
                     actions: [TargetAction] = [],
                     environment: [String: String] = [:],
                     filesGroup: ProjectGroup = .group(name: "Project"),
                     dependencies: [Dependency] = []) -> Target {
        return Target(name: name,
                      platform: [ platform ],
                      product: product,
                      bundleId: bundleId,
                      infoPlist: infoPlist,
                      entitlements: entitlements,
                      settings: settings,
                      sources: sources,
                      resources: resources,
                      headers: headers,
                      coreDataModels: coreDataModels,
                      actions: actions,
                      environment: environment,
                      filesGroup: filesGroup,
                      dependencies: dependencies)
    }
    
    /// Creates a bare bones Target with as little data as possible
    static func empty(name: String = "Target",
                      platform: Platform = .iOS,
                      product: Product = .app,
                      bundleId: String = "com.test.bundleId",
                      infoPlist: InfoPlist? = nil,
                      entitlements: AbsolutePath? = nil,
                      settings: Settings? = nil,
                      sources: [Target.SourceFile] = [],
                      resources: [FileElement] = [],
                      coreDataModels: [CoreDataModel] = [],
                      headers: Headers? = nil,
                      actions: [TargetAction] = [],
                      environment: [String: String] = [:],
                      filesGroup: ProjectGroup = .group(name: "Project"),
                      dependencies: [Dependency] = []) -> Target {
        return Target(name: name,
                      platform: [platform],
                      product: product,
                      bundleId: bundleId,
                      infoPlist: infoPlist,
                      entitlements: entitlements,
                      settings: settings,
                      sources: sources,
                      resources: resources,
                      headers: headers,
                      coreDataModels: coreDataModels,
                      actions: actions,
                      environment: environment,
                      filesGroup: filesGroup,
                      dependencies: dependencies)
    }
    
}
