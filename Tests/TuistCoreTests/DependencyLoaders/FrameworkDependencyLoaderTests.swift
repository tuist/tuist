import TSCBasic
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class FrameworkDependencyLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_frameworkNotFound() {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let subject = FrameworkDependencyLoaderError.frameworkNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_frameworkNotFound() {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let subject = FrameworkDependencyLoaderError.frameworkNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Couldn't find framework at \(path.pathString).")
    }
}

final class FrameworkDependencyLoaderTests: TuistUnitTestCase {
    var frameworkMetadataProvider: MockFrameworkMetadataProvider!
    var subject: FrameworkDependencyLoader!

    override func setUp() {
        frameworkMetadataProvider = MockFrameworkMetadataProvider()
        subject = FrameworkDependencyLoader(frameworkMetadataProvider: frameworkMetadataProvider)
        super.setUp()
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
        XCTAssertThrowsSpecific(try subject.load(path: frameworkPath), FrameworkDependencyLoaderError.frameworkNotFound(frameworkPath))
    }

    func test_oad_when_the_framework_exists() throws {
        // Given
        let path = try temporaryPath()
        let frameworkPath = path.appending(component: "tuist.framework")
        let dsymPath = path.appending(component: "tuist.dSYM")
        let bcsymbolmapPaths = [path.appending(component: "tuist.bcsymbolmap")]
        let architectures = [BinaryArchitecture.armv7s]
        let linking = BinaryLinking.dynamic
        let binaryPath = frameworkPath.appending(component: "tuist")

        try FileHandler.shared.touch(frameworkPath)

        frameworkMetadataProvider.dsymPathStub = { path in
            XCTAssertEqual(path, frameworkPath)
            return dsymPath
        }
        frameworkMetadataProvider.bcsymbolmapPathsStub = { path in
            XCTAssertEqual(path, frameworkPath)
            return bcsymbolmapPaths
        }
        frameworkMetadataProvider.linkingStub = { path in
            XCTAssertEqual(path, binaryPath)
            return linking
        }
        frameworkMetadataProvider.architecturesStub = { path in
            XCTAssertEqual(path, binaryPath)
            return architectures
        }

        // When
        let got = try subject.load(path: frameworkPath)

        // Then
        XCTAssertEqual(got, .framework(path: frameworkPath,
                                       binaryPath: frameworkPath.appending(component: "tuist"),
                                       dsymPath: dsymPath,
                                       bcsymbolmapPaths: bcsymbolmapPaths,
                                       linking: linking,
                                       architectures: architectures,
                                       isCarthage: false))
    }
}
