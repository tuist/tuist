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

        swiftPackageManagerController.loadPackageInfoStub = { path in
            switch path {
            case alamofirePath:
                return PackageInfo.alamofire
            case googleAppMeasurementPath:
                return PackageInfo.googleAppMeasurement
            case googleUtilitiesPath:
                return PackageInfo.googleUtilities
            case nanopbPath:
                return PackageInfo.nanopb
            case testPath:
                return PackageInfo.test
            case aDependencyPath:
                return PackageInfo.aDependency
            case anotherDependencyPath:
                return PackageInfo.anotherDependency
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
                "Alamofire": .alamofire(packageFolder: alamofirePath),
                "GoogleAppMeasurement": .googleAppMeasurement(artifactsFolder: googleAppMeasurementArtifactsPath, packageFolder: googleAppMeasurementPath),
                "GoogleUtilities": .googleUtilities(packageFolder: googleUtilitiesPath),
                "nanopb": .nanopb(packageFolder: nanopbPath),
                "test": .test(packageFolder: testPath),
                "a-dependency": .aDependency(packageFolder: aDependencyPath),
                "another-dependency": .anotherDependency(packageFolder: anotherDependencyPath),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
