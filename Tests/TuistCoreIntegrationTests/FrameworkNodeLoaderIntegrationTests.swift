import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistSupportTesting

final class FrameworkNodeLoaderIntegrationTests: TuistTestCase {
    var subject: FrameworkNodeLoader!

    override func setUp() {
        super.setUp()
        subject = FrameworkNodeLoader(
            frameworkMetadataProvider: FrameworkMetadataProvider(),
            otoolController: OtoolController()
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loading_AlamofireImage_loads_Alamofire() throws {
        // Given
        let carthagePath = try temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "AlamofireImage.framework").first!

        // When
        let node = try subject.load(path: frameworkPath)

        // Then
        XCTAssertNotEmpty(node.dependencies)

        let rxSwiftDependency = node.dependencies
            .first(where: { $0.frameworkNode?.binaryPath.basename.contains("Alamofire") ?? false })
        XCTAssertNotNil(rxSwiftDependency)
    }

    func test_loading_RxBlocking_fails_RxSwift_not_found() throws {
        // Given
        let carthagePath = try temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "RxBlocking.framework").first!

        // Then
        XCTAssertThrowsError(
            // When
            try subject.load(path: frameworkPath)
        )
    }
}

private extension PrecompiledNode.Dependency {
    var frameworkNode: FrameworkNode? {
        switch self {
        case let .framework(node): return node
        case .xcframework: return nil
        }
    }
}
