import ProjectDescription
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

        // Alamofire package and its dependencies
        let alamofirePath = checkoutsPath.appending(component: "Alamofire")

        // GoogleAppMeasurement package and its dependencies
        let googleAppMeasurementPath = checkoutsPath.appending(component: "GoogleAppMeasurement")
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
        let got = try subject.generate(at: path, productTypes: [:], platforms: [.iOS])

        // Then
        let expected = try ProjectDescription.DependenciesGraph.none
            .merging(with: DependenciesGraph.alamofire(packageFolder: Path(alamofirePath.pathString)))
            .merging(with: DependenciesGraph.googleAppMeasurement(packageFolder: Path(googleAppMeasurementPath.pathString)))
            .merging(with: DependenciesGraph.googleUtilities(packageFolder: Path(googleUtilitiesPath.pathString)))
            .merging(with: DependenciesGraph.nanopb(packageFolder: Path(nanopbPath.pathString)))
            .merging(with: DependenciesGraph.test(packageFolder: Path(testPath.pathString)))
            .merging(with: DependenciesGraph.aDependency(packageFolder: Path(aDependencyPath.pathString)))
            .merging(with: DependenciesGraph.anotherDependency(packageFolder: Path(anotherDependencyPath.pathString)))

        XCTAssertEqual(got.externalDependencies, expected.externalDependencies)

        // TODO: check generated projects
    }
}

extension ProjectDescription.DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        let mergedExternalDependencies = other.externalDependencies.reduce(into: externalDependencies) { result, entry in
            result[entry.key] = entry.value
        }
        let mergedExternalProjects = other.externalProjects.reduce(into: externalProjects) { result, entry in
            result[entry.key] = entry.value
        }
        return .init(externalDependencies: mergedExternalDependencies, externalProjects: mergedExternalProjects)
    }
}
