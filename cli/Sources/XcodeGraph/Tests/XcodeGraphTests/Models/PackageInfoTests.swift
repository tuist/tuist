import Foundation
import Testing
@testable import XcodeGraph

struct PackageInfoTests {
    @Test
    func resourceRule_decodesEmbedInCode() throws {
        // Given - JSON format produced by `swift package dump-package` for .embedInCode rule
        let json = """
        {
            "path": "Resources",
            "rule": {
                "embedInCode": {}
            }
        }
        """.data(using: .utf8)!

        // When / Then
        let resource = try JSONDecoder().decode(PackageInfo.Target.Resource.self, from: json)
        #expect(resource.rule == .embedInCode)
        #expect(resource.path == "Resources")
    }

    @Test
    func packageInfo_codable() throws {
        // Given
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let subject = PackageInfo(
            name: "tuist",
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
            traits: [
                PackageTrait(
                    enabledTraits: ["Tuist"],
                    name: "Tuist",
                    description: "This is the default Tuist trait"
                ),
            ],
            dependencies: [],
            platforms: [
                PackageInfo.Platform(platformName: "iOS", version: "17.2", options: []),
            ],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: [Version(stringLiteral: "5.4.9")],
            toolsVersion: Version(5, 4, 9)
        )

        // When
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(PackageInfo.self, from: data)

        // Then
        #expect(subject == decoded)
    }
}
