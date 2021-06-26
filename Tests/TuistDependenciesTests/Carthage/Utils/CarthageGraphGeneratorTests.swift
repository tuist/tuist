import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
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
        super.tearDown()

        subject = nil
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
            thirdPartyDependencies: [
                "RxSwift": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
                ),
                "RxCocoa": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxCocoa.xcframework"
                ),
                "RxRelay": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxRelay.xcframework"
                ),
                "RxTest": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxTest.xcframework"
                ),
                "RxBlocking": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxBlocking.xcframework"
                ),
                "Alamofire": .xcframework(
                    path: "/Tuist/Dependencies/Carthage/Alamofire.xcframework"
                ),
            ]
        )

        XCTAssertEqual(got, expected)
    }
}
