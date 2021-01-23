import Foundation
import XCTest
@testable import TuistGraph
@testable import TuistSupportTesting

final class CarthageDependencyTests: TuistUnitTestCase {
    func test_cartfileValue_github_exact() throws {
        // Given
        let dependency = CarthageDependency(origin: .github(path: "Alamofire/Alamofire"), requirement: .exact("1.2.3"), platforms: [.iOS])
        let expected = #"github "Alamofire/Alamofire" == 1.2.3"#

        // When
        let got = dependency.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    // MARK: - CarthageDependency.Origin tests

    func test_origin_cartfileValue_github() {
        // Given
        let origin: CarthageDependency.Origin = .github(path: "Alamofire/Alamofire")
        let expected = #"github "Alamofire/Alamofire""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_origin_cartfileValue_git() {
        // Given
        let origin: CarthageDependency.Origin = .git(path: "https://enterprise.local/desktop/git-error-translations2.git")
        let expected = #"git "https://enterprise.local/desktop/git-error-translations2.git""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_origin_cartfileValue_binary() {
        // Given
        let origin: CarthageDependency.Origin = .binary(path: "file:///some/local/path/MyFramework.json")
        let expected = #"binary "file:///some/local/path/MyFramework.json""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    // MARK: - CarthageDependency.Requirement tests

    func test_requirement_cartfileValue_exact() {
        // Given
        let origin: CarthageDependency.Requirement = .exact("1.2.3")
        let expected = #"== 1.2.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_upToNext() {
        // Given
        let origin: CarthageDependency.Requirement = .upToNext("3.2.3")
        let expected = #"~> 3.2.3"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_atLeast() {
        // Given
        let origin: CarthageDependency.Requirement = .atLeast("1.2.1")
        let expected = #">= 1.2.1"#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_branch() {
        // Given
        let origin: CarthageDependency.Requirement = .branch("develop")
        let expected = #""develop""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_requirement_cartfileValue_revision() {
        // Given
        let origin: CarthageDependency.Requirement = .revision("1234567898765432qwerty")
        let expected = #""1234567898765432qwerty""#

        // When
        let got = origin.cartfileValue

        // Then
        XCTAssertEqual(got, expected)
    }
}
