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
        fileHandler = nil
        swiftPackageManagerController = nil
        subject = nil
        super.tearDown()
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
            ]
        }

        swiftPackageManagerController.loadPackageInfoStub = { path in
            switch path {
            case checkoutsPath.appending(component: "alamofire").appending(component: "Package.swift"):
                return PackageInfo.alamofire
            case checkoutsPath.appending(component: "google-app-measurement").appending(component: "Package.swift"):
                return PackageInfo.googleAppMeasurement
            default:
                XCTFail("Unexpected path: \(path)")
                return .test
            }
        }

        // When
        let got = try subject.generate(at: path)

        // Then
        let expected = DependenciesGraph(
            thirdPartyDependencies: [
                "alamofire": .xcframework(
                    name: "alamofire",
                    path: .root,
                    architectures: []
                ),
                "google-app-measurement": .xcframework(
                    name: "google-app-measurement",
                    path: .root,
                    architectures: []
                ),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
