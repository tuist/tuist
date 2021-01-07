import Foundation
import TSCBasic
import TuistSupport
import XCTest
import TuistLoader
@testable import TuistCore
@testable import TuistSupportTesting

final class GraphLoaderIntegrationTests: TuistTestCase {
    var subject: GraphLoader!

    override func setUp() {
        super.setUp()
        subject = GraphLoader(
            modelLoader: GeneratorModelLoader(
                manifestLoader: ManifestLoader(),
                manifestLinter: ManifestLinter()
            ),
            frameworkNodeLoader: FrameworkNodeLoader(),
            xcframeworkNodeLoader: XCFrameworkNodeLoader(),
            libraryNodeLoader: LibraryNodeLoader(),
            otoolController: OtoolController()
        )
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
        let graph = try subject.loadDependencyGraph(for: [alamofireDependency], atPath: iOSBuildFolder)

        // Then
        XCTAssertTrue(graph.entryNodes.count == 1)

        let node = graph.entryNodes.first as! FrameworkNode
        XCTAssertTrue(node.name == "AlamofireImage")
        XCTAssertTrue(node.isCarthage)
        XCTAssertTrue(node.dependencies.first!.frameworkNode!.name == "Alamofire")
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
            try subject.loadDependencyGraph(for: [alamofireDependency], atPath: carthagePath),
            DependencyGraphLoadError.invalidCarthagePath(carthagePath)
        )
    }
}
