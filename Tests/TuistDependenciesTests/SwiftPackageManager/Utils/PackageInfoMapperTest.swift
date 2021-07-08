import ProjectDescription
import TuistCore
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class PackageInfoMapperTests: TuistUnitTestCase {
    private var subject: PackageInfoMapper!

    override func setUp() {
        super.setUp()

        subject = PackageInfoMapper()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func testMap() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1")
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(name: "Target1")
                ]
            )
        )
    }

    func testMap_whenTargetIsNotRegular_ignoresTarget() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2", "Target3"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2", type: .test),
                    .test(name: "Target3", type: .binary),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(name: "Target1")
                ]
            )
        )
    }

    func testMap_whenProductIsNotLibrary_ignoresProduct() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    .init(name: "Product2", type: .plugin, targets: ["Target2"]),
                    .init(name: "Product3", type: .test, targets: ["Target3"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2"),
                    .test(name: "Target3"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(name: "Target1")
                ]
            )
        )
    }

    func testMap_whenCustomSources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1", sources: ["Subfolder", "Another/Subfolder/file.swift"]),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        name: "Target1",
                        customSources: [
                            "/Package/Path/Sources/Target1/Subfolder/**",
                            "/Package/Path/Sources/Target1/Another/Subfolder/file.swift",
                        ]
                    )
                ]
            )
        )
    }

    func testMap_whenHasResources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        resources: [
                            .init(rule: .copy, path: "Resource/Folder"),
                            .init(rule: .process, path: "Another/Resource/Folder"),
                        ]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        name: "Target1",
                        customResources: [
                            "/Package/Path/Sources/Target1/Resource/Folder/**",
                            "/Package/Path/Sources/Target1/Another/Resource/Folder/**",
                        ]
                    )
                ]
            )
        )
    }

    func testMap_whenCustomPath() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        path: "Custom/Path",
                        sources: ["Sources/Folder"],
                        resources: [.init(rule: .copy, path: "Resource/Folder")]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        name: "Target1",
                        customSources: "/Package/Path/Custom/Path/Sources/Folder/**",
                        customResources: "/Package/Path/Custom/Path/Resource/Folder/**"
                    )
                ]
            )
        )
    }
}

extension PackageInfoMapping {
    fileprivate func map(packageInfo: PackageInfo) throws -> ProjectDescription.Project {
        return try self.map(
            packageInfo: packageInfo,
            packageInfos: [:],
            name: "Package",
            path: "/Package/Path",
            productTypes: [:],
            platforms: [.iOS],
            deploymentTargets: [],
            packageToProject: [:],
            productToPackage: [:],
            targetDependencyToFramework: [:]
        )
    }
}

extension PackageInfo.Target {
    fileprivate static func test(
        name: String,
        type: PackageInfo.Target.TargetType = .regular,
        path: String? = nil,
        sources: [String]? = nil,
        resources: [PackageInfo.Target.Resource] = []
    ) -> Self {
        return .init(
            name: name,
            path: path,
            url: nil,
            sources: sources,
            resources: resources,
            exclude: [],
            dependencies: [],
            publicHeadersPath: nil,
            type: type,
            settings: [],
            checksum: nil
        )
    }
}

extension ProjectDescription.Project {
    fileprivate static func test(name: String, targets: [ProjectDescription.Target]) -> Self {
        return .init(
            name: "Package",
            targets: targets,
            resourceSynthesizers: []
        )
    }
}

extension ProjectDescription.Target {
    fileprivate static func test(
        name: String,
        customSources: SourceFilesList? = nil,
        customResources: ResourceFileElements? = nil
    ) -> Self {
        return .init(
            name: name,
            platform: .iOS,
            product: .staticFramework,
            bundleId: name,
            infoPlist: .default,
            sources: customSources ?? "/Package/Path/Sources/\(name)/**",
            resources: customResources,
            settings: DependenciesGraph.spmSettings()
        )
    }
}
