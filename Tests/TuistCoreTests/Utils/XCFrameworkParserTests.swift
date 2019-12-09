import Basic
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class XCFrameworkParserTests: TuistUnitTestCase {
    func test_parsing() {
        let cache = GraphLoaderCache()
        let frameworkPath = fixturePath(path: RelativePath("MyFramework.xcframework"))
        let xcFramework = try! XCFrameworkParser.parse(path: frameworkPath, cache: cache)

        let architectures = xcFramework.libraries.flatMap { $0.architectures }
        XCTAssertEqual([.x8664, .arm64], architectures)

        XCTAssertEqual(xcFramework.binaryPath, frameworkPath.appending(RelativePath("ios-x86_64-simulator/MyFramework.framework/MyFramework")))
    }
}
