import Foundation
import XCTest
import Framework

@testable import App

final class AppTests: XCTestCase {

    func test_integration() {
        print(PublicFrameworkClass().text)
    }
    
}
