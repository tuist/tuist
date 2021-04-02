import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class PackageDependencyTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = PackageDependency.test()

        // When
        XCTAssertCodable(subject)
    }

    func test_uniqueDependencies() {
        // Given
        let subject1 = PackageDependency(
            name: "name1",
            url: "url1",
            version: "1.0.0",
            path: "path1",
            dependencies: []
        )
        let subject2 = PackageDependency(
            name: "name2",
            url: "url2",
            version: "2.0.0",
            path: "path2",
            dependencies: [subject1]
        )
        let subject3 = PackageDependency(
            name: "name3",
            url: "url3",
            version: "3.0.0",
            path: "path3",
            dependencies: [subject1, subject2]
        )
        let subject4 = PackageDependency(
            name: "name4",
            url: "url4",
            version: "4.0.0",
            path: "path4",
            dependencies: [subject2]
        )

        // subject5
        //     |- subject3
        //     |    |- subject1
        //     |    |- subject2
        //     |    |    |- subject1
        //     |- subject4
        //     |    |- subject2
        //     |    |    |- subject1
        let subject5 = PackageDependency(
            name: "name5",
            url: "url5",
            version: "5.0.0",
            path: "path5",
            dependencies: [
                subject4,
                subject3,
            ]
        )

        // When
        let got = subject5.uniqueDependencies()

        // Then
        let expected = Set([subject1, subject2, subject3, subject4, subject5])
        XCTAssertEqual(got, expected)
    }

    func test_absolutePath() {
        // Given
        let path = "/path/to/dependency"
        let subject = PackageDependency.test(path: path)

        // When
        let got = subject.absolutePath

        // Then
        let expected = AbsolutePath(path)
        XCTAssertEqual(got, expected)
    }
}
