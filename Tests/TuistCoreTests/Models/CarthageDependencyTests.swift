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
        let got = dependency.cartfileValue()

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_cartfileValue_upToNextMajor() throws {
        // Given
        let dependency = CarthageDependency(name: "RxSwift/RxSwift", requirement: .upToNextMajor("3.0.1"), platforms: [.macOS])
        let expected = #"github "RxSwift/RxSwift" ~> 3.0.1"#

        // When
        let got = dependency.cartfileValue()

        // Then
        XCTAssertEqual(got, expected)
    }
}
