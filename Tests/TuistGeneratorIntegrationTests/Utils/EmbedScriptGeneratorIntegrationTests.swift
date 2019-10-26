import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class EmbedScriptGeneratorIntegrationTests: TuistTestCase {
    var subject: EmbedScriptGenerator!

    override func setUp() {
        super.setUp()
        subject = EmbedScriptGenerator()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_script() throws {
        // Given
        let carthagePath = temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "*.framework").first!
        let framework = FrameworkNode(path: frameworkPath)

        // When
        let got = try subject.script(sourceRootPath: carthagePath, frameworkPaths: [framework.path])

        // Then
        XCTAssertTrue(got.inputPaths.contains(RelativePath("2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap")))
        XCTAssertTrue(got.inputPaths.contains(RelativePath("773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap")))
        XCTAssertTrue(got.inputPaths.contains(RelativePath("RxBlocking.framework")))
        XCTAssertTrue(got.inputPaths.contains(RelativePath("RxBlocking.framework.dSYM")))

        XCTAssertTrue(got.outputPaths.contains("${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/RxBlocking.framework"))
        XCTAssertTrue(got.outputPaths.contains("${DWARF_DSYM_FOLDER_PATH}/RxBlocking.framework.dSYM"))
        XCTAssertTrue(got.outputPaths.contains("${BUILT_PRODUCTS_DIR}/2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap"))
        XCTAssertTrue(got.outputPaths.contains("${BUILT_PRODUCTS_DIR}/773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap"))

        XCTAssertTrue(got.script.contains("install_framework \"RxBlocking.framework\""))
        XCTAssertTrue(got.script.contains("install_dsym \"RxBlocking.framework.dSYM\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap\""))
        XCTAssertTrue(got.script.contains("install_bcsymbolmap \"773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap\""))
    }

    fileprivate func temporaryFixture(_ pathString: String) -> AbsolutePath {
        let path = RelativePath(pathString)
        let fixturePath = self.fixturePath(path: path)
        let destinationPath = (try! temporaryPath()).appending(component: path.basename)
        try! FileHandler.shared.copy(from: fixturePath, to: destinationPath)
        return destinationPath
    }
}
