import Foundation
import TSCUtility
import XCTest

@testable import TuistSupport

final class PackageInfoTests: XCTestCase {
    func test_packageInfo_codable() {
        XCTAssertCodable(
            PackageInfo(
                products: [
                    PackageInfo.Product(name: "tuist", type: .executable, targets: ["tuist"]),
                    PackageInfo.Product(name: "tuist", type: .library(.dynamic), targets: ["ProjectDescription"]),
                ],
                targets: [
                    PackageInfo.Target(
                        name: "tuist",
                        path: nil,
                        url: nil,
                        sources: nil,
                        resources: [],
                        exclude: [],
                        dependencies: [
                            .target(name: "TuistKit", condition: nil),
                            .byName(name: "TuistSupport", condition: nil),
                            .product(
                                name: "ArgumentParser",
                                package: "argument-parser",
                                moduleAliases: ["TuistSupport": "InternalTuistSupport"],
                                condition: nil
                            ),
                            .product(
                                name: "ArgumentParser",
                                package: "argument-parser",
                                moduleAliases: nil,
                                condition: PackageInfo.PackageConditionDescription(platformNames: ["macOS"], config: nil)
                            ),
                        ],
                        publicHeadersPath: nil,
                        type: .executable,
                        settings: [
                            PackageInfo.Target.TargetBuildSettingDescription.Setting(
                                tool: .linker,
                                name: .linkedLibrary,
                                condition: PackageInfo.PackageConditionDescription(platformNames: ["iOS"], config: nil),
                                value: ["ProjectDescription"]
                            ),
                        ],
                        checksum: nil
                    ),
                ],
                platforms: [
                    PackageInfo.Platform(platformName: "iOS", version: "17.2", options: []),
                ],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: [Version(stringLiteral: "5.4.9")]
            )
        )
    }
}
