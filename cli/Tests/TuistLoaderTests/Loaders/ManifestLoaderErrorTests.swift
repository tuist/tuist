import Foundation
import Path
import Testing
import TuistSupport

@testable import TuistLoader
@testable import TuistTesting

struct ManifestLoaderErrorTests {
    @Test func test_description() throws {
        #expect(
            ManifestLoaderError.projectDescriptionNotFound(try AbsolutePath(validating: "/test")).description ==
                "Couldn't find ProjectDescription.framework at path /test"
        )
        #expect(
            ManifestLoaderError.unexpectedOutput(try AbsolutePath(validating: "/test/")).description ==
                "Unexpected output trying to parse the manifest at path /test"
        )
        #expect(
            ManifestLoaderError.manifestNotFound(.project, try AbsolutePath(validating: "/test/")).description ==
                "Project.swift not found at path /test"
        )
        #expect(
            ManifestLoaderError.manifestNotFound(nil, try AbsolutePath(validating: "/test/")).description ==
                "Manifest not found at path /test"
        )
        #expect(
            ManifestLoaderError.manifestLoadingFailed(
                path: try AbsolutePath(validating: "/test/"),
                data: Data(),
                context: "Context"
            )
            .description ==
            """
            Unable to load manifest at \("/test".bold())
            Context
            """
        )
    }

    @Test func test_type() throws {
        #expect(ManifestLoaderError.projectDescriptionNotFound(try AbsolutePath(validating: "/test")).type == .bug)
        #expect(ManifestLoaderError.unexpectedOutput(try AbsolutePath(validating: "/test/")).type == .bug)
        #expect(ManifestLoaderError.manifestNotFound(.project, try AbsolutePath(validating: "/test/")).type == .abort)
        #expect(
            ManifestLoaderError.manifestLoadingFailed(
                path: try AbsolutePath(validating: "/test/"),
                data: Data(),
                context: "Context"
            ).type == .abort
        )
    }
}
