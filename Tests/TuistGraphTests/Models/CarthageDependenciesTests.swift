import Foundation
import XCTest
@testable import TuistGraph
@testable import TuistSupportTesting

final class CarthageDependenciesTests: TuistUnitTestCase {
    func test_cartfileValue_singleDependency() {
        // Given
        let carthageDependencies: CarthageDependencies = .init(
            dependencies: [
                .github(path: "Dependency/Dependency", requirement: .exact("1.1.1")),
            ],
            options: .init(platforms: [.iOS], useXCFrameworks: false)
        )
        let expected = """
        github "Dependency/Dependency" == 1.1.1
        """

        // When
        let got = carthageDependencies.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_cartfileValue_multipleDependencies() {
        // Given
        let carthageDependencies: CarthageDependencies = .init(
            dependencies: [
                .github(path: "Dependency/Dependency", requirement: .exact("2.1.1")),
                .github(path: "XYZ/Foo", requirement: .revision("revision")),
                .git(path: "Foo/Bar", requirement: .atLeast("1.0.1")),
                .github(path: "Qwerty/bar", requirement: .branch("develop")),
                .github(path: "XYZ/Bar", requirement: .upToNext("1.1.1")),
                .binary(path: "https://my.domain.com/release/MyFramework.json", requirement: .upToNext("1.0.1")),
                .binary(path: "file:///some/local/path/MyFramework.json", requirement: .atLeast("1.1.0")),
            ],
            options: .init(platforms: [.iOS], useXCFrameworks: false)
        )
        let expected = """
        github "Dependency/Dependency" == 2.1.1
        github "XYZ/Foo" "revision"
        git "Foo/Bar" >= 1.0.1
        github "Qwerty/bar" "develop"
        github "XYZ/Bar" ~> 1.1.1
        binary "https://my.domain.com/release/MyFramework.json" ~> 1.0.1
        binary "file:///some/local/path/MyFramework.json" >= 1.1.0
        """

        // When
        let got = carthageDependencies.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    // MARK: - CarthageDependency.Dependency tests

    func test_dependency_cartfileValue_github() {
        // Given
        let origin: CarthageDependencies.Dependency = .github(path: "Alamofire/Alamofire", requirement: .exact("1.2.3"))
        let expected = #"github "Alamofire/Alamofire" == 1.2.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_dependency_cartfileValue_git() {
        // Given
        let origin: CarthageDependencies.Dependency = .git(path: "https://enterprise.local/desktop/git-error-translations2.git", requirement: .atLeast("5.4.3"))
        let expected = #"git "https://enterprise.local/desktop/git-error-translations2.git" >= 5.4.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_dependency_cartfileValue_binary() {
        // Given
        let origin: CarthageDependencies.Dependency = .binary(path: "file:///some/local/path/MyFramework.json", requirement: .upToNext("5.0.0"))
        let expected = #"binary "file:///some/local/path/MyFramework.json" ~> 5.0.0"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    // MARK: - CarthageDependencies.Requirement tests

    func test_requirement_cartfileValue_exact() {
        // Given
        let origin: CarthageDependencies.Requirement = .exact("1.2.3")
        let expected = #"== 1.2.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_upToNext() {
        // Given
        let origin: CarthageDependencies.Requirement = .upToNext("3.2.3")
        let expected = #"~> 3.2.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_atLeast() {
        // Given
        let origin: CarthageDependencies.Requirement = .atLeast("1.2.1")
        let expected = #">= 1.2.1"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_branch() {
        // Given
        let origin: CarthageDependencies.Requirement = .branch("develop")
        let expected = #""develop""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_revision() {
        // Given
        let origin: CarthageDependencies.Requirement = .revision("1234567898765432qwerty")
        let expected = #""1234567898765432qwerty""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }
}
