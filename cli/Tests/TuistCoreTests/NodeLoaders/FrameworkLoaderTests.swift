import FileSystemTesting
import Path
import TuistSupport
import XcodeGraph
import Testing
@testable import TuistCore
@testable import TuistTesting

struct FrameworkLoaderErrorTests {
    @Test func test_type_when_frameworkNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/frameworks/tuist.framework")
        let subject = FrameworkLoaderError.frameworkNotFound(path)

        // When
        let got = subject.type

        // Then
        #expect(got == .abort)
    }

    @Test func test_description_when_frameworkNotFound() {
        // Given
        let path = try! AbsolutePath(validating: "/frameworks/tuist.framework")
        let subject = FrameworkLoaderError.frameworkNotFound(path)

        // When
        let got = subject.description

        // Then
        #expect(got == "Couldn't find framework at \(path.pathString)")
    }
}

struct FrameworkLoaderTests {
    let frameworkMetadataProvider: MockFrameworkMetadataProvider
    let subject: FrameworkLoader

    init() {
        frameworkMetadataProvider = MockFrameworkMetadataProvider()
        subject = FrameworkLoader(frameworkMetadataProvider: frameworkMetadataProvider)
    }

    @Test(.inTemporaryDirectory) func test_load_when_the_framework_doesnt_exist() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let frameworkPath = path.appending(component: "tuist.framework")

        // Then
        await #expect(throws: FrameworkLoaderError.frameworkNotFound(frameworkPath)) {
            try await subject.load(path: frameworkPath, status: .required)
        }
    }

    @Test(.inTemporaryDirectory) func test_load_when_the_framework_exists() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
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
                status: .required
            )
        }

        // When
        let got = try await subject.load(path: frameworkPath, status: .required)

        // Then
        #expect(
            got ==
            .framework(
                path: frameworkPath,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                status: .required
            )
        )
    }
}
