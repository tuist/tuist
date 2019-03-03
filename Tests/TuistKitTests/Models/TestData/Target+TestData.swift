import Basic
import Foundation
@testable import TuistKit

extension Target {
    static func test(name: String = "Target",
                     platform: Platform = .iOS,
                     product: Product = .app,
                     bundleId: String = "com.test.bundle_id",
                     infoPlist: AbsolutePath = AbsolutePath("/Info.plist"),
                     entitlements: AbsolutePath? = AbsolutePath("/Test.entitlements"),
                     settings: Settings? = Settings.test(),
                     sources: [AbsolutePath] = [],
                     resources: [AbsolutePath] = [],
                     coreDataModels: [CoreDataModel] = [],
                     headers: Headers? = nil,
                     actions: [TargetAction] = [],
                     environment: [String: String] = [:],
                     projectStructure: ProjectStructure = .default,
                     dependencies: [Dependency] = []) -> Target {
        return Target(name: name,
                      platform: platform,
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
                      projectStructure: projectStructure,
                      dependencies: dependencies)
    }
}
