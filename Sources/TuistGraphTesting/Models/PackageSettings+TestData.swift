import Foundation
import TSCBasic
@testable import TuistGraph

extension PackageSettings {
    public static func test(
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .test(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: TuistGraph.Project.Options] = [:],
        platforms: Set<PackagePlatform> = [.iOS]
    ) -> PackageSettings {
        PackageSettings(
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            platforms: platforms
        )
    }
}
