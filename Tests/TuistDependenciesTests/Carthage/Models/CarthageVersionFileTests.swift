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
    
    func test_product_architectures_arm64_x8664() {
        // Given
        let subject: CarthageVersionFile.Product = .test(
            identifier: "macos-arm64_x86_64"
        )
        
        // When
        let got = subject.architectures
        
        // Then
        let expected: [BinaryArchitecture] = [.arm64, .x8664]
        XCTAssertEqual(got, expected)
    }
    
    func test_product_architectures_arm64_i386_x8664() {
        // Given
        let subject: CarthageVersionFile.Product = .test(
            identifier: "ios-arm64_i386_x86_64-simulator"
        )
        
        // When
        let got = subject.architectures
        
        // Then
        let expected: [BinaryArchitecture] = [.arm64, .i386, .x8664]
        XCTAssertEqual(got, expected)
    }
    
    func test_product_architectures_arm6432_armv7k() {
        // Given
        let subject: CarthageVersionFile.Product = .test(
            identifier: "watchos-arm64_32_armv7k"
        )
        
        // When
        let got = subject.architectures
        
        // Then
        let expected: [BinaryArchitecture] = [.arm6432, .armv7k]
        XCTAssertEqual(got, expected)
    }
}
