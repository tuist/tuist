import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupport
@testable import TuistSupportTesting

final class GraphTests: TuistUnitTestCase {
    func test_encode() {
        // Given
        System.shared = System()
        let project = Project.test()
        let framework = FrameworkNode.test(path: fixturePath(path: RelativePath("xpm.framework")), architectures: [.x8664, .arm64])
        let library = LibraryNode.test(
            path: fixturePath(path: RelativePath("libStaticLibrary.a")),
            publicHeaders: fixturePath(path: RelativePath(""))
        )
        let target = TargetNode.test(dependencies: [framework, library])

        let graph = Graph.test(
            projects: [project],
            precompiled: [framework, library],
            targets: [project.path: [target]]
        )

        let expected = """
        [
        {
            "product" : "\(target.target.product.rawValue)",
            "bundle_id" : "\(target.target.bundleId)",
            "platform" : "\(target.target.platform.rawValue)",
            "path" : "\(target.path)",
            "dependencies" : [
                "xpm",
                "libStaticLibrary"
            ],
            "name" : "Target",
            "type" : "source"
        },
        {
            "path" : "\(library.path)",
            "architectures" : [
                "arm64"
            ],
            "product" : "static_library",
            "name" : "\(library.name)",
            "type" : "precompiled"
        },
            {
                "path" : "\(framework.path)",
                "architectures" : [
                    "x86_64",
                    "arm64"
                ],
                "product" : "framework",
                "name" : "\(framework.name)",
                "type" : "precompiled"
            }
        ]
        """

        // Then
        XCTAssertEncodableEqualToJson(graph, expected)
    }
}
