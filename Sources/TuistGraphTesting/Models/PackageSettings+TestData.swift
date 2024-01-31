import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

extension PackageSettings {
    public static func test(
        productTypes: [String: Product] = [:],
        baseSettings: Settings = .test(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: TuistGraph.Project.Options] = [:],
        swiftToolsVersion: Version = Version("5.4.9"),
        platforms: Set<PackagePlatform> = [.iOS]
    ) -> PackageSettings {
        PackageSettings(
            productTypes: productTypes,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            swiftToolsVersion: swiftToolsVersion,
            platforms: platforms
        )
    }
}
