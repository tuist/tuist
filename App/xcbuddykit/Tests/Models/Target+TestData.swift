import Basic
import Foundation
@testable import xcbuddykit

extension Target {
    static func test(name: String = "Target",
                     platform: Platform = .ios,
                     product: Product = .app,
                     bundleId: String = "com.test.bundle_id",
                     infoPlist: AbsolutePath = AbsolutePath("/Info.plist"),
                     entitlements: AbsolutePath? = AbsolutePath("/Test.entitlements"),
                     settings: Settings? = Settings.test(),
                     buildPhases: [BuildPhase] = [
                         SourcesBuildPhase.test(),
                         ResourcesBuildPhase.test(),
                         HeadersBuildPhase.test(),
                         ScriptBuildPhase.test(),
                         CopyBuildPhase.test(),
                     ],
                     dependencies: [JSON] = []) -> Target {
        return Target(name: name,
                      platform: platform,
                      product: product,
                      bundleId: bundleId,
                      infoPlist: infoPlist,
                      entitlements: entitlements,
                      settings: settings,
                      buildPhases: buildPhases,
                      dependencies: dependencies)
    }
}
