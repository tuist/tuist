import Basic
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class XCFrameworkInfoPlistTests: TuistUnitTestCase {
    
    func test_decode() {
        let infoPlistPath = fixturePath(path: RelativePath("MyFramework.xcframework/Info.plist"))
        let xcFrameworkInfoPlist: XCFrameworkInfoPlist = try! FileHandler.shared.readPlistFile(infoPlistPath)
        XCTAssertNotNil(xcFrameworkInfoPlist)
    }
}
