import Basic
import Foundation
import TuistCore
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class PrecompiledNodeIntegrationTests: TuistTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    func test_architectures() throws {
        // Given
        let frameworkPath = temporaryFixture("xpm.framework")
        let framework = FrameworkNode(path: frameworkPath)

        // When
        let got = try framework.architectures()

        // Then
        XCTAssertEqual(got.map(\.rawValue).sorted(), ["arm64", "x86_64"])
    }

    func test_uuids() throws {
        // Given
        let frameworkPath = temporaryFixture("xpm.framework")
        let framework = FrameworkNode(path: frameworkPath)

        // When
        let got = try framework.uuids()

        // Then
        let expected = Set([
            UUID(uuidString: "FB17107A-86FA-3880-92AC-C9AA9E04BA98"),
            UUID(uuidString: "510FD121-B669-3524-A748-2DDF357A051C"),
        ])
        XCTAssertEqual(got, expected)
    }

    func test_bcsymbolmapPaths() throws {
        // Given
        let carthagePath = temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "*.framework").first!
        let framework = FrameworkNode(path: frameworkPath)

        // When
        let got = try framework.bcsymbolmapPaths().sorted()

        // Then
        XCTAssertEqual(got.count, 2)
        XCTAssertTrue(got.first == carthagePath.appending(component: "2510FE01-4D40-3956-BB71-857D3B2D9E73.bcsymbolmap"))
        XCTAssertTrue(got.last == carthagePath.appending(component: "773847A9-0D05-35AF-9865-94A9A670080B.bcsymbolmap"))
    }

    func test_dsymPath() throws {
        // Given
        let carthagePath = temporaryFixture("Carthage/")
        let frameworkPath = FileHandler.shared.glob(carthagePath, glob: "*.framework").first!
        let framework = FrameworkNode(path: frameworkPath)

        // When
        let got = framework.dsymPath

        // Then
        XCTAssertTrue(got == carthagePath.appending(component: "\(frameworkPath.basename).dSYM"))
    }

    fileprivate func temporaryFixture(_ pathString: String) -> AbsolutePath {
        let path = RelativePath(pathString)
        let fixturePath = self.fixturePath(path: path)
        let destinationPath = (try! temporaryPath()).appending(component: path.basename)
        try! FileHandler.shared.copy(from: fixturePath, to: destinationPath)
        return destinationPath
    }
}
