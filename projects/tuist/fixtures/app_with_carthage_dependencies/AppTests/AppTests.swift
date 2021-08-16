import Foundation
import Nimble
import XCTest

@testable import App

// Use Quick&Nimble to make sure they link fine
class DependenciesTests: XCTestCase {
    func test_nimble() {
        // Use Nimble to make sure it links fine
        expect("value").to(equal("value"))
    }
}
