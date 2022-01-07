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

        system.stubs["/usr/bin/xcrun --sdk iphoneos --show-sdk-platform-path"] = (
            stderror: nil,
            stdout: "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform\n",
            exitstatus: 0
        )
        // swiftlint:disable line_length
        system
            .stubs[
                "/usr/bin/xcrun vtool -show-build /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework/XCTest"
            ] =
            (
                stderror: nil,
                stdout: """
                /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture armv7):
                Load command 8
                      cmd LC_VERSION_MIN_IPHONEOS
                  cmdsize 16
                  version 9.0
                      sdk 15.0
                /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture armv7s):
                Load command 8
                      cmd LC_VERSION_MIN_IPHONEOS
                  cmdsize 16
                  version 9.0
                      sdk 15.0
                /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture arm64):
                Load command 8
                      cmd LC_VERSION_MIN_IPHONEOS
                  cmdsize 16
                  version 9.0
                      sdk 15.0
                /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework/XCTest (architecture arm64e):
                Load command 9
                      cmd LC_BUILD_VERSION
                  cmdsize 32
                 platform IOS
                    minos 14.0
                      sdk 15.0
                   ntools 1
                     tool LD
                  version 711.0
                """,
                exitstatus: 0
            )
        // swiftlint:enable line_length

        subject = SwiftPackageManagerGraphGenerator(swiftPackageManagerController: swiftPackageManagerController)
    }

    override func tearDown() {
        swiftPackageManagerController = nil
        subject = nil
        super.tearDown()
    }

    func test_generate_alamofire() throws {
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
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
            dependenciesGraph: DependenciesGraph.alamofire(spmFolder: spmFolder)
        )
    }

    func test_generate_google_measurement() throws {
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/nanopb/Sources/nanopb"))
        try fileHandler
            .createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULAppDelegateSwizzler"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULNSData"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULMethodSwizzler"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/GoogleUtilities/Sources/GULNetwork"))

        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "GoogleAppMeasurement",
                  "path": "https://github.com/google/GoogleAppMeasurement"
                },
                "subpath": "GoogleAppMeasurement"
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "GoogleUtilities",
                  "path": "https://github.com/google/GoogleUtilities"
                },
                "subpath": "GoogleUtilities"
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "nanopb",
                  "path": "https://github.com/nanopb/nanopb"
                },
                "subpath": "nanopb"
              }
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
            dependenciesGraph: try DependenciesGraph.googleAppMeasurement(spmFolder: spmFolder)
                .merging(with: DependenciesGraph.googleUtilities(
                    spmFolder: spmFolder,
                    customProductTypes: [
                        "GULMethodSwizzler": .framework,
                        "GULNetwork": .dynamicLibrary,
                    ]
                ))
                .merging(with: DependenciesGraph.nanopb(spmFolder: spmFolder))
        )
    }

    func test_generate_test_local_path() throws {
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary"))

        let testPath = AbsolutePath("/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "local",
                  "name": "test",
                  "path": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
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
            dependenciesGraph: DependenciesGraph.test(spmFolder: spmFolder, packageFolder: Path(testPath.pathString))
                .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder))
                .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder))
        )
    }

    func test_generate_test_local_location() throws {
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibrary"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/ADependency/Sources/ALibraryUtils"))
        try fileHandler.createFolder(AbsolutePath("\(spmFolder.pathString)/checkouts/another-dependency/Sources/AnotherLibrary"))
        try fileHandler.createFolder(AbsolutePath("/tmp/localPackage/Sources/TuistKit"))

        let testPath = AbsolutePath("/tmp/localPackage")
        try checkGenerated(
            workspaceDependenciesJSON: """
            [
              {
                "packageRef": {
                  "kind": "local",
                  "name": "test",
                  "location": "\(testPath.pathString)"
                },
                "subpath": "test"
              },
              {
                "packageRef": {
                  "kind": "remote",
                  "name": "a-dependency"
                },
                "subpath": "ADependency"
              },
              {
                "packageRef": {
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
            dependenciesGraph: DependenciesGraph.test(spmFolder: spmFolder, packageFolder: Path(testPath.pathString))
                .merging(with: DependenciesGraph.aDependency(spmFolder: spmFolder))
                .merging(with: DependenciesGraph.anotherDependency(spmFolder: spmFolder))
        )
    }

    private func checkGenerated(
        workspaceDependenciesJSON: String,
        loadPackageInfoStub: @escaping (AbsolutePath) -> PackageInfo,
        dependenciesGraph: TuistCore.DependenciesGraph
    ) throws {
        // Given
        fileHandler.stubReadFile = {
            XCTAssertEqual($0, self.path.appending(component: "workspace-state.json"))
            return """
            {
              "object": {
                "dependencies": \(workspaceDependenciesJSON)
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
            swiftToolsVersion: nil
        )

        // Then
        XCTAssertEqual(got, dependenciesGraph)
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
