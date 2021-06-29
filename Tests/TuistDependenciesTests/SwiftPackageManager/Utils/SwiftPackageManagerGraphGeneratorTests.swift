import ProjectDescription
import TuistDependencies
import TuistGraph
import XCTest
@testable import TuistDependenciesTesting
@testable import TuistLoaderTesting
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
        let spmFolder = Path(path.pathString)
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

        fileHandler.stubIsFolder = { _ in
            // called to convert globs to AbsolutePath
            true
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
        let got = try subject.generate(
            at: path,
            productTypes: [
                "GULMethodSwizzler": .framework,
                "GULNetwork": .dynamicLibrary,
            ],
            platforms: [.iOS]
        )

        // Then
        let expected = try ProjectDescription.DependenciesGraph.none
            .merging(with: DependenciesGraph.alamofire(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.googleAppMeasurement(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.googleUtilities(
                spmFolder: spmFolder,
                customProductTypes: [
                    "GULMethodSwizzler": .framework,
                    "GULNetwork": .dynamicLibrary
                ]
            ))
            .merging(with: DependenciesGraph.nanopb(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.test(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder))

        XCTAssertEqual(got, expected)
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
