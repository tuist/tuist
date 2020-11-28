import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarthageCommandBuilderTests: TuistUnitTestCase {
    func test_build() throws {
        // Given
        let stubbedPath = try temporaryPath()

        // When/Then
        XCTAssertEqual(
            CarthageCommandBuilder(method: .fetch, path: stubbedPath)
                .build()
                .joined(separator: " "),

            "carthage bootstrap --project-directory \(stubbedPath.pathString)"
        )

        XCTAssertEqual(
            CarthageCommandBuilder(method: .fetch, path: stubbedPath)
                .throughBundler(true)
                .build()
                .joined(separator: " "),

            "bundle exec carthage bootstrap --project-directory \(stubbedPath.pathString)"
        )

        XCTAssertEqual(
            CarthageCommandBuilder(method: .update, path: stubbedPath)
                .build()
                .joined(separator: " "),

            "carthage update --project-directory \(stubbedPath.pathString)"
        )

        XCTAssertEqual(
            CarthageCommandBuilder(method: .update, path: stubbedPath)
                .throughBundler(true)
                .build()
                .joined(separator: " "),

            "bundle exec carthage update --project-directory \(stubbedPath.pathString)"
        )

        XCTAssertEqual(
            CarthageCommandBuilder(method: .update, path: stubbedPath)
                .throughBundler(true)
                .cacheBuilds(true)
                .newResolver(true)
                .build()
                .joined(separator: " "),

            "bundle exec carthage update --project-directory \(stubbedPath.pathString) --cache-builds --new-resolver"
        )

        XCTAssertEqual(
            CarthageCommandBuilder(method: .update, path: stubbedPath)
                .throughBundler(true)
                .cacheBuilds(true)
                .newResolver(true)
                .platforms([.iOS])
                .build()
                .joined(separator: " "),

            "bundle exec carthage update --project-directory \(stubbedPath.pathString) --platform iOS --cache-builds --new-resolver"
        )
    }
}
