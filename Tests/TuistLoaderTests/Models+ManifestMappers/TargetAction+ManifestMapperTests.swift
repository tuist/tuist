import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class TargetActionManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        let manifest = ProjectDescription.TargetAction.test(name: "MyScript",
                                                            tool: "my_tool",
                                                            order: .pre,
                                                            arguments: ["arg1", "arg2"])
        // When
        let model = try TuistGraph.TargetAction.from(manifest: manifest, generatorPaths: generatorPaths)

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.script, .tool("my_tool", ["arg1", "arg2"]))
        XCTAssertEqual(model.order, .pre)
    }
}
