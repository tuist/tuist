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
        super.tearDown()
        subject = nil
    }

    func test_script_when_includingSymbolsInFileLists() throws {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let dsymPath = AbsolutePath("/frameworks/tuist.dSYM")
        let bcsymbolPath = AbsolutePath("/frameworks/tuist.bcsymbolmap")
        let framework = GraphDependencyReference.testFramework(path: path,
                                                               binaryPath: path.appending(component: "tuist"),
                                                               dsymPath: dsymPath,
                                                               bcsymbolmapPaths: [bcsymbolPath])
        // When
        let got = try subject.script(sourceRootPath: framework.precompiledPath!.parentDirectory, frameworkReferences: [framework], includeSymbolsInFileLists: true)

        // Then
        XCTAssertEqual(got.inputPaths, [
            RelativePath(path.basename),
        ])
        XCTAssertEqual(got.outputPaths, [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        XCTAssertTrue(got.script.contains("install_framework \"\(path.basename)\""))
        XCTAssertTrue(got.script.contains("install_dsym \"\(dsymPath.basename)\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"\(bcsymbolPath.basename)\""))
    }

    func test_script_when_not_includingSymbolsInFileLists() throws {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let dsymPath = AbsolutePath("/frameworks/tuist.dSYM")
        let bcsymbolPath = AbsolutePath("/frameworks/tuist.bcsymbolmap")
        let framework = GraphDependencyReference.testFramework(path: path,
                                                               binaryPath: path.appending(component: "tuist"),
                                                               dsymPath: dsymPath,
                                                               bcsymbolmapPaths: [bcsymbolPath])
        // When
        let got = try subject.script(sourceRootPath: framework.precompiledPath!.parentDirectory, frameworkReferences: [framework], includeSymbolsInFileLists: false)

        // Then
        XCTAssertEqual(got.inputPaths, [
            RelativePath(path.basename),
        ])
        XCTAssertEqual(got.outputPaths, [
            "${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/\(path.basename)",
        ])

        XCTAssertTrue(got.script.contains("install_framework \"\(path.basename)\""))
        XCTAssertTrue(got.script.contains("install_dsym \"\(dsymPath.basename)\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"\(bcsymbolPath.basename)\""))
    }
}
