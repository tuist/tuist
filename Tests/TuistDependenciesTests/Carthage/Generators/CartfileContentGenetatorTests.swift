import TuistCore
import TuistGraph
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
        let dependencies: [CarthageDependency] = []
        let expected = """
        """

        // When
        let got = subject.cartfileContent(for: dependencies)

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_build_single_dependency() throws {
        // Given
        let dependencies: [CarthageDependency] = [
            .init(origin: .github(path: "Dependency/Dependency"), requirement: .exact("1.1.1"), platforms: [.iOS]),
        ]
        let expected = """
        github "Dependency/Dependency" == 1.1.1
        """

        // When
        let got = subject.cartfileContent(for: dependencies)

        // Then
        XCTAssertEqual(got, expected)
    }

    func test_build_multiple_dependencies() throws {
        // Given
        let dependencies: [CarthageDependency] = [
            .init(origin: .github(path: "Dependency/Dependency"), requirement: .exact("2.1.1"), platforms: [.iOS]),
            .init(origin: .github(path: "XYZ/Foo"), requirement: .revision("revision"), platforms: [.tvOS, .macOS]),
            .init(origin: .git(path: "Foo/Bar"), requirement: .atLeast("1.0.1"), platforms: [.iOS]),
            .init(origin: .github(path: "Qwerty/bar"), requirement: .branch("develop"), platforms: [.watchOS]),
            .init(origin: .github(path: "XYZ/Bar"), requirement: .upToNext("1.1.1"), platforms: [.iOS]),
            .init(origin: .binary(path: "https://my.domain.com/release/MyFramework.json"), requirement: .upToNext("1.0.1"), platforms: [.iOS]),
            .init(origin: .binary(path: "file:///some/local/path/MyFramework.json"), requirement: .atLeast("1.1.0"), platforms: [.iOS]),
        ]
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
        let got = subject.cartfileContent(for: dependencies)

        // Then
        XCTAssertEqual(got, expected)
    }
}
