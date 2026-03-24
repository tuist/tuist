import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistSupport

@testable import TuistCacheEE
@testable import TuistTesting

struct BundleLoaderErrorTests {
    @Test
    func type_when_bundleNotFound() throws {
        // Given
        let path = try AbsolutePath(validating: "/bundles/tuist.bundle")
        let subject = BundleLoaderError.bundleNotFound(path)

        // When
        let got = subject.type

        // Then
        #expect(got == .abort)
    }

    @Test
    func description_when_bundleNotFound() throws {
        // Given
        let path = try AbsolutePath(validating: "/bundles/tuist.bundle")
        let subject = BundleLoaderError.bundleNotFound(path)

        // When
        let got = subject.description

        // Then
        #expect(got == "Couldn't find bundle at \(path.pathString)")
    }
}

struct BundleLoaderTests {
    private let subject: BundleLoader
    init() {
        subject = BundleLoader(
            fileSystem: fileSystem
        )
    }

    @Test(.inTemporaryDirectory)
    func load_when_the_framework_doesnt_exist() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = path.appending(component: "tuist.bundle")

        // Then
        await #expect(throws: BundleLoaderError.bundleNotFound(bundlePath)) { try await subject.load(path: bundlePath) }
    }

    @Test(.inTemporaryDirectory)
    func load_when_the_framework_exists() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = path.appending(component: "tuist.bundle")

        try FileHandler.shared.touch(bundlePath)

        // When
        let got = try await subject.load(path: bundlePath)

        // Then
        #expect(got == .bundle(path: bundlePath))
    }
}
