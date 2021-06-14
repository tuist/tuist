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
        let alamofirePath = checkoutsPath.appending(component: "Alamofire")
        let googleAppMeasurementPath = checkoutsPath.appending(component: "GoogleAppMeasurement")
        let testPath = checkoutsPath.appending(component: "test")

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
                XCTAssertEqual(path, alamofirePath.appending(component: "Package.swift"))
                return PackageInfo.alamofire
            case 2:
                XCTAssertEqual(path, googleAppMeasurementPath.appending(component: "Package.swift"))
                return PackageInfo.googleAppMeasurement
            case 3:
                XCTAssertEqual(path, testPath.appending(component: "Package.swift"))
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
                "Alamofire": PackageInfo.alamofireThirdPartyDependency(packageFolder: alamofirePath),
                "GoogleAppMeasurement": PackageInfo.googleAppMeasurementThirdPartyDependency(packageFolder: googleAppMeasurementPath),
                "test": PackageInfo.testThirdPartyDependency(packageFolder: testPath),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
