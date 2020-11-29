import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageFrameworksInteractorTests: TuistUnitTestCase {
    private var subject: CarthageFrameworksInteractor!

    override func setUp() {
        super.setUp()

        subject = CarthageFrameworksInteractor()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_save() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)

        try createFiles([
            "Temporary/Carthage/Build/.Moya.version",

            "Temporary/Carthage/Build/iOS/Moya.framework/Info.plist",
            "Temporary/Carthage/Build/iOS/ReactiveMoya.framework/Info.plist",
            "Temporary/Carthage/Build/iOS/RxMoya.framework/Info.plist",

            "Temporary/Carthage/Build/Mac/Moya.framework/Info.plist",
            "Temporary/Carthage/Build/Mac/ReactiveMoya.framework/Info.plist",
            "Temporary/Carthage/Build/Mac/RxMoya.framework/Info.plist",

            "Temporary/Carthage/Build/watchOS/Moya.framework/Info.plist",
            "Temporary/Carthage/Build/watchOS/ReactiveMoya.framework/Info.plist",
            "Temporary/Carthage/Build/watchOS/RxMoya.framework/Info.plist",

            "Temporary/Carthage/Build/tvOS/Moya.framework/Info.plist",
            "Temporary/Carthage/Build/tvOS/ReactiveMoya.framework/Info.plist",
            "Temporary/Carthage/Build/tvOS/RxMoya.framework/Info.plist",
        ])

        try fileHandler.write(
            """
            {
              "commitish" : "14.0.0",
              "iOS" : [
                {
                  "hash" : "dd80e93acb1cc0cfc8755ab35e57b1905518ab01237448ef547edf71445a2285",
                  "name" : "Moya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "cd6f9910471d467e5dcb8025d2080fae14c4b587d2a9e3c231c230092c8e551c",
                  "name" : "ReactiveMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "0991d553a79f46174f70c7d620773de6f9062046fb3584f80ba91362305c8e6e",
                  "name" : "RxMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                }
              ],
              "Mac" : [
                {
                  "hash" : "dd80e93acb1cc0cfc8755ab35e57b1905518ab01237448ef547edf71445a2285",
                  "name" : "Moya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "cd6f9910471d467e5dcb8025d2080fae14c4b587d2a9e3c231c230092c8e551c",
                  "name" : "ReactiveMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "0991d553a79f46174f70c7d620773de6f9062046fb3584f80ba91362305c8e6e",
                  "name" : "RxMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                }
              ],
              "watchOS" : [
                {
                  "hash" : "dd80e93acb1cc0cfc8755ab35e57b1905518ab01237448ef547edf71445a2285",
                  "name" : "Moya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "cd6f9910471d467e5dcb8025d2080fae14c4b587d2a9e3c231c230092c8e551c",
                  "name" : "ReactiveMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "0991d553a79f46174f70c7d620773de6f9062046fb3584f80ba91362305c8e6e",
                  "name" : "RxMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                }
              ],
              "tvOS" : [
                {
                  "hash" : "26ca97713f124c5f11233ee64403563bc963902136a90cfb7558398d913f0f4c",
                  "name" : "Moya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "6e12b5c40f36a38c1407b5039e308f651400ebb8589fef6358deaea3de7c0545",
                  "name" : "ReactiveMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                },
                {
                  "hash" : "b64e08356a8befa60eab8bd8dcefa7b1222b473480d673e6f8de7ccf2119de82",
                  "name" : "RxMoya",
                  "linking" : "dynamic",
                  "swiftToolchainVersion" : "5.3.1 (swiftlang-1200.0.41 clang-1200.0.32.8)"
                }
              ]
            }
            """,
            path: rootPath.appending(components: "Temporary", "Carthage", "Build", ".Moya.version"),
            atomically: true
        )

        // When
        try subject.copyFrameworks(carthageBuildDirectory: carthageBuildDirectory, destinationDirectory: dependenciesDirectory)

        // Then
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "iOS", "Moya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "tvOS", "Moya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "macOS", "Moya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "watchOS", "Moya.framework")))

        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "iOS", "ReactiveMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "tvOS", "ReactiveMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "macOS", "ReactiveMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "watchOS", "ReactiveMoya.framework")))

        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "iOS", "RxMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "tvOS", "RxMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "macOS", "RxMoya.framework")))
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "watchOS", "RxMoya.framework")))
    }
}
