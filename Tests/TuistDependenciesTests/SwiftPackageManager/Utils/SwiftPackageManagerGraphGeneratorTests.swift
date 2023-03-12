import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistDependenciesTesting
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

class SwiftPackageManagerGraphGeneratorTests: TuistUnitTestCase {
    private var swiftPackageManagerController: MockSwiftPackageManagerController!
    private var subject: SwiftPackageManagerGraphGenerator!
    private var path: AbsolutePath { try! temporaryPath() }
    private var spmFolder: Path { Path(path.pathString) }
    private var checkoutsPath: AbsolutePath { path.appending(component: "checkouts") }

    override func setUp() {
        super.setUp()

        swiftPackageManagerController = MockSwiftPackageManagerController()
        system.swiftVersionStub = { "5.7.0" }
        subject = SwiftPackageManagerGraphGenerator(swiftPackageManagerController: swiftPackageManagerController)
    }

    override func tearDown() {
        swiftPackageManagerController = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_alamofire_spm_pre_v5_6() throws {
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "alamofire",
                  "kind": "remote",
                  "name": "Alamofire",
                  "path": "https://github.com/Alamofire/Alamofire"
                },
                "subpath": "Alamofire"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                XCTAssertEqual(packagePath, self.path.appending(component: "checkouts").appending(component: "Alamofire"))
                return PackageInfo.alamofire
            },
            dependenciesGraph: DependenciesGraph.alamofire(spmFolder: spmFolder, platforms: [.iOS])
        )
    }

    func test_generate_alamofire_spm_v5_6() throws {
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "alamofire",
                  "kind": "remoteSourceControl",
                  "name": "Alamofire",
                  "path": "https://github.com/Alamofire/Alamofire"
                },
                "subpath": "Alamofire"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                XCTAssertEqual(packagePath, self.path.appending(component: "checkouts").appending(component: "Alamofire"))
                return PackageInfo.alamofire
            },
            dependenciesGraph: DependenciesGraph.alamofire(spmFolder: spmFolder, platforms: [.iOS])
        )
    }

    func test_generate_google_measurement() throws {
        try fileHandler.createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/nanopb/Sources/nanopb"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULAppDelegateSwizzler")
            )
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULNSData"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULMethodSwizzler")
            )
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULNetwork"))

        // swiftformat:disable wrap
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "googleappmeasurement",
                  "kind": "remote",
                  "name": "GoogleAppMeasurement",
                  "path": "https://github.com/google/GoogleAppMeasurement"
                },
                "subpath": "GoogleAppMeasurement"
              },
              {
                "packageRef": {
                  "identity" : "googleutilities",
                  "kind": "remote",
                  "name": "GoogleUtilities",
                  "path": "https://github.com/google/GoogleUtilities"
                },
                "subpath": "GoogleUtilities"
              },
              {
                "packageRef": {
                  "identity" : "nanopb",
                  "kind": "remote",
                  "name": "nanopb",
                  "path": "https://github.com/nanopb/nanopb"
                },
                "subpath": "nanopb"
              }
            ]
            """,
            workspaceArtifactsJSON: """
            [
              {
                "packageRef" : {
                  "identity" : "googleappmeasurement",
                  "kind" : "remote",
                  "path" : "https://github.com/google/GoogleAppMeasurement",
                  "name" : "GoogleAppMeasurement"
                },
                "path" : "\(spmFolder.pathString)/artifacts/GoogleAppMeasurement/GoogleAppMeasurement.xcframework",
                "targetName" : "GoogleAppMeasurement"
              },
              {
                "packageRef" : {
                  "identity" : "googleappmeasurement",
                  "kind" : "remote",
                  "path" : "https://github.com/google/GoogleAppMeasurement",
                  "name" : "GoogleAppMeasurement"
                },
                "path" : "\(spmFolder.pathString)/artifacts/GoogleAppMeasurement/GoogleAppMeasurementWithoutAdIdSupport.xcframework",
                "targetName" : "GoogleAppMeasurementWithoutAdIdSupport"
              },
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case self.checkoutsPath.appending(component: "GoogleAppMeasurement"):
                    return PackageInfo.googleAppMeasurement
                case self.checkoutsPath.appending(component: "GoogleUtilities"):
                    return PackageInfo.googleUtilities
                case self.checkoutsPath.appending(component: "nanopb"):
                    return PackageInfo.nanopb
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: try DependenciesGraph.googleAppMeasurement(spmFolder: spmFolder, platforms: [.iOS])
                .merging(with: DependenciesGraph.googleUtilities(
                    spmFolder: spmFolder,
                    customProductTypes: [
                        "GULMethodSwizzler": .framework,
                        "GULNetwork": .dynamicLibrary,
                    ],
                    platforms: [.iOS]
                ))
                .merging(with: DependenciesGraph.nanopb(spmFolder: spmFolder, platforms: [.iOS]))
        )
        // swiftformat:enable wrap
    }

    func test_generate_test_local_path() throws {
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary")
            )
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TestUtilities"))

        let testPath = try AbsolutePath(validating: "/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "test",
                  "kind": "local",
                  "name": "test",
                  "path": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "identity" : "a-dependency",
                  "kind": "remote",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
                  "identity" : "another-dependency",
                  "kind": "remote",
                  "name": "another-dependency"
                },
                "subpath": "another-dependency"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case testPath:
                    return PackageInfo.test
                case self.checkoutsPath.appending(component: "ADependency"):
                    return PackageInfo.aDependency
                case self.checkoutsPath.appending(component: "another-dependency"):
                    return PackageInfo.anotherDependency
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: DependenciesGraph.test(
                spmFolder: spmFolder,
                packageFolder: Path(testPath.pathString),
                platforms: [.iOS],
                fileHandler: fileHandler
            )
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder, platforms: [.iOS]))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder, platforms: [.iOS]))
        )
    }

    func test_generate_test_local_location_spm_pre_v5_6() throws {
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary")
            )
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TestUtilities"))
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TuistKit"))

        let testPath = try AbsolutePath(validating: "/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "test",
                  "kind": "local",
                  "name": "test",
                  "location": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "identity" : "a-dependency",
                  "kind": "remote",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
                  "identity" : "another-dependency",
                  "kind": "remote",
                  "name": "another-dependency"
                },
                "subpath": "another-dependency"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case testPath:
                    return PackageInfo.test
                case self.checkoutsPath.appending(component: "ADependency"):
                    return PackageInfo.aDependency
                case self.checkoutsPath.appending(component: "another-dependency"):
                    return PackageInfo.anotherDependency
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: DependenciesGraph.test(
                spmFolder: spmFolder,
                packageFolder: Path(testPath.pathString),
                platforms: [.iOS],
                fileHandler: fileHandler
            )
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder, platforms: [.iOS]))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder, platforms: [.iOS]))
        )
    }

    func test_generate_test_fileSystem_location_spm_v5_6() throws {
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary")
            )
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TestUtilities"))
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TuistKit"))

        let testPath = try AbsolutePath(validating: "/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "test",
                  "kind": "fileSystem",
                  "name": "test",
                  "location": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "identity" : "a-dependency",
                  "kind": "remoteSourceControl",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
                  "identity": "another-dependency",
                  "kind": "remoteSourceControl",
                  "name": "another-dependency"
                },
                "subpath": "another-dependency"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case testPath:
                    return PackageInfo.test
                case self.checkoutsPath.appending(component: "ADependency"):
                    return PackageInfo.aDependency
                case self.checkoutsPath.appending(component: "another-dependency"):
                    return PackageInfo.anotherDependency
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: DependenciesGraph.test(
                spmFolder: spmFolder,
                packageFolder: Path(testPath.pathString),
                platforms: [.iOS],
                fileHandler: fileHandler
            )
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder, platforms: [.iOS]))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder, platforms: [.iOS]))
        )
    }

    func test_generate_test_localSourceControl_location_spm_v5_6() throws {
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler
            .createFolder(try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler
            .createFolder(
                try AbsolutePath(validating: "\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary")
            )
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TuistKit"))

        let testPath = try AbsolutePath(validating: "/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "identity" : "test",
                  "kind": "localSourceControl",
                  "name": "test",
                  "location": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "identity" : "a-dependency",
                  "kind": "remoteSourceControl",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
                  "identity": "another-dependency",
                  "kind": "remoteSourceControl",
                  "name": "another-dependency"
                },
                "subpath": "another-dependency"
              }
            ]
            """,
            loadPackageInfoStub: { packagePath in
                switch packagePath {
                case testPath:
                    return PackageInfo.test
                case self.checkoutsPath.appending(component: "ADependency"):
                    return PackageInfo.aDependency
                case self.checkoutsPath.appending(component: "another-dependency"):
                    return PackageInfo.anotherDependency
                default:
                    XCTFail("Unexpected path: \(self.path)")
                    return .test
                }
            },
            dependenciesGraph: DependenciesGraph.test(
                spmFolder: spmFolder,
                packageFolder: Path(testPath.pathString),
                platforms: [.iOS],
                fileHandler: fileHandler
            )
            .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder, platforms: [.iOS]))
            .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder, platforms: [.iOS]))
        )
    }

    private func checkGenerated(
        workspaceDependenciesJSON: String,
        workspaceArtifactsJSON: String = "[]",
        loadPackageInfoStub: @escaping (AbsolutePath) -> PackageInfo,
        dependenciesGraph: TuistCore.DependenciesGraph
    ) throws {
        // Given
        try fileHandler.createFolder(try AbsolutePath(validating: "/tmp/localPackage/Sources/TestUtilities"))
        fileHandler.stubReadFile = {
            XCTAssertEqual($0, self.path.appending(component: "workspace-state.json"))
            return """
            {
              "object": {
                "dependencies": \(workspaceDependenciesJSON),
                "artifacts": \(workspaceArtifactsJSON)
              }
            }
            """.data(using: .utf8)!
        }

        fileHandler.stubIsFolder = { _ in
            // called to convert globs to AbsolutePath
            true
        }

        swiftPackageManagerController.loadPackageInfoStub = loadPackageInfoStub

        // When
        let got = try subject.generate(
            at: path,
            productTypes: [
                "GULMethodSwizzler": .framework,
                "GULNetwork": .dynamicLibrary,
            ],
            platforms: [.iOS],
            baseSettings: .default,
            targetSettings: [:],
            swiftToolsVersion: nil,
            projectOptions: [:]
        )

        // Then
        XCTAssertEqual(got, dependenciesGraph)
    }
}

extension TuistCore.DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        var mergedExternalDependencies: [ProjectDescription.Platform: [String: [ProjectDescription.TargetDependency]]] =
            externalDependencies

        other.externalDependencies.forEach { platform, otherPlatformDependencies in
            otherPlatformDependencies.forEach { name, dependency in
                if let alreadyPresent = mergedExternalDependencies[platform]?[name] {
                    fatalError("Dupliacted Entry(\(name), \(alreadyPresent), \(dependency)")
                }
                mergedExternalDependencies[platform, default: [:]][name] = dependency
            }
        }

        let mergedExternalProjects = other.externalProjects.reduce(into: externalProjects) { result, entry in
            if let alreadyPresent = result[entry.key] {
                fatalError("Dupliacted Entry(\(entry.key), \(alreadyPresent), \(entry.value)")
            }
            result[entry.key] = entry.value
        }

        return .init(externalDependencies: mergedExternalDependencies, externalProjects: mergedExternalProjects)
    }
}
