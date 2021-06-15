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
        let artifactsPath = path.appending(component: "artifacts")
        let checkoutsPath = path.appending(component: "checkouts")

        // Alamofire package and its dependencies
        let alamofirePath = checkoutsPath.appending(component: "Alamofire")

        // GoogleAppMeasurement package and its dependencies
        let googleAppMeasurementPath = checkoutsPath.appending(component: "GoogleAppMeasurement")
        let googleAppMeasurementArtifactsPath = artifactsPath.appending(component: "GoogleAppMeasurement")
        let googleUtilitiesPath = checkoutsPath.appending(component: "GoogleUtilities")
        let nanopbPath = checkoutsPath.appending(component: "nanopb")

        // Test package and its dependencies
        let testPath = checkoutsPath.appending(component: "test")
        let aDependencyPath = checkoutsPath.appending(component: "a-dependency")
        let anotherDependencyPath = checkoutsPath.appending(component: "another-dependency")

        fileHandler.stubContentsOfDirectory = { path in
            XCTAssertEqual(path, checkoutsPath)
            return [
                alamofirePath,
                googleAppMeasurementPath,
                googleUtilitiesPath,
                nanopbPath,
                testPath,
                aDependencyPath,
                anotherDependencyPath,
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
                XCTAssertEqual(path, googleUtilitiesPath.appending(component: "Package.swift"))
                return PackageInfo.googleUtilities
            case 4:
                XCTAssertEqual(path, nanopbPath.appending(component: "Package.swift"))
                return PackageInfo.nanopb
            case 5:
                XCTAssertEqual(path, testPath.appending(component: "Package.swift"))
                return PackageInfo.test
            case 6:
                XCTAssertEqual(path, aDependencyPath.appending(component: "Package.swift"))
                return PackageInfo.aDependency
            case 7:
                XCTAssertEqual(path, anotherDependencyPath.appending(component: "Package.swift"))
                return PackageInfo.anotherDependency
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
                "GoogleAppMeasurement": PackageInfo.googleAppMeasurementThirdPartyDependency(artifactsFolder: googleAppMeasurementArtifactsPath, packageFolder: googleAppMeasurementPath),
                "GoogleUtilities": PackageInfo.googleUtilitiesThirdPartyDependency(packageFolder: googleUtilitiesPath),
                "nanopb": PackageInfo.nanopbThirdPartyDependency(packageFolder: nanopbPath),
                "test": PackageInfo.testThirdPartyDependency(packageFolder: testPath),
                "a-dependency": PackageInfo.aDependencyThirdPartyDependency(packageFolder: aDependencyPath),
                "another-dependency": PackageInfo.anotherDependencyThirdPartyDependency(packageFolder: anotherDependencyPath),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
