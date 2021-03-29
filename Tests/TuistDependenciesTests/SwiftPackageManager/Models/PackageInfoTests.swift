import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class PackageInfoTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = PackageInfo.test()
        
        // When / Then
        XCTAssertCodable(subject)
    }
    
    func test_schemeName() {
        // Given
        let subject = PackageInfo.test(name: "RxSwift")
        
        // When
        let got = subject.schemeName
        
        //Then
        let expected = "RxSwift-Package"
        XCTAssertEqual(got, expected)
    }
    
    func test_supportedPlatforms_allPlatforms() {
        // Given
        let subject = PackageInfo.test(platforms: [
            .init(platformName: "ios", version: "14.0"),
            .init(platformName: "macos", version: "11.0"),
            .init(platformName: "tvos", version: "14.0"),
            .init(platformName: "watchos", version: "7.0"),
        ])
        
        // When
        let got = subject.supportedPlatforms
        
        // Then
        let expected = Set<Platform>([.iOS, .macOS, .tvOS, .watchOS])
        XCTAssertEqual(got, expected)
    }
    
    func test_supportedPlatforms_iOS() {
        // Given
        let subject = PackageInfo.test(platforms: [
            .init(platformName: "ios", version: "10.0"),
        ])
        
        // When
        let got = subject.supportedPlatforms
        
        // Then
        let expected = Set<Platform>([.iOS])
        XCTAssertEqual(got, expected)
    }
}
