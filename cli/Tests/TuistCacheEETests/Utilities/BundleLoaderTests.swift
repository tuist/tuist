import Path
import TuistSupport
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class BundleLoaderErrorTests: TuistUnitTestCase {
    func test_type_when_bundleNotFound() throws {
        // Given
        let path = try AbsolutePath(validating: "/bundles/tuist.bundle")
        let subject = BundleLoaderError.bundleNotFound(path)

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }

    func test_description_when_bundleNotFound() throws {
        // Given
        let path = try AbsolutePath(validating: "/bundles/tuist.bundle")
        let subject = BundleLoaderError.bundleNotFound(path)

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "Couldn't find bundle at \(path.pathString)")
    }
}

final class BundleLoaderTests: TuistUnitTestCase {
    private var subject: BundleLoader!

    override func setUp() {
        super.setUp()
        subject = BundleLoader(
            fileSystem: fileSystem
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_load_when_the_framework_doesnt_exist() async throws {
        // Given
        let path = try temporaryPath()
        let bundlePath = path.appending(component: "tuist.bundle")

        // Then
        await XCTAssertThrowsSpecific(
            try await subject.load(path: bundlePath),
            BundleLoaderError.bundleNotFound(bundlePath)
        )
    }

    func test_load_when_the_framework_exists() async throws {
        // Given
        let path = try temporaryPath()
        let bundlePath = path.appending(component: "tuist.bundle")

        try FileHandler.shared.touch(bundlePath)

        // When
        let got = try await subject.load(path: bundlePath)

        // Then
        XCTAssertEqual(
            got,
            .bundle(path: bundlePath)
        )
    }
}
