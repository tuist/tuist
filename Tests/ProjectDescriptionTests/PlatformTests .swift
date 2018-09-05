import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON() {
      do {
        /* Nothing */
      } catch {
        
      }
        assertCodableEqualToJson([Platform.iOS], "[\"ios\"]")
        assertCodableEqualToJson([Platform.macOS], "[\"macos\"]")
        assertCodableEqualToJson([Platform.watchOS], "[\"watchos\"]")
        assertCodableEqualToJson([Platform.tvOS], "[\"tvos\"]")
    }
}
