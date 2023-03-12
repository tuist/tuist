import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistGenerator
@testable import TuistSupportTesting

final class EmbedScriptGeneratorTests: TuistUnitTestCase {
    var subject: EmbedScriptGenerator!

    override func setUp() {
        super.setUp()
        subject = EmbedScriptGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_script_when_includingSymbolsInFileLists() throws {
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
        XCTAssertEqual(got.inputPaths, [
            RelativePath("tuist.framework"),
            RelativePath("tuist.framework/tuist"),
            RelativePath("tuist.framework/Info.plist"),
        ])
        XCTAssertEqual(got.outputPaths, [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        XCTAssertTrue(got.script.contains("install_framework \"$SRCROOT/\(path.basename)\""))
        XCTAssertTrue(got.script.contains("install_dsym \"$SRCROOT/\(dsymPath.basename)\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"$SRCROOT/\(bcsymbolPath.basename)\""))
    }

    func test_script_when_not_includingSymbolsInFileLists() throws {
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
        XCTAssertEqual(got.inputPaths, [
            RelativePath("tuist.framework"),
            RelativePath("tuist.framework/tuist"),
            RelativePath("tuist.framework/Info.plist"),
        ])
        XCTAssertEqual(got.outputPaths, [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        XCTAssertTrue(got.script.contains("install_framework \"$SRCROOT/\(path.basename)\""))
        XCTAssertTrue(got.script.contains("install_dsym \"$SRCROOT/\(dsymPath.basename)\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"$SRCROOT/\(bcsymbolPath.basename)\""))
    }
}
