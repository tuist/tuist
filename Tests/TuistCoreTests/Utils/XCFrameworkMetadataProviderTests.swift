import Basic
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class XCFrameworkMetadataProviderTests: XCTestCase {

    var subject: XCFrameworkMetadataProvider!
    var frameworkPath: AbsolutePath!

    override func setUp() {
        super.setUp()
        subject = XCFrameworkMetadataProvider()
        frameworkPath = fixturePath(path: RelativePath("MyFramework.xcframework"))
    }

    override func tearDown() {
        frameworkPath = nil
        subject = nil
        super.tearDown()
    }
    
    func test_libraries() {
        let libraries = try! subject.libraries(frameworkPath: frameworkPath)
        XCTAssertEqual(libraries.first!.identifier, "ios-x86_64-simulator")
        XCTAssertEqual(libraries.last!.identifier, "ios-arm64")
        XCTAssertEqual(libraries.first!.path, RelativePath("MyFramework.framework"))
        
        let architectures = libraries.flatMap { $0.architectures }
        XCTAssertEqual([.x8664, .arm64], architectures)
    }

    func test_binaryPath() {
        let libraries = try! subject.libraries(frameworkPath: frameworkPath)
        let binaryPath = try! subject.binaryPath(frameworkPath: frameworkPath, libraries: libraries)
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(RelativePath("ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        )
    }
}
