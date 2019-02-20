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
                     settings: TargetSettings? = TargetSettings.test(),
                     sources: [AbsolutePath] = [AbsolutePath("/sources/*")],
                     resources: [AbsolutePath] = [AbsolutePath("/resources/*")],
                     coreDataModels: [CoreDataModel] = [],
                     headers: Headers? = nil,
                     actions: [TargetAction] = [],
                     environment: [String: String] = [:],
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
                      dependencies: dependencies)
    }
}
