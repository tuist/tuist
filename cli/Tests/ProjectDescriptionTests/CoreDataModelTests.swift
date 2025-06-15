import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class CoreDataModelTests: XCTestCase {
    func test_toJSON() {
        let subject: CoreDataModel = .coreDataModel("path", currentVersion: "current")
        XCTAssertCodable(subject)
    }
}
