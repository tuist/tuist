import Foundation
import TSCBasic
import TuistCacheTesting
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CacheProfileResolverTests: TuistUnitTestCase {
    private typealias CacheProfile = TuistGraph.Cache.Profile

    var subject: CacheProfileResolver!

    override func setUp() {
        super.setUp()
        subject = CacheProfileResolver()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_resolves_default_profile_from_tuist_defaults() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: nil)
        )

        // Then
        XCTAssertEqual(
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            ),
            resolvedProfile
        )
    }

    func test_resolves_default_profile_from_tuist_defaults_when_profiles_list_is_empty() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: .test(profiles: []))
        )

        // Then
        XCTAssertEqual(
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            ),
            resolvedProfile
        )
    }

    func test_resolves_default_profile_from_config() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: Cache(profiles: [.init(name: "foo", configuration: "configuration")]))
        )

        // Then
        XCTAssertEqual(
            CacheProfile(
                name: "foo",
                configuration: "configuration"
            ),
            resolvedProfile
        )
    }

    func test_resolves_selected_profile_from_config() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "bar",
            from: .test(
                cache: Cache(
                    profiles: [
                        .init(name: "foo", configuration: "debug"),
                        .init(name: "bar", configuration: "release"),
                    ]
                )
            )
        )

        // Then
        XCTAssertEqual(
            CacheProfile(
                name: "bar",
                configuration: "release"
            ),
            resolvedProfile
        )
    }

    func test_resolves_not_found_profile() throws {
        // Then
        XCTAssertThrowsSpecific(
            try subject.resolveCacheProfile(
                named: "foo",
                from: .test(cache: Cache(profiles: [.init(name: "bar", configuration: "debug")]))
            ),
            CacheProfileResolver.Error.missingProfile(name: "foo", availableProfiles: ["bar"])
        )
    }
}
