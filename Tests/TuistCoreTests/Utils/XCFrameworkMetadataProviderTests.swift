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
    
    func test_libraries() throws {
        let libraries = try subject.libraries(frameworkPath: frameworkPath)

        // Then
        XCTAssertEqual(libraries, [
            .init(identifier: "ios-x86_64-simulator",
                  path: RelativePath("MyFramework.framework"),
                  architectures: [.x8664]),
            .init(identifier: "ios-arm64",
                  path: RelativePath("MyFramework.framework"),
                  architectures: [.arm64]),
        ])
    }

    func test_binaryPath() throws {
        let libraries = try subject.libraries(frameworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(frameworkPath: frameworkPath, libraries: libraries)
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(RelativePath("ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        )
    }
}
