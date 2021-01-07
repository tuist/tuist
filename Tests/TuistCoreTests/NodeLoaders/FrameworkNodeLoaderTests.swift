import TSCBasic
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class FrameworkNodeLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_frameworkNotFound() {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let subject = FrameworkNodeLoaderError.frameworkNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_frameworkNotFound() {
        // Given
        let path = AbsolutePath("/frameworks/tuist.framework")
        let subject = FrameworkNodeLoaderError.frameworkNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Couldn't find framework at \(path.pathString)")
    }
}

final class FrameworkNodeLoaderTests: TuistUnitTestCase {
    var frameworkMetadataProvider: MockFrameworkMetadataProvider!
    var otoolController: MockOtoolController!

    var subject: FrameworkNodeLoader!

    override func setUp() {
        frameworkMetadataProvider = MockFrameworkMetadataProvider()
        otoolController = MockOtoolController()
        subject = FrameworkNodeLoader(frameworkMetadataProvider: frameworkMetadataProvider)
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
        XCTAssertThrowsSpecific(try subject.load(path: frameworkPath), FrameworkNodeLoaderError.frameworkNotFound(frameworkPath))
    }

    func test_load_unexistent_dependency_throws() throws {
        let path = try temporaryPath()

        let (
            frameworkPath,
            _,
            _,
            _,
            _
        ) = try prepareValidFrameworkLoad(atPath: path)

        let invalidPath = path.appending(RelativePath("Unexistent.framework/Unexistent"))
        var isFirstRecursiveCall = false
//        otoolController.dlybDependenciesPathStub = { _ in
//            guard !isFirstRecursiveCall else { return .just([]) }
//            isFirstRecursiveCall = true
//            return .just([
//                invalidPath,
//            ])
//        }

        XCTAssertThrowsSpecific(
            try subject.load(path: frameworkPath),
            FrameworkNodeLoaderError.invalidDependencyPath(invalidPath.removingLastComponent())
        )
    }

    func test_load_when_the_framework_exists() throws {
        let path = try temporaryPath()

        let (
            frameworkPath,
            dsymPath,
            bcsymbolmapPaths,
            linking,
            architectures
        ) = try prepareValidFrameworkLoad(atPath: path)

        // When
        let got = try subject.load(path: frameworkPath)

        // Then
        XCTAssertEqual(got, FrameworkNode(path: frameworkPath,
                                          dsymPath: dsymPath,
                                          bcsymbolmapPaths: bcsymbolmapPaths,
                                          linking: linking,
                                          architectures: architectures,
                                          dependencies: []))
    }

    private func prepareValidFrameworkLoad(atPath path: AbsolutePath) throws -> (
        frameworkPath: AbsolutePath,
        dsymPath: AbsolutePath,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture]
    ) {
        // Given
        let frameworkPath = path.appending(component: "tuist.framework")
        let dsymPath = path.appending(component: "tuist.dSYM")
        let bcsymbolmapPaths = [path.appending(component: "tuist.bcsymbolmap")]
        let architectures = [BinaryArchitecture.armv7s]
        let linking = BinaryLinking.dynamic

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
            XCTAssertEqual(path, FrameworkNode.binaryPath(frameworkPath: frameworkPath))
            return linking
        }
        frameworkMetadataProvider.architecturesStub = { path in
            XCTAssertEqual(path, FrameworkNode.binaryPath(frameworkPath: frameworkPath))
            return architectures
        }

        return (frameworkPath, dsymPath, bcsymbolmapPaths, linking, architectures)
    }
}
