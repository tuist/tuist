import ProjectDescription
import TSCBasic
import TuistCore
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
        let testPath = AbsolutePath("/tmp/localPackage")
        let aDependencyPath = checkoutsPath.appending(component: "a-dependency")
        let anotherDependencyPath = checkoutsPath.appending(component: "another-dependency")

        fileHandler.stubReadFile = {
            XCTAssertEqual($0, path.appending(component: "workspace-state.json"))
            return """
            {
              "object": {
                "dependencies": [
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "Alamofire",
                      "path": "https://github.com/Alamofire/Alamofire"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "GoogleAppMeasurement",
                      "path": "https://github.com/google/GoogleAppMeasurement"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "GoogleUtilities",
                      "path": "https://github.com/google/GoogleUtilities"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "nanopb",
                      "path": "https://github.com/nanopb/nanopb"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "local",
                      "name": "test",
                      "path": "\(testPath.pathString)"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "a-dependency",
                      "path": "https://github.com/dependencies/a-dependency"
                    }
                  },
                  {
                    "packageRef": {
                      "kind": "remote",
                      "name": "another-dependency",
                      "path": "https://github.com/dependencies/another-dependency"
                    }
                  }
                ]
              }
            }
            """.data(using: .utf8)!
        }

        fileHandler.stubIsFolder = { _ in
            // called to convert globs to AbsolutePath
            true
        }

        fileHandler.stubSubpaths = { path in
            guard path == testPath.appending(component: "customPath").appending(component: "customPublicHeadersPath") else {
                return nil
            }

            return [
                AbsolutePath("/not/an/header.swift"),
                AbsolutePath("/an/header.h"),
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
        let got = try subject.generate(
            at: path,
            productTypes: [
                "GULMethodSwizzler": .framework,
                "GULNetwork": .dynamicLibrary,
            ],
            platforms: [.iOS]
        )

        // Then
        let expected = try TuistCore.DependenciesGraph.none
            .merging(with: DependenciesGraph.alamofire(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.googleAppMeasurement(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.googleUtilities(
                spmFolder: spmFolder,
                customProductTypes: [
                    "GULMethodSwizzler": .framework,
                    "GULNetwork": .dynamicLibrary,
                ]
            ))
            .merging(with: DependenciesGraph.nanopb(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.test(packageFolder: Path(testPath.pathString)))
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder))

        XCTAssertEqual(got, expected)
    }
}

extension TuistCore.DependenciesGraph {
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
