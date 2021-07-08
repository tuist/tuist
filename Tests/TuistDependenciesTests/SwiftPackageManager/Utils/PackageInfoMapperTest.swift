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
    fileprivate static func test(name: String) -> Self {
        return .init(
            name: name,
            path: nil,
            url: nil,
            sources: nil,
            resources: [],
            exclude: [],
            dependencies: [],
            publicHeadersPath: nil,
            type: .regular,
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
    fileprivate static func test(name: String) -> Self {
        return .init(
            name: name,
            platform: .iOS,
            product: .staticFramework,
            bundleId: name,
            infoPlist: .default,
            sources: "/Package/Path/Sources/\(name)/**",
            settings: DependenciesGraph.spmSettings()
        )
    }
}
