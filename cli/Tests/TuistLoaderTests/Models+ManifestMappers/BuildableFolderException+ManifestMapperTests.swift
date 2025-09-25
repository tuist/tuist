import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistLoader
@testable import TuistTesting

struct BuildableFolderExceptionManifestMapperTests {
    @Test func test_from() throws {
        let buildableFolder = try AbsolutePath(validating: "/buildable-folder")

        let got = try XcodeGraph.BuildableFolderException.from(
            manifest: ProjectDescription.BuildableFolderException
                .exception(
                    excluded: ["Excluded.swift"],
                    compilerFlags: ["WithFlags.swift": "-flag"],
                    publicHeaders: ["Public.h"],
                    privateHeaders: ["Private.h"]
                ),
            buildableFolder: buildableFolder
        )

        #expect(got.excluded == [buildableFolder.appending(components: ["Excluded.swift"])])
        #expect(got.compilerFlags == [buildableFolder.appending(components: ["WithFlags.swift"]): "-flag"])
        #expect(got.publicHeaders == [buildableFolder.appending(components: ["Public.h"])])
        #expect(got.privateHeaders == [buildableFolder.appending(components: ["Private.h"])])
    }
}
