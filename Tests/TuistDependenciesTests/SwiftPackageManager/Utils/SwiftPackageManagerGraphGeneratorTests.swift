import TuistDependencies
import TuistGraph
import XCTest
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

class SwiftPackageManagerGraphGeneratorTests: TuistTestCase {
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var subject: SwiftPackageManagerGraphGenerator!

    override func setUp() {
        super.setUp()

        swiftPackageManagerController = MockSwiftPackageManagerController()
        subject = SwiftPackageManagerGraphGenerator(swiftPackageManagerController: swiftPackageManagerController)
    }

    override func tearDown() {
        super.tearDown()

        fileHandler = nil
        swiftPackageManagerController = nil
        subject = nil
    }

    func test_generate() throws {
        // Given
        let path = try temporaryPath()
        let checkoutsPath = path.appending(component: "checkouts")

        fileHandler.stubContentsOfDirectory = { path in
            XCTAssertEqual(path, checkoutsPath)
            return [
                checkoutsPath.appending(component: "alamofire"),
                checkoutsPath.appending(component: "google-app-measurement"),
                checkoutsPath.appending(component: "test"),
            ]
        }

        var loadPackageInfoCalls = 0
        swiftPackageManagerController.loadPackageInfoStub = { path in
            loadPackageInfoCalls += 1
            switch loadPackageInfoCalls {
            case 1:
                XCTAssertEqual(path, checkoutsPath.appending(component: "alamofire").appending(component: "Package.swift"))
                return PackageInfo.alamofire
            case 2:
                XCTAssertEqual(path, checkoutsPath.appending(component: "google-app-measurement").appending(component: "Package.swift"))
                return PackageInfo.googleAppMeasurement
            case 3:
                XCTAssertEqual(path, checkoutsPath.appending(component: "test").appending(component: "Package.swift"))
                return PackageInfo.test
            default:
                XCTFail("Unexpected function call")
                return .test
            }
        }

        // When
        let got = try subject.generate(at: path)

        // Then
        let expected = DependenciesGraph(
            thirdPartyDependencies: [
                "alamofire": .sources(
                    name: "alamofire",
                    products: [],
                    targets: [],
                    minDeploymentTargets: [
                        .iOS("10.0", .all),
                        .macOS("10.12"),
                        .tvOS("10.0"),
                        .watchOS("3.0"),
                    ]
                ),
                "google-app-measurement": .sources(
                    name: "google-app-measurement",
                    products: [],
                    targets: [],
                    minDeploymentTargets: [
                        .iOS("10.0", .all),
                    ]
                ),
                "test": .sources(
                    name: "test",
                    products: [],
                    targets: [],
                    minDeploymentTargets: [
                        .iOS("13.0", .all),
                        .macOS("10.15"),
                        .watchOS("6.0"),
                    ]
                ),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
