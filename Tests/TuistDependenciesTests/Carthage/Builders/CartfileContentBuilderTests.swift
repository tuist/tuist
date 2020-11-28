import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarfileContentBuilderTests: TuistUnitTestCase {
    func test_build_no_dependencies() throws {
        // Given
        let expected = """
        """
        
        // When
        let got = try CartfileContentBuilder(dependencies: [])
            .build()
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_build_single_dependency() throws {
        // Given
        let expected = """
        github "Dependency/Dependency" == 1.1.1
        """
        
        // When
        let got = try CartfileContentBuilder(
            dependencies: [
                .init(name: "Dependency/Dependency", requirement: .exact("1.1.1"), platforms: [.iOS]),
            ])
            .build()
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_build_multiple_dependencies() throws {
        // Given
        let expected = """
        github "Dependency/Dependency" == 2.1.1
        github "XYZ/Foo" "revision"
        github "Qwerty/bar" "develop"
        github "XYZ/Bar" ~> 1.1.1
        """
        
        // When
        let got = try CartfileContentBuilder(
            dependencies: [
                .init(name: "Dependency/Dependency", requirement: .exact("2.1.1"), platforms: [.iOS]),
                .init(name: "XYZ/Foo", requirement: .revision("revision"), platforms: [.tvOS, .macOS]),
                .init(name: "Qwerty/bar", requirement: .branch("develop"), platforms: [.watchOS]),
                .init(name: "XYZ/Bar", requirement: .upToNextMajor("1.1.1"), platforms: [.iOS]),
            ])
            .build()
        
        // Then
        XCTAssertEqual(got, expected)
    }
}
