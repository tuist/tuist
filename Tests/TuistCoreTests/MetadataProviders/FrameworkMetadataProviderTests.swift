import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class FrameworkMetadataProviderTests: XCTestCase {
    var subject: FrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = FrameworkMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loadMetadata() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("xpm.framework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath)

        // Then
        let expectedBinaryPath = frameworkPath.appending(component: frameworkPath.basenameWithoutExt)
        let expectedDsymPath = frameworkPath.parentDirectory.appending(component: "xpm.framework.dSYM")
        XCTAssertEqual(metadata, FrameworkMetadata(
            path: frameworkPath,
            binaryPath: expectedBinaryPath,
            dsymPath: expectedDsymPath,
            bcsymbolmapPaths: [],
            linking: .dynamic,
            architectures: [.x8664, .arm64],
            isCarthage: false
        ))
    }
}
