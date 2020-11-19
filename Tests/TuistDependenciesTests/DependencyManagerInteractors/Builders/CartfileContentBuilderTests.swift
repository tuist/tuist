import XCTest
import TuistCore
import TuistSupport

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CarfileContentBuilderTests: TuistUnitTestCase {
    func test_build_no_dependenies() throws {
        // Given
        let subbedDependencies: [CarthageDependency] = []
        
        // When
        let cartfileContent = try CartfileContentBuilder(dependencies: subbedDependencies)
            .build()
        
        // Then
        let expectedCartfileContent = ""
        XCTAssertEqual(cartfileContent, expectedCartfileContent)
    }
    
    func test_build_single_dependency() throws {
        // Given
        let subbedDependencies: [CarthageDependency] = [
            .init(name: "Dependency/Dependency", requirement: .exact("1.1.1"), platforms: [.iOS])
        ]
        
        // When
        let cartfileContent = try CartfileContentBuilder(dependencies: subbedDependencies)
            .build()
        
        // Then
        let expectedCartfileContent = """
        github "Dependency/Dependency" == 1.1.1
        """
        XCTAssertEqual(cartfileContent, expectedCartfileContent)
    }
    
    func test_build_multiple_dependenies() throws {
        // Given
        let subbedDependencies: [CarthageDependency] = [
            .init(name: "Dependency/Dependency", requirement: .exact("2.1.1"), platforms: [.iOS]),
            .init(name: "XYZ/Foo", requirement: .revision("revision"), platforms: [.tvOS, .macOS]),
            .init(name: "Qwerty/bar", requirement: .branch("develop"), platforms: [.watchOS]),
            .init(name: "XYZ/Bar", requirement: .upToNextMajor("1.1.1"), platforms: [.iOS]),
        ]
        
        // When
        let cartfileContent = try CartfileContentBuilder(dependencies: subbedDependencies)
            .build()
        
        // Then
        let expectedCartfileContent = """
        github "Dependency/Dependency" == 2.1.1
        github "XYZ/Foo" "revision"
        github "Qwerty/bar" "develop"
        github "XYZ/Bar" ~> 1.1.1
        """
        XCTAssertEqual(cartfileContent, expectedCartfileContent)
    }
}
