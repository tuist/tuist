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
                checkoutsPath.appending(component: "Alamofire"),
                checkoutsPath.appending(component: "GoogleAppMeasurement"),
                checkoutsPath.appending(component: "test"),
            ]
        }

        var loadPackageInfoCalls = 0
        swiftPackageManagerController.loadPackageInfoStub = { path in
            loadPackageInfoCalls += 1
            switch loadPackageInfoCalls {
            case 1:
                XCTAssertEqual(path, checkoutsPath.appending(component: "Alamofire").appending(component: "Package.swift"))
                return PackageInfo.alamofire
            case 2:
                XCTAssertEqual(path, checkoutsPath.appending(component: "GoogleAppMeasurement").appending(component: "Package.swift"))
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
                "Alamofire": PackageInfo.alamofireThirdPartyDependency,
                "GoogleAppMeasurement": PackageInfo.googleAppMeasurementThirdPartyDependency,
                "test": PackageInfo.testThirdPartyDependency,
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
