import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistSupportTesting

final class CarthageGraphLoaderIntegrationTests: TuistTestCase {
    var subject: CarthageGraphLoader!

    override func setUp() {
        super.setUp()
        subject = CarthageGraphLoader()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loading_AlamofireImage_loads_Alamofire() throws {
        // Given
        let carthagePath = try temporaryFixture("Carthage")
        let iOSBuildFolder = FileHandler.shared.glob(carthagePath, glob: "**/iOS").first!

        let alamofireDependency = CarthageDependency(
            name: "AlamofireImage",
            requirement: .exact("1.2.3"),
            platforms: [.iOS]
        )

        // When
        let graph = try subject.load(dependencies: [alamofireDependency], atPath: iOSBuildFolder)

        // Then
        XCTAssertTrue(graph.entryNodes.count == 1)
        XCTAssertTrue(graph.entryNodes.first!.name == "AlamofireImage")
        XCTAssertTrue(graph.entryNodes.first!.isCarthage)
        XCTAssertTrue(graph.entryNodes.first!.dependencies.first!.frameworkNode!.name == "Alamofire")
    }

    func test_loading_non_carthage_folder_fails() throws {
        // Given
        let carthagePath = try temporaryFixture("Carthage")

        let alamofireDependency = CarthageDependency(
            name: "AlamofireImage",
            requirement: .exact("1.2.3"),
            platforms: [.iOS]
        )

        // When/Then
        XCTAssertThrowsSpecific(
            try subject.load(dependencies: [alamofireDependency], atPath: carthagePath),
            CarthageGraphLoaderError.invalidPath(carthagePath)
        )
    }
}
