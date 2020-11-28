import TuistCore
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class CartfileContentGenetatorTests: TuistUnitTestCase {
    private var subject: CartfileContentGenerator!
    
    override func setUp() {
        super.setUp()
        subject = CartfileContentGenerator()
    }
    
    override func tearDown() {
        subject = nil
        super.tearDown()
    }
    
    func test_build_no_dependencies() throws {
        // Given
        let expected = """
        """
        
        // When
        let got = try subject.cartfileContent(for: [])
        
        // Then
        XCTAssertEqual(got, expected)
    }
    
    func test_build_single_dependency() throws {
        // Given
        let expected = """
        github "Dependency/Dependency" == 1.1.1
        """
        
        // When
        let got = try subject.cartfileContent(for: [
            .init(name: "Dependency/Dependency", requirement: .exact("1.1.1"), platforms: [.iOS]),
        ])
        
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
        let got = try subject.cartfileContent(for: [
            .init(name: "Dependency/Dependency", requirement: .exact("2.1.1"), platforms: [.iOS]),
            .init(name: "XYZ/Foo", requirement: .revision("revision"), platforms: [.tvOS, .macOS]),
            .init(name: "Qwerty/bar", requirement: .branch("develop"), platforms: [.watchOS]),
            .init(name: "XYZ/Bar", requirement: .upToNextMajor("1.1.1"), platforms: [.iOS]),
        ])
        
        // Then
        XCTAssertEqual(got, expected)
    }
}
