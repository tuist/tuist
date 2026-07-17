import Foundation
import Path
import Testing

@testable import TuistCore

@Suite
struct IndexStoreImporterTests {
    @Test func builds_remap_arguments_reversing_the_hermetic_tokens() throws {
        let arguments = IndexStoreImporter.arguments(
            indexImportPath: try AbsolutePath(validating: "/vendor/index-import"),
            store: try AbsolutePath(validating: "/cache/abc/IndexStore"),
            dataStore: try AbsolutePath(validating: "/dd/Index.noindex/DataStore"),
            sourceRoot: try AbsolutePath(validating: "/Users/dev/app"),
            derivedData: try AbsolutePath(validating: "/dd")
        )

        #expect(arguments == [
            "/vendor/index-import",
            "-remap", "\(CacheIndexStore.sourceRootToken)=/Users/dev/app",
            "-remap", "\(CacheIndexStore.buildRootToken)=/dd",
            "/cache/abc/IndexStore",
            "/dd/Index.noindex/DataStore",
        ])
    }
}
