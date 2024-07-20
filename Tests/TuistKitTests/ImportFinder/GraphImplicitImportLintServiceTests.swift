import Path
import TuistCore
import TuistLoader
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class GraphImplicitImportLintServiceTests: TuistUnitTestCase {
    override func setUp() {
        super.setUp()

        system.succeedCommand(["/usr/bin/xcrun", "swift", "-version"], output: "Swift Version 5.2.1")
    }

    func test_TargetWithImports() async throws {
        let path = fixtureFolderPath(path: try RelativePath(validating: "ios_app_with_framework_and_disabled_resources"))
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let (graph, _, _) = try await manifestGraphLoader.load(path: path)
        try await GraphImplicitImportLintService(graph: graph).lint()
    }
}

extension GraphImplicitImportLintServiceTests {
    public func fixtureFolderPath(path: RelativePath) -> AbsolutePath {
        try! AbsolutePath(validating: #file) // swiftlint:disable:this force_try
            .appending(try! RelativePath(validating: "../../../../fixtures/")) // swiftlint:disable:this force_try
            .appending(path)
    }
}
