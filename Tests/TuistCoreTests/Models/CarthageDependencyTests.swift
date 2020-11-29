import Foundation
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class CarthageDependencyTests: TuistTestCase {
    func test_cartfileValue_exact() throws {
        // Given
        let dependency = CarthageDependency(name: "Alamofire/Alamofire", requirement: .exact("1.2.3"), platforms: [.iOS])
        let expected = #"github "Alamofire/Alamofire" == 1.2.3"#

        // When
        let got = try dependency.cartfileValue()

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_cartfileValue_upToNextMajor() throws {
        // Given
        let dependency = CarthageDependency(name: "RxSwift/RxSwift", requirement: .upToNextMajor("3.0.1"), platforms: [.macOS])
        let expected = #"github "RxSwift/RxSwift" ~> 3.0.1"#

        // When
        let got = try dependency.cartfileValue()

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_cartfileValue_range() throws {
        // Given
        let dependency = CarthageDependency(name: "RxSwift/RxSwift", requirement: .range(from: "1.0.0", to: "2.0.0"), platforms: [.iOS])
        let expectedError = CarthageDependencyError.rangeRequirementNotSupported(dependencyName: "RxSwift/RxSwift", fromVersion: "1.0.0", toVersion: "2.0.0")

        // When / Then
        XCTAssertThrowsSpecific(try dependency.cartfileValue(), expectedError)
    }
}
