import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageVersionFileTests: TuistUnitTestCase {
    func test_codable_alamofire() {
        // Given
        let json = CarthageVersionFile.testAlamofireJson
        let expected = CarthageVersionFile.testAlamofire

        // When / Then
        XCTAssertDecodableEqualToJson(json, expected)
    }

    func test_codable_rxSwift() {
        // Given
        let json = CarthageVersionFile.testRxSwiftJson
        let expected = CarthageVersionFile.testRxSwift

        // When / Then
        XCTAssertDecodableEqualToJson(json, expected)
    }

    func test_codable_realmSwift() {
        // Given
        let json = CarthageVersionFile.testRealmCocoaJson
        let expected = CarthageVersionFile.testRealmCocoa

        // When / Then
        XCTAssertDecodableEqualToJson(json, expected)
    }

    func test_codable_ahoyRTC() {
        // Given
        let json = CarthageVersionFile.testAhoyRTCJson
        let expected = CarthageVersionFile.testAhoyRTC

        // When / Then
        XCTAssertDecodableEqualToJson(json, expected)
    }

    func test_allProducts() {
        // Given
        let iOSProduct = CarthageVersionFile.Product.test(name: "iOS")
        let macOSProduct = CarthageVersionFile.Product.test(name: "macOS")
        let watchOSProduct = CarthageVersionFile.Product.test(name: "watchOS")
        let tvOSProduct = CarthageVersionFile.Product.test(name: "tvOS")

        let subject = CarthageVersionFile.test(
            iOS: [iOSProduct],
            macOS: [macOSProduct],
            watchOS: [watchOSProduct],
            tvOS: [tvOSProduct]
        )

        // When
        let got = subject.allProducts

        // Then
        let expected: [CarthageVersionFile.Product] = [iOSProduct, macOSProduct, watchOSProduct, tvOSProduct]
        XCTAssertEqual(got, expected)
    }
}
