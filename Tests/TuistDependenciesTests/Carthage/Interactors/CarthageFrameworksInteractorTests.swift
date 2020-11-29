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

    func test_save_all_platforms() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)

        try createFiles([
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

        // When
        try subject.copyFrameworks(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)

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

    func test_save_only_one_platform() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)

        try createFiles([
            "Temporary/Carthage/Build/iOS/Moya.framework/Info.plist",
            "Temporary/Carthage/Build/iOS/ReactiveMoya.framework/Info.plist",
            "Temporary/Carthage/Build/iOS/RxMoya.framework/Info.plist",
        ])

        // When
        try subject.copyFrameworks(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)

        // Then
        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "iOS", "Moya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "tvOS", "Moya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "macOS", "Moya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "Moya", "watchOS", "Moya.framework")))

        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "iOS", "ReactiveMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "tvOS", "ReactiveMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "macOS", "ReactiveMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "ReactiveMoya", "watchOS", "ReactiveMoya.framework")))

        XCTAssertTrue(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "iOS", "RxMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "tvOS", "RxMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "macOS", "RxMoya.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxMoya", "watchOS", "RxMoya.framework")))
    }

    func test_save_with_removing_unnecessary() throws {
        // Given
        let rootPath = try temporaryPath()
        let carthageBuildDirectory = rootPath.appending(components: "Temporary", "Carthage", "Build")
        let dependenciesDirectory = rootPath.appending(components: Constants.tuistDirectoryName, Constants.DependenciesDirectory.name)

        // stub carthage build directory
        try createFiles([
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

        // stub `Tuist/Dependencies` directory
        try createFiles([
            "Tuist/Dependencies/RxSwift/iOS/RxSwift.framework/Info.plist",
            "Tuist/Dependencies/RxSwift/macOS/RxSwift.framework/Info.plist",
            "Tuist/Dependencies/RxSwift/watchOS/RxSwift.framework/Info.plist",
            "Tuist/Dependencies/RxSwift/tvOS/RxSwift.framework/Info.plist",
        ])

        // stub `Tuist/Dependencies/graph.json`
        let graphPath = dependenciesDirectory.appending(component: Constants.DependenciesDirectory.graphName)
        let graphContent = """
        {
            "iOSDependencies": ["RxSwift"],
            "tvOSDependencies": ["RxSwift"],
            "macOSDependencies": ["RxSwift"],
            "watchOSDependencies": ["RxSwift"],
        }
        """
        try fileHandler.write(graphContent, path: graphPath, atomically: true)

        // When
        try subject.copyFrameworks(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)

        // Then

        // validate if frameworks were been copied
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

        // validate if unnecessary frameworks were been deleted
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxSwift", "iOS", "RxSwift.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxSwift", "tvOS", "RxSwift.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxSwift", "macOS", "RxSwift.framework")))
        XCTAssertFalse(fileHandler.exists(dependenciesDirectory.appending(components: "RxSwift", "watchOS", "RxSwift.framework")))

        // validate `Tuist/Dependencies/graph.json`
        let expectedGraph = Graph(
            iOSDependencies: ["ReactiveMoya", "RxMoya", "Moya"],
            tvOSDependencies: ["ReactiveMoya", "RxMoya", "Moya"],
            macOSDependencies: ["ReactiveMoya", "RxMoya", "Moya"],
            watchOSDependencies: ["ReactiveMoya", "RxMoya", "Moya"]
        )
        let grapData = try fileHandler.readFile(graphPath)
        let got = try JSONDecoder().decode(Graph.self, from: grapData)
        XCTAssertEqual(Set(got.iOSDependencies), Set(expectedGraph.iOSDependencies))
        XCTAssertEqual(Set(got.tvOSDependencies), Set(expectedGraph.tvOSDependencies))
        XCTAssertEqual(Set(got.macOSDependencies), Set(expectedGraph.macOSDependencies))
        XCTAssertEqual(Set(got.watchOSDependencies), Set(expectedGraph.watchOSDependencies))
    }
}
