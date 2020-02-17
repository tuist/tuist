import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class CoreDataModeltManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try FileHandler.shared.touch(temporaryPath.appending(component: "model.xcdatamodeld"))
        let manifest = ProjectDescription.CoreDataModel("model.xcdatamodeld",
                                                        currentVersion: "1")

        // When
        let model = try TuistCore.CoreDataModel.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertTrue(try coreDataModel(model, matches: manifest, at: temporaryPath, generatorPaths: generatorPaths))
    }
}
