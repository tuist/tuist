import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class FrameworkLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_frameworkNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/frameworks/tuist.framework")
        let subject = FrameworkLoaderError.frameworkNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_frameworkNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/frameworks/tuist.framework")
        let subject = FrameworkLoaderError.frameworkNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Couldn't find framework at \(path.pathString)")
    }
}

final class FrameworkLoaderTests: TuistUnitTestCase {
    var frameworkMetadataProvider: MockFrameworkMetadataProvider!
    var subject: FrameworkLoader!

    override func setUp() {
        super.setUp()
        frameworkMetadataProvider = MockFrameworkMetadataProvider()
        subject = FrameworkLoader(frameworkMetadataProvider: frameworkMetadataProvider)
    }

    override func tearDown() {
        frameworkMetadataProvider = nil
        subject = nil
        super.tearDown()
    }

    func test_load_when_the_framework_doesnt_exist() throws {
        // Given
        let path = try temporaryPath()
        let frameworkPath = path.appending(component: "tuist.framework")

        // Then
        XCTAssertThrowsSpecific(try subject.load(path: frameworkPath), FrameworkLoaderError.frameworkNotFound(frameworkPath))
    }

    func test_load_when_the_framework_exists() throws {
        // Given
        let path = try temporaryPath()
        let binaryPath = path.appending(component: "tuist")
        let frameworkPath = path.appending(component: "tuist.framework")
        let dsymPath = path.appending(component: "tuist.dSYM")
        let bcsymbolmapPaths = [path.appending(component: "tuist.bcsymbolmap")]
        let architectures = [BinaryArchitecture.armv7s]
        let linking = BinaryLinking.dynamic

        try FileHandler.shared.touch(frameworkPath)

        frameworkMetadataProvider.loadMetadataStub = {
            FrameworkMetadata(
                path: $0,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                isCarthage: false
            )
        }

        // When
        let got = try subject.load(path: frameworkPath)

        // Then
        XCTAssertEqual(
            got,
            .framework(
                path: frameworkPath,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                isCarthage: false
            )
        )
    }
}
