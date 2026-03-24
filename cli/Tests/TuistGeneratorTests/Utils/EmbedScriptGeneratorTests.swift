import Foundation
import Path
import Testing
import TuistCore
import TuistSupport

@testable import TuistGenerator
@testable import TuistTesting

struct EmbedScriptGeneratorTests {
    let subject: EmbedScriptGenerator
    init() {
        subject = EmbedScriptGenerator()
    }

    @Test
    func script_when_includingSymbolsInFileLists() throws {
        // Given
        let path = try AbsolutePath(validating: "/frameworks/tuist.framework")
        let dsymPath = try AbsolutePath(validating: "/frameworks/tuist.dSYM")
        let bcsymbolPath = try AbsolutePath(validating: "/frameworks/tuist.bcsymbolmap")
        let framework = GraphDependencyReference.testFramework(
            path: path,
            binaryPath: path.appending(component: "tuist"),
            dsymPath: dsymPath,
            bcsymbolmapPaths: [bcsymbolPath]
        )
        // When
        let got = try subject.script(
            sourceRootPath: framework.precompiledPath!.parentDirectory,
            frameworkReferences: [framework],
            includeSymbolsInFileLists: true
        )

        // Then
        #expect(got.inputPaths == [
            try RelativePath(validating: "tuist.framework"),
            try RelativePath(validating: "tuist.framework/tuist"),
            try RelativePath(validating: "tuist.framework/Info.plist"),
        ])
        #expect(got.outputPaths == [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        #expect(got.script.contains("install_framework \"$SRCROOT/\(path.basename)\""))
        #expect(got.script.contains("install_dsym \"$SRCROOT/\(dsymPath.basename)\""))
        #expect(got.script.contains("install_bcsymbolmap \"$SRCROOT/\(bcsymbolPath.basename)\""))
    }

    @Test
    func script_when_not_includingSymbolsInFileLists() throws {
        // Given
        let path = try AbsolutePath(validating: "/frameworks/tuist.framework")
        let dsymPath = try AbsolutePath(validating: "/frameworks/tuist.dSYM")
        let bcsymbolPath = try AbsolutePath(validating: "/frameworks/tuist.bcsymbolmap")
        let framework = GraphDependencyReference.testFramework(
            path: path,
            binaryPath: path.appending(component: "tuist"),
            dsymPath: dsymPath,
            bcsymbolmapPaths: [bcsymbolPath]
        )
        // When
        let got = try subject.script(
            sourceRootPath: framework.precompiledPath!.parentDirectory,
            frameworkReferences: [framework],
            includeSymbolsInFileLists: false
        )

        // Then
        #expect(got.inputPaths == [
            try RelativePath(validating: "tuist.framework"),
            try RelativePath(validating: "tuist.framework/tuist"),
            try RelativePath(validating: "tuist.framework/Info.plist"),
        ])
        #expect(got.outputPaths == [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        #expect(got.script.contains("install_framework \"$SRCROOT/\(path.basename)\""))
        #expect(got.script.contains("install_dsym \"$SRCROOT/\(dsymPath.basename)\""))
        #expect(got.script.contains("install_bcsymbolmap \"$SRCROOT/\(bcsymbolPath.basename)\""))
    }
}
