import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageGraphGeneratorTests: TuistUnitTestCase {
    private var subject: CarthageGraphGenerator!

    override func setUp() {
        super.setUp()

        subject = CarthageGraphGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate() throws {
        // Given
        let path = try temporaryPath()

        let rxSwiftVersionFilePath = path.appending(component: ".RxSwift.version")
        try fileHandler.touch(rxSwiftVersionFilePath)
        try fileHandler.write(CarthageVersionFile.testRxSwiftJson, path: rxSwiftVersionFilePath, atomically: true)

        let alamofireVersionFilePath = path.appending(component: ".Alamofire.version")
        try fileHandler.touch(alamofireVersionFilePath)
        try fileHandler.write(CarthageVersionFile.testAlamofireJson, path: alamofireVersionFilePath, atomically: true)

        // When
        let got = try subject.generate(at: path)

        // Then
        let expected = DependenciesGraph(
            externalDependencies: [
                .tvOS: [
                    "RxSwift": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxSwift.xcframework"))],
                    "RxCocoa": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxCocoa.xcframework"))],
                    "RxRelay": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxRelay.xcframework"))],
                    "RxTest": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxTest.xcframework"))],
                    "RxBlocking": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxBlocking.xcframework"))],
                    "Alamofire": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/Alamofire.xcframework"))],
                ],
                .macOS: [
                    "RxSwift": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxSwift.xcframework"))],
                    "RxCocoa": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxCocoa.xcframework"))],
                    "RxRelay": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxRelay.xcframework"))],
                    "RxTest": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxTest.xcframework"))],
                    "RxBlocking": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxBlocking.xcframework"))],
                    "Alamofire": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/Alamofire.xcframework"))],
                ],
                .watchOS: [
                    "RxSwift": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxSwift.xcframework"))],
                    "RxCocoa": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxCocoa.xcframework"))],
                    "RxRelay": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxRelay.xcframework"))],
                    "RxBlocking": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxBlocking.xcframework"))],
                    "Alamofire": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/Alamofire.xcframework"))],
                ],
                .iOS: [
                    "RxSwift": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxSwift.xcframework"))],
                    "RxCocoa": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxCocoa.xcframework"))],
                    "RxRelay": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxRelay.xcframework"))],
                    "RxTest": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxTest.xcframework"))],
                    "RxBlocking": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/RxBlocking.xcframework"))],
                    "Alamofire": [.xcframework(path: .relativeToManifest("Tuist/Dependencies/Carthage/Build/Alamofire.xcframework"))],
                ],
                .visionOS: [:],
            ],
            externalProjects: [:]
        )

        XCTAssertEqual(got, expected)
    }
}
