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
