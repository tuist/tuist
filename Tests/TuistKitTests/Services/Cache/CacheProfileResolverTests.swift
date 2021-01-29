import Foundation
import TSCBasic
import TuistCacheTesting
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CacheProfileResolverTests: TuistUnitTestCase {
    private typealias ResolvedCacheProfile = CacheProfileResolver.ResolvedCacheProfile

    var subject: CacheProfileResolver!

    override func setUp() {
        super.setUp()
        subject = CacheProfileResolver()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_resolves_default_profile_from_tuist_defaults() {
        // When
        let resolvedProfile = subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: nil)
        )

        // Then
        XCTAssertEqual(
            ResolvedCacheProfile.defaultFromTuist(
                .init(
                    name: "development",
                    configuration: "Debug"
                )
            ),
            resolvedProfile
        )
    }

    func test_resolves_default_profile_from_tuist_defaults_when_profiles_list_is_empty() {
        // When
        let resolvedProfile = subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: .test(profiles: []))
        )

        // Then
        XCTAssertEqual(
            ResolvedCacheProfile.defaultFromTuist(
                .init(
                    name: "development",
                    configuration: "Debug"
                )
            ),
            resolvedProfile
        )
    }

    func test_resolves_default_profile_from_config() {
        // When
        let resolvedProfile = subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: Cache(profiles: [.init(name: "foo", configuration: "configuration")]))
        )

        // Then
        XCTAssertEqual(
            ResolvedCacheProfile.defaultFromConfig(
                .init(
                    name: "foo",
                    configuration: "configuration"
                )
            ),
            resolvedProfile
        )
    }

    func test_resolves_selected_profile_from_config() {
        // When
        let resolvedProfile = subject.resolveCacheProfile(
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
            ResolvedCacheProfile.selectedFromConfig(
                .init(
                    name: "bar",
                    configuration: "release"
                )
            ),
            resolvedProfile
        )
    }

    func test_resolves_not_found_profile() {
        // When
        let resolvedProfile = subject.resolveCacheProfile(
            named: "foo",
            from: .test(cache: Cache(profiles: [.init(name: "bar", configuration: "debug")]))
        )

        // Then
        XCTAssertEqual(
            ResolvedCacheProfile.notFound(
                profileName: "foo",
                availableProfiles: ["bar"]
            ),
            resolvedProfile
        )
    }
}
