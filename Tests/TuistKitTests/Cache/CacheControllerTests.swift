import Foundation
import TuistCacheTesting
import TuistCore
import TuistCoreTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class CacheControllerTests: XCTestCase {
    var generator: MockGenerator!
    var xcframeworkBuilder: MockXCFrameworkBuilder!
    var cache: MockCacheStorage!
}
