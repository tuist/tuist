import Foundation
import TSCBasic
import TSCUtility
@testable import XcodeProjectGenerator

extension PackageSettings {
    public static func test(
        productTypes: [String: Product] = [:],
        productDestinations: [String: Destinations] = [:],
        baseSettings: Settings = .test(),
        targetSettings: [String: SettingsDictionary] = [:],
        projectOptions: [String: XcodeProjectGenerator.Project.Options] = [:],
        swiftToolsVersion: Version = Version("5.4.9")
    ) -> PackageSettings {
        PackageSettings(
            productTypes: productTypes,
            productDestinations: productDestinations,
            baseSettings: baseSettings,
            targetSettings: targetSettings,
            projectOptions: projectOptions,
            swiftToolsVersion: swiftToolsVersion
        )
    }
}
