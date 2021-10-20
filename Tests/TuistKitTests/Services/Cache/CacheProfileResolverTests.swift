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
            resolvedProfile,
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            )
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
            resolvedProfile,
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            )
        )
    }

    func test_resolves_default_profile_from_config() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: nil,
            from: .test(cache: Cache(profiles: [.init(name: "foo", configuration: "configuration")], path: nil))
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "foo",
                configuration: "configuration"
            )
        )
    }

    func test_resolves_selected_profile_from_config() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "bar",
            from: .test(
                cache: Cache(
                    profiles: [
                        .init(name: "foo", configuration: "debug", device: "iPhone 12", os: "15.0.0"),
                        .init(name: "bar", configuration: "release", device: "iPhone 12", os: "15.0.0"),
                    ], path: nil
                )
            )
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "bar",
                configuration: "release",
                device: "iPhone 12",
                os: "15.0.0"
            )
        )
    }

    func test_resolves_selected_release_profile_from_tuist_defaults_when_cache_config_is_nil() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "Release",
            from: .test(cache: nil)
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "Release",
                configuration: "Release"
            )
        )
    }

    func test_resolves_selected_release_profile_from_tuist_defaults_when_profiles_list_is_empty() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "Release",
            from: .test(cache: .test(profiles: []))
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "Release",
                configuration: "Release"
            )
        )
    }

    func test_resolves_selected_development_profile_from_tuist_defaults_when_cache_config_is_nil() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "Development",
            from: .test(cache: nil)
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            )
        )
    }

    func test_resolves_selected_development_profile_from_tuist_defaults_when_profiles_list_is_empty() throws {
        // When
        let resolvedProfile = try subject.resolveCacheProfile(
            named: "Development",
            from: .test(cache: .test(profiles: []))
        )

        // Then
        XCTAssertEqual(
            resolvedProfile,
            CacheProfile(
                name: "Development",
                configuration: "Debug"
            )
        )
    }

    func test_resolves_not_found_profile() throws {
        // Then
        XCTAssertThrowsSpecific(
            try subject.resolveCacheProfile(
                named: "foo",
                from: .test(cache: Cache(profiles: [.init(name: "bar", configuration: "debug")], path: nil))
            ),
            CacheProfileResolverError.missingProfile(name: "foo", availableProfiles: ["bar"])
        )
    }
}
